"""Three real machines, one generated secret, and the set the plan named.

``nix run .#planner-e2e secret-delivery`` runs this. It boots three rookery VMs
from ``$PLANNER_E2E_GUEST_IMAGE``, delivers the value in
``$PLANNER_SECRET_DELIVERY/plan.json`` to the machines that plan's vars entry
names, delivers and activates the three service artifacts, and then asks the
machines what they hold and what the units did. One test per scenario of
``openspec/changes/deliver-secrets-across-machines/specs/delivery/real-cluster/spec.md``,
named after it.

**The phases are ordered and the file order is the order.**

1. the value is delivered to the set the plan named, and to nothing else
2. the artifacts are delivered and activated, provider before consumer
3. the consumer's unit is the assertion: it authenticated with the delivered
   bytes and was refused without them

The bytes are minted here, once per session, with ``secrets.token_hex``. That is
the operator's generator run: they are in no plan, in no artifact and in no store
path, which is what ``test_no_artifact_carries_the_delivered_bytes`` reads.

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake,
so the module skips itself when it is absent.
"""

from __future__ import annotations

import json
import os
import secrets
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest

import delivery

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


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


ARTIFACTS = _env_path("PLANNER_SECRET_DELIVERY")
DEPLOYMENT = _env_path("PLANNER_SECRET_DELIVERY_DEPLOYMENT")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))


@dataclass
class Run:
    """The cluster, the plan, the bytes this run generated, and what it observed."""

    cluster: Any
    artifacts: Path
    deployment: Path
    key: Path
    plan: dict[str, Any]
    token: str
    observed: dict[str, Any] = field(default_factory=dict)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def artifact(self, name: str) -> Path:
        return (self.artifacts / name).resolve()

    def value_path(self, key: str, file: str) -> str:
        """The path the plan records for one file of one generated value."""
        path = self.plan[key]["files"][file]["path"]
        assert isinstance(path, str), path
        return path


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
    """Three machines named as the plan names them, and this run's own secret."""
    return Run(
        cluster=booted.cluster,
        artifacts=ARTIFACTS,
        deployment=DEPLOYMENT,
        key=KEY,
        plan=json.loads((ARTIFACTS / "plan.json").read_text()),
        token=secrets.token_hex(16),
    )


@pytest.fixture(scope="session")
def values_delivered(run: Run) -> Run:
    """Phase 1: every generated value goes to the machines its own entry names."""
    if run.observed.get("values"):
        return run

    dialled = {
        key: delivery.deliver_value(
            run.cluster,
            plan=run.plan,
            key=key,
            files=dict.fromkeys(entry.get("files", {}), run.token),
            ssh_key=run.key,
            base_env=dict(os.environ),
        )
        for key, entry in sorted(delivery.vars_entries(run.plan).items())
    }
    run.observed.update({"values": True, "dialled": dialled})
    return run


@pytest.fixture(scope="session")
def delivered(values_delivered: Run) -> Run:
    """Phase 2: the three artifacts, copied to their machines and activated there.

    The provider is activated and observed listening before the consumer is, so
    the consumer's first request is a request and not a retry.
    """
    run = values_delivered
    if run.observed.get("delivered"):
        return run

    base_env = dict(os.environ)
    for key, name, machine in (
        (ISSUER_KEY, "issuer", ISSUER_MACHINE),
        (IDLE_KEY, "idle", IDLE_MACHINE),
        (PROBE_KEY, "probe", PROBE_MACHINE),
    ):
        artifact = run.artifact(name)
        delivery.deliver(
            run.cluster,
            plan=run.plan,
            key=key,
            artifact=artifact,
            ssh_key=run.key,
            base_env=base_env,
        )
        delivery.activate(run.vm(machine), delivery.service_name(artifact), artifact)
        if key == ISSUER_KEY:
            port = run.plan[ISSUER_KEY]["alloc"]["ports"]["http"]
            run.vm(machine).wait_for_unit(ISSUER_UNIT, timeout=120)
            run.vm(machine).wait_until_succeeds(f"ss -ltn | grep -q ':{port}'", timeout=60)

    run.vm(PROBE_MACHINE).wait_for_unit(PROBE_UNIT, timeout=120)
    run.observed["delivered"] = True
    return run


def test_a_secret_reaches_the_machines_the_plan_names(values_delivered: Run) -> None:
    run = values_delivered
    entry = run.plan[SESSION_VALUE]
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
        assert vm.ssh_succeed(f"stat -c %U {path}").strip() == "root"

    assert run.observed["dialled"][SESSION_VALUE] == [
        run.plan[f"machine:{ISSUER_MACHINE}"]["address"],
        run.plan[f"machine:{PROBE_MACHINE}"]["address"],
    ]


def test_a_machine_outside_the_delivery_set_holds_nothing(values_delivered: Run) -> None:
    run = values_delivered
    vm = run.vm(IDLE_MACHINE)
    assert IDLE_MACHINE not in run.plan[SESSION_VALUE]["delivery"]

    for key, file in ((SESSION_VALUE, "token"), (CA_VALUE, "ca.pub")):
        path = run.value_path(key, file)
        assert vm.ssh(f"test -e {path}").returncode != 0, path

    # Not just the files: the instance's directory was never created here.
    assert vm.ssh("test -e /run/vars/issuer").returncode != 0
    assert vm.ssh_succeed("ls -A /run/vars 2>/dev/null || true").strip() == ""


def test_a_value_nobody_receives_is_on_no_machine(values_delivered: Run) -> None:
    run = values_delivered
    entry = run.plan[CA_VALUE]
    assert entry["deploy"] is False, entry
    assert entry["delivery"] == [], entry
    assert run.observed["dialled"][CA_VALUE] == []

    path = run.value_path(CA_VALUE, "ca.pub")
    for machine in MACHINES:
        assert run.vm(machine).ssh(f"test -e {path}").returncode != 0, (machine, path)


def test_a_consumer_authenticates_with_the_delivered_secret(delivered: Run) -> None:
    run = delivered
    vm = run.vm(PROBE_MACHINE)
    assert vm.ssh_succeed(f"systemctl is-active {PROBE_UNIT}").strip() == "active"

    record = json.loads(vm.ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["authorizedStatus"] == 200, record
    assert record["authorizedBody"] == "authorized", record
    assert record["url"] == run.plan[ISSUER_KEY]["provides"]["api"]["exports"]["url"]["value"]

    # The unit read the delivered path, not a value the artifact carried.
    token_path = run.value_path(SESSION_VALUE, "token")
    assert record["tokenFile"] == token_path
    unit = sorted((run.artifact("probe") / "units").iterdir())[0].read_text()
    assert token_path in unit
    assert run.token not in unit


def test_the_provider_refuses_a_request_without_it(delivered: Run) -> None:
    run = delivered
    record = json.loads(run.vm(PROBE_MACHINE).ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["anonymousStatus"] == 401, record
    assert record["anonymousBody"] == "unauthorized", record

    # The refusal is the provider's own unit answering, and it logged both requests.
    journal = run.vm(ISSUER_MACHINE).ssh_succeed(f"journalctl -u {ISSUER_UNIT} --no-pager")
    assert '"GET / HTTP/1.1" 401' in journal, journal
    assert '"GET / HTTP/1.1" 200' in journal, journal


def test_no_artifact_carries_the_delivered_bytes(delivered: Run) -> None:
    run = delivered
    searched = 0
    for path in sorted(run.artifacts.rglob("*")):
        resolved = path.resolve()
        if not resolved.is_file():
            continue
        searched += 1
        assert run.token not in resolved.read_text(errors="replace"), resolved
    assert searched > 0

    assert run.token not in json.dumps(run.plan)
    assert run.plan[SESSION_VALUE]["files"]["token"]["inPlan"] == "reference"
    for machine in MACHINES:
        store = run.vm(machine).ssh(f"grep -rl {run.token} /nix/store 2>/dev/null")
        assert store.stdout.strip() == "", store.stdout


def test_a_public_generated_value_travels_in_the_plan(delivered: Run) -> None:
    run = delivered
    ca = run.plan[CA_VALUE]["files"]["ca.pub"]
    assert ca["inPlan"] == "value", ca

    published = run.plan[ISSUER_KEY]["provides"]["api"]["exports"]["caCert"]
    assert published["plane"] == "env", published
    assert published["value"].startswith("PLANNER-E2E-CA "), published

    unit = sorted((run.artifact("probe") / "units").iterdir())[0].read_text()
    assert f"CA_CERT={published['value']}" in unit, unit

    record = json.loads(run.vm(PROBE_MACHINE).ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["caCertFirstLine"] == published["value"]
    assert record["caCertLength"] == len(published["value"])
