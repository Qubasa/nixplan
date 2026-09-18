"""The steps `apply` takes, in the order it takes them.

Everything a refusal can be made of - the plan, the manifest and the value
source - is read and refused before the first machine is dialled, so a run that
has started is a run whose remaining failures are a machine's.

Every machine of the selection is then asked what it holds, before anything is
written anywhere, so a run that cannot read one answer has changed nothing: what
the build names no entry for is announced beside the order's own lines, and a
run asked to retire takes it away with the endpoint's own removal verb before
the first write, because a holding owns host resources - a port, a unit file
name, a host path - that the entry replacing a renamed one claims. A retirement
deletes no state.

Every machine this run seals a value to is then given its unsealer and has the
unit installed, before the first value of that machine is written, so a run
interrupted half way leaves a machine that can open whatever it already holds.

Then every generated value is written, because a unit whose environment names a
value's path reads it as soon as it is activated, and only then is any entry
activated. A value of a sealing machine is written twice: the sealed copy first,
on a step of its own, and the plaintext second at the path and the record it
always had. Per entry the artifact is copied first and activated second: an
activation that had to resolve anything would be activating something other than
what was built.
"""

from __future__ import annotations

import os
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import order
import remote
import values
from errors import ApplyError
from manifest import (
    USER,
    Deployment,
    Machine,
    Value,
    ValueFile,
    address_of,
    artifact_of,
    entry_scope,
    image_file,
    machine_address,
    machine_of,
    machine_recipient,
    machine_scope,
)


@dataclass(frozen=True)
class Write:
    """One generated file, on its way to one machine of its delivery set.

    ``sealed`` is the same bytes sealed to the recipient that machine's plan
    record declares, absent for a machine whose copies are not sealed. It is
    made here, in the process that read the value source, because the seal is
    made where the plaintext already is.
    """

    value: Value
    file: ValueFile
    machine: str
    address: str
    content: bytes
    sealed: bytes | None


@dataclass(frozen=True)
class Preflight:
    """One user-scope machine this run verifies, and the facts it verifies there."""

    machine: str
    address: str
    requirements: tuple[remote.Requirement, ...]


def preflights(
    deployment: Deployment,
    taken: Sequence[str],
    planned: Sequence[Write],
    addresses: Mapping[str, str],
) -> tuple[Preflight, ...]:
    """Return the machines this run verifies before it mutates anything on them.

    A machine is asked exactly where its scope is `user`. Root is the account
    every one of these facts holds for, so a system-scope machine is asked
    nothing new, and the account's own portabled is verified only where an
    image entry attaches through it.

    Returns:
        One question per user-scope machine this run touches, whether it
        touches it with a value write or with an entry, in machine order.
    """
    reached: dict[str, str] = {}
    for write in planned:
        reached.setdefault(write.machine, write.address)
    for key in taken:
        reached.setdefault(deployment.entries[key].machine, addresses[key])
    attaching = {
        deployment.entries[key].machine
        for key in taken
        if deployment.entries[key].realiser == "image"
    }
    return tuple(
        Preflight(
            machine=machine,
            address=address,
            requirements=remote.preflight(portabled=machine in attaching),
        )
        for machine, address in sorted(reached.items())
        if machine_scope(deployment, machine) == USER
    )


def announcements(walked: order.WalkResult, withheld: Sequence[tuple[str, str]]) -> tuple[str, ...]:
    """Return what a run says about the order it walks before it takes a step.

    Returns:
        One line per cycle, then per edge the order contradicted, then per read
        whose provider this run is not applying.
    """
    return (
        *(f"cycle of {', '.join(cycle)}" for cycle in walked.cycles),
        *(
            f"ordered against the read of {provider} by {consumer}"
            for provider, consumer in walked.broken
        ),
        *(f"not applying {provider}, which {consumer} reads" for consumer, provider in withheld),
    )


@dataclass(frozen=True)
class Held:
    """What one machine of a run answered it holds that the build names no entry for."""

    machine: str
    address: str
    scope: str
    holdings: tuple[remote.Holding, ...]


def holdings(
    deployment: Deployment,
    channel: remote.Runner,
    reached: Mapping[str, str],
    *,
    opts: str,
    user: str,
    env: dict[str, str],
) -> tuple[Held, ...]:
    """Ask every machine of the selection what it holds, before anything is written.

    Every machine is asked before the first write, so a run that cannot read one
    machine's answer has changed nothing anywhere when it refuses. The question
    goes through the channel, so a run asked what it would do asks nothing and
    names no holding: what a machine currently holds is what the reporting
    command answers.

    A machine that answered nothing at all is unreachable rather than
    unreadable, and it is left alone here: no holding is claimed for it and the
    run continues, so its unreachability surfaces at the first step taken
    against it, which is the step a broken run's last line has to name.

    `reached` is the machines this run takes a step against, by address.

    Returns:
        One record per machine holding something the build names no entry for,
        in machine order.

    Raises:
        ApplyError: If a machine answered the question with something the
            command cannot read, naming the machine and what it said.
    """
    realisers = tuple(deployment.realisers.values())
    asked: list[Held] = []
    for machine, address in sorted(reached.items()):
        scope = machine_scope(deployment, machine)
        question = remote.holdings_script(realisers, scope=scope)
        if not question:
            continue
        argv = remote.ssh_argv(address, question, opts=opts, user=user)
        answer = remote.asking(channel, argv, env=env)
        if answer.status == remote.UNREACHABLE:
            continue
        if answer.status != 0:
            raise ApplyError(
                f"{machine} at {address} did not answer the question of what it holds, exiting "
                f"{answer.status}: {answer.said.strip() or 'nothing'}"
            )
        held = remote.unnamed(
            remote.holdings_of(machine, realisers, answer.said), realisers, deployment.entries
        )
        if held:
            asked.append(Held(machine=machine, address=address, scope=scope, holdings=held))
    return tuple(asked)


def holding_lines(asked: Sequence[Held], *, retire: bool) -> tuple[str, ...]:
    """Return what a run announces about what its machines hold that the build does not.

    Returns:
        One line per holding, in the shape the report's own line has, with what
        a run that was not asked to retire did about it appended.
    """
    kept = "" if retire else "; not retired"
    return tuple(
        f"{holding.sentence(held.machine)}{kept}" for held in asked for holding in held.holdings
    )


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
    deployment: Deployment,
    source: Path | None,
    reaching: Mapping[str, tuple[str, ...]],
    *,
    sealing: str | None = None,
) -> tuple[Write, ...]:
    """Return every generated file this run writes, and where it goes.

    Every address is resolved, every file is read and every sealed copy is
    made here, so a source, a plan or a sealing program that cannot answer is
    refused before a machine is dialled rather than after the first write.
    `reaching` is the value entries this run is answerable for, each with the
    machines of its delivery set this run writes it to, and `sealing` is the
    program the run seals with, which a run with nothing to seal has none of.

    Returns:
        The writes, by value entry, then delivery-set order, then file name.

    Raises:
        ApplyError: If a machine written to has no address, if a declared file
            cannot be read from the source, if a machine whose copies are
            sealed states no recipient, or if the sealing program refuses.
    """
    planned: list[Write] = []
    for value, file in values.required(deployment, reaching):
        if source is None:
            raise ApplyError(f"{value.key} declares {file.name} and no value source was named")
        content = values.bytes_of(source, value, file)
        for machine in reaching[value.key]:
            address = machine_address(deployment, machine, of=value.key)
            sealed = None
            if sealing is not None and machine_of(deployment, machine, of=value.key).sealed:
                recipient = machine_recipient(deployment, machine, of=f"{value.key} {file.name}")
                sealed = values.sealed(sealing, recipient, content)
            planned.append(
                Write(
                    value=value,
                    file=file,
                    machine=machine,
                    address=address,
                    content=content,
                    sealed=sealed,
                )
            )
    return tuple(planned)


@dataclass(frozen=True)
class Unsealer:
    """One machine's unsealer, on its way to the machine before its first value."""

    machine: str
    address: str
    scope: str
    artifact: Path


def unsealers(deployment: Deployment, planned: Sequence[Write]) -> tuple[Unsealer, ...]:
    """Return the unsealers this run installs, one per machine it seals a value to.

    Exactly the machines this run writes a value to whose record says their
    values are sealed, so a restricted run contacts no machine it would not
    otherwise contact and a run that writes no value installs nothing.

    Returns:
        One record per such machine, in machine order.
    """
    reached: dict[str, str] = {}
    for write in planned:
        reached.setdefault(write.machine, write.address)
    sealing: list[Unsealer] = []
    for machine, address in sorted(reached.items()):
        stated: Machine = machine_of(deployment, machine, of=f"the values of {machine}")
        if not stated.sealed or stated.path is None:
            continue
        sealing.append(
            Unsealer(
                machine=machine,
                address=address,
                scope=machine_scope(deployment, machine),
                artifact=stated.path,
            )
        )
    return tuple(sealing)


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
    retire: bool = False,
    log: Callable[[str], None] = remote.ignore,
) -> tuple[str, ...]:
    """Apply a built deployment, in the order the plan implies.

    `only` restricts the run and applies the whole deployment where it names
    nothing, `dry_run` prints the steps rather than taking them, and `retire`
    removes what the machines hold that the build names no entry for, which
    deletes no state.

    Returns:
        The step lines, in the order the steps happened, each handed to `log`
        as it happened.

    Raises:
        ApplyError: For any refusal. Every one of them but the answer about
            what a machine holds is made before the first dial, and that one is
            made before anything is written anywhere.
    """
    channel = Nobody() if dry_run else runner
    refuse_inapplicable(deployment)
    keys, named = selection(deployment, only)
    reached = values.reaching(deployment, (deployment.entries[key].machine for key in keys), named)
    values.check(deployment, source, reached)
    # Before the first dial: a run whose record says a machine's copies are
    # sealed and whose invocation names no program that can seal them refuses
    # here rather than after the values of the machines before it were written.
    invocation = dict(os.environ if base_env is None else base_env)
    sealing = values.sealer(values.sealing(deployment, reached), invocation.get(values.SEALING))
    planned = writes(deployment, source, reached, sealing=sealing)
    walked = order.walk(deployment.plan, keys)
    withheld = order.unsatisfied(deployment.plan, keys, deployment.entries)
    # An entry that declares no unit is realised into nothing, which the planner
    # accepts: there is no artifact to copy and no unit to activate, so the run
    # takes no step against its machine and refuses nothing on its account.
    taken = tuple(key for key in walked.order if deployment.entries[key].path is not None)
    scopes = {key: entry_scope(deployment, deployment.entries[key]) for key in taken}
    scripts = {key: remote.activation(deployment.entries[key], scope=scopes[key]) for key in taken}
    addresses = {key: address_of(deployment.entries[key]) for key in taken}
    # The record every image artifact carries is read here, where nothing has been
    # dialled: an artifact the build wrote wrongly refuses the whole run rather
    # than failing one machine half way through it.
    for key in taken:
        if deployment.entries[key].realiser == "image":
            image_file(deployment.entries[key])

    opts, env = remote.channel(invocation, ssh_key)
    lines, record = remote.recording(log)

    asked = holdings(
        deployment,
        channel,
        {deployment.entries[key].machine: addresses[key] for key in taken},
        opts=opts,
        user=user,
        env=env,
    )

    for line in (*announcements(walked, withheld), *holding_lines(asked, retire=retire)):
        record(line)

    def take(step: str, address: str, script: str, *, stdin: bytes | None = None) -> str:
        argv = remote.ssh_argv(address, script, opts=opts, user=user)
        return remote.taken(channel, step, address, argv, env=env, record=record, stdin=stdin)

    for question in preflights(deployment, taken, planned, addresses):
        step = f"preflight {question.machine} at {user}@{question.address}"
        answered = take(step, question.address, remote.preflight_script(question.requirements))
        # A dry run asked nothing, so there is nothing it could have been told.
        if not dry_run:
            remote.verify(question.machine, question.requirements, answered)

    # Before the first value write, the first copy and the first activation: a
    # holding owns host resources of the machine - a port, a unit file name, a
    # host path - and the entry that replaces a renamed one claims the same
    # ones, so the only order in which a rename can start is this one.
    if retire:
        for held in asked:
            for holding in held.holdings:
                step = f"retire {holding.identity} on {user}@{held.address} (no state deleted)"
                take(step, held.address, remote.retirement(holding, scope=held.scope))

    # And before the first value of each machine: an interrupted run then leaves
    # a machine that can open whatever it already holds. The artifact carries
    # the sealing program in its own closure, so the copy is what puts both
    # there and the install is what makes the manager run it at boot.
    for unsealer in unsealers(deployment, planned):
        copy = f"unsealer {unsealer.machine} {unsealer.artifact} -> {user}@{unsealer.address}"
        with remote.taking(copy, unsealer.address, record):
            channel.run(remote.copy_argv(unsealer.artifact, unsealer.address, user=user), env=env)
        take(
            f"unseal {unsealer.machine} on {user}@{unsealer.address}",
            unsealer.address,
            remote.unsealer_script(unsealer.artifact, scope=unsealer.scope),
        )

    writing = {write.machine: machine_scope(deployment, write.machine) for write in planned}
    moved: set[tuple[str, str]] = set()
    for write in planned:
        # The sealed copy first, so an interrupted run never leaves a machine
        # whose copy is older than the plaintext beside it. It is written on
        # every apply and answers no `changed`: two sealings of one file
        # differ, so there is nothing to compare and nothing to skip.
        if write.sealed is not None:
            sealed = (
                f"sealed {write.value.key} {write.file.name} -> "
                f"{user}@{write.address}:{write.file.sealed}"
            )
            take(
                sealed,
                write.address,
                remote.seal_script(write.file, scope=writing[write.machine]),
                stdin=write.sealed,
            )
        step = (
            f"value {write.value.key} {write.file.name} -> {user}@{write.address}:{write.file.path}"
            f" ({write.file.owner}:{write.file.group} {write.file.mode})"
        )
        script = remote.write_script(write.file, scope=writing[write.machine])
        answered = take(step, write.address, script, stdin=write.content)
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
        take(step, address, remote.restart_script(entry.units, scope=scopes[key]))
    return tuple(lines)
