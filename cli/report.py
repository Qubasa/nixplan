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
applied when the truth is that nobody was asked. Each line is printed as it is
known, because one machine's silence says nothing about another's answer.

Each answered line then carries the verdict of comparing what the machine holds
with what the build published. An image names the identity it holds in the name
of the image the machine has attached, so that comparison is identity equality
against the record's own field. A flakelet endpoint publishes no identity of the
artifact it activated - it stores one and reports the unit files instead - so
that comparison is the narrower one, and its words say so rather than borrowing
the other's. Neither changes the exit status: a stale entry is an answer, and
what to do about it is the applying command's work.

A rollback is the endpoint's own. An image entry has no generation to return to,
so rolling one back is a refusal naming the entry and its realiser rather than a
detach that would leave the machine running nothing.
"""

from __future__ import annotations

import json
import os
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

import remote
from errors import ApplyError
from manifest import (
    Deployment,
    Entry,
    address_of,
    artifact_of,
    image_file,
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


def _ignore(line: str) -> None:
    """Drop a line, for a caller that reads the returned report instead."""


def describe(deployment: Deployment) -> tuple[str, ...]:
    """Return what a built deployment holds, one line per entry then per value.

    Args:
        deployment: The deployment that was built.

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
    log: Callable[[str], None] = _ignore,
) -> Report:
    """Return what each machine reports about the entries it was given.

    Args:
        deployment: The deployment to ask about.
        runner: The channel every remote step goes through.
        only: The entry keys to ask about, empty for all of them.
        ssh_key: The private key `--ssh-key` named, if any.
        user: The login user on every machine.
        base_env: The environment to run under, the process's own by default.
        log: Called with each line as that line is known.

    Returns:
        One line per entry, in plan key order, and the machines the report
        could not ask.

    Raises:
        ApplyError: If a named key is not an entry of the deployment, or an
            endpoint answered something that is not its own status.
    """
    environment = os.environ if base_env is None else base_env
    opts = remote.ssh_opts(ssh_key, inherited=environment.get("NIX_SSHOPTS"))
    env = remote.copy_env(environment, opts)
    lines: list[str] = []
    unasked: set[str] = set()
    for entry in _selected(deployment, only):
        answer = _ask(runner, entry, opts=opts, user=user, env=env)
        line = f"{entry.key} {entry.realiser} {_answered(entry, answer)}"
        lines.append(line)
        log(line)
        if answer.status != UNREALISED and not _the_endpoint_answered(answer):
            unasked.add(entry.machine)
    return Report(lines=tuple(lines), unasked=tuple(sorted(unasked)))


def _ask(
    runner: remote.Runner, entry: Entry, *, opts: str, user: str, env: dict[str, str]
) -> remote.Answer:
    if entry.path is None:
        return remote.Answer(UNREALISED, "")
    if entry.address is None:
        return remote.Answer(UNDIALLED, "")
    argv = remote.ssh_argv(entry.address, _status_script(entry), opts=opts, user=user)
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
    log: Callable[[str], None] = _ignore,
) -> tuple[str, ...]:
    """Roll one entry back and return what its machine reported.

    Args:
        deployment: The deployment the entry belongs to.
        runner: The channel every remote step goes through.
        key: The entry to roll back.
        ssh_key: The private key `--ssh-key` named, if any.
        user: The login user on the machine.
        base_env: The environment to run under, the process's own by default.
        log: Called with each line as that line is known.

    Returns:
        The step line and the endpoint's own report, line by line.

    Raises:
        ApplyError: If the key is not an entry of the deployment, or the entry
            is realised as an image, which carries no generation.
    """
    entry = _entry(deployment, key)
    if entry.realiser != "flakelet":
        raise ApplyError(
            f"{entry.key} is realised as {entry.realiser}, which carries no generation to roll "
            f"back to"
        )
    environment = os.environ if base_env is None else base_env
    opts = remote.ssh_opts(ssh_key, inherited=environment.get("NIX_SSHOPTS"))
    env = remote.copy_env(environment, opts)
    address = address_of(entry)
    lines: list[str] = []

    def record(line: str) -> None:
        lines.append(line)
        log(line)

    with remote.taking(f"rollback {entry.key} on {user}@{address}", address, record):
        reported = runner.output(
            remote.ssh_argv(
                address, remote.rollback_script(service_name(entry)), opts=opts, user=user
            ),
            env=env,
        )
    for line in reported.splitlines():
        record(line)
    return tuple(lines)


def _status_script(entry: Entry) -> str:
    if entry.realiser == "flakelet":
        return remote.flakelet_status_script(service_name(entry))
    if entry.realiser == "image":
        return remote.image_status_script(artifact_of(entry) / image_file(entry))
    raise ApplyError(f"{entry.key} states realiser {entry.realiser}, which the command cannot ask")


def _read_status(entry: Entry, reported: str) -> str:
    if entry.realiser == "image":
        return _read_attachment(entry, reported)
    try:
        registered = json.loads(reported) if reported.strip() else []
    except json.JSONDecodeError as malformed:
        raise ApplyError(
            f"{entry.key}: the endpoint said {reported.strip()!r}, which is not its JSON status"
        ) from malformed
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
    """
    answer = remote.attachment_of(reported)
    name = image_file(entry).removesuffix(".raw").rpartition("_")[0]
    held = _held(name, answer.listed)
    if held is None:
        return "absent" if answer.state in ("", "detached") else answer.state
    identity, attachment = held
    if identity == entry.digest:
        return f"{answer.state or attachment} current"
    return f"{attachment} holds {identity}, built {entry.digest}"


def _held(name: str, listed: tuple[tuple[str, str], ...]) -> tuple[str, str] | None:
    """Return the identity and state of the image a machine holds attached for one entry."""
    holds = [
        (image.removeprefix(f"{name}_"), state)
        for image, state in listed
        if name and image.startswith(f"{name}_") and state != "detached"
    ]
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
