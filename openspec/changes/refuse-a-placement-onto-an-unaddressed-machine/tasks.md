## 1. Record what exists

- [x] 1.1 Reproduce the defect before editing anything: a registry declaring one machine with a
  `system` and a `serviceManager` and no `address`, one module whose unit command interpolates
  `${target.address}`, one placement onto it, and `mkPlan` forced. Verify the failure is
  `error: attribute 'address' missing` with no diagnostics table, and keep the throwaway expression
  as the before-and-after comparison for task 3.3. Reproduced through
  `nix eval --json .#lib --apply "$(cat <expression>)"`: `error: attribute 'address' missing at
  «string»:7:44`, pointing at the module's own interpolation. The table is not merely rowless but
  unreadable: forcing `result.diagnostics` alone fails the same way, because the table is folded
  over the entries and the entry is what raises.
- [x] 1.2 Verify no golden can move, by reading rather than by assuming: every machine of
  `fixtures/minimal-typed-edge/deployment/machines.nix` declares an address (`vault.example`,
  `alpha.example`, `beta.example`, `gamma.example` at `:6-38`), `perf/fleet.nix:152-157` and
  `perf/mesh.nix:186-191` declare `${name}.fleet.example:22` and `${name}.mesh.example:22` for every
  generated machine, and every end-to-end registry declares one
  (`tests/e2e/shared-postgres/deployment/machines.nix:12-27`,
  `tests/e2e/newcomer/template/deployment/machines.nix:2-14`). `fixtures/minimal-typed-edge/plan/*`
  and `fixtures/minimal-typed-edge/plan/diagnostics.txt` therefore stay byte-equal, and no
  regeneration with `nix eval --json .#debug.worked.plan | jq -S .` is part of this change. Read
  rather than assumed, by scanning every `.nix` file of the tree for a record declaring a
  `serviceManager` with no `address` in the same block: the four fixture machines, all six
  end-to-end registries (`generated-secret`, `newcomer`, `portable-image`, `secret-delivery`,
  `shared-postgres`, `wired-pair`) and both perf generators declare one, and `support.machines`
  and `support.laptop` in `tests/unit/support.nix:95-115` declare one each. Two registries of the
  unit suites' own deployments do not, and both were written to exercise exactly this absence:
  `tests/unit/resolution.nix:70-76`'s `bare`, which task 5.4 rewrites, and
  `tests/unit/image.nix:348-352`'s `bare`, which declares an address and neither other target key
  and whose test reads only the row it earns, so it is green unchanged. No golden moved.
- [x] 1.3 Record the three expectations this change reverses, so each is rewritten rather than
  re-pinned: `resolution.testAMachineWithNoAddress` (`tests/unit/resolution.nix:811-861`, which pins
  the `if target ? address then ... else throw` guard and expects `module-raised`),
  `platform.testAMachineOmitsItsSystem` and `platform.testAMachineOmitsItsServiceManager`
  (`tests/unit/platform.nix:98-150`, which expect `svc:only@host` in the plan with a partial
  `target`), and `operator.testAMachineOfAPlacedEntryDeclaresNoAddress`
  (`tests/unit/operator.nix:1357-1383`, which expects the warning). All three read as recorded, and
  all three are rewritten under their own names by tasks 5.1, 5.4 and 4.3.

## 2. The registry reading

- [x] 2.1 Add `"address"` to `machineTargetKeys` (`lib/resolve.nix:50-53`) and change
  `incompleteMachines` (`lib/resolve.nix:393-398`) to test the value the field reader produced -
  `machineFields.${name}.${k}.value == null` - rather than the presence of the declaration key.
  Verify against two throwaway registries: one omitting `address` and one declaring `address = 22`
  both produce `machine-target-incomplete`, and the second also produces
  `declaration-field-malformed`. Both verified: the omission answers
  `[ "machine-target-incomplete" ]` and `address = 22` answers
  `[ "declaration-field-malformed" "machine-target-incomplete" ]`. The predicate is factored as
  `missingTargetKeys`, which both the row and the new `placeable` read, so one list cannot drift
  from the other.
- [x] 2.2 Verify the row's own text still reads correctly with the address in the list: it names the
  machine, every missing key, the registry file as subject, and the entry count from `placementsOn`
  (`lib/resolve.nix:378-400`). Update the evidence sentence, which currently says only that "a
  machine declares the system it runs and the service manager that runs its units", so it names
  where the machine is reached as well. The row now reads "machine `host` declares no `address`, and
  a placement on it has no derivable target", subject `deployment/machines.nix`, resolution
  "declare `address` for `host` in deployment/machines.nix", and two missing keys render as
  "`address`, `serviceManager`". The trailing clause of the evidence also had to move: it read
  "and one entry are placed on it" at a count of one, a disagreement reachable before this change,
  and now reads "and the deployment places one entry on it".
- [x] 2.3 Verify the row is still built with the `diag.error` constructor and that
  `tests/unit/diagnostics.nix`'s purity scan stays green: no `throw`, `abort`, `assert`, `.check ` or
  `korora.check` enters `lib/*.nix` in this change. The row is `diag.error` as before, and
  `diagnostics.testARaisingHelperIsIntroduced`, which is the scan, is green in the 519-test run of
  task 7.1.

## 3. The drop

- [x] 3.1 Split the placement selection in two in `lib/resolve.nix`: keep what a member's selector
  matched (`named ++ concatLists (map tagged tags)` at `:865`) and add the planned form, which is
  that set filtered by target completeness. Extend `placeable` (`:212`) with the completeness clause
  so a named machine and a tagged machine are dropped by one predicate, and leave
  `machine-target-incomplete`, `placementsOn`, `selectedMachines` and `member-not-placed`
  (`:900-911`) computed over the requested form. Verify by evaluating a deployment whose tag selects
  three machines, one of them addressless: two entries are planned, the third is absent, exactly one
  row is produced, and no `member-not-placed` row appears. Verified on a three-machine `fleet` tag:
  the plan carries `machine:alpha`, `machine:beta`, `machine:gamma`, `svc:only@alpha` and
  `svc:only@beta`, the two commands render their own addresses, and the table is exactly
  `[ "machine-target-incomplete" ]`. One refinement the task did not foresee: the tag index
  `machinesByTag` (`:286-296`) filters through the predicate before grouping, so the completeness
  clause cannot go in the predicate the index uses or a tagged machine leaves the requested form
  and eats its own row. `selectable` is therefore registry membership plus the name grammar, used by
  the index and by the requested form, and `placeable` is `selectable` plus completeness, the one
  clause both a named and a tagged machine are dropped by. `design.md` records it.
- [x] 3.2 Make `targetOf` (`lib/resolve.nix:425-438`) return either a record carrying `address`,
  `system` and `serviceManager` or nothing, with no `//` composition of the subset that happened to
  be declared. Verify every `target` in a plan of the worked fixture carries all three and that the
  golden plan is unchanged. All four targeted entries of the worked plan
  (`nightly:client@alpha`, `@beta`, `@gamma`, `vault-repo:server@vault`) record
  `[ "address" "serviceManager" "system" ]`, and `nix eval --json .#debug.worked.plan | jq -S .`
  is equal to `fixtures/minimal-typed-edge/plan/backup.json` as committed. Dropping the two `//`
  applications is also what makes `nrOpUpdateValuesCopied` fall; see task 7.2.
- [x] 3.3 Re-run the throwaway from 1.1 and verify the evaluation now completes, returning a plan
  with the machine's own record, no entry for it, and one error row naming the machine and the
  registry file. This is the acceptance of the whole change. The same expression now answers
  `planKeys = [ "machine:host" "svc:only" ]`, `rows = [ "machine-target-incomplete" ]` and the
  machine's own record with `address = null`: no entry on the machine, and the member recorded as
  the unplaced member it became. Reaching that needed one edit beyond the task list: the member's
  rows were `memberRows ++ (if placements == [ ] then unplaced.rows else [ ])`, and the unplaced
  reading hands `impl` no `target` at all, so this very module ended the evaluation there instead -
  `function 'impl' called without required argument 'target'`, a third failure `builtins.tryEval`
  does not catch, measured on this tree. The condition now reads the requested form. `design.md`
  and `CLAUDE.md` record it, and what survives is that a provider module destructuring
  `{ target, ... }` whose every placement is dropped is still forced through the unplaced entry's
  `provides` record - the documented unplaced-member rule (`docs/authoring.md:337-345`), unchanged
  by this change and reachable without it.
- [x] 3.4 Verify a member whose only placement was dropped reaches the unplaced branch of
  `lib/plan.nix:1045-1055` and is recorded with the selector the deployment wrote, and that a machine
  the deployment selected keeps its `machine:<name>` record (`lib/plan.nix:1076-1093`) even where no
  entry survived on it. `platform.testAMemberPlacedOnlyOntoAnUnaddressedMachine` asserts both: the
  entry `svc:only` carries `key`, `placement` and `settings` with
  `placement = { machines = [ "host" ]; reason = "every"; }`, and `machine:host` is in the plan.
  `lib/plan.nix` needed no edit, as the proposal expected.

## 4. The realiser half

- [x] 4.1 Delete the `operator-entry-machine-no-address` block from `operator/read.nix:286-294`.
  Verify the reading still records `address` as an explicit absence in the deployment record rather
  than omitting the field, and that a hand-written plan with no address for a placed entry builds
  every artifact and produces no row. Deleted, and no file outside `openspec/` names the identifier
  any more. The absence is still explicit: `operator/read.nix:150-151` reads `record.address or null`
  and `address` stays in the record's own field list (`:224`, `:528`). The hand-written addressless
  plan of `operator.testAMachineOfAPlacedEntryDeclaresNoAddress` answers no row at all, carries the
  `address` key with `null`, names the artifact `entries/svc-only-bare` and is not refused.
- [x] 4.2 Verify no realiser account is left naming the deleted row: `image/read.nix:131-137` pairs
  `fieldMissing`, `targetNoPlatform` and `targetNoServiceManager` to `machine-target-incomplete`,
  which this change widens rather than retires, so
  `diagnostics.testARealiserRefusesAConditionNoRowReports` stays green. All three pairings read as
  recorded at `image/read.nix:131`, `:136` and `:137`, no account of any realiser names the deleted
  row, and the whole cross-walk is green in the 519-test run of task 7.1.
- [x] 4.3 Rewrite `operator.testAMachineOfAPlacedEntryDeclaresNoAddress`
  (`tests/unit/operator.nix:1357-1383`) against the new contract: the reading of a hand-written
  addressless plan produces no row, records `address = null`, names the artifact, and is not refused.
  Rewritten, and it asserts exactly those four: `ids = [ ]`, the record carries the `address` key,
  its value is `null`, the artifact is `entries/svc-only-bare` and `refused = false`. The deleted
  block was the only producer of that identifier, so the four assertions are the whole contract.
- [x] 4.4 Update `tests/unit/secrets.nix:685-712`, whose `deploymentRows` expects
  `[ "operator-entry-machine-no-address" ]` and `deploymentSeverities` `[ "warning" ]`, to expect
  neither. `secrets-delivery-machine-no-address` itself stays: it is the row above the secrets
  reading's own refusals (`tests/unit/secrets.nix:520-553`), and what changes is only that a
  planner-produced plan no longer reaches it. Both now expect `[ ]`, the comment above them says
  "no row at all" rather than "a warning", the `secrets-delivery-machine-no-address` assertions are
  untouched, and the secrets suite reports no failure.
- [x] 4.5 Update the docstring of `cli/manifest.py:230-251`, which says the absence "is a warning of
  the planner rather than a refusal". The refusal stays exactly where it is; the reason it can still
  be reached is a record the planner did not write. It now reads that no plan the planner emits
  carries a placed entry whose machine declares no address, and that a record is an interface a
  caller may write by hand, so the reading carries the absence and the refusal is made where the
  machine would be reached. The refusal itself is byte-identical.

## 5. The scenarios

- [x] 5.1 In `tests/unit/platform.nix`, rewrite `testAMachineOmitsItsSystem` and
  `testAMachineOmitsItsServiceManager` to expect the row, the machine's own record in the plan and no
  `svc:only@host` entry, and add `testAMachineOmitsItsAddress` and
  `testAMachineDeclaresAnAddressThatIsNotAName`. Verify each is red against the unpatched tree and
  green after task 3. `testAFullyDeclaredMachine` and `testAMachineChangesArchitecture` must stay
  green untouched. All four are present and green. Redness measured rather than assumed, by
  restoring `b7dd7e1:lib/resolve.nix` over this tree: `nix eval --json .#debug.failuresBySuite.platform`
  then answers the six-name list `testAMachineDeclaresAnAddressThatIsNotAName`,
  `testAMachineOmitsItsAddress`, `testAMachineOmitsItsServiceManager`, `testAMachineOmitsItsSystem`,
  `testAMemberPlacedOnlyOntoAnUnaddressedMachine`,
  `testATagSelectsOneUnaddressedMachineBesideTwoAddressedOnes`, and with the file restored the whole
  tree answers `[ ]`. The two untouched tests are byte-identical across the three commits. One
  refinement: `machinesWith` supplies the address, so each rewritten test still isolates exactly the
  key it omits, and `unaddressed` is the new helper that omits the address instead.
- [x] 5.2 Add `testATagSelectsOneUnaddressedMachineBesideTwoAddressedOnes`,
  `testAMemberPlacedOnlyOntoAnUnaddressedMachine` and `testAMachineNobodyPlacesOnDeclaresNoAddress`
  to `tests/unit/platform.nix`. The third asserts an applicable deployment with no row, which is the
  case that keeps a registry of not-yet-provisioned machines usable. All three present. The first
  two are in the unpatched-tree red list of task 5.1. The third is green either way and is meant to
  be: its `spare` machine declares a tag and a system and nothing else, no placement selects it, and
  the assertion is `rows = [ ]`, `applicable = true`, `planKeys = [ "machine:one" "svc:only@one" ]`.
- [x] 5.3 Add `testEveryPlannedEntryRecordsATargetWithEveryField` and
  `testAModuleNeedsNoGuardToRenderAnAddress` to `tests/unit/platform.nix`. The second places a
  module reading `target.address` unconditionally on every machine of the registry and asserts each
  rendered value carries its own machine's address and that no row is produced. Both present and
  green. Neither is red against the unpatched tree, and the task's own wording is why: each asserts
  the positive contract over a registry every machine of which is addressed, which held before the
  change for the entries that were planned at all. The first names its four targeted entries and
  asserts `[ "address" "serviceManager" "system" ]` for each; the second renders
  `/bin/serve laptop.example:22`, `/bin/serve one.example:22` and `/bin/serve two.example:22` from an
  `impl` carrying no guard, with `rows = [ ]`.
- [x] 5.4 Rewrite `resolution.testAMachineWithNoAddress` (`tests/unit/resolution.nix:811-861`)
  against the plan-artifact delta's restated scenario: the module reads the address with no guard,
  the entry for the addressless machine is absent, the entry for the addressed machine renders, the
  table carries `machine-target-incomplete` and no `module-raised`. Delete the `target ? address`
  guard and the `throw` from the test module, which is the vocabulary this change removes.
  `testAServicePublishesItsOwnEndpoint` (`:787-809`) and
  `testTheAddressAConsumerReadsIsTheProducersNotItsOwn` (`:863-920`) must stay green untouched.
  Rewritten: the module is `publisher`, which reads `ssh://${target.address}/srv` with no guard, and
  neither `target ? address` nor `throw` survives in the suite. Against the unpatched
  `lib/resolve.nix` the resolution suite does not evaluate at all -
  `nix eval --json .#debug.failuresBySuite.resolution` ends in `attribute 'address' missing` at
  `tests/unit/resolution.nix:817`, which is the defect itself rather than a failed comparison -
  and patched the suite answers `[ ]`. Both named tests are untouched by the three commits.
- [x] 5.5 Add `testTheRowOutlivesThePlacementsItDropped`,
  `testOneRowForOneMachineHoweverManyPlacementsSelectedIt`,
  `testTheRowNamesTheKeysTheMachineDidNotDeclare` and `testADroppedPlacementProducesNoModuleRow` to
  `tests/unit/diagnostics.nix`, the last one asserting that deeply forcing both the plan and the
  table succeeds. All four present at `:2348`, `:2383`, `:2423` and `:2454`. Against the unpatched
  `lib/resolve.nix` the diagnostics suite does not evaluate either, ending in `attribute 'address'
  missing` at `:2470`, the unguarded interpolation inside `testADroppedPlacementProducesNoModuleRow`,
  which is what its deep forcing is for. Patched, the suite answers `[ ]` and holds 51 tests.
- [x] 5.6 Add `testABuildOfADeploymentTheRegistryMadeInapplicable` to `tests/unit/operator.nix`:
  `plan.json`, `diagnostics.json` and `diagnostics.txt` are present, no entry artifact is, and the
  rendered table names the machine and the registry file. Present at `tests/unit/operator.nix:1378`
  and the only operator failure against the unpatched `lib/resolve.nix`
  (`failuresBySuite.operator = [ "testABuildOfADeploymentTheRegistryMadeInapplicable" ]`). It asserts
  `applicable = false`, `refused = true`, no row of the reading's own, a plan carrying `machine:bare`
  and `svc:only`, a table carrying only `machine-target-incomplete`, an empty `manifest.entries`, and
  a refusal naming both `bare` and `deployment/machines.nix`.

## 6. Registration and documentation

- [x] 6.1 Move this change's four spec files -
  `refuse-a-placement-onto-an-unaddressed-machine/specs/planner/machine-platform/spec.md`,
  `.../specs/planner/plan-artifact/spec.md`, `.../specs/planner/diagnostics/spec.md` and
  `.../specs/operator/deployment-build/spec.md` - from `excused` to `accountable` in
  `tests/unit/coverage.nix` (`:112-208`, `:212-235`); the excuse "an unimplemented change" expires
  the moment a task of this change is ticked. Verify the coverage suite classifies every
  specification and that each scenario heading above finds the test name it derives. Moved, and the
  four excuses are deleted rather than left beside the new entries. The coverage suite is green in
  the 519-test run of task 7.1, which is both halves of the cross-walk: every specification is
  classified and every scenario heading of the four delta specs finds the test its name derives.
- [x] 6.2 Update `docs/diagnostics.md`: the `machine-target-incomplete` row description (`:138`) now
  names the address, and the `operator-entry-machine-no-address` row (`:268`) is deleted. Verify
  `diagnostics.testADocumentTabulatesARowTheTreeCannotProduce` (`tests/unit/diagnostics.nix:2053-2064`)
  and `testTheLibraryGainsARow` (`:2042-2051`) are both green, which is what holds the document and
  the sources to the same row set in both directions. Delete the same row from the table in
  `docs/operator.md:260`. All three edits made and both guards green. One line the task did not
  name also had to move: the `secrets-delivery-machine-no-address` description said the condition is
  "a warning of a deployment build", which is now no row of a deployment build at all.
- [x] 6.3 Update `docs/authoring.md`: the registry table (`:727-740`) marks `address` required once a
  placement selects the machine, the paragraph at `:346-350` that tells an author to read
  `target.address` "under `target ? address`" is replaced by the statement that a planned entry's
  target carries all three fields, and the sentence at `:337-344` about a machine with no target
  names the address too. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
  All three done, and the table marks `system` and `serviceManager` required on the same terms so
  the three target keys read alike. `nix build .#checks.x86_64-linux.treefmt` exits 0.
- [x] 6.4 Update `CLAUDE.md`: under Keys and identity, beside the rule that a name carrying a key
  separator is refused and left out of every key, record that a machine a placement selects must
  declare an address, a system and a service manager, that the placement is dropped rather than
  planned because a row cannot prevent an uncatchable missing attribute, and that completeness is
  read off the field value so a malformed declaration is as incomplete as an absent one. Under
  Realisers, replace the `operator-entry-machine-no-address` paragraph (`CLAUDE.md:440-442`) with the
  record that the row is gone, that the deployment record still carries the absence and that the
  command still refuses at the point of dialling. In the same section, correct "Four of its
  conditions are reachable from a plan the planner calls applicable" for the secrets reading: a
  recipient machine with no address is no longer one of them, so the sentence names three. All four
  edits made. Two additions the task did not list: the `tryEval` bullet under Purity and totality
  now names the third uncatchable failure task 3.3 measured, a function called without a required
  argument, and a second Keys and identity bullet records that the unplaced reading of a member is
  produced only where the selector matched nothing, which is the edit task 3.3 needed.

## 7. Verification

- [x] 7.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the golden plan comparison and the fixture's `diagnostics.txt` byte comparison, which
  must both be unchanged per task 1.2. Exits 0 with `519/519 successful`, which is the figure
  `docs/tooling.md` now records. Both comparisons are among them, and no file under `fixtures/` is
  touched by any commit of this change, so no golden moved.
- [x] 7.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  selection is read twice and the completeness predicate now reads three values per selected
  machine, both linear in placements, so record the measured cost per entry for sizes 64 and 256 if
  the margin moved by more than half of the 0.15 allowance. The gate exits 1, and it exits 1 at
  `b7dd7e1` too: the same check built from the base answers `81 failures, 0 invalid comparisons,
  81 of 81 gated figures compared`, and this tree answers `72 failures` of the same 81. The nine
  figures that stopped failing are `nrOpUpdateValuesCopied` at every fixture, which is the two `//`
  applications task 3.2 removed from `targetOf`: fleet-64 8.2850 to 7.6218 per plan entry against a
  budget of 8.2591, fleet-256 6.8232 to 6.1574 against 6.8167, mesh-64 8.6114 to 7.9482 against
  8.5855, mesh-256 7.1548 to 6.4890 against 7.1483 - a fall of 7.7% to 9.8%, past half the 0.15
  allowance, so recorded here. Every other figure at sizes 64 and 256 moved by at most +1.21%
  (`nrFunctionCalls`, fleet-256 247.7634 to 250.7686; fleet-64 257.0052 to 260.0260; mesh-64
  315.5441 to 318.5648; mesh-256 306.6476 to 309.6528), with `envs.bytes` next at +0.94% and every
  byte counter and every growth ratio within noise. No budget was edited and none was made to pass.
- [x] 7.3 Run `nix run .#planner-e2e wired-pair` and verify a deployment this change does not
  concern applies unchanged. `37 passed in 56.41s`, exit 0.
