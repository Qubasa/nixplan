"""The order the command applies placed entries in.

The edges are the reads the plan resolved: `plan.<consumer>.reads.<slot>.entry`
names the provider's own plan key, and that is the only relation that says one
entry has to be activated before another. `dependsOn` is not it: a consumer's
`dependsOn` carries `machine:<name>@<hash>`, which is key provenance rather than
order.

Ties break by plan key sort order, so one deployment always walks one way. Two
instances wiring each other is a legal deployment, and its activation graph
genuinely has no first element, so a cycle is broken at the lowest key by sort
order and the edge that was ordered against is reported. Refusing would refuse a
deployment the library considers correct; silence would make a one-off startup
failure unexplainable.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class WalkResult:
    """The order to apply in, and the edges that order contradicts."""

    order: tuple[str, ...]
    broken: tuple[tuple[str, str], ...]


def walk(plan: Mapping[str, Any], keys: Iterable[str]) -> WalkResult:
    """Return the order ``keys`` are applied in, provider before consumer.

    Args:
        plan: The plan artifact, as read from its JSON.
        keys: The placed entry keys to apply.

    Returns:
        Every key once, in application order, with the provider-before-consumer
        edges the order had to contradict, provider first.
    """
    nodes = sorted(set(keys))
    providers = {node: set[str]() for node in nodes}
    for provider, consumer in edges(plan, nodes):
        providers[consumer].add(provider)

    order: list[str] = []
    broken: list[tuple[str, str]] = []
    remaining = list(nodes)
    while remaining:
        ready = [node for node in remaining if not providers[node]]
        if ready:
            chosen = ready[0]
        else:
            chosen = remaining[0]
            broken.extend((provider, chosen) for provider in sorted(providers[chosen]))
            providers[chosen].clear()
        remaining.remove(chosen)
        order.append(chosen)
        for node in remaining:
            providers[node].discard(chosen)
    return WalkResult(order=tuple(order), broken=tuple(broken))


def edges(plan: Mapping[str, Any], keys: Iterable[str]) -> tuple[tuple[str, str], ...]:
    """Return the provider-before-consumer edges among ``keys``, provider first.

    A slot the planner refused is absent from `reads`, so an absence is never an
    edge, and an edge onto a key outside ``keys`` is dropped: an entry this run
    does not apply cannot be applied before one it does.

    Args:
        plan: The plan artifact, as read from its JSON.
        keys: The placed entry keys under consideration.

    Returns:
        The edges, sorted by consumer then provider.
    """
    placed = set(keys)
    found: set[tuple[str, str]] = set()
    for consumer in sorted(placed):
        entry = plan.get(consumer)
        reads = entry.get("reads") if isinstance(entry, dict) else None
        if not isinstance(reads, dict):
            continue
        for slot in reads.values():
            provider = slot.get("entry") if isinstance(slot, dict) else None
            if isinstance(provider, str) and provider in placed and provider != consumer:
                found.add((provider, consumer))
    return tuple(sorted(found, key=lambda edge: (edge[1], edge[0])))
