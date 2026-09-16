## Why

The walk that orders an apply is Kahn's algorithm with an ad-hoc test for "is this entry on a cycle
nothing outside it feeds", and both halves cost more than the graph they read.

- **The acyclic path rescans the whole frontier per entry.** `cli/order.py:69` recomputes
  `[node for node in remaining if not providers[node]]` on every iteration and `:80-81` walks
  `remaining` again to discard the applied entry, so ordering `n` entries costs on the order of `n²`
  where the graph costs `n + m`. A 1000-entry fleet is a million comparisons to answer a question the
  edges already answer.
- **The cycle path is worse and unbounded by anything stated.** `_eligible`
  (`cli/order.py:85-102`) rebuilds the forward adjacency of the remaining subgraph and then calls
  `_reaches` (`:105-113`) once per candidate until one matches, which is `n·(n + m)` per call, and it
  can be entered once per remaining entry.
- **Its correctness rests on a docstring.** `cli/order.py:93-96` argues that a matching entry always
  exists: with nothing ready every remaining entry has a provider, so the subgraph holds a cycle, so
  some component nothing outside it feeds exists. The argument is sound for today's edge sources.
  It is enforced by nothing: `next(...)` at `:102` with no default raises a bare `StopIteration`,
  which is not `ApplyError`, so a future edge source that violates it ends a run with a traceback
  instead of a refusal. `cli/planner.py:209` catches `ApplyError` and nothing else.

What the walk computes is the condensation of the read graph: the entry it picks is a member of a
source strong component, and the edges it contradicts are exactly that component's internal edges
into that member. Naming the structure makes the cost linear and makes the report better: today
`cli/apply.py:278` prints one line per contradicted edge (`ordered against the read of A by B`)
and never says that A and B are on one cycle together, which is the fact an operator needs to know
that a one-off startup failure is expected and self-healing.

Separately, a restricted run is silent about the one thing it cannot honour. `cli/order.py:143` keeps
an edge only when the provider is in the selected set, so `planner apply --only <consumer>` activates
a consumer whose provider is not being applied and prints nothing, while a contradicted cycle edge is
printed. Both are "this read is not satisfied by this run"; only one is announced.

## What Changes

- **The order is computed from the graph's strong components.** The condensation is walked in
  dependency order, entries inside a component are ordered by plan key, and the only edges
  contradicted are edges inside a component. The order the command walks is unchanged for every
  deployment whose reads are acyclic, and unchanged for the mutual pairs the current walk already
  handles.
- **A broken cycle is reported as a cycle.** The report names the entries of the component and the
  edge or edges the order contradicted, so an operator can tell "these two read each other" from
  "this provider was left behind".
- **Ordering costs the graph.** The order is computed in time linear in the entries and the reads
  between them, and a deployment of a thousand entries orders without a per-entry rescan.
- **An impossible ordering state is a refusal.** If no entry is eligible - which no edge source in
  this tree can produce and a future one could - the command refuses naming the entries it could not
  order, rather than ending in an unhandled error.
- **A read the run cannot satisfy is announced.** A selected entry that reads a provider the run is
  not applying gets a line naming both, in the same place a contradicted edge gets one. The edge is
  still not an ordering constraint, so nothing about the order changes.

## Capabilities

### Modified Capabilities

- `operator/apply-command`: the eligibility rule for a cycle is stated as membership of a strong
  component; a broken cycle is reported as a component rather than as loose edges; the ordering cost
  is bounded by the graph; an unorderable state is a refusal; a read into an entry the run does not
  apply is announced.

## Impact

- `cli/order.py`: `walk`, `_eligible` and `_reaches` are replaced by a component computation plus a
  walk of the condensation. `edges` is unchanged, so which reads are edges is not this change's
  subject.
- `cli/apply.py:278`: the report of what the order contradicted, and the new line for a provider
  the run is not applying.
- `tests/e2e/test_harness.py`: the walk's tests gain the component report, the announcement under
  `--only`, and a scale case.
- `docs/operator.md`: what the two report lines mean and what an operator does about each.
- `openspec/changes/hold-every-stated-guarantee` states that every resolved read contributes its
  edges whatever its reach. This change is about how the resulting graph is walked and says nothing
  about which reads are edges; the two touch `cli/order.py` in different halves.
