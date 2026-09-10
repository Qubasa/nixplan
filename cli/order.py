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

The order is the strong components of that graph, walked in the dependency order
between them. A component of one entry is an entry with an order; a component of
more is a cycle, which a legal deployment can carry, and its entries are applied
in plan key order with the edges pointing backwards in that order contradicted.
So exactly the edges on a cycle are contradicted, an entry that merely reads into
one keeps its order, and ties break by plan key sort order, which leaves one
deployment walking one way. Refusing a cycle would refuse a deployment the
library considers correct; silence would make a one-off startup failure
unexplainable.

A read whose provider this run is not applying is no edge, because an entry the
run does not apply cannot be applied first. It is announced instead, so that a
restricted run states the one read it cannot honour.
"""

from __future__ import annotations

import heapq
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any

from errors import ApplyError


@dataclass(frozen=True)
class WalkResult:
    """The order to apply in, the edges it contradicts, and where it broke."""

    order: tuple[str, ...]
    broken: tuple[tuple[str, str], ...]
    cycles: tuple[tuple[str, ...], ...]


def walk(plan: Mapping[str, Any], keys: Iterable[str]) -> WalkResult:
    """Return the order ``keys`` are applied in, provider before consumer.

    Args:
        plan: The plan artifact, as read from its JSON.
        keys: The placed entry keys to apply.

    Returns:
        Every key once in application order, the provider-before-consumer edges
        that order had to contradict with the provider first, and the entries of
        each cycle it was broken at.

    Raises:
        ApplyError: If a delivered read is recorded in a shape this walk does
            not recognise, or if the components cannot be ordered.
    """
    nodes = sorted(set(keys))
    forward: dict[str, list[str]] = {node: [] for node in nodes}
    for provider, consumer in edges(plan, nodes):
        forward[provider].append(consumer)
    applied = sequence(_components(nodes, forward), forward)
    order = tuple(node for group in applied for node in group)
    at = {node: position for position, node in enumerate(order)}
    broken = sorted(
        (
            (provider, consumer)
            for provider, consumers in forward.items()
            for consumer in consumers
            if at[provider] > at[consumer]
        ),
        key=lambda edge: (at[edge[1]], edge[0]),
    )
    return WalkResult(
        order=order,
        broken=tuple(broken),
        cycles=tuple(group for group in applied if len(group) > 1),
    )


def sequence(
    components: Sequence[tuple[str, ...]], forward: Mapping[str, Sequence[str]]
) -> tuple[tuple[str, ...], ...]:
    """Return ``components`` in application order, provider component first.

    Args:
        components: The strong components of the read graph, each in plan key
            order.
        forward: The provider-to-consumers adjacency they were computed from.

    Returns:
        Every component once, each one before every component that reads into
        it. Components neither of which reads into the other are ordered by
        their lowest plan key, which no two components share.

    Raises:
        ApplyError: If the components handed in read each other, naming the
            entries that could not be ordered and the reads between them. A
            condensation is acyclic, so no component computation reaches it.
    """
    place = {node: index for index, group in enumerate(components) for node in group}
    downstream: list[set[int]] = [set() for _ in components]
    waiting = [0] * len(components)
    for provider, consumers in forward.items():
        for consumer in consumers:
            group, reader = place[provider], place[consumer]
            if group != reader and reader not in downstream[group]:
                downstream[group].add(reader)
                waiting[reader] += 1
    ready = [(group[0], index) for index, group in enumerate(components) if not waiting[index]]
    heapq.heapify(ready)
    walked: list[tuple[str, ...]] = []
    while ready:
        index = heapq.heappop(ready)[1]
        walked.append(components[index])
        for reader in downstream[index]:
            waiting[reader] -= 1
            if not waiting[reader]:
                heapq.heappush(ready, (components[reader][0], reader))
    if len(walked) != len(components):
        raise ApplyError(_unordered(components, waiting, forward))
    return tuple(walked)


def _unordered(
    components: Sequence[tuple[str, ...]],
    waiting: Sequence[int],
    forward: Mapping[str, Sequence[str]],
) -> str:
    """Return the refusal for the components the walk could not order."""
    stuck = {node for index, group in enumerate(components) if waiting[index] for node in group}
    reads = sorted(
        f"{consumer} reads {provider}"
        for provider in stuck
        for consumer in forward[provider]
        if consumer in stuck
    )
    return (
        f"no entry of {', '.join(sorted(stuck))} can be applied before the others, "
        f"so the order the reads imply cannot be walked: {'; '.join(reads)}"
    )


def _components(
    nodes: Sequence[str], forward: Mapping[str, Sequence[str]]
) -> tuple[tuple[str, ...], ...]:
    """Return the strong components of the read graph, each in plan key order.

    Tarjan's algorithm, iterative because a fleet's graph is deeper than the
    interpreter's stack. The components come out in the reverse topological
    order of the condensation, which `sequence` does not rely on.

    Args:
        nodes: Every entry, in plan key order.
        forward: The provider-to-consumers adjacency.

    Returns:
        The components, each holding its entries in plan key order.
    """
    index: dict[str, int] = {}
    low: dict[str, int] = {}
    held: list[str] = []
    on: set[str] = set()
    found: list[tuple[str, ...]] = []
    for root in nodes:
        if root in index:
            continue
        work: list[tuple[str, int]] = [(root, 0)]
        while work:
            node, at = work[-1]
            if at == 0:
                low[node] = index[node] = len(index)
                held.append(node)
                on.add(node)
            consumers = forward[node]
            entered = None
            while at < len(consumers):
                consumer = consumers[at]
                at += 1
                if consumer not in index:
                    entered = consumer
                    break
                if consumer in on:
                    low[node] = min(low[node], index[consumer])
            work[-1] = (node, at)
            if entered is not None:
                work.append((entered, 0))
                continue
            work.pop()
            if low[node] == index[node]:
                found.append(_close(node, held, on))
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[node])
    return tuple(found)


def _close(root: str, held: list[str], on: set[str]) -> tuple[str, ...]:
    """Return the component ``root`` closes, taking its entries off ``held``."""
    group: list[str] = []
    while True:
        member = held.pop()
        on.discard(member)
        group.append(member)
        if member == root:
            return tuple(sorted(group))


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
    found = {
        (provider, consumer)
        for consumer in sorted(placed)
        for provider in _named(plan, consumer)
        if provider in placed and provider != consumer
    }
    return tuple(sorted(found, key=lambda edge: (edge[1], edge[0])))


def unsatisfied(
    plan: Mapping[str, Any], keys: Iterable[str], placed: Iterable[str]
) -> tuple[tuple[str, str], ...]:
    """Return the reads of ``keys`` whose provider this run is not applying.

    Args:
        plan: The plan artifact, as read from its JSON.
        keys: The placed entry keys to apply.
        placed: Every placed entry key of the deployment.

    Returns:
        One pair per read, consumer first, sorted, for a provider the
        deployment places and this run leaves out.

    Raises:
        ApplyError: If a delivered read is recorded in a shape this walk does
            not recognise, naming the consumer and the slot.
    """
    applying = set(keys)
    withheld = set(placed) - applying
    return tuple(
        sorted(
            {
                (consumer, provider)
                for consumer in sorted(applying)
                for provider in _named(plan, consumer)
                if provider in withheld
            }
        )
    )


def _named(plan: Mapping[str, Any], consumer: str) -> tuple[str, ...]:
    """Return every provider key the resolved reads of ``consumer`` name.

    Args:
        plan: The plan artifact, as read from its JSON.
        consumer: The entry whose reads to read.

    Returns:
        The provider keys, in slot order, empty for an entry that reads nothing.

    Raises:
        ApplyError: If a delivered read is recorded in a shape this walk does
            not recognise, naming the consumer and the slot.
    """
    entry = plan.get(consumer)
    reads = entry.get("reads") if isinstance(entry, dict) else None
    if not isinstance(reads, dict):
        return ()
    return tuple(
        provider for name in sorted(reads) for provider in _providers(reads[name], consumer, name)
    )


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
