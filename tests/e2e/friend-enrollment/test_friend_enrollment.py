"""Two real machines, one of which the operator's network cannot route to.

The folder exists for the one thing no other folder shows: a machine becomes a
member of a mesh, is declared in the registry by the name that mesh answers for,
and is an ordinary machine of its scope ever after. Nothing below the registry
can tell that name from a host and a port, which is the whole trick, and nothing
in this tree implements the mesh: the membership authority is the coordination
server, placed on the operator's own machine as an entry of this deployment, the
client is the guest image's own daemon, and what this tree owns is a registry
row, a generated credential and this proof.

The server is the module this repository publishes, composed by this folder's
own deployment, and every act against it is a verb of the operator's command:
`planner invite` mints, `planner members` reads back what the server admits and
`planner expel` ends one membership. This file composes no invocation of the
server's own verbs and installs no copy of its configuration anywhere - the
object an administrative invocation reads is a store object of the entry's own
closure, which the apply already put on the machine, and the deployment's
`coordinate` statement is what names it.

The credential is a generated value like any other - minted single-use and
expiring by the generator the deployment declared, `secrecy = "secret"`,
delivered to no machine - and the two refusals that make it safe are the
server's and never this tree's: a second presentation of a spent key and a
presentation past the expiry.

Where each credential's bytes go is worth stating once, because the discipline
this folder proves is about exactly that. The deployment declares a generator
and states its program, and planning runs nothing, so the plan carries the
file's path and the sentence "its bytes are not here". Every credential a phase
below presents is minted by the verb, travels to this process on that step's own
output stream and is written into the value source the verb was handed; it is
read from there and enters exactly two argument vectors, both of them a
presenter's own: the guest's client, and the host-side node this run dials the
mesh through. No `planner` invocation, no step line, no observation line and no
assertion message carries one.

The phases are session-scoped and order-dependent: the server, the operator's
own credential, an apply against a machine that has not joined, the join, the
two refusals, the apply over the mesh, and last of all the expulsion - which
takes the wire every phase above it stands on.
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
# the published provisioning declaration creates on every machine of this
# cluster; no plan names it.
ACCOUNT = "deployer"
HUB_KEY = "mesh:hub@hub"
RUN_KEY = "guestapp:run@friend"
VALUE = "mesh:vars/enrollment"
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
# Long enough for a daemon to answer its own socket and for a join to be refused
# by a server one hop away.
PATIENCE = 240
# The bound on the one wait this folder makes against a clock rather than
# against an answer: the expiry the deployment declares, plus room. It is its
# own figure and not PATIENCE, because what it waits out is a declaration of
# `deployment/mesh.nix` and not the responsiveness of a daemon.
OUTLIVES = 600


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
# What the deployment stated about the entry that coordinates this mesh. The
# verbs read it off the built deployment, and so does this file: which entry,
# which generated value is its join credential, and the two store objects a
# verb spends, each resolved by the build against that entry's own closure.
COORDINATION = DEPLOYMENT.coordination


def _configuration() -> Path:
    """The store object holding the bytes the serving unit reads.

    The entry states a file of literals, so its bytes are the plan's and the
    artifact carries them; the realiser binds that store object into the unit's
    own namespace, so the host path exists for the server and for nobody else.
    Which store object holds those bytes is read off the unit file the artifact
    carries, because that file is the thing that names it.

    Returns:
        The store object bound at the path the entry is shown.
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
    return Path(holding[0])


CONFIG = _configuration()


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

    Everything a case observes on a machine is echoed in that shape by the one
    command it runs, because a value spanning lines is a parse this reader
    cannot make.
    """
    return {
        key: said.strip()
        for key, _, said in (line.partition("=") for line in reported.splitlines())
        if key and said
    }


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
    """The machines, the value source the verbs mint into, and what was observed."""

    cluster: Any
    source: Path
    observed: dict[str, str] = field(default_factory=dict)
    credentials: dict[str, str] = field(default_factory=dict)
    expiries: dict[str, int] = field(default_factory=dict)
    verbs: list[list[str]] = field(default_factory=list)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def root(self, machine: str, script: str) -> str:
        """Run one script as root on one machine, over the harness's own channel.

        This channel is the harness's and never the operator's: it is how the
        machines' own owners act - the third party joining the mesh on their own
        machine, a throwaway presenter spending a spent key - and none of it
        goes through a name the mesh has to answer.
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
        Every invocation is recorded, because what this folder claims about its
        own membership acts is that each of them is one of these.
        """
        self.verbs.append(list(argv))
        return self.cluster.run(
            [str(CLI), *argv],
            env=delivery.command_env(dict(os.environ), SSH_KEY, mesh=mesh),
            check=check,
        )

    def invite(self, name: str) -> str:
        """Mint one credential with the operator's own verb, and read it where it was put.

        The verb writes the files the declared generator wrote into the value
        source it was handed, at the paths the plan names for that value, so the
        bytes are read out of the source here exactly the way an operator reads
        them before handing one over. The verb prints neither.
        """
        printed = self.planner(["invite", str(BUILT), "--values", str(self.source)])
        self.observed[f"invited-{name}"] = str(printed.stdout)
        written = self.source / VALUE
        self.credentials[name] = (written / "preauthkey").read_text().strip()
        self.expiries[name] = int((written / "expiry").read_text().strip())
        return self.credentials[name]

    def members(self) -> list[dict[str, Any]]:
        """Read back what the coordination server admits, with the operator's own verb."""
        printed = self.planner(["members", str(BUILT)])
        self.observed["members"] = str(printed.stdout)
        return self.nodes(str(printed.stdout))

    def expel(self, identifier: str) -> str:
        """End one membership at the server, by the identifier the listing printed."""
        printed = self.planner(["expel", str(BUILT), identifier])
        self.observed["expelled"] = str(printed.stdout)
        return str(printed.stdout)

    def steps(self, which: str) -> list[str]:
        """The step lines of one run, in the order the steps happened."""
        return [line for line in self.observed[which].splitlines() if not line.startswith(" ")]

    @staticmethod
    def nodes(printed: str) -> list[dict[str, Any]]:
        """The machines the server admitted, out of what the listing verb printed.

        The verb echoes the server's answer under its step line, two spaces to
        the left of it the way every machine's answer is echoed, so the answer
        is the indented half and is parsed here rather than on the machine: the
        guest carries no JSON tool and a shape parsed by a shell is a shape
        parsed twice. The tool answers `null` rather than an empty list for a
        server that has admitted nobody, so that answer is read as the empty
        list it means.
        """
        said = "\n".join(line[2:] for line in printed.splitlines() if line.startswith("  "))
        listed = json.loads(said) if said.strip() else None
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
def run(booted: Any, tmp_path_factory: pytest.TempPathFactory) -> Run:
    """The two machines this run acts against, and the source it mints into.

    The value source is this run's own directory and not the deployment: a verb
    writes the bytes it minted there and nothing else anywhere, which is what
    keeps the only gate from the mesh back into evaluation an operator's own
    declaration edit.
    """
    return Run(cluster=booted.cluster, source=tmp_path_factory.mktemp("values"))


@pytest.fixture(scope="session")
def served(run: Run) -> Run:
    """Phase 1: the coordination server applied, alone.

    It is an entry of this deployment like any other - a system-scope entry on
    the operator's own machine, realised as a service artifact - so the run that
    puts the membership authority there is `planner apply` and nothing else. It
    is restricted to that entry because the other one is placed on a machine that
    is not a member yet, which is the phase after next. Nothing is installed
    beside it: the object the operator's verbs read is a store object of this
    entry's own closure, which this apply copied.
    """
    if not run.observed.get("served"):
        run.observed["served"] = str(run.planner(["apply", str(BUILT), "--only", HUB_KEY]).stdout)
    return run


def test_the_coordination_server_is_a_planned_entry_that_answers_its_own_tool(
    served: Run,
) -> None:
    """The command put the server there, it runs, and it answers over its own socket.

    The socket is waited for rather than read in the same breath: the activation
    returns when the manager has started the unit, and the server binds its
    socket when it is ready. That it answers at all is the evidence the operator's
    later verbs have something to act against, and the answer itself is that no
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
                ]
            )
        )
    )
    assert answered["active"] == "active", answered
    assert answered["socket"] == "present", answered
    assert served.members() == [], served.observed["members"]


@pytest.fixture(scope="session")
def credentials(served: Run) -> Run:
    """Phase 2: the operator mints the credential their own node joins with.

    One `planner invite`, against the server this run just applied, whose
    database has never held the group the deployment names: the declared
    generator creates it and reads back the number the database assigned, which
    is what the server's own flag takes. A single-use key admits one node, and
    the operator's machine is not the friend, so the friend's own credential is
    minted in its own phase immediately before it is spent.
    """
    if OPERATOR not in served.credentials:
        served.invite(OPERATOR)
    return served


def test_a_credential_is_minted_by_the_declared_generator(credentials: Run) -> None:
    """The bytes are in the value source, the expiry is the declaration's, neither is printed.

    Minting against a server whose database holds no such group is the whole of
    what says the generator reads the group's number back rather than naming it:
    the server's flag is `--user uint`, so a program handing it a name is
    refused, and this one answered. What the verb printed is where the bytes are
    and what they expire at, and no byte of the key: a verb that printed one
    would put it in a terminal's scrollback and in whatever captures a run.
    """
    written = credentials.source / VALUE
    key = (written / "preauthkey").read_bytes()
    assert key, written
    assert credentials.expiries[OPERATOR] > 0, credentials.expiries

    printed = credentials.observed[f"invited-{OPERATOR}"]
    assert str(written / "preauthkey") in printed, printed
    assert str(credentials.expiries[OPERATOR]) in printed, printed
    assert key.decode() not in printed, "the verb printed the credential"


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
        authkey=credentials.credentials[OPERATOR],
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

    The credential is minted here rather than with the operator's own, because a
    credential expires: the deployment declares how long one admits anybody, and
    a key minted three phases before it is spent would be a key this folder was
    racing. The join itself is taken on that machine by its own owner, over the
    harness's own channel - the handover happens outside this tree and the join
    is the third party's act, not a step of any run. The client is the guest
    image's own daemon, inert until this moment.
    """
    if not unenrolled.observed.get("joined"):
        authkey = unenrolled.invite(FRIEND)
        unenrolled.observed["joined"] = unenrolled.root(
            FRIEND,
            "; ".join(
                [
                    f"tailscale up --login-server {shlex.quote(LOGIN_SERVER)}"
                    f" --authkey {shlex.quote(authkey)}"
                    f" --hostname {shlex.quote(FRIEND)}"
                    " --accept-dns=false --accept-routes=false",
                    "printf 'address=%s\\n' \"$(tailscale ip -4 | head -1)\"",
                    "printf 'state=%s\\n' \"$(tailscale status --peers=false"
                    " | sed -n 's/.*[[:space:]]\\([A-Za-z-]*\\)$/\\1/p' | head -1)\"",
                ]
            ),
        )
        unenrolled.observed["listed"] = str(unenrolled.members())
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

    nodes = joined.members()
    mine = [node for node in nodes if node.get("given_name") == FRIEND]
    assert len(mine) == 1, nodes
    assert f"{mine[0]['given_name']}.{DOMAIN}" == FRIEND_ADDRESS, (mine[0], DOMAIN)
    assert DEPLOYMENT.plan[f"machine:{FRIEND}"]["address"] == FRIEND_ADDRESS
    assert manifest.machine_scope(DEPLOYMENT, FRIEND) == "user"
    # The operator's own node is the other member, and no third one exists.
    assert sorted(node["given_name"] for node in nodes) == sorted((FRIEND, OPERATOR)), nodes


def test_a_membership_act_is_a_verb_of_the_command(joined: Run) -> None:
    """Every act this folder took against the server was a verb of the command.

    Three of them by the time this runs - the mint of the operator's credential,
    the mint of the friend's and the listings read back - and each is a `planner`
    invocation against the deployment the build produced. The other half is what
    is absent: this folder composes no invocation of the coordination server's
    own verbs and installs no copy of its configuration at a host path, so the
    only thing that ever names the server's tool is the program the entry's own
    closure carries, which the deployment's `coordinate` statement names and the
    verbs resolve off the record.
    """
    taken = [argv[0] for argv in joined.verbs]
    assert taken.count("invite") == 2, joined.verbs
    assert taken.count("members") >= 1, joined.verbs
    assert all(argv[1] == str(BUILT) for argv in joined.verbs), joined.verbs

    # No act of this folder is the server's own verb, and no act of it installs a
    # configuration anywhere: both are things the command does or nobody does.
    spoken = [word for argv in joined.verbs for word in argv]
    assert not [word for word in spoken if "headscale" in word], joined.verbs
    assert not [word for word in spoken if "install" in word], joined.verbs

    # What a verb spends is what the build published, resolved against the
    # entry's own closure: the command reproduces no rule of the module's and
    # neither does this file.
    assert COORDINATION is not None
    assert COORDINATION.entry == HUB_KEY
    assert COORDINATION.credential == VALUE
    closure = DEPLOYMENT.plan[HUB_KEY]["closure"]
    assert COORDINATION.program in closure, closure
    assert COORDINATION.configuration in closure, closure
    assert DEPLOYMENT.plan[VALUE]["program"] in closure, closure


def test_a_second_join_with_a_spent_key_is_refused(joined: Run) -> None:
    """The server refuses the second presenter in its own words, and admits nobody.

    Single-use is what makes an intercepted handover visible: the second
    presenter is refused and the first is on the list for the operator to
    inspect. Neither refusal is this tree's - the tree only mints credentials the
    server will refuse twice - so what is asserted is the server's own sentence
    and the list it kept.
    """
    before = joined.members()
    answered = _answered(joined.hub(_presentation(joined.credentials[FRIEND], "second")))
    assert answered["presented"] != "0", answered
    assert "authkey already used" in answered["said"], answered["said"]

    after = joined.members()
    assert [node["id"] for node in after] == [node["id"] for node in before], (before, after)
    assert [node["given_name"] for node in after if node["given_name"] == FRIEND] == [FRIEND]


def test_a_key_past_its_expiry_admits_nobody(joined: Run) -> None:
    """A credential the server has outlived admits nobody, and the server says so.

    The expiry is the deployment's declaration and the verb writes it beside the
    key, so the figure this waits for is read out of the value source rather than
    asked of the server. It is waited on by comparing it against the clock of the
    machine the server runs on, because that is the clock the figure is against,
    and never by sleeping a guess.
    """
    before = joined.members()
    joined.invite("expiring")
    stated = joined.expiries["expiring"]
    answered = _answered(
        joined.hub(
            "; ".join(
                [
                    f"for _ in $(seq 1 {OUTLIVES});"
                    f' do test "$(date -u +%s)" -gt {stated} && break; sleep 1; done',
                    "printf 'clock=%s\\n' \"$(date -u +%s)\"",
                    _presentation(joined.credentials["expiring"], "late"),
                ]
            )
        )
    )
    assert int(answered["clock"]) > stated, (answered["clock"], stated)
    assert answered["presented"] != "0", answered
    assert "authkey expired" in answered["said"], answered["said"]

    after = joined.members()
    assert [node["id"] for node in after] == [node["id"] for node in before], (before, after)
    # A listing may be read back whole because it carries no bearer authority:
    # the server masks a credential it minted, and no key this run holds is in
    # what the verb printed.
    for name, key in joined.credentials.items():
        assert key not in joined.observed["members"], name


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
    """The mesh names the operator's own node currently carries a peer for.

    Read off that node rather than off the server, because what a report can
    reach is a fact about the dialling node's own map of the mesh and not about
    what the server's database says. The client is asked inside the cluster's
    namespace for the reason the node was started there.

    A name is listed here while the peer is on the map at all, expelled or not,
    so this is what the wait below is bounded by and never what an assertion is
    made of: whether the route is gone is the report's own answer, and the
    report is the thing that has to dial.
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
    """Phase 8, last of all: the operator expels the friend machine's node.

    It is last because it takes the wire every phase above it stands on. It is
    one verb of the command taking the identifier the listing verb printed - a
    node is the server's own fact and the registry's name for a machine is not
    the server's name for a node - and what follows is the report reading a
    machine it cannot reach.
    """
    if not applied.observed.get("expelled"):
        nodes = applied.members()
        mine = [node for node in nodes if node.get("given_name") == FRIEND]
        assert len(mine) == 1, nodes
        applied.observed["node"] = str(mine[0]["id"])
        applied.expel(str(mine[0]["id"]))
        applied.observed["after"] = str(applied.members())
        # An expulsion reaches this node when the server hands it a map without
        # that peer in it, which is a moment later than the verb's own answer.
        # Waited on by asking the node, because a report run before the map
        # arrived would read the route that is about to go and say `current`.
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
    nodes = expired.members()
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


def test_no_argument_vector_of_this_run_carried_a_credential(expired: Run) -> None:
    """The bytes reached the two presenters and no invocation of the command.

    Every `planner` invocation this session made is recorded, and the assertion
    is over all of them at once, made last so that the whole session is in
    scope: the mints, the listings, the expulsion, the applies and the reports.
    A credential travels on a step's own output stream into the value source and
    is read from there, so the only argument vectors that carry one are the
    presenters' own, which are the guest's client and this run's node.
    """
    assert expired.credentials, expired.credentials
    spoken = [word for argv in expired.verbs for word in argv]
    for name, key in expired.credentials.items():
        assert key, name
        for word in spoken:
            assert key not in word, f"the credential of {name} is in {word}"
        for observed in expired.observed.values():
            assert key not in observed, f"the credential of {name} is in an observation"
