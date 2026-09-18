"""Three real machines, one generated secret, and the set the plan named.

``nix run .#planner-e2e secret-delivery`` runs this. It builds the folder's
deployment with ``planner build``, boots three rookery VMs from
``$PLANNER_E2E_GUEST_IMAGE``, writes the token it minted into a value source of
its own, puts the deployment on the machines with ``planner apply --values``, and
then asks the machines what they hold and what the units did. One test per
scenario of
``openspec/specs/delivery/real-cluster/spec.md``,
each named after it, and one for the value-source scenario of
``openspec/specs/operator/apply-command/spec.md``

**The phases are ordered and the file order is the order.**

1. every machine is provisioned the way an operator provisions one: the age
   identity whose public line its registry record declares is installed at
   ``/var/lib/planner/age.key``, before anything is applied
2. the deployment is built by the command, in this process and before any
   machine is dialled, and the manifest it wrote is what the tests read
3. the run writes its own bytes into the value source, exactly the files the
   plan declares of a value some machine receives and nothing else
4. one ``planner apply`` writes every value to the set the plan named, seals a
   copy of each beside it and activates the three entries, provider before
   consumer
5. the consumer's unit is the assertion: it authenticated with the delivered
   bytes and was refused without them
6. the value rotates, the reader is stopped under it, and the last phase
   reboots its machine: ``/run`` is emptied and the machine puts its own values
   back out of the copies it can open, with no command run against it

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

import base64
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

# What provisioning leaves on a machine, and the unit an apply installs there.
# The identity file's path is the same in both scopes and is a documented
# provisioning location rather than a plan field: nothing in a deployment
# records it, so the phase that installs it is the only thing that states it.
IDENTITY = Path(__file__).parent / "throwaway-age-identity.txt"
IDENTITY_ROOT = "/var/lib/planner"
IDENTITY_PATH = f"{IDENTITY_ROOT}/age.key"
UNSEAL_UNIT = "planner-unseal.service"
# Where a system manager is given that unit and what pulls it in at boot. The
# guest's own `/etc/systemd/system` is a link into a read-only store, and
# `/run/systemd/system` is emptied by the reboot the unit exists for, so the
# install writes the unit and its `.wants` link into the one directory that is
# writable, persistent and in systemd's own search path.
UNIT_DIRECTORY = "/usr/local/lib/systemd/system"
WANTED = "multi-user.target"


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


def _answers(reported: str) -> dict[str, str]:
    """Return the ``key=value`` lines one machine printed, as a table.

    One case is one ssh command: the guest's sshd is per-connection socket
    activated, so a burst of short logins is answered by the socket's own
    trigger limit and reads as a machine that died. Everything a case observes
    is therefore echoed as a line of this shape in that one command, and a
    value that spanned lines would be a parse no reader could make.
    """
    table: dict[str, str] = {}
    for line in reported.splitlines():
        key, separator, value = line.partition("=")
        if separator:
            table[key] = value
    return table


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

    def sealed_path(self, key: str, name: str) -> str:
        """The path the record states the machine's own copy of one file is kept at.

        Read off the record rather than derived here: the derivation is the
        library's, and a path restated in this file would be the test agreeing
        with a convention instead of reading what the build published.
        """
        return self.value_file(key, name).sealed

    def unsealer(self, machine: str) -> Path:
        """The store path of the program one machine opens its own copies with."""
        stated = self.deployment.machines[machine]
        assert stated.sealed and stated.path is not None, stated
        return stated.path

    def recipient(self, machine: str) -> Any:
        """The public line the plan's own machine record states, or ``None``."""
        return self.deployment.plan[f"machine:{machine}"]["sealRecipient"]

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
def provisioned(booted: Any) -> Any:
    """Phase 1: each machine holds the identity its registry record names.

    Provisioning and not delivery. An operator runs these lines once per
    machine, before the first apply: ``install -d -m 0700`` of the parent, the
    identity file inside it, ``0400``. Here the private half is the committed
    throwaway, because the public line of it is already in the registry the
    build read; minting one per run would move the recipient under every run.

    A phase rather than a preparation of the cut, deliberately: a preparation
    body does not run on a cache hit, so a file it left behind would be an
    earlier run's and the evidence would be a replay.
    """
    encoded = base64.b64encode(IDENTITY.read_bytes()).decode()
    for machine in MACHINES:
        vm = booted.cluster.vm(machine)
        answered = vm.ssh_succeed(
            f"install -d -m 0700 {IDENTITY_ROOT}; "
            f"printf %s {encoded} | base64 -d > {IDENTITY_PATH}; "
            f"chmod 0400 {IDENTITY_PATH}; "
            f"printf 'identity=%s\\n' \"$(stat -c %U:%G:%a {IDENTITY_PATH})\"; "
            f"printf 'parent=%s\\n' \"$(stat -c %U:%G:%a {IDENTITY_ROOT})\"; "
            f"printf 'public=%s\\n' \"$(grep -c public.key {IDENTITY_PATH})\""
        )
        assert _answers(answered) == {
            "identity": f"{USER}:{USER}:400",
            "parent": f"{USER}:{USER}:700",
            "public": "1",
        }, (machine, answered)
    return booted


@pytest.fixture(scope="session")
def run(provisioned: Any) -> Run:
    """Three machines named as the plan names them, this run's secret, and its source."""
    token = secrets.token_hex(16)
    return Run(
        cluster=provisioned.cluster,
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


def _ownership(file: manifest.ValueFile) -> str:
    """What ``stat`` prints for a file delivered as the record states it."""
    return f"{file.owner}:{file.group}:{int(file.mode, 8):o}"


def _damage(run: Run, machine: str, sealed: str) -> None:
    """Replace one machine's sealed copy with bytes it cannot open."""
    run.vm(machine).ssh_succeed(f"printf %s {shlex.quote('not a sealed copy')} > {sealed}")


def test_a_delivery_writes_a_sealed_copy_beside_the_value(applied: Run) -> None:
    """Both machines of the set hold the plaintext as the record states it, and a copy.

    The copy's path is the record's own field, and the step that wrote it is in
    the apply's log beside the value write: sealed first, so a run interrupted
    between the two leaves no copy older than the plaintext beside it.
    """
    run = applied
    record = run.value_file(SESSION_VALUE, "token")
    sealed = run.sealed_path(SESSION_VALUE, "token")

    for machine in (ISSUER_MACHINE, PROBE_MACHINE):
        assert run.recipient(machine) is not None, machine
        answered = run.vm(machine).ssh_succeed(
            f"printf 'plain=%s\\n' \"$(stat -c %U:%G:%a {record.path})\"; "
            f"printf 'copy=%s\\n' \"$(stat -c %U:%G:%a {sealed})\"; "
            f"printf 'bytes=%s\\n' \"$(stat -c %s {sealed})\"; "
            f"printf 'header=%s\\n' \"$(head -c 20 {sealed})\""
        )
        read = _answers(answered)
        assert read["plain"] == _ownership(record), (machine, answered)
        # Ciphertext, whatever the record opens the plaintext to: its one reader
        # is the step that runs as the account owning the identity file.
        assert read["copy"] == f"{USER}:{USER}:400", (machine, answered)
        assert int(read["bytes"]) > 0, (machine, answered)
        assert read["header"].startswith("age-encryption.org/"), (machine, answered)

    assert [step for step in run.steps if step.startswith(f"sealed {SESSION_VALUE} token ")] == [
        f"sealed {SESSION_VALUE} token -> {USER}@{run.address(machine)}:{sealed}"
        for machine in (ISSUER_MACHINE, PROBE_MACHINE)
    ]


def test_a_sealed_copy_is_readable_by_the_unsealing_account_alone(applied: Run) -> None:
    """The file whose record opens the plaintext to an account keeps its copy closed.

    ``owned`` is delivered ``nobody:nogroup 0440``, so the account the record
    names reads the plaintext and nothing else of that value: neither the copy
    nor the directory holding it is reachable by it.
    """
    run = applied
    record = run.value_file(SESSION_VALUE, "owned")
    sealed = run.sealed_path(SESSION_VALUE, "owned")
    directory = os.path.dirname(sealed)

    answered = run.vm(PROBE_MACHINE).ssh_succeed(
        f"printf 'plain=%s\\n' \"$(stat -c %U:%G:%a {record.path})\"; "
        f"printf 'copy=%s\\n' \"$(stat -c %U:%G:%a {sealed})\"; "
        f"printf 'directory=%s\\n' \"$(stat -c %U:%G:%a {directory})\"; "
        f"printf 'opens=%s\\n' "
        f'"$(runuser -u nobody -- cat {sealed} > /dev/null 2>&1 && echo yes || echo no)"; '
        f"printf 'lists=%s\\n' "
        f'"$(runuser -u nobody -- ls {directory} > /dev/null 2>&1 && echo yes || echo no)"; '
        f"printf 'reads=%s\\n' "
        f'"$(runuser -u nobody -- cat {record.path} > /dev/null 2>&1 && echo yes || echo no)"'
    )

    assert _answers(answered) == {
        "plain": _ownership(record),
        "copy": f"{USER}:{USER}:400",
        "directory": f"{USER}:{USER}:700",
        "opens": "no",
        "lists": "no",
        "reads": "yes",
    }, answered


def test_a_machine_that_already_holds_the_unsealer_is_reported_as_unchanged(
    applied: Run,
) -> None:
    """The second apply installs nothing, and the unit is the one the build published.

    What systemd resolved is read back rather than the links alone: an install
    that wrote a link the manager does not read would pass a step here and fail
    the reboot phase, which is the phase that matters.
    """
    run = applied
    again = _apply(run)
    assert again.returncode == 0, again.stdout
    log = again.stdout.splitlines()

    for machine in (ISSUER_MACHINE, PROBE_MACHINE):
        step = f"unseal {machine} on {USER}@{run.address(machine)}"
        assert step in log, log
        assert log[log.index(step) + 1].strip() == "unchanged", log

        published = str(run.unsealer(machine) / UNSEAL_UNIT)
        answered = run.vm(machine).ssh_succeed(
            f"printf 'wanted=%s\\n' \"$(systemctl show -P WantedBy {UNSEAL_UNIT})\"; "
            f"printf 'fragment=%s\\n' \"$(systemctl show -P FragmentPath {UNSEAL_UNIT})\"; "
            f"printf 'unit=%s\\n' "
            f'"$(readlink "$(systemctl show -P FragmentPath {UNSEAL_UNIT})")"; '
            f"printf 'shown=%s\\n' "
            f'"$(systemctl cat {UNSEAL_UNIT} | grep -cF {shlex.quote("ExecStart=")})"; '
            f"printf 'wants=%s\\n' "
            f'"$(readlink {UNIT_DIRECTORY}/{WANTED}.wants/{UNSEAL_UNIT})"'
        )
        # `systemctl is-enabled` answers `alias` for a unit whose file is a link
        # out of the artifact, which is a word about how the file arrived and
        # not about what starts it. What starts it is the target's own answer.
        assert _answers(answered) == {
            "wanted": WANTED,
            "fragment": f"{UNIT_DIRECTORY}/{UNSEAL_UNIT}",
            "unit": published,
            "shown": "1",
            "wants": published,
        }, (machine, answered)


def test_a_machine_holding_a_sealed_copy_it_cannot_open(applied: Run) -> None:
    """A copy that does not open is named per value, and its own apply repairs it.

    The damage is self-healing and the phases below are unaffected: a copy is
    rewritten on every apply, because two sealings of one file differ and there
    is nothing to compare, so the apply at the end of this test puts the machine
    back where the phase found it.
    """
    run = applied
    sealed = run.sealed_path(SESSION_VALUE, "token")
    _damage(run, PROBE_MACHINE, sealed)

    status, reported = _status(run)

    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [
        f"value {SESSION_VALUE} sealed copy does not open on {PROBE_MACHINE}"
    ], reported

    assert _apply(run).returncode == 0
    status, reported = _status(run)
    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [], reported


def test_a_machine_that_seals_and_holds_no_sealed_copy(applied: Run) -> None:
    """A machine holding a plaintext and no copy of it is named as that, and exits zero."""
    run = applied
    sealed = run.sealed_path(SESSION_VALUE, "token")
    probe = run.vm(PROBE_MACHINE)
    probe.ssh_succeed(f"rm {sealed}")

    status, reported = _status(run)

    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [
        f"value {SESSION_VALUE} has no sealed copy on {PROBE_MACHINE}"
    ], reported

    assert _apply(run).returncode == 0
    assert probe.ssh(f"test -s {sealed}").returncode == 0, sealed


def test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them(
    applied: Run,
) -> None:
    """Both copies of a value cleared: the report names it, and an apply puts it back.

    A reboot no longer produces this condition, because a machine that seals
    restores its own plaintexts before its readers start, so the condition is
    stated directly here: the paths the values were written to and the copies
    the machine could have opened them from are cleared together.
    """
    run = applied
    vm = run.vm(PROBE_MACHINE)
    token = run.value_file(SESSION_VALUE, "token")
    owned = run.value_file(SESSION_VALUE, "owned")
    vm.ssh_succeed(
        f"rm -f {token.path} {owned.path} {token.sealed} {owned.sealed}; "
        f"printf 'held=%s\\n' \"$(ls -A {os.path.dirname(token.path)})\""
    )

    status, reported = _status(run)
    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [
        f"value {SESSION_VALUE} missing on {PROBE_MACHINE}",
        f"value {SESSION_VALUE} has no sealed copy on {PROBE_MACHINE}",
    ], reported

    reapplied = _apply(run)
    assert reapplied.returncode == 0, reapplied.stdout
    assert vm.ssh_succeed(f"cat {token.path}").strip() == run.token

    status, reported = _status(run)
    assert status == 0, "\n".join(reported)
    assert [line for line in reported if line.startswith("value ")] == [], reported


def test_a_copy_the_machine_cannot_open_leaves_the_value_absent_and_names_it(
    applied: Run,
) -> None:
    """The machine's own program names the copy it could not open and restores the rest.

    Run on the machine, out of the artifact the apply copied there, because the
    program a machine recovers with is the one in its own closure and not one
    this host has. Both plaintexts are cleared and one copy is damaged, so the
    two answers are in one run: a value left absent and named, and a value put
    back at the ownership its record states.
    """
    run = applied
    vm = run.vm(PROBE_MACHINE)
    token = run.value_file(SESSION_VALUE, "token")
    owned = run.value_file(SESSION_VALUE, "owned")
    unseal = run.unsealer(PROBE_MACHINE) / "bin" / "unseal"

    _damage(run, PROBE_MACHINE, token.sealed)
    answered = vm.ssh_succeed(
        f"rm -f {token.path} {owned.path}; "
        f"said=$({unseal} 2>&1); status=$?; "
        f"printf 'status=%s\\n' \"$status\"; "
        f"printf 'named=%s\\n' "
        f'"$(printf \'%s\\n\' "$said" | grep -cF {shlex.quote("did not open")})"; '
        f"printf 'about=%s\\n' "
        f'"$(printf \'%s\\n\' "$said" | grep -cF {shlex.quote(token.path)})"; '
        f"printf 'restored=%s\\n' "
        f'"$(printf \'%s\\n\' "$said" | grep -cF {shlex.quote(f"unsealed {owned.path}")})"; '
        f"printf 'absent=%s\\n' \"$(test -e {token.path} && echo no || echo yes)\"; "
        f"printf 'owned=%s\\n' \"$(stat -c %U:%G:%a {owned.path})\""
    )

    assert _answers(answered) == {
        "status": "1",
        "named": "1",
        "about": "1",
        "restored": "1",
        "absent": "yes",
        "owned": _ownership(owned),
    }, answered
    assert vm.ssh_succeed(f"cat {owned.path}").strip() == run.token

    # The value it could not open is the operator's to put back, which is one
    # apply, and the phases below start from a machine holding everything.
    assert _apply(run).returncode == 0
    assert vm.ssh_succeed(f"cat {token.path}").strip() == run.token
    assert vm.ssh_succeed(f"systemctl is-active {PROBE_UNIT}").strip() == "active"


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
    """The last phase: the reader's machine rebooted, which is what empties ``/run``.

    The reboot is issued in the guest rather than from outside, so the machine
    shuts down and comes up the way one that was told to does. Nothing is run
    against it afterwards: whatever it holds when the tests below read it, it
    put there itself, out of the copies the last apply left in the sealed root
    and with the identity file provisioning put there. That is the claim this
    phase exists for, and it is last because ``/run`` is still what a reboot
    empties.
    """
    run = halted
    vm = run.vm(PROBE_MACHINE)
    vm.ssh("systemctl reboot")
    vm.wait_for_unit("multi-user.target", timeout=300)
    return run


def test_a_machine_that_rebooted_holds_its_values_again(rebooted: Run) -> None:
    """Every value is at its own path again, with the ownership and mode of its record.

    No command was run against the machine between the reboot and this read.
    The unit the apply installed ran the machine's own program, which opened
    each copy it holds and printed the path of every plaintext it restored.
    """
    run = rebooted
    vm = run.vm(PROBE_MACHINE)
    files = [run.value_file(SESSION_VALUE, name) for name in ("token", "owned")]

    answered = vm.ssh_succeed(
        "; ".join(
            f"printf '{file.name}=%s\\n' \"$(stat -c %U:%G:%a {file.path})\"" for file in files
        )
        + f"; printf 'unseal=%s\\n' \"$(systemctl is-active {UNSEAL_UNIT})\""
        + f"; printf 'restored=%s\\n' \"$(journalctl -b -u {UNSEAL_UNIT} --no-pager -o cat "
        + f'| grep -cF {shlex.quote("unsealed /")})"'
    )

    assert _answers(answered) == {
        files[0].name: _ownership(files[0]),
        files[1].name: _ownership(files[1]),
        "unseal": "active",
        "restored": str(len(files)),
    }, answered
    assert vm.ssh_succeed(f"cat {files[0].path}").strip() == run.token


def test_a_reader_started_after_a_reboot_reads_the_delivered_bytes(rebooted: Run) -> None:
    """The reader came up against the restored file and read the bytes last delivered.

    The phase above stopped it and rotated the value under it, so the bytes in
    its record are the last delivery's and not the ones it read when it last
    ran. The unit that restores the machine's values is ordered before this one,
    which is why the machine starting it on its own is the assertion.
    """
    run = rebooted
    vm = run.vm(PROBE_MACHINE)
    vm.wait_for_unit(PROBE_UNIT, timeout=180)

    record = json.loads(vm.ssh_succeed(f"cat {RECORD_PATH}"))
    assert record["authorizedStatus"] == 200, record
    assert record["anonymousStatus"] == 401, record

    token_file = record["tokenFile"]
    answered = vm.ssh_succeed(
        f"printf 'reader=%s\\n' \"$(systemctl is-active {PROBE_UNIT})\"; "
        f"printf 'token=%s\\n' \"$(cat {token_file})\"; "
        f"printf 'ordered=%s\\n' "
        f'"$(systemctl show -P Before {UNSEAL_UNIT} | grep -cF {shlex.quote(PROBE_UNIT)})"'
    )

    assert _answers(answered) == {
        "reader": "active",
        "token": run.token,
        "ordered": "1",
    }, answered
