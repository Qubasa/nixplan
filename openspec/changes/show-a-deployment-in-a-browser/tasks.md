## 1. Baseline and registration, before anything is edited

- [x] 1.1 Record no perf baseline, and record why: this change edits nothing `perf/eval.nix`
  evaluates. It adds one top-level directory of python modules with its own `flake-module.nix`, and
  edits `flake.nix` (one `imports` line), `tests/unit/layers.nix` (`classOf`,
  `scannedDirectories`), `treefmt.nix` (one mypy root), `ruff.toml` (`src`),
  `tests/unit/consumer.nix`, `docs/`, `README.md` and `CLAUDE.md` - no file under `lib/**`,
  `image/**`, `flakelet/**`, `secrets/**`, `operator/**` or `cli/**`, and no plan field, no
  deployment-record field and no diagnostics row. Verify with `git diff --stat` naming no path
  under those directories, and by `nix build .#checks.x86_64-linux.planner-perf` passing against
  the budgets as committed, which is the assertion that the gated counters did not move. Inventing
  a baseline for a change outside `mkPlan` would record a measurement nothing in this change can
  change.
- [x] 1.2 Register this change's three delta specs in `excused` in `tests/unit/coverage.nix`, one
  line per file, each reason naming this change in the shape `excuseNamesChange` matches
  (`tests/unit/coverage.nix:389-394`), for
  `changes/show-a-deployment-in-a-browser/specs/operator/deployment-view/spec.md`,
  `.../specs/tooling/consumer-surface/spec.md` and `.../specs/tooling/repository-shape/spec.md`.
  Verify with `nix build .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md`
  fails `testEverySpecificationIsClassified`.
- [x] 1.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` reads this `tasks.md` for a single line beginning with a ticked checkbox
  (`tests/unit/coverage.nix:398-404`) and `staleExcuses` then fails the suite for an excuse that
  outlived it (`:406-416`), so ticking one box while the three paths are excused turns the suite red
  for a reason that reads like a missing test. The paths move to `accountable` and every box is
  ticked in the one edit task 11.2 makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [x] 1.4 `git add` every new file of this change before evaluating anything - the flake does not
  see an untracked path and the coverage cross-walk then reports the spec it cannot read rather than
  the file you forgot to stage. That is the three spec files, `proposal.md`, `design.md`,
  `tasks.md`, and every file a later task creates, the view's own directory included. Verify with
  `nix eval --json '.#debug.failures'` returning something other than a file-not-found error.
- [x] 1.5 Record which registration points this change does not trip, so a reader does not look for
  them: no new unit suite, so `suites` in `tests/default.nix:34-133` is untouched and the new cases
  go into the existing `consumer` (`:48-58`) and `layers` (`:121`) suites; no end-to-end folder, an
  e2e folder being discovered from `tests/e2e/*/deployment/default.nix` and the view's own
  cluster-level evidence being the open question of `design.md`; and no counterexample, the change
  asserting no claim the tree does not hold. Verify by `git diff` touching neither
  `tests/default.nix` nor `tests/e2e/`.

## 2. Where the view lives, and the four registration points

- [x] 2.1 Create the view's top-level directory with its own `flake-module.nix`, imported from
  `flake.nix:43-48` the way `cli/flake-module.nix` is, so deleting the view is deleting the
  directory and one import line (`cli/flake-module.nix:1-4`). The module publishes nothing yet.
  Verify with `nix flake show` completing and naming no new attribute.
- [x] 2.2 Add the directory to `classOf` in `tests/unit/layers.nix:54-85`, classed as the read-only
  view of a built deployment - the class the modified `Every top-level entry has a stated purpose`
  requirement states - and to `scannedDirectories` (`:295-306`) so its files are held to the path
  scan. Verify with `nix build .#checks.x86_64-linux.planner-tests`:
  `testATopLevelEntryBelongsToNoStatedClass` fails for an unclassified entry (`:98-100`) and
  `testAFileNamesAPathThatIsNotThere` for a token the scan cannot resolve.
- [x] 2.3 Add one `programs.mypy.directories` root for the view in `treefmt.nix:74-102`, with
  `--strict` and the written config that puts `cli` on the type checker's source path
  (`treefmt.nix:55-58`), because the view imports the command's reader, and with pytest as an extra
  python package because its tests live beside its modules. Verify with `nix build
  .#checks.x86_64-linux.treefmt` and by an introduced type error failing it.
- [x] 2.4 Add the view's directory to `src` in `ruff.toml:4`, so a first-party import of the view's
  own modules sorts the way it resolves at run time. Verify with `nix build
  .#checks.x86_64-linux.treefmt` after deliberately mis-sorting one import block and seeing it
  reported.

## 3. The reading of a built deployment

- [x] 3.1 Write the view's reading over one built deployment: it takes the target the operator's
  command takes and resolves it once through `manifest.resolve` (`cli/manifest.py:219-262`) before
  anything listens, so the only branch that invokes nix (`:248-253`) runs in the foreground and no
  request is ever a build, and it refuses a target it cannot read naming what was missing. Verify
  with `test_a_built_deployment_is_shown_with_no_machine_asked` and with
  `test_a_route_is_asked_while_nothing_can_build_or_dial`, the second run with a `PATH` carrying
  neither `nix` nor `ssh`.
- [x] 3.2 Build the machines document off `manifest.json` and the plan: each machine, the entries
  the manifest places on it in plan key order, each entry's realiser, profile, machine, address,
  units, digest and artifact path (`operator/read.nix:764-780`), each machine's `sealed` and `scope`
  (`:798-804`), and an entry realised into nothing shown as holding no artifact rather than as an
  empty path - the record omits `path` on purpose (`:776-779`). Verify with
  `test_every_placed_entry_appears_under_the_machine_it_is_placed_on` and
  `test_an_entry_realised_into_nothing_is_shown_as_holding_no_artifact`.
- [x] 3.3 Build the values document off the manifest's `values` (`operator/read.nix:781-787`) and
  the plan's value records: the delivery set, each declared file with its path, secrecy, ownership
  and mode, and no content of any kind - no route of the view reads a value's bytes from anywhere.
  Verify with `test_a_value_is_shown_with_its_delivery_set_and_its_files`.
- [x] 3.4 Build the diagnostics document with all six fields of every row - identifier, subject,
  severity, message, evidence and resolution (`lib/diagnostics.nix:45-63`) - reading them off the
  decoded rows rather than off the rendered table, and show a refused deployment as its rows plus
  the statement that no entry was realised. The two fields the command's reader drops today
  (`cli/manifest.py:664-679`) are restored by `answer-a-machine-question-as-a-record`, which this
  change is ordered behind and does not duplicate; the seam is recorded in
  `openspec/changes/INTEGRATION.md`. Verify with
  `test_a_row_is_shown_with_its_evidence_and_its_resolution` and
  `test_a_deployment_the_planner_refused_shows_its_rows_and_no_artifact`.

## 4. The graph and its layout

- [x] 4.1 Build the edge set out of the plan's resolved reads through the command's own reading:
  `order.reads` for one record per slot whichever shape it was recorded in
  (`cli/order.py:266-285`), one edge per provider a read names, which is one edge for a
  `reach = "one"` read (`fixtures/minimal-typed-edge/plan/backup.json:86-104`) and one per provider
  for a `reach = "all"` one (`:634-662`), dropping an edge onto an entry the build does not place
  the way `order.edges` does (`:239-244`), and naming the consumer and the slot for a read recorded
  in neither shape rather than contributing nothing in silence. Verify with
  `test_a_single_valued_read_is_one_edge_from_its_provider`,
  `test_a_read_of_every_provider_is_one_edge_per_provider` and
  `test_a_read_recorded_in_a_shape_the_view_does_not_know_is_named`.
- [x] 4.2 Compute the layout as data: the column of an entry is the index of its strong component in
  the order `order.walk` returns (`cli/order.py:69-101`), the row is plan key order within the
  column, a value is a cell in the column before its readers, the cell size is fixed, and a cycle is
  a column of more than one entry whose contradicted edges are drawn the way the walk records them
  (`:88-101`). The coordinates are a value the tests read. Verify with
  `test_one_deployment_renders_one_page`, which renders one fabricated build twice and compares the
  two pages byte for byte.

## 5. The page

- [x] 5.1 Render the page from those documents in the server: the machines and their entries as a
  table, the graph as inline SVG placed from the computed coordinates with each edge labelled by its
  slot, and the diagnostics as a six-column table. No script anywhere in the page and no reference
  to an asset the view does not serve itself. Verify with
  `test_a_page_carries_no_script_and_no_asset_it_did_not_serve`, which parses the served page with
  `html.parser` from the standard library.
- [x] 5.2 Spell every route the view answers so that its leading segment names no top-level entry of
  the repository, and name the page's own assets by those routes rather than by any path of this
  source: a repository-rooted token counts as a path exactly when its first segment is a top-level
  entry (`tests/unit/layers.nix:124-126`) and the scan reads raw file text including comments
  (`:314-316`), so a route spelled otherwise becomes a path the scan demands resolve. Verify with
  `nix build .#checks.x86_64-linux.planner-tests` after 2.2, and with the `layers` case task 9.4
  adds.

## 6. The live half

- [x] 6.1 Add the one live route: it calls the machine report's own status reading with the runner
  the command uses (`cli/report.py:115-168`), renders the record
  `answer-a-machine-question-as-a-record` publishes, and holds no script, no argv and no verdict
  vocabulary of its own - today's `Report` answers rendered sentences (`cli/report.py:81-86`,
  `:364-375`, `:422-436`), and this route consumes the record rather than parsing prose. A machine
  that could not be asked is shown as unasked, and the answer carries when it was taken. Verify with
  `test_the_live_view_asks_the_questions_the_report_asks`,
  `test_a_machine_that_answered_nothing_is_shown_as_unasked` and
  `test_a_live_answer_carries_when_it_was_taken`, all three against a recording runner with
  fabricated answers.
- [x] 6.2 Ask only when a reader asks: no timer, no background poll, no answer served as current
  that was taken for an earlier request. Verify with the recording runner in
  `test_the_live_view_asks_the_questions_the_report_asks` observing exactly one question per machine
  per request, and no argv recorded while no request is in flight.

## 7. The server

- [x] 7.1 Write the server over `http.server` from the standard library: the static routes answer
  from the deployment read at startup, the live route is the one of task 6.1, and no route writes to
  a machine, to the build, to the value source or to any file. Verify with
  `test_no_route_of_the_view_changes_a_machine_or_the_build`, which exercises every route against a
  recording runner and asserts no write and no route that applies, retires, rolls back or builds.
- [x] 7.2 Bind the loopback interface, and refuse an instruction to listen anywhere else naming the
  reason - an unauthenticated picture of a fleet's live state is not a surface to publish on a
  network. The program's own help states the target it takes, the port, and that it never mutates.
  Verify with `test_a_view_asked_to_listen_beyond_the_loopback_interface_is_refused`.

## 8. The flake wiring and the published names

- [x] 8.1 In the view's `flake-module.nix`, publish the server as `planner-view` in the namespaces
  that answer for a program a reader runs, the way the command is published
  (`cli/flake-module.nix:44-51`), and its source root as `planner-view-src` for the tests to import
  with no wrapper, the `planner-src` precedent (`:20`, `:45`). The fileset is the view's own files
  rather than python alone, because the page's static assets are part of what it serves - which is
  the reason the view is not inside `cli/`, whose published source is python-only (`:15-18`). Verify
  with `nix run .#planner-view -- --help` and `nix build .#planner-view-src`.
- [x] 8.2 Publish the check that runs the view's tests under a name of its own rather than under the
  program's, the way `checks.planner-delivery` runs the harness with pytest and `PYTHONPATH`
  (`flake-module.nix:379-388`): a name that names a program a reader runs must not also name a
  check. Verify with `nix build .#checks.x86_64-linux.<that name>` and by `nix flake show` listing
  the program and the check under two names.
- [x] 8.3 Add the view to the one shell's packages (`devshells.nix:14-22`), so a reader following
  the document types the program's own name. Verify by entering the shell and running the view's
  `--help`.

## 9. The tests

- [x] 9.1 Write the pytest layer beside the view's own modules, the way the command's
  counterexamples sit in `cli/` and are run by their own check (`flake-module.nix:347-356`), over
  built deployments fabricated on disk the way the harness fabricates them
  (`tests/e2e/test_harness.py:275-347`): a directory holding `plan.json`, `manifest.json`,
  `diagnostics.json`, `diagnostics.txt` and one artifact link per placed entry, read back through
  `manifest.read`. Every case named in tasks 3 through 7 lives here. Verify with `nix build
  .#checks.x86_64-linux.<the check of 8.2>`, which runs in a build sandbox with no nix and no
  machine.
- [x] 9.2 Assert the page and not only the JSON: parse the served page with `html.parser` and assert
  that every entry, every unit, every value and every edge the JSON documents carries is named in
  it, and that the page carries no script. State in the test file what is smoke rather than
  asserted - that a reader finds the picture legible - so the file does not read as covering it.
  Verify with `test_a_page_carries_no_script_and_no_asset_it_did_not_serve` and
  `test_one_deployment_renders_one_page`.
- [x] 9.3 Add the two `consumer` suite cases the modified `tooling/consumer-surface` requirements
  name, in `tests/unit/consumer.nix` (registered at `tests/default.nix:48-58`):
  `testAConsumerReadsTheViewOffAnOutput`, asserting the program and its source root resolve in the
  flake and that the view adds no input to the pinned set, and
  `testACheckOverAPublishedProgramTakesANameOfItsOwn`, asserting no name answers with the program in
  one namespace and with its check in another. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [x] 9.4 Add the two `layers` suite cases the modified `tooling/repository-shape` requirements
  name, in `tests/unit/layers.nix` (registered at `tests/default.nix:121`):
  `testAServedDocumentNamesARouteRatherThanAPath`, reading the view's served documents and asserting
  no leading segment of a route names a top-level entry, and
  `testAClassifiedDirectoryOfModulesIsCheckedAsWellAsClassified`, crossing the python-module
  directories of `classOf` against the mypy roots of `treefmt.nix` and the `src` of `ruff.toml` read
  as text, and failing naming the directory and the root it is missing from. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [x] 9.5 Record the one manual observation the suite cannot make: start the view against the worked
  fixture's build, open the page in a browser, and note in this change's working notes that the
  machines, the entries, the typed edges and the six-field diagnostics table are legible, with the
  date and the build's store path. This is the evidence for the claim `design.md` D8 marks as smoke,
  and it is recorded rather than asserted.

  **Recorded.** 2026-09-18, Chromium over CDP against `nix run .#planner-view`, two builds:
  `/nix/store/ylqi9g55lbic6q7lwxh7ymnb2231gnpw-planner-deployment` (planner-e2e-wired-pair) and
  `/nix/store/jmnq0hf462wg7hz4ifkkw8dw28gkiiz9-planner-deployment` (planner-e2e-secret-delivery).
  Legible in both: one heading per machine with its address and scope, one entry table per machine
  carrying realiser, profile, digest, resolved artifact path and unit names, the value cells in the
  column before their readers with the typed edges drawn to them, and the diagnostics table with
  all six fields of every row. The live half was asked with no machine reachable and rendered the
  record's own four non-answers rather than a page of errors.

## 10. Documents

- [x] 10.1 Write the view's own document under `docs/`: what it serves, the layout rule, that the
  static half dials nothing, that the live half asks the report's own questions and defines none,
  that it binds the loopback interface, and that it mutates nothing with the reason. Verify with
  `nix build .#checks.x86_64-linux.treefmt`, whose vale wrapper turns any printed alert into a
  failure (`treefmt.nix:34-48`).
- [x] 10.2 Add one row to the commands table of `README.md:86-93` naming the view, what it takes and
  what a reader needs beside it - a built deployment and a browser - because a command the root
  advertises is a command a reader can run and a dependency this repository cannot supply is named
  where the command is. Add the new check to the checks `docs/tooling.md` describes. Verify with
  `nix build .#checks.x86_64-linux.treefmt` and `nix build .#checks.x86_64-linux.planner-tests`,
  which reads `README.md` for the claims it is held to.

## 11. Gates and close

- [x] 11.1 `nix eval --json '.#debug.failures'` returns `[]`; `nix build
  .#checks.x86_64-linux.planner-tests`; `nix build .#checks.x86_64-linux.treefmt`; `nix build
  .#checks.x86_64-linux.<the check of 8.2>`; `nix build .#checks.x86_64-linux.planner-perf` against
  the budgets as committed, which task 1.1 states is the whole of this change's perf evidence. The
  golden fixture is expected byte-identical, nothing here touching `lib/**`: verify by `nix eval
  --json .#debug.worked.plan | jq -S .` comparing equal to
  `fixtures/minimal-typed-edge/plan/backup.json`, and treat a difference as a defect of this change
  rather than as a regeneration.
- [x] 11.2 In **one** edit, now that every scenario has its test: delete this change's three
  `excused` entries from `tests/unit/coverage.nix`, add the same three paths to `accountable`
  (`tests/unit/coverage.nix:57-100`), and tick every checkbox of this file. One edit because the
  excuse is stale the moment a box is ticked and `accountable` is unsatisfiable until the tests
  exist, so any other order puts the suite red in between. Then add this change's invariants to
  `CLAUDE.md`: under "Registration points", the view's class in `classOf`, its `scannedDirectories`
  entry, its mypy root and its `ruff.toml` `src` entry, and the rule that a served route's leading
  segment names no top-level entry; under "Tooling", that the view is python over the standard
  library with no client-side dependency and that its check is named for the tests rather than for
  the program; and the statement that the view reads a build and mutates nothing, the live half
  asking the machine report's own questions and defining none. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`.
