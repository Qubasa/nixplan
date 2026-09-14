## 1. Record what exists

- [ ] 1.1 Reproduce the defect before editing anything: a registry declaring one machine with a
  `system` and a `serviceManager` and no `address`, one module whose unit command interpolates
  `${target.address}`, one placement onto it, and `mkPlan` forced. Verify the failure is
  `error: attribute 'address' missing` with no diagnostics table, and keep the throwaway expression
  as the before-and-after comparison for task 3.3.
- [ ] 1.2 Verify no golden can move, by reading rather than by assuming: every machine of
  `fixtures/minimal-typed-edge/deployment/machines.nix` declares an address (`vault.example`,
  `alpha.example`, `beta.example`, `gamma.example` at `:6-38`), `perf/fleet.nix:152-157` and
  `perf/mesh.nix:186-191` declare `${name}.fleet.example:22` and `${name}.mesh.example:22` for every
  generated machine, and every end-to-end registry declares one
  (`tests/e2e/shared-postgres/deployment/machines.nix:12-27`,
  `tests/e2e/newcomer/template/deployment/machines.nix:2-14`). `fixtures/minimal-typed-edge/plan/*`
  and `fixtures/minimal-typed-edge/plan/diagnostics.txt` therefore stay byte-equal, and no
  regeneration with `nix eval --json .#debug.worked.plan | jq -S .` is part of this change. Record
  the reading in this task; if a machine without an address is found, the goldens move and that has
  to be said here before any edit.
- [ ] 1.3 Record the three expectations this change reverses, so each is rewritten rather than
  re-pinned: `resolution.testAMachineWithNoAddress` (`tests/unit/resolution.nix:811-861`, which pins
  the `if target ? address then ... else throw` guard and expects `module-raised`),
  `platform.testAMachineOmitsItsSystem` and `platform.testAMachineOmitsItsServiceManager`
  (`tests/unit/platform.nix:98-150`, which expect `svc:only@host` in the plan with a partial
  `target`), and `operator.testAMachineOfAPlacedEntryDeclaresNoAddress`
  (`tests/unit/operator.nix:1357-1383`, which expects the warning).

## 2. The registry reading

- [ ] 2.1 Add `"address"` to `machineTargetKeys` (`lib/resolve.nix:50-53`) and change
  `incompleteMachines` (`lib/resolve.nix:393-398`) to test the value the field reader produced -
  `machineFields.${name}.${k}.value == null` - rather than the presence of the declaration key.
  Verify against two throwaway registries: one omitting `address` and one declaring `address = 22`
  both produce `machine-target-incomplete`, and the second also produces
  `declaration-field-malformed`.
- [ ] 2.2 Verify the row's own text still reads correctly with the address in the list: it names the
  machine, every missing key, the registry file as subject, and the entry count from `placementsOn`
  (`lib/resolve.nix:378-400`). Update the evidence sentence, which currently says only that "a
  machine declares the system it runs and the service manager that runs its units", so it names
  where the machine is reached as well.
- [ ] 2.3 Verify the row is still built with the `diag.error` constructor and that
  `tests/unit/diagnostics.nix`'s purity scan stays green: no `throw`, `abort`, `assert`, `.check ` or
  `korora.check` enters `lib/*.nix` in this change.

## 3. The drop

- [ ] 3.1 Split the placement selection in two in `lib/resolve.nix`: keep what a member's selector
  matched (`named ++ concatLists (map tagged tags)` at `:865`) and add the planned form, which is
  that set filtered by target completeness. Extend `placeable` (`:212`) with the completeness clause
  so a named machine and a tagged machine are dropped by one predicate, and leave
  `machine-target-incomplete`, `placementsOn`, `selectedMachines` and `member-not-placed`
  (`:900-911`) computed over the requested form. Verify by evaluating a deployment whose tag selects
  three machines, one of them addressless: two entries are planned, the third is absent, exactly one
  row is produced, and no `member-not-placed` row appears.
- [ ] 3.2 Make `targetOf` (`lib/resolve.nix:425-438`) return either a record carrying `address`,
  `system` and `serviceManager` or nothing, with no `//` composition of the subset that happened to
  be declared. Verify every `target` in a plan of the worked fixture carries all three and that the
  golden plan is unchanged.
- [ ] 3.3 Re-run the throwaway from 1.1 and verify the evaluation now completes, returning a plan
  with the machine's own record, no entry for it, and one error row naming the machine and the
  registry file. This is the acceptance of the whole change.
- [ ] 3.4 Verify a member whose only placement was dropped reaches the unplaced branch of
  `lib/plan.nix:1045-1055` and is recorded with the selector the deployment wrote, and that a machine
  the deployment selected keeps its `machine:<name>` record (`lib/plan.nix:1076-1093`) even where no
  entry survived on it.

## 4. The realiser half

- [ ] 4.1 Delete the `operator-entry-machine-no-address` block from `operator/read.nix:286-294`.
  Verify the reading still records `address` as an explicit absence in the deployment record rather
  than omitting the field, and that a hand-written plan with no address for a placed entry builds
  every artifact and produces no row.
- [ ] 4.2 Verify no realiser account is left naming the deleted row: `image/read.nix:131-137` pairs
  `fieldMissing`, `targetNoPlatform` and `targetNoServiceManager` to `machine-target-incomplete`,
  which this change widens rather than retires, so
  `diagnostics.testARealiserRefusesAConditionNoRowReports` stays green.
- [ ] 4.3 Rewrite `operator.testAMachineOfAPlacedEntryDeclaresNoAddress`
  (`tests/unit/operator.nix:1357-1383`) against the new contract: the reading of a hand-written
  addressless plan produces no row, records `address = null`, names the artifact, and is not refused.
- [ ] 4.4 Update `tests/unit/secrets.nix:685-712`, whose `deploymentRows` expects
  `[ "operator-entry-machine-no-address" ]` and `deploymentSeverities` `[ "warning" ]`, to expect
  neither. `secrets-delivery-machine-no-address` itself stays: it is the row above the secrets
  reading's own refusals (`tests/unit/secrets.nix:520-553`), and what changes is only that a
  planner-produced plan no longer reaches it.
- [ ] 4.5 Update the docstring of `cli/manifest.py:230-251`, which says the absence "is a warning of
  the planner rather than a refusal". The refusal stays exactly where it is; the reason it can still
  be reached is a record the planner did not write.

## 5. The scenarios

- [ ] 5.1 In `tests/unit/platform.nix`, rewrite `testAMachineOmitsItsSystem` and
  `testAMachineOmitsItsServiceManager` to expect the row, the machine's own record in the plan and no
  `svc:only@host` entry, and add `testAMachineOmitsItsAddress` and
  `testAMachineDeclaresAnAddressThatIsNotAName`. Verify each is red against the unpatched tree and
  green after task 3. `testAFullyDeclaredMachine` and `testAMachineChangesArchitecture` must stay
  green untouched.
- [ ] 5.2 Add `testATagSelectsOneUnaddressedMachineBesideTwoAddressedOnes`,
  `testAMemberPlacedOnlyOntoAnUnaddressedMachine` and `testAMachineNobodyPlacesOnDeclaresNoAddress`
  to `tests/unit/platform.nix`. The third asserts an applicable deployment with no row, which is the
  case that keeps a registry of not-yet-provisioned machines usable.
- [ ] 5.3 Add `testEveryPlannedEntryRecordsATargetWithEveryField` and
  `testAModuleNeedsNoGuardToRenderAnAddress` to `tests/unit/platform.nix`. The second places a
  module reading `target.address` unconditionally on every machine of the registry and asserts each
  rendered value carries its own machine's address and that no row is produced.
- [ ] 5.4 Rewrite `resolution.testAMachineWithNoAddress` (`tests/unit/resolution.nix:811-861`)
  against the plan-artifact delta's restated scenario: the module reads the address with no guard,
  the entry for the addressless machine is absent, the entry for the addressed machine renders, the
  table carries `machine-target-incomplete` and no `module-raised`. Delete the `target ? address`
  guard and the `throw` from the test module, which is the vocabulary this change removes.
  `testAServicePublishesItsOwnEndpoint` (`:787-809`) and
  `testTheAddressAConsumerReadsIsTheProducersNotItsOwn` (`:863-920`) must stay green untouched.
- [ ] 5.5 Add `testTheRowOutlivesThePlacementsItDropped`,
  `testOneRowForOneMachineHoweverManyPlacementsSelectedIt`,
  `testTheRowNamesTheKeysTheMachineDidNotDeclare` and `testADroppedPlacementProducesNoModuleRow` to
  `tests/unit/diagnostics.nix`, the last one asserting that deeply forcing both the plan and the
  table succeeds.
- [ ] 5.6 Add `testABuildOfADeploymentTheRegistryMadeInapplicable` to `tests/unit/operator.nix`:
  `plan.json`, `diagnostics.json` and `diagnostics.txt` are present, no entry artifact is, and the
  rendered table names the machine and the registry file.

## 6. Registration and documentation

- [ ] 6.1 Move this change's four spec files -
  `refuse-a-placement-onto-an-unaddressed-machine/specs/planner/machine-platform/spec.md`,
  `.../specs/planner/plan-artifact/spec.md`, `.../specs/planner/diagnostics/spec.md` and
  `.../specs/operator/deployment-build/spec.md` - from `excused` to `accountable` in
  `tests/unit/coverage.nix` (`:112-208`, `:212-235`); the excuse "an unimplemented change" expires
  the moment a task of this change is ticked. Verify the coverage suite classifies every
  specification and that each scenario heading above finds the test name it derives.
- [ ] 6.2 Update `docs/diagnostics.md`: the `machine-target-incomplete` row description (`:138`) now
  names the address, and the `operator-entry-machine-no-address` row (`:268`) is deleted. Verify
  `diagnostics.testADocumentTabulatesARowTheTreeCannotProduce` (`tests/unit/diagnostics.nix:2053-2064`)
  and `testTheLibraryGainsARow` (`:2042-2051`) are both green, which is what holds the document and
  the sources to the same row set in both directions. Delete the same row from the table in
  `docs/operator.md:260`.
- [ ] 6.3 Update `docs/authoring.md`: the registry table (`:727-740`) marks `address` required once a
  placement selects the machine, the paragraph at `:346-350` that tells an author to read
  `target.address` "under `target ? address`" is replaced by the statement that a planned entry's
  target carries all three fields, and the sentence at `:337-344` about a machine with no target
  names the address too. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
- [ ] 6.4 Update `CLAUDE.md`: under Keys and identity, beside the rule that a name carrying a key
  separator is refused and left out of every key, record that a machine a placement selects must
  declare an address, a system and a service manager, that the placement is dropped rather than
  planned because a row cannot prevent an uncatchable missing attribute, and that completeness is
  read off the field value so a malformed declaration is as incomplete as an absent one. Under
  Realisers, replace the `operator-entry-machine-no-address` paragraph (`CLAUDE.md:440-442`) with the
  record that the row is gone, that the deployment record still carries the absence and that the
  command still refuses at the point of dialling. In the same section, correct "Four of its
  conditions are reachable from a plan the planner calls applicable" for the secrets reading: a
  recipient machine with no address is no longer one of them, so the sentence names three.

## 7. Verification

- [ ] 7.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the golden plan comparison and the fixture's `diagnostics.txt` byte comparison, which
  must both be unchanged per task 1.2.
- [ ] 7.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  selection is read twice and the completeness predicate now reads three values per selected
  machine, both linear in placements, so record the measured cost per entry for sizes 64 and 256 if
  the margin moved by more than half of the 0.15 allowance.
- [ ] 7.3 Run `nix run .#planner-e2e wired-pair` and verify a deployment this change does not
  concern applies unchanged.
