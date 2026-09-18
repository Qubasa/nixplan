"""The documents the view answers about one built deployment.

One document per question, each a function of what the build wrote and of
nothing else: the machines and the entries placed on them, the values with
their delivery sets and their files, and the diagnostics rows with all six
fields. No document here dials a machine, resolves a path or runs a program,
so a view of a deployment whose machines are all switched off is complete.

A field the build did not record is `None` rather than an empty value, the way
the reading the command already does carries it: an entry realised into
nothing holds no artifact, and a machine the build recorded nothing about is
not a machine that seals nothing.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

import manifest
from manifest import Deployment, Diagnostic, Entry, Value

MACHINE_PREFIX = "machine:"
REFUSED = "the planner refused this deployment, so no entry was realised"
UNREALISED = "this deployment was realised into no entry"


def machines(deployment: Deployment) -> dict[str, Any]:
    """Return the machines the build names, with the entries placed on each.

    Returns:
        One record per machine the build names anywhere - placed on, delivered
        to, or declared in the plan - each carrying its address, its scope, its
        sealing and the entries of that machine in plan key order.
    """
    placed: dict[str, list[Entry]] = {}
    for _, entry in sorted(deployment.entries.items()):
        placed.setdefault(entry.machine, []).append(entry)
    names = sorted(set(placed) | set(deployment.machines) | set(_declared(deployment)))
    return {"machines": [_machine(deployment, name, placed.get(name, ())) for name in names]}


def values(deployment: Deployment) -> dict[str, Any]:
    """Return the generated values, their delivery sets and their files.

    Returns:
        One record per value entry in plan key order, carrying the machines it
        is delivered to and each declared file's path, sealed path, secrecy,
        ownership and mode. No record carries a byte of any value: the plan
        holds a generated value's path and never its content.
    """
    return {"values": [_value(value) for _, value in sorted(deployment.values.items())]}


def diagnostics(deployment: Deployment) -> dict[str, Any]:
    """Return every diagnostics row the build published, with all six fields.

    Returns:
        The rows as the build recorded them, the rendered table beside them,
        how many entries were realised, and the statement a reader of a refused
        deployment needs: a build the planner refused carries its rows and no
        entry at all, which is a fact about the deployment rather than a reason
        to answer nothing.
    """
    return {
        "rows": [_row(row) for row in deployment.diagnostics],
        "table": deployment.rendered,
        "realised": len(deployment.entries),
        "refused": bool(deployment.errors),
        "statement": _statement(deployment),
    }


def _statement(deployment: Deployment) -> str:
    """Return what the build's own rows say about what it realised."""
    if deployment.entries:
        return f"{len(deployment.entries)} entries were realised"
    return REFUSED if deployment.errors else UNREALISED


def _declared(deployment: Deployment) -> tuple[str, ...]:
    """Return the machines the plan declares a record for."""
    return tuple(
        key.removeprefix(MACHINE_PREFIX)
        for key in deployment.plan
        if key.startswith(MACHINE_PREFIX)
    )


def _record(deployment: Deployment, machine: str) -> dict[str, Any]:
    """Return the plan's own record of one machine, empty where it declares none."""
    stated = deployment.plan.get(f"{MACHINE_PREFIX}{machine}")
    return dict(stated) if isinstance(stated, dict) else {}


def _machine(deployment: Deployment, name: str, entries: Sequence[Entry]) -> dict[str, Any]:
    """Return one machine's record, with the entries placed on it."""
    stated = deployment.machines.get(name)
    record = _record(deployment, name)
    # The planner writes `scope` into a machine record only where it is `user`,
    # so a record stating none is a system-scope machine and reads as one.
    scope = stated.scope if stated is not None else _word(record, "scope") or manifest.SYSTEM
    return {
        "name": name,
        "address": _word(record, "address"),
        "scope": scope,
        "sealed": stated.sealed if stated is not None else None,
        "unsealer": str(stated.path) if stated is not None and stated.path is not None else None,
        "entries": [_entry(entry) for entry in entries],
    }


def _word(record: dict[str, Any], field: str) -> str | None:
    """Return one field of a plan record where it is a word, and `None` otherwise."""
    stated = record.get(field)
    return stated if isinstance(stated, str) else None


def _entry(entry: Entry) -> dict[str, Any]:
    """Return one placed entry, holding no artifact where it was realised into nothing."""
    return {
        "key": entry.key,
        "realiser": entry.realiser,
        "profile": entry.profile,
        "machine": entry.machine,
        "address": entry.address,
        "units": list(entry.units),
        "digest": entry.digest,
        "artifact": str(entry.path) if entry.path is not None else None,
        "realised": entry.path is not None,
    }


def _value(value: Value) -> dict[str, Any]:
    """Return one generated value, its delivery set and its files."""
    return {
        "key": value.key,
        "program": value.program,
        "delivery": list(value.delivery),
        "files": [
            {
                "name": file.name,
                "path": file.path,
                "sealed": file.sealed,
                "secrecy": file.secrecy,
                "owner": file.owner,
                "group": file.group,
                "mode": file.mode,
            }
            for file in value.files
        ],
    }


def _row(row: Diagnostic) -> dict[str, str]:
    """Return one diagnostics row with every field its producer built it with."""
    return {
        "id": row.id,
        "subject": row.subject,
        "severity": row.severity,
        "message": row.message,
        "evidence": row.evidence,
        "resolution": row.resolution,
    }
