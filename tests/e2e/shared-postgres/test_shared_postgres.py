"""One database cluster, two databases, two consumers, on real machines.

``nix run .#planner-e2e shared-postgres`` runs this. It builds the folder's
deployment with ``planner build``, boots two rookery VMs from
``$PLANNER_E2E_GUEST_IMAGE``, mints one password per database into a value
source of its own, applies the deployment with ``planner apply --values``, and
then asks the machines what one process is serving, what each of them holds and
what the server answers. One test per scenario of
``openspec/changes/run-a-shared-database-on-real-machines/specs/delivery/real-cluster/spec.md``,
each named after it.

**The phases are ordered and the file order is the order.**

1. the deployment is built by the command, in this process and before any
   machine is dialled
2. the run mints one password per database and writes exactly the files the
   plan declares of a value some machine receives
3. one ``planner apply`` writes each value to the set the plan named and
   activates the three entries, the cluster before either consumer
4. the machines answer: one server process behind both databases, each
   consumer's own row, each machine's own credential and no other's, and the
   server's own refusal of a credential presented to the wrong database

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
OWN_KEY = "own-app:client@beta"
OWN_DB_KEY = "own-app:own@beta"
EU_VALUE = "pg:vars/password-eu"
US_VALUE = "pg:vars/password-us"
OWN_VALUE = "own-app:vars/password-private"
CLUSTER_MACHINE = "alpha"
NEAR_MACHINE = "alpha"
FAR_MACHINE = "beta"
INIT_UNIT = "pg-cluster-init.service"
SERVER_UNIT = "pg-cluster-server.service"
NEAR_UNIT = "near-app-client-write.service"
FAR_UNIT = "far-app-client-write.service"
OWN_UNIT = "own-app-client-write.service"
OWN_INIT_UNIT = "own-app-own-init.service"
OWN_SERVER_UNIT = "own-app-own-server.service"
NEAR_RECORD = "/run/shared-postgres/near.json"
FAR_RECORD = "/run/shared-postgres/far.json"
OWN_RECORD = "/run/shared-postgres-own/own.json"
DATA_DIR = "/var/lib/postgresql/data"
OWN_DATA_DIR = "/var/lib/postgresql/own"
CONF_PATH = "/etc/postgresql/postgresql.conf"
MACHINES = (CLUSTER_MACHINE, FAR_MACHINE)
ATTRIBUTE = "planner-e2e-shared-postgres"

# The cluster writes a data directory the image has no room for beside two
# delivered closures, and the figure is the stage's rather than the shared
# image's: raising the image would re-key every other folder's cut.
DISK_GIB = 12


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

    def exports(self, capability: str) -> dict[str, Any]:
        """The exports the cluster's entry published for one capability."""
        published = self.deployment.plan[CLUSTER_KEY]["provides"][capability]["exports"]
        assert isinstance(published, dict), published
        return published

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

    The waits make a read of a machine a read of a settled machine: the
    initialiser, then the server's port, then each consumer. The seconds between
    the cluster's activation and a consumer's are covered by the retry in the
    consumer's own script, which is what it is there for.
    """
    reported = run.cluster.run(
        [str(CLI), "apply", str(run.deployment.root), "--values", str(run.source)],
        env=delivery.command_env(dict(os.environ), run.key),
    )
    run.steps.extend(reported.stdout.splitlines())

    port = run.deployment.plan[CLUSTER_KEY]["alloc"]["ports"]["postgres"]
    cluster = run.vm(CLUSTER_MACHINE)
    cluster.wait_for_unit(INIT_UNIT, timeout=300)
    cluster.wait_for_unit(SERVER_UNIT, timeout=300)
    cluster.wait_until_succeeds(f"ss -ltn | grep -q ':{port}'", timeout=120)
    cluster.wait_for_unit(NEAR_UNIT, timeout=300)

    far = run.vm(FAR_MACHINE)
    far.wait_for_unit(FAR_UNIT, timeout=300)
    far.wait_for_unit(OWN_INIT_UNIT, timeout=300)
    far.wait_for_unit(OWN_SERVER_UNIT, timeout=300)
    far.wait_for_unit(OWN_UNIT, timeout=300)
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
    port = run.deployment.plan[CLUSTER_KEY]["alloc"]["ports"]["postgres"]
    assert published == f"postgresql://app_us@{address}:{port}/us", published

    answered = run.observe(
        FAR_MACHINE,
        f"printf 'unit=%s\\n' \"$(systemctl is-active {FAR_UNIT})\"",
        f"sed 's/^/record_/' {shlex.quote(FAR_RECORD)}",
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
    port = run.deployment.plan[CLUSTER_KEY]["alloc"]["ports"]["postgres"]
    declared = run.deployment.plan[CLUSTER_KEY]["units"]["init"]["env"]["PGDATA"]
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
        f"printf 'postmaster=%s\\n' \"$(head -1 {shlex.quote(DATA_DIR)}/postmaster.pid)\"",
        f"printf 'init_state=%s\\n' \"$(systemctl is-active {INIT_UNIT})\"",
        f"printf 'init_type=%s\\n' \"$(systemctl show -P Type {INIT_UNIT})\"",
        f"printf 'init_result=%s\\n' \"$(systemctl show -P Result {INIT_UNIT})\"",
        f"printf 'init_main=%s\\n' \"$(systemctl show -P MainPID {INIT_UNIT})\"",
        asks("eu", "identifier", "SELECT system_identifier FROM pg_control_system()"),
        asks("us", "identifier", "SELECT system_identifier FROM pg_control_system()"),
        asks("eu", "started", "SELECT pg_postmaster_start_time()"),
        asks("us", "started", "SELECT pg_postmaster_start_time()"),
    )

    assert declared == DATA_DIR, declared
    assert f"-D {DATA_DIR} " in serves, serves
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
    port = run.deployment.plan[CLUSTER_KEY]["alloc"]["ports"]["postgres"]
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
        "printf 'held=%s\\n' \"$(ls -A /run/vars/pg | tr '\\n' ' ')\"",
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
        f"printf 'rows=%s\\n' \"$(grep -o 'far' {shlex.quote(FAR_RECORD)} | head -1)\"",
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
    assert run.deployment.plan[OWN_VALUE]["delivery"] == [FAR_MACHINE]
    assert run.deployment.entries[OWN_DB_KEY].machine == FAR_MACHINE

    # Nothing of the shared cluster reaches it: neither capability is in its
    # reads, and the cluster's own value is delivered to it by nobody.
    assert read["values"]["dsn"] != run.exports("eu")["dsn"]["value"]
    assert read["values"]["dsn"] != run.exports("us")["dsn"]["value"]
    assert FAR_MACHINE not in run.deployment.values[EU_VALUE].delivery

    answered = run.observe(
        FAR_MACHINE,
        f"printf 'client=%s\\n' \"$(systemctl is-active {OWN_UNIT})\"",
        f"printf 'server=%s\\n' \"$(systemctl is-active {OWN_SERVER_UNIT})\"",
        f"printf 'data=%s\\n' \"$(test -s {shlex.quote(OWN_DATA_DIR)}/PG_VERSION"
        ' && echo present || echo absent)"',
        f"sed 's/^/record_/' {shlex.quote(OWN_RECORD)}",
    )
    assert answered["client"] == "active", answered
    assert answered["server"] == "active", answered
    assert answered["data"] == "present", answered
    assert answered["record_database"] == "private", answered
    assert answered["record_user"] == "app_private", answered
    assert answered["record_host"] == run.address(FAR_MACHINE), answered
    assert answered["record_labels"] == "own", answered


def test_data_written_before_a_restart_is_readable_after_it(applied: Run) -> None:
    """The server is restarted deliberately; the state and the one-shot both hold."""
    run = applied
    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.deployment.plan[CLUSTER_KEY]["alloc"]["ports"]["postgres"]
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

    assert answered["rows_before"] == "near", answered
    assert answered["rows_after"] == "near", answered
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
    carried = run.deployment.entries[CLUSTER_KEY].path
    assert carried is not None
    built = (carried / f"files{CONF_PATH}").read_bytes()
    digest = hashlib.sha256(built).hexdigest()
    bound = f"BindReadOnlyPaths={(carried / f'files{CONF_PATH}').resolve()}:{CONF_PATH}"

    psql = shlex.quote(run.psql())
    address = run.address(CLUSTER_MACHINE)
    port = run.deployment.plan[CLUSTER_KEY]["alloc"]["ports"]["postgres"]
    eu = shlex.quote(run.passwords[EU_VALUE])
    inside = (
        f'nsenter --mount --target "$(systemctl show -P MainPID {SERVER_UNIT})"'
        f" sha256sum {shlex.quote(CONF_PATH)} | cut -d' ' -f1"
    )

    answered = run.observe(
        CLUSTER_MACHINE,
        f"printf 'inside=%s\\n' \"$({inside})\"",
        f"printf 'onTheHost=%s\\n' \"$(stat -c %s {shlex.quote(CONF_PATH)})\"",
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
