"""What the command runs on a machine, and the single seam it runs through.

Every remote step is an argv handed to a runner, so a caller that wants to
observe the order and the argv substitutes a recorder for the runner and nothing
else about the command changes. The default runner is `subprocess`.

ssh options are a parameter rather than a policy of the command. A delivery into
a throwaway guest needs `-F /dev/null`: the copy runs inside a single-uid user
namespace, where a config file owned by real root appears owned by `nobody`, and
ssh then refuses to read it at all, reporting `Bad owner or permissions on
/nix/store/...-libvirt/etc/ssh/ssh_config.d/30-libvirt-ssh-proxy.conf` and
failing to connect. It also needs the host-key options a guest generated per run
has no known-hosts entry for. Both are properties of that guest rather than of
an operator, so the command extends the `NIX_SSHOPTS` its caller set: a real
operator's ssh config is then what configures a real operator's ssh.

What the command adds of its own is `-i` for `--ssh-key` and the bound on
silence: no question asked of a terminal, a connection given up on, and a
connection that stopped carrying bytes ended. Work is not bounded, because a
first `nix copy` onto a fresh machine legitimately runs for minutes. All of it
is appended, because ssh takes the first value it is given for an option, so a
caller who states one keeps it.
"""

from __future__ import annotations

import contextlib
import json
import os
import shlex
import subprocess
from collections.abc import Callable, Iterator, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Protocol

from errors import ApplyError
from manifest import (
    SYSTEM,
    USER,
    Entry,
    Realiser,
    ValueFile,
    artifact_of,
    image_file,
    service_name,
)

BOUNDS = (
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "ServerAliveInterval=30",
    "-o",
    "ServerAliveCountMax=3",
)
UNREACHABLE = 255
MISSING = (126, 127)
LISTING = "images"
CONFIGURATION = "config"
# The marker the question of what a machine holds prints per realiser, and the
# fields each realiser publishes what its own holdings are named by under.
HELD = "holdings"
FLAKELET = "flakelet"
IMAGE = "image"
URL_PREFIX = "urlPrefix"
SEPARATOR = "separator"
ALPHABET = "digestAlphabet"
LENGTH = "digestLength"
DETACHED = "detached"
RAW = ".raw"
# The two shapes every remote step is addressed in, stated once: a builder
# writes the destination into the position `destination` reads it back out of.
COPY = ("nix", "copy")
SSH = "ssh"
TO = "--to"
REMOTE = "ssh://"
UNNAMED = "the machine"
# The fixed roots, which do not move with the scope: the values root is
# `lib/util.nix`'s `varsRoot`, the staging root is the one `image/read.nix`
# stages an entry's files under, and the sealed root is where a machine keeps a
# value across a reboot. A user-scope machine is provisioned once, as root, so
# that the deploying account can write all three.
VALUES_ROOT = "/run/vars"
SEALED_ROOT = "/var/lib/planner/sealed"
STAGING_ROOT = "/run/portable-planner"
MOUNTFSD = "systemd-mountfsd.socket"
NSRESOURCED = "systemd-nsresourced.socket"
NAMESPACES = "/proc/sys/user/max_user_namespaces"
CLONE = "/proc/sys/kernel/unprivileged_userns_clone"
OK = "ok"
# The machine-scoped unit the deployment build publishes per sealing machine,
# and where each scope's manager reads a unit file it was given. The name is
# one hyphen wide, which is outside the namespace a realiser can derive a unit
# file name in, so installing it can never replace an entry's own unit.
#
# Each directory is its root and the segments below it, so every component can
# be created at its mode rather than at the umask of whatever login the run
# made, which is the rule the image realiser's attach script states for the
# same reason. One spelling per scope and never a path chosen by testing what a
# machine currently permits: this deploys as an account and never as a mode.
#
# `/usr/local/lib/systemd/system` and not `/etc/systemd/system`, which is where
# `systemctl enable` writes: on a machine whose `/etc` its own image manages
# that path is a link into a read-only store, and a guest answered
# `ln: failed to create symbolic link '/etc/systemd/system/planner-unseal.service':
# Read-only file system`. `/run/systemd/system` is writable everywhere and
# disqualified by the very thing this unit exists for: a reboot empties it, so
# the unsealer would be gone exactly when a machine needs it. The FHS directory
# for a locally installed unit is in systemd's own system unit search path, on
# a stock system as much as on that guest.
UNSEAL_UNIT = "planner-unseal.service"
SYSTEM_UNITS = ("'/usr'", ("local", "lib", "systemd", "system"))
# Already shell words, and deliberately so: the account's own unit directory is
# under a home only the machine knows, so `$HOME` is what names it and a quoted
# whole would name a directory called `$HOME`.
USER_UNITS = ('"$HOME"', (".config", "systemd", "user"))
# The target whose `.wants` directory is what starts the unit at boot, per
# scope, matching the `[Install]` section the build wrote into the unit file.
SYSTEM_WANTED = "multi-user.target"
USER_WANTED = "default.target"
# The marker the per-machine value question prints before the machine's own
# trial of its sealed copies, and what it prints instead where the machine
# holds no unsealer to ask. The words a trial answers with are the artifact's:
# a copy that opens, one that is not there, and one the machine cannot open.
SEALS = "seals"
UNCHECKED = "unchecked"
OPENS = "opens"
MISSING_COPY = "absent"
# A non-interactive login has no session, so every step that addresses the
# account's own manager states where its bus is rather than hoping a login
# shell set it.
BUS = "export XDG_RUNTIME_DIR=/run/user/$(id -u); "


class Runner(Protocol):
    """The half of a command channel every remote step uses.

    ``run`` is the shape rookery's ``Cluster.run`` has for a step that sends no
    payload, so the machine layer hands its own namespace in unchanged, and
    ``output`` is for the steps whose evidence is what the machine said.

    A step that carries bytes carries them as ``stdin``: the argv of every step
    is a function of the plan, so an observer of the channel - a process table,
    a recorder - is handed the path and never the value.
    """

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        """Run ``cmd`` where the deployment's addresses resolve."""
        ...

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        """Run ``cmd`` and return its standard output."""
        ...


@dataclass(frozen=True)
class Subprocess:
    """The runner an operator gets: the local process table."""

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        """Run ``cmd`` and report a non-zero exit as the machine's refusal."""
        return self._completed(cmd, env, stdin)

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
        """Run ``cmd``, report a non-zero exit and return its standard output."""
        return decoded(self._completed(cmd, env, stdin).stdout)

    # Bytes in and text out: a payload is a secret's own bytes, which no encoding
    # of text can carry, and what a machine printed is decoded at one place.
    def _completed(
        self, cmd: list[str], env: dict[str, str] | None, stdin: bytes | None
    ) -> subprocess.CompletedProcess[bytes]:
        try:
            return subprocess.run(cmd, env=env, input=stdin, check=True, capture_output=True)
        except subprocess.CalledProcessError as refused:
            raise Refused(destination(cmd), refused.returncode, printed(refused)) from refused


class Refused(ApplyError):
    """A machine refused a step: how it exited, and what it printed."""

    def __init__(self, address: str, status: int, said: str) -> None:
        told = f": {said}" if said else ""
        super().__init__(f"{address} refused the step, exiting {status}{told}")
        self.status = status
        self.said = said


@dataclass(frozen=True)
class Answer:
    """What one machine said to one question, and how the question exited."""

    status: int
    said: str


def asking(runner: Runner, argv: list[str], *, env: dict[str, str]) -> Answer:
    """Ask a machine one question and answer with what came back, however it exited.

    Returns:
        The exit status and what the machine printed. A question is asked
        rather than taken as a step, so a machine that refuses it is an answer
        to read rather than a refusal to raise: the four things that can have
        happened are told apart by the status.
    """
    try:
        return Answer(0, runner.output(argv, env=env))
    except Refused as refused:
        return Answer(refused.status, refused.said)
    except subprocess.CalledProcessError as refused:
        return Answer(refused.returncode, printed(refused))


@contextlib.contextmanager
def taking(step: str, address: str, record: Callable[[str], None]) -> Iterator[None]:
    """Announce one step, take it, and name the failure if the machine refuses.

    Every subcommand that takes a step against a machine goes through this, so
    the last step line a run printed names the step that was running when the
    run ended, whichever subcommand took it. The step is announced before it is
    attempted.

    Raises:
        ApplyError: If the machine refused, naming the step, the machine and
            what the machine printed, so that nothing after the step is
            attempted. The failure line follows the step line, and the argv is
            no part of either: a value write carries the bytes of a secret.
    """
    record(step)
    try:
        yield
    except subprocess.CalledProcessError as exited:
        refused = Refused(f"{step}: {address}", exited.returncode, printed(exited))
        record(f"failed {refused}")
        raise refused from exited
    except ApplyError as failed:
        named = ApplyError(f"{step}: {failed}")
        record(f"failed {named}")
        raise named from failed


def taken(
    runner: Runner,
    step: str,
    address: str,
    argv: list[str],
    *,
    env: dict[str, str],
    record: Callable[[str], None],
    stdin: bytes | None = None,
) -> str:
    """Announce one step, take it, and echo what the machine said underneath it.

    Each line the machine printed is recorded under the step line and indented
    by two spaces, which is what an operator reads under an activation, so
    every subcommand echoes a machine the same way.

    Raises:
        ApplyError: If the machine refused, so that nothing after it is
            attempted.
    """
    with taking(step, address, record):
        answered = runner.output(argv, env=env, stdin=stdin)
    for line in answered.splitlines():
        record(f"  {line}")
    return answered


def ignore(line: str) -> None:
    """Drop a step line, for a caller that reads the returned log instead."""


def recording(log: Callable[[str], None]) -> tuple[list[str], Callable[[str], None]]:
    """Return the lines one run collects, and the recorder that appends and logs one."""
    lines: list[str] = []

    def record(line: str) -> None:
        lines.append(line)
        log(line)

    return lines, record


def decoded(said: object) -> str:
    """Return what a machine printed as text, whatever bytes it printed.

    A step runs in binary mode because a payload is arbitrary bytes, so a
    machine's answer is decoded here and nowhere else. A byte the locale cannot
    decode is replaced rather than raised on: what a refusal is for is naming
    the step and the machine, and a decoder that raised would report neither.
    """
    if isinstance(said, bytes):
        return said.decode(errors="replace")
    return said if isinstance(said, str) else ""


def printed(refused: subprocess.CalledProcessError) -> str:
    """Return what a machine said when it refused a step."""
    return "\n".join(
        said.strip() for said in (decoded(refused.stderr), decoded(refused.stdout)) if said
    )


def destination(cmd: Sequence[str]) -> str:
    """Return the machine an argv addresses, which is all of it a refusal names.

    The destination is read off the position the command itself placed it in:
    the word after `--to` for a copy, and the word before the script for an ssh
    step. Never off a scan for a word that looks like one - the caller's own
    connection options are in the same vector and an option's value may spell
    anything, `-o Ciphers=aes256-gcm@openssh.com` being an ordinary one, so a
    scan reports whichever word happens to look like a destination.

    Returns:
        The destination the builder of that argv addressed, and a name for the
        machine where the vector is neither builder's.
    """
    words = list(cmd)
    if tuple(words[: len(COPY)]) == COPY and TO in words:
        at = words.index(TO) + 1
        return words[at].removeprefix(REMOTE) if at < len(words) else UNNAMED
    if words[:1] == [SSH] and len(words) >= 3:
        return words[-2]
    return UNNAMED


def ssh_opts(ssh_key: Path | None, *, inherited: str | None = None) -> str:
    """Return the ssh options every step of one invocation uses.

    Returns:
        The `NIX_SSHOPTS` the caller set, extended with `-i` for the key
        `--ssh-key` named and with the bound on silence, appended so the
        caller's own value wins.
    """
    opts = shlex.split(inherited) if inherited else []
    if ssh_key is not None:
        opts += ["-i", str(ssh_key)]
    return shlex.join([*opts, *BOUNDS])


def channel(base_env: Mapping[str, str] | None, ssh_key: Path | None) -> tuple[str, dict[str, str]]:
    """Return the ssh options of one run and the environment its steps run under.

    The environment is the caller's own, the process's own where it named none,
    with those options in `NIX_SSHOPTS`.
    """
    base = os.environ if base_env is None else base_env
    opts = ssh_opts(ssh_key, inherited=base.get("NIX_SSHOPTS"))
    return opts, _copy_env(base, opts)


def _copy_env(base: Mapping[str, str], opts: str) -> dict[str, str]:
    """Return the environment a `nix copy` runs under.

    `nix copy` reaches the machine over ssh and takes its options from the
    environment, and it needs the rest of the caller's own environment for its
    `PATH`, its `HOME` and its daemon socket.
    """
    env = dict(base)
    env["NIX_SSHOPTS"] = opts
    return env


def copy_argv(artifact: Path, address: str, *, user: str = "root") -> list[str]:
    """Return the store-to-store copy of one artifact, as argv.

    Returns:
        The `nix copy` argv, with the destination in the position a refusal
        reads it back out of. `--no-check-sigs` is required because the
        artifact was built locally and signed by nobody.
    """
    return [
        *COPY,
        TO,
        f"{REMOTE}{user}@{address}",
        "--no-check-sigs",
        str(artifact),
    ]


def ssh_argv(address: str, script: str, *, opts: str, user: str = "root") -> list[str]:
    """Return one remote script, as argv.

    Returns:
        The `ssh` argv: the destination is the word before the script, which is
        the position a refusal reads it back out of.
    """
    return [SSH, *shlex.split(opts), f"{user}@{address}", script]


def write_script(file: ValueFile, *, scope: str = SYSTEM) -> str:
    """Return the script that writes one generated file on a machine.

    Not `nix copy`: a store object is readable by every process on the machine,
    and the whole point of a generated secret is that its bytes are not in the
    store. The bytes arrive on the step's own input, so this script is a
    function of the record alone: the argv it goes out in carries the path, the
    mode and the ownership, and nothing read out of a value source.

    The temporary is created `0600 root` before its first byte, so the bytes are
    never at the login's umask; ownership is set next and the recorded mode last,
    so the file is at no instant readable by anyone the record does not admit.
    The mode cannot be applied first: a record without an owner write bit would
    then refuse the write it was created for.

    The write goes to a temporary beside the destination and is moved into place
    under a trap, so an interrupted run leaves the previous file or none, and
    never a fragment and never a stray temporary.

    The temporary is compared against the file the machine already holds and
    moved only where they differ, and the script says `changed` or `unchanged`.
    The comparison is made where both halves already exist, by the process that
    is about to write the bytes, and neither the bytes nor a digest of them is
    printed: what is reported is that the file moved, never what it moved to.

    Ownership and mode are set again after the move, on every apply rather than
    only where the bytes moved, so a mode widened on the machine is restored by
    the next one.

    An account the machine does not have is named as such rather than left to
    `chown`'s own wording, and nothing is written under it. In user scope there
    is no `chown` at all: the account owns what it writes, a record delivered
    there states no ownership of its own - one that did is
    `value-ownership-in-user-scope` and the deployment never reaches a machine -
    and an account chowning a file to the owner it already has is refused by the
    kernel. The mode is the account's to set, so it is set in both scopes.

    Returns:
        The shell script, which writes nothing readable by anyone the record
        does not admit.
    """
    path = shlex.quote(file.path)
    owned = shlex.quote(f"{file.owner}:{file.group}")
    mode = shlex.quote(file.mode)
    missing = shlex.quote(f"this machine has no account {file.owner}:{file.group} for {file.path}")
    parent = shlex.quote(str(PurePosixPath(file.path).parent))
    return (
        f"set -eu; umask 077; "
        # A file the record opens to an account is unreachable behind a directory
        # only root may traverse, so every directory of the chain is `0711`:
        # traversable by any, listable by none, and each file's own mode still
        # decides its bytes. `umask 066` is what `mkdir -p` gives the ancestors
        # it creates; the leaf is set again so an older apply's `0700` is fixed.
        f"(umask 066; mkdir -p {parent}); chmod 0711 {parent}; "
        f"tmp={path}.planner; trap 'rm -f \"$tmp\"' EXIT; "
        f'install -m 0600 /dev/null "$tmp"; '
        f'cat > "$tmp"; '
        f"{_owning(owned, missing, scope)}"
        f'chmod {mode} "$tmp"; '
        f'if cmp -s "$tmp" {path}; then moved=unchanged; rm -f "$tmp"; '
        f'else mv -f "$tmp" {path}; moved=changed; fi; trap - EXIT; '
        f"chmod {mode} {path}; {_own(owned, path, scope)}"
        f'printf "%s\\n" "$moved"'
    )


def _owning(owned: str, missing: str, scope: str) -> str:
    """Return the ownership of the temporary, which is root's step and not the account's."""
    if scope == USER:
        return ""
    return f'chown {owned} "$tmp" 2>/dev/null || {{ echo {missing} >&2; exit 1; }}; '


def _own(owned: str, path: str, scope: str) -> str:
    """Return the ownership restated on the file itself, in the scope that can state it."""
    return "" if scope == USER else f"chown {owned} {path}; "


def restart_script(units: Sequence[str], *, scope: str = SYSTEM) -> str:
    """Return the restart of one entry's units, for units that are running.

    `try-restart` is what replaces a process holding bytes that are no longer
    current without starting one an operator stopped: whether a unit runs at all
    is the activation's answer and never this step's.

    Returns:
        The shell script the machine runs, empty of any value's bytes,
        addressing the account's own manager in user scope.
    """
    units_of = " ".join(shlex.quote(unit) for unit in units)
    return _addressed(f"{_manager(scope)} try-restart {units_of} 2>&1", scope)


def seal_script(file: ValueFile, *, scope: str = SYSTEM) -> str:
    """Return the script that writes one value's sealed copy on a machine.

    The ciphertext arrives on the step's own input, exactly as the plaintext
    does, so this script is a function of the record alone and the argv it goes
    out in carries the sealed path and nothing read out of a value source. The
    bytes were sealed where the plaintext already was, by the process that read
    the source.

    The copy is `0400` under a `0700` chain whatever the record says about the
    plaintext: it is ciphertext, its one reader is the unsealing step, which
    runs as the account that owns the machine's identity file, and a
    traversable chain here would publish the value file names of every entry on
    the machine for no gain. In user scope there is no `chown`, the account
    owning what it writes.

    Nothing is compared and no `changed` is printed: two sealings of one file
    differ, so a comparison of seals says nothing and the copy is written on
    every apply. Whether a value's bytes moved stays the plaintext's answer.

    Returns:
        The shell script, which prints `sealed` when the copy is in place.
    """
    path = shlex.quote(file.sealed)
    parent = shlex.quote(str(PurePosixPath(file.sealed).parent))
    owned = shlex.quote("root:root")
    missing = shlex.quote(f"this machine has no account root for {file.sealed}")
    return (
        f"set -eu; umask 077; "
        f"mkdir -p {parent}; chmod 0700 {parent}; "
        f"tmp={path}.planner; trap 'rm -f \"$tmp\"' EXIT; "
        f'install -m 0600 /dev/null "$tmp"; '
        f'cat > "$tmp"; '
        f"{_owning(owned, missing, scope)}"
        f'chmod 0400 "$tmp"; mv -f "$tmp" {path}; trap - EXIT; '
        f'printf "%s\\n" sealed'
    )


def _unit_components(scope: str) -> tuple[str, ...]:
    """Return the manager's unit directory and every component above its root.

    Returns:
        One shell word per component, outermost first, the last of which is the
        directory itself. Each is named so the install creates it at its mode
        rather than leaving a component it made for itself at the run's umask.
    """
    root, segments = USER_UNITS if scope == USER else SYSTEM_UNITS
    components: list[str] = []
    at = root
    for segment in segments:
        at = f"{at}/{segment}"
        components.append(at)
    return tuple(components)


def unsealer_script(artifact: Path, *, scope: str = SYSTEM) -> str:
    """Return the install of one machine's unsealing unit, in the manager its scope names.

    The unit is linked out of the artifact the copy already put on the machine,
    so the file the manager reads is the file the build published and nothing
    is assembled here. What makes the manager run it at boot is a link in the
    `.wants` directory of the target the unit's own `[Install]` names, written
    beside it in the same directory rather than through `systemctl enable`,
    which writes into `/etc` - a directory that is a link into a read-only
    store on a machine whose image manages it.

    Both links are compared before anything is written, so a machine that
    already holds this build's unit is told nothing and says `unchanged`. The
    comparison is the links themselves and not `systemctl is-enabled`, whose
    answer is about the configuration directories this deliberately does not
    write; the link is the fact that starts the unit.

    Returns:
        The shell script, which prints `changed` or `unchanged`.
    """
    manager = _manager(scope)
    components = _unit_components(scope)
    wanted = USER_WANTED if scope == USER else SYSTEM_WANTED
    wants = f"{components[-1]}/{wanted}.wants"
    published = shlex.quote(str(artifact / UNSEAL_UNIT))
    made = "".join(f"install -d -m 0755 {each}; " for each in (*components, wants))
    return _addressed(
        f"set -eu; at={components[-1]}/{shlex.quote(UNSEAL_UNIT)}; "
        f"want={wants}/{shlex.quote(UNSEAL_UNIT)}; "
        f'if [ "$(readlink "$at" 2>/dev/null || true)" = {published} ] && '
        f'[ "$(readlink "$want" 2>/dev/null || true)" = {published} ]; '
        f'then printf "%s\\n" unchanged; '
        f'else {made}ln -sfn {published} "$at"; ln -sfn {published} "$want"; '
        f'{manager} daemon-reload; printf "%s\\n" changed; fi',
        scope,
    )


def values_script(paths: Sequence[str], *, check: Path | None = None) -> str:
    """Return the question of which delivered paths one machine holds.

    One question per machine rather than per file, because a machine's sshd may
    be socket activated and a burst of short logins is answered by the socket's
    own trigger limit. Nothing about the bytes of a file that is there is asked:
    a held value's contents are a secret, and reading one to report on it is not
    something this command does.

    `check` is the machine's own unsealer's trial, asked in the same login for
    the same reason and answering for every sealed copy of that machine at
    once. A machine that holds no unsealer has nothing to ask, which is its own
    answer and not an absence of copies.

    Returns:
        The shell script, which prints `<path> present` or `<path> absent` per
        delivered path and, where a trial was named, the `SEALS` marker and
        then either that trial's own lines or `UNCHECKED`.
    """
    asked = "; ".join(
        f"if [ -e {shlex.quote(path)} ]; "
        f'then printf "%s present\\n" {shlex.quote(path)}; '
        f'else printf "%s absent\\n" {shlex.quote(path)}; fi'
        for path in paths
    )
    if check is None:
        return asked
    trial = shlex.quote(str(check))
    return (
        f'{asked}; printf "%s\\n" {SEALS}; '
        # `|| true`, because the trial is a question and the presence of a
        # value is the answer this question's own exit status is about: a
        # trial that broke must not read as a machine that could not be asked.
        f"if [ -x {trial} ]; then {trial} 2> /dev/null || true; "
        f'else printf "%s\\n" {UNCHECKED}; fi'
    )


@dataclass(frozen=True)
class Requirement:
    """One fact a user-scope run rests on: how it is asked, and what it states."""

    key: str
    statement: str
    question: str
    missing: str


PORTABLED = Requirement(
    key="user-portabled",
    statement="the account's own portabled answers, which an image entry attaches through",
    question="portablectl --user list > /dev/null 2>&1",
    missing="the account's portabled answered nothing",
)

# The other fact only an attach needs, and the one whose absence is otherwise
# unreadable: portabled extracts an image's metadata in a child that has joined
# the user namespace systemd-nsresourced delegated, in which the account's own
# uid is not mapped, so that child holds a foreign uid and owns none of the
# account's directories. It opens the image's own path `O_PATH|O_DIRECTORY`
# while asking whether it is the root directory (portable.c's
# `chaseat_prefix_root` -> `path_is_root_at`), and a home that uid cannot
# traverse answers EACCES, which portabled reports as `AttachImage failed:
# Access denied` naming nothing. The question is about traversal by another uid
# and not about a mode, so every mode that grants it answers `ok`, and it walks
# to the root because one closed directory anywhere above the pool is the same
# refusal. The pool itself is the attach script's to create traversable.
TRAVERSABLE = Requirement(
    key="home-traversable",
    statement=(
        "the account's home and every directory above it are traversable by a uid that owns "
        "none of them, which the extraction of an image the account attaches is done as"
    ),
    question=(
        '(d="$HOME"; while :; do m="$(stat -Lc %a "$d" 2>/dev/null)" || exit 1; '
        '[ $((0$m & 1)) -eq 1 ] || exit 1; [ "$d" = / ] && exit 0; d="$(dirname "$d")"; done)'
    ),
    missing="a directory at or above the account's home is traversable by its owner alone",
)


def preflight(*, portabled: bool) -> tuple[Requirement, ...]:
    """Return the facts one user-scope machine is verified to hold before it is written to.

    Provisioning is root's work done once per machine, so each of these is
    verified rather than assumed, and each stays a question a local installer
    could ask of the machine it is running on. `portabled` states whether an
    image entry is placed on the machine, which is what makes the account's own
    portabled and a traversable home facts this run rests on: a value write
    needs neither.

    Returns:
        The requirements, in the order they are asked and reported.
    """
    roots = (
        (VALUES_ROOT, "values-root", "the values root"),
        (SEALED_ROOT, "sealed-root", "the sealed root"),
        (STAGING_ROOT, "staging-root", "the image staging root"),
    )
    return (
        *(
            Requirement(
                key=key,
                statement=f"{what} {root} is writable by the account",
                question=f"[ -d {shlex.quote(root)} ] && [ -w {shlex.quote(root)} ]",
                missing="it is not a directory the account can write",
            )
            for root, key, what in roots
        ),
        Requirement(
            key="lingering",
            statement="lingering keeps the account's manager alive across logins",
            question='[ "$(loginctl show-user "$(id -u)" --value -p Linger 2>/dev/null)" = yes ]',
            missing="loginctl reports no lingering for the account",
        ),
        Requirement(
            key="user-manager",
            statement="the account's own service manager answers",
            question="systemctl --user show -p Version --value > /dev/null 2>&1",
            missing="the account's manager answered nothing",
        ),
        *((PORTABLED, TRAVERSABLE) if portabled else ()),
        *(
            Requirement(
                key=unit.removeprefix("systemd-").removesuffix(".socket"),
                statement=f"{unit} is live, which an unprivileged mount delegates to",
                question=f"systemctl is-active --quiet {shlex.quote(unit)} 2>/dev/null",
                missing="the machine's manager reports it is not active",
            )
            for unit in (MOUNTFSD, NSRESOURCED)
        ),
        Requirement(
            key="user-namespaces",
            statement="the kernel permits an unprivileged user namespace",
            question=(
                f'[ "$(cat {shlex.quote(NAMESPACES)} 2>/dev/null || echo 0)" -gt 0 ] && '
                f'[ "$(cat {shlex.quote(CLONE)} 2>/dev/null || echo 1)" = 1 ]'
            ),
            missing="the kernel's own knobs refuse one",
        ),
    )


def preflight_script(requirements: Sequence[Requirement]) -> str:
    """Return the one question a user-scope machine is asked before it is written to.

    One question per machine rather than one per fact, for the reason the values
    question is one: a machine's sshd may be socket activated and a burst of
    short logins is answered by the socket's own trigger limit. The account's
    bus is stated once, ahead of every fact, because a non-interactive login
    has no session and the user-bus facts are asked in the same shell.

    Returns:
        The shell script, which prints `<key>=ok` or `<key>=<what it found>`
        for each requirement, whatever any of them answers.
    """
    return BUS + "; ".join(
        f"if {requirement.question}; "
        f"then printf '%s=%s\\n' {shlex.quote(requirement.key)} {shlex.quote(OK)}; "
        f"else printf '%s=%s\\n' {shlex.quote(requirement.key)} {shlex.quote(requirement.missing)}"
        f"; fi"
        for requirement in requirements
    )


def preflight_answer(reported: str) -> dict[str, str]:
    """Return what one machine answered the preflight question, by requirement key."""
    return {
        key: said.strip()
        for key, _, said in (line.partition("=") for line in reported.splitlines())
        if key and said
    }


def verify(machine: str, requirements: Sequence[Requirement], reported: str) -> None:
    """Refuse a machine that answered that a verified fact does not hold.

    The refusal is the command's own and not a diagnostics row: the plan holds
    no fact about what a machine currently permits, so the answer is read where
    it was asked. Every fact that failed is named, because an operator
    provisioning a machine wants the list rather than the first line of it.

    Raises:
        ApplyError: Naming the machine, each requirement that does not hold
            and what the machine answered about it, so that nothing after the
            question is attempted there.
    """
    said = preflight_answer(reported)
    failed = [
        f"{requirement.statement}, and the machine answered "
        f"{said.get(requirement.key) or 'nothing'}"
        for requirement in requirements
        if said.get(requirement.key) != OK
    ]
    if failed:
        raise ApplyError(
            f"{machine} is a user-scope machine this run cannot write to: {'; '.join(failed)}"
        )


def activate_script(name: str, artifact: Path) -> str:
    """Return the activation of one flakelet artifact through the machine's endpoint.

    The two streams are merged because the endpoint reports what it did on
    stderr, and that report is the evidence that it used the prebuilt artifact
    and resolved nothing.
    """
    return f"flakelet activate {shlex.quote(name)} {shlex.quote(str(artifact))} 2>&1"


def attach_script(artifact: Path, *, scope: str = SYSTEM) -> str:
    """Return the attachment of one image, which is the artifact's own script.

    The script takes no decision from the operator - its own scope is the
    artifact's - so what a user-scope step adds is where the account's bus is.
    """
    return _addressed(f"{shlex.quote(str(artifact / 'bin' / 'attach'))} 2>&1", scope)


def flakelet_status_script(name: str) -> str:
    """Return the endpoint's own report for one entry.

    Neither the standard error nor the exit status is discarded, because the
    status is what tells the four situations apart. The endpoint refuses a name
    it holds nothing under with its own non-zero status, which is an answer
    about the deployment; a shell that cannot run the endpoint at all exits
    `MISSING`, which is an answer about the machine; ssh exits `UNREACHABLE`
    when nothing answered. A script ending in `|| printf '[]'` reported all
    three as the first.
    """
    return f"flakelet status --json {shlex.quote(name)}"


def image_status_script(image: Path, check: Path, *, scope: str = SYSTEM) -> str:
    """Return what the machine's own tool says about one image and what it holds.

    Three facts, one question: the state of the image the caller names, the
    bytes the machine holds at each path the entry is shown a configuration file
    at, and the images the machine holds, whose names carry the identity of the
    build each came from. A machine that was never given this image answers
    nothing about it, which is why that half may fail and the exit status is the
    listing's: a machine carrying no tool exits `MISSING` and a machine whose
    service manager answers nothing exits non-zero, and both are answers about
    the machine rather than about the entry.

    The bytes are answered by the artifact's own check script, so the recipe a
    report compares against is the recipe an attach writes. It may be absent on
    a machine that was never given the artifact, which is the same fact as the
    image being absent and is not a second refusal.

    In user scope the tool asked is the account's own portabled, which holds
    what that account attached and nothing the system holds.
    """
    portable = _portable(scope)
    return _addressed(
        f"{portable} is-attached {shlex.quote(str(image))} || true; "
        f"{shlex.quote(str(check))} 2> /dev/null || true; "
        f"printf '%s\\n' {LISTING}; {portable} list --no-legend",
        scope,
    )


@dataclass(frozen=True)
class Attachment:
    """What a machine answered about one image, its files and the images it listed."""

    state: str
    listed: tuple[tuple[str, str], ...]
    configuration: tuple[tuple[str, str], ...]


def attachment_of(reported: str) -> Attachment:
    """Read one machine's answer to `image_status_script`.

    Returns:
        The word the tool printed for the image it was asked about, empty
        where it printed none, each configuration path with the word the
        artifact's check gave it, and each listed image with the state the
        listing gives it. A row the listing writes differently from the tool
        this was written against is dropped rather than guessed at, so an
        answer this cannot read carries no image and the caller reports what
        the machine said instead of a comparison.
    """
    lines = reported.splitlines()
    mark = lines.index(LISTING) if LISTING in lines else len(lines)
    head = [line for line in lines[:mark] if line.strip()]
    files = tuple(
        (columns[1], columns[2])
        for columns in (line.split() for line in head)
        if len(columns) == 3 and columns[0] == CONFIGURATION
    )
    said = [line for line in head if not line.startswith(f"{CONFIGURATION} ")]
    rows = tuple(
        (columns[0], columns[-1])
        for columns in (line.split() for line in lines[mark + 1 :])
        if len(columns) > 1
    )
    return Attachment(
        state=said[0].strip() if said else "",
        listed=rows,
        configuration=files,
    )


def rollback_script(name: str) -> str:
    """Return the rollback of one entry through the machine's endpoint."""
    return f"flakelet rollback {shlex.quote(name)} 2>&1"


def flakelet_remove_script(name: str) -> str:
    """Return the endpoint's own removal of one entry it registers.

    Never `--purge`: `remove` stops the units, unlinks them, deletes the
    endpoint's own bookkeeping and keeps and lists the state folders, and what
    it lists is what the step line echoes. Emptying those folders is a decision
    this command does not take.
    """
    return f"flakelet remove {shlex.quote(name)} 2>&1"


def image_detach_script(name: str, *, scope: str = SYSTEM) -> str:
    """Return the detachment of one image a machine listed, by the name it listed.

    `--now` stops the units before the unlink, so the step needs no unit list of
    its own and cannot stop the wrong ones, and the name resolves in the search
    paths the attachment put the image in. In user scope the daemon addressed is
    the account's own, because an attachment of it is invisible to the system's.
    """
    return _addressed(f"{_portable(scope)} detach --now {shlex.quote(name)} 2>&1", scope)


@dataclass(frozen=True)
class Holding:
    """One thing a machine answered that it holds, attributed to this planner.

    ``identity`` is the machine's own answer about what it is, and is what a
    line naming it carries: the plan key for a flakelet holding, whose endpoint
    reports back the identity the realiser wrote, and the listed image name for
    an image one, which the build's own projection is not invertible from.
    ``name`` is what the endpoint's own removal verb resolves, which for
    flakelet is the name it registered rather than the identity. ``state`` is
    the word the answer carries about it, empty where it carries none. The
    record carries no sentence of its own: the line a report and an applying
    run both print is made in the one renderer both of them call.
    """

    realiser: str
    identity: str
    name: str
    state: str


def holdings_script(realisers: Sequence[Realiser], *, scope: str = SYSTEM) -> str:
    """Return the one question of what a machine holds, over the published table.

    A realiser joins the question only where the scopes published for it admit
    the machine's scope, and the image half is addressed to the account's own
    daemon where that scope is the account's. One question per machine and not
    one per realiser or per holding, for the reason `values_script` and
    `image_status_script` fold theirs: a socket-activated sshd answers a burst
    of short logins with the socket's own trigger limit.

    Returns:
        The shell script, which prints `holdings <realiser> <status>` and then
        that realiser's own answer, per realiser. Empty where no published
        realiser reaches the machine, which is a machine to ask nothing.
    """
    asked = [
        f"held=$({REALISERS[realiser.name].asks(scope)} 2>/dev/null); "
        f"printf '%s %s %s\\n' {HELD} {shlex.quote(realiser.name)} \"$?\"; "
        f"printf '%s\\n' \"$held\""
        for realiser in realisers
        if realiser.name in REALISERS and scope in realiser.scopes
    ]
    return _addressed("; ".join(asked), scope) if asked else ""


def holdings_of(machine: str, realisers: Sequence[Realiser], reported: str) -> tuple[Holding, ...]:
    """Read one machine's answer to `holdings_script` into what it holds.

    A section whose status says the realiser's own tool is not on the machine
    carries no holding and is no refusal: a machine with no `portablectl` holds
    no attached image. Any other non-zero status is an answer the command
    cannot read.

    Returns:
        Every holding the answer carries that the published table attributes to
        this planner, in the order the machine answered them. An answer of
        nothing - a machine that was not asked, or a channel that took no step
        - carries none.

    Raises:
        ApplyError: If the answer is not the one the question printed, or a
            section exited non-zero for a reason other than a missing tool,
            naming the machine and what it said.
    """
    published = {realiser.name: realiser for realiser in realisers}
    held: list[Holding] = []
    for name, status, said in _sections(machine, reported, published):
        if status in MISSING:
            continue
        if status != 0:
            raise ApplyError(
                f"{machine} answered the question of what it holds with {name} exiting "
                f"{status}: {said.strip() or 'nothing'}"
            )
        held.extend(REALISERS[name].holds(machine, published[name], said))
    return tuple(held)


def unnamed(
    held: Sequence[Holding], realisers: Sequence[Realiser], entries: Mapping[str, Entry]
) -> tuple[Holding, ...]:
    """Return the holdings the build names no entry for.

    A holding is named where the deployment places an entry that owns it at all,
    whichever entries a run was restricted to: a restriction bounds the machines
    asked and decides nothing about what counts as unnamed.
    """
    published = {realiser.name: realiser for realiser in realisers}
    return tuple(
        holding
        for holding in held
        if not REALISERS[holding.realiser].claims(
            published[holding.realiser], entries, holding.identity
        )
    )


def retirement(holding: Holding, *, scope: str = SYSTEM) -> str:
    """Return the step that retires one holding: its endpoint's own removal verb.

    Never a script out of the holding's own artifact: that artifact belongs to a
    build this run is not applying, so the run cannot name its path and nothing
    on the machine roots it.
    """
    return REALISERS[holding.realiser].retire(holding, scope)


def _sections(
    machine: str, reported: str, published: Mapping[str, Realiser]
) -> tuple[tuple[str, int, str], ...]:
    """Return each section of one holdings answer: its realiser, status and answer."""
    sections: list[tuple[str, int, list[str]]] = []
    for line in reported.splitlines():
        columns = line.split()
        if columns[:1] == [HELD]:
            sections.append((*_marker(machine, reported, columns, published), []))
        elif sections:
            sections[-1][2].append(line)
        elif line.strip():
            raise _unreadable(machine, reported)
    return tuple((name, status, "\n".join(lines)) for name, status, lines in sections)


def _marker(
    machine: str, reported: str, columns: Sequence[str], published: Mapping[str, Realiser]
) -> tuple[str, int]:
    """Return the realiser and the status one marker line carries."""
    if len(columns) != 3 or columns[1] not in published or columns[1] not in REALISERS:
        raise _unreadable(machine, reported)
    try:
        return columns[1], int(columns[2])
    except ValueError as malformed:
        raise _unreadable(machine, reported) from malformed


def _unreadable(machine: str, reported: str) -> ApplyError:
    return ApplyError(
        f"{machine} answered the question of what it holds with {reported.strip()!r}, which is "
        f"not the answer the question prints"
    )


def _registrations(machine: str, said: str) -> list[Mapping[str, Any]]:
    """Return the entries a flakelet endpoint's own status answered with."""
    if not said.strip():
        return []
    try:
        answered = json.loads(said)
    except json.JSONDecodeError as malformed:
        raise ApplyError(
            f"{machine} answered the question of what it holds with {said.strip()!r}, which is "
            f"not its endpoint's JSON status"
        ) from malformed
    if not isinstance(answered, list):
        raise ApplyError(
            f"{machine} answered the question of what it holds with {said.strip()!r}, which is "
            f"not the list of registered entries its status is"
        )
    return [record for record in answered if isinstance(record, dict)]


def _flakelet_holdings(machine: str, realiser: Realiser, said: str) -> tuple[Holding, ...]:
    """Return the entries a flakelet endpoint registers that this planner put there.

    The identity the realiser wrote into the artifact is what the endpoint
    reports back, so a registration whose identity carries the published prefix
    came from a deployment this command applies and what follows the prefix is
    the plan key of the entry it was built for. Anything else the endpoint holds
    is the machine's own business and is read as nothing.
    """
    prefix = realiser.text(URL_PREFIX)
    held = []
    for record in _registrations(machine, said):
        url = record.get("locked_url")
        name = record.get("name")
        if not isinstance(url, str) or not url.startswith(prefix):
            continue
        state = record.get("state")
        if url[len(prefix) :] and isinstance(name, str) and name:
            held.append(
                Holding(
                    realiser=FLAKELET,
                    identity=url[len(prefix) :],
                    name=name,
                    state=state if isinstance(state, str) else "",
                )
            )
    return tuple(held)


def _image_holdings(machine: str, realiser: Realiser, said: str) -> tuple[Holding, ...]:
    """Return the images a machine lists whose names this planner composes.

    An image's own answer is a file name, so attribution is the shape of that
    name: it splits at the published separator into a name and a digest of the
    published length over the published alphabet. No plan key is derived from
    it, the projection a name is built by not being injective, and a detached
    row is an image the machine does not hold.
    """
    separator = realiser.text(SEPARATOR)
    alphabet = set(realiser.text(ALPHABET))
    length = realiser.number(LENGTH)
    held = []
    for columns in (line.split() for line in said.splitlines()):
        if len(columns) < 2 or columns[-1] == DETACHED:
            continue
        name, found, digest = columns[0].rpartition(separator)
        if name and found and len(digest) == length and set(digest) <= alphabet:
            held.append(
                Holding(realiser=IMAGE, identity=columns[0], name=columns[0], state=columns[-1])
            )
    return tuple(held)


def _flakelet_claims(realiser: Realiser, entries: Mapping[str, Entry], identity: str) -> bool:
    """Whether the build places the flakelet entry one identity is the plan key of."""
    entry = entries.get(identity)
    return entry is not None and entry.realiser == FLAKELET


def _image_claims(realiser: Realiser, entries: Mapping[str, Entry], identity: str) -> bool:
    """Whether the build places an image entry whose own image carries this name.

    The digest is deliberately not compared: an image of an earlier build of an
    entry the build still names is a machine holding another build's identity,
    which the report already answers, and one fact earns one line.
    """
    separator = realiser.text(SEPARATOR)
    held = identity.rpartition(separator)[0]
    return any(
        entry.realiser == IMAGE
        and entry.path is not None
        and image_file(entry).removesuffix(RAW).rpartition(separator)[0] == held
        for entry in entries.values()
    )


@dataclass(frozen=True)
class Steps:
    """What one realiser answers: how an entry of it is activated and asked about, how a
    machine's own answer about what it holds of that realiser is read, and how one is retired.
    """

    activate: Callable[[Entry, str], str]
    ask: Callable[[Entry, str], str]
    asks: Callable[[str], str]
    holds: Callable[[str, Realiser, str], tuple[Holding, ...]]
    claims: Callable[[Realiser, Mapping[str, Entry], str], bool]
    retire: Callable[[Holding, str], str]


def _image_status(entry: Entry, scope: str) -> str:
    artifact = artifact_of(entry)
    return image_status_script(
        artifact / image_file(entry), artifact / "bin" / "check", scope=scope
    )


REALISERS: Mapping[str, Steps] = {
    FLAKELET: Steps(
        activate=lambda entry, scope: activate_script(service_name(entry), artifact_of(entry)),
        ask=lambda entry, scope: flakelet_status_script(service_name(entry)),
        asks=lambda scope: "flakelet status --json",
        holds=_flakelet_holdings,
        claims=_flakelet_claims,
        retire=lambda holding, scope: flakelet_remove_script(holding.name),
    ),
    IMAGE: Steps(
        activate=lambda entry, scope: attach_script(artifact_of(entry), scope=scope),
        ask=_image_status,
        asks=lambda scope: f"{_portable(scope)} list --no-legend",
        holds=_image_holdings,
        claims=_image_claims,
        retire=lambda holding, scope: image_detach_script(holding.name, scope=scope),
    ),
}


def activation(entry: Entry, *, scope: str = SYSTEM) -> str:
    """Return the script that activates one entry on its machine, in its own scope.

    Raises:
        ApplyError: If the entry states a realiser this command cannot
            activate.
    """
    return _realiser(entry, "and the command activates flakelet and image").activate(entry, scope)


def status_script(entry: Entry, *, scope: str = SYSTEM) -> str:
    """Return the question one entry's machine is asked about it, in the entry's own scope.

    Raises:
        ApplyError: If the entry states a realiser this command cannot ask
            about.
    """
    return _realiser(entry, "which the command cannot ask").ask(entry, scope)


def _realiser(entry: Entry, cannot: str) -> Steps:
    """Return the realiser one entry states, or refuse in the caller's own words."""
    stated = REALISERS.get(entry.realiser)
    if stated is None:
        raise ApplyError(f"{entry.key} states realiser {entry.realiser}, {cannot}")
    return stated


def _manager(scope: str) -> str:
    """Return the service manager one scope's steps address."""
    return "systemctl --user" if scope == USER else "systemctl"


def _portable(scope: str) -> str:
    """Return the portable-image tool one scope's steps address."""
    return "portablectl --user" if scope == USER else "portablectl"


def _addressed(script: str, scope: str) -> str:
    """Return one script with the account's own bus stated, where the scope is the account's."""
    return f"{BUS}{script}" if scope == USER else script
