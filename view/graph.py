"""The graph the view draws, and where every coordinate comes from.

The edges are the resolved reads the plan records and nothing else, read
through the command's own reading: one `order.Read` per slot whichever of the
two shapes recorded it, one edge per provider a read names, and a read
recorded in neither shape named rather than dropped in silence.

The layout is data. The column of an entry is the index of its strong
component in the order `order.walk` returns, which is already
provider-before-consumer; the row is plan key order within the column, which
no two cells share; a value is a cell in the column before its readers,
because a value is written before any entry is activated; and the cell size is
fixed, so a fleet renders a larger page rather than an unreadable one. Nothing
moves for any other reason, which is what makes two renders of one build
byte-equal.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import order
from errors import ApplyError
from manifest import Deployment

CELL_WIDTH = 236
CELL_HEIGHT = 58
COLUMN_GAP = 104
ROW_GAP = 26
MARGIN = 24
ENTRY = "entry"
VALUE = "value"


@dataclass(frozen=True)
class Slot:
    """One resolved read of one consumer, with the slot it was recorded under."""

    consumer: str
    slot: str
    read: order.Read


@dataclass(frozen=True)
class Unrecognised:
    """A resolved read recorded in neither shape, named by consumer and slot."""

    consumer: str
    slot: str
    said: str


@dataclass(frozen=True)
class Reading:
    """Every read of every placed entry, and the ones no shape recognised."""

    slots: tuple[Slot, ...]
    unrecognised: tuple[Unrecognised, ...]


@dataclass(frozen=True)
class Cell:
    """One box of the picture, placed by the build's own data."""

    key: str
    kind: str
    column: int
    row: int
    machine: str | None


def reading(deployment: Deployment) -> Reading:
    """Return every resolved read of every placed entry, slot by slot.

    Each slot is read on its own through `order.reads`, so the refusal for a
    shape the command does not recognise names that slot rather than ending
    the reading of the consumer it belongs to.

    Returns:
        The reads in consumer then slot order, and one record per slot
        recorded in neither shape carrying what the reading said about it.
    """
    slots: list[Slot] = []
    unrecognised: list[Unrecognised] = []
    for consumer in sorted(deployment.entries):
        recorded = _recorded(deployment.plan, consumer)
        for name in sorted(recorded):
            one = {consumer: {"reads": {name: recorded[name]}}}
            try:
                read = order.reads(one, consumer)[0]
            except ApplyError as refused:
                unrecognised.append(Unrecognised(consumer, name, str(refused)))
            else:
                slots.append(Slot(consumer, name, read))
    return Reading(tuple(slots), tuple(unrecognised))


def graph(deployment: Deployment) -> dict[str, Any]:
    """Return the graph document: the cells, the edges and the layout of both.

    Returns:
        The cell geometry, the columns as plan keys, one cell per placed entry
        and per generated value with its coordinates, one edge per provider a
        read names with the slot as its label and whether the order had to
        contradict it, the cycles the walk broke, and the reads recorded in a
        shape the view does not know.
    """
    read = reading(deployment)
    placed = set(deployment.entries)
    walked = order.walk(_projected(deployment, read.unrecognised), placed)
    columns = _columns(walked)
    cells = _cells(deployment, read, columns)
    at = {cell.key: cell for cell in cells}
    edges = _edges(read, placed) + _delivering(deployment, read, at)
    return {
        "cell": {
            "width": CELL_WIDTH,
            "height": CELL_HEIGHT,
            "columnGap": COLUMN_GAP,
            "rowGap": ROW_GAP,
            "margin": MARGIN,
        },
        "width": _extent(cells, CELL_WIDTH, COLUMN_GAP, lambda cell: cell.column),
        "height": _extent(cells, CELL_HEIGHT, ROW_GAP, lambda cell: cell.row),
        "columns": _by_column(cells),
        "cells": [_placed(cell) for cell in cells],
        "edges": [_edge(at, edge, walked.broken) for edge in edges],
        "cycles": [list(group) for group in walked.cycles],
        "unrecognised": [
            {"consumer": one.consumer, "slot": one.slot, "said": one.said}
            for one in read.unrecognised
        ],
    }


def _recorded(plan: Any, consumer: str) -> dict[str, Any]:
    """Return the resolved reads the plan records for one consumer."""
    entry = plan.get(consumer)
    recorded = entry.get("reads") if isinstance(entry, dict) else None
    return dict(recorded) if isinstance(recorded, dict) else {}


def _projected(deployment: Deployment, unrecognised: tuple[Unrecognised, ...]) -> dict[str, Any]:
    """Return the plan with the slots no shape recognised left out.

    The order is still the command's: the walk is handed a plan whose every
    remaining read it reads itself, rather than a set of edges this module
    computed for it.
    """
    plan = dict(deployment.plan)
    dropped: dict[str, set[str]] = {}
    for one in unrecognised:
        dropped.setdefault(one.consumer, set()).add(one.slot)
    for consumer, slots in dropped.items():
        record = dict(plan[consumer])
        record["reads"] = {
            name: read for name, read in _recorded(plan, consumer).items() if name not in slots
        }
        plan[consumer] = record
    return plan


def _columns(walked: order.WalkResult) -> dict[str, int]:
    """Return the column of every entry: the index of its strong component."""
    grouped = {key: group for group in walked.cycles for key in group}
    columns: dict[str, int] = {}
    seen: set[tuple[str, ...]] = set()
    column = -1
    for key in walked.order:
        group = grouped.get(key)
        if group is None or group not in seen:
            column += 1
        if group is not None:
            seen.add(group)
        columns[key] = column
    return columns


def _cells(deployment: Deployment, read: Reading, columns: dict[str, int]) -> tuple[Cell, ...]:
    """Return one cell per entry and per value, each in its column and row."""
    placed: dict[str, tuple[int, str, str | None]] = {
        key: (columns[key], ENTRY, entry.machine) for key, entry in deployment.entries.items()
    }
    readers = _readers(deployment, read)
    for key in deployment.values:
        into = [columns[consumer] for consumer, _ in readers.get(key, ()) if consumer in columns]
        placed[key] = (min(into, default=0) - 1, VALUE, None)
    offset = -min((column for column, _, _ in placed.values()), default=0)
    rows: dict[int, int] = {}
    cells: list[Cell] = []
    for key in sorted(placed):
        column, kind, machine = placed[key]
        at = column + offset
        row = rows.get(at, 0)
        rows[at] = row + 1
        cells.append(Cell(key=key, kind=kind, column=at, row=row, machine=machine))
    return tuple(cells)


def _readers(deployment: Deployment, read: Reading) -> dict[str, tuple[tuple[str, str], ...]]:
    """Return the consumer and slot of every resolved read naming each value's files."""
    owning = {file.path: key for key, value in deployment.values.items() for file in value.files}
    found: dict[str, set[tuple[str, str]]] = {}
    for slot in read.slots:
        for path in slot.read.paths:
            key = owning.get(path)
            if key is not None:
                found.setdefault(key, set()).add((slot.consumer, slot.slot))
    return {key: tuple(sorted(reading_it)) for key, reading_it in found.items()}


def _edges(read: Reading, placed: set[str]) -> tuple[tuple[str, str, str], ...]:
    """Return one edge per provider a read names, provider first.

    An edge onto an entry the build does not place is dropped and a read of an
    entry's own export is no edge, which is what the command's own edge set
    does with both.
    """
    found = {
        (provider, slot.consumer, slot.slot)
        for slot in read.slots
        for provider in slot.read.providers
        if provider in placed and provider != slot.consumer
    }
    return tuple(sorted(found, key=lambda edge: (edge[1], edge[0], edge[2])))


def _delivering(
    deployment: Deployment, read: Reading, at: dict[str, Cell]
) -> tuple[tuple[str, str, str], ...]:
    """Return one edge per value a placed entry's resolved read names."""
    found = {
        (key, consumer, slot)
        for key, readers in _readers(deployment, read).items()
        for consumer, slot in readers
        if key in at and consumer in at
    }
    return tuple(sorted(found, key=lambda edge: (edge[1], edge[0], edge[2])))


def _by_column(cells: tuple[Cell, ...]) -> list[list[str]]:
    """Return the plan keys of each column, in row order."""
    columns: dict[int, list[str]] = {}
    for cell in sorted(cells, key=lambda cell: (cell.column, cell.row)):
        columns.setdefault(cell.column, []).append(cell.key)
    return [columns[column] for column in sorted(columns)]


def _x(cell: Cell) -> int:
    return MARGIN + cell.column * (CELL_WIDTH + COLUMN_GAP)


def _y(cell: Cell) -> int:
    return MARGIN + cell.row * (CELL_HEIGHT + ROW_GAP)


def _placed(cell: Cell) -> dict[str, Any]:
    """Return one cell as the document carries it, coordinates included."""
    return {
        "key": cell.key,
        "kind": cell.kind,
        "machine": cell.machine,
        "column": cell.column,
        "row": cell.row,
        "x": _x(cell),
        "y": _y(cell),
        "width": CELL_WIDTH,
        "height": CELL_HEIGHT,
    }


def _extent(cells: tuple[Cell, ...], size: int, gap: int, of: Callable[[Cell], int]) -> int:
    """Return the page extent one axis needs for ``cells``."""
    return 2 * MARGIN + (max((of(cell) for cell in cells), default=-1) + 1) * (size + gap) - gap


def _edge(
    at: dict[str, Cell], edge: tuple[str, str, str], broken: tuple[tuple[str, str], ...]
) -> dict[str, Any]:
    """Return one edge as an SVG path from a provider's cell to a consumer's."""
    provider, consumer, slot = edge
    start, end = at[provider], at[consumer]
    x1, y1 = _x(start) + CELL_WIDTH, _y(start) + CELL_HEIGHT // 2
    x2, y2 = _x(end), _y(end) + CELL_HEIGHT // 2
    bend = COLUMN_GAP // 2
    return {
        "provider": provider,
        "consumer": consumer,
        "slot": slot,
        "contradicted": (provider, consumer) in broken,
        "path": f"M {x1} {y1} C {x1 + bend} {y1} {x2 - bend} {y2} {x2} {y2}",
        "labelX": (x1 + x2) // 2,
        "labelY": (y1 + y2) // 2 - 6,
    }
