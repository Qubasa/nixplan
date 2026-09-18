## 1. Baseline and registration, before anything is edited

- [ ] 1.1 Record the perf baseline before touching anything: run `bash perf/measure.sh` and paste
  the nine counters into this change's working notes. This change does edit `lib/**` - a new
  `lib/vocabulary.nix`, one published attribute in `lib/default.nix:57-64`, `moduleKeys` added to
  the exports at `lib/module.nix:212-220` and four key lists added to the attrset at
  `lib/resolve.nix:206-207` - and every one of those is outside `mkPlan` and outside the right-hand
  side of `korora // { … }` at `lib/atoms.nix:77-78`, so the counters are expected
  **byte-identical** rather than merely within the 0.15 margin. Verify by re-running `bash
  perf/measure.sh` at task 8.1 and comparing; a moved counter is a defect of the projection's
  placement, never a re-recorded budget, and `nrOpUpdateValuesCopied` moving at all means a key
  landed inside a per-plan or per-machine update.
- [ ] 1.2 Register this change's two delta specs in `excused` in `tests/unit/coverage.nix`, one line
  per file, each reason in the exact shape `excuseNamesChange` matches
  (`tests/unit/coverage.nix:389-394`, the wording at `:105-106`), for
  `changes/author-a-deployment-from-outside/specs/tooling/consumer-surface/spec.md` and
  `changes/author-a-deployment-from-outside/specs/operator/deployment-build/spec.md`. Verify with
  `nix build .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [ ] 1.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` in `tests/unit/coverage.nix:396-404` reads this `tasks.md` for a single line
  beginning with a ticked checkbox, and `staleExcuses` (`:406-416`) fails the suite for an excuse
  whose change has landed, so ticking one box while the two paths are excused turns the suite red
  for a reason that reads like a missing test. The paths move to `accountable` and every box is
  ticked in the one edit task 8.2 makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [ ] 1.4 `git add` every new file of this change before evaluating anything - the flake does not
  see an untracked path and the coverage cross-walk then reports the spec it cannot read rather than
  the file you forgot to stage. That is the two spec files, `proposal.md`, `design.md`, `tasks.md`,
  and every new file a later task creates: `lib/vocabulary.nix` and the scaffold's `args.nix`.
  Verify with `nix eval --json '.#debug.failures'` returning something other than a file-not-found
  error.

## 2. The rendered table beside the rows

- [ ] 2.1 In `operator/default.nix`, bind the rendered table once and spend it twice: the
  `planner.render reading.diagnostics` expression currently inlined at `:328` becomes a `let`
  binding, the farm's `diagnostics.txt` keeps taking it, and `passthru` (`:341-347`) publishes it
  beside the rows it already publishes. Do not change the shape or the name of
  `passthru.diagnostics`: the rows stay the rows. Verify with a `tests/unit/operator.nix` case
  asserting the published text equals `planner.render` of the published rows and equals the text the
  farm holds, for the worked deployment.
- [ ] 2.2 In `tests/unit/operator.nix`, add the case for an inapplicable deployment: both published
  attributes answer, the rows carry the error, and `entries` and `machines` are still the refusal
  (`operator/default.nix:71-75`, `:299-303`), so an answer is the two attributes by name and never
  the record. Verify with `nix build .#checks.x86_64-linux.planner-tests` and by the case naming
  `testTheTableOfAnInapplicableDeploymentIsReadWithoutBuildingIt` and
  `testACallerAskingForTheWholeRecordIsAnsweredWithTheRefusal`.
- [ ] 2.3 In `tests/unit/operator.nix`, add `testTheRowsAndTheRenderedTableAreReadFromAnEvaluation`:
  reading the two attributes of the worked deployment answers the rows the build writes and the text
  the build writes, and the rows are the ones `lib/diagnostics.nix:141-169` ordered. Verify with
  `nix build .#checks.x86_64-linux.planner-tests`.

## 3. The rows-only subcommand

- [ ] 3.1 In `cli/`, add the reading that turns a target into a table: a directory holding
  `manifest.json` is answered from its own `diagnostics.json` and `diagnostics.txt` with no nix
  invocation, which is the `cli/manifest.py:231-233` branch; anything else is answered by one `nix
  eval --json` of the target with `--apply` selecting the two published attributes by name, the way
  `perf/measure.sh` applies arguments to an evaluation. Never evaluate the record as a whole. Verify
  with `tests/e2e/test_harness.py` cases `test_the_command_answers_a_target_it_did_not_build` and
  `test_the_rows_a_program_reads_are_the_rows_the_table_ordered`, both in-process over a built
  directory the harness writes, the way `_built` already writes one.
- [ ] 3.2 In `cli/planner.py`, add the `diagnose` subcommand: it prints the rendered table on
  stdout, returns 1 where a row carries an error and 0 otherwise - the `_build` precedent at
  `cli/planner.py:41-47` - and takes `--json` to print the rows instead. Register it in
  `SUBCOMMANDS` (`:100-106`) and in the parser loop (`:145-151`), with its `target` argument reading
  the same `TARGET` string and the same `EPILOG` every other subcommand reads (`:112-132`). Verify
  with `tests/e2e/test_harness.py` case `test_an_error_among_the_rows_is_the_exit_status`, which
  runs `planner.main(["diagnose", ...])` against a table carrying an error and one carrying warnings
  alone and asserts both statuses and both printed tables, the way
  `test_a_build_of_a_deployment_carrying_an_error_prints_the_table_and_refuses` does at
  `tests/e2e/test_harness.py:2662`.
- [ ] 3.3 In the same reading, refuse a target that answers neither attribute with the command's own
  `ApplyError` naming the target and the two attributes it looked for - never a traceback, never an
  empty table, and never a row of the command's own. Verify with `tests/e2e/test_harness.py` case
  `test_a_target_that_answers_no_table_is_refused_by_the_command`.
- [ ] 3.4 Extend `test_the_help_text_is_read_as_the_only_document`
  (`tests/e2e/newcomer/test_newcomer.py:390-417`) with the new subcommand's own phrases, and correct
  its docstring, which says "The help named five subcommands": the assertions are phrases and not a
  count, so what is added is a phrase. Verify by running the newcomer folder with `nix run
  .#planner-e2e -- newcomer`.

## 4. The published vocabulary

- [ ] 4.1 In `lib/module.nix`, add `moduleKeys` to the exports at `:212-220`, beside
  `unitVocabulary`, `directoryKinds`, `unitKeys`, `unitReferenceKeys`, `implKeys` and
  `configFileKeys`, which the projection needs and which is otherwise a `let` binding at `:26-35`.
  Verify with a `tests/unit/consumer.nix` case reading it back.
- [ ] 4.2 In `lib/resolve.nix`, add `machineRegistryKeys`, `instanceKeys`, `everyKeys` and
  `reservationKeys` to the attrset returned at `:206-207` - it is built once per library import, not
  once per plan, which is why they go there rather than into what `resolve.resolve` answers. Verify
  with a `tests/unit/consumer.nix` case reading each back and with task 8.1's perf comparison
  showing no counter moved.
- [ ] 4.3 Write `lib/vocabulary.nix`, the projection: for each of the key tables (`moduleKeys`,
  `implKeys`, `configFileKeys`, `unitKeys`, `machineRegistryKeys`, `instanceKeys`, `everyKeys`,
  `reservationKeys`) the keys a declaration may carry; for each field of `unitVocabulary`
  (`lib/module.nix:84-103`) the korora type name its atom carries, read the way
  `lib/module.nix:1149` reads it; `directoryKinds` (`:63-67`) as the kind-to-mode map it is; the
  members of `atoms.domains` that are lists, and nothing else, because `domains.isZeroDuration`
  (`lib/atoms.nix:111`) is a predicate riding that table; `atoms.portRange` (`:151`); the value
  `planner.excluded` already publishes; and the sentence that this record describes and does not
  validate, naming the document and section that carry the failures which end an evaluation. Read
  each table rather than writing a list beside it. Verify with `tests/unit/consumer.nix` cases
  `testThePublishedVocabularyNamesEveryKeyADeclarationMayCarry`,
  `testATypeIsPublishedByItsNameAndNotByItsPredicate` and
  `testADomainThatIsAPredicateIsNotPublishedAsADomain`, the first crossing the projected key sets
  against the tables themselves so a table that grows without the projection growing fails, and the
  second walking every leaf and asserting each is a string, a list of strings or a record of those.
- [ ] 4.4 In `lib/default.nix`, publish `vocabulary` in the returned attrset beside `atoms`,
  `excluded`, `platform`, `platformSource` and `util` (`:57-64`), importing `lib/vocabulary.nix` in
  the `let` at `:20-48` with the tables it needs. Nothing enters `mkPlan`. Verify with `nix eval
  --json '.#lib.vocabulary'` answering, and with task 8.1's perf comparison.
- [ ] 4.5 In `flake-module.nix`, add `packages.planner-schema`, one `pkgs.writeText` of
  `builtins.toJSON` of the published vocabulary, named so that no application and no other package
  uses the name. Verify with `nix build .#planner-schema` and `jq . < result`, and with the newcomer
  case `test_an_author_reads_the_vocabulary_as_one_file`, which builds it and compares its decoded
  content against `nix eval --json .#lib.vocabulary`.

## 5. The published scaffold and its second entry point

- [ ] 5.1 Write `tests/e2e/newcomer/template/deployment/args.nix`, whose formals are the three
  `tests/e2e/generated-secret/deployment/args.nix:6-10` states and whose result is `{ args }`
  carrying the `instances`, `machines`, `interfaces` and `sources` that
  `tests/e2e/newcomer/template/deployment/default.nix:29-47` states today. Derive every host path
  inside `impl` as the folder already does - this file is inside the scan at
  `tests/unit/layers.nix:715`. Verify with `nix eval --json '.#debug.failures'` and with `nix build
  .#planner-e2e-newcomer`.
- [ ] 5.2 Rewrite `tests/e2e/newcomer/template/deployment/default.nix` to compose `args.nix` and
  hand its `args` to `operator.mkDeployment`, keeping `pkgs`, `planner` and `operator` as its
  formals and stating the deployment nowhere else - the shape
  `tests/e2e/newcomer/deployment/default.nix:1-7` already has one level up. Verify with `nix build
  .#planner-e2e-newcomer` producing the same artifact set it produces today.
- [ ] 5.3 In `tests/e2e/newcomer/template/flake.nix`, add the rows-only output: `planner.mkPlan`
  over the args from `args.nix`, handed store-shaped placeholder strings for the packages the
  deployment interpolates - the `tests/unit/worked.nix:6-9` precedent - published as the two names a
  caller reads, the rows and the rendered table. Keep the one `nixpkgs` and the one `nixplan` input
  it has (`:8-12`). Verify with `tests/unit/consumer.nix` case
  `testAPlaceholderPackageIsAStorePath`, asserting each placeholder is a path under the store
  directory the plan is read against, which is what `lib/util.nix:282-296` recognises.
- [ ] 5.4 Update the fenced blocks that **are** these files, in one edit with 5.1 to 5.3 because the
  check compares bytes and any other order is red in between: `README.md:52-80` is
  `tests/e2e/newcomer/template/flake.nix`, `docs/README.md` shows three files of the deployment
  (`tests/unit/layers.nix:389-407`), and both entry points have to be shown, so add blocks for
  `deployment/args.nix` and `deployment/default.nix` to `docs/README.md` and both files to
  `shownTexts`. Add `args.nix` to the file list at `tests/unit/layers.nix:1084-1090`, which names
  the example folder's files exactly. Verify with
  `testTheExampleADocumentShowsIsTheExampleAFolderHolds` and the added
  `testTheScaffoldCarriesTwoEntryPointsOverOneDeployment`, which reads both entry points off the
  committed directory and asserts the composing one states no instance of its own.
- [ ] 5.5 In `flake.nix` or `flake-module.nix`, add `templates.default` naming
  `./tests/e2e/newcomer/template` with a description, and a `welcomeText` naming the one command an
  author runs next and the document that carries the failures which end an evaluation. Verify with
  `nix flake show` naming it and with the newcomer case
  `test_a_reader_is_handed_the_scaffold_by_name`, which runs `nix flake init -t` into a directory of
  its own on the workstation and compares every written file byte for byte against the committed
  directory.
- [ ] 5.6 Add the newcomer cases for the two answers:
  `test_the_two_answers_agree_where_both_can_decide` makes the mutation the `refused` fixture
  already makes (`tests/e2e/newcomer/test_newcomer.py:687-706`), reads the rows once through each
  entry point, and asserts the same identifier and the same subject from both, and no error row from
  either for the scaffold as shipped. Verify with `nix run .#planner-e2e -- newcomer`.
- [ ] 5.7 Add the newcomer case
  `test_the_rows_of_a_deployment_are_read_with_no_package_set_instantiated`: read the rows through
  each entry point with `NIX_SHOW_STATS=1`, record both counter sets in this change's working notes,
  and assert the package-set-free reading costs an order of magnitude fewer values. The bound is an
  order of magnitude rather than a budget because the larger figure is nixpkgs' own and this
  repository does not gate it - `perf/eval.nix` evaluates no package set. Verify with `nix run
  .#planner-e2e -- newcomer`.

## 6. The failures that end an evaluation

- [ ] 6.1 In `docs/authoring.md:644-673`, state all four failures that end an evaluation in one
  place, each with what the interpreter prints and the edit that resolves it: the abort, the missing
  attribute with the slot case the section already carries, the function called without an argument
  its pattern requires, and the derivation handed to a module instead of `"${drv}"`, whose walk is
  `lib/util.nix:398-413` gated at `:435-444` and whose message names
  `pkgs/stdenv/generic/default.nix` and nothing of this tree. Keep `docs/diagnostics.md:372-386` as
  the short statement and have it name this section. Verify with `nix build
  .#checks.x86_64-linux.treefmt` and with the `tests/unit/layers.nix` case
  `testEveryFailureThatEndsAnEvaluationIsNamedInOnePlace`, which reads the four phrases back off the
  document with line breaks flattened, the way `testTheRootDocumentStatesHowAPathReachesAUnit`
  already reads four of the root document's.
- [ ] 6.2 In `lib/vocabulary.nix`, name that document and that section and carry no sentence of it.
  Verify with the `tests/unit/consumer.nix` case
  `testThePublishedVocabularyNamesTheSectionRatherThanCopyingIt`, asserting the published record
  names the file and the heading and that no sentence of the section appears in it.
- [ ] 6.3 Record the fourth trap's reducibility where a future change finds it: its own entry in
  `openspec/changes/PARKED.md`, the file that holds a design deliberately not built together with
  the trigger that revives it, naming the condition, the reading that could recognise it
  (`lib/util.nix:398-413`, gated at `:435-444`), the capability that would own the row and the
  trigger - the first deployment outside this repository that hits it, or the next change that opens
  `planner/unit-vocabulary`. Verify by reading the entry back and by `nix build
  .#checks.x86_64-linux.planner-tests`, whose coverage cross-walk reads `openspec/**` and must stay
  green.

## 7. Documents

- [ ] 7.1 In `README.md`, replace the instruction to read a path under `tests/` (`:48-50`, `:82-84`)
  with the published name a reader initialises the scaffold by, and add the new subcommand to the
  command table at `:90`. Verify with `nix build .#checks.x86_64-linux.treefmt` and with
  `testTheExampleADocumentShowsIsTheExampleAFolderHolds` still green, the flake block being asserted
  byte for byte.
- [ ] 7.2 In `docs/tooling.md:16-31`, add the two new outputs beside the four system-independent
  ones - the published template and the schema package - and state that the schema is a projection
  which describes and does not validate. In `docs/operator.md`, document the new subcommand beside
  the five: what a target may be, what it prints, what `--json` prints, and its exit status. Verify
  with `nix build .#checks.x86_64-linux.treefmt` and with
  `test_the_shell_carries_the_command_its_documentation_is_about`
  (`tests/e2e/newcomer/test_newcomer.py:321`) still green.
- [ ] 7.3 In `docs/authoring.md`, state beside the vocabulary tables that the published record is
  the machine-readable half of the same facts, projected from the library's own tables, and that a
  predicate is named and never serialised. Do not restate the tables. Verify with `nix build
  .#checks.x86_64-linux.treefmt`.

## 8. Gates and close

- [ ] 8.1 `nix eval --json '.#debug.failures'` returns `[]`; `nix build
  .#checks.x86_64-linux.planner-tests`; `nix build .#checks.x86_64-linux.treefmt`; `bash
  perf/measure.sh` compared against the baseline of 1.1, expecting every counter byte-identical -
  treat any movement as a defect of where the projection was placed and never as a budget to
  re-record - and `nix build .#checks.x86_64-linux.planner-perf`. The golden fixture is untouched by
  this change, so verify `nix eval --json .#debug.worked.plan | jq -S .` still compares equal to
  `fixtures/minimal-typed-edge/plan/backup.json` and treat a difference as a defect.
- [ ] 8.2 In **one** edit, now that every scenario has its test: delete this change's two `excused`
  entries from `tests/unit/coverage.nix`, add the same two paths to `accountable`, and tick every
  checkbox of this file. One edit because the excuse is stale the moment a box is ticked and
  `accountable` is unsatisfiable until the tests exist, so any other order puts the suite red in
  between. Then add this change's invariants to `CLAUDE.md`: under "The operator's command", the
  rows-only subcommand, the two attributes it reads and the refusal for a target answering neither;
  under "Interfaces, composition, reads", the published vocabulary as a projection, that a predicate
  is named and never serialised, and that the row catalogue is deliberately not projected; under
  "Registration points", that the scaffold is published as a `templates` output naming the folder
  rather than a copy of it, and that the scaffold's two entry points are one deployment text; and
  under "Known bugs", the four failures that end an evaluation in one place with the reducible one
  named. Verify with `nix build .#checks.x86_64-linux.planner-tests` and `nix build
  .#checks.x86_64-linux.treefmt`.
