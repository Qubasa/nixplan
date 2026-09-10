## Why

An interface is identified by the value an author imported (`lib/resolve.nix:917` —
`slot.interface == capability.interface`). That rule is exactly right inside one evaluation and
silently fails across two, which is the only arrangement in which a service written by one author can
be wired to a service written by another.

The failure was measured rather than assumed. Two independent evaluations of `lib/`, given the same
korora, then one interface of the same shape built through each:

| Interface built from | Equal across two evaluations of `lib/` |
| --- | --- |
| `korora.string` | `true` |
| `planner.korora.url` | `false` |

The difference is `lib/atoms.nix:10-43`: this library's own atoms are `korora.typedef "url" (v: …)`,
and that predicate is a fresh closure per evaluation, so the atom is a fresh value, so the interface
over it is a fresh value. korora's own types survive because `import` is memoised by path and both
evaluations reach one file; the atoms do not, because they are built by applying a function.

The consequence is a wire that is obviously correct and refused. Two flakes that both depend on this
library get one evaluation of it only when the dependency graph is deduplicated with `follows`, and a
third-party service author cannot be made to follow anybody's input graph. Every interface in this
subset that names a `url`, a `secretRef`, a `duration`, a `schedule`, a `unitRef` or a `userName` -
which is every interface worth sharing - is unshareable between two authors today.

The second reason is now, rather than later. `hold-declaration-shape-and-fold-set-reads` puts a
**fold** on the interface, and its Risks section makes value identity newly load-bearing: "Two
consumers may want different folds of one interface → the escape hatch costs one file: an interface
is identified by the value an author imported … so a second interface with a different fold is
legal." A fold is a lambda, and two lambdas are never equal, so any identity rule that is not value
equality has to say what a fold contributes to identity. Deciding that after the fold ships means
changing the constructor twice and re-rendering its documentation twice.

## What Changes

- **An interface MAY declare an `id`, and an `id` is a claim of identity.** `interface { name,
  exports, fold ? null }` (`lib/interface.nix:47-54`, plus the `fold` that
  `hold-declaration-shape-and-fold-set-reads` adds) gains `id ? null`. When both ends of a wire
  declare the same `id`, the planner matches them without comparing values. When either end declares
  none, matching is value equality exactly as today. `name` stays a label.
- **Two interfaces claiming one `id` must agree, and disagreeing is a row.** An identity is the `id`,
  the export keyset, each export's korora type name and secrecy, and the fold's name. Two interfaces
  claiming one `id` whose identities differ are `interface-id-conflict` - an error, and the edge is
  refused. That row is the version check: an author who adds an export without moving the `id` is
  told, rather than a consumer receiving a shape it was not written against.
- **A fold gains a name, and an `id` requires one.** `planner.fold "<name>" (providers: …)` returns
  `{ name, apply }`, the shape korora already uses for `typedef name verify`. A bare-lambda fold stays
  legal on an interface that declares no `id`. An interface that declares an `id` and an unnamed fold
  is `interface-id-unnamed-fold`: its identity cannot be computed, so its claim cannot be honoured.
- **Attribution follows identity.** `fileOf` (`lib/interface.nix:75-80`) matches by value first and
  then by claimed identity, so a row about a third-party interface can print that interface's own
  declaring file when its author's `interfaces` map is passed to `mkPlan`.
- **The plan records a claim where one was made.** `provides.<capability>` already carries the
  interface's name and declaring file (`fixtures/minimal-typed-edge/plan/backup.json` —
  `"interface": "ssh-host-identity"`), which is a label and a path. The claimed `id` joins them, and
  is absent where nothing was claimed, so the golden does not move and a downstream reader gets the
  one field it can key on.
- **`interface-mismatch` says which of the two rules refused the edge.** Its evidence
  (`lib/resolve.nix:1022-1027`) gains the cases "both ends claim an `id` and the claims differ" and
  "the two are different values and at most one claims an `id`", so the resolution names the fix that
  applies.
- **An `id` that names no namespace is a warning.** `interface-id-unnamespaced` fires on an `id`
  carrying neither `.` nor `/`, because an unqualified claim in a shared namespace is a collision
  waiting for a second author. It is a warning: an unqualified `id` still works.
- Not **BREAKING**. Every construct is additive and every default is today's behaviour. No in-tree
  interface declares an `id`, so `fixtures/minimal-typed-edge/plan/backup.json` and
  `plan/diagnostics.txt` do not move.

## Capabilities

### New Capabilities

- `planner/interface-identity`: what identifies an interface - the value, or a declared `id` claim -
  what an identity is made of, what two disagreeing claims produce, and what a claim does not buy.

### Modified Capabilities

- `planner/typed-edge`: "An interface is a value and its name is a label" gains its second half. The
  value rule stays the default and the name stays a label; a declared `id` becomes a second way for
  two interfaces to be one interface, and the requirement states which rule applies when.
- `planner/interface-fold`: a fold gains an optional name and the constructor that builds one, and an
  interface that claims an `id` may not carry an unnamed fold.
- `planner/plan-artifact`: a published capability's record gains the identity its interface claimed,
  absent where nothing was claimed, and a claim is stated not to re-key an entry.

No `planner/diagnostics` change: five new rows are rows, and `tooling/nix-unit-suite` already
requires a test per row and a scenario per behaviour.

## Impact

- **Depends on `hold-declaration-shape-and-fold-set-reads`.** That change introduces `fold`; this one
  names it. Implementing this first would mean writing `foldName` against a field that does not exist.
- **`lib/interface.nix`**: `id ? null` on the constructor; a `fold` constructor beside it;
  `identityOf`, `foldName` and `foldApply`; `fileOf` gains the identity fallback; the malformed-`id`,
  unnamed-fold, unnamespaced-`id` and registry-level conflict rows beside the existing atom checks.
- **`lib/resolve.nix`**: `interfaceMatches` at `916-917` becomes identity comparison with the value
  rule as its fallback; the conflict row at the wire; the `interface-mismatch` evidence at `1022-1027`.
- **`lib/default.nix`**: `fold` joins `interface` and `unitExtension` in the `korora` attrset and in
  the library's own exports (`lib/default.nix:57-70`).
- **`lib/plan.nix`**: the capability record at `157-160` gains the claimed identity, written only
  where one was claimed.
- **`docs/`**: `authoring.md` gains `id` in the interface section and the named fold beside `fold`;
  `README.md`'s export table gains `fold`; `plan.md` gains the capability record's new field;
  `diagnostics.md` gains the five rows.
- **`tests/unit/`**: rows and scenarios in the `interfaces`, `resolution` and `plan` suites; the four
  spec paths registered in `coverage.nix`.
- **`perf/`**: the added work is one attribute test per wire on fixtures that declare no `id`, which
  is below the 0.15 margin. Budgets are re-measured; they are re-pinned only if the ratchet fires.
- **Not in scope**: addressing a module by name so a deployment can be a JSON document, and giving
  settings a type so a form can be rendered from one. Both are follow-ons that need this change
  first - a catalogue of services from many authors is worth nothing if two of them cannot be wired
  together - and neither is opened here.
