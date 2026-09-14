"""Three real machines, one generated secret, and the set the plan named.

``nix run .#planner-e2e secret-delivery`` runs this. It builds the folder's
deployment with ``planner build``, boots three rookery VMs from
``$PLANNER_E2E_GUEST_IMAGE``, writes the token it minted into a value source of
its own, puts the deployment on the machines with ``planner apply --values``, and
then asks the machines what they hold and what the units did. One test per
scenario of
``openspec/changes/deliver-secrets-across-machines/specs/delivery/real-cluster/spec.md``,
each named after it, and one for the value-source scenario of
``openspec/changes/apply-deployments-with-an-operator-command/specs/operator/apply-command/spec.md``

**The phases are ordered and the file order is the order.**

1. the deployment is built by the command, in this process and before any
   machine is dialled, and the manifest it wrote is what the tests read
2. the run writes its own bytes into the value source, exactly the files the
   plan declares of a value some machine receives and nothing else
3. one ``planner apply`` writes every value to the set the plan named and
   activates the three entries, provider before consumer
4. the consumer's unit is the assertion: it authenticated with the delivered
   bytes and was refused without them

The bytes are minted here, once per session, with ``secrets.token_hex``. That is
the operator's generator run: they are in no plan, in no artifact and in no store
path, which is what ``test_no_artifact_carries_the_delivered_bytes`` reads. The
value source stands in for the store an operator keeps them in, so it is a
directory of this run's own, outside everything the build produced.

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake,
so the module skips itself when it is absent.
"""

from __future__ import annotations

import json
import os
import secrets
import shlex
import subprocess
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

ISSUER_KEY = "issuer:api@alpha"
PROBE_KEY = "probe:client@beta"
IDLE_KEY = "idle:job@gamma"
SESSION_VALUE = "issuer:vars/session"
CA_VALUE = "issuer:vars/ca"
ISSUER_MACHINE = "alpha"
PROBE_MACHINE = "beta"
IDLE_MACHINE = "gamma"
ISSUER_UNIT = "issuer-api-serve.service"
PROBE_UNIT = "probe-client-fetch.service"
IDLE_UNIT = "idle-job-mark.service"
MACHINES = (ISSUER_MACHINE, PROBE_MACHINE, IDLE_MACHINE)
ATTRIBUTE = "planner-e2e-secret-delivery"
USER = "root"


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


def _build(target: str) -> manifest.Deployment:
    """Build one deployment with the command, and read what it built.

    This runs in the pytest process rather than through the cluster, because a
    build needs no machine, and running it inside the cluster's user namespace
    would put an evaluation and a build there (design.md D8). The command prints
    the store path first and describes the deployment after it.
    """
    built = subprocess.run([str(CLI), "build", target], capture_output=True, text=True, check=False)
    if built.returncode != 0:
        pytest.fail(f"planner build {target} exited {built.returncode}:\n{built.stderr}")
    return manifest.read(Path(built.stdout.splitlines()[0]))


CLI = _env_path("PLANNER_CLI")
FLAKE = _env_path("PLANNER_E2E_FLAKE")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))
DEPLOYMENT = _build(f"{FLAKE}#{ATTRIBUTE}")

# The path the probe's own unit writes, read off the plan rather than restated:
# the module derives it from the identity of its entry, so this is what a machine
# will look at.
RECORD_PATH = str(DEPLOYMENT.plan[PROBE_KEY]["units"]["fetch"]["env"]["RECORD_PATH"])


def _value_source(root: Path, deployment: manifest.Deployment, token: str) -> Path:
    """Write this run's bytes where the command reads them from, and return the directory.

    The layout is ``<dir>/<value entry key>/<file>``, and a value entry key
    carries a ``/`` of its own, so ``issuer:vars/session/token`` is a real nested
    path. What has to be there is read out of the manifest rather than restated:
    exactly the declared files of every value entry some machine receives.
    ``issuer:vars/ca`` is delivered nowhere, so a file of it here would be bytes
    the plan does not name and the command would refuse the source for holding
    them.

    Args:
        root: A directory this run owns.
        deployment: The built deployment the bytes are for.
        token: The bytes every declared file receives.

    Returns:
        The value source, readable by this user alone.
    """
    source = root / "values"
    source.mkdir(mode=0o700, exist_ok=True)
    source.chmod(0o700)
    for value in deployment.values.values():
        if not value.delivery:
            continue
        directory = source
        for part in Path(value.key).parts:
            directory = directory / part
            directory.mkdir(mode=0o700, exist_ok=True)
            directory.chmod(0o700)
        for file in value.files:
            written = directory / file.name
            written.write_text(token)
            written.chmod(0o600)
    return source


def _files_in(root: Path) -> list[Path]:
    """Every file the build holds, under the name the build gives it.

    A deployment is a farm of symlinks and each artifact is another one, so a
    walk that does not follow them searches four JSON files and calls that the
    artifacts. The names are kept unresolved so a failure names the file a reader
    would open.
    """
    found: list[Path] = []
    pending = [root]
    while pending:
        for child in sorted(pending.pop().iterdir()):
            if child.resolve().is_dir():
                pending.append(child)
            else:
                found.append(child)
    return found


@dataclass
class Run:
    """The cluster, the deployment the command built, this run's secret and its source."""

    cluster: Any
    deployment: manifest.Deployment
    key: Path
    token: str
    source: Path
    steps: list[str] = field(default_factory=list)
    rotation: list[str] = field(default_factory=list)
    invocations: dict[str, str] = field(default_factory=dict)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def address(self, machine: str) -> str:
        """The address the plan's own machine record declares."""
        return manifest.machine_address(self.deployment, machine, of=machine)

    def value_file(self, key: str, name: str) -> manifest.ValueFile:
        """One declared file of one generated value, as the manifest states it."""
        declared = {file.name: file for file in self.deployment.values[key].files}
        return declared[name]

    def value_path(self, key: str, name: str) -> str:
        """The path the plan records for one file of one generated value."""
        return self.value_file(key, name).path

    def value_writes(self, key: str) -> list[str]:
        """The steps of the apply that wrote one generated value, in the order taken."""
        return [step for step in self.steps if step.startswith(f"value {key} ")]

    def unit_text(self, key: str) -> str:
        """The unit file of one placed entry, out of the artifact the build made for it."""
        entry = self.deployment.entries[key]
        assert len(entry.units) == 1, entry
        return (manifest.artifact_of(entry) / "units" / entry.units[0]).read_text()

    def source_file(self, key: str, name: str) -> Path:
        """The file the run wrote into the value source for one declared file."""
        return self.source / key / name

    def source_holds(self) -> list[str]:
        """The files the value source holds, as paths relative to it, sorted."""
        return sorted(
            found.relative_to(self.source).as_posix()
            for found in self.source.rglob("*")
            if found.is_file()
        )

    @property
    def store_dir(self) -> Path:
        """The store the manifest records the artifacts are copied out of."""
        recorded = json.loads((self.deployment.root / manifest.MANIFEST).read_text())["storeDir"]
        assert isinstance(recorded, str), recorded
        return Path(recorded)


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=MACHINES, key=KEY)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage every run starts from: three machines, up and usable.

    On a cache hit this body does not run at all - the machines are resumed from
    the cut it took the first time - so nothing here may be a fact a test reads.
    It waits, and yields.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def run(booted: Any) -> Run:
    """Three machines named as the plan names them, this run's secret, and its source."""
    token = secrets.token_hex(16)
    return Run(
        cluster=booted.cluster,
        deployment=DEPLOYMENT,
        key=KEY,
        token=token,
        source=_value_source(delivery.state_root(), DEPLOYMENT, token),
    )


@pytest.fixture(scope="session")
def applied(run: Run) -> Run:
    """One ``planner apply --values``, and the machines settled after it.

    The command writes every value before it activates anything and applies the
    provider before the consumer, so one invocation is both delivery phases and
    its step log is the record of both. It goes through ``Cluster.run`` because
    the machines' addresses resolve only there, and ``command_env`` carries this
    process's own environment plus the options a throwaway guest is reached with.

    The waits make a read of a machine a read of a settled machine: the
    provider's unit, then the port it was allocated, then the consumer's unit.
    One invocation activates the consumer as soon as the provider is activated,
    so the seconds between the two are covered by the retries in the consumer's
    own script, which is what they are there for.
    """
    reported = run.cluster.run(
        [str(CLI), "apply", str(run.deployment.root), "--values", str(run.source)],
        env=delivery.command_env(dict(os.environ), run.key),
    )
    run.steps.extend(reported.stdout.splitlines())

    port = run.deployment.plan[ISSUER_KEY]["alloc"]["ports"]["http"]
    issuer = run.vm(ISSUER_MACHINE)
    issuer.wait_for_unit(ISSUER_UNIT, timeout=120)
    issuer.wait_until_succeeds(f"ss -ltn | grep -q ':{port}'", timeout=60)
    run.vm(PROBE_MACHINE).wait_for_unit(PROBE_UNIT, timeout=120)
    return run


def test_a_secret_reaches_the_machines_the_plan_names(applied: Run) -> None:
    run = applied
    entry = run.deployment.plan[SESSION_VALUE]
    assert entry["per"] == "instance", entry
    assert entry["delivery"] == [ISSUER_MACHINE, PROBE_MACHINE], entry
    assert entry["deliveryDerivedFrom"] == [
        f"{ISSUER_KEY} owns it",
        f"{PROBE_KEY} named token in uses.api.reads",
    ], entry

    path = run.value_path(SESSION_VALUE, "token")
    for machine in (ISSUER_MACHINE, PROBE_MACHINE):
        vm = run.vm(machine)
        assert vm.ssh_succeed(f"cat {path}").strip() == run.token
        assert vm.ssh_succeed(f"stat -c %a {path}").strip() == "400"
        assert vm.ssh_succeed(f"stat -c %U {path}").strip() == USER

    assert [step for step in run.value_writes(SESSION_VALUE) if " token -> " in step] == [
        f"value {SESSION_VALUE} token -> {USER}@{run.address(machine)}:{path} (root:root 0400)"
        for machine in (ISSUER_MACHINE, PROBE_MACHINE)
    ]


def test_a_machine_outside_the_delivery_set_holds_nothing(applied: Run) -> None:
    """The apply reached gamma too, so what it holds is an answer and not an omission."""
    run = applied
    vm = run.vm(IDLE_MACHINE)
    assert IDLE_MACHINE not in run.deployment.values[SESSION_VALUE].delivery
    assert f"activate {IDLE_KEY} (flakelet) on {USER}@{run.address(IDLE_MACHINE)}" in run.steps
    assert vm.ssh_succeed(f"systemctl is-active {IDLE_UNIT}").strip() == "active"

    for key, file in ((SESSION_VALUE, "token"), (CA_VALUE, "ca.pub")):
        path = run.value_path(key, file)
        assert vm.ssh(f"test -e {path}").returncode != 0, path

    # Not just the files: the instance's directory was never created here.
    assert vm.ssh("test -e /run/vars/issuer").returncode != 0
    assert vm.ssh_succeed("ls -A /run/vars 2>/dev/null || true").strip() == ""


def test_a_value_nobody_receives_is_on_no_machine(applied: Run) -> None:
    run = applied
    entry = run.deployment.plan[CA_VALUE]
    assert entry["deploy"] is False, entry
    assert entry["delivery"] == [], entry
    assert run.deployment.values[CA_VALUE].delivery == ()
    assert run.value_writes(CA_VALUE) == []

    path = run.value_path(CA_VALUE, "ca.pub")
    for machine in MACHINES:
        assert run.vm(machine).ssh(f"test -e {path}").returncode != 0, (machine, path)


def test_a_consumer_authenticates_with_the_delivered_secret(applied: Run) -> None:
    run = applied
    vm = run.vm(PROBE_MACHINE)
    assert vm.ssh_succeed(f"systemctl is-active {PROBE_UNIT}").strip() == "active"

    record = json.loads(vm.ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["authorizedStatus"] == 200, record
    assert record["authorizedBody"] == "authorized", record
    exports = run.deployment.plan[ISSUER_KEY]["provides"]["api"]["exports"]
    assert record["url"] == exports["url"]["value"]

    # The unit read the delivered path, not a value the artifact carried.
    token_path = run.value_path(SESSION_VALUE, "token")
    assert record["tokenFile"] == token_path
    unit = run.unit_text(PROBE_KEY)
    assert token_path in unit
    assert run.token not in unit


def test_the_provider_refuses_a_request_without_it(applied: Run) -> None:
    run = applied
    record = json.loads(run.vm(PROBE_MACHINE).ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["anonymousStatus"] == 401, record
    assert record["anonymousBody"] == "unauthorized", record

    # The refusal is the provider's own unit answering, and it logged both requests.
    journal = run.vm(ISSUER_MACHINE).ssh_succeed(f"journalctl -u {ISSUER_UNIT} --no-pager")
    assert '"GET / HTTP/1.1" 401' in journal, journal
    assert '"GET / HTTP/1.1" 200' in journal, journal


def test_a_secret_is_applied_from_the_operators_value_source(applied: Run) -> None:
    """The bytes came from a directory the operator wrote, and the command read them there.

    The tests above read the delivered file, the delivery set and the consumer's
    request. What is asserted here is where the bytes came from: a directory of
    this run's own, holding exactly what the plan declares of it, which the
    command read and no build could have.
    """
    run = applied
    held = run.source_file(SESSION_VALUE, "token")
    declared = run.value_file(SESSION_VALUE, "token")
    assert run.source_holds() == [
        f"{SESSION_VALUE}/owned",
        f"{SESSION_VALUE}/token",
    ]
    assert held.read_text() == run.token
    assert held.stat().st_mode & 0o077 == 0
    assert declared.secrecy == "secret"

    for machine in MACHINES:
        vm = run.vm(machine)
        if machine in run.deployment.values[SESSION_VALUE].delivery:
            assert vm.ssh_succeed(f"cat {declared.path}").strip() == held.read_text()
        else:
            assert vm.ssh(f"test -e {declared.path}").returncode != 0, machine

    record = json.loads(run.vm(PROBE_MACHINE).ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["tokenFile"] == declared.path
    assert record["authorizedStatus"] == 200, record

    # The artifact names the path the command wrote to, and neither the bytes nor
    # the directory an operator kept them in.
    unit = run.unit_text(PROBE_KEY)
    assert declared.path in unit
    assert held.read_text() not in unit
    assert str(run.source) not in unit


def test_no_artifact_carries_the_delivered_bytes(applied: Run) -> None:
    run = applied
    searched = _files_in(run.deployment.root)
    assert {"plan.json", "manifest.json", PROBE_UNIT} <= {path.name for path in searched}
    for path in searched:
        assert run.token not in path.read_text(errors="replace"), path

    assert run.token not in json.dumps(run.deployment.plan)
    assert run.deployment.plan[SESSION_VALUE]["files"]["token"]["inPlan"] == "reference"

    held = run.source_file(SESSION_VALUE, "token")
    assert not held.is_relative_to(run.deployment.root)
    assert not held.is_relative_to(run.store_dir)
    for entry in run.deployment.entries.values():
        if entry.path is not None:
            assert not held.is_relative_to(entry.path), entry

    for machine in MACHINES:
        store = run.vm(machine).ssh(f"grep -rl {run.token} /nix/store 2>/dev/null")
        assert store.stdout.strip() == "", store.stdout


def test_a_public_generated_value_travels_in_the_plan(applied: Run) -> None:
    run = applied
    ca = run.deployment.plan[CA_VALUE]["files"]["ca.pub"]
    assert ca["inPlan"] == "value", ca

    published = run.deployment.plan[ISSUER_KEY]["provides"]["api"]["exports"]["caCert"]
    assert published["plane"] == "env", published
    assert published["value"].startswith("PLANNER-E2E-CA "), published

    unit = run.unit_text(PROBE_KEY)
    assert f"CA_CERT={published['value']}" in unit, unit

    record = json.loads(run.vm(PROBE_MACHINE).ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["caCertFirstLine"] == published["value"]
    assert record["caCertLength"] == len(published["value"])


def test_a_value_delivered_with_the_defaults(applied: Run) -> None:
    """A record that declares nothing is delivered as it was before it had the fields."""
    run = applied
    path = run.value_path(SESSION_VALUE, "token")
    record = run.value_file(SESSION_VALUE, "token")
    assert (record.owner, record.group, record.mode) == ("root", "root", "0400")

    for machine in (ISSUER_MACHINE, PROBE_MACHINE):
        answered = run.vm(machine).ssh_succeed(f"stat -c %U:%G:%a {path}").strip()
        assert answered == "root:root:400", (machine, answered)


def test_a_value_delivered_to_an_account(applied: Run) -> None:
    """The owner, the group and the mode on the machine are the record's three fields."""
    run = applied
    path = run.value_path(SESSION_VALUE, "owned")
    record = run.value_file(SESSION_VALUE, "owned")
    assert (record.owner, record.group, record.mode) == ("nobody", "nogroup", "0440")

    for machine in (ISSUER_MACHINE, PROBE_MACHINE):
        vm = run.vm(machine)
        answered = vm.ssh_succeed(f"stat -c %U:%G:%a {path}").strip()
        assert answered == "nobody:nogroup:440", (machine, answered)
        # The account the record names can read it, which is the point of stating one.
        assert vm.ssh_succeed(f"runuser -u nobody -- cat {path}").strip() == run.token

    assert [step for step in run.value_writes(SESSION_VALUE) if " owned -> " in step] == [
        f"value {SESSION_VALUE} owned -> {USER}@{run.address(machine)}:{path} (nobody:nogroup 0440)"
        for machine in (ISSUER_MACHINE, PROBE_MACHINE)
    ]


def test_an_owner_changed_on_the_machine(applied: Run) -> None:
    """What a machine holds is the deployment's answer, not whatever last touched it."""
    run = applied
    path = run.value_path(SESSION_VALUE, "owned")
    vm = run.vm(ISSUER_MACHINE)
    vm.ssh_succeed(f"chown root:root {path} && chmod 0666 {path}")
    assert vm.ssh_succeed(f"stat -c %U:%G:%a {path}").strip() == "root:root:666"

    reapplied = run.cluster.run(
        [str(CLI), "apply", str(run.deployment.root), "--values", str(run.source)],
        env=delivery.command_env(dict(os.environ), run.key),
    )

    assert reapplied.returncode == 0, reapplied.stdout
    assert vm.ssh_succeed(f"stat -c %U:%G:%a {path}").strip() == "nobody:nogroup:440"
    assert f"value {SESSION_VALUE} owned -> " in reapplied.stdout


def _apply(run: Run) -> Any:
    """One ``planner apply --values`` of this run's deployment and source.

    The cluster answers with its own completed process, which is what the
    assertions read ``returncode`` and ``stdout`` off.
    """
    return run.cluster.run(
        [str(CLI), "apply", str(run.deployment.root), "--values", str(run.source)],
        env=delivery.command_env(dict(os.environ), run.key),
    )


def _status(run: Run) -> tuple[int, list[str]]:
    """What ``planner status`` says about the whole deployment, and its exit status.

    The command runs inside the cluster because a machine's address resolves only
    in the cluster's own net namespace. A machine the report could not ask is
    named on standard error, which is folded in so a failure says which one.
    """
    asked = run.cluster.run(
        [str(CLI), "status", str(run.deployment.root)],
        env=delivery.command_env(dict(os.environ), run.key),
        check=False,
    )
    return asked.returncode, asked.stdout.splitlines() + asked.stderr.splitlines()


def _invocation(run: Run, machine: str, unit: str) -> str:
    """The identity the service manager gives one unit's current run.

    A new identity is a new process for that unit, which is what a restart is,
    and a unit that is not running has none at all.
    """
    shown = run.vm(machine).ssh_succeed(f"systemctl show -P InvocationID {unit}")
    return str(shown.strip())


def test_a_machine_holding_every_value_is_reported_without_a_line(applied: Run) -> None:
    """A report of a machine holding every value it is delivered says nothing about them."""
    status, reported = _status(applied)

    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [], reported


def test_a_value_delivered_to_one_of_two_machines_is_named_where_it_is_missing(
    applied: Run,
) -> None:
    """The machine that lost a file is named, and the one that still holds it is not."""
    run = applied
    path = run.value_path(SESSION_VALUE, "token")
    probe = run.vm(PROBE_MACHINE)
    probe.ssh_succeed(f"rm {path}")

    status, reported = _status(run)

    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [
        f"value {SESSION_VALUE} missing on {PROBE_MACHINE}"
    ], reported

    assert _apply(run).returncode == 0
    assert probe.ssh_succeed(f"cat {path}").strip() == run.token


@pytest.fixture(scope="session")
def rotated(applied: Run) -> Run:
    """Phase 5: the same deployment applied again with different bytes in the source.

    Nothing about the build moves, so every artifact on every machine is the one
    already there and the only difference this apply can make is the one the
    value carries.
    """
    run = applied
    run.invocations = {
        PROBE_UNIT: _invocation(run, PROBE_MACHINE, PROBE_UNIT),
        ISSUER_UNIT: _invocation(run, ISSUER_MACHINE, ISSUER_UNIT),
    }
    run.token = secrets.token_hex(16)
    _value_source(delivery.state_root(), run.deployment, run.token)

    reported = _apply(run)
    run.rotation = reported.stdout.splitlines()
    run.vm(PROBE_MACHINE).wait_for_unit(PROBE_UNIT, timeout=120)
    return run


def test_a_value_whose_bytes_moved_is_written_and_reported_as_changed(rotated: Run) -> None:
    """The write step says the file moved, and both machines of the set hold the new bytes."""
    run = rotated
    path = run.value_path(SESSION_VALUE, "token")

    writes = [
        index
        for index, line in enumerate(run.rotation)
        if line.startswith(f"value {SESSION_VALUE} token -> ")
    ]
    assert len(writes) == 2, run.rotation
    assert [run.rotation[index + 1].strip() for index in writes] == ["changed", "changed"]

    for machine in (ISSUER_MACHINE, PROBE_MACHINE):
        assert run.vm(machine).ssh_succeed(f"cat {path}").strip() == run.token


def test_a_rotated_secret_restarts_the_entry_that_reads_it(rotated: Run) -> None:
    """The reader is a new process and the owner is not, and the step names the machine.

    The consumer declares a read of the export the value backs, so it is restarted;
    the issuer owns the generator and reads the path at request time, so nothing
    this run wrote is stale in it and it is left running.
    """
    run = rotated
    restarts = [line for line in run.rotation if line.startswith("restart ")]

    assert restarts == [
        f"restart {PROBE_KEY} for {SESSION_VALUE} on {PROBE_MACHINE} "
        f"at {USER}@{run.address(PROBE_MACHINE)}"
    ], run.rotation

    assert _invocation(run, PROBE_MACHINE, PROBE_UNIT) != run.invocations[PROBE_UNIT]
    assert _invocation(run, ISSUER_MACHINE, ISSUER_UNIT) == run.invocations[ISSUER_UNIT]


def test_a_delivered_value_moves_under_an_unchanged_artifact(rotated: Run) -> None:
    """The artifact is not a function of the bytes beside it, so activating it changed nothing.

    The reader's process is replaced by the restart step and not by the
    activation: the endpoint still holds generation 1, because a value's bytes
    are not part of the entry whose identity a generation records.
    """
    run = rotated
    service = delivery.service_name(manifest.artifact_of(run.deployment.entries[PROBE_KEY]))
    registered = json.loads(
        run.vm(PROBE_MACHINE).ssh_succeed(f"flakelet status --json {shlex.quote(service)}")
    )

    assert registered, service
    assert registered[0]["generation"] == 1, registered

    activated = [line for line in run.rotation if line.startswith(f"activate {PROBE_KEY} ")]
    assert len(activated) == 1, run.rotation


def test_a_restarted_reader_used_the_bytes_this_run_wrote(rotated: Run) -> None:
    """The consumer's unit ran again against the rotated secret and was authorized."""
    run = rotated
    vm = run.vm(PROBE_MACHINE)
    assert vm.ssh_succeed(f"systemctl is-active {PROBE_UNIT}").strip() == "active"

    record = json.loads(vm.ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["authorizedStatus"] == 200, record
    assert record["anonymousStatus"] == 401, record


@pytest.fixture(scope="session")
def halted(rotated: Run) -> Run:
    """Phase 6: the reader stopped by hand, and the value rotated under it."""
    run = rotated
    run.vm(PROBE_MACHINE).ssh_succeed(f"systemctl stop {PROBE_UNIT}")
    run.token = secrets.token_hex(16)
    _value_source(delivery.state_root(), run.deployment, run.token)

    run.rotation = _apply(run).stdout.splitlines()
    return run


def test_a_reader_that_is_not_running_is_not_started_by_the_restart(halted: Run) -> None:
    """The restart step is taken for the entry and leaves a stopped unit stopped."""
    run = halted
    vm = run.vm(PROBE_MACHINE)

    assert [line for line in run.rotation if line.startswith("restart ")] == [
        f"restart {PROBE_KEY} for {SESSION_VALUE} on {PROBE_MACHINE} "
        f"at {USER}@{run.address(PROBE_MACHINE)}"
    ], run.rotation

    # `systemctl is-active` exits 3 for a unit that is not running, so the
    # answer is read rather than demanded.
    assert vm.ssh(f"systemctl is-active {PROBE_UNIT}").stdout.strip() == "inactive"
    assert vm.ssh_succeed(f"cat {run.value_path(SESSION_VALUE, 'token')}").strip() == run.token


@pytest.fixture(scope="session")
def rebooted(halted: Run) -> Run:
    """Phase 7: the reader's machine rebooted, which is what empties ``/run``."""
    run = halted
    vm = run.vm(PROBE_MACHINE)
    vm.ssh("systemctl reboot")
    vm.wait_for_unit("multi-user.target", timeout=300)
    return run


def test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them(
    rebooted: Run,
) -> None:
    """A value lives under ``/run``, so a reboot loses it; the report names each one.

    The entry itself is back - the endpoint brings its units up again - so the
    report's value lines are the only thing that says the machine is not where the
    deployment left it, and a second apply is what puts it back.
    """
    run = rebooted
    vm = run.vm(PROBE_MACHINE)
    path = run.value_path(SESSION_VALUE, "token")
    assert vm.ssh(f"test -e {path}").returncode != 0

    status, reported = _status(run)
    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [
        f"value {SESSION_VALUE} missing on {PROBE_MACHINE}"
    ], reported

    reapplied = _apply(run)
    assert reapplied.returncode == 0, reapplied.stdout
    assert vm.ssh_succeed(f"cat {path}").strip() == run.token

    # The restart step leaves a unit that is not running alone, which is the rule
    # the phase above measures, so the unit is started here to read the bytes back.
    vm.ssh_succeed(f"systemctl start {PROBE_UNIT}")
    assert vm.ssh_succeed(f"systemctl is-active {PROBE_UNIT}").strip() == "active"

    status, reported = _status(run)
    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [], reported
