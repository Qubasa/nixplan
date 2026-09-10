"""Three real machines, one generated value, and a plan built from what exists.

``nix run .#planner-e2e generated-secret`` runs this. Nothing here writes the
bytes of a value: the generator the deployment declares mints them inside the
external tool's own sandbox, a real `age` backend holds them, and the tool's
deploy step - rendered from the plan by ``secrets/backend.nix`` - carries them to
the machines the plan's delivery set names.

**The phases are ordered and the file order is the order.**

1. the state is read from an empty backend, and the plan built from it carries
   the absence the planner produces for a value nothing has generated
2. generation runs, the state is read again, provenance is recorded, and the plan
   is re-evaluated against what the backend answered
3. the values are deployed by the tool, the three artifacts are activated, and the
   consumer's unit is the assertion: it authenticated with the delivered bytes

``$NIXOS_SECRETS_FLAKE`` is resolved at run time, so this folder skips itself
when the tool cannot be resolved and when the sandbox it needs is unavailable. A
skip is not a pass: `pytest.ini` keeps ``-rs`` so the reason is printed.

rookery is imported at run time for the same reason and is deliberately not an
input of this flake.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest

import delivery
import generation

snapshot = pytest.importorskip(
    "rookery.snapshot",
    reason='rookery is not importable: run .#planner-e2e, or eval "$(planner-e2e-env)"',
)

ISSUER_KEY = "issuer:api@alpha"
PROBE_KEY = "probe:client@beta"
IDLE_KEY = "idle:job@gamma"
ROOT_VALUE = "issuer:vars/root"
TOKEN_VALUE = "issuer:vars/token"
ISSUER_MACHINE = "alpha"
PROBE_MACHINE = "beta"
IDLE_MACHINE = "gamma"
ISSUER_UNIT = "issuer-api-serve.service"
PROBE_UNIT = "probe-client-attest.service"
RECORD_PATH = "/run/generated-secret-attest.json"
MACHINES = (ISSUER_MACHINE, PROBE_MACHINE, IDLE_MACHINE)
HEX = re.compile("^[0-9a-f]{64}$")


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


ARTIFACTS = _env_path("PLANNER_GENERATED_SECRET")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))


@dataclass
class Run:
    """The cluster, the tool, the backend the values live in, and the plan of them."""

    cluster: Any
    artifacts: Path
    root: Path
    tool: Path
    env: dict[str, str]
    store: generation.BackendStore
    configuration: dict[str, Any]
    names: dict[str, str]
    declared: dict[str, Any]
    ungenerated: dict[str, Any] = field(default_factory=dict)
    ungenerated_result: dict[str, Any] = field(default_factory=dict)
    state: dict[str, Any] = field(default_factory=dict)
    # The plan attrset of the generated state, beside the whole result the same
    # evaluation produced: a test reads entries from one and diagnostics from the other.
    plan: dict[str, Any] = field(default_factory=dict)
    result: dict[str, Any] = field(default_factory=dict)
    output: str = ""
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

    def values(self, plan: dict[str, Any]) -> tuple[generation.Value, ...]:
        return generation.values(plan, self.configuration, self.names)

    def published(self, export: str) -> Any:
        return self.plan[ISSUER_KEY]["provides"]["api"]["exports"][export]["value"]


def _identity(root: Path, age: Path) -> dict[str, str]:
    """Mint the run's own age identity and return the backend's environment.

    The storage root is this run's, so two runs cannot collide, and no
    `collect-garbage` is ever invoked: the example backends key their layout on a
    host name, and deleting another run's values is the hazard that follows.
    """
    into = root / "age"
    into.mkdir(parents=True, exist_ok=True)
    identity = into / "identity"
    if not identity.exists():
        minted = subprocess.run(
            [str(age / "bin" / "age-keygen"), "-o", str(identity)],
            capture_output=True,
            text=True,
            check=True,
        )
        (into / "recipient").write_text(
            next(
                line.split(": ")[1]
                for line in minted.stderr.splitlines()
                if line.startswith("Public key: ")
            )
        )
    return {
        "PLANNER_SECRETS_AGE_DIR": str(into / "store"),
        "PLANNER_SECRETS_AGE_IDENTITY": str(identity),
        "PLANNER_SECRETS_AGE_RECIPIENT": (into / "recipient").read_text().strip(),
    }


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=MACHINES, key=KEY)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage every run starts from: three machines, up and usable.

    On a cache hit this body does not run at all - the machines are resumed from
    the cut it took the first time - so nothing here may be a fact a test reads.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def run(booted: Any) -> Run:
    """The tool, the sandbox it needs, and this run's own backend."""
    try:
        tool = generation.tool()
    except generation.GenerationError as refused:
        pytest.skip(str(refused))

    moved = generation.contract_refusal(tool)
    assert moved is None, moved

    problem = generation.sandbox_problem()
    if problem is not None:
        pytest.skip(f"the generator's sandbox cannot run here: {problem}")

    root = delivery.state_root() / "generated-secret"
    root.mkdir(parents=True, exist_ok=True)
    configuration = json.loads((ARTIFACTS / "secrets.json").read_text())
    environment = _identity(root, ARTIFACTS / "age")

    return Run(
        cluster=booted.cluster,
        artifacts=ARTIFACTS,
        root=root,
        tool=tool,
        env=environment,
        store=generation.backend_store(configuration, name="age", env=environment),
        configuration=configuration,
        names=json.loads((ARTIFACTS / "names.json").read_text()),
        declared=json.loads((ARTIFACTS / "plan.json").read_text()),
    )


@pytest.fixture(scope="session")
def generated(run: Run) -> Run:
    """Phase 1 and 2: the state before generation, and the plan after it."""
    if run.observed.get("generated"):
        return run

    values = run.values(run.declared)
    run.ungenerated = generation.state(values, run.store)
    run.ungenerated_result = generation.plan_of(
        ARTIFACTS / "plan.nix", _written(run.root / "ungenerated.json", run.ungenerated)
    )

    run.output = generation.require_success(
        subprocess.run(
            generation.generate_argv(run.tool, ARTIFACTS / "secrets.json"),
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, **run.env},
        ),
        what="generation",
    )

    run.state = generation.state(values, run.store)
    generation.require_generated(values, run.state)

    record = run.root / generation.PROVENANCE_FILE
    generation.write_provenance(record, values)
    generation.require_provenance(values, run.state, generation.read_provenance(record))

    run.result = generation.plan_of(
        ARTIFACTS / "plan.nix", _written(run.root / "state.json", run.state)
    )
    run.plan = run.result["plan"]
    run.observed["generated"] = True
    return run


def _written(path: Path, state: dict[str, Any]) -> Path:
    """Write the state a plan is evaluated against, and return where it landed."""
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
    return path


@pytest.fixture(scope="session")
def delivered(generated: Run) -> Run:
    """Phase 3: the tool deploys the values, then the artifacts are activated."""
    run = generated
    if run.observed.get("delivered"):
        return run

    environment = {
        **os.environ,
        **run.env,
        generation.SSH_OPTIONS_VARIABLE: delivery.ssh_opts(KEY),
    }
    run.cluster.run(generation.deploy_argv(run.tool, ARTIFACTS / "secrets.json"), env=environment)

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
            ssh_key=KEY,
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


def test_an_ungenerated_value_is_absent_not_empty(generated: Run) -> None:
    """Read from an empty backend, every declared file is absent."""
    run = generated
    assert run.ungenerated == {
        ROOT_VALUE: {"key": {"present": False}},
        TOKEN_VALUE: {"fingerprint": {"present": False}, "secret": {"present": False}},
    }

    plan = run.ungenerated_result["plan"]
    assert plan[TOKEN_VALUE]["files"]["secret"]["bytes"] == "absent"
    assert plan[TOKEN_VALUE]["files"]["fingerprint"]["bytes"] == "absent"
    # The planner's own absence, reported against the entry that reads it.
    assert [row["id"] for row in run.ungenerated_result["diagnostics"]] == ["set-entry-absent"]
    assert run.ungenerated_result["applicable"] is False


def test_a_held_file_becomes_a_present_value(generated: Run) -> None:
    """After generation the backend holds every declared file, and the plan carries it."""
    run = generated
    assert generation.regenerated(run.output) == ("issuer:root", "issuer:token")
    assert generation.updated(run.output) == 2

    assert run.state[ROOT_VALUE]["key"] == {"present": True}
    assert run.state[TOKEN_VALUE]["secret"] == {"present": True}

    plan = run.plan
    assert "bytes" not in plan[TOKEN_VALUE]["files"]["secret"]
    assert plan[TOKEN_VALUE]["files"]["secret"]["inPlan"] == "reference"
    assert plan[TOKEN_VALUE]["delivery"] == [ISSUER_MACHINE, PROBE_MACHINE]
    assert plan[TOKEN_VALUE]["deliveryDerivedFrom"] == [
        f"{ISSUER_KEY} owns it",
        f"{PROBE_KEY} named secret in uses.api.reads",
    ]
    assert run.plan[ROOT_VALUE]["deploy"] is False
    # Every absence the ungenerated plan reported is gone, and nothing replaced it.
    assert run.result["diagnostics"] == []
    assert run.result["applicable"] is True


def test_a_public_files_bytes_reach_the_plan(generated: Run) -> None:
    """A public file is fetched and its bytes travel inside the plan."""
    run = generated
    fingerprint = run.state[TOKEN_VALUE]["fingerprint"]["content"]
    assert HEX.match(fingerprint), fingerprint
    assert run.state[TOKEN_VALUE]["fingerprint"]["present"] is True

    assert run.published("fingerprint") == fingerprint
    assert run.plan[TOKEN_VALUE]["files"]["fingerprint"]["inPlan"] == "value"

    # The plan built before generation published no such value.
    published = run.ungenerated_result["plan"][ISSUER_KEY]["provides"]["api"]["exports"]
    assert published["fingerprint"].get("value") is None


def test_a_secret_files_bytes_are_never_fetched(generated: Run) -> None:
    """`get` is invoked for the public file alone, and no secret byte is in the plan."""
    run = generated
    assert run.store.fetched == [("issuer:token", "fingerprint")]
    assert ("issuer:token", "secret") not in run.store.fetched
    assert ("issuer:root", "key") not in run.store.fetched

    for value in (ROOT_VALUE, TOKEN_VALUE):
        for file, record in run.state[value].items():
            secret = run.plan[value]["files"][file]["secrecy"] == "secret"
            assert ("content" in record) is not secret, (value, file, record.keys())


def test_an_unchanged_declaration_is_not_regenerated(generated: Run) -> None:
    """A second run over an unchanged plan updates nothing and refuses nothing."""
    run = generated
    again = generation.require_success(
        subprocess.run(
            generation.generate_argv(run.tool, ARTIFACTS / "secrets.json"),
            capture_output=True,
            text=True,
            check=False,
            env={**os.environ, **run.env},
        ),
        what="a second generation",
    )
    assert generation.updated(again) == 0
    assert generation.regenerated(again) == ()

    values = run.values(run.declared)
    after = generation.state(values, run.store)
    assert after == run.state
    generation.require_provenance(
        values, after, generation.read_provenance(run.root / generation.PROVENANCE_FILE)
    )


def test_the_delivered_bytes_were_generated_not_written(delivered: Run) -> None:
    """The bytes on the machines are the generator's, and no literal of them exists here."""
    run = delivered
    path = run.value_path(TOKEN_VALUE, "secret")

    held = {
        machine: run.vm(machine).ssh_succeed(f"cat {path}").strip()
        for machine in (ISSUER_MACHINE, PROBE_MACHINE)
    }
    assert held[ISSUER_MACHINE] == held[PROBE_MACHINE]
    secret = held[ISSUER_MACHINE]
    assert HEX.match(secret), secret

    # The public half the plan carries is the digest of exactly these bytes, which
    # is what makes them the pair the generator minted.
    record = json.loads(run.vm(PROBE_MACHINE).ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["tokenFingerprint"] == run.published("fingerprint")
    assert record["authorizedStatus"] == 200, record
    assert record["authorizedBody"] == "attested", record
    assert record["anonymousStatus"] == 401, record

    # Nowhere in the folder, nowhere in its artifacts, and on no machine's store.
    searched = 0
    for each in sorted(list(Path(__file__).parent.rglob("*")) + list(run.artifacts.rglob("*"))):
        resolved = each.resolve()
        if not resolved.is_file():
            continue
        searched += 1
        assert secret not in resolved.read_text(errors="replace"), resolved
    assert searched > 0
    assert secret not in json.dumps(run.plan)

    # The value nobody receives is on no machine, and the third machine holds none.
    assert run.plan[ROOT_VALUE]["delivery"] == []
    for machine in MACHINES:
        assert run.vm(machine).ssh(f"test -e {run.value_path(ROOT_VALUE, 'key')}").returncode != 0
    assert run.vm(IDLE_MACHINE).ssh("test -e /run/vars/issuer").returncode != 0
