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

from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import order
import remote
import values
from errors import ApplyError
from manifest import (
    Deployment,
    Value,
    ValueFile,
    address_of,
    artifact_of,
    image_file,
    machine_address,
)


@dataclass(frozen=True)
class Write:
    """One generated file, on its way to one machine of its delivery set."""

    value: Value
    file: ValueFile
    machine: str
    address: str
    content: bytes


def selection(
    deployment: Deployment, only: Sequence[str]
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Return the entries to apply and the values `--only` named, all of them for none.

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
    the first write. `reaching` is the value entries this run is answerable for,
    each with the machines of its delivery set this run writes it to.

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
            planned.append(
                Write(
                    value=value,
                    file=file,
                    machine=machine,
                    address=address,
                    content=content,
                )
            )
    return tuple(planned)


def rotations(
    deployment: Deployment, keys: Sequence[str], moved: Iterable[tuple[str, str]]
) -> tuple[tuple[str, str], ...]:
    """Return the entries to restart because a value they read moved.

    The readers are derived from `order.reads`, which is the relation the
    activation order is derived from: a read that orders an apply is a read that
    rotates a consumer, whichever of the two shapes the plan recorded it in. The
    whole entry is restarted rather than a named unit, because the plan says
    which entry reads the value and not which of its units opens the file -
    correct and coarse, never wrong.

    An entry that declares no unit is not restarted: there is nothing on the
    machine holding the bytes. `moved` is the value entry and the machine of
    every write whose bytes changed.

    Returns:
        One pair per restart, the value first, sorted, for the entries placed on
        the machine the value moved on.
    """
    index = {file.path: value.key for value in deployment.values.values() for file in value.files}
    reading = {key: _reads(deployment.plan, key, index) for key in keys}
    return tuple(
        sorted(
            (value, key)
            for value, machine in set(moved)
            for key in keys
            if deployment.entries[key].machine == machine
            and deployment.entries[key].units
            and value in reading[key]
        )
    )


def _reads(plan: Mapping[str, Any], key: str, index: Mapping[str, str]) -> frozenset[str]:
    """Return the value entries one placed entry's resolved reads name.

    A secret export resolves to the reference record of the generated file that
    backs it, so the value a read names is the value the path it carries belongs
    to. A public export carries bytes rather than a path, and those bytes are
    part of the plan, so a move in them moves the artifact and is the
    activation's business rather than this step's. `index` is every declared file
    path of the deployment, to its value entry.

    Returns:
        The value entry keys, empty for an entry reading no generated file.

    Raises:
        ApplyError: If a read is recorded in a shape the command does not
            recognise, which the order refused before this step was reached.
    """
    return frozenset(
        index[path] for read in order.reads(plan, key) for path in read.paths if path in index
    )


@dataclass(frozen=True)
class Nobody:
    """The channel of a run asked what it would do: it dials nothing.

    Every refusal this command makes is made from the plan, the deployment record
    and the value source, which is before the first dial, so a dry run is the same
    walk over a channel that takes no step and answers nothing. The steps it prints
    are therefore the steps a real run prints, and what is missing from its output
    is what a machine would have said.

    The walk is the walk either way, so a value write hands this channel the
    bytes it would have sent and this channel sends nothing: the payload is a
    parameter of a step and never a decision the walk takes.
    """

    def run(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> object:
        """Take no step."""
        return None

    def output(
        self, cmd: list[str], *, env: dict[str, str] | None = None, stdin: bytes | None = None
    ) -> str:
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
    log: Callable[[str], None] = remote.ignore,
) -> tuple[str, ...]:
    """Apply a built deployment, in the order the plan implies.

    `only` restricts the run and applies the whole deployment where it names
    nothing, and `dry_run` prints the steps rather than taking them.

    Returns:
        The step lines, in the order the steps happened, each handed to `log`
        as it happened.

    Raises:
        ApplyError: For any refusal, all of which happen before the first dial.
    """
    channel = Nobody() if dry_run else runner
    refuse_inapplicable(deployment)
    keys, named = selection(deployment, only)
    reached = values.reaching(deployment, (deployment.entries[key].machine for key in keys), named)
    values.check(deployment, source, reached)
    planned = writes(deployment, source, reached)
    walked = order.walk(deployment.plan, keys)
    withheld = order.unsatisfied(deployment.plan, keys, deployment.entries)
    # An entry that declares no unit is realised into nothing, which the planner
    # accepts: there is no artifact to copy and no unit to activate, so the run
    # takes no step against its machine and refuses nothing on its account.
    taken = tuple(key for key in walked.order if deployment.entries[key].path is not None)
    scripts = {key: remote.activation(deployment.entries[key]) for key in taken}
    addresses = {key: address_of(deployment.entries[key]) for key in taken}
    # The record every image artifact carries is read here, where nothing has been
    # dialled: an artifact the build wrote wrongly refuses the whole run rather
    # than failing one machine half way through it.
    for key in taken:
        if deployment.entries[key].realiser == "image":
            image_file(deployment.entries[key])

    opts, env = remote.channel(base_env, ssh_key)
    lines, record = remote.recording(log)

    for cycle in walked.cycles:
        record(f"cycle of {', '.join(cycle)}")

    for provider, consumer in walked.broken:
        record(f"ordered against the read of {provider} by {consumer}")

    for consumer, provider in withheld:
        record(f"not applying {provider}, which {consumer} reads")

    def take(step: str, address: str, script: str, *, stdin: bytes | None = None) -> str:
        argv = remote.ssh_argv(address, script, opts=opts, user=user)
        return remote.taken(channel, step, address, argv, env=env, record=record, stdin=stdin)

    moved: set[tuple[str, str]] = set()
    for write in planned:
        step = (
            f"value {write.value.key} {write.file.name} -> {user}@{write.address}:{write.file.path}"
            f" ({write.file.owner}:{write.file.group} {write.file.mode})"
        )
        answered = take(step, write.address, remote.write_script(write.file), stdin=write.content)
        if "changed" in answered.split():
            moved.add((write.value.key, write.machine))

    for key in taken:
        entry = deployment.entries[key]
        address = addresses[key]
        artifact = artifact_of(entry)
        with remote.taking(f"copy {key} {artifact} -> {user}@{address}", address, record):
            channel.run(remote.copy_argv(artifact, address, user=user), env=env)
        take(f"activate {key} ({entry.realiser}) on {user}@{address}", address, scripts[key])

    # Last, and after every activation: a unit the activation has just started is
    # holding the bytes this run wrote, and a unit it did not start is one this
    # step leaves stopped.
    for value, key in rotations(deployment, taken, moved):
        entry = deployment.entries[key]
        address = addresses[key]
        step = f"restart {key} for {value} on {entry.machine} at {user}@{address}"
        take(step, address, remote.restart_script(entry.units))
    return tuple(lines)
