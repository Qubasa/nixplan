## 1. Registration, before anything is edited

- [ ] 1.1 Register this change's one delta spec in `excused` in `tests/unit/coverage.nix:104-121`,
  by its path under `openspec/` -
  `changes/account-for-every-counterexample/specs/tooling/test-layers/spec.md` - with a reason in
  the shape `excuseNamesChange` matches (`tests/unit/coverage.nix:389-394`): "an unimplemented
  change: no task of account-for-every-counterexample has been done, so nothing in this package
  claims to satisfy it yet". Verify after 1.3 with `nix build
  .#checks.x86_64-linux.planner-tests`: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`, and a reason naming no change fails the excuse reading.
- [ ] 1.2 **Leave every checkbox of this file unchecked until task 8.1.** `changeHasLanded`
  (`tests/unit/coverage.nix:398-404`) reads this file for a `- [x]` at the start of a line and
  `staleExcuses` (`:406-416`) fails the suite for an excuse whose change has started landing, so a
  box ticked while the path is excused turns the suite red for a reason that reads like a missing
  test. Verify by ticking nothing until 8.1 and by the suite staying green through every task below.
- [ ] 1.3 `git add openspec/changes/account-for-every-counterexample/` before evaluating anything:
  the flake does not see an untracked path and the coverage cross-walk then reports the spec it
  cannot read rather than the file that was not staged. Verify with `nix eval --json
  '.#debug.failures'` answering something other than a file-not-found error.
- [ ] 1.4 Record the registration points this change does and does not touch, so a later reader does
  not look for a missing one: `excused` then `accountable` in `tests/unit/coverage.nix` (1.1, 8.1);
  the `layers` import in `tests/default.nix:121` gains one argument in 2.5, which is **not** a new
  entry in `suites` (`tests/default.nix:34-133`) because no suite file is added; `classOf`
  (`tests/unit/layers.nix:56`) and `scannedDirectories` (`:295`) are untouched because no top-level
  file or directory is added; `programs.mypy.directories` in `treefmt.nix` and `src` in `ruff.toml`
  are untouched because no python directory is added; `lib/excluded.nix`, `directoryKinds` in
  `lib/module.nix` and the `README.md` command literals are untouched. Verify by reading the diff of
  this change against that list before 8.1.

## 2. The per-counterexample reading in `tests/unit/layers.nix`

- [ ] 2.1 Add the member set of each home beside `counterexampleHomes` (`:770-774`), one binding per
  home, each using the construction that home already admits: `probeNames` (`:896-905`) for
  `tests/counterexamples/probes.nix`, an attribute-line scan of the shape `  test<Camel> =` for
  `tests/unit/counterexamples.nix`, and `definedIn` (`:946-947`) for `cli/counterexample_test.py`.
  Reuse the two that exist rather than writing a third parser: `probeNames` is already read by
  `testAProbeIsDiscoveredRatherThanListedByHand` and `definedIn` by
  `testTheCommandsOwnTestsAreCounted`. Verify with a `nix eval` of the suite's own expression
  answering 17, 24 and 14 members.
- [ ] 2.2 Add the block-to-member pairing described in `design.md` D2: for each member, the comment
  block whose last line is the last non-blank line above that member's definition, plus - for
  `cli/counterexample_test.py`, where the argument is inside the body - a block opening after that
  definition and before the next. A block owned by no member is not a pin. Do not credit a block to
  more than one member: that reading answers 55 of 55 and is the per-file defect at member
  granularity (`design.md` D2). Verify with a `nix eval` answering 7 members with no pin, and
  exactly the seven 2.4 and 2.5 name.
- [ ] 2.3 Read each member's pin through the existing rule unchanged - `pinnedIn` (`:865-870`) over
  the paired blocks, `sentenceLength` (`:874`) as the floor - so the length and the
  first-quote rule keep their one home, and keep `withdrawnClaims` (`:882-888`) folding over every
  collected fragment as it does today. A member with no fragment of at least `sentenceLength`
  characters is a line naming the home and the member. Verify with the four tests of group 3.
- [ ] 2.4 Delete `quotingHomes` (`:890`) and the `quoting` field of
  `testACounterexampleQuotesTheClaimItPins` (`:1306-1319`), leaving that test's `withdrawn` half
  alone: the per-file assertion is implied by 2.3 and two readings of one rule can disagree
  (`design.md` D5). Verify that `testACounterexampleQuotesTheClaimItPins` still fails when a pin is
  edited to a sentence the records do not state, by making that edit locally and reverting it.
- [ ] 2.5 Hand `layers` the counterexample suite's exported names: one argument on the import at
  `tests/default.nix:121`, whose value is `builtins.attrNames` of `suites.counterexamples`, and
  cross it against the names 2.1 located in the text - a name on one side only is a line naming
  both sides. Do not hand it `unitTestNames` (`tests/default.nix:135`), which names `layers`
  itself (`design.md` D3). Verify with 3.2.
- [ ] 2.6 Make an empty member set a failure naming the home, so a home whose enumeration found
  nothing is not reported as a home with nothing unaccounted for. Verify with 3.3.

## 3. The four tests

- [ ] 3.1 `testACounterexampleCarriesNoPinnedSentence` in `tests/unit/layers.nix`, answering the
  scenario `A counterexample carries no pinned sentence`: the sorted list of `<home>: <member>` lines
  for every member with no pin, expected empty. **Demonstrated to fail today by the seven live
  violations**: run it before task 4 and it names
  `anImplementationThatRaisesIsAGuardedRow`, `aRecipeFragmentHoldingANonStringIsARow`,
  `aSettingsKnobHoldingAFunctionIsARow` and `anInstanceTableOfAnotherKindIsARow` in
  `tests/counterexamples/probes.nix` and `testAPlanKeyNamesOneRecord`,
  `testARowSeverityIsHeldToTheStatedDomain` and
  `testAClaimedIdentityDoesNotCollapseTwoStructSchemas` in `tests/unit/counterexamples.nix`, and
  nothing else. Verify with `nix build .#checks.x86_64-linux.planner-tests` before 4.1 - it is red
  with those seven lines - and after 4.2 - it is green.
- [ ] 3.2 `testACounterexampleTheEnumerationCannotLocate`, answering the scenario of the same name:
  the names the evaluating suite exports crossed against the names located in its text, expected
  empty both ways. Demonstrated by indenting one binding of `tests/unit/counterexamples.nix` by four
  spaces instead of two and observing the test name that binding in the side the scan could not
  locate, then reverting. Verify with `nix build .#checks.x86_64-linux.planner-tests` on both sides
  of that edit.
- [ ] 3.3 `testAnEnumerationThatFoundNothingFails`, answering the scenario of the same name: per
  home, that the member set is not empty, expected true for all three. Demonstrated by pointing one
  home's binding at a file holding no counterexample - `tests/unit/support.nix` - and observing the
  test name that home, then reverting. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` on both sides of that edit.
- [ ] 3.4 `testAPinShorterThanASentenceIsNotAPin`, answering the scenario of the same name: that a
  member whose only quoted fragment is shorter than `sentenceLength` counts as carrying no pin, and
  that a fragment quoted after the one the rule reads as the pin does not satisfy it. Demonstrated
  today by two of the seven: `anImplementationThatRaisesIsAGuardedRow` quotes
  `A guard is not a check`, 22 characters, and `aSettingsKnobHoldingAFunctionIsARow` carries a
  101-character sentence as its block's second quote while its first is
  19 characters. Assert both conditions over the pin reading and not over a fabricated string, so
  the test is about the rule this suite applies. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` before 4.1 - it names both - and after 4.2.
- [ ] 3.5 Check the four names against every test name this repository defines before committing
  them - the unit suites' attributes, and the `def test_` lines of `cli/`, `perf/` and `tests/e2e/` -
  because one name in two layers is a failure and not a bonus
  (`tests/unit/coverage.nix:1-3`, `:370-376`). All four were free at 1098 defined names when this
  change was written. Verify with `nix build .#checks.x86_64-linux.planner-tests`:
  `testOneBehaviourIsAssertedInBothLayers` fails a name two kinds carry.

## 4. The seven comment blocks

- [ ] 4.1 In `tests/counterexamples/probes.nix`, make the first quoted fragment of each of the four
  failing blocks a sentence of at least 24 characters that the corpus `recordFiles`
  (`tests/unit/layers.nix:790-802`) names already states. Each was checked against that corpus before
  this change was written: `:106-110` for `anImplementationThatRaisesIsAGuardedRow` can quote "The
  module's own expression runs under the same `diag.guard`" (60); `:136-140` for
  `aRecipeFragmentHoldingANonStringIsARow`, "every value a declaration wrote is read for its kind
  before the reading indexes into it" (87); `:168-174` for `aSettingsKnobHoldingAFunctionIsARow`, the
  101-character sentence that is already its second quote, moved ahead of `` `lib/` never raises ``;
  `:234-236` for `anInstanceTableOfAnotherKindIsARow`, "the half of a declaration a deployment writes
  is read with the tolerance the half a module writes is" (100), which is the sentence its own prose
  already rests on. Keep every argument the block makes; only the quotation moves. Verify with 3.1
  and with `testACounterexampleQuotesTheClaimItPins`, which fails a quote the records do not state.
- [ ] 4.2 In `tests/unit/counterexamples.nix`, the same for the three failing blocks: `:327-330` for
  `testAPlanKeyNamesOneRecord` can quote "A plan key is `<instance>:<service>@<machine>` and a keyed
  form appends `@<hash>`" (81); `:473-476` for `testARowSeverityIsHeldToTheStatedDomain`, "a module
  may not tag a row's severity" (37); `:552-556` for
  `testAClaimedIdentityDoesNotCollapseTwoStructSchemas`, "The fingerprint compares korora type
  names, so two libraries declaring `url` over different predicates claim one identity" (121).
  Change no attribute, no expression and no assertion in either file. Verify with 3.1 green and with
  `nix build .#checks.x86_64-linux.planner-counterexamples-eval` and
  `.#checks.planner-counterexamples-cli` answering exactly what they answered before, the probes
  being unchanged as expressions.
- [ ] 4.3 Run `nix fmt` after 4.1 and 4.2 and only over those two files: a shortened comment leaves
  the blank line that framed it, and `checks.treefmt` then fails on formatting rather than on prose
  (`CLAUDE.md`, Known bugs). Verify with `nix build .#checks.x86_64-linux.treefmt`.

## 5. The index

- [ ] 5.1 In `CLAUDE.md`, delete the families enumeration (`:1082-1094`) and keep `:1065-1080` - the
  three homes and what decides which home a counterexample is in - adding one sentence that the
  account of which counterexamples exist is the check, that it enumerates each home by the
  construction that home admits, and that a counterexample with no pinned sentence is a line naming
  the home and the counterexample. The argument for the deletion is `design.md` D6; do not restate it
  in the index. Attribute no identifier to a file it is not in: `hold-the-index-to-the-tree` makes a
  backticked identifier the index joins to a file crossable against that file, and
  `layers.testTheTestTreeIsRead` is the only such name the section keeps
  (`tests/unit/layers.nix:977`). Verify with `nix build .#checks.x86_64-linux.treefmt`, which lints
  `CLAUDE.md`, and by `grep -n "testAnOwnershipTheRenderRefusesIsARowFirst" CLAUDE.md` still finding
  the sentence at `:513` that rests on it - that statement is under Realisers and is not part of the
  deleted list.
- [ ] 5.2 Leave `docs/tooling.md:88` alone. The `counterexamples` row describes what the suite is and
  records no figure, and a count a document records is no longer crossed against the tree
  (`CLAUDE.md`, Registration points). Verify by reading the row: it names no number.

## 6. Gates

- [ ] 6.1 `nix eval --json '.#debug.failures'` answers `[]`.
- [ ] 6.2 `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 6.3 `nix build .#checks.x86_64-linux.planner-counterexamples-eval` and
  `nix build .#checks.x86_64-linux.planner-counterexamples-cli`, both answering what they answered
  before this change: no probe attribute and no command test is added, removed or rewritten.
- [ ] 6.4 `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 6.5 `nix build .#checks.x86_64-linux.planner-perf`, expected unmoved and **not** re-recorded:
  no counter of `perf/budgets.json` is a function of a test suite's text, and nothing this change
  edits is read by `perf/eval.nix`.
- [ ] 6.6 `fixtures/minimal-typed-edge/plan/` is not regenerated: no declaration of that fixture
  changes and nothing of this change is inside `mkPlan`. Verify by `nix eval --json
  .#debug.worked.plan | jq -S .` comparing equal to the committed file.

## 7. Close

- [ ] 7.1 Record this change's invariant in `CLAUDE.md` beside the section 5.1 rewrites: that the pin
  check is per counterexample, that each home's members come off the home by its own construction,
  that a member with no pinned sentence is a failure naming the home and the member, and that the pin
  itself is the first quoted fragment of the adjacent comment block at 24 characters or more - one
  home for the rule, in `tests/unit/layers.nix`. Verify with `nix build
  .#checks.x86_64-linux.treefmt`.
- [ ] 7.2 In **one** edit, now that every scenario of this delta has its test: delete this change's
  `excused` entry from `tests/unit/coverage.nix`, add
  `changes/account-for-every-counterexample/specs/tooling/test-layers/spec.md` to `accountable`, and
  tick every checkbox of this file. One edit because the excuse is stale the moment a box is ticked
  (`changeHasLanded`, `tests/unit/coverage.nix:398-404`) and `accountable` is unsatisfiable until the
  four tests exist, so any other order puts the suite red in between. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`: no unclassified spec
  (`testEverySpecificationIsClassified`), no stale excuse
  (`testAnExcuseOutlivesTheStateItDescribes`), every heading of the delta answered
  (`testAScenarioGainsNoTest`) and none of them named in both layers
  (`testOneBehaviourIsAssertedInBothLayers`) - six scenarios, six nix-unit tests, two of them the
  ones that already answer today.
