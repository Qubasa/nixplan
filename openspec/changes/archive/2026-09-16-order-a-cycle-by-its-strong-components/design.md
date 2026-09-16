## Context

See proposal.md - Why. The relevant shape of the current walk (`cli/order.py:59-113`):

- `providers` maps a consumer to its unapplied providers; the loop takes the lowest-keyed entry with
  none, preferring one that a contradicted edge left `owed`.
- With nothing ready, `_eligible` picks the lowest entry every unapplied provider of which it reaches
  forward, contradicts exactly the edges into it, and clears them.
- `edges` (`:116-145`) is the only edge source: the provider keys a resolved read names, filtered to
  the selected set, excluding self-reads.

The entry `_eligible` picks is, by construction, a member of a strong component of the remaining
subgraph that nothing outside the component reads into. The walk therefore already implements a
condensation walk; it computes the components implicitly, once per candidate, by reachability.

## Goals / Non-Goals

**Goals:**

- Make the structure explicit, so the cost is the graph's and the report can name a cycle.
- Keep the walked order byte-identical for every deployment whose reads are acyclic, and for the
  mutual pairs the current tests pin.
- Keep the edge source untouched, so this change and `hold-every-stated-guarantee` do not
  disagree about which reads are edges.

**Non-Goals:**

- No change to which reads are edges. That is `hold-every-stated-guarantee`'s subject.
- No refusal of a cyclic deployment. The planner accepts one, so the command applies one.
- No parallelism. Components give a legal parallel schedule, and the command stays serial; the
  channel, the failure model and the report are all serial today and changing that is a separate
  change with its own risks.
- No ordering edge from a value write. Values are written before any entry is activated, which is
  already stated and is not part of the graph.

## Decisions

### Tarjan's components plus a walk of the condensation

Compute the strong components of the read graph once, in one pass, then walk the condensation:

1. Components in reverse topological order of the condensation give the order components are applied
   in. Ties between independent components break by the lowest plan key in each, so the walk stays
   deterministic and matches today's tie-break.
2. Inside a component of one entry, nothing is contradicted. Inside a component of more than one, the
   entries are applied in plan-key order and the contradicted edges are exactly the edges of the
   component that point backwards in that order.

Cost is `O(n + m)` for the components, `O(n log n)` for the key ordering, and one pass to emit.

Alternatives considered:

- **`graphlib.TopologicalSorter`.** Rejected as the whole answer: it raises `CycleError` and gives no
  way to proceed, and the command must proceed because the planner accepts a mutual pair. It is
  usable over the condensation, where by construction no cycle remains, but the condensation walk it
  would replace is a dozen lines and would then need its own key tie-break layered on top through
  `static_order`, which does not offer one.
- **Keep the current walk and memoise `_reaches`.** Rejected: it removes one factor and leaves the
  frontier rescan, the implicit invariant and the loose-edge report.
- **Refuse a cycle.** Rejected: it would refuse a deployment the library considers correct, which the
  existing requirement forbids.

### Which edges a component contradicts

Today the walk contradicts every unapplied provider edge into the chosen entry. Inside a component
ordered by plan key, the equivalent statement is: every edge from a later entry to an earlier one.
For a two-entry mutual pair the two rules produce the same single edge, which is what
`tests/e2e/test_harness.py` pins. For a three-entry cycle the component rule contradicts exactly the
one edge that closes the cycle, where the current walk contradicts every edge into its chosen entry;
the component rule is the smaller and better-explained set, and the report names the component either
way.

### The report gains a cycle line and keeps the edge lines

`cli/apply.py:278` keeps printing one line per contradicted edge, because that is the line an
operator matches against a unit that failed once at startup. A line naming the component is printed
above them. Two lines rather than one enriched line, because the edge lines are what
`tests/e2e/wired-pair` already reads.

### An unorderable state refuses

The component walk cannot reach one: a condensation is acyclic, so a source component always exists.
The refusal is therefore unreachable code by construction, and it is still written, because the
current code's equivalent position is a bare `next(...)` whose failure is a `StopIteration`
traceback. A refusal costs one line and turns a future edge source's bug into a message naming the
entries.

### The scale scenarios are measured, not asserted asymptotically

A test cannot assert an asymptotic bound. The two scale scenarios build a thousand-entry chain and a
thousand-entry chain with one mutual pair, and assert the walk returns the expected order within a
wall-clock bound generous enough not to be flaky and tight enough to fail a quadratic walk by orders
of magnitude. The current walk on a thousand-entry chain performs on the order of `10⁶` set
operations, so the separation is large.

## Risks / Trade-offs

- **A three-or-more-entry cycle changes which edges are reported.** → It is a strictly smaller and
  correctly-explained set, no such fixture exists in the tree, and the requirement states the rule.
  The pinned two-entry case is unchanged.
- **A wall-clock bound in a test can be flaky on a loaded machine.** → The bound is chosen at least
  an order of magnitude above the linear implementation's cost and at least an order of magnitude
  below the quadratic one's, and the assertion is on the returned order first, so a slow machine
  fails a timing bound and not a correctness one.
- **The announcement under `--only` adds output to a run an operator repeats often.** → One line per
  unsatisfied read, printed only when the selection actually drops a provider, and silent for a full
  apply.
