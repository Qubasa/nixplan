"""Two real machines, one of which the operator's network cannot route to.

The folder exists for the one thing no other folder shows: a machine becomes a
member of a mesh, is declared in the registry by the name that mesh answers for,
and is an ordinary machine of its scope ever after. Nothing below the registry
can tell that name from a host and a port, which is the whole trick, and nothing
in this tree implements the mesh: the membership authority is the coordination
server, placed on the operator's own machine as an entry of this deployment, the
client is the guest image's own daemon, and what this tree owns is a registry
row, a generated credential and this proof.

The credential is a generated value like any other - minted single-use and
expiring, `secrecy = "secret"`, delivered to no machine - and the two refusals
that make it safe are the server's and never this tree's: a second presentation
of a spent key and a presentation past the expiry. The operator's own acts
against the server are `headscale` invocations made over ssh, which is why the
guest carries the tool; no unit of this deployment performs them and no plan
records their arguments.

Where each credential's bytes go is worth stating once, because the discipline
this folder proves is about exactly that. The deployment declares a generator
and states its program, and planning runs nothing, so the plan carries the
file's path and the sentence "its bytes are not here". Every credential a phase
below presents is minted against the running server and read into this process
on the standard output of one ssh, and from there it enters exactly two argument
vectors, both of them a presenter's own: the guest's client, and the host-side
node this run dials the mesh through. No `planner` invocation, no step line, no
observation line and no assertion message carries one - the server's own
listings mask a key it has minted to its first twelve characters, which is why
the listings may be read back verbatim.

The phases are session-scoped and order-dependent: the server, the operator's
two acts, an apply against a machine that has not joined, the join, the two
refusals, the apply over the mesh, and last of all the expiry - which takes the
wire every phase above it stands on.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import time
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest

import delivery
import manifest

snapshot = pytest.importorskip(
    "rookery.snapshot",
    reason='rookery is not importable: run .#planner-e2e, or eval "$(planner-e2e-env)"',
)

HUB = "hub"
FRIEND = "friend"
# In slot order: rookery's static leases are 10.0.0.(10 + i), so the hub's
# address is not a free choice and the friend machine's lease appears nowhere
# in the deployment, which is the point - nothing there can dial it by a number.
MACHINES = (HUB, FRIEND)
# The login every step against the friend machine is taken as. It is the account
# tests/e2e/guest.nix declares; no plan names it.
ACCOUNT = "deployer"
HUB_KEY = "mesh:hub@hub"
RUN_KEY = "guestapp:run@friend"
VALUE = "mesh:vars/enrollment"
# The group the server files admitted machines under, which the deployment's
# own `mesh.nix` states. It is a fact of the server's database and of no plan,
# so it is this test's word and read off nothing.
OWNER = "friends"
# The host-side node this run dials the mesh through. It is not the friend: a
# single-use credential admits one node, and the operator's own machine is a
# second member with a credential of its own.
OPERATOR = "operator"
# Room for the server's database, the two artifacts and their closures. Declared
# beside the stage rather than raised in the shared image, where it would re-key
# every other folder's cut. It grows an overlay, so it has to exceed the shared
# image's own virtual size: a smaller figure is a shrink and qemu-img refuses
# one without `--shrink`.
DISK_GIB = 16
# Each credential this run mints, and how long the server admits anybody with
# it. The third is the expiry case: a figure small enough that it is already
# past by the time that phase runs, which the phase establishes by asking the
# server rather than by sleeping.
CREDENTIALS = (
    (FRIEND, "1h"),
    (OPERATOR, "1h"),
    ("expiring", "5s"),
)
# Long enough for a daemon to answer its own socket and for a join to be refused
# by a server one hop away.
PATIENCE = 240


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


CLI = _env_path("PLANNER_CLI")
FLAKE = _env_path("PLANNER_E2E_FLAKE")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
SSH_KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))
# The client this run's own node is driven with. The same store path the harness
# spawns the node from, because a second one would be a second version.
TAILSCALE = _env_path("PLANNER_TAILSCALE") / "bin" / "tailscale"


def _built(target: str) -> Path:
    """Build this folder's deployment with the operator's own command.

    Raises:
        RuntimeError: If the build failed, carrying its standard error, which
            is where a refused deployment's rendered table appears.
    """
    built = subprocess.run([str(CLI), "build", target], capture_output=True, text=True, check=False)
    if built.returncode != 0:
        raise RuntimeError(f"planner build {target} failed:\n{built.stderr.strip()}")
    return Path(built.stdout.splitlines()[0])


BUILT = _built(f"{FLAKE}#planner-e2e-friend-enrollment")
DEPLOYMENT = manifest.read(BUILT)

HUB_ENTRY = DEPLOYMENT.entries[HUB_KEY]
RUN_ENTRY = DEPLOYMENT.entries[RUN_KEY]
HUB_ADDRESS = manifest.address_of(HUB_ENTRY)
# The mesh name, which is what the registry declared as this machine's address.
FRIEND_ADDRESS = manifest.address_of(RUN_ENTRY)
HUB_UNIT = HUB_ENTRY.units[0]
RUN_UNIT = RUN_ENTRY.units[0]


def _configuration() -> tuple[str, Path]:
    """The server's configuration: the path it reads it at, and the object holding it.

    The entry states a file of literals, so its bytes are the plan's and the
    artifact carries them; the realiser binds that store object into the unit's
    own namespace, so the host path exists for the server and for nobody else.
    Which store object holds those bytes is read off the unit file the artifact
    carries, because that file is the thing that names it, and the operator's own
    invocations are pointed at the object rather than at the path only a unit can
    see.

    Returns:
        The host path the entry is shown, and the store object bound there.
    """
    declared = sorted(DEPLOYMENT.plan[HUB_KEY]["configData"])
    assert len(declared) == 1, declared
    path = declared[0]
    text = (manifest.artifact_of(HUB_ENTRY) / "units" / HUB_UNIT).read_text()
    bound = [
        line.partition("=")[2]
        for line in text.splitlines()
        if line.startswith("BindReadOnlyPaths=")
    ]
    holding = [shown.partition(":")[0] for shown in bound if shown.partition(":")[2] == path]
    assert len(holding) == 1, (bound, path)
    return path, Path(holding[0])


CONFIG_PATH, CONFIG = _configuration()


def _stated(field_name: str) -> str:
    """One scalar the rendered configuration states, by its own key.

    The line is stripped before it is read, so a key nested under another is
    found by its name: every name asked for here is unique in that file.

    Raises:
        AssertionError: If the configuration states no such key.
    """
    for line in CONFIG.read_text().splitlines():
        name, separator, said = line.strip().partition(": ")
        if separator and name == field_name:
            return said.strip().strip('"')
    raise AssertionError(f"{CONFIG} states no {field_name}")


LOGIN_SERVER = _stated("server_url")
SOCKET = _stated("unix_socket")
DOMAIN = _stated("base_domain")
# Where the operator's own invocations read the configuration. Not the store
# object the unit is shown and not the host path it is shown it at: the path the
# entry states exists inside that unit's namespace alone, and the store object
# is named by its hash with no suffix, which the server's own configuration
# reader refuses - `error loading config file <store path>`, because it decides
# the format from the file extension. So one copy of the same bytes under a name
# ending in `.yaml`, made on the machine by the phase that starts the server,
# under a directory of this test's own: the paths inside the file are absolute,
# so a copy answers about the same database and the same socket.
OPERATOR_CONFIG = "/run/planner-friend-enrollment/config.yaml"
HEADSCALE = f"headscale --config {shlex.quote(OPERATOR_CONFIG)}"
INSTALL_CONFIG = f"install -D -m 0444 {shlex.quote(str(CONFIG))} {shlex.quote(OPERATOR_CONFIG)}"


def _unit_record() -> dict[str, Any]:
    """The plan record of the friend machine's one unit, which its paths are read off."""
    units = DEPLOYMENT.plan[RUN_KEY]["units"]
    assert len(units) == 1, units
    record = next(iter(units.values()))
    assert isinstance(record, dict), record
    return record


UNIT_RECORD = _unit_record()
# Both derived by the module from the identity of its own entry, so they are read
# off the plan here rather than restated, and the third is the name the planner
# put in the entry's target because the registry declared it.
RUNTIME_DIRECTORY = UNIT_RECORD["runtimeDirectory"][0]
RECORD_NAME = UNIT_RECORD["env"]["RECORD_NAME"]
DIALLED_NAME = UNIT_RECORD["env"]["DIALLED_NAME"]


def _answered(reported: str) -> dict[str, str]:
    """One case's `key=value` lines, as a mapping.

    Everything a case observes is echoed in that shape by the one command it
    runs, because a value spanning lines is a parse this reader cannot make.
    """
    return {
        key: said.strip()
        for key, _, said in (line.partition("=") for line in reported.splitlines())
        if key and said
    }


def _node_script() -> str:
    """The one question the server is asked about the machines it has admitted.

    The listing is handed back whole and read in this process, because the guest
    carries no JSON tool and a shape parsed by a shell is a shape parsed twice.
    A credential the server minted appears in it masked to its first twelve
    characters, so the listing carries no bearer authority.
    """
    return f"printf 'nodes=%s\\n' \"$({HEADSCALE} nodes list --output json | tr -d '\\n')\""


def _presentation(authkey: str, hostname: str) -> str:
    """A script presenting one credential from a throwaway node of the hub machine.

    A second node rather than the machine's own daemon: the daemon holds one node
    key and one membership, and what is under test is a presentation the server
    refuses, so the presenter is brought up with a state directory of its own and
    taken down again. `--tun=userspace-networking` is what makes it a thing a
    second node on one machine can be at all - it creates no tun device and claims
    no capability - and the join is run under a timeout because the client blocks
    and prints a registration URL where the server refused the credential.

    The credential is an argument of the client and of nothing else. What comes
    back is the client's own last line, which is the server's refusal in the
    server's own words.
    """
    return "; ".join(
        [
            "d=$(mktemp -d)",
            # `&` ends the command it backgrounds, so the pid is read in the same
            # element: a `; ` after it is a syntax error, which is what the shell
            # answered the first time this ran.
            "tailscaled --tun=userspace-networking --state=$d/state --socket=$d/sock"
            " --statedir=$d/dir --port=0 > $d/daemon.log 2>&1 & pid=$!",
            f"for _ in $(seq 1 {PATIENCE}); do test -S $d/sock && break; sleep 0.25; done",
            f"timeout 60 tailscale --socket=$d/sock up --login-server {shlex.quote(LOGIN_SERVER)}"
            f" --authkey {shlex.quote(authkey)} --hostname {shlex.quote(hostname)}"
            " --accept-dns=false --accept-routes=false > $d/up.log 2>&1",
            "status=$?",
            "kill $pid 2> /dev/null",
            "printf 'presented=%s\\n' \"$status\"",
            "printf 'said=%s\\n' \"$(tail -1 $d/up.log | tr -d '\\r')\"",
            "rm -rf $d",
        ]
    )


@dataclass
class Run:
    """The machines, and what each phase observed on them."""

    cluster: Any
    observed: dict[str, str] = field(default_factory=dict)
    credentials: dict[str, dict[str, Any]] = field(default_factory=dict)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def root(self, machine: str, script: str) -> str:
        """Run one script as root on one machine, over the harness's own channel.

        This channel is the harness's and never the operator's: it is how the
        machines' own owners act - the operator minting against the server on the
        hub, the third party joining the mesh on their own machine - and none of
        it goes through a name the mesh has to answer.
        """
        return str(self.vm(machine).ssh_succeed(script, timeout=PATIENCE))

    def hub(self, script: str) -> str:
        """Run one script as root on the machine the coordination server runs on."""
        return self.root(HUB, script)

    def account(self, mesh: Any, script: str) -> str:
        """Run one script as the account on the friend machine, over the mesh.

        The address is the mesh name, so what reaches the machine is the same
        transport an apply uses and the same name the registry declared. An `ssh`
        of its own rather than the harness's root channel: root's session carries
        a bus of its own, so a `--user` tool run from it dials root's manager.
        One command per case, because the guest's sshd is socket activated and a
        burst of short logins hits its trigger limit.
        """
        options = shlex.split(mesh.ssh_options)
        return str(
            self.cluster.run(
                [
                    "ssh",
                    *options,
                    f"{ACCOUNT}@{FRIEND_ADDRESS}",
                    'export XDG_RUNTIME_DIR=/run/user/"$(id -u)"; ' + script,
                ],
                env=delivery.command_env(dict(os.environ), SSH_KEY, mesh=mesh),
            ).stdout
        )

    def planner(self, argv: list[str], *, mesh: Any = None, check: bool = True) -> Any:
        """Run the operator's own command inside the cluster.

        A machine's address exists only in the cluster's own network namespace,
        and the friend machine's exists only in the mesh, so the command runs
        there and reaches the second one through the membership this run holds.
        """
        return self.cluster.run(
            [str(CLI), *argv],
            env=delivery.command_env(dict(os.environ), SSH_KEY, mesh=mesh),
            check=check,
        )

    def steps(self, which: str) -> list[str]:
        """The step lines of one run, in the order the steps happened."""
        return [line for line in self.observed[which].splitlines() if not line.startswith(" ")]

    def nodes(self, reported: str) -> list[dict[str, Any]]:
        """The machines the server has admitted, as it listed them.

        The tool answers `null` rather than an empty list for a server that has
        admitted nobody, so that answer is read as the empty list it means.
        """
        listed = json.loads(_answered(reported)["nodes"])
        return [] if listed is None else [node for node in listed if isinstance(node, dict)]


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=MACHINES, key=SSH_KEY, disk_gib=DISK_GIB)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage every run starts from: two machines, up and usable.

    On a cache hit this body does not run at all - the machines are resumed from
    the cut they took the first time - so nothing here may be a fact a test
    reads, and nothing here delivers, activates, attaches or joins anything. It
    waits for `multi-user.target` rather than for ssh, because the vsock sshd
    answers before the login `PATH` exists, and yields.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def run(booted: Any) -> Run:
    """The two machines this run acts against."""
    return Run(cluster=booted.cluster)


@pytest.fixture(scope="session")
def served(run: Run) -> Run:
    """Phase 1: the coordination server applied, alone.

    It is an entry of this deployment like any other - a system-scope entry on
    the operator's own machine, realised as a service artifact - so the run that
    puts the membership authority there is `planner apply` and nothing else. It
    is restricted to that entry because the other one is placed on a machine that
    is not a member yet, which is the phase after next. The one act beside the
    apply is the operator's own copy of the configuration, which every later
    invocation of the server's tool reads: `OPERATOR_CONFIG` says why it exists.
    """
    if not run.observed.get("served"):
        run.observed["served"] = str(run.planner(["apply", str(BUILT), "--only", HUB_KEY]).stdout)
        run.hub(INSTALL_CONFIG)
    return run


def test_the_coordination_server_is_a_planned_entry_that_answers_its_own_tool(
    served: Run,
) -> None:
    """The command put the server there, it runs, and it answers over its own socket.

    The socket is waited for rather than read in the same breath: the activation
    returns when the manager has started the unit, and the server binds its
    socket when it is ready. That it answers at all is the evidence the operator's
    later acts have something to act against, and the answer itself is that no
    machine has been admitted, which is where this folder starts.
    """
    steps = served.steps("served")
    assert steps == [
        f"copy {HUB_KEY} {manifest.artifact_of(HUB_ENTRY)} -> root@{HUB_ADDRESS}",
        f"activate {HUB_KEY} ({HUB_ENTRY.realiser}) on root@{HUB_ADDRESS}",
    ], steps

    answered = _answered(
        served.hub(
            "; ".join(
                [
                    f"for _ in $(seq 1 {PATIENCE}); do test -S {shlex.quote(SOCKET)} && break;"
                    " sleep 0.25; done",
                    f"printf 'active=%s\\n' \"$(systemctl is-active {shlex.quote(HUB_UNIT)})\"",
                    f"printf 'socket=%s\\n' \"$(test -S {shlex.quote(SOCKET)}"
                    ' && echo present || echo absent)"',
                    f"printf 'asked=%s\\n' \"$({HEADSCALE} nodes list --output json > /dev/null"
                    ' 2>&1 && echo answered || echo refused)"',
                    f"printf 'why=%s\\n' \"$({HEADSCALE} nodes list --output json 2>&1"
                    " >/dev/null | tr '\\n' ' ' | cut -c 1-200)\"",
                    _node_script(),
                ]
            )
        )
    )
    assert answered["active"] == "active", answered
    assert answered["socket"] == "present", answered
    assert answered["asked"] == "answered", answered.get("why", answered)
    assert served.nodes(f"nodes={answered['nodes']}") == [], answered["nodes"]


@pytest.fixture(scope="session")
def credentials(served: Run) -> Run:
    """Phase 2: the operator's two acts against the server.

    The group first, because the tool that mints a credential takes the number
    the server's own database assigned it and never the name, and that number is
    read back off the server. Then three credentials: one for the friend machine,
    one for the operator's own node - a single-use key admits one node, and the
    operator's machine is not the friend - and one that expires in seconds, for
    the phase about a key past its expiry.

    Two logins rather than one, because the second act needs the answer of the
    first in its own argument vector. What comes back is read in this process and
    goes into no observation line: the mint's answer carries the bytes.
    """
    if credentials_are_minted(served):
        return served

    created = served.hub(
        f"{HEADSCALE} users create {shlex.quote(OWNER)} > /dev/null; "
        f"{HEADSCALE} users list --output json | tr -d '\\n'"
    )
    named = [user for user in json.loads(created) if user.get("name") == OWNER]
    assert len(named) == 1, created
    owner = named[0]["id"]
    minted = served.hub(
        "; ".join(
            f"{HEADSCALE} preauthkeys create --user {shlex.quote(str(owner))}"
            f" --expiration {shlex.quote(expiry)} --output json | tr -d '\\n'; echo"
            for _, expiry in CREDENTIALS
        )
    )
    answers = [json.loads(line) for line in minted.splitlines() if line.strip()]
    assert len(answers) == len(CREDENTIALS), len(answers)
    served.credentials = {
        name: answer for (name, _), answer in zip(CREDENTIALS, answers, strict=True)
    }
    served.observed["owner"] = str(owner)
    served.observed["ownerkind"] = type(owner).__name__
    return served


def credentials_are_minted(run: Run) -> bool:
    """Whether this run has already taken the operator's minting act."""
    return bool(run.credentials)


def test_a_credential_is_minted_against_a_group_the_server_numbered(
    credentials: Run,
) -> None:
    """The group's identifier is a number, and each credential is its own bytes.

    The number is the fact the minting script's comment states: the tool's flag
    is `-u, --user uint`, so a name would be refused and the identifier has to be
    read back off the server's own answer. That the three credentials differ is
    what single-use means on this side of the handover - one of them admits the
    friend machine and no other presenter can spend it.
    """
    assert credentials.observed["ownerkind"] == "int", credentials.observed
    assert credentials.observed["owner"].isdigit(), credentials.observed

    minted = [credentials.credentials[name] for name, _ in CREDENTIALS]
    assert len(minted) == len(CREDENTIALS), len(minted)
    for answer in minted:
        assert answer["key"], sorted(answer)
        assert isinstance(answer["expiration"]["seconds"], int), sorted(answer["expiration"])
    assert len({answer["key"] for answer in minted}) == len(CREDENTIALS)
    # The one that carries the expiry case expires before the ones that do not.
    expiries = [answer["expiration"]["seconds"] for answer in minted]
    assert expiries[-1] < min(expiries[:-1]), expiries


@pytest.fixture(scope="session")
def mesh(credentials: Run) -> Iterator[Any]:
    """The operator's own node, held for the rest of the session.

    Entered once and kept: the credential it presents is single-use, so a block
    entered twice would present a spent key the second time. Every phase below
    that dials the friend machine by its mesh name dials it through this node,
    which is the only route to that machine there is.
    """
    with delivery.mesh_membership(
        delivery.state_root(),
        key=SSH_KEY,
        login_server=LOGIN_SERVER,
        authkey=credentials.credentials[OPERATOR]["key"],
        hostname=OPERATOR,
        prefix=delivery.namespace_prefix(credentials.cluster),
    ) as membership:
        yield membership


@pytest.fixture(scope="session")
def unenrolled(credentials: Run, mesh: Any) -> Run:
    """Phase 3: an apply against the friend machine before it has joined.

    The operator's node is up, so the dial is made the way every dial of that
    machine is made; what is missing is the machine on the other end of the name.
    """
    if not credentials.observed.get("unenrolled"):
        refused = credentials.planner(
            ["apply", str(BUILT), "--only", RUN_KEY, "--user", ACCOUNT],
            mesh=mesh,
            check=False,
        )
        credentials.observed["unenrolled"] = str(refused.stdout)
        credentials.observed["unenrolled-said"] = str(refused.stderr)
        credentials.observed["unenrolled-status"] = str(refused.returncode)
    return credentials


def test_a_machine_that_never_joined_receives_nothing(unenrolled: Run) -> None:
    """The run refuses at that machine's first step and leaves nothing behind.

    Which step is first is not this test's choice: the question of what a machine
    holds is asked before anything is written, and a machine that answers nothing
    at all is left alone there rather than claimed unreadable, so the refusal
    surfaces at the preflight - the head of the on-machine line for a machine
    whose scope is `user`. The failure names the machine, the login and the mesh
    name, and carries what the dial answered.

    What was written is asked of the machine itself, over the harness's own
    channel rather than the operator's: the friend machine is a machine of this
    cluster whether or not it is a member, so the question can be put to it
    directly. Two answers say nothing arrived - its store does not hold the
    entry's artifact, and the account's own portable pool is empty - and the step
    log says the same thing from the other side: the run took one step and it was
    not a write.
    """
    assert unenrolled.observed["unenrolled-status"] != "0", unenrolled.observed["unenrolled-status"]
    said = unenrolled.observed["unenrolled-said"]
    assert f"preflight {FRIEND} at {ACCOUNT}@{FRIEND_ADDRESS}" in said, said
    assert FRIEND_ADDRESS in said, said
    assert "refused the step, exiting 255" in said, said

    steps = unenrolled.steps("unenrolled")
    assert [step for step in steps if step.startswith(("value ", "copy ", "activate "))] == [], (
        steps
    )
    # The dial's own words follow the refusal on the stream ssh wrote them to, so
    # the failed step is a line of the report and not necessarily its last.
    assert [step for step in steps if step.startswith("failed ")], steps

    answered = _answered(
        unenrolled.root(
            FRIEND,
            "; ".join(
                [
                    f"home=$(getent passwd {shlex.quote(ACCOUNT)} | cut -d: -f6)",
                    "printf 'artifact=%s\\n' \"$(test -e"
                    f" {shlex.quote(str(manifest.artifact_of(RUN_ENTRY)))}"
                    ' && echo present || echo absent)"',
                    "printf 'pool=%s\\n' \"$(ls -A"
                    ' "${XDG_STATE_HOME:-$home/.local/state}"/portables 2> /dev/null | wc -l)"',
                ]
            ),
        )
    )
    assert answered["artifact"] == "absent", answered
    assert answered["pool"] == "0", answered


@pytest.fixture(scope="session")
def joined(unenrolled: Run) -> Run:
    """Phase 4: the friend machine joins, with the credential handed to it.

    Taken on that machine by its own owner, over the harness's own channel: the
    handover happens outside this tree and the join is the third party's act,
    not a step of any run. The client is the guest image's own daemon, inert
    until this moment.
    """
    if not unenrolled.observed.get("joined"):
        unenrolled.observed["joined"] = unenrolled.root(
            FRIEND,
            "; ".join(
                [
                    f"tailscale up --login-server {shlex.quote(LOGIN_SERVER)}"
                    f" --authkey {shlex.quote(unenrolled.credentials[FRIEND]['key'])}"
                    f" --hostname {shlex.quote(FRIEND)}"
                    " --accept-dns=false --accept-routes=false",
                    "printf 'address=%s\\n' \"$(tailscale ip -4 | head -1)\"",
                    "printf 'state=%s\\n' \"$(tailscale status --peers=false"
                    " | sed -n 's/.*[[:space:]]\\([A-Za-z-]*\\)$/\\1/p' | head -1)\"",
                ]
            ),
        )
        unenrolled.observed["listed"] = unenrolled.hub(_node_script())
    return unenrolled


def test_the_servers_node_list_names_the_machine_the_registry_declared(joined: Run) -> None:
    """The machine the server admitted is the machine the registry declares.

    The registry's `address` for it is a name, and the name the server answers
    for a node is that node's own name under the domain the server's
    configuration states - so the two are crossed here rather than asserted
    apart. Everything else about the machine is what any machine's registry row
    carries, which is the claim: enrollment added no key.
    """
    answered = _answered(joined.observed["joined"])
    assert answered["address"].startswith("100."), answered

    nodes = joined.nodes(joined.observed["listed"])
    mine = [node for node in nodes if node.get("given_name") == FRIEND]
    assert len(mine) == 1, nodes
    assert f"{mine[0]['given_name']}.{DOMAIN}" == FRIEND_ADDRESS, (mine[0], DOMAIN)
    assert DEPLOYMENT.plan[f"machine:{FRIEND}"]["address"] == FRIEND_ADDRESS
    assert manifest.machine_scope(DEPLOYMENT, FRIEND) == "user"
    # The operator's own node is the other member, and no third one exists.
    assert sorted(node["given_name"] for node in nodes) == sorted((FRIEND, OPERATOR)), nodes


def test_a_second_join_with_a_spent_key_is_refused(joined: Run) -> None:
    """The server refuses the second presenter in its own words, and admits nobody.

    Single-use is what makes an intercepted handover visible: the second
    presenter is refused and the first is on the list for the operator to
    inspect. Neither refusal is this tree's - the tree only mints credentials the
    server will refuse twice - so what is asserted is the server's own sentence
    and the list it kept.
    """
    before = joined.nodes(joined.observed["listed"])
    answered = _answered(joined.hub(_presentation(joined.credentials[FRIEND]["key"], "second")))
    assert answered["presented"] != "0", answered
    assert "authkey already used" in answered["said"], answered["said"]

    after = joined.nodes(joined.hub(_node_script()))
    assert [node["id"] for node in after] == [node["id"] for node in before], (before, after)
    assert [node["given_name"] for node in after if node["given_name"] == FRIEND] == [FRIEND]


def test_a_key_past_its_expiry_admits_nobody(joined: Run) -> None:
    """A credential the server has outlived admits nobody, and the server says so.

    The expiry is waited on by asking rather than by sleeping: the server states
    a credential's expiry when it mints it and lists the same figure back, and
    the machine running the server is the clock that figure is against, so the
    wait is a comparison of the two on that machine. The listing is read back
    whole and carries no bearer authority - the server masks a key it minted to
    its first twelve characters.
    """
    expiring = joined.credentials["expiring"]
    stated = expiring["expiration"]["seconds"]
    before = joined.nodes(joined.hub(_node_script()))
    answered = _answered(
        joined.hub(
            "; ".join(
                [
                    f"for _ in $(seq 1 {PATIENCE});"
                    f' do test "$(date -u +%s)" -gt {stated} && break; sleep 0.5; done',
                    "printf 'clock=%s\\n' \"$(date -u +%s)\"",
                    f"printf 'keys=%s\\n' \"$({HEADSCALE} preauthkeys list --output json"
                    " | tr -d '\\n')\"",
                    _presentation(expiring["key"], "late"),
                ]
            )
        )
    )
    listed = [key for key in json.loads(answered["keys"]) if key.get("id") == expiring["id"]]
    assert len(listed) == 1, answered["keys"]
    assert listed[0]["expiration"]["seconds"] == stated, listed[0]
    assert int(answered["clock"]) > stated, answered["clock"]
    assert listed[0]["key"].endswith("***"), listed[0]["key"]

    assert answered["presented"] != "0", answered
    assert "authkey expired" in answered["said"], answered["said"]
    after = joined.nodes(joined.hub(_node_script()))
    assert [node["id"] for node in after] == [node["id"] for node in before], (before, after)


@pytest.fixture(scope="session")
def applied(joined: Run, mesh: Any) -> Run:
    """Phase 7: one apply against the friend machine, now that it is a member.

    Made as the account and dialled by the mesh name, which is the whole point:
    the walk is the walk every machine gets and the transport is the mesh's
    business.
    """
    if not joined.observed.get("applied"):
        joined.observed["applied"] = str(
            joined.planner(
                ["apply", str(BUILT), "--only", RUN_KEY, "--user", ACCOUNT], mesh=mesh
            ).stdout
        )
    return joined


def test_a_user_scope_entry_is_applied_over_the_mesh(applied: Run, mesh: Any) -> None:
    """The run dials the name, asks first, activates under the account's own manager.

    Every step of it names the mesh name, because that is the address the
    registry declared and nothing below the registry knows any other. The
    preflight is the first of those steps and precedes every one that mutates the
    machine, the entry is attached through that account's own portabled and
    started by its own manager, and the unit writes back the name it was dialled
    by - which is how the name is read off the machine as well as off the plan.
    The report then asks the same machine over the same name and finds this
    build's image, which closes the loop the folder exists for.
    """
    steps = applied.steps("applied")
    asked = [i for i, step in enumerate(steps) if step.startswith(f"preflight {FRIEND} ")]
    mutating = [
        i for i, step in enumerate(steps) if step.startswith(("value ", "copy ", "activate "))
    ]
    assert len(asked) == 1, steps
    assert mutating, steps
    assert asked[0] < min(mutating), steps
    assert all(f"{ACCOUNT}@{FRIEND_ADDRESS}" in steps[i] for i in (*asked, *mutating)), steps
    assert steps[-1] == f"activate {RUN_KEY} (image) on {ACCOUNT}@{FRIEND_ADDRESS}", steps

    record = f'"$XDG_RUNTIME_DIR"/{shlex.quote(RUNTIME_DIRECTORY)}/{shlex.quote(RECORD_NAME)}'
    answered = _answered(
        applied.account(
            mesh,
            "; ".join(
                [
                    f"for _ in $(seq 1 {PATIENCE}); do test -s {record} && break; sleep 0.25; done",
                    "printf 'attached=%s\\n' \"$(portablectl --user is-attached"
                    f' {shlex.quote(RUN_KEY)} 2>&1 || echo refused)"',
                    f"printf 'active=%s\\n' \"$(systemctl --user is-active"
                    f' {shlex.quote(RUN_UNIT)})"',
                    "printf 'rootimage=%s\\n' \"$(systemctl --user show -P RootImage"
                    f' {shlex.quote(RUN_UNIT)})"',
                    f"printf 'owner=%s\\n' \"$(systemctl --user show -P MainPID"
                    f' {shlex.quote(RUN_UNIT)} | xargs -r -I{{}} stat -c %U /proc/{{}})"',
                    f"printf 'record=%s\\n' \"$(cat {record})\"",
                ]
            ),
        )
    )
    assert answered["attached"] in {"attached", "running"}, answered
    assert answered["active"] == "active", answered
    assert answered["owner"] == ACCOUNT, answered
    assert answered["rootimage"].endswith(f"_{RUN_ENTRY.digest}.raw"), answered
    assert answered["record"] == FRIEND_ADDRESS, answered
    assert DIALLED_NAME == FRIEND_ADDRESS

    reported = applied.planner(
        ["status", str(BUILT), "--only", RUN_KEY, "--user", ACCOUNT], mesh=mesh, check=False
    )
    lines = str(reported.stdout).splitlines()
    assert reported.returncode == 0, (lines, reported.stderr)
    assert len(lines) == 1, lines
    assert lines[0].startswith(f"{RUN_KEY} image "), lines
    assert lines[0].endswith("current"), lines


def _routed(mesh: Any, cluster: Any) -> list[str]:
    """The mesh names the operator's own node currently has a route to.

    Read off that node rather than off the server, because what a report can
    reach is a fact about the dialling node's own map of the mesh and not about
    what the server's database says. The client is asked inside the cluster's
    namespace for the reason the node was started there.
    """
    asked = subprocess.run(
        [
            *delivery.namespace_prefix(cluster),
            str(TAILSCALE),
            f"--socket={mesh.socket}",
            "status",
            "--json",
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    if asked.returncode != 0:
        return []
    peers = json.loads(asked.stdout).get("Peer") or {}
    return [str(peer.get("DNSName", "")).rstrip(".") for peer in peers.values()]


@pytest.fixture(scope="session")
def expired(applied: Run, mesh: Any) -> Run:
    """Phase 8, last of all: the operator expires the friend machine's node.

    It is last because it takes the wire every phase above it stands on. Nothing
    of this tree does it: expiring a node is an act against the server, which is
    how membership ends, and what follows is the report reading a machine it
    cannot reach.
    """
    if not applied.observed.get("expired"):
        nodes = applied.nodes(applied.hub(_node_script()))
        mine = [node for node in nodes if node.get("given_name") == FRIEND]
        assert len(mine) == 1, nodes
        applied.observed["expired"] = applied.hub(
            f"{HEADSCALE} nodes expire --identifier {mine[0]['id']} --force > /dev/null; "
            + _node_script()
        )
        # An expiry reaches this node when the server hands it a map without that
        # peer in it, which is a moment later than the tool's own answer. Waited
        # on by asking the node, because a report run before the map arrived would
        # read the route that is about to go and say `current`.
        for _ in range(PATIENCE):
            if FRIEND_ADDRESS not in _routed(mesh, applied.cluster):
                break
            time.sleep(0.25)
        applied.observed["routed"] = ",".join(_routed(mesh, applied.cluster))
        asked = applied.planner(
            ["status", str(BUILT), "--only", RUN_KEY, "--user", ACCOUNT], mesh=mesh, check=False
        )
        applied.observed["report"] = str(asked.stdout)
        applied.observed["report-said"] = str(asked.stderr)
        applied.observed["report-status"] = str(asked.returncode)
    return applied


def test_an_expired_node_reads_as_unreachable(expired: Run) -> None:
    """The report names the machine as one it could not ask, and exits non-zero.

    An answer about reachability and never about retirement: the build still
    names the entry, the machine still holds it, and what changed is that nobody
    can ask. The machine is named by the name the registry declared, and the
    non-zero status is the report's own rule for a machine that answered nothing
    - a rule this change did not have to add.
    """
    nodes = expired.nodes(expired.observed["expired"])
    mine = [node for node in nodes if node.get("given_name") == FRIEND]
    assert len(mine) == 1, nodes
    assert mine[0]["expiry"] is not None, mine[0]

    lines = expired.observed["report"].splitlines()
    assert lines == [
        f"{RUN_KEY} {RUN_ENTRY.realiser} unreachable: {FRIEND} at {FRIEND_ADDRESS} answered nothing"
    ], lines
    assert f"planner: {FRIEND} could not be asked" in expired.observed["report-said"]
    assert expired.observed["report-status"] == "1", expired.observed["report-status"]
    # The value the deployment declares reaches no machine, so no machine was
    # ever asked about it and no line of the report is about one.
    assert DEPLOYMENT.values[VALUE].delivery == (), DEPLOYMENT.values[VALUE].delivery
