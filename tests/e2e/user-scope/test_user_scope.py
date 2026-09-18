"""One real machine deployed as an account, and what the command does to it.

The folder exists for the one thing no other folder can show: a machine whose
registry record states ``scope = "user"`` is written to by a login that is not
root, so every step of the run is taken by an account. What that costs is asked
of the machine rather than assumed - the preflight question is the first step
the run takes there - and what it buys is an entry whose image is attached
through that account's own portabled and whose units run under that account's
own service manager, with the system manager running none of it.

The machine's half of that stack is provisioning and lives in
``tests/e2e/guest.nix``: the account with lingering, the three fixed roots made
writable by it, ``systemd-mountfsd`` and ``systemd-nsresourced``, polkit, the
dm-verity certificate whose private half signs this folder's image, a home the
extraction child can traverse and a store the account may add a path to. No
plan states any of them, which is why they are the image's and why every one of
them is part of every snapshot cut's key.

The phases are session-scoped and order-dependent: the apply, then what the
machine holds because of it, then a reboot issued in the guest and one apply
over what survived it.
"""

from __future__ import annotations

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

MACHINE = "alpha"
# The login every step of this run is taken as, which is the whole point of the
# folder. It is the account tests/e2e/guest.nix declares; no plan names it.
ACCOUNT = "deployer"
ADDRESS = "10.0.0.10"
ENTRY = "serve:app"
KEY = f"{ENTRY}@{MACHINE}"
VALUE = "serve:vars/served"


def _env_path(variable: str) -> Path:
    """The path a variable names, or skip the module: it needs the built layer."""
    value = os.environ.get(variable)
    if value is None:
        pytest.skip(f"{variable} is unset; run this through .#planner-e2e", allow_module_level=True)
    return Path(value)


CLI = _env_path("PLANNER_CLI")
FLAKE = _env_path("PLANNER_E2E_FLAKE")
GUEST_IMAGE = _env_path("PLANNER_E2E_GUEST_IMAGE")
SSH_KEY = delivery.ssh_key(delivery.state_root(), _env_path("PLANNER_E2E_SSH_KEY"))


def _built(target: str) -> Path:
    """Build this folder's deployment with the operator's own command.

    Raises:
        RuntimeError: If the build failed, carrying its standard error, which
            is where a refused deployment's rendered table appears.
    """
    built = subprocess.run([str(CLI), "build", target], capture_output=True, text=True, check=False)
    if built.returncode != 0:
        raise RuntimeError(f"planner build {target} failed:\n{built.stderr.strip()}")
    return Path(built.stdout.splitlines()[0])


BUILT = _built(f"{FLAKE}#planner-e2e-user-scope")
DEPLOYMENT = manifest.read(BUILT)


def _unit_record() -> dict[str, Any]:
    """The plan record of the entry's one unit, which every path is read off."""
    units = DEPLOYMENT.plan[KEY]["units"]
    assert len(units) == 1, units
    record = next(iter(units.values()))
    assert isinstance(record, dict), record
    return record


UNIT_RECORD = _unit_record()
UNIT = DEPLOYMENT.entries[KEY].units[0]
# Both derived by the module from the identity of its own entry, so they are
# read off the plan here rather than restated: the record's directory is the one
# the account's manager creates for this unit, and the file in it is the one the
# unit's own environment names.
RUNTIME_DIRECTORY = UNIT_RECORD["runtimeDirectory"][0]
RECORD_NAME = UNIT_RECORD["env"]["RECORD_NAME"]
TOKEN_PATH = UNIT_RECORD["env"]["TOKEN_FILE"]


def _value_source(root: Path, token: str) -> Path:
    """Write this run's bytes where the command reads them from, and return the directory.

    The layout is ``<dir>/<value entry key>/<file>``, and which files have to be
    there is read out of the manifest rather than restated.
    """
    source = root / "user-scope-values"
    source.mkdir(mode=0o700, exist_ok=True)
    source.chmod(0o700)
    for value in DEPLOYMENT.values.values():
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


@dataclass
class Run:
    """The machine, the built deployment and what was observed on it."""

    cluster: Any
    token: str
    source: Path
    observed: dict[str, str] = field(default_factory=dict)

    @property
    def vm(self) -> Any:
        return self.cluster.vm(MACHINE)

    def account(self, script: str) -> str:
        """Run one script as a login of the account, the way the command reaches it.

        An `ssh` of its own rather than the harness's root channel: root's
        session carries a `DBUS_SESSION_BUS_ADDRESS` of its own, so every
        `--user` tool run under `runuser` from that session dials root's bus and
        is refused. One command per case, because the guest's sshd is
        socket activated and a burst of short logins hits its trigger limit.
        """
        options = shlex.split(delivery.guest_ssh_options(SSH_KEY))
        return str(
            self.cluster.run(
                [
                    "ssh",
                    *options,
                    f"{ACCOUNT}@{ADDRESS}",
                    'export XDG_RUNTIME_DIR=/run/user/"$(id -u)"; ' + script,
                ],
                env=delivery.command_env(dict(os.environ), SSH_KEY),
            ).stdout
        )

    def applied(self, which: str = "applied") -> list[str]:
        """The step lines of one apply, in the order the steps happened."""
        return [line for line in self.observed[which].splitlines() if not line.startswith(" ")]

    def apply(self) -> str:
        """Apply this deployment as the account, and return everything it printed."""
        return str(
            self.cluster.run(
                [
                    str(CLI),
                    "apply",
                    str(BUILT),
                    "--user",
                    ACCOUNT,
                    "--values",
                    str(self.source),
                ],
                env=delivery.command_env(dict(os.environ), SSH_KEY),
            ).stdout
        )


def _answered(reported: str) -> dict[str, str]:
    """One case's `key=value` lines, as a mapping.

    Everything a case observes is echoed in that shape by the one command it
    runs, because a value spanning lines is a parse this reader cannot make.
    """
    return {
        key: said.strip()
        for key, _, said in (line.partition("=") for line in reported.splitlines())
        if key and said
    }


@delivery.cluster_stage(snapshot, image=GUEST_IMAGE, names=(MACHINE,), key=SSH_KEY)
def booted(cluster: Any) -> Iterator[Any]:
    """The stage every run starts from: one machine, up and usable.

    On a cache hit this body does not run at all - the machine is resumed from
    the cut it took the first time - so nothing here may be a fact a test reads,
    and nothing here delivers, activates or attaches anything. It waits for
    `multi-user.target` rather than for ssh, because the vsock sshd answers
    before the login `PATH` exists, and yields.
    """
    delivery.await_ready(cluster.cluster)
    yield cluster


@pytest.fixture(scope="session")
def run(booted: Any) -> Run:
    """The machine and this run's own bytes for the one value it delivers."""
    token = secrets.token_hex(16)
    return Run(
        cluster=booted.cluster,
        token=token,
        source=_value_source(delivery.state_root(), token),
    )


@pytest.fixture(scope="session")
def attached(run: Run) -> Run:
    """Phase 1: one `planner apply` made as the account and nothing else.

    It writes the value, copies the artifact and runs the artifact's own attach
    script, all over an ssh of that account: no step of it is root's. The output
    is the evidence the phase-1 cases read, so the apply happens once, here.
    """
    if not run.observed.get("applied"):
        run.observed["applied"] = run.apply()
    return run


def test_a_user_scope_apply_asks_the_machine_before_it_writes_to_it(attached: Run) -> None:
    """The preflight question is the first step the run takes against the machine.

    Every other step of this run mutates it - a value write, a copy into its
    store, an activation - and the question precedes all three, so a machine
    that was not provisioned is refused before anything of this run is on it.
    """
    steps = attached.applied()
    asked = [i for i, step in enumerate(steps) if step.startswith(f"preflight {MACHINE} ")]
    mutating = [
        i
        for i, step in enumerate(steps)
        if step.startswith(("value ", "copy ", "activate ", "retire "))
    ]
    assert len(asked) == 1, steps
    assert mutating, steps
    assert asked[0] < min(mutating), steps
    # Every step of this run is the account's, the login being in each line.
    assert all(f"{ACCOUNT}@{ADDRESS}" in steps[i] for i in mutating), steps


def test_an_entry_attaches_and_runs_under_the_accounts_own_manager(attached: Run) -> None:
    """The image the account attached is the one this build published, and it runs.

    `portablectl --user` answers about it, the unit's `RootImage` is the copy in
    the account's own pool rather than the store path the artifact carries, and
    the process the unit started is owned by the account.
    """
    answered = _answered(
        attached.account(
            "printf 'attached=%s\\n' \"$(portablectl --user is-attached "
            f'{shlex.quote(DEPLOYMENT.entries[KEY].key)} 2>&1 || echo refused)"; '
            f"printf 'active=%s\\n' \"$(systemctl --user is-active {shlex.quote(UNIT)})\"; "
            "printf 'rootimage=%s\\n' \"$(systemctl --user show -P RootImage "
            f'{shlex.quote(UNIT)})"; '
            f"printf 'owner=%s\\n' \"$(systemctl --user show -P MainPID {shlex.quote(UNIT)}"
            ' | xargs -r -I{} stat -c %U /proc/{})"; '
            "printf 'pool=%s\\n' \"${XDG_STATE_HOME:-$HOME/.local/state}/portables\""
        )
    )
    assert answered["attached"] in {"attached", "running"}, answered
    assert answered["active"] == "active", answered
    assert answered["owner"] == ACCOUNT, answered
    assert answered["rootimage"].startswith(answered["pool"] + "/"), answered
    assert answered["rootimage"].endswith(f"_{DEPLOYMENT.entries[KEY].digest}.raw"), answered


def test_the_system_manager_runs_none_of_it(attached: Run) -> None:
    """The machine's own manager knows nothing of the entry's unit.

    `systemctl is-active` exits 3 for a unit that is not running, so this is
    asked over `ssh` rather than `ssh_succeed`: the answer is the word, and the
    exit status is that word's own.
    """
    asked = attached.vm.ssh(f"systemctl is-active {shlex.quote(UNIT)}")
    assert asked.stdout.strip() in {"inactive", "unknown"}, asked.stdout
    listed = attached.vm.ssh("systemctl list-unit-files --no-legend").stdout
    assert UNIT not in listed, listed


def test_a_value_delivered_without_a_stated_ownership_is_readable_by_the_unit(
    attached: Run,
) -> None:
    """The value is the account's because the account wrote it, and the unit opens it.

    The declaration states no owner and no group - in user scope either one is
    a planner refusal - so the delivery chowns nothing and the file belongs to
    the login the run was made as. The unit runs as that same account, which is
    why it can read it, and the record it wrote under the directory its manager
    created is the proof that it did.
    """
    answered = _answered(
        attached.account(
            f"printf 'value=%s\\n' \"$(stat -c %U:%G:%a {shlex.quote(TOKEN_PATH)})\"; "
            f"printf 'read=%s\\n' \"$(cat {shlex.quote(TOKEN_PATH)})\"; "
            "printf 'record=%s\\n' \"$(cat "
            f'"$XDG_RUNTIME_DIR"/{shlex.quote(RUNTIME_DIRECTORY)}/{shlex.quote(RECORD_NAME)})"; '
            f"printf 'logged=%s\\n' \"$(journalctl --user -u {shlex.quote(UNIT)} --no-pager -o cat"
            " | sed -n 's/^token-read: //p' | tail -1)\""
        )
    )
    mode = DEPLOYMENT.values[VALUE].files[0].mode
    assert answered["value"] == f"{ACCOUNT}:{ACCOUNT}:{int(mode, 8):o}", answered
    assert answered["read"] == attached.token, answered
    assert answered["record"] == attached.token, answered
    assert answered["logged"] == attached.token, answered


@pytest.fixture(scope="session")
def rebooted(attached: Run) -> Run:
    """Phase 2: the machine rebooted from inside the guest.

    Issued in the guest rather than by a QMP reset, so the machine goes down
    the way a machine goes down. What it takes with it is `/run`: the value the
    run delivered is gone, which is the state the phase below reads.
    """
    if not attached.observed.get("rebooted"):
        attached.vm.ssh("systemctl reboot")
        delivery.await_ready(attached.cluster)
        attached.observed["rebooted"] = "yes"
    return attached


def test_a_reboot_leaves_the_lingering_manager_and_the_attachment(rebooted: Run) -> None:
    """Nobody logs in, and the account's manager and its attachment are both back.

    Lingering is what brings the manager up with no session, and the attachment
    is the account's own state rather than the machine's: the image sits in the
    account's pool and the unit files portabled wrote sit under its home, so
    both survive a reboot that emptied `/run`. The unit itself does not: the
    value it reads was in `/run`, so the manager has it loaded and stopped.
    """
    answered = _answered(
        rebooted.account(
            'printf \'linger=%s\\n\' "$(loginctl show-user "$(id -u)" --value -p Linger)"; '
            'printf \'manager=%s\\n\' "$(systemctl is-active user@"$(id -u)".service)"; '
            "printf 'attached=%s\\n' \"$(portablectl --user is-attached "
            f'{shlex.quote(DEPLOYMENT.entries[KEY].key)} 2>&1 || echo refused)"; '
            f"printf 'loaded=%s\\n' \"$(systemctl --user show -P LoadState {shlex.quote(UNIT)})\"; "
            f"printf 'active=%s\\n' \"$(systemctl --user is-active {shlex.quote(UNIT)}"
            ' || true)"; '
            f"printf 'value=%s\\n' \"$(cat {shlex.quote(TOKEN_PATH)} 2> /dev/null || echo absent)\""
        )
    )
    assert answered["linger"] == "yes", answered
    assert answered["manager"] == "active", answered
    assert answered["attached"] in {"attached", "running"}, answered
    assert answered["loaded"] == "loaded", answered
    assert answered["active"] == "inactive", answered
    assert answered["value"] == "absent", answered


@pytest.fixture(scope="session")
def reapplied(rebooted: Run) -> Run:
    """Phase 3: one apply over the machine the reboot left."""
    if not rebooted.observed.get("reapplied"):
        rebooted.observed["reapplied"] = rebooted.apply()
    return rebooted


def test_an_apply_over_a_rebooted_machine_rewrites_the_value_and_attaches_nothing(
    reapplied: Run,
) -> None:
    """The value `/run` lost is written again, and the attachment is left alone.

    The image the reboot left attached is this build's, so the script places no
    image and attaches nothing, and it starts nothing either: starting is the
    attachment's own step, taken only where this run attached, and the
    value-driven step is a `try-restart`, which is about a unit that is running
    and not about one that is down. So an entry a reboot stopped is an entry
    this run leaves stopped, and what it restores is the bytes.
    """
    said = [line.strip() for line in reapplied.observed["reapplied"].splitlines()]
    assert [line for line in said if line.startswith("placed ")] == [], said
    assert [line for line in said if line.startswith("attached ")] == [], said
    assert "nothing changed" in said, said
    steps = reapplied.applied("reapplied")
    assert [step for step in steps if step.startswith(f"value {VALUE} ")], steps
    answered = _answered(
        reapplied.account(
            f"printf 'active=%s\\n' \"$(systemctl --user is-active {shlex.quote(UNIT)}"
            ' || true)"; '
            f"printf 'value=%s\\n' \"$(cat {shlex.quote(TOKEN_PATH)})\"; "
            f"printf 'owner=%s\\n' \"$(stat -c %U:%G:%a {shlex.quote(TOKEN_PATH)})\""
        )
    )
    assert answered["active"] == "inactive", answered
    assert answered["value"] == reapplied.token, answered
    mode = DEPLOYMENT.values[VALUE].files[0].mode
    assert answered["owner"] == f"{ACCOUNT}:{ACCOUNT}:{int(mode, 8):o}", answered


def test_the_entry_runs_again_when_its_own_manager_is_asked_to_start_it(
    reapplied: Run,
) -> None:
    """The whole loop closes with no root anywhere: the account starts it again.

    Which units run at all is the account's own answer, so this is the step an
    operator takes after a reboot, and it is taken through the account's
    lingering manager over the image the account still has attached. The record
    is the unit's own answer that it read the value this run rewrote.
    """
    record = f'"$XDG_RUNTIME_DIR"/{shlex.quote(RUNTIME_DIRECTORY)}/{shlex.quote(RECORD_NAME)}'
    answered = _answered(
        reapplied.account(
            f"systemctl --user start {shlex.quote(UNIT)}; "
            # `start` returns when the process is forked and the record is the
            # first thing that process writes, so the file is waited for rather
            # than read in the same breath.
            f"for _ in $(seq 1 100); do [ -s {record} ] && break; sleep 0.1; done; "
            f"printf 'active=%s\\n' \"$(systemctl --user is-active {shlex.quote(UNIT)})\"; "
            "printf 'rootimage=%s\\n' \"$(systemctl --user show -P RootImage "
            f'{shlex.quote(UNIT)})"; '
            f"printf 'owner=%s\\n' \"$(systemctl --user show -P MainPID {shlex.quote(UNIT)}"
            ' | xargs -r -I{} stat -c %U /proc/{})"; '
            f"printf 'record=%s\\n' \"$(cat {record})\""
        )
    )
    assert answered["active"] == "active", answered
    assert answered["owner"] == ACCOUNT, answered
    assert answered["rootimage"].endswith(f"_{DEPLOYMENT.entries[KEY].digest}.raw"), answered
    assert answered["record"] == reapplied.token, answered
