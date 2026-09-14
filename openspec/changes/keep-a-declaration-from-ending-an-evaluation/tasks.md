## 1. The record check in the module reading

The checks land before the guard. A guard installed first would appear to hold while the library's own
type errors flew through it, because `builtins.tryEval` catches neither a type error nor a missing
attribute, and the reading would then look total without being it.

- [ ] 1.1 Add one record reading to `lib/module.nix` beside `keyRow`, taking `subject`, the module
  label, a `where` and the value, returning `{ value, rows }` with `{ }` as the fallback and one
  `declaration-malformed` error row naming the site and the module file. It mirrors `declaredRecord`
  (`lib/resolve.nix:135-159`) for the half a module writes, and the identifier sits beside
  `implementation-malformed` (`lib/resolve.nix:1346-1354`). Verify by calling it directly from a
  throwaway evaluation with an integer: the value is `{ }` and the row carries the six fields.
- [ ] 1.2 Route `readClaims` through it - the `claims` record itself before `util.extraKeys [ "ports" ]
  claims` (`lib/module.nix:364`) and each port claim before `util.extraKeys claimKeys claim` (`:343`)
  - and drop a malformed claim from the returned `ports` explicitly rather than leaving it to
  `util.filterAttrs (_: claim: claim ? fixed)` (`:355`), which drops it silently and would otherwise
  earn `port-claim-not-fixed`. Verify with `testAPortClaimIsNotARecord` in
  `tests/unit/diagnostics.nix`: red before this task with an evaluation that ends rather than a
  failing assertion, green after, asserting the identifier, the severity, the subject and that the
  entry records no port claim.
- [ ] 1.3 Route `readSlot` (`lib/module.nix:227`) and `readCapability` (`:302`) through it, and route
  the `uses` and `provides` records themselves before `builtins.mapAttrs` walks them
  (`lib/module.nix:1004-1026`). Verify with `testASlotIsNotARecord` and
  `testACapabilityIsNotARecord` in `tests/unit/diagnostics.nix`, each red before this task and green
  after, and each asserting that no wire for the slot is resolved and that the capability publishes
  nothing.
- [ ] 1.4 Route the remaining index sites of the same reading: `readVars`'s generators (`:496`) and
  generated files (`:405`), `readPin` (`:615`) and its `locked` record (`:623`), and `read`'s own
  `declaration` before `util.extraKeys moduleKeys declaration` (`:1058`). Verify with
  `testAModuleReturnsSomethingOtherThanARecord` in `tests/unit/diagnostics.nix`, and verify the
  `vars` and `pin` shapes by hand with a throwaway deployment declaring each as an integer: the table
  carries one `declaration-malformed` row per site and the plan is still produced.
- [ ] 1.5 Route `readUnit` (`:785`) and `readConfigFile` (`:916`) through it, and decide the fate of
  the upstream filters at `lib/resolve.nix:1234` and `:1253`, which today drop a non-record unit and a
  non-record configuration file silently. Verify by evaluating a deployment whose implementation
  returns `units.web = 5`: the table carries the row and the entry declares no such unit, where today
  it carries neither.

## 2. The declaration under the planner's recovery

- [ ] 2.1 Move the module application in `compose.service` (`lib/compose.nix:30-31`) inside
  `diag.guard`, with `{ }` as the fallback, and give the second, shape-only reading (`:42-50`) the
  record check from task 1.1, because `attrNames` inside a guard still raises uncatchably. The service
  record carries the rows the way it already carries `unknownKeys` and `slotSet` (`:66-67`). Verify by
  evaluating a deployment whose module interpolates a missing settings key: the evaluation completes.
- [ ] 2.2 Collect those rows in `memberRows` (`lib/resolve.nix:1078-1105`) beside
  `member.unknownKeys` (`:1091`). Verify with `testAModuleRaisesWhileComputingItsDeclaration` in
  `tests/unit/diagnostics.nix`: red before task 2.1 as an ended evaluation, green after, asserting
  `module-raised` with the member's subject, `impl-missing` beside it, and that a second instance of
  the same deployment is planned in full.
- [ ] 2.3 Verify no new identifier was introduced for the degradation: the table for a raising
  declaration carries exactly `module-raised` and `impl-missing` for that member, and
  `tests/unit/diagnostics.nix`'s identifier cross-walk against `docs/diagnostics.md` stays green.

## 3. The far end of a wire and of a binding

- [ ] 3.1 In `lib/resolve.nix`, read the wired capability for an interface before the comparisons
  force it: `capabilityClaim` (`:1585`) and `sameValue` (`:1590`) are the two sites, and
  `readsAt`'s `providerMember.placed.${machine}.capabilities.${capability.capability}` (`:1608`) is
  the third index with no absence path. Emit `wire-capability-untyped` (error) subjected to the
  consuming entry, naming the slot and the capability, and leave the slot absent from `results`
  rather than present and empty. Verify with `testAWireResolvesToACapabilityDeclaringNoInterface` in
  `tests/unit/resolution.nix`: red before this task as `attribute 'interface' missing`, green after,
  asserting the identifier, the subject, the absence of the slot from the consumer's reads, and that
  the provider's `capability-interface-missing` is in the same table with its own subject.
- [ ] 3.2 Require `interface` in `bindingOf` (`lib/resolve.nix:1001-1019`) beside `member` and
  `capability`, so a hand-written record falls into the existing `binding-malformed` path
  (`:1043-1059`) with its message and resolution unchanged. Verify with
  `testARootBindsASlotToARecordCarryingNoInterface` in `tests/unit/composition.nix`: red before this
  task, green after, asserting the identifier, the subject, and that the slot is then the
  deployment's to fill rather than one the root bound.
- [ ] 3.3 Verify the two untested identifiers are now exercised: `capability-interface-missing` and
  `binding-malformed` each appear in a test's expectation, which is what neither did before this
  change.

## 4. The suite's probes

- [ ] 4.1 Add `testAProbePlansEveryMalformedShapeAtOnce` to `tests/unit/diagnostics.nix`: one
  deployment carrying a malformed claim, slot, capability, generator and declaration, a module whose
  declaration raises, a wire to an untyped capability and a hand-written binding, beside one
  well-formed instance. Deep-force the plan and the table and assert one row per mistake and that the
  well-formed instance is planned in full. Verify it is red before group 1 as an ended evaluation.
- [ ] 4.2 Add `testAProbeNamesTheDeclarationItPlanned` to `tests/unit/diagnostics.nix`, asserting that
  each probe's expectation is an identifier and a subject rather than the fact that the evaluation
  completed: a reading that dropped the declaration silently fails it. Verify by making the record
  reading return no row for one site and observing the named identifier in the failure.
- [ ] 4.3 Verify the purity scan (`tests/unit/diagnostics.nix:476-508`) is unchanged and still green,
  and record in the change that it is not what holds this property: it matches five call spellings as
  substrings over comment-stripped lines and an index is neither.

## 5. Registration and documentation

- [ ] 5.1 Move this change's three specification files -
  `keep-a-declaration-from-ending-an-evaluation/specs/planner/diagnostics/spec.md`,
  `.../specs/planner/typed-edge/spec.md` and `.../specs/tooling/nix-unit-suite/spec.md` - from
  `excused` to `accountable` in `tests/unit/coverage.nix`; the excuse "an unimplemented change"
  expires the moment a task above is ticked. Verify `testEverySpecificationIsClassified`, the excuse
  staleness check and the scenario cross-walk are green: each of the nine scenario headings must find
  the test name it derives.
- [ ] 5.2 Add `declaration-malformed` to `docs/diagnostics.md` under `### Leaf modules` and
  `wire-capability-untyped` under `### Wiring and resolution`, and widen the `binding-malformed`
  description (`docs/diagnostics.md:156`) by the clause that a record carrying no interface is not a
  capability off a sibling's handle. Update the per-suite figures and the total at
  `docs/tooling.md:81-113` by the nine tests this change adds - seven in `diagnostics`, one in
  `resolution`, one in `composition`. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale
  included.
- [ ] 5.3 Record the invariant in `CLAUDE.md`. Under Purity and totality, beside the existing
  `builtins.tryEval` bullet: a guard is not a check, because a type error and a missing attribute are
  uncatchable, so every value a declaration wrote is checked to be a record before the reading indexes
  into it, and the module's own expression is forced under the same recovery the implementation half
  gets. Under Interfaces, composition, reads: a wire's far end is read for an interface before either
  comparison, because `provides` reaches the wire as the author's own record rather than as the
  validated reading, and a binding is a capability handle only if it carries one.

## 6. Verification

- [ ] 6.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the fixture's `plan/*` comparison and its `diagnostics.txt` byte comparison, both of which
  must be unchanged: every condition this change turns into a row ends the evaluation today, so no
  deployment that evaluates can hold one.
- [ ] 6.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  check adds one predicate per record the reading already reads and one `tryEval` per member, so the
  cost per plan entry may move; record the measured figures for sizes 64 and 256 if the margin moved
  by more than half of the 0.15 allowance.
- [ ] 6.3 Verify one end-to-end folder still applies unchanged - `nix run .#planner-e2e wired-pair` -
  so that a deployment none of these rows concerns is untouched.
