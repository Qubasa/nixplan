## Context

See proposal.md — Why. The mechanics the approach has to fit:

| Fact | Site | Consequence for this change |
| --- | --- | --- |
| a refused read is absent from `results`, so nothing can default against it | `lib/resolve.nix:1000-1006`, `docs/authoring.md` "When a read is refused" | the absence is the decided design and is not up for revision here |
| a missing attribute is what `builtins.tryEval` does not catch | `CLAUDE.md` "Purity and totality" | an implementation reading an absent slot cannot be contained by any guard the library could add |
| `applicable` forces the whole table, and the table's rows include every entry's own | `lib/default.nix:111-116` | one unguarded consumer makes the table unevaluable for every entry, which is the gap the spec did not state |
| the suite already has one hatch for this exact class | `tests/unit/coverage.nix`, `omitted` — "A module's own code raises an uncatchable error" | the unguarded scenario is registered there rather than asserted |
| a fold's result is delivered to `impl` only, never to the plan | `lib/resolve.nix:1002-1006` — `value` is the entry-keyed set, `implValue` the folded one | the shape a fold returns is a convention between an interface and its consumers, invisible to any plan reader |
| every fold test in the tree has exactly one consumer | `tests/unit/resolution.nix` — `testAFoldReplacesTheProviderKeyedSet` and its neighbours | the many-consumer case has no evidence, which is why it reads like a limitation |
| `fixtures/**` is excluded from the formatter and compared with `==` | `CLAUDE.md` "Fixtures and goldens" | any fixture edit is a golden edit, so the folded evidence goes in the unit layer |

## Goals / Non-Goals

**Goals:**

- The spec says what the implementation does about a refused fold, including the condition under which
  a refusal is reportable at all.
- The published fold example is the shape that scales to many consumers, so an author does not reach
  for a second interface over a file format.
- The many-consumer case has evidence in the suite rather than in a conversation.

**Non-Goals:**

- Any library change. Nothing about `lib/interface.nix`, `lib/resolve.nix` or `lib/compose.nix` moves.
- Any change to the refusal channel, the id/subject/severity split, `reach`, delivery derivation or the
  diagnostics record.
- Per-consumer folds, a fold argument on a slot, or opening `collects`/`contributes`
  (`lib/excluded.nix:49-60`).
- Adopting a fold in `fixtures/minimal-typed-edge`.

## Decisions

### D1 — Correct the words, and give authors a rule that keeps the table renderable

The requirement promises a plan for every other entry. The implementation delivers that only where no
implementation forces the refused slot. Two candidate fixes:

- **Say what happens** (chosen). The requirement states both halves, the documents state the
  consequence, and `docs/authoring.md` gains the rule that follows from it: when an interface's fold
  can refuse, a consumer reads its slot under `results ? <slot>`. A wiring mistake still fails loudly,
  because an unwired slot is a row the planner already produced before any implementation ran; what the
  guard preserves is the one case where the planner has something to say and the message came from the
  fold.
- **Change the behaviour.** Rejected in three shapes. A poisoned value that raises with the row's text
  puts author text into a raise the planner would then re-catch as `module-raised`, which is the
  channel `hold-declaration-shape-and-fold-set-reads` design D8 closed. An empty set is refused by the
  existing convention, and for the stated reason: `or [ ]` must not be writable. Omitting an
  undelivered consumer's entry from the plan would remove a key other entries name in `dependsOn` and
  that `cli/manifest.py` addresses, which is a far larger blast radius than the words.

### D2 — The unguarded scenario is registered as omitted, not asserted

A test of it would abort the suite rather than fail it: the failure is a missing attribute, and
`nix-unit` has no way to observe an evaluation that ends. `tests/unit/coverage.nix` already carries
this hatch for `A module's own code raises an uncatchable error` and `A misspelled capability
reference`, both for the same reason, so the scenario joins them with a reason naming the measurement
that stands in for it.

The measurement is recorded in tasks.md, the way `clean-up-transplant-residue` task 4.3 records the
one perf observation the layer cannot hold: a throwaway two-consumer deployment evaluated twice, once
with an unconditional `results.<slot>` read and once guarded, with both outputs quoted.

### D3 — The guarded half is asserted in the resolution suite

`tests/unit/resolution.nix` already builds folds with its `folding`, `reading` and `edge` helpers and
already asserts a refused fold's absent slot. The new test is one more deployment through the same
helpers, with two consumers that guard, asserting three things a single-consumer test cannot: one row
per consuming entry, `delivered = false` on each read, and that the table renders while `applicable`
is false. Placing it beside `testARefusedFoldLeavesTheSlotAbsent` keeps the pair readable as the two
halves of one behaviour.

### D4 — The documented fold normalises and refuses; rendering stays in the consumer

The example in `docs/authoring.md` becomes a fold that validates, refuses by returned value, and
returns one record per provider carrying that provider's entry key. Each consumer renders its own bytes
in `impl`.

This is a documentation decision with a structural argument behind it: a fold that returns bytes can
serve exactly one output format, so the first consumer with a second format has to declare a second
interface — for a difference that is not a policy difference. A fold that returns records serves any
number of them. ThermOS is the outside case: its `contract.merge` functions return data and its
builders render, and its one transforming module (`modules/middleware/pam.nix`) is a module in the
graph rather than a second merge.

Alternatives considered:

- **Keep the rendering example and add a note.** Rejected: the example is what gets copied, and the
  note would be read after the second interface was already declared.
- **A planner-supplied combinator table.** Already rejected by `hold-declaration-shape-and-fold-set-reads`
  design D1, and this change strengthens that: with rendering out of the fold, the useful policies are
  validate, dedupe and order, which an author writes in three lines.
- **State the convention as a requirement that a fold must not return a string.** Rejected: a fold's
  output never enters the plan, so the planner cannot observe the difference, and a rule nothing can
  check is prose pretending to be a contract. The requirement states that a fold may return any value
  and that rendering is the consumer's; the taste goes in the documents.

### D5 — The fixture keeps its hand-written fold

`hold-declaration-shape-and-fold-set-reads` design.md:219-222 left this open and gave the argument for
leaving it: the folder's value is evidence of the unfolded shape, which is what every interface without
a fold still produces. Adopting a fold there would also put the new evidence where a golden comparison
mediates it, so a change to the example's records would show up as a plan diff rather than as a test.
The unit layer is where a fold can be declared, refused and re-declared per test.

### D6 — No perf re-measurement

No library expression changes, and no deployment under `perf/` declares a fold or a settings-derived
slot set, so the nine gated counters have no new work to do. The verification is that
`checks.<system>.planner-perf` still passes against the committed budgets, not a re-pin.

## Risks / Trade-offs

- **A stated guard convention could make authors guard every read defensively, which is what the
  absent slot exists to prevent** → the rule is scoped to a slot whose interface declares a fold that
  can refuse, which is the only case where the planner holds a message the author wrote. Every other
  refused read is a wiring row the planner produced before the implementation ran, and reading those
  slots unguarded stays the documented default.
- **Restating three scenarios inside a MODIFIED requirement duplicates their titles across two
  accountable spec files** → the cross-walk maps a title to a test name (`hasTest`), so each copy is
  satisfied by the one existing test and nothing is double-counted. The cost is that renaming one of
  those scenarios later touches two files.
- **A requirement that names an uncatchable failure reads like a promise the suite proves** → the
  `omitted` entry is the visible statement that it is not asserted here, and the reason is recorded
  with the measurement that replaces it.
- **An operator running `planner build` on a deployment whose fold refuses and whose consumer does not
  guard still sees a bare missing-attribute error, with the fold's message lost** → out of scope and
  named as an open question below, because every fix is a behaviour change with a wider blast radius
  than this change's subject.

## Migration Plan

Additive in every position, and no in-tree evaluation changes:

1. The spec delta modifies one requirement and adds one. No library, fixture, golden, plan field or
   deployment is touched, so `planner.worked.plan` and `plan/diagnostics.txt` stay equal by
   construction.
2. `tests/unit/coverage.nix` gains one `accountable` entry and one `omitted` entry, and
   `tests/unit/resolution.nix` gains three tests. A failing cross-walk is the intended state between
   the first and the last of those edits.
3. The document edits are prose and one code block. `nix fmt` covers the markdown, and
   `layers.testAFileNamesAPathThatIsNotThere` covers any path either edit names.

Rollback is reverting the spec, the two test files and the three documents; nothing persists between
evaluations.

## Open Questions

- Whether the operator's command should render a refusal an unguarded consumer hides. The candidate is
  a `planner build` that resolves the diagnostics table before it forces any entry's units, which is a
  question about `operator/read.nix` and `cli/` rather than about the library, and it needs a deployment
  where the distinction is observable. Deferrable: it changes no requirement here, and the guard rule
  from D1 already makes the message reachable for an author who wants it.
