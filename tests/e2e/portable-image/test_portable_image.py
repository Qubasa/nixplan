"""One real machine, two built images, and what attaching one does to it.

``nix run .#planner-e2e portable-image`` runs this. It builds the deployment this
folder declares with ``planner build $PLANNER_E2E_FLAKE#planner-e2e-portable-image``,
boots one rookery VM from ``$PLANNER_E2E_GUEST_IMAGE``, and puts the confined
entry on it with ``planner apply``, which copies the artifact and runs the attach
script that artifact carries. One test per scenario of
``openspec/changes/emit-systemd-portable-service-images/specs/realiser/portable-service-image/spec.md``
that is about what a real machine does with a built image, named after it, plus
the image scenario of
``openspec/changes/apply-deployments-with-an-operator-command/specs/operator/apply-command/spec.md``.

It builds that deployment twice. The second build,
``planner-e2e-portable-image-changed``, is attached by nothing and exists so
that a report about a machine holding an earlier build has two identities to
name.

The build runs in this process and the apply runs inside the cluster (`design.md
D8`): a build needs no address, and a machine's address exists only in the
cluster's own net namespace.

**The phases are ordered and the file order is the order.**

1. the command applies the confined entry, and that is what attaches it
2. the image is attached by the script the artifact carries, and its unit runs
3. the profile the entry was stated under is the one the machine enforces
4. an image built for another architecture is refused by its own script
5. a report says what this machine holds, against this build and against another
6. the units are stopped, the image stays attached, and a report says so
7. detaching removes what attaching made, and leaves what it was shown

rookery is imported at run time rather than statically: it is resolved from
``$ROOKERY_FLAKE`` by the runner and is deliberately not an input of this flake
(design.md D2), so the module skips itself when it is absent - and
`mypy --strict` type-checks it without rookery present (treefmt.nix). The machine
is a ``@cluster_snapshot_fixture`` stage: the first run boots and cuts it, every
later run resumes the cut, and the apply below still runs against the machine
every time.
"""

from __future__ import annotations

import json
import os
import platform
import shlex
import shutil
import subprocess
from collections.abc import Iterator, Mapping
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

MACHINE = "alpha"
USER = "root"
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


CLI = _env_path("PLANNER_CLI")
FLAKE = _env_path("PLANNER_E2E_FLAKE")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))


def _built(target: str) -> Path:
    """Build one deployment with the operator's own command.

    This runs before any machine is dialled, because a build resolves no address
    and the artifacts it produces are what the apply then carries in.

    Args:
        target: The flake reference of the deployment this folder declares.

    Returns:
        The store path of the built deployment, which is the command's first line
        of output.

    Raises:
        RuntimeError: If the build failed, carrying its own standard error -
            which is where a refused deployment's rendered table appears.
    """
    built = subprocess.run([str(CLI), "build", target], capture_output=True, text=True, check=False)
    if built.returncode != 0:
        raise RuntimeError(f"planner build {target} failed:\n{built.stderr.strip()}")
    return Path(built.stdout.splitlines()[0])


BUILT = _built(f"{FLAKE}#planner-e2e-portable-image")
DEPLOYMENT = manifest.read(BUILT)
CHANGED = _built(f"{FLAKE}#planner-e2e-portable-image-changed")
CHANGED_BUILD = manifest.read(CHANGED)


@dataclass
class Run:
    """The machine, the deployment the command built, and what was run on it."""

    cluster: Any
    deployment: manifest.Deployment
    key: Path
    observed: dict[str, str] = field(default_factory=dict)

    @property
    def vm(self) -> Any:
        return self.cluster.vm(MACHINE)

    @property
    def plan(self) -> Mapping[str, Any]:
        return self.deployment.plan

    def entry(self, key: str) -> manifest.Entry:
        """What the manifest records for one placed entry."""
        return self.deployment.entries[key]

    def artifact(self, key: str) -> Path:
        """The store path of the artifact the build produced for one plan key."""
        return manifest.artifact_of(self.entry(key))

    def attachment(self, key: str) -> dict[str, Any]:
        loaded = json.loads((self.artifact(key) / "attachment.json").read_text())
        assert isinstance(loaded, dict)
        return loaded

    def raw(self, key: str) -> str:
        """The image file itself, at the path the machine reads it from."""
        return str(self.artifact(key) / self.attachment(key)["image"])

    def units_of(self, key: str) -> list[str]:
        units = self.attachment(key)["units"]
        assert isinstance(units, list)
        return [str(unit) for unit in units]

    def logged(self) -> list[str]:
        """Every line the apply printed, steps and machine reports alike."""
        return self.observed["applied"].splitlines()

    def steps(self) -> list[str]:
        """The steps the apply took, one line each, in the order they happened."""
        return [line for line in self.logged() if not line.startswith("  ")]

    def under(self, step: str) -> str:
        """What the machine itself said, which the apply printed indented under a step."""
        lines = self.logged()
        reported: list[str] = []
        for line in lines[lines.index(step) + 1 :]:
            if not line.startswith("  "):
                break
            reported.append(f"{line[2:]}\n")
        return "".join(reported)

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
    return Run(cluster=booted.cluster, deployment=DEPLOYMENT, key=KEY)


@pytest.fixture(scope="session")
def delivered(run: Run) -> Run:
    """The host file the confined entry reads, and the foreign image beside it.

    The file is written by hand because that is what it is: a file an operator
    put there, which the image carries a recipe for and never the bytes of.

    The foreign image arrives by the one copy this harness still takes, and it is
    the harness's rather than the command's because the plan places that entry on
    another machine of another architecture: `planner apply` puts an artifact
    where the plan placed it, so nothing the command can be asked would put this
    one here. Getting it here anyway is what leaves the architecture refusal
    something to refuse, and it is why the address is stated in the argv.
    """
    if run.observed.get("delivered"):
        return run

    shown = run.shown_path()
    run.vm.ssh_succeed(f"mkdir -p {shlex.quote(os.path.dirname(shown))}")
    run.vm.ssh_succeed(f"printf %s {shlex.quote(SHOWN_TEXT)} > {shlex.quote(shown)}")

    address = manifest.address_of(run.entry(CONFINED_KEY))
    run.cluster.run(
        [
            "nix",
            "copy",
            "--to",
            f"ssh://{USER}@{address}",
            "--no-check-sigs",
            str(run.artifact(FOREIGN_KEY)),
        ],
        env=delivery.command_env(dict(os.environ), run.key),
    )

    run.observed["delivered"] = address
    return run


@pytest.fixture(scope="session")
def attached(delivered: Run) -> Run:
    """Phase 1: the confined entry applied by the command, which is what attaches it.

    One `planner apply` copies the artifact to the machine the plan placed it on
    and runs the attach script the artifact carries there, printing a line per
    step it took and the machine's own report under each. That output is the
    evidence the phase-1 tests read, so the apply happens once, here.
    """
    if delivered.observed.get("applied"):
        return delivered

    applied = delivered.cluster.run(
        [str(CLI), "apply", str(BUILT), "--only", CONFINED_KEY],
        env=delivery.command_env(dict(os.environ), delivered.key),
    )
    delivered.observed["applied"] = applied.stdout
    return delivered


@pytest.fixture(scope="session")
def detached(attached: Run) -> Run:
    """Phase 5: the same image detached by the other script it carries."""
    if attached.observed.get("detached"):
        return attached

    command = f"{attached.artifact(CONFINED_KEY)}/bin/detach"
    attached.vm.ssh_succeed(command, timeout=180)
    attached.observed["detached"] = command
    return attached


def test_an_image_entry_is_attached_by_the_command(attached: Run) -> None:
    """The command copied the artifact, ran its script, and the units it names run.

    The whole step log of an apply restricted to this one entry is the copy and
    the activation, in that order, and the lines under the activation are what
    the machine said while the artifact's own script ran: `portablectl`'s account
    of the unit files it took out of the image.
    """
    entry = attached.entry(CONFINED_KEY)
    activated = f"activate {CONFINED_KEY} (image) on {USER}@{entry.address}"
    assert attached.steps() == [
        f"copy {CONFINED_KEY} {entry.path} -> {USER}@{entry.address}",
        activated,
    ]

    report = attached.under(activated)
    state = attached.vm.ssh_succeed(
        f"portablectl is-attached {shlex.quote(attached.raw(CONFINED_KEY))}"
    ).strip()
    assert state != "detached", state

    for unit in attached.units_of(CONFINED_KEY):
        assert unit in report, report
        assert attached.vm.ssh(f"systemctl is-active {unit}").stdout.strip() == "active", report


def test_an_image_reports_the_attachment_word_the_machine_printed(attached: Run) -> None:
    """`portablectl` prints four words for an image a machine holds, and none is absence.

    The attachment started the units, so the word this machine gives is
    `running` rather than the plainest one the tool has. A report comparing
    against the plainest word would call an entry it just applied absent. The
    verdict is beside that word rather than instead of it: the machine names
    the identity it holds in the name of the image it has attached, and this
    machine holds the one this build published.
    """
    printed = attached.vm.ssh_succeed(
        f"portablectl is-attached {shlex.quote(attached.raw(CONFINED_KEY))}"
    ).strip()
    reported = attached.cluster.run(
        [str(CLI), "status", str(BUILT), "--only", CONFINED_KEY],
        env=delivery.command_env(dict(os.environ), attached.key),
    ).stdout.splitlines()

    assert len(reported) == 1, reported
    assert reported[0].startswith(f"{CONFINED_KEY} image {printed}"), (reported, printed)
    assert "absent" not in reported[0], reported


def test_the_image_is_attached_by_the_script_the_artifact_carries(attached: Run) -> None:
    """Nothing but the artifact's own script ran, and the machine holds its image."""
    entry = attached.entry(CONFINED_KEY)
    assert entry.realiser == "image"
    assert [step for step in attached.steps() if step.startswith("activate ")] == [
        f"activate {CONFINED_KEY} ({entry.realiser}) on {USER}@{entry.address}"
    ]

    raw = attached.raw(CONFINED_KEY)
    state = attached.vm.ssh_succeed(f"portablectl is-attached {shlex.quote(raw)}").strip()
    assert state in {"attached", "attached-runtime", "running", "running-runtime"}, state

    listed = attached.vm.ssh_succeed("portablectl list --no-legend")
    assert attached.attachment(CONFINED_KEY)["name"] in listed, listed


def test_the_attached_unit_becomes_active(attached: Run) -> None:
    """Every unit the attachment names is a unit the service manager is running."""
    units = attached.units_of(CONFINED_KEY)
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
    name = attached.attachment(CONFINED_KEY)["name"]
    shown = attached.vm.ssh_succeed(
        f"portablectl inspect --cat {shlex.quote(attached.raw(CONFINED_KEY))}"
    )
    assert f"PORTABLE_ID={name}" in shown, shown
    assert "PORTABLE_PRETTY_NAME=watch:file on alpha" in shown, shown


def test_a_command_resolves_inside_the_image(attached: Run) -> None:
    """The running unit's command is a path in the image, reached through the image.

    `RootImage` is the image the process is running out of, and the executable
    the unit names is under the store directory the plan recorded - which is
    what makes the entry's declared closure the only thing it can reach.
    """
    unit = attached.units_of(CONFINED_KEY)[0]
    raw = shlex.quote(attached.raw(CONFINED_KEY))
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

    The profile is a statement of the deployment, read back out of the manifest
    rather than out of a call this folder makes, so the image the machine
    enforces is the one the deployment asked for.

    The same file is read twice: by the confined unit, which reaches only the
    copy it was shown, and over ssh, where the operator's own file is plainly
    there. One of the two alone would be a claim about a missing file rather
    than about confinement.
    """
    stated = attached.entry(CONFINED_KEY)
    assert (stated.realiser, stated.profile) == ("image", "strict")

    profile = attached.attachment(CONFINED_KEY)["profile"]
    assert profile == stated.profile

    unit = attached.units_of(CONFINED_KEY)[0]
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
    stated = attached.entry(FOREIGN_KEY)
    assert (stated.realiser, stated.profile) == ("image", "default")
    assert attached.attachment(FOREIGN_KEY)["target"]["system"] == FOREIGN_SYSTEM

    refusal = attached.vm.ssh(f"{attached.artifact(FOREIGN_KEY)}/bin/attach", timeout=120)
    assert refusal.returncode != 0
    said = refusal.stdout + refusal.stderr
    assert FOREIGN_SYSTEM in said, said
    assert HOST_SYSTEM in said, said

    raw = attached.raw(FOREIGN_KEY)
    assert (
        attached.vm.ssh_succeed(f"portablectl is-attached {shlex.quote(raw)}").strip() == "detached"
    )
    for unit in attached.units_of(FOREIGN_KEY):
        loaded = attached.vm.ssh_succeed(f"systemctl show -P LoadState {unit}").strip()
        assert loaded == "not-found", loaded


def _status(run: Run, root: Path, key: str) -> tuple[int, list[str]]:
    """What `planner status` says about one entry of one build, and its exit status.

    The command runs inside the cluster because a machine's address exists only
    in the cluster's own net namespace, which is also why no test here drives the
    reporting module in this process.
    """
    asked = run.cluster.run(
        [str(CLI), "status", str(root), "--only", key],
        env=delivery.command_env(dict(os.environ), run.key),
        check=False,
    )
    return asked.returncode, asked.stdout.splitlines()


def _listed_state(run: Run, key: str) -> str:
    """The state the machine's own listing gives the image it holds for one entry."""
    name = run.attachment(key)["name"]
    listed = run.vm.ssh_succeed("portablectl list --no-legend")
    rows = [line.split() for line in listed.splitlines() if line.strip()]
    held = [columns[-1] for columns in rows if columns[0].startswith(f"{name}_")]
    assert len(held) == 1, listed
    return str(held[0])


def test_a_machine_holding_this_build_is_reported_as_current(attached: Run) -> None:
    """The identity the machine holds is the identity this build published.

    An image carries its identity in its own file name, so the comparison is
    identity equality and the machine names both halves of it: the image it has
    attached, and the listing it prints of what it holds.
    """
    entry = attached.entry(CONFINED_KEY)

    status, reported = _status(attached, BUILT, CONFINED_KEY)

    assert status == 0, reported
    assert len(reported) == 1, reported
    assert reported[0].endswith(" current"), reported
    assert attached.attachment(CONFINED_KEY)["image"].endswith(f"_{entry.digest}.raw")


def test_a_machine_holding_an_older_build_is_reported_with_both_identities(
    attached: Run,
) -> None:
    """This machine holds the first build, and the second build's report says so.

    An interrupted apply leaves a fleet in exactly this state, and the report has
    to tell it apart from a machine holding this build and from one holding
    nothing at all.
    """
    held = attached.entry(CONFINED_KEY).digest
    built = CHANGED_BUILD.entries[CONFINED_KEY].digest
    assert held != built, (held, built)

    status, reported = _status(attached, CHANGED, CONFINED_KEY)

    state = _listed_state(attached, CONFINED_KEY)
    assert reported == [f"{CONFINED_KEY} image {state} holds {held}, built {built}"], reported
    assert "absent" not in reported[0], reported
    assert status == 0, reported


def test_an_image_the_machine_already_holds_attached_is_not_attached_twice(
    attached: Run,
) -> None:
    """`portablectl` refuses an image it holds, so a second apply asks before attaching.

    The attach script the artifact carries runs under `set -eu` and ends in
    `portablectl attach`, so a run that took that step again would fail against a
    machine that is already in the intended state.
    """
    entry = attached.entry(CONFINED_KEY)

    again = attached.cluster.run(
        [str(CLI), "apply", str(BUILT), "--only", CONFINED_KEY],
        env=delivery.command_env(dict(os.environ), attached.key),
    )

    steps = [line for line in again.stdout.splitlines() if not line.startswith("  ")]
    assert steps == [
        f"copy {CONFINED_KEY} {entry.path} -> {USER}@{entry.address}",
        f"attached {CONFINED_KEY} already on {USER}@{entry.address}",
    ], again.stdout
    for unit in attached.units_of(CONFINED_KEY):
        assert attached.vm.ssh(f"systemctl is-active {unit}").stdout.strip() == "active"


@pytest.fixture(scope="session")
def stopped(attached: Run) -> Run:
    """Phase 6: the units stopped, the image still attached.

    The tool prints another word for an image whose units are not running, and a
    report about an attached idle entry is a different line from a report about a
    running one. Every test above this fixture needs the units running and the
    detach below does not care, so nothing is restored: the file order is the
    order.
    """
    if attached.observed.get("stopped"):
        return attached

    for unit in attached.units_of(CONFINED_KEY):
        attached.vm.ssh_succeed(f"systemctl stop {unit}")
    attached.observed["stopped"] = " ".join(attached.units_of(CONFINED_KEY))
    return attached


def test_an_attached_image_of_this_build_is_reported_as_current(stopped: Run) -> None:
    """The verdict is beside the word the machine's own tool printed, not instead of it."""
    printed = stopped.vm.ssh_succeed(
        f"portablectl is-attached {shlex.quote(stopped.raw(CONFINED_KEY))}"
    ).strip()

    status, reported = _status(stopped, BUILT, CONFINED_KEY)

    assert printed.startswith("attached"), printed
    assert reported == [f"{CONFINED_KEY} image {printed} current"], reported
    assert status == 0, reported


def test_an_attached_image_from_an_earlier_build_is_not_reported_as_current(
    stopped: Run,
) -> None:
    """An earlier build's image is attached, which is two facts and not one."""
    held = stopped.entry(CONFINED_KEY).digest
    built = CHANGED_BUILD.entries[CONFINED_KEY].digest

    status, reported = _status(stopped, CHANGED, CONFINED_KEY)

    state = _listed_state(stopped, CONFINED_KEY)
    assert reported == [f"{CONFINED_KEY} image {state} holds {held}, built {built}"], reported
    assert "current" not in reported[0], reported
    assert status == 0, reported


def test_detaching_removes_the_units_and_the_staging_directory(detached: Run) -> None:
    """The units are unknown again, the staging directory is gone, the store is not."""
    for unit in detached.units_of(CONFINED_KEY):
        loaded = detached.vm.ssh_succeed(f"systemctl show -P LoadState {unit}").strip()
        assert loaded == "not-found", loaded

    staging = detached.attachment(CONFINED_KEY)["staging"]
    assert detached.vm.ssh(f"test -e {shlex.quote(staging)}").returncode != 0

    for path in detached.attachment(CONFINED_KEY)["closure"]:
        assert (
            detached.vm.ssh_succeed(f"nix-store --check-validity {path} && echo ok").strip() == "ok"
        )


def test_a_host_file_the_image_was_shown_survives_detaching(detached: Run) -> None:
    """A file the machine was shown is the machine's, so detaching does not touch it."""
    shown = detached.shown_path()
    assert detached.vm.ssh_succeed(f"cat {shlex.quote(shown)}") == SHOWN_TEXT


# The assembly below runs on this host rather than on the machine, because what
# it observes is a window inside one script and the machine only ever shows the
# state after it. `PORTABLE_PLANNER_ROOT` is what the script already offers for
# staging an assembly somewhere other than `/`, so nothing is stubbed: this is
# the artifact's own script, reading the recipe the plan recorded.
ASSEMBLY = pytest.mark.skipif(
    shutil.which("systemctl") is None or platform.machine() != "x86_64",
    reason="the attach script's own guards refuse a host that is not the target",
)


def _staged() -> tuple[Path, str, str, str]:
    """The attach script, the file it stages, that file's mode, and the path it reads.

    The staged path and its mode are the attachment's; the path the recipe reads
    is the plan's, because a reference is a fragment of the recipe and never a
    host path of its own.
    """
    entry = DEPLOYMENT.entries[CONFINED_KEY]
    attachment = json.loads((manifest.artifact_of(entry) / "attachment.json").read_text())
    configuration = [p for p in attachment["hostPaths"] if p["kind"] == "configuration-file"]
    assert len(configuration) == 1, attachment["hostPaths"]
    records = list(DEPLOYMENT.plan[CONFINED_KEY]["configData"].values())
    assert len(records) == 1, records
    referenced = [item["ref"] for item in records[0]["render"] if "ref" in item]
    assert len(referenced) == 1, records
    return (
        manifest.artifact_of(entry) / "bin" / "attach",
        str(configuration[0]["from"]),
        str(configuration[0]["mode"]),
        str(referenced[0]),
    )


def _assemble(root: Path, mask: str) -> subprocess.CompletedProcess[str]:
    """Run the artifact's attach script against a root of this host, under one umask.

    It gets as far as `portablectl`, which is the first thing in it that needs a
    machine, so everything before that - the guards, the reference checks and the
    assembly - has happened by the time it returns.
    """
    script, _, _, _ = _staged()
    return subprocess.run(
        ["sh", "-c", f"umask {mask}; exec {shlex.quote(str(script))}"],
        env={"PATH": os.environ["PATH"], "PORTABLE_PLANNER_ROOT": str(root)},
        capture_output=True,
        text=True,
        check=False,
    )


@ASSEMBLY
def test_a_staged_file_renders_a_secret(tmp_path: Path) -> None:
    """The staged file carries its declared mode, the bytes are the recipe's, and
    nothing the assembly needed on the way is left behind. The fragment appended
    here is a reference to a host file rather than to a generated secret, and the
    rule is the same one: a login that would create a file at 0666 writes 0444
    because the declaration said so."""
    _, staged, mode, read = _staged()
    (tmp_path / read.lstrip("/")).parent.mkdir(parents=True)
    (tmp_path / read.lstrip("/")).write_text(SHOWN_TEXT)

    _assemble(tmp_path, "000")

    assembled = tmp_path / staged.lstrip("/")
    assert oct(assembled.stat().st_mode & 0o7777) == oct(int(mode, 8))
    assert assembled.read_text().endswith(SHOWN_TEXT)
    assert not assembled.with_name(f"{assembled.name}.assembling").exists()


@ASSEMBLY
def test_the_assembly_of_a_file_fails_part_way(tmp_path: Path) -> None:
    """A run that dies between the first byte and the last leaves nothing readable wider.

    The referenced path is a directory, so it exists for the check the script
    makes before it writes anything and then fails the `cat` that appends it.
    What is on the host at that point is the half-written file the assembly
    concatenates into, which nobody but its owner can read, and no file at the
    path the unit is shown.
    """
    _, staged, mode, read = _staged()
    (tmp_path / read.lstrip("/")).mkdir(parents=True)

    interrupted = _assemble(tmp_path, "000")
    assert interrupted.returncode != 0

    assembled = tmp_path / staged.lstrip("/")
    partial = assembled.with_name(f"{assembled.name}.assembling")
    assert not assembled.exists()
    assert partial.read_text() != ""
    assert oct(partial.stat().st_mode & 0o7777) == "0o600"

    (tmp_path / read.lstrip("/")).rmdir()
    (tmp_path / read.lstrip("/")).write_text(SHOWN_TEXT)
    _assemble(tmp_path, "000")
    assert assembled.read_text().endswith(SHOWN_TEXT)
    assert oct(assembled.stat().st_mode & 0o7777) == oct(int(mode, 8))


@ASSEMBLY
def test_the_mode_does_not_depend_on_the_attaching_environment(tmp_path: Path) -> None:
    """Two attaching environments, one mode: the declaration decides it, not the login.

    Both the file the unit is shown and the file it is assembled into are read,
    because a recipe that chmod-ed at the end would answer for the first under
    either mask and still have spent the assembly at whatever the login left.
    """
    _, staged, mode, read = _staged()
    finished = []
    staging = []
    for index, mask in enumerate(("000", "077")):
        whole = tmp_path / f"{index}-whole"
        (whole / read.lstrip("/")).parent.mkdir(parents=True)
        (whole / read.lstrip("/")).write_text(SHOWN_TEXT)
        _assemble(whole, mask)
        finished.append((whole / staged.lstrip("/")).stat().st_mode & 0o7777)

        # A directory where the recipe expects a file: the run gets as far as
        # appending it and stops, so what is on the host is the assembly itself.
        part = tmp_path / f"{index}-part"
        (part / read.lstrip("/")).mkdir(parents=True)
        _assemble(part, mask)
        partial = (part / staged.lstrip("/")).with_name(f"{Path(staged).name}.assembling")
        staging.append(partial.stat().st_mode & 0o7777)

    assert finished == [int(mode, 8), int(mode, 8)]
    assert staging == [0o600, 0o600]
