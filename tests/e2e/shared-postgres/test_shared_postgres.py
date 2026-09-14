"""Two instances of one database module on one machine, on real machines.

``nix run .#planner-e2e shared-postgres`` runs this. It builds the folder's
deployment with ``planner build``, boots two rookery VMs from
``$PLANNER_E2E_GUEST_IMAGE``, mints one password per database into a value
source of its own, applies the deployment with ``planner apply --values``, and
then asks the machines what is serving, what each of them holds and what the
servers answer. One test per scenario of
``openspec/changes/run-a-shared-database-on-real-machines/specs/delivery/real-cluster/spec.md``
and of
``openspec/changes/give-every-instance-its-own-database/specs/delivery/real-cluster/spec.md``,
each named after it.

``alpha`` runs four entries: the shared cluster, the consumer that shares its
machine, the private cluster and the application that owns it. ``beta`` runs the
remote consumer, so a working consumer outside one delivery set is still here.

**No path in this module is written down.** Every one of them is read off the
plan the command built: the configuration file out of the entry's ``configData``
keyset, the data and socket directory and the record out of the units' recorded
environment, the port out of ``alloc.ports``. A broken derivation is a red test
rather than a constant that still matches.

**The phases are ordered and the file order is the order.**

1. the deployment is built by the command, in this process and before any
   machine is dialled
2. the run mints one password per database and writes exactly the files the
   plan declares of a value some machine receives
3. one ``planner apply`` writes each value to the set the plan named and
   activates the five entries, each cluster before the consumers that read it
4. the machines answer: two server processes sharing no host resource, each
   consumer's own row in the instance it wired, each machine's own credential
   and no other's, and each server's own refusal of a credential the other
   published

**One case is one ssh command.** The guest's sshd is per-connection socket
activated, so a burst of short logins is answered by the socket's own trigger
limit and the machine stops accepting connections part way through a test. Each
case therefore runs one command whose output is ``key=value`` lines, compares a
file's bytes on the machine and reports the comparison as one word.

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake,
so the module skips itself when it is absent.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
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

CLUSTER_KEY = "pg:cluster@alpha"
NEAR_KEY = "near-app:client@alpha"
FAR_KEY = "far-app:client@beta"
OWN_KEY = "own-app:client@alpha"
OWN_DB_KEY = "own-app:own@alpha"
EU_VALUE = "pg:vars/password-eu"
US_VALUE = "pg:vars/password-us"
OWN_VALUE = "own-app:vars/password-private"
CLUSTER_MACHINE = "alpha"
NEAR_MACHINE = "alpha"
PRIVATE_MACHINE = "alpha"
FAR_MACHINE = "beta"
BOOTSTRAP_UNIT = "pg-cluster-bootstrap.service"
INIT_UNIT = "pg-cluster-init.service"
SERVER_UNIT = "pg-cluster-server.service"
NEAR_UNIT = "near-app-client-write.service"
FAR_UNIT = "far-app-client-write.service"
OWN_UNIT = "own-app-client-write.service"
OWN_INIT_UNIT = "own-app-own-init.service"
OWN_SERVER_UNIT = "own-app-own-server.service"
MACHINES = (CLUSTER_MACHINE, FAR_MACHINE)
ATTRIBUTE = "planner-e2e-shared-postgres"
CHANGED_ATTRIBUTE = "planner-e2e-shared-postgres-changed"

# Two clusters write two data directories the image has no room for beside two
# delivered closures, and the figure is the stage's rather than the shared
# image's: raising the image would re-key every other folder's cut.
DISK_GIB = 16

# The folder's own declarations, read to assert they state no path the units use.
DECLARATIONS = Path(__file__).parent / "deployment"


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


def _build(target: str) -> manifest.Deployment:
    """Build one deployment with the command, and read what it built.

    This runs in the pytest process rather than through the cluster, because a
    build needs no machine and running it inside the cluster's user namespace
    would put an evaluation and a build there.
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
CHANGED = _build(f"{FLAKE}#{CHANGED_ATTRIBUTE}")


def _value_source(root: Path, deployment: manifest.Deployment, secrets_of: dict[str, str]) -> Path:
    """Write this run's bytes where the command reads them from, and return the directory.

    The layout is ``<dir>/<value entry key>/<file>``, and a value entry key
    carries a ``/`` of its own, so ``pg:vars/password-eu/password`` is a real
    nested path. Which files have to be there is read out of the manifest rather
    than restated: exactly the declared files of every value entry some machine
    receives.

    Args:
        root: A directory this run owns.
        deployment: The built deployment the bytes are for.
        secrets_of: The bytes for each value entry key.

    Returns:
        The value source, readable by this user alone.
    """
    source = root / "shared-postgres-values"
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
            written.write_text(secrets_of[value.key])
            written.chmod(0o600)
    return source


def _answered(reported: str) -> dict[str, str]:
    """The ``key=value`` lines one machine printed, as a record."""
    return dict(line.split("=", 1) for line in reported.splitlines() if "=" in line)


@dataclass
class Run:
    """The cluster, the deployment, this run's two passwords and their source."""

    cluster: Any
    deployment: manifest.Deployment
    key: Path
    passwords: dict[str, str]
    source: Path
    steps: list[str] = field(default_factory=list)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def address(self, machine: str) -> str:
        """The address the plan's own machine record declares."""
        return manifest.machine_address(self.deployment, machine, of=machine)

    def value_path(self, key: str, name: str) -> str:
        """The path the plan records for one file of one generated value."""
        declared = {file.name: file for file in self.deployment.values[key].files}
        return declared[name].path

    def unit_text(self, key: str, unit: str) -> str:
        """One unit file of one placed entry, out of the artifact built for it."""
        entry = self.deployment.entries[key]
        return (manifest.artifact_of(entry) / "units" / unit).read_text()

    def exports(self, capability: str, key: str = CLUSTER_KEY) -> dict[str, Any]:
        """The exports one provider entry published for one capability."""
        published = self.deployment.plan[key]["provides"][capability]["exports"]
        assert isinstance(published, dict), published
        return published

    def unit_env(self, key: str, unit: str, name: str) -> str:
        """One environment variable the plan recorded for one unit of one entry."""
        given = self.deployment.plan[key]["units"][unit]["env"][name]
        assert isinstance(given, str), given
        return given

    def state_dir(self, key: str) -> str:
        """The data and socket directory one cluster entry derived for itself."""
        return self.unit_env(key, "init", "PGDATA")

    def record_path(self, key: str) -> str:
        """The file one consumer entry writes its record to."""
        return self.unit_env(key, "write", "RECORD_PATH")

    def label(self, key: str) -> str:
        """The label one consumer entry writes, as its own declaration resolved it."""
        return self.unit_env(key, "write", "LABEL")

    def config_path(self, key: str) -> str:
        """The configuration file one entry's own server command names."""
        command = self.unit_command(key, "server")
        named = [
            word.removeprefix("config_file=")
            for word in command.split()
            if word.startswith("config_file=")
        ]
        assert len(named) == 1, command
        assert named[0] in self.deployment.plan[key]["configData"], named
        return named[0]

    def hba_path(self, key: str) -> str:
        """The authentication file: the other configuration file the entry declares."""
        declared = sorted(self.deployment.plan[key]["configData"])
        other = [path for path in declared if path != self.config_path(key)]
        assert len(other) == 1, declared
        assert isinstance(other[0], str), other
        return other[0]

    def unit_command(self, key: str, unit: str) -> str:
        """The command the plan recorded for one unit of one entry."""
        command = self.deployment.plan[key]["units"][unit]["command"]
        assert isinstance(command, str), command
        return command

    def directory_mode(self, key: str, unit: str) -> str:
        """The mode one unit's declaration states its state directory is created at."""
        mode = self.deployment.plan[key]["units"][unit]["stateDirectoryMode"]
        assert isinstance(mode, str), mode
        return mode

    def port(self, key: str) -> int:
        """The port one entry claimed."""
        claimed = self.deployment.plan[key]["alloc"]["ports"]["postgres"]
        assert isinstance(claimed, int), claimed
        return claimed

    def socket(self, key: str) -> str:
        """The unix socket one cluster's server listens on, from its own two facts."""
        return f"{self.state_dir(key)}/.s.PGSQL.{self.port(key)}"

    def psql(self) -> str:
        """The client the cluster's own closure carries, on the cluster's machine.

        The package is a declared closure root of the cluster entry, so the path
        is the plan's own answer rather than a name resolved on the machine.
        """
        roots = [
            root
            for root in self.deployment.plan[CLUSTER_KEY]["closure"]
            if re.search(r"-postgresql-[0-9]", root)
        ]
        assert len(roots) == 1, roots
        return f"{roots[0]}/bin/psql"

    def observe(self, machine: str, *commands: str, timeout: int = 180) -> dict[str, str]:
        """Run one ssh command on one machine and read back its ``key=value`` lines."""
        reported = self.vm(machine).ssh_succeed("; ".join(commands), timeout=timeout)
        return _answered(reported)


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=MACHINES, key=KEY, disk_gib=DISK_GIB)
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
    """Two machines named as the plan names them, two passwords, and their source."""
    passwords = {
        EU_VALUE: secrets.token_hex(16),
        US_VALUE: secrets.token_hex(16),
        OWN_VALUE: secrets.token_hex(16),
    }
    return Run(
        cluster=booted.cluster,
        deployment=DEPLOYMENT,
        key=KEY,
        passwords=passwords,
        source=_value_source(delivery.state_root(), DEPLOYMENT, passwords),
    )


@pytest.fixture(scope="session")
def applied(run: Run) -> Run:
    """One ``planner apply --values``, and the machines settled after it.

    The command writes every value before it activates anything and applies the
    provider before the consumers, so one invocation is both delivery phases and
    its step log is the record of both. It goes through ``Cluster.run`` because
    the machines' addresses resolve only there.

    The waits make a read of a machine a read of a settled machine: each
    initialiser, then each server's own port, then each consumer. The seconds
    between a cluster's activation and a consumer's are covered by the retry in
    the consumer's own script, which is what it is there for.
    """
    reported = run.cluster.run(
        [str(CLI), "apply", str(run.deployment.root), "--values", str(run.source)],
        env=delivery.command_env(dict(os.environ), run.key),
    )
    run.steps.extend(reported.stdout.splitlines())

    cluster = run.vm(CLUSTER_MACHINE)
    for key, init, server in (
        (CLUSTER_KEY, INIT_UNIT, SERVER_UNIT),
        (OWN_DB_KEY, OWN_INIT_UNIT, OWN_SERVER_UNIT),
    ):
        cluster.wait_for_unit(init, timeout=300)
        cluster.wait_for_unit(server, timeout=300)
        cluster.wait_until_succeeds(f"ss -ltn | grep -q ':{run.port(key)}'", timeout=120)
    cluster.wait_for_unit(NEAR_UNIT, timeout=300)
    cluster.wait_for_unit(OWN_UNIT, timeout=300)

    run.vm(FAR_MACHINE).wait_for_unit(FAR_UNIT, timeout=300)
    return run


def test_two_instances_take_one_database_each(applied: Run) -> None:
    """One provider entry, two consumer entries, and two different data sources.

    Read off the plan and the artifacts rather than off a machine: what a
    consumer was given is decided before anything is dialled.
    """
    run = applied
    placed = sorted(key for key in run.deployment.entries)
    assert placed == sorted([CLUSTER_KEY, NEAR_KEY, FAR_KEY, OWN_KEY, OWN_DB_KEY]), placed

    # Neither consumer of the shared cluster carries the database its module
    # owns: the instance cut it, so there is no entry of it to place.
    assert not [key for key in placed if key.startswith(("near-app:own", "far-app:own"))], placed

    eu = run.exports("eu")
    us = run.exports("us")
    assert eu["dsn"]["value"] != us["dsn"]["value"], (eu, us)

    near = run.unit_text(NEAR_KEY, NEAR_UNIT)
    far = run.unit_text(FAR_KEY, FAR_UNIT)
    assert f"DB_DSN={eu['dsn']['value']}" in near, near
    assert f"DB_DSN={us['dsn']['value']}" in far, far
    assert us["dsn"]["value"] not in near, near
    assert eu["dsn"]["value"] not in far, far

    # And one provider behind them: both capabilities are the same entry's.
    assert set(run.deployment.plan[CLUSTER_KEY]["provides"]) == {"eu", "us"}


def test_a_consumer_on_another_machine_reads_over_the_address_the_plan_recorded(
    applied: Run,
) -> None:
    run = applied
    assert run.deployment.entries[FAR_KEY].machine == FAR_MACHINE
    assert run.deployment.entries[CLUSTER_KEY].machine == CLUSTER_MACHINE

    published = run.exports("us")["dsn"]["value"]
    address = run.address(CLUSTER_MACHINE)
    port = run.port(CLUSTER_KEY)
    assert published == f"postgresql://app_us@{address}:{port}/us", published

    answered = run.observe(
        FAR_MACHINE,
        f"printf 'unit=%s\\n' \"$(systemctl is-active {FAR_UNIT})\"",
        f"sed 's/^/record_/' {shlex.quote(run.record_path(FAR_KEY))}",
    )
    assert answered["unit"] == "active", answered
    assert answered["record_host"] == address, answered
    assert answered["record_port"] == str(port), answered
    assert answered["record_database"] == "us", answered
    assert answered["record_user"] == "app_us", answered
    assert answered["record_dsn"] == published, answered
    # Its own database holds its own row and no other consumer's.
    assert answered["record_labels"] == "far", answered


def test_one_process_is_behind_both_capabilities(applied: Run) -> None:
    """One server, two databases, and a one-shot that applied and exited.

    "One process" is read three ways in one command: the main pid the service
    manager holds for the long-running unit is the pid the cluster's own
    `postmaster.pid` names, and each database answers with the same cluster
    identifier and the same start time.
    """
    run = applied
    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.port(CLUSTER_KEY)
    declared = run.state_dir(CLUSTER_KEY)
    serves = run.deployment.plan[CLUSTER_KEY]["units"]["server"]["command"]

    def asks(database: str, name: str, query: str) -> str:
        password = run.passwords[EU_VALUE if database == "eu" else US_VALUE]
        user = "app_eu" if database == "eu" else "app_us"
        return (
            f"printf '{database}_{name}=%s\\n' \"$(PGPASSWORD={shlex.quote(password)} {psql}"
            f' -h {address} -p {port} -U {user} -d {database} -tAc {shlex.quote(query)})"'
        )

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'server=%s\\n' \"$(systemctl show -P MainPID {SERVER_UNIT})\"",
        f"printf 'server_state=%s\\n' \"$(systemctl is-active {SERVER_UNIT})\"",
        f"printf 'postmaster=%s\\n' \"$(head -1 {shlex.quote(declared)}/postmaster.pid)\"",
        f"printf 'init_state=%s\\n' \"$(systemctl is-active {INIT_UNIT})\"",
        f"printf 'init_type=%s\\n' \"$(systemctl show -P Type {INIT_UNIT})\"",
        f"printf 'init_result=%s\\n' \"$(systemctl show -P Result {INIT_UNIT})\"",
        f"printf 'init_main=%s\\n' \"$(systemctl show -P MainPID {INIT_UNIT})\"",
        asks("eu", "identifier", "SELECT system_identifier FROM pg_control_system()"),
        asks("us", "identifier", "SELECT system_identifier FROM pg_control_system()"),
        asks("eu", "started", "SELECT pg_postmaster_start_time()"),
        asks("us", "started", "SELECT pg_postmaster_start_time()"),
    )

    assert f"-D {declared} " in serves, serves
    assert answered["server_state"] == "active", answered
    assert answered["server"].isdigit() and answered["server"] != "0", answered
    assert answered["server"] == answered["postmaster"], answered

    # Both capabilities are served out of one cluster, started once.
    assert answered["eu_identifier"] == answered["us_identifier"], answered
    assert answered["eu_identifier"].isdigit(), answered
    assert answered["eu_started"] == answered["us_started"], answered

    # The one-shot applied and exited; the long-running unit is what remains.
    assert answered["init_state"] == "active", answered
    assert answered["init_type"] == "oneshot", answered
    assert answered["init_result"] == "success", answered
    assert answered["init_main"] == "0", answered


def test_a_credential_of_one_capability_is_refused_by_the_other(applied: Run) -> None:
    """The server's own answer, read from the machine, and not a plan claim."""
    run = applied
    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.port(CLUSTER_KEY)
    eu = shlex.quote(run.passwords[EU_VALUE])

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'own=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port}"
        " -U app_eu -d eu -tAc 'SELECT current_database()' 2>&1 | tr -d '\\n')\"",
        f"printf 'other=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port}"
        " -U app_us -d us -tAc 'SELECT current_database()' 2>&1 | tr '\\n' ' ')\"",
        f"printf 'status=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port}"
        " -U app_us -d us -tAc 'SELECT 1' >/dev/null 2>&1; echo $?)\"",
    )
    assert answered["own"] == "eu", answered
    assert answered["status"] != "0", answered
    assert "password authentication failed" in answered["other"], answered
    assert "app_us" in answered["other"], answered


def test_a_consumers_machine_holds_its_own_credential_only(applied: Run) -> None:
    run = applied
    eu_path = run.value_path(EU_VALUE, "password")
    us_path = run.value_path(US_VALUE, "password")

    assert run.deployment.plan[EU_VALUE]["delivery"] == [CLUSTER_MACHINE]
    assert run.deployment.plan[US_VALUE]["delivery"] == [CLUSTER_MACHINE, FAR_MACHINE]
    assert run.deployment.plan[EU_VALUE]["deliveryDerivedFrom"] == [
        f"{NEAR_KEY} named password in uses.db.reads",
        f"{CLUSTER_KEY} owns it",
    ]
    assert run.deployment.plan[US_VALUE]["deliveryDerivedFrom"] == [
        f"{FAR_KEY} named password in uses.db.reads",
        f"{CLUSTER_KEY} owns it",
    ]

    held = run.observe(
        FAR_MACHINE,
        f"printf 'us=%s\\n' \"$(printf %s {shlex.quote(run.passwords[US_VALUE])}"
        f' | cmp -s - {us_path} && echo same || echo differs)"',
        f"printf 'us_mode=%s\\n' \"$(stat -c %a {us_path})\"",
        f"printf 'us_owner=%s\\n' \"$(stat -c %U:%G {us_path})\"",
        f"printf 'eu=%s\\n' \"$(test -e {eu_path} && echo present || echo absent)\"",
        f"printf 'held=%s\\n' \"$(ls -A {os.path.dirname(os.path.dirname(us_path))}"
        " | tr '\\n' ' ')\"",
    )
    assert held["us"] == "same", held
    assert held["us_mode"] == "440", held
    assert held["us_owner"] == "postgres:postgres", held
    assert held["eu"] == "absent", held
    assert held["held"].split() == ["password-us"], held

    both = run.observe(
        CLUSTER_MACHINE,
        f"printf 'eu=%s\\n' \"$(printf %s {shlex.quote(run.passwords[EU_VALUE])}"
        f' | cmp -s - {eu_path} && echo same || echo differs)"',
        f"printf 'us=%s\\n' \"$(printf %s {shlex.quote(run.passwords[US_VALUE])}"
        f' | cmp -s - {us_path} && echo same || echo differs)"',
    )
    assert both["eu"] == "same", both
    assert both["us"] == "same", both


def test_a_working_consumer_is_outside_one_delivery_set(applied: Run) -> None:
    """beta runs a consumer of one capability, so its absence is an answer."""
    run = applied
    assert FAR_MACHINE not in run.deployment.values[EU_VALUE].delivery
    assert f"activate {FAR_KEY} (flakelet) on root@{run.address(FAR_MACHINE)}" in run.steps, (
        run.steps
    )

    eu_path = run.value_path(EU_VALUE, "password")
    answered = run.observe(
        FAR_MACHINE,
        f"printf 'unit=%s\\n' \"$(systemctl is-active {FAR_UNIT})\"",
        f"printf 'eu=%s\\n' \"$(test -e {eu_path} && echo present || echo absent)\"",
        f"printf 'eu_dir=%s\\n' \"$(test -e {os.path.dirname(eu_path)}"
        ' && echo present || echo absent)"',
        f"printf 'rows=%s\\n' \"$(grep -o 'far' {shlex.quote(run.record_path(FAR_KEY))}"
        ' | head -1)"',
    )
    assert answered["unit"] == "active", answered
    assert answered["eu"] == "absent", answered
    assert answered["eu_dir"] == "absent", answered
    assert answered["rows"] == "far", answered


def test_an_instance_that_keeps_its_own_database_wires_nothing(applied: Run) -> None:
    """The same module, uncut: it runs the database it owns and reads no shared one.

    The two instances above are cuts of this composition, so the claim the folder
    makes is that one module source serves both shapes. Here the binding the
    module wrote is what resolves the slot: the read names this instance's own
    member, no wire of the deployment names it, and the row it writes is against
    a server nobody else talks to.
    """
    run = applied
    read = run.deployment.plan[OWN_KEY]["reads"]["db"]

    assert read["entry"] == OWN_DB_KEY, read
    assert read["wire"] == {"instance": "own-app", "provides": "private"}, read
    assert run.deployment.plan[OWN_VALUE]["delivery"] == [PRIVATE_MACHINE]
    assert run.deployment.entries[OWN_DB_KEY].machine == PRIVATE_MACHINE

    # Nothing of the shared cluster reaches it: neither capability is in its
    # reads, and neither of the shared cluster's values is named by it.
    assert read["values"]["dsn"] != run.exports("eu")["dsn"]["value"]
    assert read["values"]["dsn"] != run.exports("us")["dsn"]["value"]
    assert read["values"]["password"]["path"] == run.value_path(OWN_VALUE, "password"), read

    answered = run.observe(
        PRIVATE_MACHINE,
        f"printf 'client=%s\\n' \"$(systemctl is-active {OWN_UNIT})\"",
        f"printf 'server=%s\\n' \"$(systemctl is-active {OWN_SERVER_UNIT})\"",
        f"printf 'data=%s\\n' \"$(test -s {shlex.quote(run.state_dir(OWN_DB_KEY))}/PG_VERSION"
        ' && echo present || echo absent)"',
        f"sed 's/^/record_/' {shlex.quote(run.record_path(OWN_KEY))}",
    )
    assert answered["client"] == "active", answered
    assert answered["server"] == "active", answered
    assert answered["data"] == "present", answered
    assert answered["record_database"] == "private", answered
    assert answered["record_user"] == "app_private", answered
    assert answered["record_host"] == run.address(PRIVATE_MACHINE), answered
    assert answered["record_labels"] == "own", answered


def test_two_instances_of_one_module_run_on_one_machine(applied: Run) -> None:
    """Two servers of one module on one machine, sharing no host resource.

    The six facts the module derived - two data directories, two ports, two
    sockets - are read off the plan and are pairwise different there. The
    machine is then asked which process each of them belongs to: the main pid
    the service manager keeps for a unit is the pid written in that server's own
    data directory, so neither answer is about the other server.
    """
    run = applied
    assert run.deployment.entries[CLUSTER_KEY].machine == CLUSTER_MACHINE
    assert run.deployment.entries[OWN_DB_KEY].machine == CLUSTER_MACHINE

    derived = [
        run.state_dir(CLUSTER_KEY),
        run.state_dir(OWN_DB_KEY),
        str(run.port(CLUSTER_KEY)),
        str(run.port(OWN_DB_KEY)),
        run.socket(CLUSTER_KEY),
        run.socket(OWN_DB_KEY),
    ]
    assert len(set(derived)) == len(derived), derived
    assert run.config_path(CLUSTER_KEY) != run.config_path(OWN_DB_KEY)

    def asks(name: str, key: str, unit: str) -> tuple[str, ...]:
        state = shlex.quote(run.state_dir(key))
        return (
            f"printf '{name}_state=%s\\n' \"$(systemctl is-active {unit})\"",
            f"printf '{name}_pid=%s\\n' \"$(systemctl show -P MainPID {unit})\"",
            f"printf '{name}_held=%s\\n' \"$(head -1 {state}/postmaster.pid)\"",
            f"printf '{name}_socket=%s\\n' \"$(test -S {shlex.quote(run.socket(key))}"
            ' && echo present || echo absent)"',
            f"printf '{name}_listeners=%s\\n' \"$(ss -ltn | grep -c ':{run.port(key)} ')\"",
        )

    answered = run.observe(
        CLUSTER_MACHINE,
        *asks("shared", CLUSTER_KEY, SERVER_UNIT),
        *asks("private", OWN_DB_KEY, OWN_SERVER_UNIT),
    )

    for name in ("shared", "private"):
        assert answered[f"{name}_state"] == "active", answered
        assert answered[f"{name}_pid"].isdigit(), answered
        assert answered[f"{name}_pid"] != "0", answered
        assert answered[f"{name}_pid"] == answered[f"{name}_held"], answered
        assert answered[f"{name}_socket"] == "present", answered
        assert answered[f"{name}_listeners"] == "1", answered
    assert answered["shared_pid"] != answered["private_pid"], answered


def test_every_path_a_unit_uses_comes_from_the_plan(run: Run) -> None:
    """No path this module asserts is written down, here or in the deployment.

    Each one carries the instance and the member of the entry that uses it,
    which is what makes two entries of one module on one machine claim two of
    everything, and none of them appears in the folder's own declarations.
    """
    derived = {
        CLUSTER_KEY: (
            run.state_dir(CLUSTER_KEY),
            run.config_path(CLUSTER_KEY),
            run.hba_path(CLUSTER_KEY),
        ),
        OWN_DB_KEY: (
            run.state_dir(OWN_DB_KEY),
            run.config_path(OWN_DB_KEY),
            run.hba_path(OWN_DB_KEY),
        ),
        NEAR_KEY: (run.record_path(NEAR_KEY),),
        FAR_KEY: (run.record_path(FAR_KEY),),
        OWN_KEY: (run.record_path(OWN_KEY),),
    }

    for key, paths in derived.items():
        instance, member = key.split("@")[0].split(":")
        for path in paths:
            assert f"{instance}-{member}" in path, (key, path)

    used = [path for paths in derived.values() for path in paths]
    assert len(set(used)) == len(used), used

    records = [run.record_path(key) for key in (NEAR_KEY, FAR_KEY, OWN_KEY)]
    assert len({os.path.dirname(path) for path in records}) == len(records), records

    for source in sorted(DECLARATIONS.rglob("*.nix")):
        written = source.read_text()
        for path in used:
            assert path not in written, (source, path)


def test_each_application_reaches_the_database_it_wired(applied: Run) -> None:
    """Each row is in the instance its application wired, and nowhere else.

    The evidence is the servers' own answers. `initdb` mints a cluster
    identifier, so the two instances report two, and each consumer's record
    carries the one the server it reached reported to it.
    """
    run = applied
    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    identity = "SELECT system_identifier FROM pg_control_system()"
    labels = "SELECT string_agg(label, ',' ORDER BY label) FROM notes"

    def asks(name: str, key: str, user: str, database: str, value: str, query: str) -> str:
        return (
            f"printf '{name}=%s\\n' \"$(PGPASSWORD={shlex.quote(run.passwords[value])} {psql}"
            f" -h {address} -p {run.port(key)} -U {user} -d {database}"
            f' -tAc {shlex.quote(query)})"'
        )

    here = run.observe(
        CLUSTER_MACHINE,
        f"sed 's/^/near_/' {shlex.quote(run.record_path(NEAR_KEY))}",
        f"sed 's/^/own_/' {shlex.quote(run.record_path(OWN_KEY))}",
        asks("shared_identity", CLUSTER_KEY, "app_eu", "eu", EU_VALUE, identity),
        asks("private_identity", OWN_DB_KEY, "app_private", "private", OWN_VALUE, identity),
        asks("eu_rows", CLUSTER_KEY, "app_eu", "eu", EU_VALUE, labels),
        asks("us_rows", CLUSTER_KEY, "app_us", "us", US_VALUE, labels),
        asks("private_rows", OWN_DB_KEY, "app_private", "private", OWN_VALUE, labels),
    )
    there = run.observe(
        FAR_MACHINE,
        f"sed 's/^/far_/' {shlex.quote(run.record_path(FAR_KEY))}",
    )

    assert here["shared_identity"].isdigit(), here
    assert here["private_identity"].isdigit(), here
    assert here["shared_identity"] != here["private_identity"], here

    assert here["near_identifier"] == here["shared_identity"], here
    assert there["far_identifier"] == here["shared_identity"], (here, there)
    assert here["own_identifier"] == here["private_identity"], here

    assert here["eu_rows"] == run.label(NEAR_KEY), here
    assert here["us_rows"] == "far", here
    assert here["private_rows"] == "own", here

    assert here["near_database"] == "eu", here
    assert there["far_database"] == "us", there
    assert here["own_database"] == "private", here
    assert here["own_port"] == str(run.port(OWN_DB_KEY)), here
    assert here["near_port"] == str(run.port(CLUSTER_KEY)), here


def test_neither_cluster_carries_the_others_databases(applied: Run) -> None:
    """Each server's own list of databases, read over its own socket.

    The socket is the one the module derived, so the question reaches the
    instance that owns it whatever the other is listening on. `postgres` is
    `initdb`'s maintenance database and belongs to no declaration; every other
    name a server holds is one the deployment declared for that instance.
    """
    run = applied
    psql = shlex.quote(run.psql())
    query = (
        "SELECT string_agg(datname, ',' ORDER BY datname) FROM pg_database WHERE NOT datistemplate"
    )

    def asks(name: str, key: str, user: str, database: str) -> str:
        # The port too: a socket file is named after one, so the directory alone
        # reaches whichever instance happens to hold the compiled-in default.
        return (
            f"printf '{name}=%s\\n' \"$({psql} -h {shlex.quote(run.state_dir(key))}"
            f" -p {run.port(key)} -U {user} -d {database} -tAc {shlex.quote(query)}"
            " 2>&1 | tr '\\n' ' ')\""
        )

    answered = run.observe(
        CLUSTER_MACHINE,
        asks("shared", CLUSTER_KEY, "app_eu", "eu"),
        asks("private", OWN_DB_KEY, "app_private", "private"),
    )

    held = {name: answered[name].strip().split(",") for name in ("shared", "private")}
    declared = {
        "shared": sorted(run.deployment.plan[CLUSTER_KEY]["provides"]),
        "private": sorted(run.deployment.plan[OWN_DB_KEY]["provides"]),
    }
    for name, names in held.items():
        assert names == sorted([*declared[name], "postgres"]), answered
        for other in declared["private" if name == "shared" else "shared"]:
            assert other not in names, answered


def test_a_credential_of_the_shared_cluster_is_refused_by_the_private_one(applied: Run) -> None:
    """The private server's own refusal, read from the machine.

    Two refusals, because the shared instance published two things the private
    server has never stored: a password, and a role to present it as. Both come
    back as one sentence, because a server that named the missing role would be
    answering whether it exists. The control is the private instance's own
    credential on the same port.
    """
    run = applied
    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.port(OWN_DB_KEY)
    eu = shlex.quote(run.passwords[EU_VALUE])
    own = shlex.quote(run.passwords[OWN_VALUE])

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'refused=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port}"
        " -U app_private -d private -tAc 'SELECT current_database()' 2>&1 | tr '\\n' ' ')\"",
        f"printf 'status=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port}"
        " -U app_private -d private -tAc 'SELECT 1' >/dev/null 2>&1; echo $?)\"",
        f"printf 'stranger=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port}"
        " -U app_eu -d private -tAc 'SELECT 1' 2>&1 | tr '\\n' ' ')\"",
        f"printf 'own=%s\\n' \"$(PGPASSWORD={own} {psql} -h {address} -p {port}"
        " -U app_private -d private -tAc 'SELECT current_database()' 2>&1 | tr -d '\\n')\"",
    )
    assert answered["status"] != "0", answered
    assert "password authentication failed" in answered["refused"], answered
    assert "app_private" in answered["refused"], answered
    assert "password authentication failed" in answered["stranger"], answered
    assert "app_eu" in answered["stranger"], answered
    assert answered["own"] == "private", answered


def test_the_private_clusters_credential_is_on_its_own_machine_only(applied: Run) -> None:
    """The value backing the private instance is on the machine that runs it."""
    run = applied
    own_path = run.value_path(OWN_VALUE, "password")
    directory = os.path.dirname(os.path.dirname(own_path))

    assert run.deployment.plan[OWN_VALUE]["delivery"] == [PRIVATE_MACHINE]
    assert run.deployment.plan[OWN_VALUE]["deliveryDerivedFrom"] == [
        f"{OWN_KEY} named password in uses.db.reads",
        f"{OWN_DB_KEY} owns it",
    ]

    held = run.observe(
        PRIVATE_MACHINE,
        f"printf 'bytes=%s\\n' \"$(printf %s {shlex.quote(run.passwords[OWN_VALUE])}"
        f' | cmp -s - {own_path} && echo same || echo differs)"',
        f"printf 'mode=%s\\n' \"$(stat -c %a {own_path})\"",
        f"printf 'owner=%s\\n' \"$(stat -c %U:%G {own_path})\"",
        f"printf 'held=%s\\n' \"$(ls -A {directory} | tr '\\n' ' ')\"",
    )
    assert held["bytes"] == "same", held
    assert held["mode"] == "440", held
    assert held["owner"] == "postgres:postgres", held
    assert held["held"].split() == ["password-private"], held

    elsewhere = run.observe(
        FAR_MACHINE,
        f"printf 'value=%s\\n' \"$(test -e {own_path} && echo present || echo absent)\"",
        f"printf 'directory=%s\\n' \"$(test -e {directory} && echo present || echo absent)\"",
    )
    assert elsewhere["value"] == "absent", elsewhere
    assert elsewhere["directory"] == "absent", elsewhere


def test_data_written_before_a_restart_is_readable_after_it(applied: Run) -> None:
    """The server is restarted deliberately; the state and the one-shot both hold."""
    run = applied
    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.port(CLUSTER_KEY)
    eu = shlex.quote(run.passwords[EU_VALUE])
    read = (
        f"PGPASSWORD={eu} {psql} -h {address} -p {port} -U app_eu -d eu"
        " -tAc \"SELECT string_agg(label, ',' ORDER BY label) FROM notes\""
    )

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'init_before=%s\\n' \"$(systemctl show -P ExecMainStartTimestamp {INIT_UNIT})\"",
        f"printf 'server_before=%s\\n' \"$(systemctl show -P MainPID {SERVER_UNIT})\"",
        f"printf 'rows_before=%s\\n' \"$({read})\"",
        f"systemctl restart {SERVER_UNIT}",
        f"printf 'server_after=%s\\n' \"$(systemctl show -P MainPID {SERVER_UNIT})\"",
        f"printf 'server_state=%s\\n' \"$(systemctl is-active {SERVER_UNIT})\"",
        f"for _ in $(seq 1 60); do {read} >/dev/null 2>&1 && break; sleep 2; done",
        f"printf 'rows_after=%s\\n' \"$({read})\"",
        f"printf 'init_after=%s\\n' \"$(systemctl show -P ExecMainStartTimestamp {INIT_UNIT})\"",
        f"printf 'init_state=%s\\n' \"$(systemctl is-active {INIT_UNIT})\"",
        timeout=300,
    )

    assert answered["rows_before"] == run.label(NEAR_KEY), answered
    assert answered["rows_after"] == run.label(NEAR_KEY), answered
    assert answered["server_state"] == "active", answered
    assert answered["server_after"] != answered["server_before"], answered
    assert answered["init_after"] == answered["init_before"], answered
    assert answered["init_state"] == "active", answered


def test_the_server_reads_the_configuration_file_the_artifact_carries(applied: Run) -> None:
    """The bytes are the build's, the bind is the declared path, and the server read it.

    The file's bytes are compared on the machine and reported as one word,
    because a value spanning lines is a parse the reader cannot make. They are
    compared inside the unit's own mount namespace: `BindReadOnlyPaths=` is the
    unit's, and what the host holds at that path is the empty mount point
    systemd created for it.

    `max_connections` is the observation that the server read the file rather
    than a flag: the compiled-in default is 100. `SHOW config_file` is not, and
    neither is `pg_settings.sourcefile`: both are superuser-only and answer a
    database owner with nothing.
    """
    run = applied
    conf = run.config_path(CLUSTER_KEY)
    carried = run.deployment.entries[CLUSTER_KEY].path
    assert carried is not None
    built = (carried / f"files{conf}").read_bytes()
    digest = hashlib.sha256(built).hexdigest()
    bound = f"BindReadOnlyPaths={(carried / f'files{conf}').resolve()}:{conf}"

    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.port(CLUSTER_KEY)
    eu = shlex.quote(run.passwords[EU_VALUE])
    inside = (
        f'nsenter --mount --target "$(systemctl show -P MainPID {SERVER_UNIT})"'
        f" sha256sum {shlex.quote(conf)} | cut -d' ' -f1"
    )

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'inside=%s\\n' \"$({inside})\"",
        f"printf 'onTheHost=%s\\n' \"$(stat -c %s {shlex.quote(conf)})\"",
        f"printf 'connections=%s\\n' \"$(PGPASSWORD={eu} {psql}"
        f" -h {address} -p {port} -U app_eu -d eu -tAc"
        f' {shlex.quote("SELECT setting FROM pg_settings WHERE name = 'max_connections'")})"',
    )

    assert answered["inside"] == digest, answered
    assert answered["onTheHost"] == "0", answered
    assert answered["connections"] == "32", answered
    # The unit binds the artifact's own store path, so copying the artifact
    # copied the bytes.
    assert bound in (carried / "units" / f"{SERVER_UNIT}").read_text()
    # No flag carries what the file carries.
    assert "max_connections" not in run.deployment.plan[CLUSTER_KEY]["units"]["server"]["command"]


def test_a_killed_daemon_is_running_again_without_an_apply(applied: Run) -> None:
    """The service manager restarts the server; nothing dials the machine to do it."""
    run = applied
    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'before=%s\\n' \"$(systemctl show -P MainPID {SERVER_UNIT})\"",
        f"printf 'policy=%s\\n' \"$(systemctl show -P Restart {SERVER_UNIT})\"",
        f'kill -9 "$(systemctl show -P MainPID {SERVER_UNIT})"',
        f"for _ in $(seq 1 60); do"
        f' [ "$(systemctl is-active {SERVER_UNIT})" = active ] && break; sleep 2; done',
        f"printf 'state=%s\\n' \"$(systemctl is-active {SERVER_UNIT})\"",
        f"printf 'after=%s\\n' \"$(systemctl show -P MainPID {SERVER_UNIT})\"",
        f"printf 'restarts=%s\\n' \"$(systemctl show -P NRestarts {SERVER_UNIT})\"",
        f"printf 'init=%s\\n' \"$(systemctl show -P ExecMainStartTimestamp {INIT_UNIT})\"",
        timeout=300,
    )

    assert answered["policy"] == "on-failure", answered
    assert answered["state"] == "active", answered
    assert answered["after"].isdigit() and answered["after"] != "0", answered
    assert answered["after"] != answered["before"], answered
    assert int(answered["restarts"]) >= 1, answered


def test_no_artifact_carries_a_delivered_password(applied: Run) -> None:
    """Neither password is in the build, in the plan or in either machine's store."""
    run = applied
    searched: list[Path] = []
    pending = [run.deployment.root]
    while pending:
        for child in sorted(pending.pop().iterdir()):
            if child.resolve().is_dir():
                pending.append(child)
            else:
                searched.append(child)

    body = json.dumps(run.deployment.plan)
    for password in run.passwords.values():
        assert password not in body
        for path in searched:
            assert password not in path.read_text(errors="replace"), path

    for key in (EU_VALUE, US_VALUE):
        assert run.deployment.plan[key]["files"]["password"]["inPlan"] == "reference"

    pattern = "|".join(run.passwords.values())
    for machine in MACHINES:
        found = run.vm(machine).ssh(f"grep -rlE {shlex.quote(pattern)} /nix/store 2>/dev/null")
        assert found.stdout.strip() == "", found.stdout


def test_each_service_reads_its_own_credential(applied: Run) -> None:
    """No unit of this deployment is root, and each one opens the file it needs.

    The cluster's units run as the account the password is delivered to, and the
    consumer runs as another account that declares that account's group. Both
    are read from the machines: the unit's `User=`, the account the process
    actually has, and whether that account can open the path the plan gave it.
    """
    run = applied
    eu_path = run.value_path(EU_VALUE, "password")
    us_path = run.value_path(US_VALUE, "password")

    cluster_units = run.deployment.plan[CLUSTER_KEY]["units"]
    assert cluster_units["init"]["user"] == "postgres", cluster_units
    assert cluster_units["server"]["user"] == "postgres", cluster_units
    consumer = run.deployment.plan[FAR_KEY]["units"]["write"]
    assert consumer["user"] == "nobody", consumer

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'init_user=%s\\n' \"$(systemctl show -P User {shlex.quote(INIT_UNIT)})\"",
        f"printf 'server_account=%s\\n' \"$(ps -o user= -p"
        f' "$(systemctl show -P MainPID {shlex.quote(SERVER_UNIT)})" | tr -d " ")"',
        f"printf 'eu_open=%s\\n' \"$(runuser -u postgres -- test -r {eu_path}"
        f' && echo yes || echo no)"',
        f"printf 'us_open=%s\\n' \"$(runuser -u postgres -- test -r {us_path}"
        f' && echo yes || echo no)"',
    )
    assert answered["init_user"] == "postgres", answered
    assert answered["server_account"] == "postgres", answered
    assert answered["eu_open"] == "yes", answered
    assert answered["us_open"] == "yes", answered

    far = run.observe(
        FAR_MACHINE,
        f"printf 'unit_user=%s\\n' \"$(systemctl show -P User {shlex.quote(FAR_UNIT)})\"",
        f"printf 'groups=%s\\n' \"$(systemctl show -P SupplementaryGroups"
        f' {shlex.quote(FAR_UNIT)})"',
        f"printf 'reads=%s\\n' \"$(runuser -u nobody -g postgres -- cat {us_path}"
        f' >/dev/null && echo yes || echo no)"',
        f"printf 'root_only=%s\\n' \"$(runuser -u nobody -- test -r {us_path}"
        f' && echo yes || echo no)"',
    )
    assert far["unit_user"] == "nobody", far
    assert far["groups"] == "postgres", far
    # The group is what admits it: the same account without that group cannot.
    assert far["reads"] == "yes", far
    assert far["root_only"] == "no", far


def test_the_init_step_creates_no_directory_of_its_own(applied: Run) -> None:
    """The data directory is the service manager's, and the step makes nothing.

    The declaration is what the unit carries, so the evidence is the directive
    on the unit, the directory it produced and the step's own text carrying no
    command that creates one. All three are read off the plan and the machine.
    """
    run = applied
    state = run.state_dir(CLUSTER_KEY)
    declared = run.deployment.plan[CLUSTER_KEY]["units"]["init"]["stateDirectory"]
    assert len(declared) == 1, declared
    assert state.endswith(f"/{declared[0]}"), (state, declared)

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'owner=%s\\n' \"$(stat -c %U:%G {shlex.quote(state)})\"",
        f"printf 'declares=%s\\n' \"$(systemctl show -P StateDirectory {shlex.quote(INIT_UNIT)})\"",
        f"printf 'creates=%s\\n' \"$(grep -cE 'install -d|mkdir' "
        f'{shlex.quote(run.unit_command(CLUSTER_KEY, "init"))} || true)"',
    )
    assert answered["declares"] == declared[0], answered
    assert answered["owner"] == "postgres:postgres", answered
    assert answered["creates"] == "0", answered


def test_the_data_directory_arrives_at_the_mode_the_server_requires(applied: Run) -> None:
    """The mode is the declaration's, and the server started against it.

    `stat` prints no leading zero, so the comparison is against the declared
    mode without it. The server refuses a data directory wider than `0750` by
    name, so the absence of that sentence in its own journal is the second half.
    """
    run = applied
    state = run.state_dir(CLUSTER_KEY)
    mode = run.directory_mode(CLUSTER_KEY, "server")
    assert {run.directory_mode(CLUSTER_KEY, unit) for unit in ("bootstrap", "init")} == {mode}

    psql = shlex.quote(run.psql())
    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'mode=%s\\n' \"$(stat -c %a {shlex.quote(state)})\"",
        f"printf 'owner=%s\\n' \"$(stat -c %U:%G {shlex.quote(state)})\"",
        f"printf 'state=%s\\n' \"$(systemctl is-active {SERVER_UNIT})\"",
        f"printf 'refused=%s\\n' \"$(journalctl -u {SERVER_UNIT} --no-pager"
        " | grep -cE 'invalid permissions|group or world access' || true)\"",
        f"printf 'alive=%s\\n' \"$({psql} -h {shlex.quote(state)} -p {run.port(CLUSTER_KEY)}"
        " -U postgres -d postgres -tAc 'SELECT 1')\"",
    )
    assert answered["mode"] == mode.removeprefix("0"), (answered, mode)
    assert answered["owner"] == "postgres:postgres", answered
    assert answered["state"] == "active", answered
    assert answered["refused"] == "0", answered
    assert answered["alive"] == "1", answered


def test_the_authentication_file_arrives_as_a_declared_file(applied: Run) -> None:
    """The bytes are the build's, at the path the module derived, and the server read it.

    The digest is compared inside the unit's own mount namespace, the way the
    configuration file's is: `BindReadOnlyPaths=` is the unit's, and the host
    holds the empty mount point systemd made for it. `SHOW hba_file` is
    superuser-only, so it is asked over the socket the module derived.
    """
    run = applied
    hba = run.hba_path(CLUSTER_KEY)
    carried = run.deployment.entries[CLUSTER_KEY].path
    assert carried is not None
    built = (carried / f"files{hba}").read_bytes()
    digest = hashlib.sha256(built).hexdigest()

    psql = shlex.quote(run.psql())
    inside = (
        f'nsenter --mount --target "$(systemctl show -P MainPID {SERVER_UNIT})"'
        f" sha256sum {shlex.quote(hba)} | cut -d' ' -f1"
    )
    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'inside=%s\\n' \"$({inside})\"",
        f"printf 'onTheHost=%s\\n' \"$(stat -c %s {shlex.quote(hba)})\"",
        f"printf 'named=%s\\n' \"$({psql} -h {shlex.quote(run.state_dir(CLUSTER_KEY))}"
        f" -p {run.port(CLUSTER_KEY)} -U postgres -d postgres -tAc 'SHOW hba_file')\"",
    )
    assert answered["inside"] == digest, answered
    assert answered["onTheHost"] == "0", answered
    assert answered["named"] == hba, answered

    # The path is the plan's: a key of the entry's own `configData`, and the
    # configuration file the module declares beside it is what names it.
    assert hba in run.deployment.plan[CLUSTER_KEY]["configData"]
    conf = run.deployment.entries[CLUSTER_KEY].path
    assert conf is not None
    assert hba in (conf / f"files{run.config_path(CLUSTER_KEY)}").read_text()


def test_one_file_decides_how_a_password_is_hashed(applied: Run) -> None:
    """The stored verifier's method is the declared file's, and no flag states one.

    The verifier is read as the superuser over the socket, because `pg_authid`
    answers a database owner with nothing. Its first `$`-separated field is the
    method the server hashed with, and the control is the same role reaching the
    published port over the network.
    """
    run = applied
    carried = run.deployment.entries[CLUSTER_KEY].path
    assert carried is not None
    declared = (carried / f"files{run.config_path(CLUSTER_KEY)}").read_text()
    stated = [
        line.split("=", 1)[1].strip()
        for line in declared.splitlines()
        if line.startswith("password_encryption")
    ]
    assert len(stated) == 1, declared

    owner = run.exports("eu")["username"]["value"]
    verifier = f"SELECT split_part(rolpassword, '$', 1) FROM pg_authid WHERE rolname = '{owner}'"
    psql = shlex.quote(run.psql())
    state = shlex.quote(run.state_dir(CLUSTER_KEY))
    port = run.port(CLUSTER_KEY)

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'method=%s\\n' \"$({psql} -h {state} -p {port} -U postgres -d postgres"
        f' -tAc {shlex.quote(verifier)})"',
        f"printf 'setting=%s\\n' \"$({psql} -h {state} -p {port} -U postgres -d postgres"
        " -tAc 'SHOW password_encryption')\"",
        f"printf 'flags=%s\\n' \"$(grep -c -- '--auth'"
        f' {shlex.quote(run.unit_command(CLUSTER_KEY, "bootstrap"))} || true)"',
        f"printf 'network=%s\\n' \"$(PGPASSWORD={shlex.quote(run.passwords[EU_VALUE])} {psql}"
        f" -h {run.address(CLUSTER_MACHINE)} -p {port} -U {owner} -d eu -tAc 'SELECT 1')\"",
    )
    assert answered["setting"] == stated[0], (answered, stated)
    assert answered["method"].lower() == stated[0].lower(), (answered, stated)
    assert answered["flags"] == "0", answered
    assert answered["network"] == "1", answered


def test_an_identifier_carrying_a_quote_is_not_sql(applied: Run) -> None:
    """One consumer's label carries a quote, and what reached the database is one label.

    The label is read off the plan rather than written here, so the declaration
    and the assertion cannot drift. The step reporting no syntax error is the
    other half: a quote that was parsed rather than escaped ends the statement.
    """
    run = applied
    label = run.label(NEAR_KEY)
    assert "'" in label, label

    psql = shlex.quote(run.psql())
    rows = "SELECT string_agg(label, ',' ORDER BY label) FROM notes"
    answered = run.observe(
        CLUSTER_MACHINE,
        f"sed 's/^/near_/' {shlex.quote(run.record_path(NEAR_KEY))}",
        f"printf 'unit=%s\\n' \"$(systemctl is-active {NEAR_UNIT})\"",
        f"printf 'stored=%s\\n' \"$(PGPASSWORD={shlex.quote(run.passwords[EU_VALUE])} {psql}"
        f" -h {run.address(CLUSTER_MACHINE)} -p {run.port(CLUSTER_KEY)}"
        f' -U {run.exports("eu")["username"]["value"]} -d eu -tAc {shlex.quote(rows)})"',
        f"printf 'errors=%s\\n' \"$(journalctl -u {NEAR_UNIT} --no-pager"
        " | grep -ci 'syntax error' || true)\"",
    )
    assert answered["near_label"] == label, answered
    assert answered["stored"] == label, answered
    assert answered["unit"] == "active", answered
    assert answered["errors"] == "0", answered


def _cluster_state(run: Run) -> dict[str, str]:
    """The bootstrap's own verdict, the DDL step's last start, and the cluster's identity.

    One ssh command, because the guest's sshd is per-connection socket
    activated. `ConditionResult` is the service manager's answer about whether
    it ran the unit at all, which is the fact the declaration replaced a shell
    test on the same path with.
    """
    version = f"{run.state_dir(CLUSTER_KEY)}/PG_VERSION"
    identity = "SELECT system_identifier FROM pg_control_system()"
    return run.observe(
        CLUSTER_MACHINE,
        f"printf 'condition=%s\\n' \"$(systemctl show -P ConditionResult {BOOTSTRAP_UNIT})\"",
        f"printf 'bootstrap_state=%s\\n' \"$(systemctl show -P ActiveState {BOOTSTRAP_UNIT})\"",
        f"printf 'bootstrap_status=%s\\n' \"$(systemctl show -P ExecMainStatus {BOOTSTRAP_UNIT})\"",
        f"printf 'init_started=%s\\n' \"$(systemctl show -P"
        f' ExecMainStartTimestampMonotonic {INIT_UNIT})"',
        f"printf 'init_state=%s\\n' \"$(systemctl show -P ActiveState {INIT_UNIT})\"",
        f"printf 'version=%s\\n' \"$(test -e {shlex.quote(version)}"
        ' && echo present || echo absent)"',
        f"printf 'identity=%s\\n' \"$({shlex.quote(run.psql())}"
        f" -h {shlex.quote(run.state_dir(CLUSTER_KEY))} -p {run.port(CLUSTER_KEY)}"
        f' -U postgres -d postgres -tAc {shlex.quote(identity)})"',
    )


@dataclass
class Again:
    """One machine either side of a second apply, and the build the second applied."""

    run: Run
    before: dict[str, str]
    after: dict[str, str]


@pytest.fixture(scope="session")
def reapplied(applied: Run) -> Again:
    """A second apply, of the same deployment with one declaration moved.

    What moved is the declared owner of one database, so this apply has to
    converge a database that already exists rather than create one. The cluster
    is read either side of the apply, because "ran once and was skipped after"
    is a comparison and the apply is between its halves.
    """
    first = applied
    before = _cluster_state(first)

    run = Run(
        cluster=first.cluster,
        deployment=CHANGED,
        key=first.key,
        passwords=first.passwords,
        source=first.source,
    )
    reported = run.cluster.run(
        [str(CLI), "apply", str(run.deployment.root), "--values", str(run.source)],
        env=delivery.command_env(dict(os.environ), run.key),
    )
    run.steps.extend(reported.stdout.splitlines())

    cluster = run.vm(CLUSTER_MACHINE)
    cluster.wait_for_unit(INIT_UNIT, timeout=300)
    cluster.wait_for_unit(SERVER_UNIT, timeout=300)
    cluster.wait_until_succeeds(f"ss -ltn | grep -q ':{run.port(CLUSTER_KEY)}'", timeout=120)
    cluster.wait_for_unit(NEAR_UNIT, timeout=300)
    run.vm(FAR_MACHINE).wait_for_unit(FAR_UNIT, timeout=300)

    return Again(run=run, before=before, after=_cluster_state(run))


def test_the_bootstrap_runs_once_and_is_skipped_after(reapplied: Again) -> None:
    """The initialisation happened once; the step that converges happened twice.

    Whether an activation restarts a unit whose file did not move is the
    endpoint's own business, so the skip is asked of the service manager after
    the second apply rather than inferred from it. Restarting a unit two others
    require stops them, so the cluster is started again in the same command:
    the tests after this one read the server, and the identity it then reports
    is what says the skip left the data alone.
    """
    run = reapplied.run
    before, after = reapplied.before, reapplied.after
    identity = "SELECT system_identifier FROM pg_control_system()"
    reads = (
        f"{shlex.quote(run.psql())} -h {shlex.quote(run.state_dir(CLUSTER_KEY))}"
        f" -p {run.port(CLUSTER_KEY)} -U postgres -d postgres -tAc {shlex.quote(identity)}"
    )

    assert before["condition"] == "yes", before
    assert before["bootstrap_state"] == "active", before
    assert before["bootstrap_status"] == "0", before
    assert before["version"] == "present", before
    assert before["identity"].isdigit(), before

    assert after["init_started"] != before["init_started"], (before, after)
    assert after["init_state"] == "active", after

    asked = run.observe(
        CLUSTER_MACHINE,
        f"systemctl restart {BOOTSTRAP_UNIT}",
        f"printf 'condition=%s\\n' \"$(systemctl show -P ConditionResult {BOOTSTRAP_UNIT})\"",
        f"printf 'state=%s\\n' \"$(systemctl show -P ActiveState {BOOTSTRAP_UNIT})\"",
        f"systemctl start {SERVER_UNIT}",
        f"for _ in $(seq 1 60); do {reads} >/dev/null 2>&1 && break; sleep 2; done",
        f"printf 'identity=%s\\n' \"$({reads})\"",
        f"printf 'server=%s\\n' \"$(systemctl is-active {SERVER_UNIT})\"",
        timeout=300,
    )
    assert asked["condition"] == "no", asked
    assert asked["state"] == "inactive", asked
    assert asked["server"] == "active", asked
    assert asked["identity"] == before["identity"], (before, asked)


def test_a_changed_database_owner_takes_effect_on_a_second_apply(reapplied: Again) -> None:
    """The database the first apply created is owned by the role the second names.

    The two owners are read off the two builds' own plans, so the test states
    neither. The rows written under the previous owner are read back through the
    new one, which is what makes the handover a handover rather than a rename.
    """
    run = reapplied.run
    was = DEPLOYMENT.plan[CLUSTER_KEY]["provides"]["eu"]["exports"]["username"]["value"]
    now = run.exports("eu")["username"]["value"]
    assert was != now, (was, now)

    psql = shlex.quote(run.psql())
    state = shlex.quote(run.state_dir(CLUSTER_KEY))
    port = run.port(CLUSTER_KEY)
    owner = "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'eu'"
    rows = "SELECT string_agg(label, ',' ORDER BY label) FROM notes"

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'owner=%s\\n' \"$({psql} -h {state} -p {port} -U postgres -d postgres"
        f' -tAc {shlex.quote(owner)})"',
        f"printf 'rows=%s\\n' \"$(PGPASSWORD={shlex.quote(run.passwords[EU_VALUE])} {psql}"
        f" -h {run.address(CLUSTER_MACHINE)} -p {port} -U {now} -d eu"
        f' -tAc {shlex.quote(rows)})"',
        f"printf 'consumer=%s\\n' \"$(systemctl is-active {NEAR_UNIT})\"",
    )
    assert answered["owner"] == now, answered
    assert answered["rows"] == run.label(NEAR_KEY), answered
    assert answered["consumer"] == "active", answered


def test_a_role_the_deployment_no_longer_names_cannot_log_in(reapplied: Again) -> None:
    """The superseded role keeps everything it owned and loses only its login."""
    run = reapplied.run
    gone = DEPLOYMENT.plan[CLUSTER_KEY]["provides"]["eu"]["exports"]["username"]["value"]
    assert gone not in {run.exports(name)["username"]["value"] for name in ("eu", "us")}

    psql = shlex.quote(run.psql())
    state = shlex.quote(run.state_dir(CLUSTER_KEY))
    address = run.address(CLUSTER_MACHINE)
    port = run.port(CLUSTER_KEY)
    eu = shlex.quote(run.passwords[EU_VALUE])
    login = f"SELECT rolcanlogin FROM pg_roles WHERE rolname = '{gone}'"
    holds = "SELECT tableowner FROM pg_tables WHERE tablename = 'notes'"

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'refused=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port} -U {gone}"
        " -d eu -tAc 'SELECT 1' 2>&1 | tr '\\n' ' ')\"",
        f"printf 'status=%s\\n' \"$(PGPASSWORD={eu} {psql} -h {address} -p {port} -U {gone}"
        " -d eu -tAc 'SELECT 1' >/dev/null 2>&1; echo $?)\"",
        f"printf 'login=%s\\n' \"$({psql} -h {state} -p {port} -U postgres -d postgres"
        f' -tAc {shlex.quote(login)})"',
        f"printf 'holds=%s\\n' \"$({psql} -h {state} -p {port} -U postgres -d eu"
        f' -tAc {shlex.quote(holds)})"',
    )
    assert answered["status"] != "0", answered
    assert "not permitted to log in" in answered["refused"], answered
    assert answered["login"] == "f", answered
    assert answered["holds"] == gone, answered
