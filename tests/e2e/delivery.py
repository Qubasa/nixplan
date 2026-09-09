"""Delivering one planned entry to the machine the plan placed it on, and
obtaining the machines a delivery needs.

The plan is the only thing this module reads to decide where a delivery goes: an
entry's key names its machine, and the machine's record carries the address. A
caller that asks for a machine the plan did not place the entry on is refused
rather than dialled, because the alternative is a delivery that succeeds against
the wrong host.

Nothing here imports rookery. The two handles it needs - a namespace that can run
a command where the cluster's addresses exist, and a control channel into one
guest - are declared as protocols, so the pure half type-checks and runs in a
build sandbox that has no VM. `cluster_stage` takes rookery's ``snapshot`` module
as an argument for the same reason: every end-to-end folder obtains the same
guests the same way, and stating that once here keeps the import at the caller.
"""

from __future__ import annotations

import base64
import functools
import json
import os
import shlex
import shutil
import tempfile
from collections.abc import Callable, Iterator
from pathlib import Path, PurePosixPath
from typing import Any, Protocol

MACHINE_PREFIX = "machine:"
# The prefix flakelet reports a planned entry's identity under. Must stay equal to
# the one written in flakelet/read.nix.
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
    machine = key.rpartition("@")[2]
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


def machine_address(plan: dict[str, Any], machine: str, *, of: str) -> str:
    """Return the address the registry declared for one machine.

    Args:
        plan: The plan artifact, as read from its JSON.
        machine: The machine name.
        of: What is being delivered, for the refusal to name.

    Returns:
        The machine's address.

    Raises:
        DeliveryError: If the plan has no record for that machine, or the record
            declares no address.
    """
    record = plan.get(f"{MACHINE_PREFIX}{machine}")
    if record is None:
        raise DeliveryError(f"the plan carries no {MACHINE_PREFIX}{machine} record for {of}")
    address = record.get("address")
    if not isinstance(address, str) or not address:
        raise DeliveryError(f"machine {machine} declares no address, so {of} cannot be delivered")
    return address


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
    return machine_address(plan, machine, of=key)


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


VARS_MARKER = ":vars/"


def vars_entries(plan: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Return the plan's generated-value entries, keyed as the plan keys them.

    A value's entry is `<instance>:vars/<generator>` when one value exists for
    the instance and `<instance>:vars/<generator>@<machine>` when one exists per
    placement, so a caller can tell the two apart without asking the plan.

    Args:
        plan: The plan artifact, as read from its JSON.

    Returns:
        The vars entries of the plan, by key.
    """
    return {key: entry for key, entry in plan.items() if VARS_MARKER in key}


def install_argv(
    address: str,
    path: str,
    content: str,
    *,
    ssh_key: str | Path,
    user: str = "root",
) -> list[str]:
    """Return the write of one generated file onto one machine, as argv.

    Not `nix copy`: a store object is readable by every process on the machine,
    and the whole point of a delivered secret is that its bytes are not in the
    store. The bytes travel base64-encoded because the namespace runs an argv
    rather than a shell, and land at mode 0400 under a directory the delivery
    creates.

    Args:
        address: The address of the receiving machine.
        path: The absolute path the plan records for the file.
        content: The bytes to write.
        ssh_key: The private key the receiving machine authorises.
        user: The login user on the receiving machine.

    Returns:
        The `ssh` argv that writes the file.
    """
    encoded = base64.b64encode(content.encode()).decode()
    remote = (
        f"set -eu; umask 077; mkdir -p {shlex.quote(str(PurePosixPath(path).parent))}; "
        f"printf %s {shlex.quote(encoded)} | base64 -d > {shlex.quote(path)}; "
        f"chmod 0400 {shlex.quote(path)}"
    )
    return ["ssh", *shlex.split(ssh_opts(ssh_key)), f"{user}@{address}", remote]


def deliver_value(
    namespace: Namespace,
    *,
    plan: dict[str, Any],
    key: str,
    files: dict[str, str],
    ssh_key: str | Path,
    base_env: dict[str, str],
    user: str = "root",
) -> list[str]:
    """Deliver one generated value to the machines its entry names, and no others.

    The entry's `delivery` list is the only thing consulted: a value nobody
    receives is delivered nowhere, and a machine the list does not name is not
    dialled even when it runs a service of the same instance.

    Args:
        namespace: A handle that runs a command where the cluster's addresses
            resolve (rookery's ``Cluster``).
        plan: The plan artifact, as read from its JSON.
        key: The vars entry key of the value.
        files: The bytes of each declared file, by file name.
        ssh_key: The private key the receiving machines authorise.
        base_env: The environment to run under, before ``NIX_SSHOPTS``.
        user: The login user on the receiving machines.

    Returns:
        The addresses that were dialled, in delivery-set order.

    Raises:
        DeliveryError: If the plan has no such entry, if the entry declares a file
            the caller gave no bytes for, or if a machine in the set has no
            address.
    """
    entry = plan.get(key)
    if entry is None:
        raise DeliveryError(f"the plan carries no entry {key}")
    declared = entry.get("files", {})
    missing = sorted(set(declared) - set(files))
    if missing:
        raise DeliveryError(f"{key} declares {', '.join(missing)} and no bytes were given for them")

    env = delivery_env(base_env, ssh_key)
    dialled: list[str] = []
    for machine in entry.get("delivery", []):
        address = machine_address(plan, machine, of=key)
        for name, record in sorted(declared.items()):
            namespace.run(
                install_argv(
                    address,
                    record["path"],
                    files[name],
                    ssh_key=ssh_key,
                    user=user,
                ),
                env=env,
            )
        dialled.append(address)
    return dialled


def ssh_key(root: Path, source: Path) -> Path:
    """Copy the image's private key under ``root`` at mode 0600 and return it.

    The credential belongs to the image, not to the run: a resumed snapshot
    authorizes whatever its cut froze, so the key both ends use has to be static
    (`design.md D3`). It arrives as a store file, and a store file is mode 0444 -
    which ssh refuses to read a private key from - so the copy is what a run
    actually connects with.

    Args:
        root: A directory this run owns.
        source: The store path of the key the guest image authorizes.

    Returns:
        The private key path, readable by this user alone.
    """
    key = root / "id_ed25519"
    shutil.copyfile(source, key)
    key.chmod(0o600)
    return key


@functools.cache
def state_root() -> Path:
    """Return the run's state directory: the runner's, or a short one of our own.

    A run-dir socket path has 107 usable bytes and the ones rookery opens are
    under ``<state>/rookery/rookery-<pid>-<id>/vm-<i>/``: a state root under
    pytest's own ``tmp_path_factory`` is already over the limit, and the daemon
    that fails then exits during startup with nothing but the socket path to say
    why. The runner hands one in; the fallback keeps a direct ``pytest`` run
    working, and is memoized so one process has one such directory.
    """
    named = os.environ.get("PLANNER_E2E_STATE")
    if named:
        return Path(named)
    return Path(tempfile.mkdtemp(prefix="pe-"))


Preparation = Callable[[Any], Iterator[Any]]


def cluster_stage(
    snapshot: Any,
    *,
    image: Path,
    names: tuple[str, ...],
    key: Path,
    memory_mib: int = 2048,
    cpus: int = 2,
) -> Callable[[Preparation], Any]:
    """Return the decorator that declares a folder's machines as a snapshot stage.

    Every end-to-end folder obtains its machines this way, so the posture is
    stated once. ``@cluster_snapshot_fixture`` rather than ``@snapshot_fixture``
    because a single-VM cut can only ever resume as slot 0, and a wired pair
    needs two machines with a route between them; the whole-cluster decorator
    boots every slot in one namespace and cuts them together.

    ``uefi`` is on because the guest boots systemd-boot from a GPT ESP and the
    decorator's own default is BIOS; Secure Boot is off because the image is
    unsigned; the TPM is off because nothing in the guest measures anything. All
    three are part of the cut's key, so a later change of posture is a miss.

    No ``extra_env``, ``extra_files`` or ``extra_tools`` are declared, because the
    preparation reads no variable and runs no program of its own: it waits for
    readiness over rookery's channels and yields. That is also why an artifact's
    path never enters the key, so editing a folder's deployment does not
    invalidate the boot.

    Args:
        snapshot: rookery's ``snapshot`` module, imported by the caller.
        image: The guest image every machine boots.
        names: The machine names, in slot order, as the plan names them.
        key: The private key the image authorizes.
        memory_mib: Memory per machine; part of the key.
        cpus: Virtual CPUs per machine; part of the key.

    Returns:
        The decorator to apply to the folder's preparation generator.
    """
    decorator: Callable[[Preparation], Any] = snapshot.cluster_snapshot_fixture(
        image=image,
        vms=names,
        ssh_key=key,
        memory_mib=memory_mib,
        cpus=cpus,
        uefi=True,
        secure_boot=False,
        tpm=False,
        scope="session",
    )
    return decorator


def await_ready(cluster: Any, *, timeout: float = 180.0) -> None:
    """Wait until every machine of ``cluster`` is usable, not merely reachable.

    ``wait_for_ssh`` attests the socket-activated vsock sshd, which answers
    before the system reaches ``multi-user.target`` and populates the login
    ``PATH``. A cut taken there would freeze a half-booted guest, and the first
    test to resume it would run its commands before coreutils resolved, so each
    machine is waited to its default target before the cut is taken.

    Args:
        cluster: rookery's live ``Cluster``.
        timeout: Seconds to allow each wait.
    """
    for vm in cluster.vms:
        vm.wait_for_ssh(timeout=timeout)
        vm.wait_for_unit("multi-user.target", timeout=timeout)
    cluster.wait_ready()
    cluster.wait_for_network()


def cut_is_cached(stage: Any, *, lineage: Any, cache: Any, slots: int) -> bool:
    """Whether the cut ``stage`` publishes is in the cache under its own key.

    The stage's lineage node is the handle rookery itself reads off a fixture to
    chain a child onto a parent (``_rookery_cluster_snapshot_node``,
    ``rookery/snapshot/cluster_lineage.py:160-166``), and the key is derived from
    it the same way the resume path derives it. A caller uses this to say which of
    the two things happened: the machines were resumed, or they were prepared and
    the cut is now there for the next run.

    Args:
        stage: The fixture a ``cluster_stage`` decorator produced.
        lineage: rookery's ``snapshot.lineage`` module.
        cache: rookery's ``snapshot.cache`` module.
        slots: The number of machines in the cut.

    Returns:
        Whether a usable group entry exists for the stage's key.
    """
    node = stage._rookery_cluster_snapshot_node
    keys = lineage.compute_cluster_keys(lineage.chain_to_root(node))
    return cache.lookup_group(keys[node.name], slots) is not None
