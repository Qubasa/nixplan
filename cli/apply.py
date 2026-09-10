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
from collections.abc import Callable, Iterable, Mapping, Sequence
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
        ApplyError: If any row is an error, with the rendered table as the
            message, or the rows themselves when the deployment carries no
            rendered table.
    """
    rows = deployment.errors
    if not rows:
        return
    rendered = deployment.table.strip() or "\n".join(
        f"{row.id} {row.subject} {row.message}" for row in rows
    )
    raise ApplyError(f"{deployment.root} is not applicable:\n{rendered}")


def writes(deployment: Deployment, source: Path | None, keys: Iterable[str]) -> tuple[Write, ...]:
    """Return every generated file this run writes, and where it goes.

    Every address is resolved and every file is read here, so a source or a plan
    that cannot answer is refused before a machine is dialled rather than after
    the first write.

    Args:
        deployment: The deployment being applied.
        source: The value source, or ``None`` when the operator named none.
        keys: The value entries this run is answerable for.

    Returns:
        The writes, by value entry, then delivery-set order, then file name.

    Raises:
        ApplyError: If a machine of a delivery set has no address, or a declared
            file cannot be read from the source.
    """
    planned: list[Write] = []
    for value, file in values.required(deployment, keys):
        if source is None:
            raise ApplyError(f"{value.key} declares {file.name} and no value source was named")
        content = values.bytes_of(source, value, file)
        for machine in value.delivery:
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
        return remote.activate_script(service_name(entry), entry.path)
    if entry.realiser == "image":
        return remote.attach_script(entry.path)
    raise ApplyError(
        f"{entry.key} states realiser {entry.realiser}, and the command activates "
        f"flakelet and image"
    )


def _ignore(line: str) -> None:
    """Drop a step line, for a caller that reads the returned log instead."""


def apply(
    deployment: Deployment,
    runner: remote.Runner,
    *,
    source: Path | None = None,
    only: Sequence[str] = (),
    ssh_key: Path | None = None,
    user: str = "root",
    base_env: Mapping[str, str] | None = None,
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
        log: Called with each step line as that step happens.

    Returns:
        The step lines, in the order the steps happened.

    Raises:
        ApplyError: For any refusal, all of which happen before the first dial.
    """
    environment = os.environ if base_env is None else base_env
    refuse_inapplicable(deployment)
    keys, named = selection(deployment, only)
    reached = values.reaching(deployment, (deployment.entries[key].machine for key in keys), named)
    values.check(deployment, source, reached)
    planned = writes(deployment, source, reached)
    walked = order.walk(deployment.plan, keys)
    scripts = {key: activation(deployment.entries[key]) for key in walked.order}
    addresses = {key: address_of(deployment.entries[key]) for key in walked.order}

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
        with remote.refusing(step, write.address):
            runner.run(
                remote.ssh_argv(
                    write.address,
                    remote.write_script(write.file.path, write.content),
                    opts=opts,
                    user=user,
                ),
                env=env,
            )
        record(step)

    for key in walked.order:
        entry = deployment.entries[key]
        address = addresses[key]
        copy = f"copy {key} {entry.path} -> {user}@{address}"
        with remote.refusing(copy, address):
            runner.run(remote.copy_argv(entry.path, address, user=user), env=env)
        record(copy)
        step = f"activate {key} ({entry.realiser}) on {user}@{address}"
        with remote.refusing(step, address):
            reported = runner.output(
                remote.ssh_argv(address, scripts[key], opts=opts, user=user), env=env
            )
        record(step)
        for line in reported.splitlines():
            record(f"  {line}")
    return tuple(lines)
