## 1. The member a module is

- [ ] 1.1 Add `member = mname` to `implArgs` in `lib/resolve.nix:1199-1206`, beside `instance`, and
  verify by evaluating a deployment whose implementation interpolates it: the value equals the
  attribute key the composing root declared the member under.
- [ ] 1.2 Add the four scenarios of `specs/planner/plan-artifact/spec.md` to `tests/unit/resolution.nix`
  as `testAnImplementationDerivesANameFromItsOwnEntry`,
  `testTwoMembersOfOneInstanceDeriveTwoNames`, `testTheMemberHandedIsTheAttributeKeyOfTheMember` and
  `testAModuleThatIgnoresTheArgumentPlansAsItDid`, and verify each fails against the unpatched
  `lib/resolve.nix` and passes after 1.1. The last one compares the entry keys of a deployment whose
  modules read neither argument against the keys recorded before the change.
- [ ] 1.3 Verify no golden moves: `nix eval --json .#debug.worked.plan | jq -S .` equals
  `fixtures/minimal-typed-edge/plan/*` as committed, and
  `nix build .#checks.x86_64-linux.planner-tests` still reports `testTheGoldenPlanMatches` green.

## 2. The claim index

- [ ] 2.1 In `lib/plan.nix`, have `placedEntry` return a fourth field `claims = { machine, paths,
  ports, directories }` built from `configData.record`, `member.alloc.ports` and `placement.units`
  (the extension applications' `runtimeDirectory`, `stateDirectory` and `cacheDirectory` values, read
  the way `groupsOf` reads `supplementaryGroups` at `lib/plan.nix:325-343`), each de-duplicated within
  the entry. Verify by evaluating the worked fixture and reading the claims of
  `vault-repo:server@vault`: one path, one port, no directory.
- [ ] 2.2 Add `collisionRows` to `lib/plan.nix`, called from `entries` (`lib/plan.nix:877-964`) over
  the placed entries' claims: group by machine, then by resource, emit one row per resource with more
  than one claimant, subject the row to the first claimant in sorted plan-key order, and name every
  claimant, the machine and the resource. Identifiers `entry-host-path-claimed-twice` (error),
  `entry-port-claimed-twice` (error), `entry-unit-directory-shared` (warning). Verify with a
  throwaway deployment placing two members on one machine that both write `/etc/x.conf`: the table
  carries exactly one error row naming both keys.
- [ ] 2.3 Verify the rows are built with `planner.row`-family constructors and carry an `evidence`
  and a `resolution` naming derivation from `instance` and `member`, and that
  `tests/unit/diagnostics.nix`'s purity scan and row/refusal cross-walk stay green
  (`nix build .#checks.x86_64-linux.planner-tests`).

## 3. The rows' scenarios

- [ ] 3.1 Add `testTwoEntriesOnOneMachineWriteOneHostPath`, `testTwoEntriesOnOneMachineClaimOnePort`
  and `testTwoEntriesOnOneMachineShareOneUnitDirectory` to `tests/unit/plan.nix`, each asserting the
  identifier, the severity, the subject and that both plan keys and the machine appear in the message.
  Verify each is red before task 2.2 and green after.
- [ ] 3.2 Add the three negative scenarios -
  `testOneMemberPlacedOnTwoMachinesClaimsItsPathOnEach`, `testTwoUnitsOfOneEntryShareItsDirectory`
  and `testACollisionIsReportedOnceAndNamesBothEntries` - to `tests/unit/plan.nix`. Verify the first
  two produce an empty row list for the new identifiers and the third produces exactly one row over
  three claimants.
- [ ] 3.3 Verify a UDP claim and a TCP claim of one number on one machine produce no row, inside
  `testTwoEntriesOnOneMachineClaimOnePort`.

## 4. Registration and documentation

- [ ] 4.1 Move `refuse-two-entries-claiming-one-host-resource/specs/planner/diagnostics/spec.md` and
  `.../specs/planner/plan-artifact/spec.md` from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse expires the moment a task of this change is ticked - and
  verify `testEverySpecificationIsClassified`, `testNoExcuseOutlivesItsChange`-class staleness and
  the scenario cross-walk are green: each scenario heading must find the test name it derives.
- [ ] 4.2 Add the three identifiers to `docs/diagnostics.md` in a section of their own, and name
  `member` beside `instance` and `machine` wherever `docs/authoring.md` lists the implementation
  arguments. Verify `nix build .#checks.x86_64-linux.treefmt` (vale included) passes.
- [ ] 4.3 Record in `CLAUDE.md` under Diagnostics: a host resource two entries of one machine claim
  is a row, which claims are read and from where, why the directory row is a warning while the other
  two are errors, and that `member` is in the implementation arguments so a module can name a
  resource after its entry rather than after itself.

## 5. Verification

- [ ] 5.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including the fixture's `diagnostics.txt` byte comparison, which must be unchanged.
- [ ] 5.2 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold; record
  the measured cost per entry for sizes 64 and 256 in the task list if the margin moved by more than
  half of the 0.15 allowance.
- [ ] 5.3 Verify one end-to-end folder still applies unchanged - `nix run .#planner-e2e wired-pair` -
  so that a deployment the rows do not concern is untouched.
