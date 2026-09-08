"""One real machine, two built images, and what attaching one does to it.

``nix run .#planner-e2e portable-image`` runs this. It boots one rookery VM from
``$PLANNER_E2E_GUEST_IMAGE``, delivers the images in ``$PLANNER_PORTABLE_IMAGE``
to it, and runs the scripts those images carry - on the machine, through its own
service manager. One test per scenario of
``openspec/changes/emit-systemd-portable-service-images/specs/realiser/portable-service-image/spec.md``
that is about what a real machine does with a built image, named after it.

**The phases are ordered and the file order is the order.**

1. the image is attached by the script the artifact carries, and its unit runs
2. the profile the entry was stated under is the one the machine enforces
3. an image built for another architecture is refused by its own script
4. detaching removes what attaching made, and leaves what it was shown

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake
(design.md D2), so the module skips itself when it is absent - and
`mypy --strict` type-checks it without rookery present (treefmt.nix). The machine
is a ``@cluster_snapshot_fixture`` stage: the first run boots and cuts it, every
later run resumes the cut, and the delivery and attachment below still run
against the machine every time.
"""

from __future__ import annotations

import json
import os
import shlex
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

MACHINE = "alpha"
CONFINED = "confined"
FOREIGN = "foreign"
CONFINED_KEY = "watch:file@alpha"
FOREIGN_KEY = "mirror:copy@elsewhere"
SHOWN_TEXT = "upstream says so\n"
HOST_SYSTEM = "x86_64-linux"
FOREIGN_SYSTEM = "aarch64-linux"


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


IMAGES = _env_path("PLANNER_PORTABLE_IMAGE")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))


@dataclass
class Run:
    """The machine, the images, the plan they were built from, and what was run."""

    cluster: Any
    images: Path
    key: Path
    plan: dict[str, Any]
    observed: dict[str, str] = field(default_factory=dict)

    @property
    def vm(self) -> Any:
        return self.cluster.vm(MACHINE)

    def image(self, name: str) -> Path:
        return (self.images / name).resolve()

    def attachment(self, name: str) -> dict[str, Any]:
        loaded = json.loads((self.image(name) / "attachment.json").read_text())
        assert isinstance(loaded, dict)
        return loaded

    def raw(self, name: str) -> str:
        """The image file itself, at the path the machine reads it from."""
        return str(self.image(name) / self.attachment(name)["image"])

    def units_of(self, name: str) -> list[str]:
        units = self.attachment(name)["units"]
        assert isinstance(units, list)
        return [str(unit) for unit in units]

    def render(self) -> list[dict[str, str]]:
        """The recipe the confined entry's one configuration file is assembled from."""
        records = list(self.plan[CONFINED_KEY]["configData"].values())
        assert len(records) == 1, records
        items = records[0]["render"]
        assert isinstance(items, list)
        return [dict(item) for item in items]

    def shown_path(self) -> str:
        """The host file that recipe reads.

        Read out of the plan rather than restated here: the recipe naming that
        path is the only reason the machine needs the file at all.
        """
        for item in self.render():
            if "ref" in item:
                return item["ref"]
        raise AssertionError(f"{CONFINED_KEY} assembles no file from a host path")

    def recipe(self) -> str:
        """What a machine following that recipe has to end up with."""
        return "".join(item.get("text", SHOWN_TEXT) for item in self.render())

    @staticmethod
    def between(logged: str, opening: str, closing: str) -> str:
        """The lines the unit printed between two markers of its own."""
        lines = logged.splitlines()
        return "".join(
            f"{line}\n" for line in lines[lines.index(opening) + 1 : lines.index(closing)]
        )

    @staticmethod
    def reported(logged: str, prefix: str) -> str:
        """The one line the unit printed under a prefix of its own."""
        found = [line for line in logged.splitlines() if line.startswith(prefix)]
        assert len(found) == 1, logged
        return found[0][len(prefix) :].strip()


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=(MACHINE,), key=KEY)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage every run starts from: one machine, up and usable.

    On a cache hit this body does not run at all - the machine is resumed from
    the cut it took the first time - so nothing here may be a fact a test reads.
    It waits, and yields.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def run(booted: Any) -> Run:
    """One machine, named as the plan names it, obtained once for the whole run."""
    return Run(
        cluster=booted.cluster,
        images=IMAGES,
        key=KEY,
        plan=json.loads((IMAGES / "plan.json").read_text()),
    )


@pytest.fixture(scope="session")
def delivered(run: Run) -> Run:
    """Both images on the machine, and the host file the confined entry reads.

    The file is written by hand because that is what it is: a file an operator
    put there, which the image carries a recipe for and never the bytes of.

    The confined entry goes to the machine the plan placed it on, through the
    driver that reads that placement. The other image is copied to the same
    machine deliberately - no plan places it there, which is the whole point -
    so it is carried by the same argv with the address stated.
    """
    if run.observed.get("delivered"):
        return run

    shown = run.shown_path()
    run.vm.ssh_succeed(f"mkdir -p {shlex.quote(os.path.dirname(shown))}")
    run.vm.ssh_succeed(f"printf %s {shlex.quote(SHOWN_TEXT)} > {shlex.quote(shown)}")

    base_env = dict(os.environ)
    address = delivery.deliver(
        run.cluster,
        plan=run.plan,
        key=CONFINED_KEY,
        artifact=run.image(CONFINED),
        ssh_key=run.key,
        base_env=base_env,
    )
    run.cluster.run(
        delivery.copy_argv(run.image(FOREIGN), address),
        env=delivery.delivery_env(base_env, run.key),
    )

    run.observed["delivered"] = address
    return run


@pytest.fixture(scope="session")
def attached(delivered: Run) -> Run:
    """Phase 1: the confined image attached by running the artifact's own script."""
    if delivered.observed.get("attached"):
        return delivered

    command = f"{delivered.image(CONFINED)}/bin/attach"
    delivered.vm.ssh_succeed(command, timeout=180)
    delivered.observed["attached"] = command
    return delivered


@pytest.fixture(scope="session")
def detached(attached: Run) -> Run:
    """Phase 4: the same image detached by the other script it carries."""
    if attached.observed.get("detached"):
        return attached

    command = f"{attached.image(CONFINED)}/bin/detach"
    attached.vm.ssh_succeed(command, timeout=180)
    attached.observed["detached"] = command
    return attached


def test_the_image_is_attached_by_the_script_the_artifact_carries(attached: Run) -> None:
    """Nothing but the artifact's own script ran, and the machine holds its image."""
    assert attached.observed["attached"] == f"{attached.image(CONFINED)}/bin/attach"

    raw = attached.raw(CONFINED)
    state = attached.vm.ssh_succeed(f"portablectl is-attached {shlex.quote(raw)}").strip()
    assert state in {"attached", "attached-runtime", "running", "running-runtime"}, state

    listed = attached.vm.ssh_succeed("portablectl list --no-legend")
    assert attached.attachment(CONFINED)["name"] in listed, listed


def test_the_attached_unit_becomes_active(attached: Run) -> None:
    """Every unit the attachment names is a unit the service manager is running."""
    units = attached.units_of(CONFINED)
    assert units == ["watch-file-report.service"]

    for unit in units:
        state = attached.vm.ssh(f"systemctl is-active {unit}").stdout.strip()
        assert state == "active", attached.vm.ssh(f"systemctl status -l --no-pager {unit}").stdout
        source = attached.vm.ssh_succeed(f"systemctl show -P FragmentPath {unit}").strip()
        assert source.endswith(unit), source


def test_the_identity_file_is_present(attached: Run) -> None:
    """The machine reads the image's own identity out of it, and attaching needed it.

    `portablectl` refuses an image with no `os-release`, so the attach that
    already happened is half the claim; the other half is that the identity it
    carries names this entry rather than the host it was built on.
    """
    name = attached.attachment(CONFINED)["name"]
    shown = attached.vm.ssh_succeed(
        f"portablectl inspect --cat {shlex.quote(attached.raw(CONFINED))}"
    )
    assert f"PORTABLE_ID={name}" in shown, shown
    assert "PORTABLE_PRETTY_NAME=watch:file on alpha" in shown, shown


def test_a_command_resolves_inside_the_image(attached: Run) -> None:
    """The running unit's command is a path in the image, reached through the image.

    `RootImage` is the image the process is running out of, and the executable
    the unit names is under the store directory the plan recorded - which is
    what makes the entry's declared closure the only thing it can reach.
    """
    unit = attached.units_of(CONFINED)[0]
    raw = shlex.quote(attached.raw(CONFINED))
    resolved = attached.vm.ssh_succeed(f"readlink -f {raw}").strip()
    root = attached.vm.ssh_succeed(f"systemctl show -P RootImage {unit}").strip()
    assert root == resolved, root

    command = attached.vm.ssh_succeed(f"systemctl show -P ExecStart {unit}")
    executable = attached.plan[CONFINED_KEY]["units"]["report"]["command"]
    assert executable in command, command
    assert executable.startswith(attached.plan[CONFINED_KEY]["storeDir"] + "/")

    listed = attached.vm.ssh_succeed(f"systemd-dissect --list {raw}")
    assert executable.lstrip("/") in listed, executable


def test_the_confinement_profile_is_enforced_by_the_machine(attached: Run) -> None:
    """The stated profile is the one attached, and the unit lives inside it.

    The same file is read twice: by the confined unit, which reaches only the
    copy it was shown, and over ssh, where the operator's own file is plainly
    there. One of the two alone would be a claim about a missing file rather
    than about confinement.
    """
    profile = attached.attachment(CONFINED)["profile"]
    assert profile == "strict"

    unit = attached.units_of(CONFINED)[0]
    dropin = attached.vm.ssh_succeed(f"systemctl show -P DropInPaths {unit}").split()[0]
    applied = attached.vm.ssh_succeed(f"readlink -f {shlex.quote(dropin)}").strip()
    assert f"/portable/profile/{profile}/" in applied, applied

    logged = attached.vm.ssh_succeed(f"journalctl -u {unit} --no-pager -o cat")
    assert attached.between(logged, "assembled-begin", "assembled-end") == attached.recipe()

    identity = attached.reported(logged, "identity:")
    # Every profile but trusted carries DynamicUser=yes, so the service cannot be root.
    assert identity != "uid=0", identity

    denied = attached.reported(logged, "original-read:")
    assert "No such file or directory" in denied, denied
    shown = attached.shown_path()
    assert attached.vm.ssh_succeed(f"cat {shlex.quote(shown)}") == SHOWN_TEXT


def test_an_image_built_for_another_architecture_is_refused(attached: Run) -> None:
    """The artifact's own script refuses, naming both systems, and starts nothing."""
    assert attached.attachment(FOREIGN)["target"]["system"] == FOREIGN_SYSTEM

    refusal = attached.vm.ssh(f"{attached.image(FOREIGN)}/bin/attach", timeout=120)
    assert refusal.returncode != 0
    said = refusal.stdout + refusal.stderr
    assert FOREIGN_SYSTEM in said, said
    assert HOST_SYSTEM in said, said

    raw = attached.raw(FOREIGN)
    assert (
        attached.vm.ssh_succeed(f"portablectl is-attached {shlex.quote(raw)}").strip() == "detached"
    )
    for unit in attached.units_of(FOREIGN):
        loaded = attached.vm.ssh_succeed(f"systemctl show -P LoadState {unit}").strip()
        assert loaded == "not-found", loaded


def test_detaching_removes_the_units_and_the_staging_directory(detached: Run) -> None:
    """The units are unknown again, the staging directory is gone, the store is not."""
    for unit in detached.units_of(CONFINED):
        loaded = detached.vm.ssh_succeed(f"systemctl show -P LoadState {unit}").strip()
        assert loaded == "not-found", loaded

    staging = detached.attachment(CONFINED)["staging"]
    assert detached.vm.ssh(f"test -e {shlex.quote(staging)}").returncode != 0

    for path in detached.attachment(CONFINED)["closure"]:
        assert (
            detached.vm.ssh_succeed(f"nix-store --check-validity {path} && echo ok").strip() == "ok"
        )


def test_a_host_file_the_image_was_shown_survives_detaching(detached: Run) -> None:
    """A file the machine was shown is the machine's, so detaching does not touch it."""
    shown = detached.shown_path()
    assert detached.vm.ssh_succeed(f"cat {shlex.quote(shown)}") == SHOWN_TEXT
