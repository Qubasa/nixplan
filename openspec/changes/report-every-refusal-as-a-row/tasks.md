# Tasks

Ordered so that each phase leaves the tree green. The row constructor lands first, because every
phase after it writes rows. The plan record and the planner's own rows land second, so that the
smallest documented deployment builds while only the library has changed. The reading gains its
refusals third, fourth and fifth, one kind of fact per phase. The build's own answers land sixth, and
the realisers are narrowed last, when every row they lean on exists.

Each scenario's test belongs to exactly one layer. A fact about evaluation is a nix-unit suite under
`tests/unit/`; a fact needing a real `nix` invocation or a booted machine is an end-to-end test under
`tests/e2e/<folder>/`. Two scenarios of this change are end-to-end and the rest are unit.

## 1. One constructor for a row

- [x] 1.1 `lib/default.nix`: export `row`, `error` and `warning` beside `render` and `mkTable`
  (`lib/default.nix:70-73`). Nothing else about the library changes: the constructor is already the
  only place that applies `util.oneLine` to a message, an evidence line and a resolution
  (`lib/diagnostics.nix:33-47`). Verify `nix eval .#lib --apply builtins.attrNames` lists the three
  new names and `nix build .#checks.x86_64-linux.planner-tests` is unchanged.
- [x] 1.2 `operator/read.nix`: build every row through `planner.error` and `planner.warning` rather
  than writing the six fields by hand (`:126-152`, `:164-185`). Verify the rows of
  `tests/unit/operator.nix` are equal field for field to the ones recorded before this task, and
  that a plan key carrying a line break renders as one line in
  `planner.render`.
- [x] 1.3 `tests/unit/diagnostics.nix`: add `testARowIsBuiltOutsideTheLibrary` (scenario "A row is
  built outside the library") and `testAMemberNameCarriesALineBreak` (scenario "A member name
  carries a line break"). Both unit layer. Verify each fails when `operator/read.nix` writes a row
  literal again.

## 2. The plan records what a realisation reads

- [x] 2.1 `lib/plan.nix`: exempt `closure` and `units` from `pruned` for a placed entry (`:22`,
  `:559-583`), leaving the unplaced entry and the value entry as they are. Verify the plan of the
  example at `docs/README.md:52-125` carries `closure = [ ]` on `hearer:main@host` and `units = { }`
  on `talker:main@host`, and that `nix eval` of both entries through `image/read.nix` no longer
  raises about a field the entry does not record.
- [x] 2.2 `tests/unit/plan.nix`: add `testAUnitNamesNoStorePath`, `testAPlacedServiceRunsNoUnit` and
  `testAnEntryThatIsPlacedNowhereRecordsNoUnit` (the three scenarios of
  `specs/planner/plan-artifact/spec.md`). All unit layer. Verify each fails against the tree as it
  stood before 2.1, except the third, which passes before and after and is the guard on the
  exemption's boundary.
- [x] 2.3 `fixtures/minimal-typed-edge/plan/plan.json`: regenerate with
  `nix eval --json .#planner.worked.plan | jq -S .` and record here which entries gained which
  field. `diagnostics.txt` and `diagnostics.json` do not move, because no row changes. Verify
  `tests/unit/worked.nix` compares equal and the fixture carries no `...` and no hash that is not
  sixteen hex digits.
  - The golden is `fixtures/minimal-typed-edge/plan/backup.json`, and the regeneration is a no-op:
    the output of the command is byte identical to the committed file. No entry gained a field,
    because all four placed entries of the fixture already declare a closure root and a unit. The
    folder carries no `diagnostics.json`; its rendered table is `plan/diagnostics.txt` and it does
    not move either.
- [x] 2.4 `lib/plan.nix` and `lib/resolve.nix`: the three new planner rows of
  `specs/planner/diagnostics/spec.md` - an error for a unit value containing a line break, an error
  for a declared closure root that is not a path under the plan's store directory, and an error for a
  declared closure root the plan also records as a delivered reference. Each names the entry and the
  field, and each is the condition `image/read.nix:355`, `:343` and `:345` refuse. Verify the three
  conditions each produce one row and leave the rest of the plan readable.
- [x] 2.5 `tests/unit/plan.nix` and `tests/unit/closure.nix`: add
  `testAUnitValueNoUnitFileHasALineFor`, `testADeclaredClosureRootIsNotAStorePath` and
  `testADeclaredClosureRootArrivesByDelivery` (three scenarios of
  `specs/planner/diagnostics/spec.md`). All unit layer. Verify each row's identifier, subject and
  severity, and that the plan still carries the entry the row is about.

## 3. The reading classifies by shape

- [x] 3.1 `operator/read.nix`: replace `isMachineRecord` (`:49`) and `isValueEntry` (`:51`) with
  tests of the record - a delivery set for a generated value, a placement for a service entry,
  neither for a machine record - and read a key only for the instance, service and machine of a
  placed service entry, split at its last separator. A record matching none of the three shapes is an
  error row naming the key and the shapes. Verify a deployment with an instance called `machine`
  builds an artifact for it, and a member named inside the value namespace reads without a missing
  attribute.
- [x] 3.2 `operator/read.nix`: a placed entry declaring no unit is realised into nothing - present
  in the deployment record, contributing no artifact, producing no row - and a statement naming such
  an entry is an error row. Verify `talker:main@host` of the documented example appears in the record
  with its machine, that the build produces one artifact and not two, and that stating a realiser for
  it is refused naming the entry.
- [x] 3.3 `tests/unit/operator.nix`: add `testAnInstanceIsNamedMachine`,
  `testAMemberIsNamedInsideTheValueNamespace`, `testAKeyMatchesNoShapeThePlanCarries` and
  `testAPlacedEntryDeclaresNoUnit` (the four scenarios of `Every record of a plan is classified by
  the shape of its record`). All unit layer. Verify the second fails with a missing attribute against
  the tree before 3.1, which is the abort the change removes.

## 4. The reading answers the whole statement

- [x] 4.1 `operator/read.nix`: resolve the statement field by field down the three steps it is
  already read by (`:70-82`, `:102-106`), so `profile` inherits from `realise.default` the way
  `realiser` does. Verify a deployment stating `default = { realiser = "image"; profile = "strict";
  }` and `"svc:only" = { realiser = "image"; }` builds under `strict` and produces no row.
- [x] 4.2 `operator/read.nix`: a statement key that is neither a plan key nor a prefix of one is an
  error row naming the key given and the keys the plan carries; a statement that is not a record is
  an error row naming the entry and what was found. Verify `realise."svc:onlyy"` is refused and that
  `realise."svc:only" = "image"` is refused rather than read as the default.
- [x] 4.3 `operator/read.nix`: a stated profile outside `imageReader.profileNames` is an error row
  naming the entry, the profile stated and the profiles that exist - the sentence the row's
  resolution already writes for an absent profile (`:135-142`). Verify `profile = "stricT"` is
  refused by the reading and never reaches `image/read.nix:195-199`.
- [x] 4.4 `tests/unit/operator.nix`: rewrite `testAnEntryStatesNoRealiser`, whose `elsewhere` case
  (`:236-256`) records a statement about a key the plan does not carry as intended, and add
  `testAProfileIsInheritedFromTheDefaultStatement`, `testAStatedProfileIsOutsideTheDomain`,
  `testAStatementNamesAnEntryThePlanDoesNotCarry` and `testAStatementIsNotARecord`. All unit layer.
  Verify the rewritten test asserts a row where it asserted `rows = [ ]`.

## 5. The reading crosses the statement against the entry

- [x] 5.1 `flakelet/read.nix`: nothing changes in the rules, and `acceptsName`, `acceptsUnit` and
  `confinement` are already exported (`:103-111`). `operator/read.nix` imports them the way it
  already imports `../image/read.nix`, and asks rather than restating. Verify no rule text appears
  twice in the tree and `tests/unit/layers.nix` still passes.
- [x] 5.2 `operator/read.nix`: four rows from the statement crossed with the entry - a host path the
  stated realiser cannot assemble, a service manager the stated realiser does not emit for, a name
  the stated realiser's endpoint refuses, and a unit needing an access the stated profile denies.
  Each names the entry, the fact and the statement that produced it. Verify the worked fixture's
  `vault-repo:server@vault`, which carries a configuration file, is refused under the flakelet
  statement and built under an image statement.
- [x] 5.3 `tests/unit/operator.nix`: add `testAConfigurationFileMeetsARealiserWithNoAssembleStep`,
  `testAnEntryWithConfigurationDataIsRealisedAsAnImage`,
  `testAnEntryIsStatedForARealiserItsMachineCannotRun`,
  `testANameTheEndpointRefusesIsARowBeforeItIsARaise`,
  `testAUnitNeedingAHostUserMeetsAConfiningProfile` and
  `testAnEntryOwningARootOnlyFileMeetsAConfiningProfile` (the scenarios of `A statement is checked
  against the entry it is about` and `A confinement profile is checked against the entry it
  confines`). All unit layer. Verify each row's identifier and subject, and that the sentence the
  name row states is the same string the realiser's raise prints.

## 6. What a build produces and publishes

- [x] 6.1 `operator/default.nix`: stop discarding the derivation (`:88-92`). The tree always holds
  `plan.json`, `diagnostics.json` and `diagnostics.txt`; it holds `entries/<projected>` for the
  entries the reading realises and nothing for an entry of an inapplicable deployment; it carries no
  marker of its own; and `passthru.entries.<key>` of an inapplicable deployment is refused with
  `planner.render` of the table. Verify `nix build` of a deployment with an error row produces the
  three files, that `jq` reads the rows out of `diagnostics.json`, and that asking for one entry's
  artifact prints the table.
- [x] 6.2 `operator/read.nix`: `operator-entry-machine-no-address` becomes a warning
  (`:143-149`) and the deployment record carries the address as an absence rather than omitting the
  field (`:236-245`). Verify a deployment whose registry declares no address for one machine builds
  every artifact and reports one warning naming the entry and the machine.
- [x] 6.3 `operator/read.nix`: the per-entry identity the record publishes becomes the artifact
  version digest the endpoint records as `settings_hash`, and the plan entry digest is read from
  `plan.json` (D9). Verify changing one machine's address moves every plan entry key on it and moves
  no published identity, and that the value the record publishes is the value
  `flakelet/read.nix:153-159` writes into the endpoint's metadata.
- [x] 6.4 `tests/unit/operator.nix`: add `testAMachineOfAPlacedEntryDeclaresNoAddress` and
  `testAMachineAddressChangesAndNoArtifactByteDoes`, and rewrite
  `testTheManifestNamesEveryEntryThePlanPlaced` and `testADeploymentWhoseDiagnosticsCarryAnError`
  against the restated requirements. All unit layer. Verify the rewritten address assertion asserts a
  warning where it asserted an error.
- [x] 6.5 `tests/e2e/newcomer/`: add the test named by the scenario "Both halves of the table are
  reachable for a refused deployment" to the folder `open-the-repository-to-a-consumer` owns,
  building a deployment with one error row through a real `nix build` and reading the rows out of
  the result. End-to-end layer, because the claim is about what a derivation produces. Verify the
  test fails against a tree where `operator/default.nix` raises.
- [x] 6.6 `tests/e2e/wired-pair/test_wired_pair.py`: add
  `test_the_endpoint_reports_the_identity_the_build_published`. End-to-end layer, because the claim
  is about what a machine holds. Verify it fails when the record publishes the plan entry digest
  again.

## 7. The realisers are narrowed and their claims restated

- [x] 7.1 `image/read.nix`: rewrite the header claim of `:5-8` as what will be true - a refusal here
  is a condition an error row of the planner's table or of the deployment build's table already
  reported, and a refusal about a fact the statement carries belongs to the deployment build. No
  refusal is deleted. Verify the file's raises are unchanged in wording and
  `tests/unit/diagnostics.nix`'s source scan still finds no raising call under `lib/`.
- [x] 7.2 `flakelet/read.nix`: the same for the comment at `:1-9`, naming the deployment build as
  the layer that reports the host-path and naming conditions first. Verify no rule is restated and
  the three raises are unchanged.
- [ ] 7.3 `tests/unit/diagnostics.nix`: add `testARealiserRefusesAConditionNoRowReports`, which
  crosses every `fail` in `image/read.nix` and `flakelet/read.nix` against the row producers of
  `lib/` and `operator/read.nix` and names any refusal with no row above it, and
  `testAnApplicableDeploymentIsRealisedWithoutARaise`, which reads every placed entry of the worked
  fixture under a statement naming the image realiser where a configuration file exists. Both unit
  layer. Verify the first goes red when a `fail` is added to either realiser with no row beside it.
- [ ] 7.4 `tests/unit/flakelet.nix` and `tests/unit/image.nix`: update the scenarios the two realiser
  deltas restate - `testAnUnusableInstanceName`, `testAUnitNameOutsideTheServicesNamespace`,
  `testAWellFormedEntryIsNotRefused`, `testAnEntryShownAConfigurationFile`,
  `testAFactThePlanDoesNotCarry`, `testAnEnvironmentValueCarriesANewline` - each asserting the row
  above the raise as well as the raise. Verify each still fails when its subject is mutated.

## 8. Documentation and invariants

- [ ] 8.1 `docs/diagnostics.md`: the layering rule, the three kinds of fact and the layer that
  reports each, and the sentence that a realiser's raise is what a direct caller receives. Verify
  every identifier it names exists in the tree.
- [ ] 8.2 `docs/operator.md`: what a build of an inapplicable deployment produces and where its rows
  are read from, the statement's field-by-field resolution, the statement-level refusals, the address
  warning, and the identity the record publishes. Verify every command in it runs as written.
- [ ] 8.3 `CLAUDE.md`: replace the claim under Realisers that every refusal there is a condition
  `mkPlan` reports, with the three-layer rule; record the `closure` and `units` exemption beside the
  `delivery` one; record that a plan record is classified by shape and never by key text; record the
  address warning and where the apply refusal lives; record that the record publishes the artifact
  identity; and record that `row`, `error` and `warning` are exported and that a row producer outside
  the library uses them. Verify the file passes vale under
  `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 8.4 Registration: the five spec paths of this change in `accountable` in
  `tests/unit/coverage.nix`. Verify the coverage cross-walk reports an empty difference over them.

## 9. Verification

- [ ] 9.1 `nix build .#checks.x86_64-linux.planner-tests -L`: green, with one test per scenario of
  the five spec files of this change and no name shared with a pytest test.
- [ ] 9.2 The documented example, end to end: evaluate `docs/README.md:52-125` as written, confirm
  `diagnostics = [ ]` and `applicable = true`, build it, and confirm the artifact of
  `hearer:main@host` exists and no artifact of `talker:main@host` does. Record the store path here.
- [ ] 9.3 Prove each new refusal can fire and only fires when it should: for each of the eleven rows
  the reading gains and the three the planner gains, mutate one deployment to trigger it, confirm
  exactly the tests of that scenario fail, and revert. Record the mutation and the failing test name
  per row.
- [ ] 9.4 Prove the rule holds mechanically: add a `fail` to `image/read.nix` with no row above it
  and confirm `testARealiserRefusesAConditionNoRowReports` names it; remove it and confirm the suite
  is green.
- [ ] 9.5 `nix build .#checks.x86_64-linux.treefmt -L` and `nix fmt`: no change to any file this
  change touched, and no blank line left where a comment moved.
- [ ] 9.6 `nix run .#planner-e2e`: green, with the count recorded here against the count before the
  change, and the two new end-to-end tests present in it.
