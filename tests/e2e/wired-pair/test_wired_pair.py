"""Two real machines, one plan, and the wire between them.

``nix run .#planner-e2e wired-pair`` runs this. It boots two rookery VMs from
``$PLANNER_E2E_GUEST_IMAGE``, delivers the artifacts in ``$PLANNER_WIRED_PAIR``
to the machines ``$PLANNER_WIRED_PAIR/plan.json`` placed them on, and observes what
the two machines then do. One test per scenario of
``openspec/changes/prove-plan-on-real-machines/specs/delivery/real-cluster/spec.md``,
named after it.

**The phases are ordered and the file order is the order.** The requirements are
a state machine, so each test asserts the state it depends on rather than
assuming it:

1. the participants are real (nothing has been delivered yet)
2. both entries are delivered and activated (the ``delivered`` fixture)
3. the receiving machine evaluated nothing and can reach no other store
4. the wire is traffic, and cutting it is visible - which restores it afterwards
5. an unchanged redelivery is a no-op, a changed one is generation 2, a rollback
   returns generation 1
6. both machines reboot, and the entries come back without a second delivery

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake
(design.md D2), so a static import would make this file unloadable - and
`mypy --strict` type-checks it without rookery present (treefmt.nix).
"""

from __future__ import annotations

import importlib
import json
import os
import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import pytest

import delivery

SERVER_ENTRY = "site:server"
SERVER_KEY = "site:server@alpha"
CLIENT_KEY = "check:client@beta"
SWEEP_KEY = "sweep:job@alpha"
SERVER_MACHINE = "alpha"
CLIENT_MACHINE = "beta"
SERVER_UNIT = "site-server-serve.service"
CLIENT_UNIT = "check-client-fetch.service"
SWEEP_UNIT = "sweep-job-rotate.service"
SWEEP_TIMER = "sweep-job-rotate.timer"
SWEEP_MARKER = "/run/cluster-sweep.ran"
RECORD_PATH = "/run/cluster-probe.body"
STORE_PATH = re.compile(r"/nix/store/[0-9a-z]{32}-[^\s\"']+")


def _rookery() -> Any:
    """Import rookery, or skip: this suite has nothing to say without machines."""
    try:
        return importlib.import_module("rookery.qemu")
    except ImportError as exc:  # pragma: no cover - the runner assembles the path
        pytest.skip(f"rookery is not importable ({exc}); run this through .#planner-e2e")


@dataclass
class Run:
    """The cluster, the plans, and what each phase observed."""

    cluster: Any
    artifacts: Path
    deployment: Path
    key: Path
    plan: dict[str, Any]
    plan_changed: dict[str, Any]
    observed: dict[str, Any] = field(default_factory=dict)

    def vm(self, machine: str) -> Any:
        return self.cluster.vm(machine)

    def artifact(self, name: str) -> Path:
        return (self.artifacts / name).resolve()

    def unit_text(self, name: str) -> str:
        units = sorted((self.artifacts / name / "units").iterdir())
        assert len(units) == 1, units
        return units[0].read_text()

    def page_text(self, name: str) -> str:
        """What the producer's delivered unit actually serves, read from its own root."""
        served = re.search(r"--directory (\S+)", self.unit_text(name))
        assert served is not None, self.unit_text(name)
        return (Path(served.group(1)) / "index.html").read_text()


def _env_path(variable: str) -> Path:
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e")
    return Path(value)


@pytest.fixture(scope="session")
def artifacts() -> Path:
    """The built artifacts of this folder's deployment."""
    return _env_path("PLANNER_WIRED_PAIR")


@pytest.fixture(scope="session")
def keydir(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """The run's own key pair, and the share the guests install it from.

    Generated per run: the image carries no credential, and none is borrowed
    from rookery (design.md D6).
    """
    root = tmp_path_factory.mktemp("wired-pair-key")
    delivery.keypair(root)
    return root


@pytest.fixture(scope="session")
def run(artifacts: Path, keydir: Path) -> Iterator[Run]:
    """Two machines named as the plan names them, booted once for the whole run."""
    qemu = _rookery()
    deployment = _env_path("PLANNER_WIRED_PAIR_DEPLOYMENT")

    with delivery.booted(
        qemu,
        image=_env_path("PLANNER_E2E_GUEST_IMAGE"),
        names=(SERVER_MACHINE, CLIENT_MACHINE),
        keydir=keydir,
    ) as live:
        yield Run(
            cluster=live,
            artifacts=artifacts,
            deployment=deployment,
            key=keydir / "id_ed25519",
            plan=json.loads((artifacts / "plan.json").read_text()),
            plan_changed=json.loads((artifacts / "plan-changed.json").read_text()),
        )


@pytest.fixture(scope="session")
def delivered(run: Run) -> Run:
    """Phase 2: both entries copied to their machines and activated there.

    The producer is activated and observed listening before the consumer is, so
    the consumer's first fetch is a fetch and not a retry.
    """
    if run.observed.get("delivered"):
        return run

    base_env = dict(os.environ)
    reports: dict[str, str] = {}
    dialled: dict[str, str] = {}

    for key, name, machine in (
        (SERVER_KEY, "site", SERVER_MACHINE),
        (CLIENT_KEY, "check", CLIENT_MACHINE),
        (SWEEP_KEY, "sweep", SERVER_MACHINE),
    ):
        artifact = run.artifact(name)
        dialled[key] = delivery.deliver(
            run.cluster,
            plan=run.plan,
            key=key,
            artifact=artifact,
            ssh_key=run.key,
            base_env=base_env,
        )
        service = delivery.service_name(artifact)
        reports[key] = delivery.activate(run.vm(machine), service, artifact)
        if key == SERVER_KEY:
            port = run.plan[SERVER_KEY]["alloc"]["ports"]["http"]
            run.vm(machine).wait_for_unit(SERVER_UNIT, timeout=120)
            run.vm(machine).wait_until_succeeds(f"ss -ltn | grep -q ':{port}'", timeout=60)

    run.vm(CLIENT_MACHINE).wait_for_unit(CLIENT_UNIT, timeout=120)
    run.observed.update({"delivered": True, "reports": reports, "dialled": dialled})
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
    assert delivery.copy_argv("/nix/store/x", "10.0.0.10")[:2] == ["nix", "copy"]


def _store_root(path: str) -> str:
    """Return the store object a path names, dropping any path inside it."""
    return "/".join(path.split("/")[:4])


def test_the_machines_are_not_told_the_answer(run: Run) -> None:
    address = run.plan[f"machine:{SERVER_MACHINE}"]["address"]
    contributed_anywhere: list[str] = []
    for machine, name in ((SERVER_MACHINE, "site"), (CLIENT_MACHINE, "check")):
        vm = run.vm(machine)
        artifact = run.artifact(name)
        assert vm.ssh(f"nix-store --check-validity {artifact}").returncode != 0
        for unit in sorted((artifact / "units").iterdir()):
            assert vm.ssh(f"nix-store --check-validity {unit.resolve()}").returncode != 0
        own = set(vm.ssh_succeed("nix-store -qR /run/current-system").split())
        named = sorted({_store_root(path) for path in STORE_PATH.findall(run.unit_text(name))})
        assert named, run.unit_text(name)
        for path in named:
            valid = vm.ssh(f"nix-store --check-validity {path}").returncode == 0
            assert valid == (path in own), path
            if path not in own:
                contributed_anywhere.append(path)
        config = json.loads(vm.ssh_succeed("cat /etc/flakelet/config.json"))
        assert config.get("services", {}) == {}, config
    assert contributed_anywhere
    declaring = [
        path for path in sorted(run.deployment.rglob("*.nix")) if address in path.read_text()
    ]
    assert [path.name for path in declaring] == ["machines.nix"], declaring




def test_the_machine_holds_what_the_artifact_names(delivered: Run) -> None:
    for machine, name in ((SERVER_MACHINE, "site"), (CLIENT_MACHINE, "check")):
        vm = delivered.vm(machine)
        artifact = delivered.artifact(name)
        assert vm.ssh_succeed(f"nix-store --check-validity {artifact} && echo ok").strip() == "ok"
        named = sorted(set(STORE_PATH.findall(delivered.unit_text(name))))
        assert named, delivered.unit_text(name)
        for path in named:
            assert vm.ssh_succeed(f"nix-store --check-validity {path} && echo ok").strip() == "ok"
    other = delivered.vm(CLIENT_MACHINE)
    assert other.ssh(f"nix-store --check-validity {delivered.artifact('site')}").returncode != 0


def test_the_plan_names_the_address(delivered: Run) -> None:
    dialled = delivered.observed["dialled"]
    assert dialled[SERVER_KEY] == delivered.plan[f"machine:{SERVER_MACHINE}"]["address"]
    assert dialled[CLIENT_KEY] == delivered.plan[f"machine:{CLIENT_MACHINE}"]["address"]


def test_an_entry_is_not_delivered_to_a_machine_it_was_not_placed_on(delivered: Run) -> None:
    with pytest.raises(delivery.DeliveryError) as raised:
        delivery.placed_key(delivered.plan, SERVER_ENTRY, CLIENT_MACHINE)
    message = str(raised.value)
    assert SERVER_ENTRY in message
    assert CLIENT_MACHINE in message
    assert SERVER_MACHINE in message
    other = delivered.vm(CLIENT_MACHINE)
    assert other.ssh(f"nix-store --check-validity {delivered.artifact('site')}").returncode != 0




def test_the_unit_runs_from_the_delivered_directory(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    assert server.ssh_succeed(f"systemctl is-active {SERVER_UNIT}").strip() == "active"
    reported = delivery.status(server, delivery.service_name(delivered.artifact("site")))
    assert reported["locked_url"] == delivery.locked_url(SERVER_KEY), reported
    assert reported["generation"] == 1, reported
    assert reported["last_error"] is None, reported
    assert SERVER_UNIT in reported["units"], reported


def test_no_evaluation_happens_on_the_machine(delivered: Run) -> None:
    report = delivered.observed["reports"][SERVER_KEY]
    assert "using prebuilt artifact" in report, report
    assert "resolving" not in report, report
    assert "building" not in report, report


def test_no_store_but_the_machines_own_is_reachable(delivered: Run) -> None:
    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        vm = delivered.vm(machine)
        assert vm.ssh("getent hosts cache.nixos.org").returncode != 0
        assert vm.ssh("timeout 5 nix-store --realise /nix/store/nonexistent").returncode != 0




def test_the_consumer_reaches_the_producer(delivered: Run) -> None:
    client = delivered.vm(CLIENT_MACHINE)
    assert client.ssh_succeed(f"systemctl is-active {CLIENT_UNIT}").strip() == "active"
    body = client.ssh_succeed(f"cat {RECORD_PATH}")
    assert body == delivered.page_text("site"), body


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
        path.relative_to(delivered.deployment)
        for path in sorted(delivered.deployment.rglob("*"))
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

    server.ssh_succeed(f"systemctl start {SERVER_UNIT}")
    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)




def test_an_unchanged_entry_is_a_no_op(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    service = delivery.service_name(delivered.artifact("site"))
    before = server.ssh_succeed(f"systemctl show -P MainPID {SERVER_UNIT}").strip()

    delivery.deliver(
        delivered.cluster,
        plan=delivered.plan,
        key=SERVER_KEY,
        artifact=delivered.artifact("site"),
        ssh_key=delivered.key,
        base_env=dict(os.environ),
    )
    delivery.activate(server, service, delivered.artifact("site"))

    assert delivery.status(server, service)["generation"] == 1
    assert server.ssh_succeed(f"systemctl show -P MainPID {SERVER_UNIT}").strip() == before


def test_a_changed_entry_is_a_new_generation(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    client = delivered.vm(CLIENT_MACHINE)
    service = delivery.service_name(delivered.artifact("site-changed"))
    assert service == delivery.service_name(delivered.artifact("site"))

    delivery.deliver(
        delivered.cluster,
        plan=delivered.plan_changed,
        key=SERVER_KEY,
        artifact=delivered.artifact("site-changed"),
        ssh_key=delivered.key,
        base_env=dict(os.environ),
    )
    report = delivery.activate(server, service, delivered.artifact("site-changed"))
    assert "generation 2" in report, report
    assert delivery.status(server, service)["generation"] == 2

    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == delivered.page_text("site-changed")


def test_rollback_returns_the_previous_generation(delivered: Run) -> None:
    server = delivered.vm(SERVER_MACHINE)
    client = delivered.vm(CLIENT_MACHINE)
    service = delivery.service_name(delivered.artifact("site"))

    report = delivery.rollback(server, service)
    assert "generation 1" in report, report
    assert delivery.status(server, service)["generation"] == 1

    client.wait_until_succeeds(f"systemctl restart {CLIENT_UNIT}", timeout=120)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == delivered.page_text("site")


def test_the_endpoint_reports_what_the_rollback_came_from(delivered: Run) -> None:
    """The endpoint's own record says the change was a rollback, and from where.

    Read back off the machine rather than inferred from the generation number: a
    rollback to 1 and a redelivery of the older content both leave generation 1,
    and only the record tells a machine's history which of the two happened.
    """
    server = delivered.vm(SERVER_MACHINE)
    status = delivery.status(server, delivery.service_name(delivered.artifact("site")))

    assert status["generation"] == 1, status
    assert status["changed"]["by"] == {"kind": "rollback", "from": 2}, status




def test_a_scheduled_unit_is_not_fired_by_deploying_it(delivered: Run) -> None:
    """Delivering and activating a scheduled entry installs a trigger, not a run."""
    server = delivered.vm(SERVER_MACHINE)
    service = delivery.service_name(delivered.artifact("sweep"))

    assert delivery.status(server, service)["generation"] >= 1
    started = server.ssh_succeed(f"systemctl show -p ExecMainStartTimestamp {SWEEP_UNIT}")
    assert started.strip() == "ExecMainStartTimestamp=", started
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
    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        delivered.vm(machine).ssh("systemctl reboot", timeout=30)

    for machine in (SERVER_MACHINE, CLIENT_MACHINE):
        vm = delivered.vm(machine)
        vm.wait_for_ssh(timeout=300)
        vm.wait_for_network(timeout=300)

    delivered.vm(SERVER_MACHINE).wait_for_unit(SERVER_UNIT, timeout=180)
    delivered.vm(CLIENT_MACHINE).wait_for_unit(CLIENT_UNIT, timeout=180)

    client = delivered.vm(CLIENT_MACHINE)
    assert client.ssh_succeed(f"cat {RECORD_PATH}") == delivered.page_text("site")


def test_a_reconcile_leaves_a_hand_activated_entry_alone(delivered: Run) -> None:
    for machine, name, unit in (
        (SERVER_MACHINE, "site", SERVER_UNIT),
        (CLIENT_MACHINE, "check", CLIENT_UNIT),
    ):
        vm = delivered.vm(machine)
        service = delivery.service_name(delivered.artifact(name))
        assert json.loads(vm.ssh_succeed("cat /etc/flakelet/config.json")).get("services") == {}
        vm.ssh_succeed("systemctl restart flakelet-reconcile.service", timeout=120)
        assert delivery.status(vm, service)["generation"] >= 1
        assert vm.ssh_succeed(f"systemctl is-active {unit}").strip() == "active"
