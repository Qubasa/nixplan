"""Delivering one planned entry to the machine the plan placed it on, and
booting the machines a delivery needs.

The plan is the only thing this module reads to decide where a delivery goes: an
entry's key names its machine, and the machine's record carries the address. A
caller that asks for a machine the plan did not place the entry on is refused
rather than dialled, because the alternative is a delivery that succeeds against
the wrong host.

Nothing here imports rookery. The two handles it needs - a namespace that can run
a command where the cluster's addresses exist, and a control channel into one
guest - are declared as protocols, so the pure half type-checks and runs in a
build sandbox that has no VM. `booted` takes rookery's ``qemu`` module as an
argument for the same reason: every end-to-end folder boots the same guest the
same way, and stating that once here keeps the import at the caller.
"""

from __future__ import annotations

import contextlib
import json
import os
import shlex
import subprocess
import tempfile
from collections.abc import Iterator
from pathlib import Path
from typing import Any, Protocol

MACHINE_PREFIX = "machine:"
LOCKED_URL_PREFIX = "plan:"


class DeliveryError(RuntimeError):
    """A delivery the plan does not support, refused before anything is dialled."""


class Namespace(Protocol):
    """The half of rookery's ``Cluster`` a delivery uses: run a command on the LAN."""

    def run(self, cmd: list[str], *, env: dict[str, str] | None = None) -> object:
        """Run ``cmd`` where the cluster's addresses resolve."""
        ...


class Control(Protocol):
    """The half of rookery's ``Vm`` an activation uses: a command channel into a guest."""

    def ssh_succeed(self, command: str, *, timeout: float = ...) -> str:
        """Run ``command`` in the guest, assert it exits 0, return its stdout."""
        ...


def machine_of(key: str) -> str | None:
    """Return the machine an entry key is placed on, or ``None`` for an unplaced one.

    Args:
        key: A plan entry key, ``<instance>:<service>@<machine>`` when placed.

    Returns:
        The machine name, or ``None`` when the key carries no machine.
    """
    machine = key.partition("@")[2]
    if not machine:
        return None
    return machine


def machines_placed(plan: dict[str, Any], entry: str) -> list[str]:
    """Return the machines ``entry`` is placed on, sorted.

    Args:
        plan: The plan artifact, as read from its JSON.
        entry: An entry without its machine, ``<instance>:<service>``.

    Returns:
        Every machine name the plan carries a placed key of ``entry`` for.
    """
    prefix = f"{entry}@"
    return sorted(key[len(prefix) :] for key in plan if key.startswith(prefix))


def placed_key(plan: dict[str, Any], entry: str, machine: str) -> str:
    """Return the plan key of ``entry`` on ``machine``, or refuse.

    Args:
        plan: The plan artifact, as read from its JSON.
        entry: An entry without its machine, ``<instance>:<service>``.
        machine: The machine the caller wants to deliver to.

    Returns:
        The key of that entry on that machine.

    Raises:
        DeliveryError: If the plan placed ``entry`` on other machines, naming the
            entry, the machine asked for and the machines it was placed on.
    """
    key = f"{entry}@{machine}"
    if key in plan:
        return key
    placed = machines_placed(plan, entry)
    raise DeliveryError(
        f"the plan does not place {entry} on {machine}: "
        f"it is placed on {', '.join(placed) if placed else 'no machine'}"
    )


def address_of(plan: dict[str, Any], key: str) -> str:
    """Return the address of the machine ``key`` is placed on.

    The address is read from the machine's own record rather than from the
    entry's target, so a delivery dials what the registry declared.

    Args:
        plan: The plan artifact, as read from its JSON.
        key: A placed entry key.

    Returns:
        The machine's address.

    Raises:
        DeliveryError: If the key carries no machine, the plan has no record for
            it, or that record declares no address.
    """
    machine = machine_of(key)
    if machine is None:
        raise DeliveryError(f"{key} is placed on no machine, so it has no address")
    record = plan.get(f"{MACHINE_PREFIX}{machine}")
    if record is None:
        raise DeliveryError(f"the plan carries no {MACHINE_PREFIX}{machine} record for {key}")
    address = record.get("address")
    if not isinstance(address, str) or not address:
        raise DeliveryError(f"machine {machine} declares no address, so {key} cannot be delivered")
    return address


def locked_url(key: str) -> str:
    """Return the identity the endpoint reports for a planned entry's artifact."""
    return f"{LOCKED_URL_PREFIX}{key}"


def service_name(artifact: str | Path) -> str:
    """Return the service name an artifact declares in its ``meta.json``.

    Args:
        artifact: A built flakelet artifact directory.

    Returns:
        The name the endpoint registers the entry under.
    """
    meta = json.loads((Path(artifact) / "meta.json").read_text())
    name = meta["name"]
    if not isinstance(name, str):
        raise DeliveryError(f"{artifact}/meta.json declares no service name")
    return name


def copy_argv(artifact: str | Path, address: str, *, user: str = "root") -> list[str]:
    """Return the store-to-store copy an operator runs, as argv.

    Args:
        artifact: The store path to deliver.
        address: The address of the receiving machine.
        user: The login user on the receiving machine.

    Returns:
        The ``nix copy`` argv. ``--no-check-sigs`` is required because the
        artifact was built locally and signed by nobody.
    """
    return [
        "nix",
        "copy",
        "--to",
        f"ssh://{user}@{address}",
        "--no-check-sigs",
        str(artifact),
    ]


def ssh_opts(ssh_key: str | Path) -> str:
    """Return the ``NIX_SSHOPTS`` a delivery to a throwaway guest needs.

    ``-F /dev/null`` is load-bearing rather than tidy. The copy runs inside the
    cluster's single-uid user namespace, where a host config file owned by real
    root appears owned by ``nobody``, and ssh then refuses to read it at all:
    ``Bad owner or permissions on /nix/store/...-libvirt/etc/ssh/ssh_config.d/
    30-libvirt-ssh-proxy.conf`` followed by a failed connection. rookery's own
    control channel carries the same flag for the same reason
    (``rookery/qemu/access.py:52-56``).

    The guest is generated per run, so there is no host key to have accepted
    beforehand and no known-hosts file, global or per-user, to write one to.
    """
    return " ".join(
        [
            "-F",
            "/dev/null",
            "-i",
            str(ssh_key),
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "GlobalKnownHostsFile=/dev/null",
            "-o",
            "BatchMode=yes",
        ]
    )


def delivery_env(base_env: dict[str, str], ssh_key: str | Path) -> dict[str, str]:
    """Return the environment a delivery runs under.

    ``Cluster.run`` replaces the environment rather than extending it, so the
    caller's own environment is carried through here: ``nix copy`` needs its
    ``PATH``, its ``HOME`` and its daemon socket.
    """
    env = dict(base_env)
    env["NIX_SSHOPTS"] = ssh_opts(ssh_key)
    return env


def deliver(
    namespace: Namespace,
    *,
    plan: dict[str, Any],
    key: str,
    artifact: str | Path,
    ssh_key: str | Path,
    base_env: dict[str, str],
    user: str = "root",
) -> str:
    """Copy one entry's artifact to the machine the plan placed it on.

    Args:
        namespace: A handle that runs a command where the cluster's addresses
            resolve (rookery's ``Cluster``).
        plan: The plan artifact, as read from its JSON.
        key: The placed entry key to deliver.
        artifact: The built artifact for that entry.
        ssh_key: The private key the receiving machine authorises.
        base_env: The environment to run under, before ``NIX_SSHOPTS``.
        user: The login user on the receiving machine.

    Returns:
        The address that was dialled, so a caller can assert it was the plan's.
    """
    address = address_of(plan, key)
    namespace.run(
        copy_argv(artifact, address, user=user),
        env=delivery_env(base_env, ssh_key),
    )
    return address


def activate(control: Control, name: str, artifact: str | Path, *, timeout: float = 120.0) -> str:
    """Activate a delivered artifact through the endpoint on the machine itself.

    The endpoint reports what it did on stderr - ``using prebuilt artifact``,
    ``resolving``, ``activating generation``
    (`flakelet-core/src/manager.rs:1026,1050,1174`) - while the control channel
    hands back stdout, so the two streams are merged here: what the machine says
    about the activation is the evidence that it used a prebuilt artifact and
    resolved nothing.

    Args:
        control: A command channel into the receiving guest.
        name: The service name the artifact declares.
        artifact: The delivered store path.
        timeout: Seconds to allow the activation.

    Returns:
        The endpoint's own report of the activation.
    """
    command = f"flakelet activate {shlex.quote(name)} {shlex.quote(str(artifact))} 2>&1"
    return control.ssh_succeed(command, timeout=timeout)


def rollback(control: Control, name: str, *, timeout: float = 120.0) -> str:
    """Roll the entry back to its previous generation and return the endpoint's report."""
    return control.ssh_succeed(f"flakelet rollback {shlex.quote(name)} 2>&1", timeout=timeout)


def status(control: Control, name: str, *, timeout: float = 60.0) -> dict[str, Any]:
    """Return what the endpoint reports about one registered entry.

    Raises:
        DeliveryError: If the endpoint reports no entry under ``name``.
    """
    out = control.ssh_succeed(f"flakelet status --json {shlex.quote(name)}", timeout=timeout)
    entries = json.loads(out)
    if not entries:
        raise DeliveryError(f"the endpoint reports no entry named {name}")
    first = entries[0]
    if not isinstance(first, dict):
        raise DeliveryError(f"the endpoint reported {first!r} for {name}, which is not an entry")
    return first


def keypair(root: Path) -> Path:
    """Generate the run's own key pair under ``root`` and return the private key.

    The guest image carries no credential, so every run makes its own and hands
    the public half to the machines over the reserved ``rookery`` share.

    Args:
        root: A directory this run owns; ``root/share`` becomes the share.

    Returns:
        The private key path.
    """
    key = root / "id_ed25519"
    subprocess.run(
        ["ssh-keygen", "-t", "ed25519", "-N", "", "-C", "planner-e2e", "-f", str(key)],
        check=True,
        capture_output=True,
    )
    share = root / "share"
    share.mkdir(exist_ok=True)
    (share / "authorized_keys").write_text((root / "id_ed25519.pub").read_text())
    return key


def state_root() -> Path:
    """Return the run's state directory: the runner's, or a short one of our own.

    A virtiofs socket path has 107 usable bytes and the one rookery opens is
    ``<state>/rookery/rookery-<pid>-<id>/vm-<i>/virtiofs-<tag>.sock``: a state
    root under pytest's own ``tmp_path_factory`` is already one byte over, and
    virtiofsd then exits during startup with nothing but the socket path to say
    why. The runner hands one in; the fallback keeps a direct ``pytest`` run
    working.
    """
    named = os.environ.get("PLANNER_E2E_STATE")
    if named:
        return Path(named)
    return Path(tempfile.mkdtemp(prefix="pe-"))


@contextlib.contextmanager
def booted(
    qemu: Any,
    *,
    image: Path,
    names: tuple[str, ...],
    keydir: Path,
    memory_mib: int = 2048,
    cpus: int = 2,
) -> Iterator[Any]:
    """Boot one guest per name, wait for each to be usable, and yield the cluster.

    Args:
        qemu: rookery's ``qemu`` module, imported by the caller.
        image: The guest image every machine boots.
        names: The machine names, as the plan names them.
        keydir: The directory ``keypair`` was called with.
        memory_mib: Memory per machine.
        cpus: Virtual CPUs per machine.

    Yields:
        rookery's live ``Cluster``, ready and networked.
    """
    share = qemu.VirtioFsShare(tag="rookery", host_path=keydir / "share", read_only=True)
    specs = [
        qemu.VmSpec(
            image=image,
            name=name,
            ssh_key=keydir / "id_ed25519",
            secure_boot=False,
            shares=(share,),
        )
        for name in names
    ]
    with qemu.cluster(specs, memory_mib=memory_mib, cpus=cpus, state_root=state_root()) as live:
        for name in names:
            live.vm(name).wait_for_share("rookery", timeout=180)
        live.wait_ready()
        live.wait_for_network()
        yield live
