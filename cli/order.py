"""The order the command applies placed entries in.

The edges are the reads the plan resolved. A read of one entry records the
provider's own plan key at `plan.<consumer>.reads.<slot>.entry`; a read of every
entry that provides the capability records them as `entries`, keyed by plan key.
Both are the same relation and both are ordered against. `dependsOn` is not it:
a consumer's `dependsOn` carries `machine:<name>@<hash>`, which is key
provenance rather than order.

A delivered read recorded in neither shape is a refusal rather than zero edges:
an unrecognised shape that contributed nothing silently is what let every
set-valued read go unordered.

Ties break by plan key sort order, so one deployment always walks one way. Two
instances wiring each other is a legal deployment, and its activation graph
genuinely has no first element, so an edge is contradicted. Only an edge on a
cycle is: the entry the walk takes there is one every unapplied provider of
which is reachable from it, so provider and consumer sit on one cycle, and an
entry that merely reads into a cycle keeps its order. Refusing would refuse a
deployment the library considers correct; silence would make a one-off startup
failure unexplainable.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from typing import Any

from errors import ApplyError


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

        With an entry ready, the lowest by key sort order is taken, except that
        a provider a contradicted edge left behind is taken first: the consumer
        already ran without it. With none ready, the entries whose every
        unapplied provider is reachable from the entry itself are the eligible
        ones, the lowest of those by key sort order is taken, and exactly the
        edges into it from its own unapplied providers are contradicted.
    """
    nodes = sorted(set(keys))
    providers = {node: set[str]() for node in nodes}
    for provider, consumer in edges(plan, nodes):
        providers[consumer].add(provider)

    order: list[str] = []
    broken: list[tuple[str, str]] = []
    owed: set[str] = set()
    remaining = list(nodes)
    while remaining:
        ready = [node for node in remaining if not providers[node]]
        if ready:
            chosen = next((node for node in ready if node in owed), ready[0])
        else:
            chosen = _eligible(remaining, providers)
            broken.extend((provider, chosen) for provider in sorted(providers[chosen]))
            owed |= providers[chosen]
            providers[chosen].clear()
        remaining.remove(chosen)
        owed.discard(chosen)
        order.append(chosen)
        for node in remaining:
            providers[node].discard(chosen)
    return WalkResult(order=tuple(order), broken=tuple(broken))


def _eligible(remaining: list[str], providers: Mapping[str, set[str]]) -> str:
    """Return the entry whose incoming edges the walk contradicts.

    Args:
        remaining: The entries still to apply, in key sort order.
        providers: The unapplied providers of each of them.

    Returns:
        The lowest entry every unapplied provider of which it reaches forward.
        One exists whenever no entry is ready: every remaining entry then has a
        provider, so the graph holds a cycle, and every entry of a component
        nothing outside it provides into is eligible.
    """
    forward: dict[str, set[str]] = {node: set() for node in remaining}
    for consumer in remaining:
        for provider in providers[consumer]:
            forward[provider].add(consumer)
    return next(node for node in remaining if providers[node] <= _reaches(node, forward))


def _reaches(start: str, forward: Mapping[str, set[str]]) -> set[str]:
    seen: set[str] = set()
    stack = [start]
    while stack:
        for consumer in forward[stack.pop()]:
            if consumer not in seen:
                seen.add(consumer)
                stack.append(consumer)
    return seen


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

    Raises:
        ApplyError: If a delivered read is recorded in a shape this walk does
            not recognise, naming the consumer and the slot.
    """
    placed = set(keys)
    found: set[tuple[str, str]] = set()
    for consumer in sorted(placed):
        entry = plan.get(consumer)
        reads = entry.get("reads") if isinstance(entry, dict) else None
        if not isinstance(reads, dict):
            continue
        for name in sorted(reads):
            for provider in _providers(reads[name], consumer, name):
                if provider in placed and provider != consumer:
                    found.add((provider, consumer))
    return tuple(sorted(found, key=lambda edge: (edge[1], edge[0])))


def _providers(slot: Any, consumer: str, name: str) -> tuple[str, ...]:
    """Return the plan keys one resolved read names as providers.

    Args:
        slot: The read record, `plan.<consumer>.reads.<name>`.
        consumer: The entry that declared the read, for the refusal.
        name: The slot's name, for the refusal.

    Returns:
        The provider keys, empty for a read the planner did not deliver.

    Raises:
        ApplyError: If the read was delivered and records its providers in
            neither shape the plan uses.
    """
    if not isinstance(slot, dict):
        return ()
    one = slot.get("entry")
    if isinstance(one, str):
        return (one,)
    every = slot.get("entries")
    if isinstance(every, dict) and all(isinstance(key, str) for key in every):
        return tuple(sorted(every))
    if not slot.get("delivered"):
        return ()
    raise ApplyError(
        f"{consumer} reads {name} as a resolved slot recorded in a shape the order "
        "does not recognise: it names its providers by neither entry nor entries"
    )
