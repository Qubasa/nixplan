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
VERSION = 3
STORE_VARIABLE = "NIX_STORE_DIR"
DEFAULT_STORE = "/nix/store"
SYSTEM = "system"
USER = "user"
SCOPES = (SYSTEM, USER)
HOLDINGS = "holdings"
MACHINES = "machines"
SEAL_RECIPIENT = "sealRecipient"


@dataclass(frozen=True)
class ValueFile:
    """One file a generated value declares, and what it is delivered as.

    `owner`, `group` and `mode` are the plan's, never this command's: the
    deployment's statement and the bytes on every machine cannot disagree if
    only one of them decides.

    ``sealed`` is where the machine keeps the copy it can open by itself. It is
    read off the record rather than derived from ``path``: the derivation is
    the library's, and this command imports nothing of it.
    """

    name: str
    path: str
    sealed: str
    secrecy: str
    owner: str
    group: str
    mode: str


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
    """A placed entry, with the artifact built for it and where it goes.

    An entry that declares no unit is realised into nothing, which the planner
    accepts, so the build publishes its record with no path at all. The absence
    is the record, not a null the reading has to refuse.

    ``digest`` is the identity the build published for the artifact, which is
    the identity a machine's own endpoint stores for it, so a report compares
    the two rather than recomputing either.
    """

    key: str
    path: Path | None
    realiser: str
    profile: str | None
    machine: str
    address: str | None
    units: tuple[str, ...]
    digest: str


@dataclass(frozen=True)
class Machine:
    """One machine a delivered value reaches, as the build recorded it.

    ``sealed`` is whether that machine's values are sealed to a recipient it
    declared, and ``path`` is the store path of the unsealer that opens them,
    absent for a machine that seals nothing. The recipient is not here: the
    plan's own machine record carries it, and a second copy in the build record
    would be a second answer a stale build could disagree with.
    """

    name: str
    sealed: bool
    scope: str
    path: Path | None


@dataclass(frozen=True)
class Diagnostic:
    """One row of a deployment's diagnostics."""

    id: str
    subject: str
    severity: str
    message: str


@dataclass(frozen=True)
class Realiser:
    """What the reading published about one realiser it was handed.

    ``scopes`` is what the realiser realises, which an entry's own scope is
    crossed against. ``holdings`` is what a machine's own answer names the
    things that realiser put there by, published as data: a nix pattern and a
    python pattern are two dialects, so one published pattern would be one rule
    with two readings.
    """

    name: str
    scopes: tuple[str, ...]
    holdings: Mapping[str, Any]

    def text(self, field: str) -> str:
        """Return one published holdings field that is a word.

        Raises:
            ApplyError: If the realiser publishes no such field, naming the
                realiser, the field and what it published.
        """
        stated = self.holdings.get(field)
        if not isinstance(stated, str) or not stated:
            raise self._unpublished(field, stated)
        return stated

    def number(self, field: str) -> int:
        """Return one published holdings field that is a count.

        Raises:
            ApplyError: If the realiser publishes no such field, naming the
                realiser, the field and what it published.
        """
        stated = self.holdings.get(field)
        if not isinstance(stated, int) or isinstance(stated, bool) or stated <= 0:
            raise self._unpublished(field, stated)
        return stated

    def _unpublished(self, field: str, stated: Any) -> ApplyError:
        return ApplyError(
            f"{MANIFEST} publishes realiser {self.name} with {HOLDINGS} {field} {stated!r}, and "
            f"the command reads what a machine's own answer names a holding by out of that field"
        )


@dataclass(frozen=True)
class Deployment:
    """A built deployment, as this command reads it.

    ``realisers`` is what the reading published about each realiser it knows:
    the scopes it realises, which the command crosses an entry's own scope
    against rather than deciding by the realiser's name, and what a machine's
    own answer names its holdings by.

    ``machines`` is the machines a delivered value reaches, which is not the
    machines the entries are placed on: a value's machine need run no entry.
    """

    root: Path
    plan: Mapping[str, Any]
    entries: Mapping[str, Entry]
    values: Mapping[str, Value]
    machines: Mapping[str, Machine]
    realisers: Mapping[str, Realiser]
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
    """Return the store nix resolves a path in: `NIX_STORE_DIR`, or the default store."""
    return os.environ.get(STORE_VARIABLE) or DEFAULT_STORE


def resolve(target: str) -> Path:
    """Resolve a target to the built deployment directory it names.

    A target is a directory holding `manifest.json`, or a flake reference.

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
    """Read the built deployment at ``root``, holding `manifest.json` and `plan.json`.

    Returns:
        The deployment: its plan, its value entries, the machines a value
        reaches, its diagnostics, and its placed entries with the store path
        each artifact resolves to. Resolving is load-bearing rather than tidy:
        the manifest addresses an artifact inside the build, the build is a
        farm of symlinks, and the path an activation names on the machine has
        to be the path the copy put there. A deployment carrying no diagnostics
        file carries no row.

    Raises:
        ApplyError: If a file is absent or unreadable, if the record states a
            version this command does not implement or a store it does not run
            against, if it carries no realisers table or a realiser of it publishes no scope
            or no holdings, if it carries no machines table, if the manifest states an
            entry without a field the command needs, naming both, or if it states an
            artifact path that lands outside the build, naming the entry and the path.
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
    machines = {
        name: _machine(root, name, _mapping(record, of=f"manifest machine {name}"))
        for name, record in sorted(_mapping(interface[MACHINES], of=MANIFEST).items())
    }
    realisers = {
        name: _published(name, _mapping(record, of=f"manifest realiser {name}"))
        for name, record in sorted(_mapping(interface["realisers"], of=MANIFEST).items())
    }
    return Deployment(
        root=root,
        plan=plan,
        entries=entries,
        values=values,
        machines=machines,
        realisers=realisers,
        diagnostics=_rows(root / ROWS),
        table=_read(root / TABLE),
    )


def address_of(entry: Entry) -> str:
    """Return the address to dial for one placed entry.

    No plan the planner emits carries a placed entry whose machine declares no
    address, and a record is an interface a caller may write by hand, so the
    reading carries the absence and the refusal is made here, where the machine
    would be reached.

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


def machine_recipient(deployment: Deployment, machine: str, *, of: str) -> str:
    """Return the public line the plan says that machine's copies are sealed to.

    A reader of its own beside `machine_address`, and for the same reason: a
    value's machine need run no entry, so the recipient is the plan's own
    `machine:<name>` record and never an entry's target. The field is present
    and null where no recipient is declared, so a record carrying neither is a
    record written before the field existed rather than a machine that seals
    nothing.

    Raises:
        ApplyError: If the plan carries no record for that machine, or the
            record states no recipient while the build record says that
            machine's values are sealed.
    """
    record = deployment.plan.get(f"{MACHINE_PREFIX}{machine}")
    if not isinstance(record, dict):
        raise ApplyError(f"the plan carries no {MACHINE_PREFIX}{machine} record for {of}")
    recipient = record.get(SEAL_RECIPIENT)
    if not isinstance(recipient, str) or not recipient:
        raise ApplyError(
            f"{MANIFEST} says the values of {machine} are sealed and the plan records "
            f"{SEAL_RECIPIENT} {recipient!r} for it, so {of} cannot be sealed"
        )
    return recipient


def machine_of(deployment: Deployment, machine: str, *, of: str) -> Machine:
    """Return what the build recorded about one machine a value reaches.

    Raises:
        ApplyError: If the record's table of the machines a value reaches does
            not name it, which is a record that cannot say whether that
            machine's copies are sealed.
    """
    stated = deployment.machines.get(machine)
    if stated is None:
        raise ApplyError(
            f"{MANIFEST} carries no {MACHINES} record for {machine}, which {of} is delivered to"
        )
    return stated


def machine_scope(deployment: Deployment, machine: str) -> str:
    """Return the scope the plan records for one machine.

    The planner writes `scope` into a machine record only where it is `user`,
    so a record stating none is a system-scope machine and reads as one.

    Raises:
        ApplyError: If the record states a scope outside the domain.
    """
    record = deployment.plan.get(f"{MACHINE_PREFIX}{machine}")
    stated = record.get("scope", SYSTEM) if isinstance(record, dict) else SYSTEM
    return _scope(stated, of=f"machine {machine}")


def entry_scope(deployment: Deployment, entry: Entry) -> str:
    """Return the scope one placed entry's steps on its machine are addressed in.

    The scope is the entry's own target's, which is what the artifact was built
    for, and it is crossed against the scopes the record publishes for the
    realiser that entry states rather than against the realiser's name.

    Raises:
        ApplyError: If the target states a scope outside the domain, if the
            record publishes no realiser of that name, or if the realiser
            publishes no such scope, naming the entry, the scope and what the
            realiser publishes.
    """
    record = deployment.plan.get(entry.key)
    target = record.get("target") if isinstance(record, dict) else None
    stated = target.get("scope", SYSTEM) if isinstance(target, dict) else SYSTEM
    scope = _scope(stated, of=f"the target of {entry.key}")
    published = deployment.realisers.get(entry.realiser)
    if published is None:
        raise ApplyError(
            f"{entry.key} states realiser {entry.realiser}, and the record publishes "
            f"{', '.join(sorted(deployment.realisers)) or 'no realiser at all'}"
        )
    if scope not in published.scopes:
        raise ApplyError(
            f"{entry.key} is placed on {entry.machine} in {scope} scope, and {entry.realiser} "
            f"realises {', '.join(published.scopes)}"
        )
    return scope


def artifact_of(entry: Entry) -> Path:
    """Return the store path the build's link for one placed entry resolves to.

    Raises:
        ApplyError: If the entry declares no unit, so the build published no
            artifact for it. The refusal names that entry and no other.
    """
    if entry.path is None:
        raise ApplyError(
            f"{entry.key} declares no unit, so the build published no artifact for it and this "
            f"step has nothing to take"
        )
    return entry.path


def service_name(entry: Entry) -> str:
    """Return the service name a flakelet artifact declares in its `meta.json`.

    Returns:
        The name the endpoint registers the entry under.

    Raises:
        ApplyError: If the artifact declares no name, or the entry has none.
    """
    return _declared(entry, "meta.json", "name", missing="declares no service name")


def unit_files(entry: Entry) -> dict[str, str]:
    """Return the store path of each unit file one flakelet artifact carries.

    The artifact is a farm of links, so a unit file is a store path of its own
    and it is the path the endpoint records for the generation it runs. That is
    what makes the two comparable: the machine reports the paths it activated
    and this reports the paths the build produced.

    Raises:
        ApplyError: If the entry has no artifact.
    """
    artifact = artifact_of(entry)
    return {unit: str((artifact / "units" / unit).resolve()) for unit in entry.units}


def image_file(entry: Entry) -> str:
    """Return the image file name `attachment.json` names, relative to the artifact.

    Raises:
        ApplyError: If the attachment names no image.
    """
    return _declared(entry, "attachment.json", "image", missing="names no image")


def _declared(entry: Entry, file: str, field: str, *, missing: str) -> str:
    """Return one field of an entry's own artifact record, in the caller's words.

    Raises:
        ApplyError: If the record states no such name, naming the entry and the
            file it was read from.
    """
    artifact = artifact_of(entry)
    stated = _load(artifact / file).get(field)
    if not isinstance(stated, str) or not stated:
        raise ApplyError(f"{entry.key}: {artifact}/{file} {missing}")
    return stated


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
    if "realisers" not in interface:
        raise ApplyError(
            f"{path} carries no realisers table, and the command reads the scopes a realiser "
            f"realises out of it rather than assuming them"
        )
    if MACHINES not in interface:
        raise ApplyError(
            f"{path} carries no {MACHINES} table, and an absent table is not a fleet whose "
            f"machines seal nothing: this is not a record the command can read"
        )


def _published(name: str, record: Mapping[str, Any]) -> Realiser:
    """Return what one realiser published: the scopes it realises and its holdings.

    Raises:
        ApplyError: If it publishes no scope, or no holdings table. A realiser
            publishing none could attribute nothing a machine answered, and a
            holding nothing attributes reads as nothing to retire.
    """
    scopes = _texts(record, "scopes", of=f"realiser {name}")
    if not scopes:
        raise ApplyError(
            f"{MANIFEST} publishes realiser {name} with no scope, and a realiser that realises "
            f"nothing is not one an entry can state"
        )
    holdings = record.get(HOLDINGS)
    if not isinstance(holdings, dict) or not holdings:
        raise ApplyError(
            f"{MANIFEST} publishes realiser {name} with {HOLDINGS} {holdings!r}, and the command "
            f"reads what a machine's own answer names a holding of it by out of that table"
        )
    return Realiser(name=name, scopes=scopes, holdings=holdings)


def _scope(stated: Any, *, of: str) -> str:
    """Return one stated scope, or refuse naming what was stated and the domain."""
    for scope in SCOPES:
        if stated == scope:
            return scope
    raise ApplyError(f"{of} records scope {stated!r}, and a scope is {' or '.join(SCOPES)}")


def _entry(root: Path, key: str, record: Mapping[str, Any]) -> Entry:
    profile = record.get("profile")
    if profile is not None and not isinstance(profile, str):
        raise ApplyError(f"{key} records profile as {profile!r}, which is not a profile name")
    address = record.get("address")
    if address is not None and not isinstance(address, str):
        raise ApplyError(f"{key} records address as {address!r}, which is not an address")
    stated = record.get("path")
    if stated is not None and not (isinstance(stated, str) and stated):
        raise ApplyError(f"{key} records path as {stated!r}, which is not a path in the build")
    return Entry(
        key=key,
        path=None if stated is None else _artifact(root, key, stated),
        realiser=_text(record, "realiser", of=key),
        profile=profile,
        machine=_text(record, "machine", of=key),
        address=address or None,
        units=_texts(record, "units", of=key),
        digest=_text(record, "key", of=key),
    )


def _machine(root: Path, name: str, record: Mapping[str, Any]) -> Machine:
    sealed = record.get("sealed")
    if not isinstance(sealed, bool):
        raise ApplyError(
            f"machine {name} records sealed as {sealed!r}, and the command reads whether that "
            f"machine's values are sealed out of it"
        )
    stated = record.get("path")
    if stated is not None and not (isinstance(stated, str) and stated):
        raise ApplyError(f"machine {name} records path as {stated!r}, which is not a path")
    if sealed and stated is None:
        raise ApplyError(f"machine {name} records sealed values and no unsealer to open them with")
    return Machine(
        name=name,
        sealed=sealed,
        scope=_scope(record.get("scope", SYSTEM), of=f"machine {name}"),
        path=None if stated is None else _artifact(root, f"machine {name}", stated),
    )


def _artifact(root: Path, key: str, stated: str) -> Path:
    """Return the store path one stated artifact path resolves to inside the build.

    Containment is decided by where the path lands and not by what is there, so
    it is settled on the joined path with its `..` components collapsed and
    before any link is followed: the build is a farm of symlinks, and every one
    of them points at a store path outside the build by design, so following
    them first would answer that no artifact is inside the build at all.

    Returns:
        The store path the build's link for that entry resolves to, which is the
        path the copy puts on the machine and the activation names there.

    Raises:
        ApplyError: If the path lands outside the build, whether it is stated
            as an absolute location or climbs out of the build with `..`.
    """
    inside = Path(os.path.abspath(root))
    landed = Path(os.path.abspath(inside / stated))
    if not landed.is_relative_to(inside):
        raise ApplyError(
            f"{key} records path {stated!r}, which lands at {landed} and outside the build "
            f"{inside}: a manifest addresses an artifact inside the build it was read from"
        )
    return (root / stated).resolve()


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
    at = f"{key}/{name}"
    return ValueFile(
        name=name,
        path=_text(record, "path", of=at),
        sealed=_text(record, "sealed", of=at),
        secrecy=_text(record, "secrecy", of=at),
        owner=_text(record, "owner", of=at),
        group=_text(record, "group", of=at),
        mode=_text(record, "mode", of=at),
    )


def _rows(path: Path) -> tuple[Diagnostic, ...]:
    if not path.is_file():
        return ()
    rows = _decoded(path)
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


def _read(path: Path) -> str:
    """Return the text of one file inside the build, or refuse naming it.

    A build this command reads is a directory the operator named, so its bytes
    are not guaranteed to be the bytes a build wrote. Text that is not UTF-8
    raises a `UnicodeDecodeError`, which is a `ValueError` and not a
    `JSONDecodeError`, so decoding is guarded here rather than at each caller.
    """
    if not path.is_file():
        return ""
    try:
        return path.read_text()
    except OSError as absent:
        raise ApplyError(f"{path} cannot be read: {absent}") from absent
    except ValueError as malformed:
        raise ApplyError(f"{path} is not readable as text: {malformed}") from malformed


def _decoded(path: Path) -> Any:
    """Return what one file inside the build decodes to, or refuse naming it."""
    try:
        return json.loads(path.read_text())
    except OSError as absent:
        raise ApplyError(f"{path} cannot be read: {absent}") from absent
    except ValueError as malformed:
        raise ApplyError(f"{path} is not readable as JSON: {malformed}") from malformed


def _load(path: Path) -> Mapping[str, Any]:
    return _mapping(_decoded(path), of=str(path))


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
