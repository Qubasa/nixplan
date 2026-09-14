## 1. The registry field

- [ ] 1.1 Add `number = { what = "a number"; is = builtins.isInt; }` to `shapes`
  (`lib/resolve.nix:64-85`). Verify by reading a registry that states a port as `"22"`: the table
  carries one `declaration-field-malformed` row naming the machine, the field and "a number", and the
  rest of the registry is still read.
- [ ] 1.2 Add `"reserves"` to `machineRegistryKeys` (`lib/resolve.nix:42-48`). Verify a machine
  declaring `reserves` earns no `declaration-unknown-key` row and a machine declaring `reservations`
  still does, with the row listing all six admitted keys.
- [ ] 1.3 Read the field in `machineFields` (`lib/resolve.nix:268-274`): `reserves` with
  `shapes.record` and a fallback of `{ }`, then inside it `ports` with `shapes.record` and `paths`
  with `shapes.names`, then each `ports.<name>` with `proto` read the way a claim's protocol is read
  and `number` with `shapes.number`. Every row joins `machineFieldRows` (`lib/resolve.nix:276-282`)
  so it is subjected to the registry file. Verify each malformed shape produces exactly one row and
  the machine's other fields still read.
- [ ] 1.4 Project the reading into a `machineReservations` table beside `targets`
  (`lib/resolve.nix:440`) and publish it on `resolved` beside `machines` and `usedMachines`
  (`lib/resolve.nix:1984-2004`). Do not touch `machineRecords` (`lib/resolve.nix:402-419`) or
  `targetOf` (`lib/resolve.nix:425-438`). Verify by evaluating a deployment whose machine reserves a
  port: `resolved.machines.<name>` has the attribute names it had, and `machineKey` of it is the
  string it was before the reservation was written.

## 2. The machine as a claimant

- [ ] 2.1 In `lib/plan.nix`, turn the reservations of each machine in `resolved.usedMachines` into
  claims of the shape `claimsOf` already returns - `{ key = "machine:<name>"; machine; kind; name; }`
  - with `kind = "ports"` named `"<proto>/<number>"` in the spelling `portsOf` uses
  (`lib/plan.nix:701-709`) and `kind = "paths"` named by the host path, and append them to the flat
  list at `lib/plan.nix:1098`. `collisionRows` (`lib/plan.nix:733-757`) is not edited. Verify with a
  throwaway deployment whose machine reserves `tcp/22` and whose placed entry claims it: the table
  carries exactly one `entry-port-claimed-twice` error naming both claimants.
- [ ] 2.2 Reword the `hostResources` message template (`lib/plan.nix:750`) so it names the machine and
  lists its claimants without calling them entries, and extend the `resolution` of the `paths` and
  `ports` resources (`lib/plan.nix:644-656`) to name the registry's reservation as well as the
  entry's claim where a reservation is among the claimants. Verify both texts: an entry-to-entry
  collision resolves to deriving the resource from `instance` and `member` as it did, and a
  reservation collision names both declarations.
- [ ] 2.3 Verify no plan field is added: the machine record built at `lib/plan.nix:1078-1093` carries
  the same keys it did, `pruned` is untouched, and a reservation appears in no entry's `keyInput`
  (`lib/plan.nix:786-803`). Read `debug.worked.plan` for a machine and compare its attribute names
  against the committed `fixtures/minimal-typed-edge/plan/backup.json`.
- [ ] 2.4 Verify the rows are still built by the `hostResources` constructors and that
  `tests/unit/diagnostics.nix` stays green: no `throw`, `abort`, `assert`, `.check ` or
  `korora.check` enters `lib/`, and the row-versus-refusal cross-walk is unmoved because this change
  introduces no identifier.

## 3. The scenarios

- [ ] 3.1 Add the registry scenarios of `specs/planner/machine-platform/spec.md` to
  `tests/unit/resolution.nix` as `testAMachineReservesAPortAndAHostPath`,
  `testAMachineStatesNoReservation`, `testAReservationOfTheWrongShape` and
  `testAReservationIsADeclarationAndNotAProbe`. The last one plans two deployments differing only in
  a reserved path, one that exists on the evaluating host and one that cannot, and compares their row
  lists and their plans for equality. Verify each is red before task 1.3 and green after.
- [ ] 3.2 Add `testAMachineThatReservesAPortKeysAsItDid` to `tests/unit/plan.nix`: plan one deployment
  twice, once with the machine's reservation and once without, and assert every plan key, every
  machine key and every generated value key is equal. Verify it is red against a build that records
  the reservation in `machineRecords` and green against task 1.4.
- [ ] 3.3 Add the collision scenarios to `tests/unit/plan.nix` as
  `testAMachineReservesAPortAnEntryClaims`, `testAMachineReservesAPathAnEntryWrites` and
  `testAMachineAndTwoEntriesClaimOnePort`, each asserting the identifier, the severity, the subject
  and that the machine's key, every entry key and the resource appear in the message. The third
  asserts one row over three claimants, subjected to the first of the three plan keys in order.
  Verify each is red before task 2.1 and green after.
- [ ] 3.4 Add the negative scenarios to `tests/unit/plan.nix` as
  `testAMachineReservesAPortNothingClaims`, `testAReservationOnAMachineNoPlacementSelects` and
  `testAReservedPortAndAClaimOnAnotherProtocol`. Verify each produces an empty row list for both
  identifiers, and that the second leaves no row of the table subjected to that machine.

## 4. The goldens

- [ ] 4.1 Verify no golden moves: `nix eval --json .#debug.worked.plan | jq -S .` equals
  `fixtures/minimal-typed-edge/plan/backup.json` as committed, and the fixture's
  `plan/diagnostics.txt` comparison is unchanged. No machine of `fixtures/minimal-typed-edge`,
  `perf/fleet.nix:156` or `perf/mesh.nix:190` declares a reservation, and the plan records the field
  nowhere, so there is nothing for `pruned` to drop and no regeneration to run.
- [ ] 4.2 Do not add a reservation to `fixtures/minimal-typed-edge/deployment/machines.nix`. `vault`
  runs a `borg-repo` server claiming `tcp/22`
  (`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:14-18`), so reserving that port there
  makes the worked deployment inapplicable and moves both goldens. Verify by stating the case in a
  throwaway deployment of `tests/unit/plan.nix` instead, and by checking the fixture's registry is
  untouched in the diff.

## 5. Registration and documentation

- [ ] 5.1 Move `reserve-what-a-machine-already-holds/specs/planner/machine-platform/spec.md` and
  `.../specs/planner/diagnostics/spec.md` from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse says the change is unimplemented, and it expires the moment
  a task above is ticked. Verify `testEverySpecificationIsClassified` is green and the scenario
  cross-walk finds every `test<Name>` task 3 adds, with no name defined in both the unit and the
  end-to-end layer.
- [ ] 5.2 Correct `docs/authoring.md`: the machine key table (`docs/authoring.md:727-733`) gains the
  reservation row, and the sentence "A machine declares those five keys and nothing else"
  (`docs/authoring.md:735`) becomes the six it now declares. Add a short paragraph beneath it showing
  the shape, saying that an absent statement checks nothing, that no realiser reads it and that the
  planner never reads the machine. Verify `nix build .#checks.x86_64-linux.treefmt` passes, vale
  included.
- [ ] 5.3 Update `docs/diagnostics.md`: the section at `docs/diagnostics.md:232-245` is headed "What
  two entries of one machine both claim" and now also holds what a machine and an entry both claim.
  Restate the heading and the prose above the table, extend the `entry-host-path-claimed-twice` and
  `entry-port-claimed-twice` descriptions with the reservation half, and say that
  `entry-unit-directory-shared` has none because a unit directory name is not a host path the
  registry can state. Add no identifier to the table.
- [ ] 5.4 Record the invariant in `CLAUDE.md`: under Diagnostics, beside the paragraph about a host
  resource two entries of one machine claim, that a machine may state what it already holds, that the
  statement is a claimant keyed `machine:<name>` taking part in the same ordering, that it earns the
  existing rows rather than new ones, and that the directory claim has no reservation half; under
  Keys and identity, that the statement is deliberately outside `machineRecords` and `targetOf`,
  because `machineKey` hashes the record and every placed entry and per-placement value depends on it
  (`lib/plan.nix:778`, `lib/plan.nix:955`), so recording it would ask for a redelivery and a
  regeneration of bytes that are still correct.

## 6. Verification

- [ ] 6.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the golden plan comparison and the fixture's `diagnostics.txt` byte comparison. This
  change adds four tests to `resolution` and seven to `plan`; reconcile the per-suite figures of
  `docs/tooling.md` if that suite names them.
- [ ] 6.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold. The
  reading grows by one field per machine and the claim list by one entry per reserved resource, and
  no fixture of `perf/` reserves anything, so the expectation is an unmoved figure; record the
  measured cost per entry for sizes 64 and 256 if the margin moves by more than half of the 0.15
  allowance.
