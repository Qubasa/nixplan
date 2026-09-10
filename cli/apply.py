"""The steps `apply` takes, in the order it takes them.

Everything a refusal can be made of - the plan, the manifest and the value
source - is read and refused before the first machine is dialled, so a run that
has started is a run whose remaining failures are a machine's.

Then every generated value is written, because a unit whose environment names a
value's path reads it as soon as it is activated, and only then is any entry
activated. Per entry the artifact is copied first and activated second: an
activation that had to resolve anything would be activating something other than
what was built.
"""

from __future__ import annotations

import os
import subprocess
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import order
import remote
import values
from errors import ApplyError
from manifest import (
    Deployment,
    Entry,
    Value,
    ValueFile,
    address_of,
    artifact_of,
    image_file,
    machine_address,
    service_name,
)


@dataclass(frozen=True)
class Write:
    """One generated file, on its way to one machine of its delivery set."""

    value: Value
    file: ValueFile
    address: str
    content: bytes


def selection(
    deployment: Deployment, only: Sequence[str]
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Return the placed entries to apply and the value entries `--only` named.

    Args:
        deployment: The deployment being applied.
        only: The keys the caller restricted the run to, empty for all of them.

    Returns:
        The placed entry keys, sorted, and the value keys named directly.

    Raises:
        ApplyError: If a named key is neither an entry nor a value of the
            deployment, naming the key given and the keys it carries.
    """
    if not only:
        return tuple(sorted(deployment.entries)), ()
    entries: set[str] = set()
    named: set[str] = set()
    for key in only:
        if key in deployment.entries:
            entries.add(key)
        elif key in deployment.values:
            named.add(key)
        else:
            carried = sorted([*deployment.entries, *deployment.values])
            raise ApplyError(
                f"--only names {key}, which the deployment carries as neither an entry nor a "
                f"value: it carries {', '.join(carried)}"
            )
    return tuple(sorted(entries)), tuple(sorted(named))


def refuse_inapplicable(deployment: Deployment) -> None:
    """Refuse a deployment whose diagnostics carry an error row.

    Args:
        deployment: The deployment being applied.

    Raises:
        ApplyError: If any row is an error, with the diagnostics as the planner
            rendered them as the message.
    """
    if not deployment.errors:
        return
    raise ApplyError(f"{deployment.root} is not applicable:\n{deployment.rendered}")


def writes(
    deployment: Deployment, source: Path | None, reaching: Mapping[str, tuple[str, ...]]
) -> tuple[Write, ...]:
    """Return every generated file this run writes, and where it goes.

    Every address is resolved and every file is read here, so a source or a plan
    that cannot answer is refused before a machine is dialled rather than after
    the first write.

    Args:
        deployment: The deployment being applied.
        source: The value source, or ``None`` when the operator named none.
        reaching: The value entries this run is answerable for, each with the
            machines of its delivery set this run writes it to.

    Returns:
        The writes, by value entry, then delivery-set order, then file name.

    Raises:
        ApplyError: If a machine written to has no address, or a declared file
            cannot be read from the source.
    """
    planned: list[Write] = []
    for value, file in values.required(deployment, reaching):
        if source is None:
            raise ApplyError(f"{value.key} declares {file.name} and no value source was named")
        content = values.bytes_of(source, value, file)
        for machine in reaching[value.key]:
            address = machine_address(deployment, machine, of=value.key)
            planned.append(Write(value=value, file=file, address=address, content=content))
    return tuple(planned)


def activation(entry: Entry) -> str:
    """Return the script that activates one entry on its machine.

    Args:
        entry: The placed entry.

    Returns:
        The shell script the machine runs: the endpoint's own activation for a
        flakelet artifact, the artifact's own attach script for an image.

    Raises:
        ApplyError: If the entry states a realiser this command cannot activate.
    """
    if entry.realiser == "flakelet":
        return remote.activate_script(service_name(entry), artifact_of(entry))
    if entry.realiser == "image":
        return remote.attach_script(artifact_of(entry))
    raise ApplyError(
        f"{entry.key} states realiser {entry.realiser}, and the command activates "
        f"flakelet and image"
    )


def holds_attached(
    runner: remote.Runner,
    entry: Entry,
    address: str,
    *,
    image: str,
    opts: str,
    user: str,
    env: dict[str, str],
) -> bool:
    """Return whether the machine already holds one image entry attached.

    The attach script runs under `set -eu` and `portablectl` refuses an image
    it already holds, so a second run over an attached entry would fail on a
    machine that is in the intended state.

    Args:
        runner: The channel every remote step goes through.
        entry: The placed entry, realised as an image.
        address: The machine's address.
        image: The image the artifact carries, resolved before the first dial.
        opts: The ssh options of this invocation.
        user: The login user on the machine.
        env: The environment a remote step runs under.

    Returns:
        Whether the machine answered with an attachment. A machine that could
        not answer is one the attachment is attempted on: a question that
        failed is no evidence that the image is there, and the artifact's own
        script is what decides.
    """
    script = remote.image_status_script(artifact_of(entry) / image)
    try:
        answered = runner.output(remote.ssh_argv(address, script, opts=opts, user=user), env=env)
    except (ApplyError, subprocess.CalledProcessError):
        return False
    return remote.attachment_of(answered).state not in ("", "detached")


def _ignore(line: str) -> None:
    """Drop a step line, for a caller that reads the returned log instead."""


@dataclass(frozen=True)
class Nobody:
    """The channel of a run asked what it would do: it dials nothing.

    Every refusal this command makes is made from the plan, the deployment record
    and the value source, which is before the first dial, so a dry run is the same
    walk over a channel that takes no step and answers nothing. The steps it prints
    are therefore the steps a real run prints, and what is missing from its output
    is what a machine would have said.
    """

    def run(self, cmd: list[str], *, env: dict[str, str] | None = None) -> object:
        """Take no step."""
        return None

    def output(self, cmd: list[str], *, env: dict[str, str] | None = None) -> str:
        """Answer nothing, which is what a machine that was not asked said."""
        return ""


def apply(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    source: Path | None = None,
    only: Sequence[str] = (),
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    dry_run: bool = False,
    log: Callable[[str], None] = _ignore,
) -> tuple[str, ...]:
    """Apply a built deployment, in the order the plan implies.

    Args:
        deployment: The deployment to apply.
        runner: The channel every remote step goes through.
        source: The value source `--values` named, if any.
        only: The keys to restrict the run to, empty for the whole deployment.
        ssh_key: The private key `--ssh-key` named, if any.
        user: The login user on every machine.
        base_env: The environment a `nix copy` inherits, the process's own by
            default.
        dry_run: Whether to print the steps rather than take them.
        log: Called with each step line as that step happens.

    Returns:
        The step lines, in the order the steps happened.

    Raises:
        ApplyError: For any refusal, all of which happen before the first dial.
    """
    environment = os.environ if base_env is None else base_env
    channel = Nobody() if dry_run else runner
    refuse_inapplicable(deployment)
    keys, named = selection(deployment, only)
    reached = values.reaching(deployment, (deployment.entries[key].machine for key in keys), named)
    values.check(deployment, source, reached)
    planned = writes(deployment, source, reached)
    walked = order.walk(deployment.plan, keys)
    # An entry that declares no unit is realised into nothing, which the planner
    # accepts: there is no artifact to copy and no unit to activate, so the run
    # takes no step against its machine and refuses nothing on its account.
    taken = tuple(key for key in walked.order if deployment.entries[key].path is not None)
    scripts = {key: activation(deployment.entries[key]) for key in taken}
    addresses = {key: address_of(deployment.entries[key]) for key in taken}
    images = {
        key: image_file(deployment.entries[key])
        for key in taken
        if deployment.entries[key].realiser == "image"
    }

    opts = remote.ssh_opts(ssh_key, inherited=environment.get("NIX_SSHOPTS"))
    env = remote.copy_env(environment, opts)
    lines: list[str] = []

    def record(line: str) -> None:
        lines.append(line)
        log(line)

    for provider, consumer in walked.broken:
        record(f"ordered against the read of {provider} by {consumer}")

    for write in planned:
        step = (
            f"value {write.value.key} {write.file.name} -> {user}@{write.address}:{write.file.path}"
        )
        with remote.taking(step, write.address, record):
            channel.run(
                remote.ssh_argv(
                    write.address,
                    remote.write_script(write.file.path, write.content),
                    opts=opts,
                    user=user,
                ),
                env=env,
            )

    for key in taken:
        entry = deployment.entries[key]
        address = addresses[key]
        artifact = artifact_of(entry)
        with remote.taking(f"copy {key} {artifact} -> {user}@{address}", address, record):
            channel.run(remote.copy_argv(artifact, address, user=user), env=env)
        if entry.realiser == "image" and holds_attached(
            channel, entry, address, image=images[key], opts=opts, user=user, env=env
        ):
            record(f"attached {key} already on {user}@{address}")
            continue
        step = f"activate {key} ({entry.realiser}) on {user}@{address}"
        with remote.taking(step, address, record):
            reported = channel.output(
                remote.ssh_argv(address, scripts[key], opts=opts, user=user), env=env
            )
        for line in reported.splitlines():
            record(f"  {line}")
    return tuple(lines)
