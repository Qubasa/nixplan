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

import contextlib
import dataclasses
import functools
import json
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import time
from collections.abc import Callable, Iterator, Sequence
from pathlib import Path
from typing import Any

import runner

MACHINE_PREFIX = "machine:"
MANIFEST = "manifest.json"
REALISERS = "realisers"
HOLDINGS = "holdings"
URL_PREFIX = "urlPrefix"

STATUS_FILE = "flakelet-core/src/manager.rs"
STATUS_STRUCT = "ServiceStatus"
STATUS_FIELD = re.compile(r"^\s*pub (\w+):", re.MULTILINE)
DECISION = "openspec/changes/answer-whether-a-machine-is-current/design.md"

# The sealing tool, named the way a run names it: the command's own wrapper
# exports the program off the module's own attribute, so what a run seals with
# is the build's answer and never the caller's `PATH`, and the guard below
# resolves the wrapper rather than looking a program name up.
SEALING = "PLANNER_AGE"
SEALING_TARGET = "planner"
SEALING_EXPORT = re.compile(rf"^export {SEALING}=(\S+)$", re.MULTILINE)
KEYGEN = "age-keygen"
# A native recipient is `age1` and 58 characters of the bech32 alphabet. This
# reads one off what the tool printed and states no rule: the grammar has one
# home, in the library, and a second copy of it here would be a second answer.
RECIPIENT_LINE = re.compile(r"age1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{58}")
SEALED_TEXT = b"planner sealed this string and opened it again"
SEALING_DECISION = "openspec/changes/unseal-a-value-after-a-reboot/design.md"
# The mesh client, named the way the sealing tool is: the variable carries the
# store path the build pinned, so the daemon a run joins with is the build's
# answer and never the caller's `PATH`.
TAILSCALE = "PLANNER_TAILSCALE"
DAEMON = "tailscaled"
CLIENT = "tailscale"
# The daemon's socket answers a little after the process starts - about three
# seconds when the state directory is new - so readiness is polled rather than
# slept through, and `up` is bounded because it blocks printing a registration
# URL where the credential is spent or empty, which is a refusal to report.
MESH_READY = 30.0
MESH_POLL = 0.25
MESH_STEP = 5.0
MESH_JOIN = 60.0
MESH_STOP = 10.0
# Seconds a dial through the mesh may say nothing before it is a failed dial
# rather than a wait. `mesh_ssh_options` states what it is measured against.
MESH_DIAL = 20
# A cluster's own namespaces, entered by the file rookery publishes its anchor
# in and the two namespaces its own entry joins. Read at every call and never
# cached: a restarted stage has another anchor, and a stale pid names either
# nothing or somebody else's namespaces.
ANCHOR_PID = "anchor.pid"
NAMESPACES = ("--user", "--net")
# What `flakelet status --json` answers with at the locked revision. No field of
# it is the identity the endpoint stores for the artifact, which is why the
# report compares a flakelet entry by the unit files instead.
ENDPOINT_REPORTS = (
    "name",
    "flake",
    "origin",
    "generation",
    "units",
    "locked_url",
    "pin",
    "override_flake",
    "degraded",
    "held",
    "disabled",
    "last_error",
    "updating",
    "failed_units",
    "unit_states",
    "missing_providers",
    "state",
    "export_blockers",
    "changed",
)


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


def record_of(root: Path) -> dict[str, Any]:
    """Return the deployment record one built directory publishes.

    Raises:
        DeliveryError: If the directory carries none.
    """
    record = root / MANIFEST
    if not record.is_file():
        raise DeliveryError(f"{root} carries no {MANIFEST}, so it is not a built deployment")
    stated: dict[str, Any] = json.loads(record.read_text())
    return stated


def published(record: dict[str, Any], realiser: str, field: str) -> Any:
    """Return one field of what a record publishes about one realiser's holdings.

    Raises:
        DeliveryError: If the record publishes no such field, naming the
            realiser and what it does publish.
    """
    holdings = record.get(REALISERS, {}).get(realiser, {}).get(HOLDINGS, {})
    if field not in holdings:
        raise DeliveryError(
            f"the deployment record publishes no {field} for {realiser}, and this reads what a "
            f"machine's own answer names a holding by out of the record: it publishes "
            f"{sorted(holdings) or 'nothing'}"
        )
    return holdings[field]


def locked_url(record: dict[str, Any], key: str) -> str:
    """Return the identity the endpoint reports for a planned entry's artifact.

    The prefix is the one the record publishes as what a machine's own answer
    names a flakelet holding by, so nothing here keeps a second copy of the
    literal `flakelet/read.nix` writes.
    """
    return f"{published(record, 'flakelet', URL_PREFIX)}{key}"


def pinned_endpoint() -> str | None:
    """Return the flakelet reference this repository's lock pins, or ``None``.

    Read from the lock rather than written out, so that bumping the input is
    what re-runs the comparison below: a recorded revision beside the lock's own
    would keep answering for the revision nobody runs any more.
    """
    lock = Path(__file__).resolve().parents[2] / "flake.lock"
    try:
        locked = json.loads(lock.read_text())["nodes"]["flakelet"]["locked"]
    except (OSError, KeyError, json.JSONDecodeError):
        return None
    owner, repo, rev = locked.get("owner"), locked.get("repo"), locked.get("rev")
    if not (owner and repo and rev):
        return None
    return f"github:{owner}/{repo}/{rev}"


def endpoint_source(reference: str | None = None) -> Path | None:
    """Return the source of the pinned endpoint, or ``None`` where it is unresolvable.

    Args:
        reference: The flake reference to fetch. Defaults to the locked one.

    Returns:
        The store path the reference resolves to. A build sandbox reaches no
        network and a checkout may hold no lock, and neither is evidence about
        what the endpoint reports, so both answer ``None`` and the caller skips.
    """
    resolved = reference or pinned_endpoint()
    if resolved is None:
        return None
    argv = ["nix", "flake", "prefetch", "--json", resolved]
    try:
        fetched = subprocess.run(argv, capture_output=True, text=True, check=False)
    except OSError:
        return None
    if fetched.returncode != 0:
        return None
    try:
        return Path(json.loads(fetched.stdout)["storePath"])
    except (KeyError, ValueError):
        return None


def endpoint_reports(source: Path) -> tuple[str, ...] | None:
    """Return the fields the endpoint's status answer carries, or ``None``.

    Args:
        source: The endpoint's own source.

    Returns:
        The field names of the struct `flakelet status --json` serialises, in
        the order the source declares them, or ``None`` where that struct is
        not there to read: a source this cannot parse says nothing about what
        the tool answers.
    """
    try:
        text = (source / STATUS_FILE).read_text()
    except OSError:
        return None
    body = text.partition(f"pub struct {STATUS_STRUCT} {{")[2].partition("\n}")[0]
    return tuple(found.group(1) for found in STATUS_FIELD.finditer(body)) or None


def endpoint_refusal(source: Path | None) -> str | None:
    """Return the banner naming a moved status answer, or ``None``.

    The report compares a flakelet entry by the unit files the endpoint reports
    because that answer carries no identity of the artifact. That is a fact
    about one revision of somebody else's tool, so it is compared rather than
    trusted, and an answer that gained the identity makes the weaker comparison
    obsolete rather than wrong.

    Args:
        source: The endpoint's source, or ``None`` where it was unresolvable.

    Returns:
        The refusal to print and fail on, or ``None``. An unreadable signal is
        not evidence the answer moved, so both an unresolved source and an
        unparseable one answer ``None``.
    """
    if source is None:
        return None
    found = endpoint_reports(source)
    if found is None or found == ENDPOINT_REPORTS:
        return None
    gained = sorted(set(found) - set(ENDPOINT_REPORTS))
    lost = sorted(set(ENDPOINT_REPORTS) - set(found))
    return runner.banner(
        "THE FLAKELET STATUS ANSWER HAS MOVED",
        [
            f"gained: {', '.join(gained) or 'nothing'}",
            f"lost: {', '.join(lost) or 'nothing'}",
            f"resolved: {pinned_endpoint()}",
            "",
            f"{STATUS_STRUCT} in {STATUS_FILE} is what `flakelet status --json` prints.",
            "The report compares a flakelet entry by the unit files that answer",
            "carries, because it carries no identity of the artifact:",
            f"{DECISION}.",
            "",
            "If the answer now names the identity, compare that instead and rewrite",
            "that decision, cli/report.py's `_running` and this recorded field set.",
        ],
    )


def sealing_reference() -> str:
    """Return the flake attribute the sealing program is read out of.

    The wrapper and not a program name, because the wrapper is what a run reads
    it from: a tool found on this process's own `PATH` would answer for a run
    nobody makes.
    """
    return f"{Path(__file__).resolve().parents[2]}#{SEALING_TARGET}"


def sealing_tool(reference: str | None = None) -> Path | None:
    """Return the program the command's own wrapper seals with, or ``None``.

    Args:
        reference: The flake attribute of that wrapper. Defaults to the
            attribute of the checkout this file is in.

    Returns:
        The path the wrapper exports as `PLANNER_AGE`. A build sandbox builds
        nothing and a store copy of this file sits in no checkout, and neither
        is evidence about what the tool does, so both answer ``None`` and the
        caller skips.
    """
    argv = ["nix", "build", "--no-link", "--print-out-paths", reference or sealing_reference()]
    try:
        built = subprocess.run(argv, capture_output=True, text=True, check=False)
    except OSError:
        return None
    paths = built.stdout.split()
    if built.returncode != 0 or not paths:
        return None
    try:
        wrapper = (Path(paths[-1]) / "bin" / SEALING_TARGET).read_text()
    except OSError:
        return None
    named = SEALING_EXPORT.search(wrapper)
    return None if named is None else Path(named.group(1))


def sealing_skip(reference: str | None = None) -> str:
    """Return the reason a round trip could not be attempted, naming the reference.

    An unreadable signal is not evidence that the behaviour still holds, so the
    caller skips with this rather than passing.
    """
    return (
        f"{reference or sealing_reference()} resolves to no wrapper naming {SEALING}, "
        f"so nothing about sealing was asserted"
    )


def sealing_refusal(tool: Path, root: Path) -> str | None:
    """Return the banner naming a sealing tool that no longer round-trips, or ``None``.

    The whole mechanism is one behaviour of one tool: it mints an identity whose
    printed public line is a native recipient, seals to that line, and opens the
    result with the identity file. That is asserted as the round trip rather
    than assumed, and no version string is compared, because a bump that changes
    nothing would fail a suite for nothing.

    Args:
        tool: The sealing program, as `sealing_tool` resolved it.
        root: A directory this call may mint a throwaway pair in.

    Returns:
        The refusal to print and fail on, or ``None`` where the round trip
        still holds.
    """
    keygen = tool.parent / KEYGEN
    identity = root / "identity.txt"
    if not keygen.is_file():
        return _sealing_banner(tool, None, f"{keygen} is not there to mint an identity with")
    minted = subprocess.run([str(keygen), "-o", str(identity)], capture_output=True, check=False)
    printed = RECIPIENT_LINE.search((minted.stdout + minted.stderr).decode(errors="replace"))
    if minted.returncode != 0 or printed is None:
        return _sealing_banner(tool, None, f"{keygen} printed no native recipient")
    recipient = printed.group(0)
    sealed = subprocess.run(
        [str(tool), "--encrypt", "--recipient", recipient],
        input=SEALED_TEXT,
        capture_output=True,
        check=False,
    )
    if sealed.returncode != 0 or not sealed.stdout:
        return _sealing_banner(tool, recipient, "it sealed nothing to that recipient")
    opened = subprocess.run(
        [str(tool), "--decrypt", "--identity", str(identity)],
        input=sealed.stdout,
        capture_output=True,
        check=False,
    )
    if opened.stdout != SEALED_TEXT:
        return _sealing_banner(tool, recipient, "what it opened is not what it sealed")
    return None


def _sealing_banner(tool: Path, recipient: str | None, broke: str) -> str:
    """Return the banner for one way the round trip stopped working."""
    return runner.banner(
        "THE SEALING TOOL NO LONGER ROUND-TRIPS A NATIVE RECIPIENT",
        [
            f"resolved: {tool}",
            f"minted: {recipient or 'nothing this could read as a recipient'}",
            f"what broke: {broke}",
            "",
            "A delivery seals every value to the public line the machine's own",
            "registry record declares, and the machine opens its copies with the",
            "identity file it was provisioned with and nothing else. That is the",
            f"mechanism {SEALING_DECISION} records as D1.",
            "",
            "No version is compared here, so this is the behaviour itself moving:",
            "rewrite that decision, the recipient's grammar in lib/util.nix and",
            "this round trip together.",
        ],
    )


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


@dataclasses.dataclass(frozen=True)
class MeshMembership:
    """One host-side mesh node, and the ssh options a run reaches the mesh with."""

    name: str
    socket: Path
    ssh_options: str


def _mesh_programs() -> tuple[Path, Path]:
    """Return the pinned daemon and client, or refuse naming the variable.

    Raises:
        DeliveryError: If the variable is unset, naming it: a run that joined no
            mesh has no route to a machine declared by its mesh name, and a
            client found on this process's own ``PATH`` would answer for a build
            nobody made.
    """
    named = os.environ.get(TAILSCALE)
    if not named:
        raise DeliveryError(
            f"{TAILSCALE} is unset, and it names the mesh client a run joins with: "
            f'run this through .#planner-e2e, or `eval "$(planner-e2e-env)"` in a checkout'
        )
    root = Path(named)
    return root / "bin" / DAEMON, root / "bin" / CLIENT


def mesh_ssh_options(key: Path, client: Path, socket: Path) -> str:
    """Return the ``NIX_SSHOPTS`` a mesh name is dialled with.

    The guest's own options still apply - the machine on the other side is the
    same throwaway guest, reached over another transport - so this extends
    `guest_ssh_options` and replaces nothing.

    The first added option is a ``ProxyCommand``, and it is the whole transport,
    because a userspace node installs no OS resolver: the mesh name is resolved
    inside the dialing path by ``tailscale nc`` and by nothing this host can
    look up. ``tailscale ping <name>`` and ``tailscale debug resolve`` both
    answer ``lookup <name> on 169.254.1.1:53: no such host`` for that reason,
    whatever ``--accept-dns`` says, so a hostname the host's own resolver has to
    answer was never available.

    The second is a ``ConnectTimeout``, and it is what makes an unreachable
    member an answer rather than a hang. A node the coordination server expired
    stays in the dialing node's netmap - ``expired=true`` beside
    ``online=true`` - and the dial through it then produces no output and never
    returns, measured at 30s and still going, against under a second for the
    same name before the expiry. ssh makes no ``connect(2)`` of its own behind a
    proxy, but ``ssh_exchange_identification`` is bounded by this same option,
    so a proxy that says nothing is a failed dial at `MESH_DIAL` seconds. Every
    consumer of a mesh dial has that exposure, which is why the figure is here
    and not in a folder.

    Args:
        key: The private key this run connects with.
        client: The mesh client the proxy dials through.
        socket: The node's own control socket.

    Returns:
        The options, as one ``NIX_SSHOPTS`` string. The proxy is one shell word,
        because the command splits that variable with ``shlex.split``
        (`cli/remote.py:399`) and an unquoted proxy would arrive as six.
    """
    proxy = f"ProxyCommand={client} --socket={socket} nc %h %p"
    return f"{guest_ssh_options(key)} -o {shlex.quote(proxy)} -o ConnectTimeout={MESH_DIAL}"


@contextlib.contextmanager
def mesh_membership(
    root: Path,
    *,
    key: Path,
    login_server: str,
    authkey: str,
    hostname: str,
    prefix: Sequence[str] = (),
) -> Iterator[MeshMembership]:
    """Join the mesh as one host-side node for the length of the block.

    The node is ``--tun=userspace-networking``, which is what makes this a thing
    a test may do at all: it creates no tun device, claims no ``CAP_NET_ADMIN``
    and needs no root, so the whole membership is the login's own processes and
    its own state directory. Nothing of the host's networking is configured,
    which is also why the mesh name it joins under is unreachable by name
    outside the dialing path (`mesh_ssh_options`).

    The credential is an argument of the process this spawns and of nothing
    else: it is not printed, not logged and not in any refusal below, so a
    failure names the node and the server it was refused by and stops there.

    Args:
        root: A directory this run owns; the node's state goes under it.
        key: The guest ssh key, as `ssh_key` returned it.
        login_server: The coordination server's URL.
        authkey: The single-use credential the server minted.
        hostname: The name this node joins under, which is the first label of
            the mesh name the server then answers for.
        prefix: The argv prefix every process this spawns is run under, as
            `namespace_prefix` builds it. Empty is a node on the host's own
            network, which reaches a coordination server on the host and no
            machine of a cluster.

    Yields:
        The membership: its own name, its control socket and the ssh options.

    Raises:
        DeliveryError: If the variable naming the client is unset, if the daemon
            exits or never answers on its socket, or if the server refuses the
            join or leaves it hanging on a registration URL.
    """
    daemon, client = _mesh_programs()
    state = root / f"mesh-{hostname}"
    state.mkdir(parents=True, exist_ok=True)
    socket = state / "sock"
    with (state / "daemon.log").open("wb") as log:
        running = subprocess.Popen(
            [
                *prefix,
                str(daemon),
                "--tun=userspace-networking",
                f"--state={state / 'state'}",
                f"--socket={socket}",
                f"--statedir={state / 'dir'}",
                "--port=0",
            ],
            stdout=log,
            stderr=subprocess.STDOUT,
        )
        try:
            _mesh_answers(client, socket, running, hostname=hostname, prefix=prefix)
            _mesh_join(
                client,
                socket,
                login_server=login_server,
                authkey=authkey,
                name=hostname,
                prefix=prefix,
            )
            yield MeshMembership(
                name=hostname,
                socket=socket,
                ssh_options=mesh_ssh_options(key, client, socket),
            )
        finally:
            running.terminate()
            try:
                running.wait(timeout=MESH_STOP)
            except subprocess.TimeoutExpired:
                running.kill()
                running.wait()


def _mesh_answers(
    client: Path,
    socket: Path,
    running: subprocess.Popen[bytes],
    *,
    hostname: str,
    prefix: Sequence[str],
) -> None:
    """Wait until the daemon answers on its own socket, or refuse.

    ``status --json`` is the question because it exits 0 the moment the daemon
    answers and 1 while nothing is listening, whatever the node's state is:
    before a join it answers ``NeedsLogin``, and the plain ``status`` exits 1
    there too, which is a readiness signal that never arrives.
    """
    deadline = time.monotonic() + MESH_READY
    while time.monotonic() < deadline:
        if running.poll() is not None:
            raise DeliveryError(
                f"the mesh daemon of {hostname} exited {running.returncode} before its socket "
                f"answered; what it printed is in {socket.parent / 'daemon.log'}"
            )
        try:
            answered = subprocess.run(
                [*prefix, str(client), f"--socket={socket}", "status", "--json"],
                capture_output=True,
                check=False,
                timeout=MESH_STEP,
            )
        except subprocess.TimeoutExpired:
            continue
        if answered.returncode == 0:
            return
        time.sleep(MESH_POLL)
    raise DeliveryError(
        f"the mesh daemon of {hostname} did not answer on {socket} within "
        f"{MESH_READY:.0f}s; what it printed is in {socket.parent / 'daemon.log'}"
    )


def _mesh_join(
    client: Path,
    socket: Path,
    *,
    login_server: str,
    authkey: str,
    name: str,
    prefix: Sequence[str],
) -> None:
    """Present the credential once and refuse where the server does not admit the node.

    ``up`` blocks printing a registration URL where the credential is empty or
    already spent, so the bound is the refusal and not a hang to tolerate. No
    refusal here carries what the client said or what it was run with: the
    credential is in that argument vector, and a chained ``TimeoutExpired``
    would print it.
    """
    argv = [
        *prefix,
        str(client),
        f"--socket={socket}",
        "up",
        "--login-server",
        login_server,
        "--authkey",
        authkey,
        "--hostname",
        name,
        "--accept-dns=false",
        "--accept-routes=false",
    ]
    try:
        joined = subprocess.run(argv, capture_output=True, check=False, timeout=MESH_JOIN)
    except subprocess.TimeoutExpired:
        raise DeliveryError(
            f"{name} was still being registered by {login_server} after {MESH_JOIN:.0f}s, which "
            f"is what a spent or empty credential looks like: `up` prints a URL and waits"
        ) from None
    if joined.returncode != 0:
        raise DeliveryError(
            f"{login_server} refused {name}, exiting {joined.returncode}; what it said is not "
            f"repeated here, the credential being an argument of that same command"
        )


def namespace_prefix(cluster: Any) -> tuple[str, ...]:
    """Return the argv prefix that runs one process inside a cluster's namespaces.

    A machine's ``10.0.0.x`` address exists only inside the cluster's own
    network namespace, which is why every command a folder makes against a
    machine goes through ``Cluster.run``
    (``rookery/qemu/access.py``, ``run_in_namespace``). A mesh node is no
    different: the coordination server answers on a machine's address, so the
    daemon that registers with it and the proxy that dials through it are inside
    that namespace or they reach nothing at all.

    The two namespaces are the two rookery's own entry joins, and the anchor is
    read off ``anchor.pid`` in the run directory - the pid rookery publishes as
    a cluster's liveness key, not one found by looking at processes. It is read
    on every call and held nowhere: a resumed or restarted stage is another
    anchor, and a pid kept across phases names either nothing or another
    cluster's namespaces, where a machine's address is byte-identical.
    ``--preserve-credentials`` is required: without it ``nsenter``'s
    ``setgroups`` is refused in the single-uid user namespace, which is
    rookery's reason for carrying the flag too. Joining a user namespace this
    login owns needs no privilege.

    Args:
        cluster: rookery's live ``Cluster``.

    Returns:
        The prefix, to hand `mesh_membership` as ``prefix``. It is deliberately
        not in the ssh options: the proxy is spawned by ``ssh`` under
        ``Cluster.run``, which is inside the namespace already, and the daemon's
        socket is a plain file both sides see, rookery's mount namespace
        touching only ``/proc``.

    Raises:
        DeliveryError: If the run directory carries no anchor, naming it.
    """
    anchor = Path(cluster.vms[0].run_dir) / ANCHOR_PID
    if not anchor.is_file():
        raise DeliveryError(
            f"{anchor} is not there, and it is what names the namespaces a mesh node has to "
            f"be inside: a node outside them registers with no coordination server"
        )
    return ("nsenter", "-t", anchor.read_text().strip(), "--preserve-credentials", *NAMESPACES)


def command_env(
    base_env: dict[str, str],
    key: Path,
    *,
    mesh: MeshMembership | None = None,
) -> dict[str, str]:
    """Return the environment the operator's command runs under in a cluster.

    ``Cluster.run`` replaces the environment rather than extending it, so the
    caller's own is carried through here: the command shells out to ``nix copy``,
    which needs its ``PATH``, its ``HOME`` and its daemon socket.

    Args:
        base_env: The caller's own environment.
        key: The private key this run connects with.
        mesh: The membership a machine declared by its mesh name is reached
            through. Where one is given its options are the whole value, the
            guest's own options being inside them already: the mesh name is a
            name only the dialing path resolves, so the transport is that
            membership's proxy and not an address the command can dial.

    Returns:
        The environment, with ``NIX_SSHOPTS`` set.
    """
    env = dict(base_env)
    env["NIX_SSHOPTS"] = guest_ssh_options(key) if mesh is None else mesh.ssh_options
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
    offline: bool = True,
    disk_gib: int = 0,
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
        offline: Whether the cluster is hermetic; part of the key. A folder whose
            claim is about a machine fetching its own inputs states ``False``,
            which adds the ``pasta`` uplink and an upstream for the cluster's
            resolver. Every other folder leaves it on, and the wire it tests is
            then bounded by the machines themselves.
        disk_gib: The size every machine's overlay is grown to, in GiB, for a
            folder whose service holds state on disk. ``0`` keeps the image's
            own size, which is what a folder delivering artifacts and nothing
            else needs. It is part of the key, so the figure is declared beside
            the folder that needs it rather than raised in the shared image,
            where it would re-key every other folder's cut.

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
        offline=offline,
        disk_size_gib=disk_gib,
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
