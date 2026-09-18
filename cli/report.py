"""What the command reports: what a build holds, what a machine holds, and what a
rollback undid.

A status is what the machine's own endpoint says, and absence is one of its
answers rather than the report's: an entry the endpoint answers about and does
not register is absent, a machine whose endpoint cannot be run carries no
endpoint, a machine that answers nothing is unreachable, and an entry whose
machine declares no address is one the command will not dial. The exit status
is what tells the four apart, because an endpoint refuses a name it holds
nothing under with a status of its own: only a shell that could not run the
endpoint at all, and only ssh that reached nothing, are the other two. Printing
absence for either of those would tell an operator the deployment was never
applied when the truth is that nobody was asked. An answer the command cannot
read as the endpoint's own status is a fifth condition rather than a fifth
spelling of absence: it is the command's own refusal naming the entry and what
the machine said, because a machine whose answer cannot be read is a machine
that was not asked. Each line is printed as it is known, because one machine's
silence says nothing about another's answer.

Each question is answered as a record carrying the fields the verdict is made
of, and each line is the rendering of exactly one of them, made in `lines_of`
and nowhere else: a program reads a field and never matches a word out of a
sentence, and a reworded line moves in one place.

Each answered line then carries the verdict of comparing what the machine holds
with what the build published. An image names the identity it holds in the name
of the image the machine has attached, so that comparison is identity equality
against the record's own field, made against the entry's own image and never
against whichever image the machine lists first. A flakelet endpoint publishes
no identity of the artifact it activated - it stores one and reports the unit
files instead - so that comparison is the narrower one, and its words say so
rather than borrowing the other's. Neither changes the exit status: a stale
entry is an answer, and what to do about it is the applying command's work.

A machine is then asked, once, what else it holds, and every holding the build
names no entry for costs its own line. A holding is attributed before it is
named: only what the record publishes for the realiser that would have put it
there makes an answer this planner's, so a service the machine's own
configuration declares is read as nothing. The line carries the machine's own
answer - the plan key where the answer names one, the listed name where it
names only that - and it costs no exit status either, for the reason a stale
entry does not: removing it is the applying command's work.

The one question a machine is asked about its values carries the machine's own
trial of its sealed copies, because a report that cost a login per file would
fail as a machine that died. What the trial answers is whether each copy is
there and whether it opens, never a byte of one: a copy that does not open and
a value with no copy at all are two lines an operator cannot learn any other
way, both of them saying that the machine will not have that value after its
next reboot, and a machine holding no unsealer is reported as one whose copies
were not checked rather than as one whose copies are fine. None of the three
changes the exit status, for the reason a stale entry does not.

A rollback is the endpoint's own. An image entry has no generation to return to,
so rolling one back is a refusal naming the entry and its realiser rather than a
detach that would leave the machine running nothing.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import remote
from errors import ApplyError
from manifest import (
    Deployment,
    Entry,
    ValueFile,
    address_of,
    entry_scope,
    image_file,
    machine_address,
    machine_scope,
    service_name,
    unit_files,
)

UNDIALLED = -1
UNREALISED = -2

# How a machine was reached, which is what a consumer reads to tell the answers
# apart. Absence is one of them and rests on the one fact it always rested on:
# an endpoint that answered and registered no entry. An answer the command
# cannot read is not in this set at all, because it stays the command's own
# refusal.
REALISES_NOTHING = "realises-nothing"
NOT_DIALLED = "not-dialled"
UNREACHED = "unreachable"
NO_ENDPOINT = "no-endpoint"
ABSENT = "absent"
ANSWERED = "answered"

# What comparing the units a flakelet endpoint reports against the ones the
# build produced answers. The endpoint publishes no identity of the artifact it
# activated, so this is the narrower question and none of its answers is
# `current`.
RUNS_THIS_BUILD = "runs-this-build"
RUNS_ANOTHER_BUILD = "runs-another-build"
NOTHING_TO_COMPARE = "nothing-to-compare"

# The machine's own verdict on a sealed copy, over the words its unsealer
# prints: `remote.OPENS`, `remote.MISSING_COPY`, `remote.UNCHECKED` for a
# machine that holds no unsealer to ask, and this one for a copy the machine
# cannot open, which a trial reports by naming the failure rather than a word.
CLOSED = "closed"


@dataclass(frozen=True)
class EntryAnswer:
    """What one machine answered about one entry, before it is a sentence.

    A field the reading did not compute is `None` and never an empty value, so
    a consumer cannot read an absence as a fact: an unreachable machine says
    nothing about an identity. `state` is the word the machine's own tool
    printed for the image it was asked about and `listed` the state its listing
    gives the image it holds for this entry, which are two answers for a
    machine holding an earlier build.
    """

    key: str
    machine: str
    realiser: str
    reached: str
    address: str | None = None
    said: str | None = None
    generation: int | None = None
    locked_url: str | None = None
    units: str | None = None
    held: str | None = None
    built: str | None = None
    state: str | None = None
    listed: str | None = None
    configuration: tuple[tuple[str, str], ...] | None = None
    last_error: str | None = None


@dataclass(frozen=True)
class ValueAnswer:
    """What one machine answered about one value delivered to it.

    One record per value and not per file, the way the line always was: a value
    one of whose files is gone is one answer about that value. `seal` is `None`
    for a machine whose record does not say its copies are sealed, so a machine
    that was asked nothing about a copy is not a machine that answered.
    """

    key: str
    machine: str
    present: bool
    seal: str | None = None


@dataclass(frozen=True)
class HoldingAnswer:
    """One holding a machine answered that the build names no entry for.

    The holding is the record `remote` already read, beside the machine it was
    asked of, which is the only thing rendering it ever needed.
    """

    machine: str
    holding: remote.Holding


Verdict = EntryAnswer | ValueAnswer | HoldingAnswer


@dataclass(frozen=True)
class Report:
    """What each entry's machine answered, and the machines that answered nothing."""

    lines: tuple[str, ...]
    unasked: tuple[str, ...]
    answers: tuple[Verdict, ...] = ()


def describe(deployment: Deployment) -> tuple[str, ...]:
    """Return what a built deployment holds, one line per entry then per value.

    Returns:
        A line per placed entry naming its realiser, machine, address, artifact
        and units, then a line per value entry naming its delivery set and its
        files, both in plan key order, and then the diagnostics the build wrote
        as the planner rendered them. The rows are the build's own: a warning
        is what a deployment holds as much as an entry is, and a deployment the
        planner refused publishes its rows and no entries at all.
    """
    lines = [
        f"{entry.key} {entry.realiser} {entry.machine} {entry.address or 'unaddressed'} "
        f"{entry.path or 'no artifact'} "
        f"[{' '.join(entry.units)}]"
        for entry in _entries(deployment)
    ]
    lines += [
        f"{value.key} delivered to [{' '.join(value.delivery)}] "
        f"files [{' '.join(file.name for file in value.files)}]"
        for _, value in sorted(deployment.values.items())
    ]
    lines += deployment.rendered.splitlines()
    return tuple(lines)


def status(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    only: Sequence[str] = (),
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    log: Callable[[str], None] = remote.ignore,
) -> Report:
    """Return what each machine reports about the entries it was given.

    `only` restricts the report and asks about every entry where it names none.

    Returns:
        One record per question asked - one per entry, one per value delivered
        to a machine and one per holding the build names no entry for - the
        lines they render into, each handed to `log` as it is known, and the
        machines the report could not ask.

    Raises:
        ApplyError: If a named key is not an entry of the deployment, if an
            endpoint answered something that is not its own status, or if a
            machine answered the question of what it holds with something the
            command cannot read, naming the machine and what it said.
    """
    opts, env = remote.channel(base_env, ssh_key)
    lines, record = remote.recording(log)
    answers: list[Verdict] = []
    said: set[str] = set()
    unasked: set[str] = set()

    def told(answer: Verdict, *, once: bool = False) -> None:
        answers.append(answer)
        for line in lines_of(answer):
            # `once` is the machine's own verdict about its unsealer: one fact
            # however many values of that machine carry it, and one line.
            if once and line in said:
                continue
            said.add(line)
            record(line)

    for entry in _selected(deployment, only):
        answer = _ask(runner, deployment, entry, opts=opts, user=user, env=env)
        told(_answered(entry, answer))
        if answer.status != UNREALISED and not _the_endpoint_answered(answer):
            unasked.add(entry.machine)
    for machine, delivered in _values(deployment, only).items():
        address = machine_address(deployment, machine, of=f"the values of {machine}")
        trial = _trial(deployment, machine)
        question = remote.values_script([file.path for _, file in delivered], check=trial)
        answer = remote.asking(
            runner, remote.ssh_argv(address, question, opts=opts, user=user), env=env
        )
        if answer.status != 0:
            unasked.add(machine)
            continue
        for value in _values_answered(delivered, machine, answer.said, asked=trial is not None):
            told(value, once=True)
    for machine in _machines(deployment, only):
        held = _holdings(deployment, runner, machine, opts=opts, user=user, env=env)
        if held is None:
            unasked.add(machine)
            continue
        for holding in held:
            told(HoldingAnswer(machine=machine, holding=holding))
    return Report(lines=tuple(lines), unasked=tuple(sorted(unasked)), answers=tuple(answers))


def _machines(deployment: Deployment, only: Sequence[str]) -> tuple[str, ...]:
    """Return the machines of the selection an answer can be asked of, sorted.

    A machine declaring no address is asked nothing: its entries' own lines
    already say it was not dialled, and a machine the build places no entry of
    the selection on is not asked at all.
    """
    placed = {entry.machine for entry in _selected(deployment, only) if entry.address is not None}
    return tuple(sorted(placed))


def _holdings(
    deployment: Deployment,
    runner: remote.Runner,
    machine: str,
    *,
    opts: str,
    user: str,
    env: dict[str, str],
) -> tuple[remote.Holding, ...] | None:
    """Return what one machine holds that the build names no entry for.

    One question per machine, beside the value question, because a machine's
    endpoint may be reached over a socket-activated login. What the deployment
    places decides which holdings are named and the selection decides only
    which machines are asked, so a restriction never makes an entry an orphan.

    Returns:
        The holdings the build names no entry for, empty for a machine holding
        none of them, and `None` for a machine that could not be asked.

    Raises:
        ApplyError: If the answer is not the one the question prints, naming
            the machine and what it said.
    """
    realisers = tuple(deployment.realisers.values())
    question = remote.holdings_script(realisers, scope=machine_scope(deployment, machine))
    if not question:
        return ()
    address = machine_address(deployment, machine, of=f"what {machine} holds")
    answer = remote.asking(
        runner, remote.ssh_argv(address, question, opts=opts, user=user), env=env
    )
    if answer.status != 0:
        return None
    return remote.unnamed(
        remote.holdings_of(machine, realisers, answer.said), realisers, deployment.entries
    )


def _values(
    deployment: Deployment, only: Sequence[str]
) -> dict[str, tuple[tuple[str, ValueFile], ...]]:
    """Return the values each machine of the selection is delivered, by machine.

    A machine declaring no address is asked nothing: its entries' own lines
    already say it was not dialled, and a value question would be a second copy
    of that refusal.

    Returns:
        The value entry key and file of every declared file delivered to that
        machine, sorted, for each machine with an address and a value.
    """
    delivered: dict[str, tuple[tuple[str, ValueFile], ...]] = {}
    for machine in _machines(deployment, only):
        held = tuple(
            sorted(
                (
                    (value.key, file)
                    for value in deployment.values.values()
                    if machine in value.delivery
                    for file in value.files
                ),
                # By the file's name and never by the record: two files of one
                # value tie on the key, and a `ValueFile` is not ordered.
                key=lambda held: (held[0], held[1].name),
            )
        )
        if held:
            delivered[machine] = held
    return delivered


def _halves(reported: str) -> tuple[list[str], list[str]]:
    """Return the presence half of one machine's answer and its trial half.

    The two are one login's output, so they are told apart by the marker the
    question printed between them and never by the shape of a line: both
    halves answer `<path> <word>`.
    """
    lines = reported.splitlines()
    mark = lines.index(remote.SEALS) if remote.SEALS in lines else len(lines)
    return lines[:mark], [line for line in lines[mark + 1 :] if line.strip()]


def _absent(delivered: tuple[tuple[str, ValueFile], ...], reported: str) -> tuple[str, ...]:
    """Return the value entries the machine answered were not all there.

    Only the presence of each path is read. What a held file contains is never
    asked: reading a secret to report on it is not something this command does.
    `reported` is what the machine printed, one `<path> present|absent` a line.

    Returns:
        The value entry keys with at least one path the machine does not hold,
        sorted, empty for a machine holding every one of them.
    """
    said = {
        columns[0]: columns[1]
        for columns in (line.split() for line in _halves(reported)[0])
        if len(columns) == 2
    }
    return tuple(sorted({key for key, file in delivered if said.get(file.path) != "present"}))


def _trial(deployment: Deployment, machine: str) -> Path | None:
    """Return the machine's own trial of its sealed copies, where the build made one.

    Returns:
        The unsealer's check program, and nothing for a machine whose copies
        the record says are not sealed.
    """
    stated = deployment.machines.get(machine)
    if stated is None or not stated.sealed or stated.path is None:
        return None
    return stated.path / "bin" / "check"


def _values_answered(
    delivered: tuple[tuple[str, ValueFile], ...],
    machine: str,
    reported: str,
    *,
    asked: bool,
) -> tuple[ValueAnswer, ...]:
    """Return one record per value that machine is delivered, in key order.

    Returns:
        The value key, whether the machine holds every declared path of it, and
        the machine's own verdict on its sealed copy where its copies are
        sealed at all.
    """
    missing = set(_absent(delivered, reported))
    sealed = _seals(delivered, reported, asked=asked)
    return tuple(
        ValueAnswer(
            key=key,
            machine=machine,
            present=key not in missing,
            seal=sealed.get(key),
        )
        for key in sorted({key for key, _ in delivered})
    )


def _seals(
    delivered: tuple[tuple[str, ValueFile], ...],
    reported: str,
    *,
    asked: bool,
) -> dict[str, str]:
    """Return one machine's verdict on each sealed copy it holds, by value key.

    The verdict is the machine's own, obtained by asking its own unsealer, and
    nothing about the bytes of a copy is printed or transferred: a native seal
    names no recipient, so whether it opens is the only question there is and
    the tool that owns the format is the only thing that can answer it. A copy
    sealed to a rotated identity and a copy whose bytes were damaged are one
    verdict, because they are one answer.

    Returns:
        One verdict per value the machine answered about, empty for a machine
        whose copies are not sealed or whose trial answered nothing, and
        `remote.UNCHECKED` for every value of a machine holding no unsealer.
        None of them changes the exit status.
    """
    if not asked:
        return {}
    trial = _halves(reported)[1]
    if not trial:
        return {}
    if remote.UNCHECKED in trial:
        return {key: remote.UNCHECKED for key, _ in delivered}
    said = {
        columns[0]: columns[1] for columns in (line.split() for line in trial) if len(columns) == 2
    }
    answered: dict[str, list[str]] = {}
    for key, file in delivered:
        if file.sealed in said:
            answered.setdefault(key, []).append(said[file.sealed])
    return {key: _verdict(words) for key, words in answered.items()}


def _verdict(words: list[str]) -> str:
    """Return one value's verdict over the words its own copies earned.

    A value is one answer however many files it declares, the way its presence
    already is, and a copy that is not there is the plainer fact: a machine
    cannot open what it does not hold.
    """
    if remote.MISSING_COPY in words:
        return remote.MISSING_COPY
    if any(word != remote.OPENS for word in words):
        return CLOSED
    return remote.OPENS


def _ask(
    runner: remote.Runner,
    deployment: Deployment,
    entry: Entry,
    *,
    opts: str,
    user: str,
    env: dict[str, str],
) -> remote.Answer:
    if entry.path is None:
        return remote.Answer(UNREALISED, "")
    if entry.address is None:
        return remote.Answer(UNDIALLED, "")
    scope = entry_scope(deployment, entry)
    question = remote.status_script(entry, scope=scope)
    argv = remote.ssh_argv(entry.address, question, opts=opts, user=user)
    return remote.asking(runner, argv, env=env)


def _the_endpoint_answered(answer: remote.Answer) -> bool:
    """Whether this answer came from the machine's own endpoint at all."""
    return answer.status not in (UNDIALLED, UNREALISED, remote.UNREACHABLE, *remote.MISSING)


def _reached(entry: Entry, reached: str, **fields: Any) -> EntryAnswer:
    """Return the record of one entry, with the fields that way of reaching it has."""
    return EntryAnswer(
        key=entry.key,
        machine=entry.machine,
        realiser=entry.realiser,
        address=entry.address,
        reached=reached,
        **fields,
    )


def _answered(entry: Entry, answer: remote.Answer) -> EntryAnswer:
    """Return the record of how one machine was reached and what it answered."""
    if answer.status == UNREALISED:
        return _reached(entry, REALISES_NOTHING)
    if answer.status == UNDIALLED:
        return _reached(entry, NOT_DIALLED)
    if answer.status == remote.UNREACHABLE:
        return _reached(entry, UNREACHED)
    if answer.status in remote.MISSING:
        return _reached(entry, NO_ENDPOINT, said=answer.said)
    if answer.status != 0:
        return _reached(entry, ABSENT)
    return _read_status(entry, answer.said)


def rollback(
    deployment: Deployment,
    runner: remote.Runner,
    key: str,
    *,
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
    log: Callable[[str], None] = remote.ignore,
) -> tuple[str, ...]:
    """Roll one entry back and return what its machine reported.

    Returns:
        The step line and the endpoint's own report, line by line, each handed
        to `log` as it is known.

    Raises:
        ApplyError: If the key is not an entry of the deployment, if the entry
            is realised as an image, which carries no generation, or if its
            machine or its artifact is one the build does not name. Every one
            of those is settled before the step is announced, so a `failed`
            line always names a machine's own refusal.
    """
    entry = _entry(deployment, key)
    if entry.realiser != "flakelet":
        raise ApplyError(
            f"{entry.key} is realised as {entry.realiser}, which carries no generation to roll "
            f"back to"
        )
    opts, env = remote.channel(base_env, ssh_key)
    address = address_of(entry)
    script = remote.rollback_script(service_name(entry))
    lines, record = remote.recording(log)
    remote.taken(
        runner,
        f"rollback {entry.key} on {user}@{address}",
        address,
        remote.ssh_argv(address, script, opts=opts, user=user),
        env=env,
        record=record,
    )
    return tuple(lines)


def _read_status(entry: Entry, reported: str) -> EntryAnswer:
    """Return the record one endpoint's own answer about one entry is.

    Raises:
        ApplyError: If the answer is not the endpoint's own status.
    """
    if entry.realiser == "image":
        return _read_attachment(entry, reported)
    registered = _registered(entry, reported)
    if not registered:
        return _reached(entry, ABSENT)
    first = registered[0]
    if not isinstance(first, dict):
        raise ApplyError(f"{entry.key}: the endpoint reported {first!r}, which is not an entry")
    failed = first.get("last_error")
    return _reached(
        entry,
        ANSWERED,
        generation=first.get("generation"),
        locked_url=first.get("locked_url"),
        units=_running(entry, first.get("units")),
        last_error=None if failed in (None, "") else failed,
    )


def _registered(entry: Entry, reported: str) -> list[Any]:
    """Return the entries one endpoint registers, which is the only absence there is.

    The endpoint prints the entries it holds under the name it was asked about,
    so an empty registration is the one answer that says the deployment never
    reached this machine. Every other answer is read as the condition it is: a
    value of another kind, or one of a shape no entry can be read out of, is
    the command's own refusal naming the entry and what the machine said, and
    never a line saying the machine holds nothing.

    Returns:
        The registrations, empty for an endpoint that holds none.

    Raises:
        ApplyError: If the answer is not the endpoint's own status.
    """
    if not reported.strip():
        return []
    try:
        answered = json.loads(reported)
    except json.JSONDecodeError as malformed:
        raise ApplyError(
            f"{entry.key}: the endpoint said {reported.strip()!r}, which is not its JSON status"
        ) from malformed
    if not isinstance(answered, list):
        raise ApplyError(
            f"{entry.key}: the endpoint said {reported.strip()!r}, which is not the list of "
            f"registered entries its status is"
        )
    return answered


def _running(entry: Entry, reported: object) -> str:
    """Return which of the three answers the unit comparison makes.

    The endpoint publishes no identity of the artifact it activated, so this is
    the narrower question: what it reports for the generation it runs is the
    store path of each unit file, and those are the files the build's own
    artifact holds. An entry whose closure, host paths, service manager or
    platform moved without moving a unit's text runs this build's units and
    carries another identity, which is why none of the three says current.
    """
    if not isinstance(reported, dict) or not reported:
        return NOTHING_TO_COMPARE
    if reported == unit_files(entry):
        return RUNS_THIS_BUILD
    return RUNS_ANOTHER_BUILD


def _read_attachment(entry: Entry, reported: str) -> EntryAnswer:
    """Return what the machine holds attached for one image entry, and whose build it is.

    An image carries its identity in its own file name, so the machine names
    the identity it holds and the record carries it beside the one the build
    published: the comparison is identity equality and the word is the
    renderer's. A listing this cannot read leaves the record the machine's own
    state and no identity at all, so nothing is compared against a guess.

    The identity read is the entry's own: a machine may hold an earlier build's
    image of the same entry beside this one, and whichever of them the listing
    prints first decides nothing. This build's image is looked for by name, and
    a listing holding only another build's is what names both identities.

    An identity match is evidence about the image and about nothing beside it:
    the version digest excludes a configuration file's bytes on purpose, so the
    record carries every configuration path whose bytes disagree and an entry
    shown one of them is never reported current.
    """
    answer = remote.attachment_of(reported)
    mine = image_file(entry).removesuffix(".raw")
    held = _held(mine, mine.rpartition("_")[0], answer.listed)
    if held is None:
        if answer.state in ("", "detached"):
            return _reached(entry, ABSENT)
        return _reached(entry, ANSWERED, state=answer.state)
    identity, attachment = held
    return _reached(
        entry,
        ANSWERED,
        held=identity,
        built=entry.digest,
        state=answer.state,
        listed=attachment,
        configuration=tuple(sorted(pair for pair in answer.configuration if pair[1] != "current")),
    )


def lines_of(answer: Verdict) -> tuple[str, ...]:
    """Return the lines one record is printed as, which is where every line is made.

    Every sentence the command prints about a machine comes from here, so a
    record and a line cannot disagree and a reworded line moves in one place.

    Returns:
        One line for an entry and for a holding, and for a value the lines its
        answer earns: none for a value the machine holds whose copy opens, one
        for a value it does not hold, one for a copy that is not there or does
        not open, and both where both are true of it.
    """
    if isinstance(answer, EntryAnswer):
        return (f"{answer.key} {answer.realiser} {_verdict_of(answer)}",)
    if isinstance(answer, ValueAnswer):
        return _value_lines(answer)
    return (f"{answer.machine} holds {answer.holding.identity}, which this build does not name",)


def _verdict_of(answer: EntryAnswer) -> str:
    """Return what one entry's record says, in the words an operator reads."""
    if answer.reached == REALISES_NOTHING:
        return "realises nothing: the entry declares no unit, so no machine holds anything for it"
    if answer.reached == NOT_DIALLED:
        return f"not dialled: machine {answer.machine} declares no address"
    if answer.reached == UNREACHED:
        return f"unreachable: {answer.machine} at {answer.address} answered nothing"
    if answer.reached == NO_ENDPOINT:
        return f"no endpoint on {answer.machine}: {answer.said}"
    if answer.reached == ABSENT:
        return "absent"
    if answer.realiser == "image":
        return _image_verdict(answer)
    return _endpoint_verdict(answer)


def _endpoint_verdict(answer: EntryAnswer) -> str:
    """Return the generation a flakelet endpoint holds and what it runs."""
    ran = {
        RUNS_THIS_BUILD: "runs this build's units",
        RUNS_ANOTHER_BUILD: "runs units this build did not produce",
        NOTHING_TO_COMPARE: "reports nothing to compare",
    }[answer.units or NOTHING_TO_COMPARE]
    held = f"generation {answer.generation} of {answer.locked_url} {ran}"
    return held if answer.last_error is None else f"{held}, last error {answer.last_error}"


def _image_verdict(answer: EntryAnswer) -> str:
    """Return what the machine holds for one image entry, against what the build built."""
    if answer.held is None:
        return answer.state or ""
    if answer.held != answer.built:
        return f"{answer.listed} holds {answer.held}, built {answer.built}"
    beside = ", ".join(f"{path} {word}" for path, word in answer.configuration or ())
    if beside:
        return f"{answer.state or answer.listed} holds this build's image, {beside}"
    return f"{answer.state or answer.listed} current"


def _value_lines(answer: ValueAnswer) -> tuple[str, ...]:
    """Return the lines one value's record earns, the missing one first."""
    seal = {
        remote.UNCHECKED: f"{answer.machine} holds no unsealer, so its sealed copies were "
        "not checked",
        remote.MISSING_COPY: f"value {answer.key} has no sealed copy on {answer.machine}",
        CLOSED: f"value {answer.key} sealed copy does not open on {answer.machine}",
    }.get(answer.seal or remote.OPENS)
    return (
        *([] if answer.present else [f"value {answer.key} missing on {answer.machine}"]),
        *([] if seal is None else [seal]),
    )


def _held(mine: str, name: str, listed: tuple[tuple[str, str], ...]) -> tuple[str, str] | None:
    """Return the identity and state of the image a machine holds for one entry.

    `mine` is the image file name this build published for the entry and `name`
    is the entry's own image name, which every build of it shares.

    Returns:
        This build's image where the machine holds it, another build's of the
        same entry where it holds one of those instead, and nothing where it
        holds neither. A detached image is one the machine does not hold.
    """
    holds = [
        (image.removeprefix(f"{name}_"), state)
        for image, state in listed
        if name and image.startswith(f"{name}_") and state != "detached"
    ]
    for held in holds:
        if f"{name}_{held[0]}" == mine:
            return held
    return holds[0] if holds else None


def _entries(deployment: Deployment) -> tuple[Entry, ...]:
    return tuple(entry for _, entry in sorted(deployment.entries.items()))


def _selected(deployment: Deployment, only: Sequence[str]) -> tuple[Entry, ...]:
    if not only:
        return _entries(deployment)
    return tuple(_entry(deployment, key) for key in sorted(set(only)))


def _entry(deployment: Deployment, key: str) -> Entry:
    entry = deployment.entries.get(key)
    if entry is None:
        raise ApplyError(
            f"--only names {key}, which the deployment does not place: it places "
            f"{', '.join(sorted(deployment.entries))}"
        )
    return entry
