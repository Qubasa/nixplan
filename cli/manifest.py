"""Reading a built deployment: its plan, its manifest, its diagnostics and the
artifact of each entry it placed.

`manifest.json` is the whole interface between the evaluating side and this
command. It maps a plan key to the artifact built for it, because a plan key
carries `@` and `:` and is therefore not a directory name, so nothing here
reconstructs an artifact's name: the mapping is data and it is read.

A target is either such a directory or a flake reference, and a flake reference
is built once per invocation. A build that fails carries the rendered
diagnostics table on its stderr, because the build layer raises with it, so that
stderr is what the refusal says.

A directory handed in by name is read as it is found. That is why the error rows
of a deployment are read too: a build cannot produce a tree whose diagnostics
carry one, and a directory can.
"""

from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from errors import ApplyError

MANIFEST = "manifest.json"
PLAN = "plan.json"
TABLE = "diagnostics.txt"
ROWS = "diagnostics.json"
MACHINE_PREFIX = "machine:"
VERSION = 1
STORE_VARIABLE = "NIX_STORE_DIR"
DEFAULT_STORE = "/nix/store"


@dataclass(frozen=True)
class ValueFile:
    """One file a generated value declares."""

    name: str
    path: str
    secrecy: str


@dataclass(frozen=True)
class Value:
    """A generated value entry: the machines that receive it and its files.

    A `program` is the generator the plan recorded, and its presence says the
    bytes are that program's rather than the operator's.
    """

    key: str
    delivery: tuple[str, ...]
    program: str | None
    files: tuple[ValueFile, ...]


@dataclass(frozen=True)
class Entry:
    """A placed entry, with the artifact built for it and where it goes."""

    key: str
    path: Path
    realiser: str
    profile: str | None
    machine: str
    address: str | None
    units: tuple[str, ...]


@dataclass(frozen=True)
class Diagnostic:
    """One row of a deployment's diagnostics."""

    id: str
    subject: str
    severity: str
    message: str


@dataclass(frozen=True)
class Deployment:
    """A built deployment, as this command reads it."""

    root: Path
    plan: Mapping[str, Any]
    entries: Mapping[str, Entry]
    values: Mapping[str, Value]
    diagnostics: tuple[Diagnostic, ...]
    table: str

    @property
    def errors(self) -> tuple[Diagnostic, ...]:
        """The rows that make the deployment inapplicable."""
        return tuple(row for row in self.diagnostics if row.severity == "error")

    @property
    def rendered(self) -> str:
        """The table the build wrote, or the rows themselves where it wrote none."""
        return self.table.strip() or "\n".join(
            f"{row.id} {row.subject} {row.message}" for row in self.diagnostics
        )


def store_dir() -> str:
    """Return the store directory this command runs against.

    Returns:
        The store nix itself resolves a path in: `NIX_STORE_DIR` where the
        caller set it, and the default store otherwise.
    """
    return os.environ.get(STORE_VARIABLE) or DEFAULT_STORE


def resolve(target: str) -> Path:
    """Resolve a target to the built deployment directory it names.

    Args:
        target: A directory holding `manifest.json`, or a flake reference.

    Returns:
        The directory the deployment was built into.

    Raises:
        ApplyError: If the target is a directory that is neither, if it names a
            store path that is no longer there, if the reference does not
            build, or if it builds something that is not a deployment. A
            build's message carries its own stderr, which is where the rendered
            diagnostics table appears.
    """
    named = Path(target)
    if (named / MANIFEST).is_file():
        return named
    if "#" not in target and named.is_relative_to(store_dir()) and not named.exists():
        raise ApplyError(
            f"{target} is not there any more: the build it names was collected, so build the "
            f"reference that produced it again"
        )
    # A directory carrying neither file cannot be read and cannot be built. Left
    # to nix it becomes a flake reference, and the answer is then about commit
    # hashes rather than about the deployment that was meant.
    if named.is_dir() and not (named / "flake.nix").is_file():
        raise ApplyError(
            f"{target} is a directory carrying no {MANIFEST} and no flake.nix, "
            f"so it is neither a built deployment nor a flake: name the flake "
            f"attribute that builds it, or a directory `planner build` wrote"
        )
    built = subprocess.run(
        ["nix", "build", "--no-link", "--print-out-paths", target],
        capture_output=True,
        text=True,
        check=False,
    )
    if built.returncode != 0:
        raise ApplyError(f"{target} does not build:\n{built.stderr.strip()}")
    paths = built.stdout.split()
    if not paths:
        raise ApplyError(f"{target} built no output path")
    root = Path(paths[-1])
    if not (root / MANIFEST).is_file():
        raise ApplyError(f"{target} built {root}, which carries no {MANIFEST}")
    return root


def read(root: Path) -> Deployment:
    """Read the built deployment at ``root``.

    Args:
        root: A directory holding `manifest.json` and `plan.json`.

    Returns:
        The deployment: its plan, its value entries, its diagnostics, and its
        placed entries with the store path each artifact resolves to. Resolving
        is load-bearing rather than tidy: the manifest addresses an artifact
        inside the build, the build is a farm of symlinks, and the path an
        activation names on the machine has to be the path the copy put there. A
        deployment carrying no diagnostics file carries no row.

    Raises:
        ApplyError: If a file is absent or unreadable, if the record states a
            version this command does not implement or a store it does not run
            against, or if the manifest states an entry without a field the
            command needs, naming both.
    """
    interface = _load(root / MANIFEST)
    _shape(root / MANIFEST, interface)
    plan = _load(root / PLAN)
    entries = {
        key: _entry(root, key, _mapping(record, of=f"manifest entry {key}"))
        for key, record in sorted(_mapping(interface["entries"], of=MANIFEST).items())
    }
    values = {
        key: _value(key, _mapping(record, of=f"manifest value {key}"))
        for key, record in sorted(_mapping(interface.get("values", {}), of=MANIFEST).items())
    }
    table = root / TABLE
    return Deployment(
        root=root,
        plan=plan,
        entries=entries,
        values=values,
        diagnostics=_rows(root / ROWS),
        table=table.read_text() if table.is_file() else "",
    )


def address_of(entry: Entry) -> str:
    """Return the address to dial for one placed entry.

    A machine that declares no address is a warning of the planner rather than
    a refusal, so the record carries the absence and the refusal is made here,
    where the machine would be reached.

    Args:
        entry: The placed entry.

    Returns:
        The address the record carries for the entry's machine.

    Raises:
        ApplyError: If the record carries no address for that machine.
    """
    if entry.address is None:
        raise ApplyError(
            f"{entry.key}: machine {entry.machine} declares no address, so the command cannot "
            f"reach it"
        )
    return entry.address


def machine_address(deployment: Deployment, machine: str, *, of: str) -> str:
    """Return the address the plan's machine record declares.

    The address of a machine that receives a value is the registry's, not an
    entry's own target, and a value's machine need run no entry at all.

    Args:
        deployment: The deployment being applied.
        machine: The machine name.
        of: What is being delivered, for a refusal to name.

    Returns:
        The address to dial.

    Raises:
        ApplyError: If the plan carries no record for that machine, or the
            record declares no address.
    """
    record = deployment.plan.get(f"{MACHINE_PREFIX}{machine}")
    if not isinstance(record, dict):
        raise ApplyError(f"the plan carries no {MACHINE_PREFIX}{machine} record for {of}")
    address = record.get("address")
    if not isinstance(address, str) or not address:
        raise ApplyError(f"machine {machine} declares no address, so {of} cannot be delivered")
    return address


def service_name(entry: Entry) -> str:
    """Return the service name a flakelet artifact declares in its `meta.json`.

    Args:
        entry: A placed entry realised as a flakelet artifact.

    Returns:
        The name the endpoint registers the entry under.

    Raises:
        ApplyError: If the artifact declares no name.
    """
    meta = _load(entry.path / "meta.json")
    name = meta.get("name")
    if not isinstance(name, str) or not name:
        raise ApplyError(f"{entry.key}: {entry.path}/meta.json declares no service name")
    return name


def image_file(entry: Entry) -> str:
    """Return the image an image artifact carries, as `attachment.json` names it.

    Args:
        entry: A placed entry realised as a portable-service image.

    Returns:
        The image file name, relative to the artifact directory.

    Raises:
        ApplyError: If the attachment names no image.
    """
    attachment = _load(entry.path / "attachment.json")
    image = attachment.get("image")
    if not isinstance(image, str) or not image:
        raise ApplyError(f"{entry.key}: {entry.path}/attachment.json names no image")
    return image


def _shape(path: Path, interface: Mapping[str, Any]) -> None:
    version = interface.get("version")
    if version != VERSION:
        raise ApplyError(
            f"{path} states version {version!r}, and this command implements version {VERSION}"
        )
    stated = interface.get("storeDir")
    running = store_dir()
    if stated != running:
        raise ApplyError(f"{path} names store {stated!r}, and this command runs against {running}")
    if "entries" not in interface:
        raise ApplyError(
            f"{path} carries no entries table, and an absent table is not an empty one: this is "
            f"not a record the command can read"
        )


def _entry(root: Path, key: str, record: Mapping[str, Any]) -> Entry:
    profile = record.get("profile")
    if profile is not None and not isinstance(profile, str):
        raise ApplyError(f"{key} records profile as {profile!r}, which is not a profile name")
    address = record.get("address")
    if address is not None and not isinstance(address, str):
        raise ApplyError(f"{key} records address as {address!r}, which is not an address")
    return Entry(
        key=key,
        path=(root / _text(record, "path", of=key)).resolve(),
        realiser=_text(record, "realiser", of=key),
        profile=profile,
        machine=_text(record, "machine", of=key),
        address=address or None,
        units=_texts(record, "units", of=key),
    )


def _value(key: str, record: Mapping[str, Any]) -> Value:
    files = _mapping(record.get("files", {}), of=f"the files of {key}")
    program = record.get("program")
    if program is not None and not isinstance(program, str):
        raise ApplyError(f"{key} records program as {program!r}, which is not a store path")
    return Value(
        key=key,
        delivery=_texts(record, "delivery", of=key),
        program=program,
        files=tuple(_file(key, name, file) for name, file in sorted(files.items())),
    )


def _file(key: str, name: str, file: Any) -> ValueFile:
    record = _mapping(file, of=f"{key} file {name}")
    return ValueFile(
        name=name,
        path=_text(record, "path", of=f"{key}/{name}"),
        secrecy=_text(record, "secrecy", of=f"{key}/{name}"),
    )


def _rows(path: Path) -> tuple[Diagnostic, ...]:
    if not path.is_file():
        return ()
    rows = json.loads(path.read_text())
    if not isinstance(rows, list):
        raise ApplyError(f"{path} is not a list of diagnostics rows")
    return tuple(
        Diagnostic(
            id=str(row.get("id", "")),
            subject=str(row.get("subject", "")),
            severity=str(row.get("severity", "")),
            message=str(row.get("message", "")),
        )
        for row in rows
        if isinstance(row, dict)
    )


def _load(path: Path) -> Mapping[str, Any]:
    try:
        decoded = json.loads(path.read_text())
    except OSError as absent:
        raise ApplyError(f"{path} cannot be read: {absent}") from absent
    except json.JSONDecodeError as malformed:
        raise ApplyError(f"{path} is not readable as JSON: {malformed}") from malformed
    return _mapping(decoded, of=str(path))


def _mapping(value: Any, *, of: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ApplyError(f"{of} is {value!r}, which is not a record")
    return value


def _text(record: Mapping[str, Any], field: str, *, of: str) -> str:
    value = record.get(field)
    if not isinstance(value, str) or not value:
        raise ApplyError(f"{of} records {field} as {value!r}, and the command needs one")
    return value


def _texts(record: Mapping[str, Any], field: str, *, of: str) -> tuple[str, ...]:
    value = record.get(field, [])
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ApplyError(
            f"{of} records {field} as {value!r}, and the command needs a list of names"
        )
    return tuple(value)
