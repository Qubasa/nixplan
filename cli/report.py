"""What the command reports: what a build holds, what a machine holds, and what a
rollback undid.

A status is what the machine's own endpoint says, and an entry the machine does
not hold is reported as absent rather than as a failure: asking is not applying,
and a machine that holds nothing answers the question correctly by saying so.

A rollback is the endpoint's own. An image entry has no generation to return to,
so rolling one back is a refusal naming the entry and its realiser rather than a
detach that would leave the machine running nothing.
"""

from __future__ import annotations

import json
import os
from collections.abc import Mapping, Sequence
from pathlib import Path

import remote
from errors import ApplyError
from manifest import Deployment, Entry, address_of, image_file, service_name


def describe(deployment: Deployment) -> tuple[str, ...]:
    """Return what a built deployment holds, one line per entry then per value.

    Args:
        deployment: The deployment that was built.

    Returns:
        A line per placed entry naming its realiser, machine, address, artifact
        and units, then a line per value entry naming its delivery set and its
        files, both in plan key order.
    """
    lines = [
        f"{entry.key} {entry.realiser} {entry.machine} {entry.address or 'unaddressed'} "
        f"{entry.path} "
        f"[{' '.join(entry.units)}]"
        for entry in _entries(deployment)
    ]
    lines += [
        f"{value.key} delivered to [{' '.join(value.delivery)}] "
        f"files [{' '.join(file.name for file in value.files)}]"
        for _, value in sorted(deployment.values.items())
    ]
    return tuple(lines)


def status(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    only: Sequence[str] = (),
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
) -> tuple[str, ...]:
    """Return what each machine reports about the entries it was given.

    Args:
        deployment: The deployment to ask about.
        runner: The channel every remote step goes through.
        only: The entry keys to ask about, empty for all of them.
        ssh_key: The private key `--ssh-key` named, if any.
        user: The login user on every machine.
        base_env: The environment to run under, the process's own by default.

    Returns:
        One line per entry, in plan key order.

    Raises:
        ApplyError: If a named key is not an entry of the deployment.
    """
    environment = os.environ if base_env is None else base_env
    opts = remote.ssh_opts(ssh_key, inherited=environment.get("NIX_SSHOPTS"))
    env = remote.copy_env(environment, opts)
    lines: list[str] = []
    for entry in _selected(deployment, only):
        address = address_of(entry)
        reported = runner.output(
            remote.ssh_argv(address, _status_script(entry), opts=opts, user=user), env=env
        )
        lines.append(f"{entry.key} {entry.realiser} {_read_status(entry, reported)}")
    return tuple(lines)


def rollback(
    deployment: Deployment,
    runner: remote.Runner,
    key: str,
    *,
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
) -> tuple[str, ...]:
    """Roll one entry back and return what its machine reported.

    Args:
        deployment: The deployment the entry belongs to.
        runner: The channel every remote step goes through.
        key: The entry to roll back.
        ssh_key: The private key `--ssh-key` named, if any.
        user: The login user on the machine.
        base_env: The environment to run under, the process's own by default.

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
    reported = runner.output(
        remote.ssh_argv(address, remote.rollback_script(service_name(entry)), opts=opts, user=user),
        env=env,
    )
    return (f"rollback {entry.key} on {user}@{address}", *reported.splitlines())


def _status_script(entry: Entry) -> str:
    if entry.realiser == "flakelet":
        return remote.flakelet_status_script(service_name(entry))
    if entry.realiser == "image":
        return remote.image_status_script(entry.path / image_file(entry))
    raise ApplyError(f"{entry.key} states realiser {entry.realiser}, which the command cannot ask")


def _read_status(entry: Entry, reported: str) -> str:
    if entry.realiser == "image":
        return "attached" if reported.strip() == "attached" else "absent"
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
    return f"generation {first.get('generation')} of {first.get('locked_url')}"


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
