## 1. Totality of the readings

- [x] 1.1 Record `impl` only where the declaration carried a function, so the value the reading keeps
  and the `impl-missing` row it built cannot disagree. Verify: the probe
  `anImplementationThatIsNotAFunctionIsARow` answers `ok` under
  `nix build .#checks.x86_64-linux.planner-counterexamples-eval`.
- [x] 1.2 Force a guarded implementation once: read the recovery's own answer before any operand
  re-forces the application, at the shape test and at the provider's exports. Verify: the probe
  `anImplementationThatRaisesIsAGuardedRow` answers `ok`, and the table carries `module-raised`
  beside `impl-missing`.
- [x] 1.3 Read a root's member container for its kind before it is indexed. Verify: the probe
  `aRootReturningServicesOfAnotherKindIsARow` answers `ok`.
- [x] 1.4 Read each fragment of a rendered configuration file for its kind before it is coerced.
  Verify: the probe `aRecipeFragmentHoldingANonStringIsARow` answers `ok`.
- [x] 1.5 Verify every settings value against its declared type before it enters a key input, and
  record nothing the type refused. Verify: the probe `aSettingsKnobHoldingAFunctionIsARow` answers
  `ok`, and the entry's key forces.
- [x] 1.6 Recognise a generated file reference by its record rather than by an attribute name, so a
  hand-written export shaped like one is a row. Verify: the probe
  `anExportCarryingTheVarsFileMarkerIsARow` answers `ok`.
- [x] 1.7 Read the four arguments the entry point is handed - the machine registry, the instance
  table, the interface attribution and the store directory - and the generated-value state answer,
  each for its kind, subjecting their rows to an issue identifier. Verify: the probes
  `aMachineRegistryOfAnotherKindIsARow`, `anInstanceTableOfAnotherKindIsARow`,
  `anInterfaceAttributionOfAnotherKindIsARow`, `aStoreDirectoryOfAnotherKindIsARow` and
  `aVarsStateAnswerOfAnotherKindIsARow` all answer `ok`.
- [x] 1.8 Add the suite assertions for 1.1 to 1.7 in `tests/unit/diagnostics.nix`, one per condition,
  each asserting the row's identifier and subject: a probe proves the evaluation completed and only a
  suite test says which row it produced. Names are the derived names of the scenarios in
  `specs/planner/diagnostics/spec.md`. Verify: `nix eval --json .#debug.failuresBySuite.diagnostics`
  is `[]`.

## 2. The table and the verdict survive one entry

- [x] 2.1 Produce each entry's row list under the recovery, so the table and the applicability
  verdict are answerable without forcing any plan record. Verify: a deployment whose module reads an
  unwired slot renders its table and answers `applicable`, while reading that one entry's record
  raises.
- [x] 2.2 Rewrite the two counterexamples that assert the withdrawn claim -
  `anImplementationWithStrictFormalsIsARow` and `anUnwiredSlotStillLeavesATableToPrint` - to assert
  the narrowed one: the table prints, the verdict answers, the one record raises. Verify: both are in
  `tests/counterexamples/probes.nix`, both answer `ok`, and
  `nix build .#checks.x86_64-linux.planner-counterexamples-eval` succeeds.
- [x] 2.3 State the contract that a module's implementation accepts the arguments it does not name,
  and enumerate the two conditions the interpreter does not let a caller catch. Verify: the sentences
  are in `lib/default.nix`'s header and in `CLAUDE.md` under Purity and totality, and
  `tests/unit/layers.nix` still passes.

## 3. Names, keys and the keyspace

- [x] 3.1 Refuse an empty name and a name carrying a line break or a control character where the name
  grammar already refuses the three key separators, keeping it a denylist. Verify:
  `counterexamples.testEveryPlacedEntryIsReadOrNamed` passes.
- [x] 3.2 Refuse a plan key claimed twice with an error row naming both claimants, and make the
  deployment inapplicable rather than letting one record replace the other. Verify:
  `counterexamples.testAPlanKeyNamesOneRecord` passes, and the new scenario's test in
  `tests/unit/plan.nix` asserts both claimants are named.
- [x] 3.3 Replace keying by what a declaration stated with a comparison against the value's own
  defaults, for a generated file's owner, group and mode and for a configuration file's owner and
  group. Verify: `counterexamples.testStatingAGeneratedFileDefaultDoesNotRekeyTheValue` and
  `counterexamples.testStatingAConfigurationFileOwnershipDefaultDoesNotRekeyTheEntry` pass.
- [x] 3.4 Delete the record's statement of which ownership keys were written once nothing reads it,
  and remove the note in `CLAUDE.md` that keeps it alive. Verify: `nix build
  .#checks.x86_64-linux.planner-tests` is green and no file names the field.
- [x] 3.5 Compare shown host paths of one machine for nesting as well as for equality, as an error
  row naming both declarations. Verify: `counterexamples.testTwoShownHostPathsOfOneEntryMayNotNest`
  passes and neither realiser is reached.
- [x] 3.6 Add the remaining suite assertions for the scenarios of
  `specs/planner/plan-artifact/spec.md`. Verify: `nix eval --json .#debug.failuresBySuite.plan` is
  `[]`.

## 4. Diagnostics discipline

- [x] 4.1 Apply the one-line rule to a row's subject, and make one definition of a line break -
  carriage return as well as newline - serve both the scan and the repair. Verify:
  `counterexamples.testASubjectCarryingALineBreakRendersOneLinePerRow` and
  `counterexamples.testAFoldRefusalCannotCarryACarriageReturn` pass.
- [x] 4.2 Accept a subject that is a plan key the planner built, a path relative to the deployment
  root or an issue identifier, and stop refusing a name the key grammar admits. Verify:
  `counterexamples.testANameTheKeyGrammarAdmitsIsNotRefusedByTheSubjectRule` passes and the fixture's
  `diagnostics.txt` comparison still holds.
- [x] 4.3 Deduplicate on what a producer built rather than on what a subject repair left, so two facts
  about two files sharing a basename stay two rows. Verify:
  `counterexamples.testTwoModuleFilesSharingABasenameKeepTwoRows` passes.
- [x] 4.4 Close the severity domain where a row is built: a value outside it is reported naming its
  producer and is never counted as a warning for not being the error spelling. Verify:
  `counterexamples.testARowSeverityIsHeldToTheStatedDomain` passes.
- [x] 4.5 Give a fold's refusal a marker a successful fold cannot imitate, keeping the message, the
  identifier, the subject and the severity where they are. Verify:
  `counterexamples.testAFoldMayReturnAnAttributeCalledRefused` passes and every fold in
  `tests/e2e/*/deployment` and `fixtures/` still refuses and still delivers.
- [x] 4.6 Add the suite assertions for the remaining scenarios of
  `specs/planner/diagnostics/spec.md` and `specs/planner/interface-fold/spec.md`. Verify: those two
  suites report no failures.

## 5. Secrecy, readability and the typed edge

- [x] 5.1 Compare a secret export's secrecy against the secrecy of the file backing it, as an error
  row naming both, and publish nothing for the refused export. Verify:
  `counterexamples.testASecretExportMayNotBeBackedByAPublicFile` passes and no bytes of the file are
  in the plan.
- [x] 5.2 Ask the readability comparison about an entry's own generated value, beside the two sites
  that ask it about a declared read and a configuration file. Verify:
  `counterexamples.testAUnitThatCannotOpenItsOwnValueIsARow` passes and the answer does not depend on
  which realiser reads the plan.
- [x] 5.3 Widen the mention scan from the entry's own undeployed values to every value the mentioning
  machine does not receive, keeping the undeployed case as the instance where the delivery set is
  empty. Verify: `counterexamples.testNamingAValuePathOnAMachineOutsideTheDeliverySetIsARow` passes
  and `vars.testAUnitOpensAValueNobodyReceives` still passes with its own row.
- [x] 5.4 Verify each delivered read against the consuming interface's own export type, leaving a
  refused slot unfilled with an error row naming the consumer, the slot and what the type reported.
  Verify: `counterexamples.testAClaimedIdentityDoesNotCollapseTwoStructSchemas` passes, and every
  wire in `tests/e2e/*/deployment` and `fixtures/` still delivers.
- [x] 5.5 Reach every row an interface can earn from the modules that imported it rather than from
  the attribution argument. Verify: `counterexamples.testAttributionDoesNotDecideApplicability`
  passes, and adding attribution changes only which file a row names.
- [x] 5.6 Add the suite assertions for the scenarios of `specs/planner/secret-delivery/spec.md`,
  `specs/planner/typed-edge/spec.md` and `specs/planner/interface-identity/spec.md`. Verify: the
  `vars`, `resolution` and `interfaces` suites report no failures.

## 6. The unit vocabulary and the realisers

- [x] 6.1 Read a configuration file's stated source for its kind and hold it to the store; record no
  disposition for a refused one. Verify:
  `counterexamples.testAConfigurationFileSourceIsReadForItsKindAndHeldToTheStore` passes and neither
  realiser is handed a host path outside the store.
- [x] 6.2 Refuse the bind-list separator and the specifier character in a shown host path, in the one
  home that grammar already has. Verify:
  `counterexamples.testAConfigurationFilePathIsAWordAUnitFileCanBind` passes.
- [x] 6.3 Hold a unit's own name and an environment name to the rule their values are, and hold an
  environment name additionally to the environment name grammar. Verify:
  `counterexamples.testAUnitNameCarryingALineBreakIsARow` passes and the 14 existing `env` records
  under `tests/e2e/`, `fixtures/` and `perf/` are unaffected.
- [x] 6.4 Carry the confinement profile in the image's version digest. Verify:
  `counterexamples.testTheVersionDigestCarriesTheConfinementProfile` passes and
  `tests/unit/image.nix` is green with its keyed paths updated.
- [x] 6.5 Escape an environment name the way its value is escaped, and refuse a part the renderer
  cannot carry. Verify: `counterexamples.testAnEnvironmentNameIsEscapedTheWayItsValueIs` passes.
- [x] 6.6 Anchor the flakelet realiser's restated unit rule so no character the endpoint treats as a
  terminator passes as an ordinary one. Verify: the new scenario's test in `tests/unit/flakelet.nix`
  passes and `LOCKED_URL_PREFIX` is untouched.
- [x] 6.7 Check every value the rendered secrets step carries as a word in the half that answers the
  table, ownership included, and cross the two word sets rather than listing them twice. Verify:
  `counterexamples.testAnOwnershipTheRenderRefusesIsARowFirst` passes and
  `tests/unit/diagnostics.nix`'s realiser-refusal cross-walk still accounts for every refusal.
- [x] 6.8 Classify a plan record in the secrets reading by what it records rather than by the text of
  its key, so every generated value is projected or refused by name. Verify:
  `counterexamples.testTheSecretsReadingSeesEveryGeneratedValueThePlanCarries` passes.
- [x] 6.9 Index the derived unit file names per machine in the reading that derives them, as an error
  row naming both entries and the name. Verify:
  `counterexamples.testTwoEntriesOfOneMachineDoNotShareAUnitFileName` passes under either stated
  realiser.
- [x] 6.10 Read the realisation statement's realiser and profile, and a plan's configuration file
  mode, for their kinds. Verify: the probes `aRealiserStatementOfAnotherKindIsARow`,
  `aProfileStatementOfAnotherKindIsARow` and
  `aConfigurationFileWithNoModeIsARowInTheOperatorReading` answer `ok`.
- [x] 6.11 Add the suite assertions for the scenarios of `specs/planner/unit-vocabulary/spec.md`,
  `specs/realiser/*/spec.md` and `specs/operator/deployment-build/spec.md`. Verify: the `units`,
  `image`, `flakelet`, `secrets` and `operator` suites report no failures.

## 7. The operator's command

- [x] 7.1 Derive the readers a moved value restarts from the same relation the activation order is
  derived from, so every recorded read shape rotates its consumer. Verify:
  `pytest cli/counterexample_test.py -k rotates` passes.
- [x] 7.2 Refuse a resolved read recorded in a shape the walk does not recognise whatever kind of
  value it is, naming the consumer and the slot. Verify: `pytest cli/counterexample_test.py -k
  neither_shape` passes.
- [x] 7.3 Require a stated artifact path to resolve inside the build, naming the entry and the path
  otherwise, before the first dial. Verify: `pytest cli/counterexample_test.py -k leaves_the_build`
  passes.
- [x] 7.4 Measure a value source to the leaves of each delivered value's own directory, naming every
  undeclared file by its path below it. Verify: `pytest cli/counterexample_test.py -k undeclared`
  passes.
- [x] 7.5 Name a refusal from the record the command read rather than from the vector it built.
  Verify: `pytest cli/counterexample_test.py -k ssh_option` passes.
- [x] 7.6 Produce the absence line only from an endpoint that answered and registered no entry, and
  make an answer the command cannot read its own refusal with a non-zero exit. Verify: `pytest
  cli/counterexample_test.py -k "absence or not_a_status"` passes.
- [x] 7.7 Compare an image by the identity the build published, selected out of the machine's answer
  by the entry it belongs to, naming both identities when they differ. Verify: `pytest
  cli/counterexample_test.py -k image_report` passes.
- [x] 7.8 Add the tests for the new scenarios of `specs/operator/apply-command/spec.md` and
  `specs/operator/machine-report/spec.md` in `cli/counterexample_test.py`. Verify:
  `nix build .#checks.x86_64-linux.planner-counterexamples-cli` succeeds.

## 8. Registration, documents and budgets

- [x] 8.1 Count `cli/counterexample_test.py` as a layer of tests in the specification cross-walk, the
  way the budget checker's own tests are counted. Verify:
  `nix eval --json .#debug.failuresBySuite.coverage` is `[]` with this change's specs accountable.
- [x] 8.2 Move this change's 14 spec files from `excused` to `accountable` in
  `tests/unit/coverage.nix`. Verify: the `coverage` suite reports no unclassified, no vanished, no
  doubled and no untested scenario.
- [x] 8.3 Record the new identifiers in `docs/diagnostics.md`, each under the family it belongs to.
  Verify: the row table cross-walk in `tests/unit/diagnostics.nix` accounts for every identifier the
  library produces.
- [x] 8.4 Update the suite figures and the counterexample rows in `docs/tooling.md`, and the totals
  in `tests/unit/layers.nix`. Verify: `nix eval --json .#debug.failuresBySuite.layers` is `[]`.
- [x] 8.5 Record in `CLAUDE.md`: the narrowed totality sentence and the two named conditions, the key
  input rule, the digest gaining the profile, the unit file namespace owner, the machine question the
  mention scan asks, the nominal depth of a claimed identity with the wire verify beside it, and the
  fold's refusal marker. Delete the three claims this work proves stale. Verify: `nix build
  .#checks.x86_64-linux.treefmt` is green, prose included.
- [x] 8.6 Re-measure the evaluation budgets for the widened mention scan and the added verify pass,
  and commit the new figures rather than relaxing the margins. Verify:
  `nix build .#checks.x86_64-linux.planner-perf` is green at margin 0.15 and growth bound 1.25 across
  sizes 4, 16, 64 and 256.
- [x] 8.7 Regenerate the golden plan if and only if it moved, and state which rule moved it. Verify:
  `nix eval --json .#debug.worked.plan | jq -S .` equals `fixtures/minimal-typed-edge/plan/`'s
  committed files.

## 9. The whole tree

- [x] 9.1 Run the full unit layer and account for every failure. Verify:
  `nix build .#checks.x86_64-linux.planner-tests` reports every test successful.
- [x] 9.2 Run both counterexample checks and the command's tests. Verify:
  `nix build .#checks.x86_64-linux.planner-counterexamples-eval` and
  `nix build .#checks.x86_64-linux.planner-counterexamples-cli` both succeed, and every probe answers
  `ok`.
- [x] 9.3 Run the machine layer on real guests, since the digest, the key input and the wire verify
  all change what a machine is handed. Verify: `nix run .#planner-e2e` passes every folder, with
  `secret-delivery`'s rotation phases and `portable-image`'s attachment phases green.
