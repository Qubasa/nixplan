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

Each answered line then carries the verdict of comparing what the machine holds
with what the build published. An image names the identity it holds in the name
of the image the machine has attached, so that comparison is identity equality
against the record's own field, made against the entry's own image and never
against whichever image the machine lists first. A flakelet endpoint publishes
no identity of the artifact it activated - it stores one and reports the unit
files instead - so that comparison is the narrower one, and its words say so
rather than borrowing the other's. Neither changes the exit status: a stale
entry is an answer, and what to do about it is the applying command's work.

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
    image_file,
    machine_address,
    service_name,
    unit_files,
)

UNDIALLED = -1
UNREALISED = -2


@dataclass(frozen=True)
class Report:
    """What each entry's machine answered, and the machines that answered nothing."""

    lines: tuple[str, ...]
    unasked: tuple[str, ...]


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
        One line per entry, in plan key order, each handed to `log` as it is
        known, and the machines the report could not ask.

    Raises:
        ApplyError: If a named key is not an entry of the deployment, or an
            endpoint answered something that is not its own status.
    """
    opts, env = remote.channel(base_env, ssh_key)
    lines, record = remote.recording(log)
    unasked: set[str] = set()
    for entry in _selected(deployment, only):
        answer = _ask(runner, entry, opts=opts, user=user, env=env)
        record(f"{entry.key} {entry.realiser} {_answered(entry, answer)}")
        if answer.status != UNREALISED and not _the_endpoint_answered(answer):
            unasked.add(entry.machine)
    for machine, delivered in _values(deployment, only).items():
        address = machine_address(deployment, machine, of=f"the values of {machine}")
        question = remote.values_script([file.path for _, file in delivered])
        answer = remote.asking(
            runner, remote.ssh_argv(address, question, opts=opts, user=user), env=env
        )
        if answer.status != 0:
            unasked.add(machine)
            continue
        for key in _absent(delivered, answer.said):
            record(f"value {key} missing on {machine}")
    return Report(lines=tuple(lines), unasked=tuple(sorted(unasked)))


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
    machines = {entry.machine for entry in _selected(deployment, only) if entry.address is not None}
    delivered: dict[str, tuple[tuple[str, ValueFile], ...]] = {}
    for machine in sorted(machines):
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
        for columns in (line.split() for line in reported.splitlines())
        if len(columns) == 2
    }
    return tuple(sorted({key for key, file in delivered if said.get(file.path) != "present"}))


def _ask(
    runner: remote.Runner, entry: Entry, *, opts: str, user: str, env: dict[str, str]
) -> remote.Answer:
    if entry.path is None:
        return remote.Answer(UNREALISED, "")
    if entry.address is None:
        return remote.Answer(UNDIALLED, "")
    argv = remote.ssh_argv(entry.address, remote.status_script(entry), opts=opts, user=user)
    return remote.asking(runner, argv, env=env)


def _the_endpoint_answered(answer: remote.Answer) -> bool:
    """Whether this answer came from the machine's own endpoint at all."""
    return answer.status not in (UNDIALLED, UNREALISED, remote.UNREACHABLE, *remote.MISSING)


def _answered(entry: Entry, answer: remote.Answer) -> str:
    if answer.status == UNREALISED:
        return "realises nothing: the entry declares no unit, so no machine holds anything for it"
    if answer.status == UNDIALLED:
        return f"not dialled: machine {entry.machine} declares no address"
    if answer.status == remote.UNREACHABLE:
        return f"unreachable: {entry.machine} at {entry.address} answered nothing"
    if answer.status in remote.MISSING:
        return f"no endpoint on {entry.machine}: {answer.said}"
    if answer.status != 0:
        return "absent"
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


def _read_status(entry: Entry, reported: str) -> str:
    if entry.realiser == "image":
        return _read_attachment(entry, reported)
    registered = _registered(entry, reported)
    if not registered:
        return "absent"
    first = registered[0]
    if not isinstance(first, dict):
        raise ApplyError(f"{entry.key}: the endpoint reported {first!r}, which is not an entry")
    held = (
        f"generation {first.get('generation')} of {first.get('locked_url')} "
        f"{_running(entry, first.get('units'))}"
    )
    failed = first.get("last_error")
    return held if failed in (None, "") else f"{held}, last error {failed}"


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
    """Say whether the units a machine runs are the units this build produced.

    The endpoint publishes no identity of the artifact it activated, so this is
    the narrower question, and the words are the narrower ones: what it reports
    for the generation it runs is the store path of each unit file, and those
    are the files the build's own artifact holds. An entry whose closure, host
    paths, service manager or platform moved without moving a unit's text runs
    this build's units and carries another identity, which is why no line here
    says current.
    """
    if not isinstance(reported, dict) or not reported:
        return "reports nothing to compare"
    if reported == unit_files(entry):
        return "runs this build's units"
    return "runs units this build did not produce"


def _read_attachment(entry: Entry, reported: str) -> str:
    """Say what the machine holds attached for one image entry, and whose build it is.

    An image carries its identity in its own file name, so the machine names
    the identity it holds and the comparison is identity equality. The image
    the build published and the image the machine holds are two questions: a
    machine holding an earlier build's image answers that one is attached and
    that it is not this one, and a listing this cannot read leaves the line the
    machine's own answer rather than a verdict over a guess.

    The identity compared is the entry's own: a machine may hold an earlier
    build's image of the same entry beside this one, and whichever of them the
    listing prints first decides nothing. This build's image is looked for by
    name, and a listing holding only another build's is what names both
    identities.

    An identity match is evidence about the image and about nothing beside it:
    the version digest excludes a configuration file's bytes on purpose, so an
    entry shown a file the machine no longer holds the current bytes of is
    never `current`, and the line says which path disagrees.
    """
    answer = remote.attachment_of(reported)
    mine = image_file(entry).removesuffix(".raw")
    held = _held(mine, mine.rpartition("_")[0], answer.listed)
    if held is None:
        return "absent" if answer.state in ("", "detached") else answer.state
    identity, attachment = held
    beside = _beside(answer.configuration)
    if identity != entry.digest:
        return f"{attachment} holds {identity}, built {entry.digest}"
    if beside:
        return f"{answer.state or attachment} holds this build's image, {beside}"
    return f"{answer.state or attachment} current"


def _beside(configuration: tuple[tuple[str, str], ...]) -> str:
    """Return what the machine holds beside the image that the build does not."""
    return ", ".join(f"{path} {word}" for path, word in sorted(configuration) if word != "current")


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
