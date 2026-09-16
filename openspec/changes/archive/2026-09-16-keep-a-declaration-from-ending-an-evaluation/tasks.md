## 1. The record check in the module reading

The checks land before the guard. A guard installed first would appear to hold while the library's own
type errors flew through it, because `builtins.tryEval` catches neither a type error nor a missing
attribute, and the reading would then look total without being it.

- [x] 1.1 Add one record reading to `lib/module.nix` beside `keyRow`, taking `subject`, the module
  label, a `where` and the value, returning `{ value, rows }` with `{ }` as the fallback and one
  `declaration-malformed` error row naming the site and the module file. It mirrors `declaredRecord`
  (`lib/resolve.nix:135-159`) for the half a module writes, and the identifier sits beside
  `implementation-malformed` (`lib/resolve.nix:1346-1354`). Verify by calling it directly from a
  throwaway evaluation with an integer: the value is `{ }` and the row carries the six fields.
  Done as `declaredRecord` in `lib/module.nix`. A `/tmp` probe planning `claims.ports.api = 5432`
  returns the six fields: `error`, `declaration-malformed`, subject `modules/bad.nix`, message
  "port claim `api` of modules/bad.nix is declared as a value of type int, and the reading needs a
  record", the evidence about the rest of the file still being read, and the resolution. The
  resolution is `write a record for ${where}` and not `… in ${subject}`: `where` already ends in the
  module label, so the drafted wording named the same file twice.
- [x] 1.2 Route `readClaims` through it - the `claims` record itself before `util.extraKeys [ "ports" ]
  claims` (`lib/module.nix:364`) and each port claim before `util.extraKeys claimKeys claim` (`:343`)
  - and drop a malformed claim from the returned `ports` explicitly rather than leaving it to
  `util.filterAttrs (_: claim: claim ? fixed)` (`:355`), which drops it silently and would otherwise
  earn `port-claim-not-fixed`. Verify with `testAPortClaimIsNotARecord` in
  `tests/unit/diagnostics.nix`: red before this task with an evaluation that ends rather than a
  failing assertion, green after, asserting the identifier, the severity, the subject and that the
  entry records no port claim. Green: one `declaration-malformed` error subjected to
  `modules/bad.nix`, the entry carries no `alloc`, and the well-formed instance is still planned. At
  `b7dd7e1` the same deployment ends the evaluation with `error: expected a set but found an integer:
  5432`.
- [x] 1.3 Route `readSlot` (`lib/module.nix:227`) and `readCapability` (`:302`) through it, and route
  the `uses` and `provides` records themselves before `builtins.mapAttrs` walks them
  (`lib/module.nix:1004-1026`). Verify with `testASlotIsNotARecord` and
  `testACapabilityIsNotARecord` in `tests/unit/diagnostics.nix`, each red before this task and green
  after, and each asserting that no wire for the slot is resolved and that the capability publishes
  nothing. Green. The slot probe records no `reads` on the entry and the capability probe no
  `provides`; the capability probe also wires the re-exported capability from a second instance and
  observes `wire-capability-untyped` with the slot undelivered, which is what "addressable by no
  wire" means once the capability itself declares nothing.
- [x] 1.4 Route the remaining index sites of the same reading: `readVars`'s generators (`:496`) and
  generated files (`:405`), `readPin` (`:615`) and its `locked` record (`:623`), and `read`'s own
  `declaration` before `util.extraKeys moduleKeys declaration` (`:1058`). Verify with
  `testAModuleReturnsSomethingOtherThanARecord` in `tests/unit/diagnostics.nix`, and verify the
  `vars` and `pin` shapes by hand with a throwaway deployment declaring each as an integer: the table
  carries one `declaration-malformed` row per site and the plan is still produced. Green, and the
  hand check covers six sites, one row each, with `bad:only@one` planned every time: `the generators
  of modules/bad.nix`, `generator "token"`, `the files of generator "token"`, `generated file
  "token/key"`, `the pin of modules/bad.nix` and `the locked record of modules/bad.nix`. Caveat: a
  non-record `locked` earned `pin-malformed` ("declares no locked record") at `b7dd7e1`, since
  `isAttrs locked` was already tested there; that sentence is deleted and the condition now reads as
  the family identifier, which is what the spec asks for a pin. No documented identifier became
  unproducible - `pin-malformed` still answers a missing lock key and a non-string locked field, and
  `testADocumentTabulatesARowTheTreeCannotProduce` is green.
- [x] 1.5 Read the containers `units` and `configData` for their kind before `util.filterAttrs` walks
  them (`lib/resolve.nix:1248` and `:1268`), and record `the unit set` and `the configuration data`
  as sites of `implementation-malformed`. The upstream filters stay, and `readUnit` and
  `readConfigFile` are not routed through the reading of task 1.1. The task as drafted said those
  filters "drop a non-record unit and a non-record configuration file silently" and that a deployment
  whose implementation returns `units.web = 5` gets no row today; measured at `b7dd7e1`, that
  deployment gets `implementation-malformed :: bad:only@two` and is planned, because `malformed`
  already reports the complement of each filter. What did end the evaluation is `units = 5`, which
  reaches `util.filterAttrs` and aborts with `expected a set but found an integer: 5` - the fourth
  abort of this family, and the one this task fixes. Routing `readUnit` and `readConfigFile` through
  `declaredRecord` would add a branch nothing can reach, since each is handed only records, and would
  put a second identifier on a site `implementation-malformed` already names. `design.md` records the
  correction as a decision rather than an open question.

## 2. The declaration under the planner's recovery

- [x] 2.1 Move the module application in `compose.service` (`lib/compose.nix:30-31`) inside
  `diag.guard`, with `{ }` as the fallback, and give the second, shape-only reading (`:42-50`) the
  record check from task 1.1, because `attrNames` inside a guard still raises uncatchably. The service
  record carries the rows the way it already carries `unknownKeys` and `slotSet` (`:66-67`). Verify by
  evaluating a deployment whose module interpolates a missing settings key: the evaluation completes.
  Done: `computed = diag.guard { … }` and `recordOf` for the shape-only reading and for `provides`.
  The probe's raising module (a `throw` inside `uses.far.reads`) plans to `module-raised` plus
  `impl-missing` with the sibling instance planned in full; at `b7dd7e1` the same deployment ends the
  evaluation with the module's own text, `error: the module could not decide what it reads`, and no
  table. An interpolation of a missing settings key stays uncatchable and is documented as such.
- [x] 2.2 Collect those rows in `memberRows` (`lib/resolve.nix:1078-1105`) beside
  `member.unknownKeys` (`:1091`). Verify with `testAModuleRaisesWhileComputingItsDeclaration` in
  `tests/unit/diagnostics.nix`: red before task 2.1 as an ended evaluation, green after, asserting
  `module-raised` with the member's subject, `impl-missing` beside it, and that a second instance of
  the same deployment is planned in full. Green: `module-raised :: member:only` and
  `impl-missing :: modules/bad.nix`, and `good:only@one` keeps its unit.
- [x] 2.3 Verify no new identifier was introduced for the degradation: the table for a raising
  declaration carries exactly `module-raised` and `impl-missing` for that member, and
  `tests/unit/diagnostics.nix`'s identifier cross-walk against `docs/diagnostics.md` stays green.
  Verified: those two rows and nothing else, and `testTheLibraryGainsARow` and
  `testADocumentTabulatesARowTheTreeCannotProduce` are both green with the two new identifiers
  documented.

## 3. The far end of a wire and of a binding

- [x] 3.1 In `lib/resolve.nix`, read the wired capability for an interface before the comparisons
  force it: `capabilityClaim` (`:1585`) and `sameValue` (`:1590`) are the two sites, and
  `readsAt`'s `providerMember.placed.${machine}.capabilities.${capability.capability}` (`:1608`) is
  the third index with no absence path. Emit `wire-capability-untyped` (error) subjected to the
  consuming entry, naming the slot and the capability, and leave the slot absent from `results`
  rather than present and empty. Verify with `testAWireResolvesToACapabilityDeclaringNoInterface` in
  `tests/unit/resolution.nix`: red before this task as `attribute 'interface' missing`, green after,
  asserting the identifier, the subject, the absence of the slot from the consumer's reads, and that
  the provider's `capability-interface-missing` is in the same table with its own subject. Green:
  `farTyped` gates both comparisons, `placements` is empty where the provider member declares no such
  capability, and the test reads the table as `capability-interface-missing :: modules/provider/leaf.nix`
  beside `wire-capability-untyped :: consumer:only`, with the slot undelivered, no `entry` recorded,
  the consumer's `SLOTS` empty and all three entries planned. At `b7dd7e1` the same deployment ends
  with `error: attribute 'interface' missing at lib/resolve.nix:1590:89`.
- [x] 3.2 Require `interface` in `bindingOf` (`lib/resolve.nix:1001-1019`) beside `member` and
  `capability`, so a hand-written record falls into the existing `binding-malformed` path
  (`:1043-1059`) with its message and resolution unchanged. Verify with
  `testARootBindsASlotToARecordCarryingNoInterface` in `tests/unit/composition.nix`: red before this
  task, green after, asserting the identifier, the subject, and that the slot is then the
  deployment's to fill rather than one the root bound. Green: `binding-malformed :: pair:app` beside
  `slot-unwired`, whose resolution is the unbound form naming `wire.far` with an instance and a
  capability rather than the bound form naming a member; the consumer receives nothing and both
  entries are planned. `member` and `capability` are also read
  for being strings, because the line below them indexes `memberKeyOf` with the first; `design.md`
  records that. At `b7dd7e1` the same deployment ends with `error: attribute 'interface' missing`.
- [x] 3.3 Verify the two untested identifiers are now exercised: `capability-interface-missing` and
  `binding-malformed` each appear in a test's expectation, which is what neither did before this
  change. `capability-interface-missing` is in the expectation of
  `resolution.testAWireResolvesToACapabilityDeclaringNoInterface`, and `binding-malformed` in
  `composition.testARootBindsASlotToARecordCarryingNoInterface` and in
  `diagnostics.testAProbePlansEveryMalformedShapeAtOnce`.

## 4. The suite's probes

- [x] 4.1 Add `testAProbePlansEveryMalformedShapeAtOnce` to `tests/unit/diagnostics.nix`: one
  deployment carrying a malformed claim, slot, capability, generator and declaration, a module whose
  declaration raises, a wire to an untyped capability and a hand-written binding, beside one
  well-formed instance. Deep-force the plan and the table and assert one row per mistake and that the
  well-formed instance is planned in full. Verify it is red before group 1 as an ended evaluation.
  Green: eleven rows, one per mistake plus the two degradations a malformed whole declaration and a
  raising one earn (`impl-missing` twice) and the `slot-unwired` the discarded binding leaves, with
  `good:only@one` planned and the same table on a second evaluation of the same arguments.
- [x] 4.2 Add `testAProbeNamesTheDeclarationItPlanned` to `tests/unit/diagnostics.nix`, asserting that
  each probe's expectation is an identifier and a subject rather than the fact that the evaluation
  completed: a reading that dropped the declaration silently fails it. Verify by making the record
  reading return no row for one site and observing the named identifier in the failure. Green: the
  test names `declaration-malformed :: modules/bad.nix` for each of the five shapes and asserts that
  the same table with those rows filtered out still deep-forces and names nothing, which is the table
  a silent drop would have produced.
- [x] 4.3 Verify the purity scan (`tests/unit/diagnostics.nix:476-508`) is unchanged and still green,
  and record in the change that it is not what holds this property: it matches five call spellings as
  substrings over comment-stripped lines and an index is neither. Unchanged - no hunk of this change
  touches the scan - and green as part of the suite. `design.md`'s "The suite plans probes rather than
  scanning source" is where the reason is recorded.

## 5. Registration and documentation

- [x] 5.1 Move this change's three specification files -
  `keep-a-declaration-from-ending-an-evaluation/specs/planner/diagnostics/spec.md`,
  `.../specs/planner/typed-edge/spec.md` and `.../specs/tooling/nix-unit-suite/spec.md` - from
  `excused` to `accountable` in `tests/unit/coverage.nix`; the excuse "an unimplemented change"
  expires the moment a task above is ticked. Verify `testEverySpecificationIsClassified`, the excuse
  staleness check and the scenario cross-walk are green: each of the nine scenario headings must find
  the test name it derives. Done, and the whole `coverage` suite is green: the nine headings resolve
  to seven `test…` names in `diagnostics`, one in `resolution` and one in `composition`.
- [x] 5.2 Add `declaration-malformed` to `docs/diagnostics.md` under `### Leaf modules` and
  `wire-capability-untyped` under `### Wiring and resolution`, and widen the `binding-malformed`
  description (`docs/diagnostics.md:156`) by the clause that a record carrying no interface is not a
  capability off a sibling's handle. Update the per-suite figures and the total at
  `docs/tooling.md:81-113` by the nine tests this change adds - seven in `diagnostics`, one in
  `resolution`, one in `composition`. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale
  included. Done: `diagnostics` 47 to 54, `composition` 32 to 33, `resolution` 53 to 54, total 507 to
  516, which is what `coverage.testASuiteGainsATest` compares against. `treefmt` exits 0.
- [x] 5.3 Record the invariant in `CLAUDE.md`. Under Purity and totality, beside the existing
  `builtins.tryEval` bullet: a guard is not a check, because a type error and a missing attribute are
  uncatchable, so every value a declaration wrote is checked to be a record before the reading indexes
  into it, and the module's own expression is forced under the same recovery the implementation half
  gets. Under Interfaces, composition, reads: a wire's far end is read for an interface before either
  comparison, because `provides` reaches the wire as the author's own record rather than as the
  validated reading, and a binding is a capability handle only if it carries one. Both bullets added,
  the first also stating that the implementation's half keeps `implementation-malformed`.

## 6. Verification

- [x] 6.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the fixture's `plan/*` comparison and its `diagnostics.txt` byte comparison, both of which
  must be unchanged: every condition this change turns into a row ends the evaluation today, so no
  deployment that evaluates can hold one. Exit 0, 516/516 successful, and no file under `fixtures/`
  is touched by this change.
- [x] 6.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  check adds one predicate per record the reading already reads and one `tryEval` per member, so the
  cost per plan entry may move; record the measured figures for sizes 64 and 256 if the margin moved
  by more than half of the 0.15 allowance. The budgets do not hold, and did not at `b7dd7e1`: the
  same 81 of 81 gated figures are above budget on both trees, up to +15.47% (`fleet-4`
  `nrPrimOpCalls`), so the check exits 1 before this change and after it. Measured against the same
  run of the base tree, this change costs +1.21% per plan entry on average and +3.22% at worst
  (`worked` `sets.bytes`), which is under half of the 0.15 allowance. At the two sizes the task names
  the figures are smaller still: `fleet-64` +0.15% to +0.99% per counter, `fleet-256` +0.04% to
  +0.81%, `mesh-64` +0.11% to +0.79%, `mesh-256` +0.03% to +0.61%, `nrOpUpdateValuesCopied`
  unchanged at every one of them. The growth bound holds everywhere: every ratio the run printed is
  at most 0.77 against a bound of 1.25. `perf/budgets.json` is not edited.
- [x] 6.3 Verify one end-to-end folder still applies unchanged - `nix run .#planner-e2e wired-pair` -
  so that a deployment none of these rows concerns is untouched. 37 passed in 52.85s, exit 0.
