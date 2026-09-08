## Context

See `proposal.md` — Why. Requirements are in `specs/planner/collect-slots/spec.md`; this document covers how they are arrived at and where they get written down.

Three constraints shape everything below.

The planner does not exist. `notes/clan-portable-services-design.md` is the authority, the `examples/*` folders are its worked demonstrations, and `pkgs/qubasa-blog/posts/` is the public rendering. So "implementation" here means writing a decision down in three places that must not disagree.

Collect slots are not adopted. Every example folder that uses them opens by saying so (`examples/firewall/README.md:3-10`). A correction to an unadopted mechanism cannot be adopted either, which is why the design record is `DECIDED` and why `posts/03-evaluation-order.md` is untouched — its eight-round trace documents wired slots, and round 7 there has nothing yet to correct.

The two corrections are one computation. Transitive exclusion needs the transitive closure of "which contributed units do I pull in", and that closure is a labelled sub-relation of the answer graph that stratification needs anyway. Splitting them into two changes would mean building the graph twice and would let the worse half ship alone.

## Goals / Non-Goals

**Goals:**

- One authority for the corrected rules, cited by the example and the blog rather than restated by them.
- A worked deployment in which the deadlock is visible as plan data, because the two-graph composition is not believable as prose.
- The firewall folder keeps its thesis and its census stays arithmetically true after rows move out of it.

**Non-Goals:**

- Adopting collect slots. Nothing in this change removes a disclaimer header or retires an open bead.
- Specifying the unit graph as a manifest object. `requires`, `after` and the stop edge remain interpolated strings; making them data is `universe-l83.2` and strictly larger. This change specifies the edges the planner *emits*, not a representation that would let it check edges an author wrote into a shell string.
- Extending the blog series. It is closed at seven parts and every post's footer says so.
- Naming a severity for any new row from a module. `consequence` stays the only severity input a module author supplies.

## Decisions

### Exclusion is computed before stratification, not after

The order is forced rather than chosen. Exclusion removes answer-graph edges, and removing edges changes strata — on the worked machine it is the difference between a two-cycle that refuses the plan and a three-stratum sort that succeeds. So the pipeline is: resolve membership from placement, label the edges that carry unit references, compute exclusions over the labelled closure, then stratify.

*Alternative considered: build the plan, then cycle-check the unit graph at manifest assembly.* Rejected on three grounds. It fires late, after keys are derived. Its diagnostic names units rather than declarations, so the reader has to work backwards to a declaration they may not have written. And it would refuse a deployment in which every declaration is individually correct — the failure is a property of the combination, which is the planner's product and nobody's authored mistake. Prevention by construction is the same argument the design already used to make the `owned.firewall` readback unspellable rather than detected.

### Per-export set dependence is detected, not declared

An export of a collector that reads nothing from the collected set carries no real dependency, and treating `impl` as atomic is what makes the current rule refuse a correct deployment. Nix laziness settles it without new syntax: apply `impl` with `collected` bound to a value that throws, force each export separately, and the exports that survive are set-independent.

*Alternative considered: a second contribution shape that puts exports in the asking half.* Rejected. It gives one concept two spellings, and the asking half is already where `nothing = true` lives — a contribution that is empty and a contribution that is static would sit side by side and read the same while meaning different things. Detection also degrades safely: a false negative puts an entry one stratum later than necessary, which costs an ordering and never correctness.

### `order` is a field on the slot, not a sort inside the collector

A collector that must act on its members in dependency order cannot compute that order, because the wire graph is deployment knowledge and a module may not read it.

*Alternative considered: hand modules the projected slot graph.* Rejected for the reason `from.peers` replaced `from = "mesh:vpn-core"` — a module holding a deployment's structure is the defect that example exists to fix. Making it a field also puts the failure where it belongs: a cycle in the projection is refused by the planner, and no module or wire entry is named, which is a new row shape the spec has to state explicitly because every other row in the design names an author.

Determinism is part of the requirement rather than an implementation nicety. The order is interpolated into a unit's command, so an unstable tie-break re-keys the collector and everything downstream of it on every plan.

### A consistency group is a group owner that collects, not an interposition primitive

Members answer the owner's participation question; the owner answers the outer question once, for the group. This is what makes the chain — services, then owner, then backup — and therefore what makes stratification compulsory rather than a tidiness.

*Alternatives considered.* A relation between interfaces, so that answering the participation question discharges the obligation to answer the outer one: rejected, it puts knowledge of one question inside another and the unanswered check would need a graph over interfaces. A suppression primitive letting a service claim members and mute them: rejected as three new mechanisms where the deployment already has one — `answers.<q>.nothing = true` says "this instance has nothing to say about that question", and the fleet is the party that knows its own machine has a group owner.

What is genuinely new is one check, not a mechanism: the set the deployment silenced must equal the set the owner claimed. Both sides are already in the plan. Getting it wrong in one direction double-reads a subject with one copy torn; in the other it drops a subject from every copy with a clean plan. Both are silent, so both are error rows.

### `DECIDED`, not `ADOPTED`, and what follows from that

`§30` follows the `§25` convention: a numbered section with a status and a bead. The status decides the rest of the change. `ADOPTED` would mean retiring the disclaimer in five example READMEs, adding a stratum pass to the blog's eight-round trace, and removing post 7's "exists in no tree" framing — a much larger change that also asserts more than has been demonstrated. `DECIDED` says the rules are settled and the mechanism they belong to is not.

### A new example folder rather than extending the firewall one

*Alternative considered: add the group, the snapshotter and a second collector to `examples/firewall/`.* Rejected. That folder's thesis is the rule question, its README derives a census from it in several places, and its `plan/diagnostics.txt` header states counts that would all move. The new folder also gets a second machine so that the group case and the no-group control sit side by side, which the firewall deployment has no room for.

Rows move rather than being duplicated: the two `zeta` rows and the `x prod` refcount row leave the firewall folder for the folder whose deployment actually produces them, and the firewall folder's "What this folder does not answer" entries become cross-references. Duplicated rows would drift.

### The blog gets a paragraph, not a post

Post 7's collector section already frames the mechanism as a sketch and already carries a four-row table whose backup row says "state silently not backed up". That residual is now specific — a subject the collector cannot read, a group it cannot make consistent, and a chain it cannot order — so the honest edit is to sharpen that row and add the chain case beside it. A new post would reopen a closed series and would front-run adoption.

## Risks / Trade-offs

- **The spec describes a planner that does not exist, so it can drift from the notes.** → `§30` cites the spec path, and the archive step moves the delta into `openspec/specs/planner/collect-slots/spec.md`, making one file the thing both the notes and the example point at.
- **Hand-written plan JSON in the new folder can contradict the spec it is meant to demonstrate.** → A task cross-walks every spec scenario to a row in `plan/diagnostics.txt` or a field in a plan file, and records the scenarios the example deliberately does not exercise.
- **The firewall folder's counts break when rows move out.** → The census is stated in three places (README manifest line, README section prose, diagnostics header). A task re-derives all three from the files rather than adjusting them by hand.
- **Establishing a `planner/` spec grouping with one capability may turn out wrong.** → Cheapest moment to be wrong is now, with `openspec/specs/` empty; moving one directory later costs nothing.
- **Detection of set dependence by lazy poisoning is a technique, not a guarantee.** → It is specified as behaviour ("an export that does not read the set carries no edge") so a different mechanism can satisfy it. A false negative costs an unnecessary stratum, never a missed cycle, which is the safe direction.
- **The prevented deadlock is only the class the planner generates.** → Stated as a non-goal and recorded in the new folder's residuals, so the guarantee is not read as wider than it is.

## Migration Plan

No deployed artifact and no rollback surface. There is a required order, because each step is the authority for the next:

1. `§30` in the design notes, with the spec path cited.
2. `examples/quiesce-group/`, citing `§30`.
3. Firewall folder: move the three rows out, convert three residuals to cross-references, re-derive the census.
4. Post 7's collector section.

Reverting is `git revert` of the notes and blog commits; nothing else consumes them.

## Open Questions

- The bead id for `§30`. `universe-zh5` gains the collector-chain case and `universe-l83.2` gains the collect fields, but neither owns the chain rules, so this likely wants a new bead. Assigning it does not change the specs, the approach or the task breakdown.
- Whether `order` ever takes a second value. `wire` is the only one any case needs, and the field exists rather than being implicit so that a second value would be an addition rather than a change of shape.
