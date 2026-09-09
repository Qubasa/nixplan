"""Reading a plan the way the operator's command reads it, and obtaining the
machines an end-to-end folder needs.

What a delivery does is the command's: copying an artifact, writing a generated
value, activating an entry, asking a machine what it holds and rolling one entry
back are steps of `cli/`, and a folder's test runs that command rather than
assembling the same steps beside it. What is left here is what only a test needs.

The plan readers stay because the assertions read the plan too, and a test that
reads a plan the way the tool does is a test that can disagree with the tool.

The rest is rookery glue and imports none of rookery. `cluster_stage` takes
rookery's ``snapshot`` module as an argument, so every folder obtains the same
guests the same way while the import stays at the caller, and this file still
type-checks and runs in a build sandbox that has no VM.
"""

from __future__ import annotations

import functools
import json
import os
import shutil
import tempfile
from collections.abc import Callable, Iterator
from pathlib import Path
from typing import Any

MACHINE_PREFIX = "machine:"
# The prefix flakelet reports a planned entry's identity under. Must stay equal to
# the one written in flakelet/read.nix.
LOCKED_URL_PREFIX = "plan:"


class DeliveryError(RuntimeError):
    """A delivery the plan does not support, refused before anything is dialled."""


def machine_of(key: str) -> str | None:
    """Return the machine a plan key is placed on, or ``None`` for an unplaced one."""
    return key.rpartition("@")[2] or None


def machines_placed(plan: dict[str, Any], entry: str) -> list[str]:
    """Return the machines ``<instance>:<service>`` is placed on, sorted."""
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
    """Return the name the endpoint registers, as the artifact's ``meta.json`` declares it."""
    meta = json.loads((Path(artifact) / "meta.json").read_text())
    name = meta["name"]
    if not isinstance(name, str):
        raise DeliveryError(f"{artifact}/meta.json declares no service name")
    return name


VARS_MARKER = ":vars/"


def vars_entries(plan: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Return the plan's generated-value entries, keyed as the plan keys them.

    A value's entry is `<instance>:vars/<generator>` when one value exists for
    the instance and `<instance>:vars/<generator>@<machine>` when one exists per
    placement, so a caller can tell the two apart without asking the plan.
    """
    return {key: entry for key, entry in plan.items() if VARS_MARKER in key}


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


def guest_ssh_options(key: Path) -> str:
    """Return the ``NIX_SSHOPTS`` a throwaway rookery guest has to be reached with.

    These options are properties of the guest, never of an operator, which is
    why the command extends this rather than deciding it. ``-F /dev/null`` is
    load-bearing: the command runs inside the cluster's single-uid user
    namespace, where a host config file owned by real root appears owned by
    ``nobody``, and ssh then refuses to read it at all - ``Bad owner or
    permissions on /nix/store/...-libvirt/etc/ssh/ssh_config.d/
    30-libvirt-ssh-proxy.conf`` followed by a failed connection. rookery's own
    control channel carries the same flag for the same reason
    (``rookery/qemu/access.py:52-56``). The guest is generated per run, so there
    is no host key to have accepted beforehand and no known-hosts file, global or
    per-user, to write one to.

    Args:
        key: The private key this run connects with.

    Returns:
        The options, as one ``NIX_SSHOPTS`` string.
    """
    return " ".join(
        [
            "-F",
            "/dev/null",
            "-i",
            str(key),
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


def command_env(base_env: dict[str, str], key: Path) -> dict[str, str]:
    """Return the environment the operator's command runs under in a cluster.

    ``Cluster.run`` replaces the environment rather than extending it, so the
    caller's own is carried through here: the command shells out to ``nix copy``,
    which needs its ``PATH``, its ``HOME`` and its daemon socket.
    """
    env = dict(base_env)
    env["NIX_SSHOPTS"] = guest_ssh_options(key)
    return env


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
