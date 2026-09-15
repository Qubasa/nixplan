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
import shlex
import subprocess
from collections.abc import Callable, Iterator, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Protocol

from errors import ApplyError
from manifest import ValueFile

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
# The two shapes every remote step is addressed in, stated once: a builder
# writes the destination into the position `destination` reads it back out of.
COPY = ("nix", "copy")
SSH = "ssh"
TO = "--to"
REMOTE = "ssh://"
UNNAMED = "the machine"


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

    Args:
        runner: The channel every remote step goes through.
        argv: The question, as argv.
        env: The environment it runs under.

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
def refusing(subject: str, address: str) -> Iterator[None]:
    """Report a machine's refusal of one step as the command's own refusal.

    Args:
        subject: The step being taken, as the log names it.
        address: The machine it is taken against.

    Yields:
        Nothing. The step is taken inside the context.

    Raises:
        ApplyError: If the step failed, naming the subject, the machine and
            what the machine printed. The argv is no part of the message: a
            value write carries the bytes of a secret.
    """
    try:
        yield
    except subprocess.CalledProcessError as refused:
        raise Refused(f"{subject}: {address}", refused.returncode, printed(refused)) from refused
    except ApplyError as refused:
        raise ApplyError(f"{subject}: {refused}") from refused


@contextlib.contextmanager
def taking(step: str, address: str, record: Callable[[str], None]) -> Iterator[None]:
    """Announce one step, take it, and name the failure if the machine refuses.

    Every subcommand that takes a step against a machine goes through this, so
    the last step line a run printed names the step that was running when the
    run ended, whichever subcommand took it.

    Args:
        step: The line naming the step, printed before the step is attempted.
        address: The machine it is taken against.
        record: Where a line goes.

    Yields:
        Nothing. The step is taken inside the context.

    Raises:
        ApplyError: If the machine refused, so that nothing after it is
            attempted. The failure line follows the step line.
    """
    record(step)
    try:
        with refusing(step, address):
            yield
    except ApplyError as refused:
        record(f"failed {refused}")
        raise


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

    Args:
        cmd: The argv one of this module's builders produced.

    Returns:
        The destination that builder addressed, and a name for the machine
        where the vector is neither builder's.
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

    Args:
        ssh_key: The private key `--ssh-key` named, if any.
        inherited: The `NIX_SSHOPTS` the caller set, if any.

    Returns:
        The inherited options, extended with `-i` for the key and with the
        bound on silence, appended so the caller's own value wins.
    """
    opts = shlex.split(inherited) if inherited else []
    if ssh_key is not None:
        opts += ["-i", str(ssh_key)]
    return shlex.join([*opts, *BOUNDS])


def copy_env(base: Mapping[str, str], opts: str) -> dict[str, str]:
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

    Args:
        artifact: The store path to copy.
        address: The address of the receiving machine.
        user: The login user on the receiving machine.

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

    Args:
        address: The address of the machine.
        script: The shell script to run there.
        opts: The ssh options of this invocation.
        user: The login user on the machine.

    Returns:
        The `ssh` argv: the destination is the word before the script, which is
        the position a refusal reads it back out of.
    """
    return [SSH, *shlex.split(opts), f"{user}@{address}", script]


def write_script(file: ValueFile) -> str:
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
    `chown`'s own wording, and nothing is written under it.

    Args:
        file: The value file record the plan carries.

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
        f'chown {owned} "$tmp" 2>/dev/null || {{ echo {missing} >&2; exit 1; }}; '
        f'chmod {mode} "$tmp"; '
        f'if cmp -s "$tmp" {path}; then moved=unchanged; rm -f "$tmp"; '
        f'else mv -f "$tmp" {path}; moved=changed; fi; trap - EXIT; '
        f"chmod {mode} {path}; chown {owned} {path}; "
        f'printf "%s\\n" "$moved"'
    )


def restart_script(units: Sequence[str]) -> str:
    """Return the restart of one entry's units, for units that are running.

    `try-restart` is what replaces a process holding bytes that are no longer
    current without starting one an operator stopped: whether a unit runs at all
    is the activation's answer and never this step's.

    Args:
        units: The unit file names of the entry.

    Returns:
        The shell script the machine runs, empty of any value's bytes.
    """
    return f"systemctl try-restart {' '.join(shlex.quote(unit) for unit in units)} 2>&1"


def values_script(paths: Sequence[str]) -> str:
    """Return the question of which delivered paths one machine holds.

    One question per machine rather than per file, because a machine's sshd may
    be socket activated and a burst of short logins is answered by the socket's
    own trigger limit. Nothing about the bytes of a file that is there is asked:
    a held value's contents are a secret, and reading one to report on it is not
    something this command does.

    Args:
        paths: The declared paths of the values delivered to that machine.

    Returns:
        The shell script, which prints `<path> present` or `<path> absent`.
    """
    return "; ".join(
        f"if [ -e {shlex.quote(path)} ]; "
        f'then printf "%s present\\n" {shlex.quote(path)}; '
        f'else printf "%s absent\\n" {shlex.quote(path)}; fi'
        for path in paths
    )


def activate_script(name: str, artifact: Path) -> str:
    """Return the activation of one flakelet artifact through the machine's endpoint.

    The two streams are merged because the endpoint reports what it did on
    stderr, and that report is the evidence that it used the prebuilt artifact
    and resolved nothing.

    Args:
        name: The service name the artifact declares.
        artifact: The copied artifact path.

    Returns:
        The shell script the machine runs.
    """
    return f"flakelet activate {shlex.quote(name)} {shlex.quote(str(artifact))} 2>&1"


def attach_script(artifact: Path) -> str:
    """Return the attachment of one image, which is the artifact's own script."""
    return f"{shlex.quote(str(artifact / 'bin' / 'attach'))} 2>&1"


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


def image_status_script(image: Path, check: Path) -> str:
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

    Args:
        image: The image file inside the copied artifact.
        check: The artifact's own staleness check.
    """
    return (
        f"portablectl is-attached {shlex.quote(str(image))} || true; "
        f"{shlex.quote(str(check))} 2> /dev/null || true; "
        f"printf '%s\\n' {LISTING}; portablectl list --no-legend"
    )


@dataclass(frozen=True)
class Attachment:
    """What a machine answered about one image, its files and the images it listed."""

    state: str
    listed: tuple[tuple[str, str], ...]
    configuration: tuple[tuple[str, str], ...]


def attachment_of(reported: str) -> Attachment:
    """Read one machine's answer to `image_status_script`.

    Args:
        reported: What the machine printed.

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
