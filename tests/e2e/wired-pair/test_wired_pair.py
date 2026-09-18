"""Two real machines, one plan, and the wire between them.

``nix run .#planner-e2e wired-pair`` runs this. It builds its own deployment with
``planner build $PLANNER_E2E_FLAKE#planner-e2e-wired-pair``, boots two rookery VMs
from ``$PLANNER_E2E_GUEST_IMAGE``, puts the deployment on the machines its plan
placed the entries on with ``planner apply``, and observes what the two machines
then do. One test per scenario of
``openspec/specs/delivery/real-cluster/spec.md``,
named after it.

The build runs in this process and the apply runs through ``Cluster.run``
(design.md D8): a build needs no cluster, and the machines' addresses resolve
only inside the cluster's net namespace.

**The phases are ordered and the file order is the order.** The requirements are
a state machine, so each test asserts the state it depends on rather than
assuming it:

1. every build is produced by the operator's command, before a machine is dialled
2. the participants are real (nothing has been applied yet)
3. the whole deployment is applied by one command (the ``delivered`` fixture)
4. the receiving machine evaluated nothing and can reach no other store
5. the wire is traffic, and cutting it is visible - which restores it afterwards
6. an unchanged re-apply is a no-op, a changed one is generation 2, a rollback
   returns generation 1
7. both machines reboot, and the entries come back without a second apply
8. a run broken between the two machines, and the second run that finishes it -
   which restores the route it cut
9. the build that names ``sweep`` no longer, reported and then applied without
   being asked to retire, so the machine still runs what no build names
10. the same build applied with ``--retire``, which takes the holding away with
    the endpoint's own removal verb and deletes nothing the job wrote
11. the build whose probe the page does not answer, which the endpoint rolls
    back, and then the build whose probe it does

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake
(design.md D2), so the module skips itself when it is absent - and
`mypy --strict` type-checks it without rookery present (treefmt.nix). The two
machines are a ``@cluster_snapshot_fixture`` stage: the first run boots and cuts
them, every later run resumes the cut, and the apply phases below still run
against the machines every time.
"""

from __future__ import annotations

import itertools
import json
import os
import re
import shlex
import subprocess
from collections.abc import Iterator, Sequence
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest

import delivery

snapshot = pytest.importorskip(
    "rookery.snapshot",
    reason='rookery is not importable: run .#planner-e2e, or eval "$(planner-e2e-env)"',
)
snapshot_cache = pytest.importorskip("rookery.snapshot.cache")
snapshot_lineage = pytest.importorskip("rookery.snapshot.lineage")


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


CLI = _env_path("PLANNER_CLI")
FLAKE = _env_path("PLANNER_E2E_FLAKE")
SOURCE = _env_path("PLANNER_WIRED_PAIR_DEPLOYMENT")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))

# Imported below the skip: the command's source root is on the import path only
# for a run that names the command at all.
import manifest  # noqa: E402
import remote  # noqa: E402
import report  # noqa: E402

SERVER_ENTRY = "site:server"
SERVER_KEY = "site:server@alpha"
CLIENT_KEY = "check:client@beta"
SWEEP_KEY = "sweep:job@alpha"
KEYS = (SERVER_KEY, CLIENT_KEY, SWEEP_KEY)
SERVER_MACHINE = "alpha"
CLIENT_MACHINE = "beta"
SERVER_UNIT = "site-server-serve.service"
CLIENT_UNIT = "check-client-fetch.service"
SWEEP_UNIT = "sweep-job-rotate.service"
SWEEP_TIMER = "sweep-job-rotate.timer"
STORE_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-[^\s\"']+")
MACHINES = (SERVER_MACHINE, CLIENT_MACHINE)


def _built(attribute: str) -> tuple[manifest.Deployment, tuple[str, ...]]:
    """Build one deployment with the operator's command and read what it wrote.

    Args:
        attribute: The flake attribute of one build of this folder's deployment.

    Returns:
        The built deployment, read the way the command reads it, and the step
        lines the build printed under the store path.

    Raises:
        RuntimeError: If the build failed, carrying the command's own output.
    """
    reference = f"{FLAKE}#{attribute}"
    built = subprocess.run(
        [str(CLI), "build", reference], capture_output=True, text=True, check=False
    )
    if built.returncode != 0 or not built.stdout.strip():
        raise RuntimeError(f"planner build {reference} produced nothing:\n{built.stderr.strip()}")
    reported = built.stdout.splitlines()
    return manifest.read(Path(reported[0])), tuple(reported[1:])


BUILT, BUILD_LOG = _built("planner-e2e-wired-pair")
CHANGED, CHANGED_LOG = _built("planner-e2e-wired-pair-changed")
# The three builds the phases at the end of the file are about, produced here
# with the other two because a build needs no cluster: `retired` is the
# folder's instances minus `sweep`, and the two probed builds differ in the one
# request their probe fetches.
RETIRED = _built("planner-e2e-wired-pair-retired")[0]
PROBED = _built("planner-e2e-wired-pair-probed")[0]
HEALTHY = _built("planner-e2e-wired-pair-healthy")[0]


def _output_of(key: str, unit: str) -> str:
    """The path one unit of the built plan is told to write, read off the plan.

    The module derives it from the identity of its own entry, so the path a
    machine will look at is the plan's rather than a convention restated here.
    """
    command = str(BUILT.plan[key]["units"][unit]["command"])
    found = re.search(r"--output (\S+)", command)
    assert found is not None, command
    return found.group(1)


def _touched_by(key: str, unit: str) -> str:
    """The path one unit of the built plan touches, which its command ends in."""
    command = str(BUILT.plan[key]["units"][unit]["command"])
    return command.split()[-1]


RECORD_PATH = _output_of(CLIENT_KEY, "fetch")
SWEEP_MARKER = _touched_by(SWEEP_KEY, "rotate")


def _probe_unit(deployment: manifest.Deployment) -> str:
    """The unit file a probed build derived for the served entry, read off the build.

    Derived rather than written out: the name is the realiser's own derivation
    off the artifact's service name, so the entry's unit list is where it is
    known.
    """
    derived = [unit for unit in deployment.entries[SERVER_KEY].units if unit != SERVER_UNIT]
    assert len(derived) == 1, deployment.entries[SERVER_KEY].units
    return derived[0]


PROBE_UNIT = _probe_unit(PROBED)


@dataclass
class Run:
    """The cluster, the two builds, and what each phase observed."""

    cluster: Any
    resumed: dict[str, bool]
    source: Path
    built: manifest.Deployment
    build_log: tuple[str, ...]
    changed: manifest.Deployment
    changed_log: tuple[str, ...]
    key: Path
    plan: dict[str, Any]
    observed: dict[str, Any] = field(default_factory=dict)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def artifact(self, key: str, *, of: manifest.Deployment | None = None) -> Path:
        """The artifact a build produced for one plan key, as its own manifest records it."""
        return manifest.artifact_of((self.built if of is None else of).entries[key])

    def unit_text(self, artifact: Path) -> str:
        units = sorted((artifact / "units").iterdir())
        assert len(units) == 1, units
        return units[0].read_text()

    def page_text(self, artifact: Path) -> str:
        """What the producer's delivered unit actually serves, read from its own root."""
        served = re.search(r"--directory (\S+)", self.unit_text(artifact))
        assert served is not None, self.unit_text(artifact)
        return (Path(served.group(1)) / "index.html").read_text()


def _command(run: Run, *argv: str) -> tuple[str, ...]:
    """Run one subcommand of the operator's command inside the cluster.

    The machines' addresses exist only in the cluster's net namespace, and
    ``Cluster.run`` replaces the environment rather than extending it, so the
    caller's own is carried through with the ssh options a throwaway guest is
    reached with.

    Args:
        run: The run whose cluster and credential to use.
        argv: The command's arguments, subcommand first.

    Returns:
        The lines the command printed on stdout.
    """
    done = run.cluster.run([str(CLI), *argv], env=delivery.command_env(dict(os.environ), run.key))
    return tuple(done.stdout.splitlines())


def _reported(vm: Any, service: str) -> dict[str, Any]:
    """What a machine's own endpoint says about one entry it registered.

    Several claims below are about the machine's own record rather than about
    what the command printed, so they are read off the endpoint directly.

    Args:
        vm: The machine to ask.
        service: The name the endpoint registered the entry under.

    Returns:
        The endpoint's first record for that entry, which is the whole of what
        it reports for one name.
    """
    registered = json.loads(vm.ssh_succeed(f"flakelet status --json {shlex.quote(service)}"))
    assert registered, f"the endpoint reports no entry named {service}"
    record = registered[0]
    assert isinstance(record, dict), registered
    return record


def _activation(log: Sequence[str], key: str) -> str:
    """The endpoint's own report for one entry, out of an apply log.

    Args:
        log: The step lines one apply printed.
        key: The plan key whose activation to read.

    Returns:
        The indented report lines under that entry's activation, unindented. The
        last activation of the key is the one read, so a re-apply's report is.
    """
    activations = [index for index, line in enumerate(log) if line.startswith(f"activate {key} ")]
    assert activations, log
    under = itertools.takewhile(lambda line: line.startswith("  "), log[activations[-1] + 1 :])
    return "\n".join(line.strip() for line in under)


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=MACHINES, key=KEY)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage every run starts from: two machines, up and usable.

    On a cache hit this body does not run at all - the machines are resumed from
    the cut it took the first time - so nothing here may be a fact a test reads.
    It waits, and yields.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def run(booted: Any) -> Run:
    """Two machines named as the plan names them, obtained once for the whole run."""
    return Run(
        cluster=booted.cluster,
        resumed=dict(booted.resumed),
        source=SOURCE,
        built=BUILT,
        build_log=BUILD_LOG,
        changed=CHANGED,
        changed_log=CHANGED_LOG,
        key=KEY,
        plan=dict(BUILT.plan),
    )


@pytest.fixture(scope="session")
def delivered(run: Run) -> Run:
    """Phase 3: the whole deployment applied by one run of the operator's command.

    The command orders the steps itself, so the fixture states none of them. It
    waits afterwards for the producer to be listening before the consumer's own
    unit is up, so the consumer's first fetch is a fetch and not a retry.
    """
    if run.observed.get("applied"):
        return run

    applied = _command(run, "apply", str(run.built.root))
    server = run.vm(SERVER_MACHINE)
    port = run.plan[SERVER_KEY]["alloc"]["ports"]["http"]
    server.wait_for_unit(SERVER_UNIT, timeout=120)
    server.wait_until_succeeds(f"ss -ltn | grep -q ':{port}'", timeout=60)
    run.vm(CLIENT_MACHINE).wait_for_unit(CLIENT_UNIT, timeout=120)

    run.observed["applied"] = applied
    return run


def test_every_participant_is_the_real_one(run: Run) -> None:
    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        vm = run.vm(machine)
        assert vm.ssh_succeed("uname -r").strip()
        assert vm.ssh_succeed("systemctl is-active sshd.service").strip() == "active"
        assert vm.ssh_succeed("systemctl is-system-running --wait").strip() in {
            "running",
            "degraded",
        }
        assert (
            vm.ssh_succeed("readlink -f $(command -v flakelet)").strip().startswith("/nix/store/")
        )
        assert "systemd" in vm.ssh_succeed("systemctl --version")


def _store_root(path: str) -> str:
    """Return the store object a path names, dropping any path inside it."""
    return "/".join(path.split("/")[:4])


def test_the_machines_are_not_told_the_answer(run: Run) -> None:
    address = run.plan[f"machine:{SERVER_MACHINE}"]["address"]
    contributed_anywhere: list[str] = []
    for key in (SERVER_KEY, CLIENT_KEY):
        entry = run.built.entries[key]
        vm = run.vm(entry.machine)
        artifact = manifest.artifact_of(entry)
        assert vm.ssh(f"nix-store --check-validity {artifact}").returncode != 0
        for unit in sorted((artifact / "units").iterdir()):
            assert vm.ssh(f"nix-store --check-validity {unit.resolve()}").returncode != 0
        own = set(vm.ssh_succeed("nix-store -qR /run/current-system").split())
        named = sorted({_store_root(path) for path in STORE_PATH.findall(run.unit_text(artifact))})
        assert named, run.unit_text(artifact)
        for path in named:
            valid = vm.ssh(f"nix-store --check-validity {path}").returncode == 0
            assert valid == (path in own), path
            if path not in own:
                contributed_anywhere.append(path)
        config = json.loads(vm.ssh_succeed("cat /etc/flakelet/config.json"))
        assert config.get("services", {}) == {}, config
    assert contributed_anywhere
    declaring = [path for path in sorted(run.source.rglob("*.nix")) if address in path.read_text()]
    assert [path.name for path in declaring] == ["machines.nix"], declaring


def test_a_prepared_cluster_is_cached_for_the_next_run(run: Run) -> None:
    """The machines were resumed, or the cut they were prepared into is now cached.

    A whole-cluster cut is all-or-nothing, so the two machines report one state
    between them, and whichever state it is, the cut exists afterwards: that is
    what makes the next run a resume.
    """
    assert sorted(run.resumed) == sorted(MACHINES), run.resumed
    assert len(set(run.resumed.values())) == 1, run.resumed
    assert delivery.cut_is_cached(
        booted,
        lineage=snapshot_lineage,
        cache=snapshot_cache,
        slots=len(MACHINES),
    ), "the stage's cut was neither resumed from nor published to the cache"


def test_a_resumed_machine_is_usable_at_once(run: Run) -> None:
    """A cut taken at "sshd answers" would resume a guest with no login PATH yet."""
    for machine in MACHINES:
        vm = run.vm(machine)
        assert vm.ssh_succeed("systemctl is-active multi-user.target").strip() == "active"
        assert vm.ssh_succeed("command -v cat").strip().startswith("/")
        assert vm.ssh_succeed("id -un").strip() == "root"


def test_a_resumed_machine_holds_the_address_its_slot_was_cut_with(run: Run) -> None:
    """A machine's address is frozen into its slot's RAM, so it must still be the plan's."""
    for machine in MACHINES:
        vm = run.vm(machine)
        address = run.plan[f"machine:{machine}"]["address"]
        assert vm.name == machine
        assert vm.ip == address
        held = vm.ssh_succeed("ip -4 -o addr show scope global")
        assert f"{address}/" in held, held


def test_the_machines_are_reached_with_the_key_the_image_carries(run: Run) -> None:
    """Both channels are authorized by the image's key, and no password is accepted.

    Every ``ssh_succeed`` in this file rides the control channel, which is
    authenticated with this key; the copy the command makes rides the machine's
    own sshd on the cluster LAN, which is dialled here with the same key.
    """
    public = subprocess.run(
        ["ssh-keygen", "-y", "-f", str(run.key)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split()[:2]

    for machine in MACHINES:
        vm = run.vm(machine)
        authorized = vm.ssh_succeed("cat /etc/ssh/authorized_keys.d/root").split()
        assert authorized[:2] == public, authorized
        refused = vm.ssh_succeed("grep -i '^PasswordAuthentication' /etc/ssh/sshd_config")
        assert refused.split()[-1].lower() == "no", refused

    address = run.plan[f"machine:{SERVER_MACHINE}"]["address"]
    run.cluster.run(
        ["ssh", *shlex.split(delivery.guest_ssh_options(run.key)), f"root@{address}", "true"],
        env=delivery.command_env(dict(os.environ), run.key),
    )


def test_no_host_directory_is_mounted_in_a_machine(run: Run) -> None:
    """A share cannot survive a cut, so a snapshotted guest mounts none."""
    for machine in MACHINES:
        mounted = run.vm(machine).ssh_succeed("cat /proc/mounts")
        assert "virtiofs" not in mounted, mounted


def test_a_cut_carries_no_delivery(run: Run) -> None:
    """Freshly obtained machines hold no entry, however they were obtained."""
    for machine in MACHINES:
        vm = run.vm(machine)
        assert json.loads(vm.ssh_succeed("flakelet status --json")) == []
        for key in KEYS:
            assert vm.ssh(f"nix-store --check-validity {run.artifact(key)}").returncode != 0


def test_the_machine_holds_what_the_artifact_names(delivered: Run) -> None:
    for key in (SERVER_KEY, CLIENT_KEY):
        entry = delivered.built.entries[key]
        artifact = manifest.artifact_of(entry)
        vm = delivered.vm(entry.machine)
        assert vm.ssh_succeed(f"nix-store --check-validity {artifact} && echo ok").strip() == "ok"
        named = sorted(set(STORE_PATH.findall(delivered.unit_text(artifact))))
        assert named, delivered.unit_text(artifact)
        for path in named:
            assert vm.ssh_succeed(f"nix-store --check-validity {path} && echo ok").strip() == "ok"
    other = delivered.vm(CLIENT_MACHINE)
    assert other.ssh(f"nix-store --check-validity {delivered.artifact(SERVER_KEY)}").returncode != 0


def test_the_artifacts_were_built_by_the_operators_command(delivered: Run) -> None:
    """Every artifact a machine holds is the one the build produced for that key.

    Three readings of one path have to agree: the manifest the build wrote, the
    copy step the apply printed, and the store of the machine the entry is placed
    on. The folder contributes none of them. That it holds no builder of its own
    is asserted from outside, by `testAnEndToEndFolderHoldsABuilderOfItsOwn`: a
    scan written here would match its own needles.
    """
    applied = delivered.observed["applied"]
    for key in KEYS:
        entry = delivered.built.entries[key]
        artifact = manifest.artifact_of(entry)
        described = (
            f"{key} {entry.realiser} {entry.machine} {entry.address} {artifact} "
            f"[{' '.join(entry.units)}]"
        )
        assert described in delivered.build_log, delivered.build_log
        assert f"copy {key} {artifact} -> root@{entry.address}" in applied, applied
        vm = delivered.vm(entry.machine)
        assert vm.ssh_succeed(f"nix-store --check-validity {artifact} && echo ok").strip() == "ok"


def test_the_plan_names_the_address(delivered: Run) -> None:
    applied = delivered.observed["applied"]
    for key, machine in ((SERVER_KEY, SERVER_MACHINE), (CLIENT_KEY, CLIENT_MACHINE)):
        address = delivered.plan[f"machine:{machine}"]["address"]
        assert f"copy {key} {delivered.artifact(key)} -> root@{address}" in applied, applied
        assert f"activate {key} (flakelet) on root@{address}" in applied, applied


def test_an_entry_is_not_delivered_to_a_machine_it_was_not_placed_on(delivered: Run) -> None:
    with pytest.raises(delivery.DeliveryError) as raised:
        delivery.placed_key(delivered.plan, SERVER_ENTRY, CLIENT_MACHINE)
    message = str(raised.value)
    assert SERVER_ENTRY in message
    assert CLIENT_MACHINE in message
    assert SERVER_MACHINE in message
    other = delivered.vm(CLIENT_MACHINE)
    assert other.ssh(f"nix-store --check-validity {delivered.artifact(SERVER_KEY)}").returncode != 0


def test_the_unit_runs_from_the_delivered_directory(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    assert server.ssh_succeed(f"systemctl is-active {SERVER_UNIT}").strip() == "active"
    reported = _reported(server, delivery.service_name(delivered.artifact(SERVER_KEY)))
    record = delivery.record_of(delivered.built.root)
    assert reported["locked_url"] == delivery.locked_url(record, SERVER_KEY), reported
    assert reported["generation"] == 1, reported
    assert reported["last_error"] is None, reported
    assert SERVER_UNIT in reported["units"], reported


def test_no_evaluation_happens_on_the_machine(delivered: Run) -> None:
    report_lines = _activation(delivered.observed["applied"], SERVER_KEY)
    assert "using prebuilt artifact" in report_lines, report_lines
    assert "resolving" not in report_lines, report_lines
    assert "building" not in report_lines, report_lines


# The cluster's dnsmasq has no upstream, so no external name and no substituter
# resolves. Being offline is a property of the network, not luck.
def test_no_store_but_the_machines_own_is_reachable(delivered: Run) -> None:
    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        vm = delivered.vm(machine)
        assert vm.ssh("getent hosts cache.nixos.org").returncode != 0
        assert vm.ssh("timeout 5 nix-store --realise /nix/store/nonexistent").returncode != 0


def test_the_consumer_reaches_the_producer(delivered: Run) -> None:
    client = delivered.vm(CLIENT_MACHINE)
    assert client.ssh_succeed(f"systemctl is-active {CLIENT_UNIT}").strip() == "active"
    body = client.ssh_succeed(f"cat {RECORD_PATH}")
    assert body == delivered.page_text(delivered.artifact(SERVER_KEY)), body


def test_the_address_used_is_the_address_the_plan_recorded(delivered: Run) -> None:
    address = delivered.plan[f"machine:{SERVER_MACHINE}"]["address"]
    exported = delivered.plan[SERVER_KEY]["provides"]["page"]["exports"]["url"]["value"]
    assert address in exported
    unit = delivered.vm(CLIENT_MACHINE).ssh_succeed(
        f"systemctl cat {CLIENT_UNIT} | grep ^ExecStart="
    )
    assert exported in unit, unit
    held = delivered.vm(SERVER_MACHINE).ssh_succeed("ip -4 -o addr show scope global")
    assert address in held, held


def test_neither_end_was_told_the_address_by_the_harness(delivered: Run) -> None:
    address = delivered.plan[f"machine:{SERVER_MACHINE}"]["address"]
    declaring = [
        path.relative_to(delivered.source)
        for path in sorted(delivered.source.rglob("*"))
        if path.is_file() and address in path.read_text()
    ]
    assert [str(path) for path in declaring] == ["machines.nix"], declaring
    assert delivered.plan[SERVER_KEY]["target"]["address"] == address


def test_the_allocated_port_is_the_listening_port(delivered: Run) -> None:
    port = delivered.plan[SERVER_KEY]["alloc"]["ports"]["http"]
    listening = delivered.vm(SERVER_MACHINE).ssh_succeed("ss -ltnH")
    assert f":{port}" in listening, listening
    assert f":{port}" not in delivered.vm(CLIENT_MACHINE).ssh_succeed("ss -ltnH")


def test_cutting_the_wires_far_end_is_visible(delivered: Run) -> None:
    address = delivered.plan[f"machine:{SERVER_MACHINE}"]["address"]
    server = delivered.vm(SERVER_MACHINE)
    client = delivered.vm(CLIENT_MACHINE)

    server.ssh_succeed(f"systemctl stop {SERVER_UNIT}")
    failed = client.ssh(f"systemctl restart {CLIENT_UNIT}")
    assert failed.returncode != 0, failed
    journal = client.ssh_succeed(f"journalctl -u {CLIENT_UNIT} --no-pager -n 20")
    assert address in journal, journal

    # Restores the wire for the phases after this one. These tests share one session
    # and run in order.
    server.ssh_succeed(f"systemctl start {SERVER_UNIT}")
    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)


def test_a_report_against_a_build_the_machine_does_not_hold_says_so(delivered: Run) -> None:
    """The machines hold the first build here, and the second build's report says so.

    The phases after this one deliver the changed entry, so at this point the
    two builds differ in exactly the way an interrupted apply leaves a fleet:
    the entry is applied, from another build. The report has to tell that apart
    from an entry the machine holds and from one it does not hold at all.
    """
    entry = delivered.built.entries[SERVER_KEY]
    changed = delivered.changed.entries[SERVER_KEY]
    service = delivery.service_name(manifest.artifact_of(entry))
    own = _reported(delivered.vm(entry.machine), service)

    against = _command(delivered, "status", str(delivered.changed.root), "--only", SERVER_KEY)

    assert _built_units(changed) != _built_units(entry), changed.path
    assert against == (
        f"{SERVER_KEY} {entry.realiser} generation {own['generation']} of "
        f"{own['locked_url']} runs units this build did not produce",
    ), against


def test_an_unchanged_entry_is_a_no_op(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    service = delivery.service_name(delivered.artifact(SERVER_KEY))
    before = server.ssh_succeed(f"systemctl show -P MainPID {SERVER_UNIT}").strip()

    _command(delivered, "apply", str(delivered.built.root), "--only", SERVER_KEY)

    assert _reported(server, service)["generation"] == 1
    assert server.ssh_succeed(f"systemctl show -P MainPID {SERVER_UNIT}").strip() == before


def test_a_changed_entry_is_a_new_generation(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    client = delivered.vm(CLIENT_MACHINE)
    changed = delivered.artifact(SERVER_KEY, of=delivered.changed)
    service = delivery.service_name(changed)
    assert service == delivery.service_name(delivered.artifact(SERVER_KEY))

    applied = _command(delivered, "apply", str(delivered.changed.root), "--only", SERVER_KEY)
    assert any(str(changed) in line for line in delivered.changed_log), delivered.changed_log
    assert f"copy {SERVER_KEY} {changed} -> root@{server.ip}" in applied, applied
    reported = _activation(applied, SERVER_KEY)
    assert "generation 2" in reported, reported
    assert _reported(server, service)["generation"] == 2

    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == delivered.page_text(changed)


def test_rollback_returns_the_previous_generation(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    client = delivered.vm(CLIENT_MACHINE)
    service = delivery.service_name(delivered.artifact(SERVER_KEY))

    rolled = _command(delivered, "rollback", str(delivered.built.root), "--only", SERVER_KEY)
    delivered.observed["rolled_back"] = rolled
    assert any("generation 1" in line for line in rolled), rolled
    assert _reported(server, service)["generation"] == 1

    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == delivered.page_text(
        delivered.artifact(SERVER_KEY)
    )


def test_the_endpoint_reports_what_the_rollback_came_from(delivered: Run) -> None:
    """The endpoint's own record says the change was a rollback, and from where.

    Read back off the machine rather than inferred from the generation number: a
    rollback to 1 and a redelivery of the older content both leave generation 1,
    and only the record tells a machine's history which of the two happened.
    """
    server = delivered.vm(SERVER_MACHINE)
    status = _reported(server, delivery.service_name(delivered.artifact(SERVER_KEY)))

    assert status["generation"] == 1, status
    assert status["changed"]["by"] == {"kind": "rollback", "from": 2}, status


def test_the_command_rolls_one_entry_back(delivered: Run) -> None:
    """One command returned the machine to its previous generation and said so.

    The rollback itself happened in the phase above, which is where the ordered
    file puts it; what is asserted here is its two halves. The machine's own
    record is the evidence for the first, because a rollback to generation 1 and
    a re-apply of the older artifact both leave generation 1 behind.
    """
    server = delivered.vm(SERVER_MACHINE)
    rolled = delivered.observed["rolled_back"]
    address = delivered.plan[f"machine:{SERVER_MACHINE}"]["address"]
    record = _reported(server, delivery.service_name(delivered.artifact(SERVER_KEY)))

    assert rolled[0] == f"rollback {SERVER_KEY} on root@{address}", rolled
    assert any("generation 1" in line for line in rolled[1:]), rolled
    assert record["changed"]["by"] == {"kind": "rollback", "from": 2}, record
    assert server.ssh_succeed(f"systemctl is-active {SERVER_UNIT}").strip() == "active"
    body = delivered.vm(CLIENT_MACHINE).ssh_succeed(f"cat {RECORD_PATH}")
    assert body == delivered.page_text(delivered.artifact(SERVER_KEY)), body


def _built_units(entry: manifest.Entry) -> dict[str, str]:
    """The unit files the build produced for one entry, as its machine reports them."""
    artifact = manifest.artifact_of(entry)
    return {unit: str((artifact / "units" / unit).resolve()) for unit in entry.units}


def test_the_command_reports_what_a_machine_holds(delivered: Run) -> None:
    """`planner status` answers with each machine's own endpoint report.

    Every entry is applied at this point in the ordered phases, and its line has
    to be what that entry's own machine says about it, with the verdict of
    comparing that answer with the build the report was run against.
    """
    entries = [delivered.built.entries[key] for key in KEYS]
    holds = _command(delivered, "status", str(delivered.built.root))

    for entry in entries:
        own = _reported(
            delivered.vm(entry.machine), delivery.service_name(manifest.artifact_of(entry))
        )
        line = (
            f"{entry.key} {entry.realiser} generation {own['generation']} of "
            f"{own['locked_url']} runs this build's units"
        )
        assert line in holds, holds
        assert own["units"] == _built_units(entry), own


def test_an_entry_the_endpoint_does_not_register_is_reported_as_absent(delivered: Run) -> None:
    """Absence is an endpoint's own answer, so it is read off a machine that answered.

    It cannot be obtained from ``planner status`` here without unapplying an
    entry the phases after this one still read, so it is obtained from a machine
    that genuinely registers no such service - the consumer's, asked for the
    producer's entry - through the command's own script and the command's own
    reading of what came back. The endpoint refuses a name it holds nothing
    under with a status of its own, which is what tells this apart from a
    machine carrying no endpoint at all.
    """
    producer = delivered.built.entries[SERVER_KEY]
    asked = delivered.vm(CLIENT_MACHINE).ssh(
        remote.flakelet_status_script(delivery.service_name(manifest.artifact_of(producer)))
    )

    assert asked.returncode != 0, asked
    assert asked.returncode not in (*remote.MISSING, remote.UNREACHABLE), asked
    answer = remote.Answer(asked.returncode, asked.stderr.strip())
    assert report._answered(producer, answer) == "absent", asked


def test_the_identity_a_machine_holds_is_in_its_report_line(delivered: Run) -> None:
    """The line is the endpoint's own record, and the verdict is over that record.

    Read back off the machine and compared with what the command printed, so
    what is asserted is that the report answers with the endpoint's answer
    rather than with anything the deployment record states. The endpoint names
    no identity for the artifact it activated, so the verdict is over the unit
    files it does name, and the line says which comparison that was.
    """
    entry = delivered.built.entries[SERVER_KEY]
    own = _reported(delivered.vm(entry.machine), delivery.service_name(manifest.artifact_of(entry)))

    reported = _command(delivered, "status", str(delivered.built.root), "--only", entry.key)

    assert reported == (
        f"{entry.key} {entry.realiser} generation {own['generation']} of "
        f"{own['locked_url']} runs this build's units",
    ), reported
    assert own["last_error"] is None, own


def test_a_scheduled_unit_is_not_fired_by_deploying_it(delivered: Run) -> None:
    """Applying a scheduled entry installs a trigger, not a run."""
    server = delivered.vm(SERVER_MACHINE)
    service = delivery.service_name(delivered.artifact(SWEEP_KEY))

    assert _reported(server, service)["generation"] >= 1
    started = server.ssh_succeed(f"systemctl show -p ExecMainStartTimestamp {SWEEP_UNIT}")
    assert started.strip() == "ExecMainStartTimestamp=", started
    # An inactive unit reports itself with exit status 3, so this asks over plain ssh
    # rather than through the succeed helper.
    assert server.ssh(f"systemctl is-active {SWEEP_UNIT}").stdout.strip() == "inactive"
    assert server.ssh(f"test -e {SWEEP_MARKER}").returncode != 0


def test_the_timer_the_schedule_declares_is_enabled(delivered: Run) -> None:
    """The trigger is armed, elapses in the future, and names the entry's service."""
    server = delivered.vm(SERVER_MACHINE)

    assert server.ssh_succeed(f"systemctl is-active {SWEEP_TIMER}").strip() == "active"
    assert server.ssh_succeed(f"systemctl show -P Unit {SWEEP_TIMER}").strip() == SWEEP_UNIT

    listed = server.ssh_succeed("systemctl list-timers --all --no-pager")
    assert SWEEP_TIMER in listed, listed
    left = server.ssh_succeed(f"systemctl show -P NextElapseUSecRealtime {SWEEP_TIMER}").strip()
    assert left not in {"", "0", "n/a"}, listed


def test_a_reboot_brings_the_entries_back(delivered: Run) -> None:
    # Rebooted from inside the guest: a claim about the service manager needs it to
    # bring the machine down itself.
    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        delivered.vm(machine).ssh("systemctl reboot", timeout=30)

    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        vm = delivered.vm(machine)
        vm.wait_for_ssh(timeout=300)
        vm.wait_for_network(timeout=300)

    delivered.vm(SERVER_MACHINE).wait_for_unit(SERVER_UNIT, timeout=180)
    delivered.vm(CLIENT_MACHINE).wait_for_unit(CLIENT_UNIT, timeout=180)

    client = delivered.vm(CLIENT_MACHINE)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == delivered.page_text(
        delivered.artifact(SERVER_KEY)
    )


def test_a_reconcile_leaves_a_hand_activated_entry_alone(delivered: Run) -> None:
    for key, unit in ((SERVER_KEY, SERVER_UNIT), (CLIENT_KEY, CLIENT_UNIT)):
        entry = delivered.built.entries[key]
        vm = delivered.vm(entry.machine)
        service = delivery.service_name(manifest.artifact_of(entry))
        assert json.loads(vm.ssh_succeed("cat /etc/flakelet/config.json")).get("services") == {}
        vm.ssh_succeed("systemctl restart flakelet-reconcile.service", timeout=120)
        assert _reported(vm, service)["generation"] >= 1
        assert vm.ssh_succeed(f"systemctl is-active {unit}").strip() == "active"


def test_the_endpoint_reports_the_identity_the_build_published(delivered: Run) -> None:
    """What a machine holds for an entry carries the identity the build published.

    The point of publishing the artifact's own digest rather than the plan entry
    key is that the two sides can be compared, so this reads both. The endpoint
    names the plan key it registered the entry under, and the artifact it holds
    at that path carries the digest, which the endpoint's own status does not
    report - which is why the command's own verdict, asserted last, is over the
    unit files that status does carry rather than over this digest. The phases
    above applied, re-applied and rolled back, so what each machine holds here
    is the first build's artifact again.
    """
    record = delivery.record_of(delivered.built.root)
    published = record["entries"]
    holds = _command(delivered, "status", str(delivered.built.root))

    for key in (SERVER_KEY, CLIENT_KEY):
        entry = delivered.built.entries[key]
        vm = delivered.vm(entry.machine)
        reported = _reported(vm, delivery.service_name(manifest.artifact_of(entry)))
        assert reported["locked_url"] == delivery.locked_url(record, key), reported
        held = json.loads(vm.ssh_succeed(f"cat {manifest.artifact_of(entry)}/meta.json"))
        assert held["settings_hash"] == published[key]["key"], (held, published[key])
        assert published[key]["key"] != delivered.plan[key]["key"], published[key]
        assert "settings_hash" not in reported, reported
        line = [text for text in holds if text.startswith(f"{key} ")]
        assert line == [
            f"{key} {entry.realiser} generation {reported['generation']} of "
            f"{reported['locked_url']} runs this build's units"
        ], holds


def _apply_however_it_ends(run: Run, *argv: str) -> tuple[int, list[str]]:
    """Apply inside the cluster and keep the exit status, however the run ends.

    ``Cluster.run`` is for commands that succeed, and the subject of this phase
    is one that does not, so the command runs under a shell that reports its
    status instead of passing it on. The two streams are merged because the
    refusal is printed on standard error and the step log on standard output,
    and the claim is about the order of the two.

    Args:
        run: The run whose cluster and credential to use.
        argv: The arguments after `apply`.

    Returns:
        The command's exit status and the lines it printed.
    """
    quoted = shlex.join([str(CLI), "apply", *argv])
    done = run.cluster.run(
        ["sh", "-c", f"{quoted} 2>&1; echo exit=$?"],
        env=delivery.command_env(dict(os.environ), run.key),
    )
    printed = done.stdout.splitlines()
    return int(printed[-1].removeprefix("exit=")), printed[:-1]


@pytest.fixture(scope="session")
def interrupted(delivered: Run) -> Run:
    """Phase 8: the route to the consumer's machine cut, and the run that breaks on it.

    The route is cut before the run starts rather than raced against it from a
    second thread, so the break is deterministic: the run reaches the producer's
    machine and fails on the consumer's. What is cut is the delivery channel -
    the TCP listener the plan's addresses reach - and the channel this fixture
    drives the guest over is the vsock one, so the route can be restored
    afterwards, which it is.

    Both readings of the consumer's own endpoint are taken here, before the cut
    and after the broken run, so what the machine held is compared with what it
    holds whatever any later phase does.
    """
    if delivered.observed.get("interrupted"):
        return delivered

    client = delivered.vm(CLIENT_MACHINE)
    service = delivery.service_name(delivered.artifact(CLIENT_KEY))
    before = _reported(client, service)

    client.ssh_succeed("systemctl stop sshd.service")
    try:
        status, printed = _apply_however_it_ends(delivered, str(delivered.built.root))
    finally:
        client.ssh_succeed("systemctl start sshd.service")

    delivered.observed["interrupted"] = printed
    delivered.observed["interrupted_status"] = status
    delivered.observed["client_before"] = before
    delivered.observed["client_after"] = _reported(client, service)
    return delivered


def test_a_run_broken_between_two_machines_names_the_step_that_broke(
    interrupted: Run,
) -> None:
    """The last step line is the step that was running, and the failure names it."""
    printed: list[str] = interrupted.observed["interrupted"]
    consumer = interrupted.built.entries[CLIENT_KEY]
    reached = interrupted.plan[f"machine:{CLIENT_MACHINE}"]["address"]
    serving = interrupted.plan[f"machine:{SERVER_MACHINE}"]["address"]
    steps = [line for line in printed if line.startswith(("value ", "copy ", "activate "))]

    assert interrupted.observed["interrupted_status"] != 0, printed
    assert f"activate {SERVER_KEY} (flakelet) on root@{serving}" in steps, printed
    assert steps[-1] == f"copy {CLIENT_KEY} {consumer.path} -> root@{reached}", printed

    failed = [line for line in printed if line.startswith("failed ")]
    assert len(failed) == 1, printed
    assert CLIENT_KEY in failed[0], failed
    assert reached in failed[0], failed
    assert "Traceback" not in "\n".join(printed), printed


def test_a_second_run_finishes_what_the_broken_run_left(interrupted: Run) -> None:
    """The recovery is another apply of the same build: every step it repeats is cheap."""
    consumer = interrupted.built.entries[CLIENT_KEY]
    client = interrupted.vm(CLIENT_MACHINE)

    applied = _command(interrupted, "apply", str(interrupted.built.root))

    assert f"copy {CLIENT_KEY} {consumer.path} -> root@{consumer.address}" in applied, applied
    assert f"activate {CLIENT_KEY} (flakelet) on root@{consumer.address}" in applied, applied
    assert [line for line in applied if line.startswith("failed ")] == [], applied

    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == interrupted.page_text(
        interrupted.artifact(SERVER_KEY)
    )


def test_a_machine_the_broken_run_never_reached_holds_what_it_held_before(
    interrupted: Run,
) -> None:
    """A run that stopped at one machine left the machines after it untouched."""
    before = interrupted.observed["client_before"]
    after = interrupted.observed["client_after"]

    assert after == before, (before, after)
    assert after["last_error"] is None, after


def _observed(vm: Any, *commands: str, timeout: int = 180) -> dict[str, str]:
    """Run one ssh command on one machine and read back its ``key=value`` lines.

    One case is one login: the guest's sshd is per-connection socket activated,
    so a burst of short logins is answered by the socket's own trigger limit
    rather than by the machine, and a value spanning lines is a parse this
    cannot make.
    """
    reported = vm.ssh_succeed("; ".join(commands), timeout=timeout)
    return dict(line.split("=", 1) for line in reported.splitlines() if "=" in line)


def _held_line(machine: str, identity: str) -> str:
    """The one line a report and an apply both name a holding with."""
    return f"{machine} holds {identity}, which this build does not name"


def _steps(printed: Sequence[str]) -> list[int]:
    """The indexes of the lines that name a step a run took against a machine."""
    return [
        index
        for index, line in enumerate(printed)
        if line.startswith(("preflight ", "value ", "copy ", "activate ", "retire ", "restart "))
    ]


def _under(printed: Sequence[str], step: str) -> tuple[str, ...]:
    """The lines one step's machine printed, which the command indents under it."""
    assert step in printed, printed
    after = printed[printed.index(step) + 1 :]
    return tuple(itertools.takewhile(lambda line: line.startswith("  "), after))


SWEEP_SERVICE = delivery.service_name(manifest.artifact_of(BUILT.entries[SWEEP_KEY]))


@pytest.fixture(scope="session")
def dropped(interrupted: Run) -> Run:
    """Phase 9: the build that names `sweep` no longer, reported and then applied.

    `retired` places `site` on the same tag, so the machine running the dropped
    entry is still named and still reachable, which is what makes
    `sweep:job@alpha` a holding rather than an unreachable machine.

    The job's own unit is started by hand here: the folder's schedule is
    `daily`, so the job fires during no run, and the file it writes has to
    exist before the retirement for the phase after this one to read it back.
    """
    if interrupted.observed.get("dropped"):
        return interrupted

    server = interrupted.vm(SERVER_MACHINE)
    server.ssh_succeed(f"systemctl start {SWEEP_UNIT}", timeout=120)
    interrupted.observed["sweep_before"] = _reported(server, SWEEP_SERVICE)
    interrupted.observed["dropped"] = _command(interrupted, "status", str(RETIRED.root))
    interrupted.observed["dropped_applied"] = _command(interrupted, "apply", str(RETIRED.root))
    return interrupted


def test_a_machine_holds_what_no_build_names(dropped: Run) -> None:
    """A report against the build that dropped one entry names what still runs.

    The identity the line carries is read back off the machine's own endpoint
    record rather than composed here: what the endpoint reports for the dropped
    entry is the identity the realiser wrote, and the plan key the line names is
    what follows the prefix the deployment record publishes.
    """
    server = dropped.vm(SERVER_MACHINE)
    entry = dropped.built.entries[SERVER_KEY]
    own = _reported(server, delivery.service_name(manifest.artifact_of(entry)))
    held = _reported(server, SWEEP_SERVICE)
    reported = dropped.observed["dropped"]

    assert SWEEP_KEY not in RETIRED.entries, sorted(RETIRED.entries)
    assert held["locked_url"] == delivery.locked_url(delivery.record_of(RETIRED.root), SWEEP_KEY)
    assert _held_line(SERVER_MACHINE, SWEEP_KEY) in reported, reported

    # The entry the build still names is reported as it was before: one line,
    # the machine's own record, and the verdict over the unit files it names.
    assert (
        f"{SERVER_KEY} {entry.realiser} generation {own['generation']} of "
        f"{own['locked_url']} runs this build's units"
    ) in reported, reported
    assert [line for line in reported if line.startswith(f"{CLIENT_MACHINE} holds ")] == []


def test_an_apply_of_a_build_that_dropped_an_entry_announces_what_the_machine_still_runs(
    dropped: Run,
) -> None:
    """The same line the report prints, printed before the run's first step."""
    applied = dropped.observed["dropped_applied"]
    announced = f"{_held_line(SERVER_MACHINE, SWEEP_KEY)}; not retired"

    assert announced in applied, applied
    steps = _steps(applied)
    assert steps, applied
    assert applied.index(announced) < steps[0], applied


def test_an_apply_that_was_not_asked_to_retire_leaves_the_holding_running(dropped: Run) -> None:
    """Nothing was removed, and the entry the build does name was applied."""
    applied = dropped.observed["dropped_applied"]
    before = dropped.observed["sweep_before"]
    address = dropped.plan[f"machine:{SERVER_MACHINE}"]["address"]
    held = _reported(dropped.vm(SERVER_MACHINE), SWEEP_SERVICE)

    assert f"{_held_line(SERVER_MACHINE, SWEEP_KEY)}; not retired" in applied, applied
    assert [line for line in applied if line.startswith("retire ")] == [], applied
    assert f"activate {SERVER_KEY} (flakelet) on root@{address}" in applied, applied

    observed = _observed(
        dropped.vm(SERVER_MACHINE),
        f"printf 'timer=%s\\n' \"$(systemctl is-active {SWEEP_TIMER} || true)\"",
        f"printf 'marker=%s\\n' \"$(test -e {SWEEP_MARKER} && echo present || echo absent)\"",
        f"printf 'serves=%s\\n' \"$(systemctl is-active {SERVER_UNIT} || true)\"",
    )
    assert held["generation"] == before["generation"], (before, held)
    assert held["units"] == _built_units(dropped.built.entries[SWEEP_KEY]), held
    assert observed["timer"] == "active", observed
    assert observed["marker"] == "present", observed
    assert observed["serves"] == "active", observed


@pytest.fixture(scope="session")
def retired(dropped: Run) -> Run:
    """Phase 10: the same build applied once more, this time asked to retire.

    The apply is the whole of the change: the holding is announced with no `;
    not retired` and taken away with the endpoint's own removal verb before the
    run copies or activates anything.
    """
    if dropped.observed.get("retired"):
        return dropped

    dropped.observed["retired"] = _command(dropped, "apply", str(RETIRED.root), "--retire")
    return dropped


def test_a_retired_entry_stops_running_and_the_endpoint_no_longer_registers_it(
    retired: Run,
) -> None:
    """The units are gone, the endpoint knows nothing under the name, and the rest runs."""
    applied = retired.observed["retired"]
    address = retired.plan[f"machine:{SERVER_MACHINE}"]["address"]

    assert f"retire {SWEEP_KEY} on root@{address} (no state deleted)" in applied, applied
    assert [line for line in applied if line.startswith("failed ")] == [], applied

    observed = _observed(
        retired.vm(SERVER_MACHINE),
        "printf 'registered=%s\\n' "
        f'"$(flakelet status --json {SWEEP_SERVICE} > /dev/null 2>&1; echo $?)"',
        f"printf 'unit=%s\\n' \"$(systemctl cat {SWEEP_UNIT} > /dev/null 2>&1; echo $?)\"",
        f"printf 'timer=%s\\n' \"$(systemctl cat {SWEEP_TIMER} > /dev/null 2>&1; echo $?)\"",
        f"printf 'rotate=%s\\n' \"$(systemctl is-active {SWEEP_UNIT} || true)\"",
        f"printf 'armed=%s\\n' \"$(systemctl is-active {SWEEP_TIMER} || true)\"",
        f"printf 'serves=%s\\n' \"$(systemctl is-active {SERVER_UNIT} || true)\"",
    )

    assert observed["registered"] != "0", observed
    assert observed["unit"] != "0", observed
    assert observed["timer"] != "0", observed
    assert observed["rotate"] == "inactive", observed
    assert observed["armed"] == "inactive", observed
    assert observed["serves"] == "active", observed

    client = retired.vm(CLIENT_MACHINE)
    assert client.ssh_succeed(f"systemctl is-active {CLIENT_UNIT}").strip() == "active"


def test_a_file_the_retired_entry_wrote_survives_its_retirement(retired: Run) -> None:
    """The file the job wrote is the state a retirement does not delete.

    It is why the step is `flakelet remove` and never `flakelet remove
    --purge`: the bytes on the machine outlived the entry, and deleting them is
    an operator's decision this command does not take.
    """
    applied = retired.observed["retired"]
    address = retired.plan[f"machine:{SERVER_MACHINE}"]["address"]

    observed = _observed(
        retired.vm(SERVER_MACHINE),
        f"printf 'marker=%s\\n' \"$(test -e {SWEEP_MARKER} && echo present || echo absent)\"",
        f"printf 'written=%s\\n' \"$(stat -c %s {SWEEP_MARKER} 2>/dev/null || echo none)\"",
    )

    assert observed["marker"] == "present", observed
    assert observed["written"] == "0", observed
    assert f"retire {SWEEP_KEY} on root@{address} (no state deleted)" in applied, applied


def test_the_line_of_a_retirement_says_what_it_kept(retired: Run) -> None:
    """The step line says no state was deleted, and the endpoint's own words follow it.

    What the endpoint prints for a removal it kept nothing for is one line
    naming the entry it removed; it adds one `state left in ...` line per state
    folder that still holds data, and the retired entry declares none, so the
    absence of such a line is the endpoint reporting that there was nothing to
    keep. Both are the machine's own output, indented under the step by the
    command.
    """
    applied = retired.observed["retired"]
    address = retired.plan[f"machine:{SERVER_MACHINE}"]["address"]
    step = f"retire {SWEEP_KEY} on root@{address} (no state deleted)"

    assert step in applied, applied
    assert _under(applied, step) == (f"  {SWEEP_SERVICE}: removed",), applied
    assert not any("purge" in line for line in applied), applied


@pytest.fixture(scope="session")
def probe_failed(retired: Run) -> Run:
    """Phase 11: the build whose probe the page does not answer, applied.

    Last but one in file order, and nothing after it may apply this build
    again: a rolled-back activation records a hold keyed on the artifact, so a
    second apply of the same artifact is refused for the hold rather than for
    the probe. The run is restricted to the served entry, whose unit the probe
    is declared on.
    """
    if retired.observed.get("probe_printed") is not None:
        return retired

    server = retired.vm(SERVER_MACHINE)
    service = delivery.service_name(retired.artifact(SERVER_KEY))
    assert service == delivery.service_name(retired.artifact(SERVER_KEY, of=PROBED))
    before = _reported(server, service)

    status, printed = _apply_however_it_ends(retired, str(PROBED.root), "--only", SERVER_KEY)

    retired.observed["probe_before"] = before
    retired.observed["probe_status"] = status
    retired.observed["probe_printed"] = printed
    retired.observed["probe_after"] = _reported(server, service)
    return retired


def test_a_failing_probe_leaves_the_previous_generation_running(probe_failed: Run) -> None:
    """The endpoint kept the generation it was running, and its units are the ones running.

    The comparison is the endpoint's own record before and after: a rollback
    deletes the generation it had just created, so the generation number is the
    one from before and the unit files it names are the previous artifact's,
    which carry no probe file at all.
    """
    before = probe_failed.observed["probe_before"]
    after = probe_failed.observed["probe_after"]

    assert PROBE_UNIT in PROBED.entries[SERVER_KEY].units, PROBED.entries[SERVER_KEY].units
    assert PROBE_UNIT not in probe_failed.built.entries[SERVER_KEY].units
    assert after["generation"] == before["generation"], (before, after)
    assert after["units"] == _built_units(probe_failed.built.entries[SERVER_KEY]), after

    observed = _observed(
        probe_failed.vm(SERVER_MACHINE),
        f"printf 'serves=%s\\n' \"$(systemctl is-active {SERVER_UNIT} || true)\"",
        f"printf 'probe=%s\\n' \"$(systemctl cat {PROBE_UNIT} > /dev/null 2>&1; echo $?)\"",
        "printf 'fragment=%s\\n' "
        f'"$(readlink -f "$(systemctl show -P FragmentPath {SERVER_UNIT})")"',
    )

    # The service manager's own view of which file it is running, beside the
    # endpoint's record of it: the previous generation's unit file, not the one
    # the rolled-back generation carried.
    assert observed["serves"] == "active", observed
    assert observed["probe"] != "0", observed
    assert observed["fragment"] == _built_units(probe_failed.built.entries[SERVER_KEY])[SERVER_UNIT]


def test_a_failing_probe_is_a_failed_apply(probe_failed: Run) -> None:
    """The run failed on the activation, naming the entry, the machine and its words."""
    printed = probe_failed.observed["probe_printed"]
    address = probe_failed.plan[f"machine:{SERVER_MACHINE}"]["address"]
    failed = [line for line in printed if line.startswith("failed ")]

    assert probe_failed.observed["probe_status"] != 0, printed
    assert f"activate {SERVER_KEY} (flakelet) on root@{address}" in printed, printed
    assert len(failed) == 1, printed
    assert SERVER_KEY in failed[0], failed
    assert address in failed[0], failed

    # What the machine printed follows the line that names the step, because a
    # refusal carries it as its own message and the message spans lines: the
    # endpoint names the probe unit it started and says what it did about the
    # generation it had just created.
    said = "\n".join(printed[printed.index(failed[0]) :])
    assert PROBE_UNIT in said, printed
    assert "rolled back" in said, printed

    whole = "\n".join(printed)
    assert "Traceback" not in whole, printed
    assert "BatchMode" not in whole, printed
    assert "flakelet activate" not in whole, printed


def _page_of(deployment: manifest.Deployment) -> str:
    """What the served entry of one build serves, read off that build's own plan.

    `Run.page_text` reads the one unit file an artifact carries, and a probed
    entry's artifact carries two, so the served directory is taken from the
    plan record of the unit that serves it.
    """
    command = str(deployment.plan[SERVER_KEY]["units"]["serve"]["command"])
    found = re.search(r"--directory (\S+)", command)
    assert found is not None, command
    return (Path(found.group(1)) / "index.html").read_text()


def test_a_passing_probe_activates_the_new_generation(probe_failed: Run) -> None:
    """The build whose probe the page answers is a generation, and the probe ran.

    A build of its own rather than the folder's `default` gaining a probe: a
    probe is a unit field, so it is in the entry's key, and an artifact carrying
    one carries a second unit file - which every phase above reads the served
    entry as not having. The artifact is also a different one than the failing
    build's, which is what the endpoint's hold is keyed on.
    """
    run = probe_failed
    server = run.vm(SERVER_MACHINE)
    service = delivery.service_name(run.artifact(SERVER_KEY, of=HEALTHY))
    held = run.observed["probe_after"]

    applied = _command(run, "apply", str(HEALTHY.root), "--only", SERVER_KEY)

    reported = _reported(server, service)
    assert f"activate {SERVER_KEY} (flakelet) on root@{server.ip}" in applied, applied
    assert [line for line in applied if line.startswith("failed ")] == [], applied
    assert reported["generation"] > held["generation"], (held, reported)
    assert reported["units"] == _built_units(HEALTHY.entries[SERVER_KEY]), reported
    assert reported["last_error"] is None, reported

    page = _page_of(HEALTHY)
    observed = _observed(
        server,
        f"printf 'loaded=%s\\n' \"$(systemctl cat {PROBE_UNIT} > /dev/null 2>&1; echo $?)\"",
        f"printf 'logged=%s\\n' \"$(journalctl -u {PROBE_UNIT} --no-pager -o cat"
        ' | tr -s "[:space:]" " ")"',
        f"printf 'serves=%s\\n' \"$(systemctl is-active {SERVER_UNIT} || true)\"",
    )

    # That the probe ran is read off its own output: the request's answer is in
    # the unit's journal. A completed one-shot nothing references is unloaded
    # again by the service manager, which then answers about it with the
    # defaults of a unit that never ran, so its properties are no evidence.
    assert observed["loaded"] == "0", observed
    assert page.strip() in observed["logged"], observed
    assert observed["serves"] == "active", observed
