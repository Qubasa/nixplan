"""One real machine, four built deployments, and what attaching one does to it.

``nix run .#planner-e2e portable-image`` runs this. It builds the deployment this
folder declares with ``planner build $PLANNER_E2E_FLAKE#planner-e2e-portable-image``,
boots one rookery VM from ``$PLANNER_E2E_GUEST_IMAGE``, and puts the confined
entry on it with ``planner apply``, which copies the artifact and runs the attach
script that artifact carries. One test per scenario of
``openspec/specs/realiser/portable-service-image/spec.md``
that is about what a real machine does with a built image, named after it, plus
the image scenario of
``openspec/specs/operator/apply-command/spec.md``, the image scenarios of
``openspec/changes/retire-an-entry-a-build-no-longer-names/specs/operator/machine-report/spec.md``
and that change's retired-image scenario of its own ``apply-command`` delta, and
the failing-probe scenario of
``openspec/changes/probe-a-service-before-it-counts-as-live/specs/realiser/portable-service-image/spec.md``,
and the cross-entry scenarios of
``openspec/changes/bind-a-value-an-entry-did-not-generate/specs/delivery/real-cluster/spec.md``.

It builds that deployment four times. The second build,
``planner-e2e-portable-image-changed``, is attached by nothing and exists so
that a report about a machine holding an earlier build has two identities to
name. The third, ``planner-e2e-portable-image-retired``, is the same deployment
without ``beacon``, so that the image the machine holds for that entry is a
holding the build names no entry for. The fourth,
``planner-e2e-portable-image-probed``, declares a probe on ``beacon`` that
refuses.

The build runs in this process and the apply runs inside the cluster (`design.md
D8`): a build needs no address, and a machine's address exists only in the
cluster's own net namespace.

**The phases are ordered and the file order is the order.**

1. the command applies the confined entry, and that is what attaches it
2. the image is attached by the script the artifact carries, and its unit runs
3. the profile the entry was stated under is the one the machine enforces
4. an entry that generated none of it opens the value a peer entry generated
5. an image built for another architecture is refused by its own script
6. a report says what this machine holds, against this build and against another
7. the units are stopped, the image stays attached, and a report says so
8. detaching removes what attaching made, and leaves what it was shown
9. an image the machine holds for no entry of the build is named as the machine
   listed it, and retiring it is the endpoint's own removal verb
10. a probe that refuses is a failed apply step, and the image stays attached

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
import secrets
import shlex
import subprocess
from collections.abc import Iterator, Mapping
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
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
SECRET_VALUE = "watch:vars/upstream"
FOREIGN_KEY = "mirror:copy@elsewhere"
OPENER_KEY = "opener:read@alpha"
BEACON_KEY = "beacon:ping@alpha"
SHOWN_TEXT = "upstream says so\n"
EDITED_TEXT = "upstream changed its mind\n"
AGAIN_TEXT = "upstream said it twice\n"
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
RETIRED = _built(f"{FLAKE}#planner-e2e-portable-image-retired")
PROBED = _built(f"{FLAKE}#planner-e2e-portable-image-probed")
PROBED_BUILD = manifest.read(PROBED)


def _configured() -> tuple[str, str]:
    """The two files the confined entry is shown, read off the plan's own keyset.

    The module derives both paths from the identity of its entry, so they are
    read here rather than restated. One of the two names the unit that reloads
    for it and the other names none, which is what tells them apart.
    """
    records = DEPLOYMENT.plan[CONFINED_KEY]["configData"]
    reloading = sorted(path for path, record in records.items() if record["reload"])
    silent = sorted(path for path, record in records.items() if not record["reload"])
    assert (len(reloading), len(silent)) == (1, 1), records
    return str(reloading[0]), str(silent[0])


WATCHED, QUIET = _configured()


def _opened_copy() -> str:
    """Where the consuming entry writes what it read, off its own unit's command.

    The module derives that path inside `impl` from the identity of its entry,
    so it is read out of the plan rather than restated here.
    """
    units = DEPLOYMENT.plan[OPENER_KEY]["units"]
    assert len(units) == 1, units
    command = str(next(iter(units.values()))["command"])
    return command.split()[-1]


_OPENED_COPY = _opened_copy()


def _value_source(root: Path, deployment: manifest.Deployment, secret: str) -> Path:
    """Write this run's bytes where the command reads them from, and return the directory.

    The layout is ``<dir>/<value entry key>/<file>``, and what has to be there is
    read out of the manifest rather than restated: exactly the declared files of
    every value entry some machine receives.

    Args:
        root: A directory this run owns.
        deployment: The built deployment the bytes are for.
        secret: The bytes every declared file receives.

    Returns:
        The value source, readable by this user alone.
    """
    source = root / "portable-image-values"
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
            written.write_text(secret)
            written.chmod(0o600)
    return source


@dataclass
class Run:
    """The machine, the deployment the command built, and what was run on it."""

    cluster: Any
    deployment: manifest.Deployment
    key: Path
    secret: str
    source: Path
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

    def attached_raw(self, key: str) -> str:
        """The same file at the path the service manager names it by.

        The artifact is a farm of symlinks and the attach script names the image
        derivation directly, so `RootImage` answers with that path rather than
        with the link beside it.
        """
        return str(Path(self.raw(key)).resolve())

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

    def configuration(self, path: str) -> dict[str, Any]:
        """The plan record of one configuration file of the confined entry.

        Named by the path it is assembled at, because the entry declares two:
        one naming the unit that reads it and one naming no unit.
        """
        record = self.plan[CONFINED_KEY]["configData"][path]
        assert isinstance(record, dict), record
        return record

    def render(self, path: str = WATCHED) -> list[dict[str, str]]:
        """The recipe one configuration file of the confined entry is assembled from."""
        items = self.configuration(path)["render"]
        assert isinstance(items, list)
        return [dict(item) for item in items]

    def shown_path(self) -> str:
        """The host file those recipes read.

        Read out of the plan rather than restated here: the recipe naming that
        path is the only reason the machine needs the file at all.
        """
        for item in self.render():
            if "ref" in item:
                return item["ref"]
        raise AssertionError(f"{CONFINED_KEY} assembles no file from a host path")

    def recipe(self, path: str = WATCHED, shown: str = SHOWN_TEXT) -> str:
        """What a machine following one recipe has to end up with."""
        return "".join(item.get("text", shown) for item in self.render(path))

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
    secret = secrets.token_hex(16)
    return Run(
        cluster=booted.cluster,
        deployment=DEPLOYMENT,
        key=KEY,
        secret=secret,
        source=_value_source(delivery.state_root(), DEPLOYMENT, secret),
    )


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
        [
            str(CLI),
            "apply",
            str(BUILT),
            "--only",
            CONFINED_KEY,
            "--values",
            str(delivered.source),
        ],
        env=delivery.command_env(dict(os.environ), delivered.key),
    )
    delivered.observed["applied"] = applied.stdout
    return delivered


@pytest.fixture(scope="session")
def detached(attached: Run) -> Run:
    """The last phase: the same image detached by the other script it carries."""
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
    file = attached.deployment.values[SECRET_VALUE].files[0]
    # Values before units: the entry reads one, so its write is the first step.
    assert attached.steps() == [
        f"value {SECRET_VALUE} {file.name} -> {USER}@{entry.address}:{file.path}"
        f" ({file.owner}:{file.group} {file.mode})",
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


def test_a_confined_image_reads_a_group_readable_delivered_secret(attached: Run) -> None:
    """A secret is denied for its record, not for being a secret.

    The unit runs under `strict`, so it has no static account: its reader is a
    transient one. The file is delivered `nobody:nogroup` at a mode with group
    read and the unit declares that group, so the record admits it - and the
    realiser, whose denial reads the record, did not refuse the entry at all.
    """
    value = attached.deployment.values[SECRET_VALUE]
    file = value.files[0]
    assert (file.owner, file.group, file.mode) == ("nobody", "nogroup", "0440")
    assert value.delivery == (MACHINE,)

    unit = attached.units_of(CONFINED_KEY)[0]
    answered = attached.vm.ssh_succeed(
        f"printf 'groups=%s\\n' \"$(systemctl show -P SupplementaryGroups {shlex.quote(unit)})\"; "
        f"printf 'held=%s\\n' \"$(stat -c %U:%G:%a {shlex.quote(file.path)})\"; "
        f"printf 'logged=%s\\n' \"$(journalctl -u {shlex.quote(unit)} --no-pager -o cat"
        f" | grep -c 'secret-read: succeeded')\""
    )
    held = dict(line.split("=", 1) for line in answered.splitlines() if "=" in line)
    assert held["groups"] == "nogroup", held
    assert held["held"] == "nobody:nogroup:440", held
    # The transient account opened it, which is the whole claim.
    assert held["logged"] != "0", held

    logged = attached.vm.ssh_succeed(f"journalctl -u {unit} --no-pager -o cat")
    assert attached.reported(logged, "secret-read:") == f"succeeded with {attached.secret}"


@pytest.fixture(scope="session")
def opened(attached: Run) -> Run:
    """The entry that opens a value a different entry generated.

    One `planner apply` restricted to that entry writes every value its machine
    receives, copies the artifact and runs the attach script the artifact
    carries, which is the statement that shows the peer's value to a unit whose
    own declaration generates nothing. Everything the machine is asked about it
    is asked in one login, and every answer is one `key=value` line.

    The image is detached again once those answers are recorded, so this phase
    leaves the machine as it found it and the phases below are read over the
    state they were written against. The three tests read the recorded answers.
    """
    if attached.observed.get("opened"):
        return attached

    attached.observed["opened"] = str(
        attached.cluster.run(
            [
                str(CLI),
                "apply",
                str(BUILT),
                "--only",
                OPENER_KEY,
                "--values",
                str(attached.source),
            ],
            env=delivery.command_env(dict(os.environ), attached.key),
        ).stdout
    )

    unit = attached.units_of(OPENER_KEY)[0]
    owning = attached.units_of(CONFINED_KEY)[0]
    value = attached.deployment.values[SECRET_VALUE].files[0].path
    attached.observed["opened-answers"] = _asked(
        attached,
        f'echo "state=$(systemctl is-active {shlex.quote(unit)})"',
        f'echo "copy=$(cat {shlex.quote(_OPENED_COPY)} 2>&1)"',
        f'echo "host=$(cat {shlex.quote(value)} 2>&1)"',
        f'echo "record=$(stat -c %U:%G:%a {shlex.quote(value)})"',
        f'echo "files=$(ls -1 {shlex.quote(value)} | wc -l)"',
        f'echo "owner=$(journalctl -u {shlex.quote(owning)} --no-pager -o cat'
        f" | grep -c 'secret-read: succeeded')\"",
    )
    attached.observed["opened-unit-file"] = str(
        attached.vm.ssh_succeed(f"systemctl cat {shlex.quote(unit)}")
    )
    attached.vm.ssh_succeed(f"{attached.artifact(OPENER_KEY)}/bin/detach", timeout=180)
    return attached


def test_the_consumers_unit_opens_the_peers_value_on_the_machine(opened: Run) -> None:
    """The unit read the peer's value and wrote what it read, on the machine.

    The consuming entry generates nothing: the value is the watching entry's,
    and this entry's declared read is what puts it on this machine. The copy the
    unit wrote is the reading taken inside the unit's own mount namespace: the
    image carries an empty file at that path, so bytes there are the bind's and a
    copy equal to what this run generated cannot come from anywhere else.
    """
    answered = _pairs(opened.observed["opened-answers"])
    entry = opened.entry(OPENER_KEY)
    address = manifest.address_of(entry)
    steps = _steps(opened.observed["opened"])

    assert opened.plan[OPENER_KEY].get("vars", {}) == {}, opened.plan[OPENER_KEY]
    assert f"activate {OPENER_KEY} (image) on {USER}@{address}" in steps, steps
    assert answered["state"] == "active", answered
    assert answered["copy"] == opened.secret, answered
    assert answered["host"] == opened.secret, answered


def test_the_bind_comes_from_the_artifacts_own_unit_file(opened: Run) -> None:
    """The statement that shows the value is the realiser's, not the harness's.

    The unit file is read off the machine, where `portablectl` put the copy it
    took out of the delivered image, so nothing here constructed it. The bind is
    one line among the statements the attachment carries, the profile's own
    drop-in adding binds of its own, and the mount point it needs is the image's:
    the image root is a read-only squashfs, so a bind onto a path the image does
    not carry is a unit that cannot start at all.
    """
    value = opened.deployment.values[SECRET_VALUE].files[0].path
    answered = _pairs(opened.observed["opened-answers"])
    lines = [line.strip() for line in opened.observed["opened-unit-file"].splitlines()]
    described = opened.attachment(OPENER_KEY)["hostPaths"]

    assert f"BindReadOnlyPaths={value}:{value}" in lines, lines
    assert [(shown["path"], shown["kind"]) for shown in described] == [(value, "generated-file")], (
        described
    )
    assert answered["state"] == "active", answered


def test_one_file_on_the_machine_serves_both_entries(opened: Run) -> None:
    """One value is one file, and the owner and the reader are shown that one path.

    The delivery writes the path the value's own entry records, so neither entry
    is shown a copy of its own, and the record on the machine is the record the
    value entry states rather than anything either reading chose.
    """
    value = opened.deployment.values[SECRET_VALUE].files[0]
    answered = _pairs(opened.observed["opened-answers"])
    owning = opened.attachment(CONFINED_KEY)["hostPaths"]
    reading = opened.attachment(OPENER_KEY)["hostPaths"]

    assert answered["files"] == "1", answered
    assert answered["record"] == f"{value.owner}:{value.group}:440", answered
    # The owner's unit read it, and the reader's copy is those same bytes.
    assert answered["owner"] != "0", answered
    assert answered["copy"] == opened.secret, answered
    assert [shown["path"] for shown in owning if shown["kind"] == "generated-file"] == [
        value.path
    ], owning
    assert [shown["path"] for shown in reading] == [value.path], reading


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


def _bytes_at(run: Run, path: str) -> str:
    """What the machine holds for one of the entry's configuration files.

    Read at the staging path the attachment records rather than at the path the
    unit is shown: that one exists inside the image's own mount namespace and
    nowhere on the host.
    """
    staged, _, _ = _staged(path)
    return str(run.vm.ssh_succeed(f"cat {shlex.quote(staged)}"))


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


def test_an_entry_that_matches_in_every_respect(attached: Run) -> None:
    """The image is this build's and so are the bytes beside it, so the word is `current`.

    An image's version digest excludes a configuration file's bytes on purpose,
    so `current` is a claim about both halves and the report has to have asked
    the machine about the second one.
    """
    status, reported = _status(attached, BUILT, CONFINED_KEY)

    assert status == 0, reported
    assert reported == [f"{CONFINED_KEY} image {_listed_state(attached, CONFINED_KEY)} current"]
    for path in (WATCHED, QUIET):
        held = _bytes_at(attached, path)
        assert held == attached.recipe(path), (path, held)


def _apply(run: Run, root: Path) -> str:
    """Apply one build of this deployment's confined entry, and return the whole log."""
    return str(
        run.cluster.run(
            [
                str(CLI),
                "apply",
                str(root),
                "--only",
                CONFINED_KEY,
                "--values",
                str(run.source),
            ],
            env=delivery.command_env(dict(os.environ), run.key),
        ).stdout
    )


def _main_pids(run: Run, key: str) -> dict[str, str]:
    """The main process of each unit of one entry, as the machine reports it.

    One login for every unit: the guest's sshd is per-connection socket
    activated, so a burst of short logins is answered by the socket's own
    trigger limit rather than by a shell.
    """
    units = run.units_of(key)
    asked = "; ".join(
        f"printf '%s=%s\\n' {shlex.quote(unit)} "
        f'"$(systemctl show -P MainPID {shlex.quote(unit)})"'
        for unit in units
    )
    answered = run.vm.ssh_succeed(asked)
    reported = dict(line.split("=", 1) for line in answered.splitlines() if "=" in line)
    assert set(reported) == set(units), answered
    return reported


def _steps(logged: str) -> list[str]:
    """The steps one apply took, one line each, in the order they happened."""
    return [line for line in logged.splitlines() if not line.startswith(" ")]


def _said(logged: str) -> list[str]:
    """What the machines said, which the apply printed indented under its steps."""
    return [line.strip() for line in logged.splitlines() if line.startswith(" ")]


@pytest.fixture(scope="session")
def reapplied(attached: Run) -> Run:
    """Phase 2: the same build applied again, with nothing changed in between.

    The command asks nothing before activating, so this run takes every step the
    first one took. What the phase is for is the machine's own answer to each of
    them, and the processes it left alone.
    """
    if attached.observed.get("reapplied"):
        return attached

    attached.observed["before-reapply"] = json.dumps(_main_pids(attached, CONFINED_KEY))
    attached.observed["reapplied"] = _apply(attached, BUILT)
    attached.observed["after-reapply"] = json.dumps(_main_pids(attached, CONFINED_KEY))
    return attached


def test_a_first_attachment(attached: Run) -> None:
    """The first apply attached and started, and replaced nothing.

    A machine holding no image of an entry has nothing to replace, so the
    attachment is the whole of what the script did there.
    """
    step = f"activate {CONFINED_KEY} (image) on {USER}@{attached.entry(CONFINED_KEY).address}"
    said = attached.under(step).splitlines()

    assert f"attached {attached.attachment(CONFINED_KEY)['image']}" in said, said
    assert f"started {' '.join(attached.units_of(CONFINED_KEY))}" in said, said
    assert [line for line in said if line.startswith("replaced ")] == [], said


def test_an_unchanged_deployment_applied_twice(reapplied: Run) -> None:
    """Both runs take every step, and the second one changed nothing on the machine.

    No entry is skipped for being present: whether an activation is a change is
    the activation's own answer, and here it is that nothing was.
    """
    logged = reapplied.observed["reapplied"]

    assert _steps(logged) == reapplied.steps(), logged
    assert _said(logged) == ["unchanged", "nothing changed"], logged
    assert json.loads(reapplied.observed["before-reapply"]) == json.loads(
        reapplied.observed["after-reapply"]
    ), logged


def test_the_same_build_run_again(reapplied: Run) -> None:
    """The image the machine runs the entry from is the one it already ran it from.

    `RootImage` is the fact the replacement step reads, so the claim that nothing
    was detached and re-attached is made against that and not against a listing.
    """
    unit = reapplied.units_of(CONFINED_KEY)[0]

    held = reapplied.vm.ssh_succeed(f"systemctl show -P RootImage {shlex.quote(unit)}").strip()

    assert held == reapplied.attached_raw(CONFINED_KEY), held
    assert "replaced" not in reapplied.observed["reapplied"]
    assert json.loads(reapplied.observed["before-reapply"]) == json.loads(
        reapplied.observed["after-reapply"]
    )


def test_the_script_run_twice_over_an_unchanged_entry(reapplied: Run) -> None:
    """Run by hand a third time, the artifact's own script says nothing changed.

    The command is not in the way here: the script is the whole decision about
    what the machine holds of one entry, so running it directly is what tests
    that running it twice is running it once.
    """
    script = f"{reapplied.artifact(CONFINED_KEY)}/bin/attach"
    before = _main_pids(reapplied, CONFINED_KEY)

    said = reapplied.vm.ssh_succeed(script, timeout=180).strip()

    assert said == "nothing changed", said
    assert _main_pids(reapplied, CONFINED_KEY) == before
    for path in (WATCHED, QUIET):
        assert _bytes_at(reapplied, path) == reapplied.recipe(path)


def test_a_file_whose_bytes_did_not_change(reapplied: Run) -> None:
    """An unchanged configuration file is assembled over nothing and reloads nothing."""
    logged = reapplied.observed["reapplied"]

    assert [line for line in _said(logged) if line.startswith("assembled ")] == [], logged
    assert [line for line in _said(logged) if "reload" in line or "restart" in line] == [], logged


def test_a_value_whose_bytes_are_unchanged(reapplied: Run) -> None:
    """The write says the bytes did not move, and still sets the ownership and mode."""
    file = reapplied.deployment.values[SECRET_VALUE].files[0]
    logged = reapplied.observed["reapplied"]

    assert "unchanged" in _said(logged), logged
    answered = reapplied.vm.ssh_succeed(f"stat -c '%a %U %G' {shlex.quote(file.path)}").strip()
    assert answered == f"{int(file.mode, 8):o} {file.owner} {file.group}", answered


def test_an_unchanged_value_restarts_nothing(reapplied: Run) -> None:
    """A value whose bytes did not move causes no restart step and moves no process."""
    logged = reapplied.observed["reapplied"]

    assert [line for line in _steps(logged) if line.startswith("restart ")] == [], logged
    assert json.loads(reapplied.observed["before-reapply"]) == json.loads(
        reapplied.observed["after-reapply"]
    )


@pytest.fixture(scope="session")
def edited(reapplied: Run) -> Run:
    """Phase 3: the host file the two recipes read, rewritten and nothing applied.

    The machine now holds an artifact whose identity is current and bytes that
    are not, which is the state the report has to tell apart from a current one.
    """
    if reapplied.observed.get("edited"):
        return reapplied

    shown = reapplied.shown_path()
    reapplied.vm.ssh_succeed(f"printf %s {shlex.quote(EDITED_TEXT)} > {shlex.quote(shown)}")
    reapplied.observed["edited"] = EDITED_TEXT
    return reapplied


def test_an_entry_whose_configuration_bytes_are_out_of_date(edited: Run) -> None:
    """The artifact matches and the bytes beside it do not, and the line says which.

    The word for a fully current entry is not printed here, and the path that
    disagrees is named, so an operator can tell the two halves apart.
    """
    status, reported = _status(edited, BUILT, CONFINED_KEY)

    assert status == 0, reported
    assert len(reported) == 1, reported
    assert not reported[0].endswith(" current"), reported
    assert "holds this build's image" in reported[0], reported
    assert WATCHED in reported[0] and QUIET in reported[0], reported
    assert "stale" in reported[0], reported


@pytest.fixture(scope="session")
def reassembled(edited: Run) -> Run:
    """Phase 4: the deployment applied over the edited file."""
    if edited.observed.get("reassembled"):
        return edited

    edited.observed["before-reassembly"] = json.dumps(_main_pids(edited, CONFINED_KEY))
    edited.observed["reassembled"] = _apply(edited, BUILT)
    edited.observed["after-reassembly"] = json.dumps(_main_pids(edited, CONFINED_KEY))
    return edited


def test_an_entry_whose_configuration_bytes_changed_and_whose_image_did_not(
    reassembled: Run,
) -> None:
    """The new bytes are there, the image was neither detached nor re-attached."""
    unit = reassembled.units_of(CONFINED_KEY)[0]
    logged = reassembled.observed["reassembled"]

    held = _bytes_at(reassembled, WATCHED)

    assert held == reassembled.recipe(WATCHED, EDITED_TEXT), held
    assert f"assembled {WATCHED}" in _said(logged), logged
    assert [line for line in _said(logged) if line.startswith("attached ")] == [], logged
    assert [line for line in _said(logged) if line.startswith("replaced ")] == [], logged
    assert reassembled.vm.ssh_succeed(
        f"systemctl show -P RootImage {shlex.quote(unit)}"
    ).strip() == reassembled.attached_raw(CONFINED_KEY)


def test_an_entry_whose_configuration_bytes_changed(reassembled: Run) -> None:
    """The command's own step reports the file as changed, by the machine's answer.

    The line is printed under the activation step rather than beside it: what
    changed is the activation's answer and the command repeats it.
    """
    logged = reassembled.observed["reassembled"]
    step = f"activate {CONFINED_KEY} (image) on {USER}@{reassembled.entry(CONFINED_KEY).address}"
    reported = [line.strip() for line in logged.splitlines()]

    assert step in _steps(logged), logged
    assert reported.index(f"assembled {WATCHED}") > reported.index(step), logged
    assert "nothing changed" not in _said(logged), logged


def test_an_edited_file_reloads_the_unit_it_named(reassembled: Run) -> None:
    """The unit the edited file named is a new process, and the step names both.

    The unit declares no reload command, so the service manager's answer to a
    reload of it is a restart, which is the word the line carries.
    """
    unit = reassembled.units_of(CONFINED_KEY)[0]
    said = _said(reassembled.observed["reassembled"])

    assert f"restarted {unit} for {WATCHED}" in said, said
    assert (
        json.loads(reassembled.observed["before-reassembly"])[unit]
        != json.loads(reassembled.observed["after-reassembly"])[unit]
    )


def test_a_file_naming_no_unit(reassembled: Run) -> None:
    """The other file's bytes were written and nothing was reloaded on its account."""
    said = _said(reassembled.observed["reassembled"])

    held = _bytes_at(reassembled, QUIET)

    assert held == reassembled.recipe(QUIET, EDITED_TEXT), held
    assert f"assembled {QUIET}" in said, said
    assert [line for line in said if line.endswith(f"for {QUIET}")] == [], said


@pytest.fixture(scope="session")
def replaced(reassembled: Run) -> Run:
    """Phase 5: the other build applied over this one, and this one applied back.

    Both directions are one replacement, and the restore is what leaves the
    machine holding the build every phase below reads.
    """
    if reassembled.observed.get("replaced"):
        return reassembled

    reassembled.observed["replaced"] = _apply(reassembled, CHANGED)
    reassembled.observed["listed-after-replacement"] = reassembled.vm.ssh_succeed(
        "portablectl list --no-legend"
    )
    reassembled.observed["restored"] = _apply(reassembled, BUILT)
    return reassembled


def test_a_second_build_of_an_attached_entry(replaced: Run) -> None:
    """The previous image was stopped and detached, and one image is left.

    The image the entry ran from is read from the service manager rather than
    guessed from a name, because two builds of one entry render the same unit
    file names.
    """
    said = _said(replaced.observed["replaced"])
    changed = CHANGED_BUILD.entries[CONFINED_KEY]
    image = json.loads((manifest.artifact_of(changed) / "attachment.json").read_text())

    assert f"replaced {replaced.attached_raw(CONFINED_KEY)}" in said, said
    assert f"attached {image['image']}" in said, said
    assert f"started {' '.join(replaced.units_of(CONFINED_KEY))}" in said, said

    name = replaced.attachment(CONFINED_KEY)["name"]
    listed = replaced.observed["listed-after-replacement"]
    rows = [line.split() for line in listed.splitlines() if line.strip()]
    assert [columns[0] for columns in rows if columns[0].startswith(f"{name}_")] == [
        str(image["image"]).removesuffix(".raw")
    ], listed


def test_an_entry_whose_artifact_identity_changed(replaced: Run) -> None:
    """The machine runs the build that was applied last, and holds no other.

    Applied back, the first build replaces the second the same way, which is what
    leaves this machine holding it for the phases below.
    """
    unit = replaced.units_of(CONFINED_KEY)[0]
    said = _said(replaced.observed["restored"])
    changed = CHANGED_BUILD.entries[CONFINED_KEY]
    other = json.loads((manifest.artifact_of(changed) / "attachment.json").read_text())

    held = replaced.vm.ssh_succeed(f"systemctl show -P RootImage {shlex.quote(unit)}").strip()

    assert held == replaced.attached_raw(CONFINED_KEY), held
    other_raw = Path(manifest.artifact_of(changed) / str(other["image"])).resolve()
    assert f"replaced {other_raw}" in said, said
    assert _listed_state(replaced, CONFINED_KEY) != "detached"


@pytest.fixture(scope="session")
def stopped(replaced: Run) -> Run:
    """Phase 6: the units stopped, the image still attached.

    The tool prints another word for an image whose units are not running, and a
    report about an attached idle entry is a different line from a report about a
    running one. Every test above this fixture needs the units running and the
    detach below does not care, so nothing is restored: the file order is the
    order.
    """
    if replaced.observed.get("stopped"):
        return replaced

    for unit in replaced.units_of(CONFINED_KEY):
        replaced.vm.ssh_succeed(f"systemctl stop {unit}")
    replaced.observed["stopped"] = " ".join(replaced.units_of(CONFINED_KEY))
    return replaced


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


def test_a_unit_that_is_not_running_is_not_started_by_a_reload(stopped: Run) -> None:
    """A stopped unit stays stopped, and the file it named is written anyway.

    Which units run at all is the attachment's answer: this image is already
    attached, so nothing here starts anything, and the reload of a unit that is
    not running is not a reason to start it.
    """
    unit = stopped.units_of(CONFINED_KEY)[0]
    shown = stopped.shown_path()
    stopped.vm.ssh_succeed(f"printf %s {shlex.quote(AGAIN_TEXT)} > {shlex.quote(shown)}")

    logged = _apply(stopped, BUILT)

    said = _said(logged)
    assert f"assembled {WATCHED}" in said, said
    assert [line for line in said if line.startswith(("restarted ", "reloaded "))] == [], said
    assert [line for line in said if line.startswith("started ")] == [], said
    assert stopped.vm.ssh(f"systemctl is-active {unit}").stdout.strip() == "inactive"
    assert _bytes_at(stopped, WATCHED) == stopped.recipe(WATCHED, AGAIN_TEXT)


# The assembly below runs on the machine, like everything else this folder
# observes, and under a root of its own: `PORTABLE_PLANNER_ROOT` is what the
# attach script already offers for staging an assembly somewhere other than `/`,
# so this is the artifact's own script reading the recipe the plan recorded.
#
# What the script does after the assembly - `portablectl attach` and `systemctl
# start` - is the machine's attachment, which the phases above already made and
# the phase below takes apart. Those two commands are answered by a `PATH` of
# this run's own, so the script stops at the first thing that would change the
# machine and the window the assembly opens is all these tests observe.


def _staged(path: str = WATCHED) -> tuple[str, str, str]:
    """The file the attach script stages, that file's mode, and the path it reads.

    The staged path and its mode are the attachment's; the path the recipe reads
    is the plan's, because a reference is a fragment of the recipe and never a
    host path of its own. The entry declares two configuration files, so which
    one is meant is named rather than assumed.
    """
    entry = DEPLOYMENT.entries[CONFINED_KEY]
    attachment = json.loads((manifest.artifact_of(entry) / "attachment.json").read_text())
    configuration = [
        p
        for p in attachment["hostPaths"]
        if p["kind"] == "configuration-file" and p["path"] == path
    ]
    assert len(configuration) == 1, attachment["hostPaths"]
    record = DEPLOYMENT.plan[CONFINED_KEY]["configData"][path]
    referenced = [item["ref"] for item in record["render"] if "ref" in item]
    assert len(referenced) == 1, record
    return (str(configuration[0]["from"]), str(configuration[0]["mode"]), str(referenced[0]))


STOP = "/run/planner-assembly/stop-here"


@pytest.fixture(scope="session")
def assembling(stopped: Run) -> Run:
    """A machine ready to run the attach script without attaching anything.

    The two commands the script ends in are answered by a directory of this
    run's own: `command -v systemctl` is one of the script's guards, so the name
    has to resolve, and what it does when the script runs it is refuse, which
    ends the run where the assembly ends.
    """
    if stopped.observed.get("assembling"):
        return stopped

    stubs = " && ".join(
        f"printf '#!/bin/sh\\nexit 1\\n' > {STOP}/{name} && chmod 0755 {STOP}/{name}"
        for name in ("portablectl", "systemctl")
    )
    stopped.vm.ssh_succeed(f"mkdir -p {STOP} && {stubs}")
    stopped.observed["assembling"] = STOP
    return stopped


def _probe(run: Run, case: str, mask: str, *, shown: bool, fresh: bool = True) -> dict[str, str]:
    """Assemble under one root and one umask, and report what the machine holds.

    One command rather than one per observation: the machine's sshd is
    per-connection socket activated, and a burst of short logins is answered by
    the socket's own trigger limit rather than by a shell.

    Args:
        run: The machine and the deployment the command built.
        case: A name for the root this case assembles under.
        mask: The umask the attaching login runs with.
        shown: Whether the file the recipe reads is a file. A directory in its
            place passes the check the script makes before it writes anything
            and fails the `cat` that appends it, which is the interrupted run.
        fresh: Whether to clear the root first. A case run twice with this
            false is a run resuming what the interrupted one left behind.

    Returns:
        The mode of the staged file and of the assembly beside it - `none`
        where there is no such file - and whether the staged file ends in the
        bytes of the file the recipe references.
    """
    staged, _, read = _staged()
    root = f"/run/planner-assembly/{case}"
    script = f"{run.artifact(CONFINED_KEY)}/bin/attach"
    # Every path the image is shown has to exist under the fake root, or the
    # script stops at its own check before it assembles anything. The delivered
    # secret is one of them and is its own source, so a file is all it needs.
    delivered = run.deployment.values[SECRET_VALUE].files[0].path
    place = "; ".join(
        [
            f"mkdir -p $(dirname {root}{delivered}) && : > {root}{delivered}",
            f"rm -rf {root}{read}",
            f"mkdir -p $(dirname {root}{read})",
            (
                f"printf %s {shlex.quote(SHOWN_TEXT)} > {root}{read}"
                if shown
                else f"mkdir -p {root}{read}"
            ),
        ]
    )
    tail = (
        f"if [ -f {root}{read} ] && [ -f {root}{staged} ] && "
        f"tail -c $(wc -c < {root}{read}) {root}{staged} | cmp -s - {root}{read}; "
        'then echo "tail=referenced"; else echo "tail=other"; fi'
    )
    reported = run.vm.ssh_succeed(
        "; ".join(
            ([f"rm -rf {root}"] if fresh else [])
            + [
                place,
                f"env PATH={STOP}:$PATH PORTABLE_PLANNER_ROOT={root} "
                f"sh -c {shlex.quote(f'umask {mask}; exec {script}')} > /dev/null 2>&1",
                f'echo "staged=$(stat -c %a {root}{staged} 2>/dev/null || echo none)"',
                f'echo "assembly=$(stat -c %a {root}{staged}.assembling 2>/dev/null || echo none)"',
                f"echo \"partials=$(find {root} -name '*.assembling' -printf '%m ')\"",
                tail,
            ]
        ),
        timeout=180,
    )
    answered = dict(line.split("=", 1) for line in reported.splitlines() if "=" in line)
    assert {"staged", "assembly", "tail", "partials"} <= answered.keys(), reported
    return answered


def test_an_interrupted_run_leaves_no_widened_file(assembling: Run) -> None:
    """A run that stopped part way leaves no widened file, and the next one finishes.

    The same root twice: the first run dies in the middle of the concatenation,
    the second is handed the file the recipe reads and completes the assembly.
    """
    _, mode, _ = _staged()
    declared = f"{int(mode, 8):o}"

    interrupted = _probe(assembling, "resumed", "000", shown=False)
    finished = _probe(assembling, "resumed", "000", shown=True, fresh=False)

    assert interrupted["staged"] == "none", interrupted
    assert set(interrupted["partials"].split()) == {"600"}, interrupted
    assert finished["staged"] == declared, finished
    assert finished["tail"] == "referenced", finished
    assert finished["partials"].split() == [], finished


def test_a_staged_file_renders_a_secret(assembling: Run) -> None:
    """The staged file carries its declared mode, the bytes are the recipe's, and
    nothing the assembly needed on the way is left behind. The fragment appended
    here is a reference to a host file rather than to a generated secret, and the
    rule is the same one: a login that would create a file at 0666 writes 0444
    because the declaration said so."""
    _, mode, _ = _staged()

    answered = _probe(assembling, "whole", "000", shown=True)

    assert answered["staged"] == f"{int(mode, 8):o}"
    assert answered["tail"] == "referenced", answered
    assert answered["assembly"] == "none"


def test_the_assembly_of_a_file_fails_part_way(assembling: Run) -> None:
    """A run that dies between the first byte and the last leaves nothing readable wider.

    What is on the machine at that point is the half-written file the assembly
    concatenates into, which nobody but its owner can read, and no file at the
    path the unit is shown.
    """
    interrupted = _probe(assembling, "part", "000", shown=False)

    assert interrupted["staged"] == "none"
    assert set(interrupted["partials"].split()) == {"600"}, interrupted


def test_the_mode_does_not_depend_on_the_attaching_environment(assembling: Run) -> None:
    """Two attaching environments, one mode: the declaration decides it, not the login.

    Both the file the unit is shown and the file it is assembled into are read,
    because a recipe that chmod-ed at the end would answer for the first under
    either mask and still have spent the assembly at whatever the login left.
    """
    _, mode, _ = _staged()
    permissive = (
        _probe(assembling, "open-whole", "000", shown=True),
        _probe(assembling, "open-part", "000", shown=False),
    )
    restrictive = (
        _probe(assembling, "tight-whole", "077", shown=True),
        _probe(assembling, "tight-part", "077", shown=False),
    )

    declared = f"{int(mode, 8):o}"
    assert [answered["staged"] for answered in (permissive[0], restrictive[0])] == [
        declared,
        declared,
    ]
    assert [set(answered["partials"].split()) for answered in (permissive[1], restrictive[1])] == [
        {"600"},
        {"600"},
    ]


def test_a_staged_file_is_readable_through_a_directory_nobody_may_list(assembling: Run) -> None:
    """Traversal is the only access a unit needs, and it is the only one an account has.

    A unit reaches a staged file by its full path through `BindReadOnlyPaths`, so
    the directories above it are created traversable and not listable. What a
    listable one would publish is the configuration file names of every entry on
    the machine, to any account, which no declaration asked to be published.
    """
    staged, mode, _ = _staged()
    root = "/run/planner-assembly/unlistable"
    staging = assembling.attachment(CONFINED_KEY)["staging"]
    leaf = str(PurePosixPath(staged).parent)

    assembled = _probe(assembling, "unlistable", "000", shown=True)
    assert assembled["staged"] == f"{int(mode, 8):o}", assembled

    def unprivileged(command: str) -> str:
        return f"su -s /bin/sh -c {shlex.quote(command)} nobody"

    reported = assembling.vm.ssh_succeed(
        "; ".join(
            [
                f'echo "entry=$(stat -c %a {root}{staging})"',
                f'echo "leaf=$(stat -c %a {root}{leaf})"',
                f"if {unprivileged(f'cat {root}{staged}')} > /dev/null 2>&1; "
                'then echo "read=yes"; else echo "read=no"; fi',
                f"if {unprivileged(f'ls {root}{leaf}')} > /dev/null 2>&1; "
                'then echo "list=yes"; else echo "list=no"; fi',
                f"if {unprivileged(f'ls {root}{staging}')} > /dev/null 2>&1; "
                'then echo "listEntry=yes"; else echo "listEntry=no"; fi',
            ]
        ),
        timeout=180,
    )
    answered = dict(line.split("=", 1) for line in reported.splitlines() if "=" in line)

    assert answered["entry"] == "711", answered
    assert answered["leaf"] == "711", answered
    assert answered["read"] == "yes", answered
    assert answered["list"] == "no", answered
    assert answered["listEntry"] == "no", answered


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
    """A file the machine was shown is the machine's, so detaching does not touch it.

    The bytes are the last ones a phase above wrote there, which is the point: an
    operator's file is not the attachment's to restore or remove.
    """
    shown = detached.shown_path()
    assert detached.vm.ssh_succeed(f"cat {shlex.quote(shown)}") == AGAIN_TEXT


# The phases below are last in file order because the file order is the phase
# order and nothing is restored between them: the one above leaves the machine
# with nothing attached, so the first of these puts an image there again, and
# the last one leaves an image attached that no phase takes away - this realiser
# has no generation to return to, which is the claim it proves.


def _listed_names(listing: str) -> list[str]:
    """Every image name one `portablectl list --no-legend` printed, in its order."""
    return [line.split()[0] for line in listing.splitlines() if line.strip()]


def _image_of(deployment: manifest.Deployment, key: str) -> dict[str, Any]:
    """The attachment description one build published for one entry.

    Read off the build being asked about rather than off the run's own, because
    two of the phases below hold one entry's image against another build of it.
    """
    loaded = json.loads(
        (manifest.artifact_of(deployment.entries[key]) / "attachment.json").read_text()
    )
    assert isinstance(loaded, dict), loaded
    return loaded


def _held_name(deployment: manifest.Deployment, key: str) -> str:
    """The name a machine's own listing gives the image one build published."""
    return str(_image_of(deployment, key)["image"]).removesuffix(".raw")


def _asked(run: Run, *asked: str) -> str:
    """Ask one machine several things in one login and return what it printed.

    One login rather than one per observation: the guest's sshd is
    per-connection socket activated, and a burst of short logins is answered by
    the socket's own trigger limit rather than by a shell.
    """
    return str(run.vm.ssh_succeed("; ".join(asked), timeout=180))


def _pairs(reported: str) -> dict[str, str]:
    """The `key=value` lines of one such answer, which is how a machine is read here."""
    return dict(line.split("=", 1) for line in reported.splitlines() if "=" in line)


@pytest.fixture(scope="session")
def beaconed(detached: Run) -> Run:
    """Phase 8: an image the machine holds for an entry the build below drops.

    Nothing is attached when this runs, the phase above having detached the only
    image the machine held, so this one is what puts an image there again. It is
    the artifact's own `bin/attach` and not an apply on purpose: what the tests
    below read is a machine holding something a build names no entry for, and an
    apply is a build naming it. The artifact arrives by the harness's own copy
    for the same reason.
    """
    if detached.observed.get("beaconed"):
        return detached

    artifact = detached.artifact(BEACON_KEY)
    address = manifest.address_of(detached.entry(BEACON_KEY))
    detached.cluster.run(
        [
            "nix",
            "copy",
            "--to",
            f"ssh://{USER}@{address}",
            "--no-check-sigs",
            str(artifact),
        ],
        env=delivery.command_env(dict(os.environ), detached.key),
    )
    detached.observed["beaconed"] = detached.vm.ssh_succeed(
        f"{artifact}/bin/attach > /dev/null && portablectl list --no-legend", timeout=300
    )
    return detached


def test_an_image_the_machine_holds_for_no_entry_of_the_build_is_named_as_the_machine_listed_it(
    beaconed: Run,
) -> None:
    """The line carries the name the machine printed, and derives no plan key from it.

    The projection a plan key is turned into an image name by is not injective,
    so the only identity an image the build names nothing for has is the name
    the machine's own listing gave it. The entry the build still names keeps its
    own line, and the holding costs no exit status.
    """
    listed = _listed_names(beaconed.observed["beaconed"])
    held = _held_name(DEPLOYMENT, BEACON_KEY)

    status, reported = _status(beaconed, RETIRED, CONFINED_KEY)

    assert held in listed, beaconed.observed["beaconed"]
    assert [line for line in reported if "does not name" in line] == [
        f"{MACHINE} holds {held}, which this build does not name"
    ], reported
    assert "beacon:ping" not in "\n".join(reported), reported
    assert [line for line in reported if line.startswith(CONFINED_KEY)] != [], reported
    assert status == 0, reported


@pytest.fixture(scope="session")
def retired(beaconed: Run) -> Run:
    """Phase 9: the build that names no `beacon` entry, applied and asked to retire.

    Restricted to the entry this build still places on the machine, which bounds
    the machines the run asks and decides nothing about what counts as a
    holding. The apply attaches that entry as it would any other, which is what
    leaves the two tests below an image of an earlier build of a named entry
    beside a retirement.
    """
    if beaconed.observed.get("retired"):
        return beaconed

    beaconed.observed["retired"] = beaconed.cluster.run(
        [
            str(CLI),
            "apply",
            str(RETIRED),
            "--retire",
            "--only",
            CONFINED_KEY,
            "--values",
            str(beaconed.source),
        ],
        env=delivery.command_env(dict(os.environ), beaconed.key),
    ).stdout
    beaconed.observed["listed-after-retirement"] = beaconed.vm.ssh_succeed(
        "portablectl list --no-legend"
    )
    beaconed.observed["gone"] = _asked(
        beaconed,
        *[
            f'echo "load-{unit}=$(systemctl show -P LoadState {shlex.quote(unit)})"'
            for unit in beaconed.units_of(BEACON_KEY)
        ],
        f'echo "kept=$(portablectl is-attached'
        f' {shlex.quote(beaconed.raw(CONFINED_KEY))} 2>&1 || echo detached)"',
    )
    return beaconed


def test_an_earlier_builds_image_of_a_named_entry_is_not_an_unnamed_holding(
    retired: Run,
) -> None:
    """One fact earns one line, and it is the line that carries both identities.

    The machine holds the image the apply above attached, which is an earlier
    build of an entry the second build still names, so the holdings question
    adds nothing to what the report already says about it.
    """
    held = retired.entry(CONFINED_KEY).digest
    built = CHANGED_BUILD.entries[CONFINED_KEY].digest

    status, reported = _status(retired, CHANGED, CONFINED_KEY)

    state = _listed_state(retired, CONFINED_KEY)
    assert reported == [f"{CONFINED_KEY} image {state} holds {held}, built {built}"], reported
    assert [line for line in reported if "does not name" in line] == [], reported
    assert status == 0, reported


def test_a_retired_image_is_detached_and_its_units_are_gone(retired: Run) -> None:
    """The removal verb was the endpoint's own, and the machine holds nothing of it.

    The step names the identity the machine answered rather than any path of the
    retired holding's own artifact - that artifact is a build this run is not
    applying - and it is taken before the first value write and the first
    activation, because a holding owns the unit file names the entry replacing
    it would claim.
    """
    steps = [line for line in retired.observed["retired"].splitlines() if not line.startswith("  ")]
    dropped = _held_name(DEPLOYMENT, BEACON_KEY)
    step = f"retire {dropped} on {USER}@{retired.entry(CONFINED_KEY).address} (no state deleted)"
    answered = _pairs(retired.observed["gone"])
    name = str(_image_of(DEPLOYMENT, BEACON_KEY)["name"])
    listed = _listed_names(retired.observed["listed-after-retirement"])

    assert step in steps, steps
    assert steps.index(step) < min(
        index
        for index, line in enumerate(steps)
        if line.startswith(("value ", "copy ", "activate "))
    ), steps
    assert str(retired.artifact(BEACON_KEY)) not in retired.observed["retired"], steps
    assert [held for held in listed if held.startswith(f"{name}_")] == [], listed
    for unit in retired.units_of(BEACON_KEY):
        assert answered[f"load-{unit}"] == "not-found", answered
    assert _held_name(DEPLOYMENT, CONFINED_KEY) in listed, listed
    assert answered["kept"] != "detached", answered


@pytest.fixture(scope="session")
def probed(retired: Run) -> Run:
    """Phase 10: the build whose probe refuses, applied to the machine.

    Restricted to the probed entry, and the apply is expected to fail: this
    realiser starts the derived probe unit with the entry's own and has no
    generation to return to, so the failure is the last thing this folder
    observes and the image it attached stays attached.
    """
    if retired.observed.get("probed"):
        return retired

    applied = retired.cluster.run(
        [
            str(CLI),
            "apply",
            str(PROBED),
            "--only",
            BEACON_KEY,
            "--values",
            str(retired.source),
        ],
        env=delivery.command_env(dict(os.environ), retired.key),
        check=False,
    )
    retired.observed["probed"] = f"{applied.stdout}\n{applied.stderr}"
    retired.observed["probed-status"] = str(applied.returncode)
    return retired


def test_a_failing_probe_fails_the_attach_and_changes_nothing_else(probed: Run) -> None:
    """A probe that refuses is a failed apply step, and the image stays attached.

    This realiser has no previous generation to return to, so the probe is
    evidence and not a gate: what it buys is a failing step naming the entry,
    the machine and what the machine printed, over a machine that goes on
    running what it holds.
    """
    entry = PROBED_BUILD.entries[BEACON_KEY]
    attachment = _image_of(PROBED_BUILD, BEACON_KEY)
    units = [str(unit) for unit in attachment["units"]]
    declared = [str(unit) for unit in _image_of(DEPLOYMENT, BEACON_KEY)["units"]]
    # The derived probe unit, read as the file the probed build carries and the
    # unprobed build of the same entry does not: the name is the realiser's and
    # is not restated here.
    derived = [unit for unit in units if unit not in declared]
    logged = probed.observed["probed"]
    raw = str(manifest.artifact_of(entry) / str(attachment["image"]))
    assert len(derived) == 1, units

    answered = _pairs(
        _asked(
            probed,
            f'echo "attached=$(portablectl is-attached {shlex.quote(raw)} 2>&1 || echo detached)"',
            f'echo "result=$(systemctl show -P Result {shlex.quote(derived[0])})"',
            f'echo "status=$(systemctl show -P ExecMainStatus {shlex.quote(derived[0])})"',
            f'echo "serving=$(systemctl is-active {shlex.quote(declared[0])} || true)"',
            # The probe's own output, which `systemctl start` does not print and
            # the journal does. It is what every assertion below reports on a
            # failure: a probe unit that failed for a reason other than the
            # probe refusing would be a green test otherwise.
            f'echo "probe=$(journalctl --no-pager -o cat -u {shlex.quote(derived[0])}'
            f" | tr '\\n' '|')\"",
            f'echo "kept=$(portablectl is-attached'
            f' {shlex.quote(probed.raw(CONFINED_KEY))} 2>&1 || echo detached)"',
        )
    )

    assert probed.observed["probed-status"] != "0", logged
    assert f"activate {BEACON_KEY} (image) on {USER}@{entry.address}" in logged, logged
    assert derived[0] in logged, logged
    assert answered["result"] == "exit-code", answered
    assert answered["status"] == "1", answered
    assert answered["attached"] != "detached", answered
    assert answered["serving"] == "active", answered
    assert answered["kept"] != "detached", answered
