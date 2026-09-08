## Why

The staging reference added to `state-subject` in `examples/firewall/` turned a collector from a leaf of the answer graph into an interior node: `modules/postgres/service.nix` hands the backup a unit reference, and a group snapshotter would hand it a real answer computed from a set it collected itself. Two rules that were correct while collectors were leaves are now wrong, and the composition of the two produces a runtime deadlock that no plan-time check in the current design can see.

The urgency is that the only thing preventing the deadlock today is an accident. `impl` is applied atomically (`examples/firewall/plan/diagnostics.txt`, the `x epsilon` row), so any real answer from a collector is treated as if it read the collected set, which refuses the deployment for a dependency that does not exist. The workaround an author would reach for — make the answer independent of the set — removes the accidental refusal and exposes the deadlock. Recording the two corrections now is cheaper than discovering them from a machine that failed to back itself up.

## What Changes

- **Round 7 becomes topological over collectors on a machine.** The single barrier ("every answerer's `impl`, then the collector's") is replaced by stratification of the per-machine answer graph. The existing rule that `nothing = true` is the only answer two collectors may exchange stops being an axiom and becomes a consequence: an empty answer carries no edge, so it cannot lie on a cycle.
- **Reflexive exclusion becomes transitive exclusion.** A collector is currently excluded only from the set it asks for. It must also be excluded from any participant-shaped set belonging to a collector whose staging unit it transitively requires, or a collector's own unit gets stopped by a unit it pulled in.
- **`order` becomes the fifth field on a collect slot.** A collector that must act on its members in dependency order cannot compute that order, because the wire graph is deployment knowledge. `order = "wire"` makes the planner deliver the set ordered, and it is the first collect field whose failure names no author.
- **A consistency group is one subject.** New `quiesce-participant` interface, and the rule that members of a group answer the group's owner rather than the backup, with the deployment silencing their direct answers.
- **Per-export dependency on `collected` is detectable, not declared.** Applying `impl` with a poisoned `collected` and forcing each export separately distinguishes a set-dependent answer from a static one, so the fine-grained round-7 edge needs no new spelling.
- New example folder `examples/quiesce-group/` demonstrating the group, the collector chain and the deadlock over one machine.
- New `§30` in `notes/clan-portable-services-design.md`, marked **DECIDED** and explicitly not adopted, following the `§25` convention.
- `pkgs/qubasa-blog/posts/07-reading-real-fleets.md` collector section updated: the backup row's residual is now specific, and the corpus's four collectors gain the chain case.
- **Not changing** `pkgs/qubasa-blog/posts/03-evaluation-order.md`. Its eight-round trace documents wired slots in the adopted design; collect slots exist in no tree, so the corrected round 7 has nothing to correct there yet.

No **BREAKING** changes: collect slots are a sketch, so nothing downstream depends on the rules being replaced.

## Capabilities

### New Capabilities

- `planner/collect-slots`: how the planner resolves a collect slot — membership and exclusion, the order in which a collected set is delivered, the stratification of `impl` application over collectors, the unit edges a staged answer makes the planner emit, and what each failure mode refuses versus rows. `openspec/specs/` is empty, so this change establishes the `planner/` grouping for the deployment planner's capabilities; later work on placement, allocation and key derivation belongs beside it.

### Modified Capabilities

None. `openspec/specs/` contains no specs today.

## Impact

**Design record**
- `notes/clan-portable-services-design.md` — new `§30`, needs a bead id assigned. Related open beads: `universe-zh5` (cardinality, gains the collector-chain case), `universe-l83.2` (manifest schema, gains the collect fields and the `requires` edge), `universe-xop` (would owe nothing once a function of the collected set replaces the `owned` readback).

**Examples**
- New `examples/quiesce-group/` in the established shape: `interfaces/`, `modules/`, `deployment/`, `plan/*.json`, `plan/diagnostics.txt`, `README.md`.
- `examples/firewall/README.md` — three entries in "What this folder does not answer" (consistency group, collector-as-subject, restore) become cross-references to the new folder rather than open questions.
- `examples/firewall/plan/diagnostics.txt` — the two `zeta` rows and the `x prod` refcount row move to the new folder, where the deployment that produces them exists.

**Blog**
- `pkgs/qubasa-blog/posts/07-reading-real-fleets.md` — collector section.

**Not affected**
- No project code. The planner does not exist; this change records decided behaviour and its worked demonstration.
- `pkgs/qubasa-blog/posts/03-evaluation-order.md`, and the "Part N of 7" series framing, which stays closed at seven.
