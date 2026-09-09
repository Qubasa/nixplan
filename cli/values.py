"""The value source: bytes an operator holds, checked against the plan before
anything is dialled.

The layout is `<dir>/<entry-key>/<file>`, and an entry key carries a `/` of its
own (`issuer:vars/session`), so `<dir>/issuer:vars/session/token` is a real
nested path. The source is therefore enumerated by walking it, and a declared
file is addressed by joining the key and the name rather than by splitting a
relative path back into the two.

The required set is exactly the declared files of every value entry whose
delivery set is non-empty. Bytes are needed only for a file that will actually
be written, and the plan carries the bytes of nothing, so what a value entry
states about being in the plan is not consulted here.

When `--only` restricts the run the missing-file check is restricted with it: to
the value entries whose delivery set intersects the machines of the selected
entries, plus any value entry `--only` names directly. What the source holds is
still measured against every value the whole deployment delivers, so a source
that is right for the deployment stays right for a restricted run of it, and a
deployment that delivers no value takes an empty source and nothing else.
"""

from __future__ import annotations

from collections.abc import Iterable
from pathlib import Path

from errors import ApplyError
from manifest import Deployment, Value, ValueFile


def delivered(deployment: Deployment) -> tuple[str, ...]:
    """Return the keys of the value entries some machine receives, sorted."""
    return tuple(key for key, value in sorted(deployment.values.items()) if value.delivery)


def reaching(
    deployment: Deployment, machines: Iterable[str], named: Iterable[str]
) -> tuple[str, ...]:
    """Return the value entries a run restricted to ``machines`` must hold bytes for.

    Args:
        deployment: The deployment being applied.
        machines: The machines of the entries the run applies.
        named: The keys `--only` named, which may include a value entry.

    Returns:
        The delivered value keys the run is answerable for, sorted.
    """
    reached = frozenset(machines)
    wanted = frozenset(named)
    return tuple(
        key
        for key in delivered(deployment)
        if key in wanted or reached.intersection(deployment.values[key].delivery)
    )


def required(deployment: Deployment, keys: Iterable[str]) -> tuple[tuple[Value, ValueFile], ...]:
    """Return every file that will be written, by value entry then file name.

    Args:
        deployment: The deployment being applied.
        keys: The value entries under consideration.

    Returns:
        Each delivered value entry paired with each file it declares.
    """
    return tuple(
        (value, file)
        for key in sorted(set(keys))
        for value in (deployment.values[key],)
        if value.delivery
        for file in value.files
    )


def held(root: Path) -> tuple[str, ...]:
    """Return the files the source holds, as paths relative to it, sorted."""
    return tuple(
        sorted(found.relative_to(root).as_posix() for found in root.rglob("*") if found.is_file())
    )


def check(deployment: Deployment, root: Path | None, keys: Iterable[str]) -> None:
    """Refuse a value source that does not match the plan, before anything is dialled.

    Args:
        deployment: The deployment being applied.
        root: The value source, or ``None`` when the operator named none.
        keys: The value entries this run is answerable for.

    Raises:
        ApplyError: If the source is not a directory, if it holds no bytes for a
            file a delivered value declares, or if it holds a file no delivered
            value of the deployment declares.
    """
    if root is not None and not root.is_dir():
        raise ApplyError(f"the value source {root} is not a directory")
    present = frozenset(held(root)) if root is not None else frozenset()

    for value, file in required(deployment, keys):
        relative = f"{value.key}/{file.name}"
        if relative in present:
            continue
        if root is None:
            raise ApplyError(
                f"{value.key} declares {file.name}, delivered to "
                f"{', '.join(value.delivery)}, and no value source was named"
            )
        raise ApplyError(
            f"{value.key} declares {file.name} and the value source holds no {relative}"
        )

    everything = frozenset(
        f"{value.key}/{file.name}" for value, file in required(deployment, delivered(deployment))
    )
    extra = sorted(present - everything)
    if extra:
        raise ApplyError(
            f"the value source holds {extra[0]}, which no value this deployment delivers declares"
        )


def bytes_of(root: Path, value: Value, file: ValueFile) -> bytes:
    """Return the bytes the source holds for one declared file.

    Args:
        root: The value source.
        value: The value entry the file belongs to.
        file: The declared file.

    Returns:
        The file's bytes, as they will be written.

    Raises:
        ApplyError: If the file cannot be read.
    """
    path = root / value.key / file.name
    try:
        return path.read_bytes()
    except OSError as unreadable:
        raise ApplyError(f"{value.key}: {path} cannot be read: {unreadable}") from unreadable
