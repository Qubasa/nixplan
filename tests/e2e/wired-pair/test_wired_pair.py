"""Two real machines, one plan, and the wire between them.

``nix run .#planner-e2e wired-pair`` runs this. It builds its own deployment with
``planner build $PLANNER_E2E_FLAKE#planner-e2e-wired-pair``, boots two rookery VMs
from ``$PLANNER_E2E_GUEST_IMAGE``, puts the deployment on the machines its plan
placed the entries on with ``planner apply``, and observes what the two machines
then do. One test per scenario of
``openspec/changes/prove-plan-on-real-machines/specs/delivery/real-cluster/spec.md``,
named after it.

The build runs in this process and the apply runs through ``Cluster.run``
(design.md D8): a build needs no cluster, and the machines' addresses resolve
only inside the cluster's net namespace.

**The phases are ordered and the file order is the order.** The requirements are
a state machine, so each test asserts the state it depends on rather than
assuming it:

1. both builds are produced by the operator's command, before a machine is dialled
2. the participants are real (nothing has been applied yet)
3. the whole deployment is applied by one command (the ``delivered`` fixture)
4. the receiving machine evaluated nothing and can reach no other store
5. the wire is traffic, and cutting it is visible - which restores it afterwards
6. an unchanged re-apply is a no-op, a changed one is generation 2, a rollback
   returns generation 1
7. both machines reboot, and the entries come back without a second apply

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
SWEEP_MARKER = "/run/cluster-sweep.ran"
RECORD_PATH = "/run/cluster-probe.body"
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
        return (self.built if of is None else of).entries[key].path

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
        artifact = entry.path
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
        vm = delivered.vm(entry.machine)
        assert vm.ssh_succeed(f"nix-store --check-validity {entry.path} && echo ok").strip() == "ok"
        named = sorted(set(STORE_PATH.findall(delivered.unit_text(entry.path))))
        assert named, delivered.unit_text(entry.path)
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
        described = (
            f"{key} {entry.realiser} {entry.machine} {entry.address} {entry.path} "
            f"[{' '.join(entry.units)}]"
        )
        assert described in delivered.build_log, delivered.build_log
        assert f"copy {key} {entry.path} -> root@{entry.address}" in applied, applied
        vm = delivered.vm(entry.machine)
        assert vm.ssh_succeed(f"nix-store --check-validity {entry.path} && echo ok").strip() == "ok"


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
    assert reported["locked_url"] == delivery.locked_url(SERVER_KEY), reported
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


def test_the_command_reports_what_a_machine_holds(delivered: Run) -> None:
    """`planner status` answers with each machine's own endpoint report.

    The present half is asserted through the command itself: every entry is
    applied at this point in the ordered phases, and its line has to be what that
    entry's own machine says about it.

    The absent half cannot be obtained from ``planner status`` here without
    unapplying an entry the phases after this one still read, so it is obtained
    from a machine that genuinely registers no such service - the consumer's,
    asked for the producer's entry - through the command's own script and the
    command's own reading of what came back. What that proves is the whole claim:
    the endpoint answers rather than fails, and the command calls it absent.
    """
    entries = [delivered.built.entries[key] for key in KEYS]
    holds = _command(delivered, "status", str(delivered.built.root))

    for entry in entries:
        own = _reported(delivered.vm(entry.machine), delivery.service_name(entry.path))
        line = f"{entry.key} {entry.realiser} generation {own['generation']} of {own['locked_url']}"
        assert line in holds, holds

    producer = delivered.built.entries[SERVER_KEY]
    elsewhere = delivered.vm(CLIENT_MACHINE).ssh_succeed(
        remote.flakelet_status_script(delivery.service_name(producer.path))
    )
    assert json.loads(elsewhere) == [], elsewhere
    assert report._read_status(producer, elsewhere) == "absent"


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
        service = delivery.service_name(entry.path)
        assert json.loads(vm.ssh_succeed("cat /etc/flakelet/config.json")).get("services") == {}
        vm.ssh_succeed("systemctl restart flakelet-reconcile.service", timeout=120)
        assert _reported(vm, service)["generation"] >= 1
        assert vm.ssh_succeed(f"systemctl is-active {unit}").strip() == "active"


def test_the_endpoint_reports_the_identity_the_build_published(delivered: Run) -> None:
    """A machine's record for an entry carries the identity the build published.

    The point of publishing the artifact's own digest rather than the plan entry
    key is that the two sides can be compared, so this reads both: the record the
    build wrote, and what the endpoint says it holds. The phases above applied,
    re-applied and rolled back, so what each machine holds here is the first
    build's artifact again, and the identity has to be the one that build
    published for it.
    """
    published = json.loads((delivered.built.root / "manifest.json").read_text())["entries"]

    for key in (SERVER_KEY, CLIENT_KEY):
        entry = delivered.built.entries[key]
        record = _reported(delivered.vm(entry.machine), delivery.service_name(entry.path))
        assert record["settings_hash"] == published[key]["key"], (record, published[key])
        assert published[key]["key"] != delivered.plan[key]["key"], published[key]
