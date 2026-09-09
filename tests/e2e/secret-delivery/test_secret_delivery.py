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
RECORD_PATH = "/run/secret-delivery-probe.json"
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
        return (entry.path / "units" / entry.units[0]).read_text()

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

    assert run.value_writes(SESSION_VALUE) == [
        f"value {SESSION_VALUE} token -> {USER}@{run.address(machine)}:{path}"
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
    assert run.source_holds() == [f"{SESSION_VALUE}/token"]
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
