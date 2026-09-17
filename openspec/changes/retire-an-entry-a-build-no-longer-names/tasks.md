## 1. Baseline and registration, before anything is edited

- [ ] 1.1 Record the perf baseline before touching anything the planner evaluates: run `bash
  perf/measure.sh` (or `~/.claude/outputs/measure-perf.sh worked 0`) and paste the nine counters into
  this change's working notes. Nothing of this change is expected to be inside `mkPlan` - the
  published table is `operator/read.nix`'s and the realisers' - so the counters are expected not to
  move, and the recorded baseline is what turns "expected" into evidence. The gate is two-sided with
  a 0.15 margin, so a regression is a task to fix and never a re-recorded budget.
- [ ] 1.2 Register this change's three delta specs in `excused` in `tests/unit/coverage.nix`, one
  line per file, each reason naming this change in the shape `excuseNamesChange`
  (`tests/unit/coverage.nix:373-378`) matches - "an unimplemented change: no task of
  retire-an-entry-a-build-no-longer-names has been done, so nothing in this package claims to satisfy
  it yet" - for
  `changes/retire-an-entry-a-build-no-longer-names/specs/operator/machine-report/spec.md`,
  `.../specs/operator/apply-command/spec.md` and `.../specs/operator/deployment-build/spec.md`.
  Verify with `nix build .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md`
  fails `testEverySpecificationIsClassified`.
- [ ] 1.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` (`tests/unit/coverage.nix:380-385`) reads this `tasks.md` for a single `- [x]`
  line, and `staleExcuses` (`:387-397`) fails the suite for an excuse whose change has landed, so
  ticking one box while the three paths are excused turns the suite red for a reason that reads like
  a missing test. The paths move to `accountable` and the boxes are ticked in the one edit task 10.2
  makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [ ] 1.4 `git add` every new file of this change before evaluating anything - the flake does not see
  an untracked path and the failure reads as a missing file. That is the three spec files,
  `proposal.md`, `design.md`, `tasks.md`, and every new file a later task creates (the portable-image
  module, its deployment build, and any new test file). Verify with `nix eval --json
  '.#debug.failures'` returning something other than a file-not-found error.

## 2. What each realiser publishes

- [ ] 2.1 In `flakelet/read.nix`, bind the `plan:` prefix once - it is written at
  `flakelet/read.nix:194` as part of `flake_url` - and publish it beside `nameRule`, `acceptsName`,
  `unitRule` and `acceptsUnit` in the endpoint record (`flakelet/read.nix:81-86`, `:139-148`) as what
  a machine's own answer names this realiser's holdings by. `meta.json` keeps being built from the
  same binding, so the prefix has one home. Verify with a `tests/unit/flakelet.nix` case asserting
  the published value and the `flake_url` of one artifact are the one string.
- [ ] 2.2 In `image/read.nix`, publish the name separator, the digest alphabet and the digest length
  the image file name is composed of (`image/read.nix:919` over `:208` and `lib/util.nix:495-496`) in
  the same record the name and unit rules are published in (`image/read.nix:520-526`). Publish data
  and no regular expression: a nix pattern and a python pattern are two dialects, and one published
  pattern would be one rule with two readings. Verify with a `tests/unit/image.nix` case asserting
  that the image file name of one entry splits, at the published separator, into a name
  `acceptsName` admits and a digest of the published length over the published alphabet.
- [ ] 2.3 In `operator/read.nix`, publish one `realisers` table in `manifest` (`operator/read.nix:608-627`),
  keyed by realiser, holding what each realiser published in 2.1 and 2.2, for **every** realiser the
  reading is handed rather than only the ones this deployment's entries state - an entry the build
  dropped may have been the last one of its realiser, and a table of the stated ones would make
  exactly that holding unfindable. Ask the realiser for it the way `endpoint.pathRule` and
  `endpoint.recordRule` are asked for (`operator/read.nix:180-190`, `:313-323`), so a third realiser
  is published by existing. Verify with 2.4.
- [ ] 2.4 Move the record's stated version from 1 to 2 in `operator/read.nix:609` and
  `cli/manifest.py:36`, with no dual support and no default for a missing table: a new command
  reading an older record would attribute no holding and report none, and a false negative here reads
  as nothing to retire. Update the literals in `tests/unit/operator.nix:835,839`,
  `tests/e2e/test_harness.py:170,1249,1263` and anything else `grep -rn '"version": 1'` finds; the
  two counterexample records already read `manifest.VERSION`. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` and `nix run .#planner-e2e -- test_harness.py`.
- [ ] 2.5 Add to `tests/unit/operator.nix` the three nix-unit tests of
  `specs/operator/deployment-build/spec.md`, which is the only layer those three scenarios land in
  because they are decisions of an evaluation and no machine is involved:
  `testTheRecordPublishesWhatAMachineNamesAFlakeletHoldingBy`,
  `testARecordPublishesTheFactForARealiserItsEntriesDoNotState` and
  `testEveryRealiserTheReadingIsHandedPublishesTheFact` - the last one crossing the realiser records
  the suite is handed against the table the reading published, so a realiser that publishes none
  fails here rather than reaching a deployment. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [ ] 2.6 Delete `LOCKED_URL_PREFIX` from `tests/e2e/delivery.py:36` and read the published value out
  of the deployment record instead, so `delivery.locked_url` stops keeping a second copy equal by
  comment. Verify that `tests/e2e/wired-pair/test_wired_pair.py` and
  `tests/e2e/newcomer/test_newcomer.py`, which both call `delivery.locked_url`, still pass:
  `nix run .#planner-e2e wired-pair`.

## 3. The command reads the record

- [ ] 3.1 In `cli/manifest.py`, read the `realisers` table into a frozen dataclass per realiser on
  `Deployment`, refusing a record that carries no table for a realiser one of its entries states,
  naming the realiser and the field the way the version refusal names both versions. Verify with a
  `tests/e2e/test_harness.py` case handing the command a record with the table removed and asserting
  the refusal names the realiser.
- [ ] 3.2 Keep `cli/` importing nothing of `lib/`, `operator/` or `tests/`: what a deployment is, the
  command learns from `manifest.json`. Verify by `grep -rn "^import\|^from" cli/` naming no such
  module, which is what `tests/unit/layers.nix` already asserts.

## 4. Asking a machine what it holds

- [ ] 4.1 In `cli/remote.py`, add the one question per machine: a script built from the published
  table that prints, per realiser, a marker line carrying the realiser and the exit status of its own
  tool, then that tool's answer - `flakelet status --json` with no names for one, `portablectl list
  --no-legend` for the other. A realiser joins the script only where the `scopes` the record
  publishes for it admit the machine's scope, and the image half carries `--user` where the
  machine's scope is `user`; a record publishing no `scopes` for a realiser admits every machine, so
  a system-scope machine is asked as stated above. One question per machine and not one per realiser
  or per holding, because a socket-activated sshd answers a burst of short logins with its own
  trigger limit, which is why `values_script` and `image_status_script` already fold their
  questions. Verify with `tests/e2e/test_harness.py` cases asserting one argv per machine carries
  both halves on a system-scope machine, and on a user-scope one only the halves whose published
  scopes admit it, with `--user` in the image half.
- [ ] 4.2 In `cli/remote.py`, read each half into holdings: a frozen dataclass carrying the realiser,
  the identity or name the machine gave it, and the state where the answer has one. A flakelet answer
  is a holding of this planner where its `locked_url` starts with the published prefix, and what
  follows is the plan key; an image row is one where its name splits at the published separator into
  a name and a digest of the published shape, and its identity is the name the listing printed with
  no plan key derived from it. A marker status of 126 or 127 is a machine without that tool and
  therefore no holding and no refusal; any other non-zero status is the command's own refusal naming
  the machine and what it said. Verify with `tests/e2e/test_harness.py` cases over fabricated answers
  for each of the four readings.
- [ ] 4.3 In `cli/remote.py`, add the retirement step per realiser through the existing `REALISERS`
  table (`cli/remote.py:533-542`): `flakelet remove <name>` without `--purge`, and `portablectl
  detach --now <name>` over the name the listing printed, with `--user` where the machine's scope is
  `user` - the flag the holdings question carried. Do not call `bin/detach`: the artifact of a
  holding this build does not name is not in this build and nothing on the machine roots it, and
  `image/default.nix:348-356` is the precedent for a step over what the machine answered. Every step
  goes through the channel `cli/remote.py` already dials; add no second channel here. Verify with
  the harness cases of 6.3.

## 5. The report

- [ ] 5.1 In `cli/report.py`, ask the holdings question once per machine of the selection, beside the
  value question, and print one line per holding the build names no entry for: `<machine> holds
  <identity>, which this build does not name`. Leave the exit status alone - a holding is an answer a
  machine gave, like a stale entry and a missing value - and leave `_held`
  (`cli/report.py:372-391`) answering the question it already answers, so an image of an earlier
  build of a named entry stays one line and is not also a holding. Verify with 5.2 and 7.
- [ ] 5.2 Add to `tests/e2e/test_harness.py` the seven scenarios of
  `specs/operator/machine-report/spec.md` that a recorder can answer, which is the only layer they
  land in because each is decided by what the command does with an answer rather than by what a tool
  prints: `test_a_machine_holding_nothing_unnamed_is_reported_without_such_a_line`,
  `test_an_unnamed_holding_does_not_change_the_exit_status`,
  `test_a_service_the_machines_own_configuration_declares_is_not_reported`,
  `test_an_entry_the_selection_excluded_is_not_reported_as_unnamed`,
  `test_a_machine_the_build_no_longer_names_is_not_asked`,
  `test_the_question_of_what_a_machine_holds_is_asked_once_per_machine` and
  `test_an_answer_about_what_a_machine_holds_that_the_command_cannot_read_is_a_refusal`. Fabricate
  only endpoint answers of the shape `tests/e2e/delivery.py:44-64` pins, never a `portablectl`
  answer: an image verdict measured against an invented listing is the one thing this layer exists
  to avoid, which is why the two image scenarios are in 7.2. Verify with `nix run .#planner-e2e --
  test_harness.py`.

## 6. The apply walk

- [ ] 6.1 In `cli/apply.py`, ask every machine of the selection what it holds before the first write,
  announce each holding where the run's other announcements are printed - after the cycle,
  contradicted-edge and unsatisfied-read lines and before the first step - with `; not retired`
  appended where the run was not asked to retire, and take every retirement before the first value
  write, the first copy and the first activation. Ask all machines before writing anything so a run
  that cannot read one answer has changed nothing anywhere. Verify with 6.3.
- [ ] 6.2 In `cli/planner.py`, add `--retire` to `apply` only, as a flag, with help that says it
  removes what the machines hold that the build does not name and deletes no state. Add nothing to
  `status` and add no subcommand: `README.md`'s five documented commands are asserted literally in
  `tests/unit/layers.nix`, and a step of the walk belongs in the walk. Verify with `nix run .#planner
  -- apply --help` and the parser cases in `tests/e2e/test_harness.py`.
- [ ] 6.3 Add to `tests/e2e/test_harness.py` the seven scenarios of
  `specs/operator/apply-command/spec.md` that a recorder can answer, which is the only layer they
  land in because each is about the argv a step is addressed by or a refusal made before a machine
  matters: `test_a_run_asked_what_it_would_do_names_no_holding`,
  `test_a_retirement_asks_the_endpoint_to_remove_the_entry`,
  `test_a_retirement_names_only_what_the_machine_answered_and_the_record_published`,
  `test_a_retirement_precedes_every_value_write_and_every_activation_of_the_run`,
  `test_an_entry_left_out_of_a_restricted_run_is_not_retired`,
  `test_a_restriction_naming_a_holding_the_deployment_does_not_place_is_refused` and
  `test_a_build_naming_no_entry_on_a_machine_retires_nothing_there`. The retirement argv assertions
  read the recorded vectors the harness already records, and the payload-dropping rule stands: assert
  the vector, never a fabricated secret. Verify with `nix run .#planner-e2e -- test_harness.py`.

## 7. The machines

- [ ] 7.1 In `tests/e2e/wired-pair/deployment/default.nix`, add a third build, `retired`, whose
  instances are the folder's own minus `sweep` (`tests/e2e/wired-pair/deployment/instances.nix:26-31`),
  so that the server machine keeps `site` and the machine is still named and still reachable while
  `sweep:job@<server>` is a holding the build does not name. Note that it is exposed as
  `packages.planner-e2e-wired-pair-retired` by the name rule `docs/cluster.md:97-98` states. Verify
  with `nix build .#packages.x86_64-linux.planner-e2e-wired-pair-retired`.
- [ ] 7.2 Add to `tests/e2e/wired-pair/test_wired_pair.py`, at the end of the file because the file
  order is the phase order, the six scenarios that need a real endpoint, which is the only layer they
  land in: `test_a_machine_holds_what_no_build_names`,
  `test_an_apply_of_a_build_that_dropped_an_entry_announces_what_the_machine_still_runs`,
  `test_an_apply_that_was_not_asked_to_retire_leaves_the_holding_running`,
  `test_a_retired_entry_stops_running_and_the_endpoint_no_longer_registers_it`,
  `test_a_file_the_retired_entry_wrote_survives_its_retirement` and
  `test_the_line_of_a_retirement_says_what_it_kept`. Three session-scoped phases in order: a report
  and an apply of `retired` without the flag, then the same apply with it. Start `sweep`'s own unit by
  hand before the retirement so the file it writes exists - the folder's schedule is `daily` on
  purpose and the job never fires during a run, and starting a unit by hand is what
  `secret-delivery`'s reboot phase already does - and assert that file is still there afterwards.
  Verify with `nix run .#planner-e2e wired-pair`.
- [ ] 7.3 In `tests/e2e/portable-image/deployment/`, add one instance placed on the booted machine's
  own tag whose module declares one long-running unit, no host path and `platforms = [
  "x86_64-linux" ]` - neither existing module fits, `mirror/copy.nix:7` being aarch64 and
  `report/watch.nix` owning the folder's host paths - and a third build, `retired`, whose instances
  are the folder's own minus that one. Derive every path the new module needs inside `impl` from its
  own `instance` and `member`, because `tests/unit/layers.nix` scans this folder's deployment for a
  host path. Verify with `nix build
  .#packages.x86_64-linux.planner-e2e-portable-image-retired` and with `nix build
  .#checks.x86_64-linux.planner-tests`, which is what refuses a declared host path.
- [ ] 7.4 Add to `tests/e2e/portable-image/test_portable_image.py`, at the end of the file, the three
  image scenarios, which land in this folder and nowhere else because it owns every claim this
  repository makes about `portablectl`:
  `test_an_image_the_machine_holds_for_no_entry_of_the_build_is_named_as_the_machine_listed_it`,
  `test_an_earlier_builds_image_of_a_named_entry_is_not_an_unnamed_holding` and
  `test_a_retired_image_is_detached_and_its_units_are_gone`. The phase attaches the new entry's image
  with that artifact's own `bin/attach`, then reports and applies `retired` with the flag; it sits
  after the existing `detached` fixture, which is why it re-attaches rather than assuming anything is
  attached, and it leaves `bin/detach` and
  `test_detaching_removes_the_units_and_the_staging_directory` untouched. Verify with `nix run
  .#planner-e2e portable-image`.
- [ ] 7.5 If the third artifact and its closure do not fit, give this folder's stage its own disk
  through `delivery.cluster_stage`'s `disk_gib` (`tests/e2e/portable-image/test_portable_image.py:283`)
  and never through `additionalSpace` in `tests/e2e/guest.nix:184`: growing the shared image re-keys
  every other folder's cut, and growing one stage re-keys only its own. Do not edit
  `tests/e2e/guest.nix` for this; if it is edited for any reason, run `rookery snapshot gc --all`
  before anything else. Verify with `nix run .#planner-e2e portable-image` on a cold cut.

## 8. Documents

- [ ] 8.1 In `docs/operator.md`, document the fifth thing a report says, `--retire`, where the
  retirement sits in the walk (`## The order apply walks`), that it deletes no state, and the limit
  of D8: a machine the build no longer names carries no address in the build, so it is emptied while
  the build still names an entry on it, or by hand with the endpoint's own tool. Verify with `nix
  build .#checks.x86_64-linux.treefmt`, which lints every `*.md` outside the excludes.
- [ ] 8.2 In `docs/cluster.md`, state the new phases of both folders and the third build each grows,
  beside the existing paragraphs for `wired-pair` and `portable-image`, and keep the sentence about
  `bin/detach` accurate - it is still the artifact's own script and still what that folder's last
  phase runs, and it is not what a retirement runs. Verify with `nix build
  .#checks.x86_64-linux.treefmt`.

## 9. Gates

- [ ] 9.1 `nix eval --json '.#debug.failures'` returns `[]`.
- [ ] 9.2 `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 9.3 `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 9.4 `nix build .#checks.x86_64-linux.planner-perf`, against the baseline of 1.1. The gate is
  two-sided with a 0.15 margin: a counter that moved is a task to fix here, never a re-recorded
  budget.
- [ ] 9.5 `fixtures/minimal-typed-edge/plan/backup.json` is **not** regenerated by this change: no
  declaration of that fixture changes, nothing of this change is inside `mkPlan`, and the fixture's
  plan is therefore byte-identical. Verify by `nix eval --json .#debug.worked.plan | jq -S .`
  comparing equal to the committed file, and regenerate only if it does not.

## 10. Close

- [ ] 10.1 Add this change's invariants to `CLAUDE.md`: under "The operator's command", that a report
  names what a machine holds that the build does not, that the line costs no exit status and that
  retirement is opt-in, uses the endpoint's own removal verb, deletes no state and is taken before
  anything is put in place; under "Realisers", that each realiser publishes what a machine's own
  answer names its holdings by and that `bin/detach` is the artifact's own contract and not what
  retires a holding; under "Known bugs" or "The operator's command", that a machine the build no
  longer names is out of reach and why. Name the registration points this change touches:
  `accountable`/`excused` in `tests/unit/coverage.nix` (10.2) and nothing else - no new suite, so
  `suites` in `tests/default.nix` is untouched; no new top-level path, so `classOf` in
  `tests/unit/layers.nix` is untouched; no new python directory, so `programs.mypy.directories` in
  `treefmt.nix` and `src` in `ruff.toml` are untouched; no directory kind, so `directoryKinds` in
  `lib/module.nix` is untouched; no excluded construct, so `lib/excluded.nix` is untouched; and no
  command is added or removed, so the `README.md` literals are untouched. Verify with `nix build
  .#checks.x86_64-linux.treefmt`, which lints `CLAUDE.md`.
- [ ] 10.2 In **one** edit, now that every scenario of task groups 2, 5, 6 and 7 has its test: delete
  this change's three `excused` entries from `tests/unit/coverage.nix`, add the same three paths to
  `accountable`, and tick every checkbox of this file. The three steps are one edit because the
  excuse is stale the moment a box is ticked (`changeHasLanded`, `tests/unit/coverage.nix:380-385`)
  and `accountable` is unsatisfiable until the tests exist, so any other order puts the suite red in
  between. Verify with `nix build .#checks.x86_64-linux.planner-tests`: no unclassified spec
  (`testEverySpecificationIsClassified`), no stale excuse (`testAnExcuseOutlivesTheStateItDescribes`),
  every heading of the three delta files with a test (`testAScenarioGainsNoTest`) and none of them
  named in both layers (`testOneBehaviourIsAssertedInBothLayers`) - 26 scenarios across three delta
  files, 3 under nix-unit and 23 under pytest.
