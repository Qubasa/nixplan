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

import base64
import contextlib
import shlex
import subprocess
from collections.abc import Iterator, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Protocol

from errors import ApplyError

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


class Runner(Protocol):
    """The half of a command channel every remote step uses.

    ``run`` is the shape rookery's ``Cluster.run`` already has, so the machine
    layer hands its own namespace in unchanged, and ``output`` is for the steps
    whose evidence is what the machine said.
    """

    def run(self, cmd: list[str], *, env: dict[str, str] | None = None) -> object:
        """Run ``cmd`` where the deployment's addresses resolve."""
        ...

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        """Run ``cmd`` and return its standard output."""
        ...


@dataclass(frozen=True)
class Subprocess:
    """The runner an operator gets: the local process table."""

    def run(self, cmd: list[str], *, env: dict[str, str] | None = None) -> object:
        """Run ``cmd`` and report a non-zero exit as the machine's refusal."""
        return self._completed(cmd, env)

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        """Run ``cmd``, report a non-zero exit and return its standard output."""
        return self._completed(cmd, env).stdout

    def _completed(
        self, cmd: list[str], env: dict[str, str] | None
    ) -> subprocess.CompletedProcess[str]:
        try:
            return subprocess.run(cmd, env=env, check=True, capture_output=True, text=True)
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


def printed(refused: subprocess.CalledProcessError) -> str:
    """Return what a machine said when it refused a step."""
    return "\n".join(part.strip() for part in (refused.stderr, refused.stdout) if part)


def destination(cmd: Sequence[str]) -> str:
    """Return the machine an argv addresses, which is all of it a refusal names."""
    for word in cmd:
        if word.startswith("ssh://"):
            return word.removeprefix("ssh://")
        if "@" in word:
            return word
    return "the machine"


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
        The `nix copy` argv. `--no-check-sigs` is required because the artifact
        was built locally and signed by nobody.
    """
    return [
        "nix",
        "copy",
        "--to",
        f"ssh://{user}@{address}",
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
        The `ssh` argv.
    """
    return ["ssh", *shlex.split(opts), f"{user}@{address}", script]


def write_script(path: str, content: bytes) -> str:
    """Return the script that writes one generated file on a machine.

    Not `nix copy`: a store object is readable by every process on the machine,
    and the whole point of a generated secret is that its bytes are not in the
    store. The bytes travel base64-encoded because a runner runs an argv rather
    than a shell, and land at mode 0400 under a directory this script creates.

    Args:
        path: The absolute path the value entry records for the file.
        content: The bytes to write.

    Returns:
        The shell script, which writes nothing readable by anyone else.
    """
    encoded = base64.b64encode(content).decode()
    return (
        f"set -eu; umask 077; mkdir -p {shlex.quote(str(PurePosixPath(path).parent))}; "
        f"printf %s {shlex.quote(encoded)} | base64 -d > {shlex.quote(path)}; "
        f"chmod 0400 {shlex.quote(path)}"
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

    Neither the standard error nor the exit status is discarded. An endpoint
    that holds nothing under the name, one that is not on the machine's path
    and one that refuses the caller need four different things done about
    them, and a script that answered the empty list for all of them told an
    operator none of it.
    """
    return f"flakelet status --json {shlex.quote(name)}"


def image_status_script(image: Path) -> str:
    """Return what the machine's own tool says about holding one image attached."""
    return f"portablectl is-attached {shlex.quote(str(image))}"


def rollback_script(name: str) -> str:
    """Return the rollback of one entry through the machine's endpoint."""
    return f"flakelet rollback {shlex.quote(name)} 2>&1"
