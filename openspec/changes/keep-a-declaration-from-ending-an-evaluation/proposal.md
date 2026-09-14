## Why

`lib/default.nix:5-8` states the library's headline property: "Evaluation is total. Every check returns
a row instead of raising, and no raising call appears anywhere under this directory." `CLAUDE.md`
repeats it as "one malformed declaration becomes a row and the rest is still read". Three ordinary
author mistakes break it. Each ends `mkPlan` with no plan and no diagnostics table at all, and none of
the three is exotic: they are a typo in a claim, a typo inside a module, and a forgotten `interface`.

**A value the reading indexes into is indexed before it is checked.** `claims.ports.api = 5432;`
reaches `readClaims`, whose `portRows` calls `util.extraKeys claimKeys claim`
(`lib/module.nix:343`), which is `attrNames (removeAttrs set allowed)` (`lib/util.nix:117`) with no
`isAttrs` guard. `builtins.removeAttrs 5432 [ ]` raises `expected a set but found an integer`, and
`builtins.tryEval` does not catch it - verified by evaluating both - exactly as
`lib/diagnostics.nix:55-58` records: tryEval catches a `throw` and a failed `assert` and nothing else.
The same exposure sits at ten other index sites of the same reading, reached from `read`'s four
sub-readings (`lib/module.nix:996-1026`): a slot at `lib/module.nix:227`, a capability at `:302`, a
generator at `:496`, a generated file at `:405`, a pin at `:615`, and the module's own declaration at
`:1058`. A module returning something other than a record therefore dies at `util.extraKeys
moduleKeys declaration` (`lib/module.nix:1058`), not at a row. Worse than the raise is the fail-open
behaviour underneath it: `5432 ? fixed` is `false` rather than a raise, so
`util.filterAttrs (_: claim: claim ? fixed)` (`lib/module.nix:355`) would silently drop the
integer claim if the raise above it were merely suppressed.

**The declaration half of a module is applied outside every guard.** `lib/compose.nix:30-31` applies
`module { settings = settings.values; }` bare. The hazard was known at that exact site: the
shape-only second reading three lines below it is wrapped (`lib/compose.nix:42-50`,
`observed = diag.guard { … }`), and the implementation half is guarded four ways in `lib/resolve.nix`
- `implShape` at `:1216`, `unitsRaw` at `:1227`, `closureRaw`, and `implementation-malformed` at
`:1346-1354` for an implementation that returns a non-record. A `settings.typo` inside a `uses` block
is consequently an unattributed evaluation failure where the implementation half would have produced
`module-raised` naming the member.

**A capability the author forgot to type takes the wire down with it.** `lib/compose.nix:68-75` copies
`declaration.provides` verbatim into the root's `provides`, and `lib/resolve.nix:646-648` carries that
raw attrset into `rootProvides` - not the validated reading, which is `readCapability`'s and does hold
the `hasInterface` guard (`lib/module.nix:292`). The wire then forces `capability.interface`
unconditionally at `lib/resolve.nix:1585` and `:1590`, so `error: attribute 'interface' missing`
replaces the table. The library already owns the row for that condition:
`capability-interface-missing` (`lib/module.nix:315-323`). It is produced and never printed, because
the abort happens while the table is being forced. `lib/resolve.nix:1608` has the same shape,
indexing `capabilities.${capability.capability}` with no `or`. The second trigger is `bindingOf`
(`lib/resolve.nix:1001-1019`), which tests for the two key names `member` and `capability` only: a
root hand-writing `wire.db = { member = "database"; capability = "pg"; };` passes the
`binding-malformed` check at `:1043-1059` and is then indexed into as if it were a capability handle.
Neither `capability-interface-missing` nor `binding-malformed` has a test anywhere under `tests/`.

Nothing in the tree can see any of this. The purity scan in `tests/unit/diagnostics.nix:476-508` is
substring matching for five call spellings over comment-stripped lines (`hasInfix call line`), and
`removeAttrs`, `attrNames` and `capability.interface` are none of them. `CLAUDE.md` already records
the scan's limits under Known bugs. The guarantee is held by a text scan that cannot observe the way
it is being broken.

## What Changes

- **A value a module wrote where the reading needs a record is a row, not the end of the evaluation.**
  One identifier, `declaration-malformed` (error), produced at every site the module reading indexes
  into, with the row naming the site and the module file. It is the module-half twin of
  `implementation-malformed` (`lib/resolve.nix:1346`) and of the deployment half's
  `declaration-field-malformed` (`lib/resolve.nix:110-117`), whose published description at
  `docs/diagnostics.md:229` already claims "the deployment's half is read with the tolerance the
  module's half is read with" - a promise the module's half does not currently keep.
- **The module's own expression is forced under the recovery the implementation half already gets.**
  `compose.service` applies the module inside `diag.guard`, so a module that raises while computing
  its declaration is one `module-raised` row naming the member and the rest of the deployment is
  still read. The guard's fallback is the empty record, which degrades into the existing
  `impl-missing` row (`lib/module.nix:1072-1080`) rather than inventing a second sentence for one
  mistake.
- **A wire resolves only to a far end that carries an interface.** A capability declaring no
  interface value leaves the slot undelivered and earns `wire-capability-untyped` (error) against the
  consuming entry, beside the provider's own `capability-interface-missing`. Two entries have a
  problem and the table says so twice, once per subject.
- **`binding-malformed` covers a hand-written record.** A binding is refused unless it carries an
  interface, so `{ member = "database"; capability = "pg"; }` is the row its message already
  describes - "a value that is not a capability of one of its members" - rather than a value indexed
  into. No new identifier: the condition and the sentence are unchanged.
- **The suite plans each malformed shape rather than scanning for it.** A probe per shape asserts the
  row's identifier and subject, so a future reading that indexes before it checks fails the suite
  instead of ending it.

## Capabilities

### New Capabilities

<!-- none: every rule below belongs to a capability that exists -->

### Modified Capabilities

- `planner/diagnostics`: a record the reading indexes into is checked to be a record first, and the
  module's own expression is forced under the planner's recovery. Both are the totality the capability
  already requires, stated as checks a reading can be held to.
- `planner/typed-edge`: a wire and a binding resolve only to a far end carrying an interface value;
  one that does not is a row against the consumer and an undelivered slot.
- `tooling/nix-unit-suite`: the totality property is held by planning probes per malformed shape,
  because the source scan cannot observe an index.

## Impact

- `lib/module.nix`: one record reading beside `keyRow`, and every sub-reading routed through it
  before it indexes - `readClaims` and its port claims, `readSlot`, `readCapability`, `readVars`'s
  generators and files, `readPin`, and `read`'s own `declaration`. The `readUnit` and `readConfigFile`
  sites are already filtered upstream (`lib/resolve.nix:1234`, `:1253`) and gain a row instead of a
  silent drop.
- `lib/compose.nix`: the module application at `:30-31` moves inside `diag.guard`, and the second
  reading at `:42-50` gains the record check its `attrNames` needs. The rows travel as a member fact
  to `memberRows` beside `member.unknownKeys` (`lib/resolve.nix:1091`).
- `lib/resolve.nix`: the wire's far end is read for an interface before `identityOf` and the value
  comparison force it (`:1584-1590`), `readsAt`'s capability index gains its absence path (`:1608`),
  and `bindingOf` (`:1001-1019`) requires `interface` beside `member` and `capability`.
- `tests/unit/{diagnostics,composition,resolution}.nix`: nine tests, five of them probes over
  malformed shapes.
- `tests/unit/coverage.nix`: this change's three spec files move from `excused` to `accountable`.
- `docs/diagnostics.md`: `declaration-malformed` under Leaf modules, `wire-capability-untyped` under
  Wiring and resolution, and the `binding-malformed` row's description widened by one clause.
- `CLAUDE.md`: under Purity and totality, that a guard is not a check and which of the two each
  condition needs; under Interfaces, composition, reads, that a wire's far end is read for an
  interface before it is compared.
- No golden moves. Every condition this change turns into a row currently ends the evaluation, so no
  deployment that evaluates today can hold one, which includes `fixtures/minimal-typed-edge` and both
  perf fixtures. `fixtures/minimal-typed-edge/plan/*` is unchanged by construction rather than by
  inspection.
- Nothing under `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. A realiser is handed
  the same plan; what changes is that a deployment which used to have no plan at all now has one and
  a table.
