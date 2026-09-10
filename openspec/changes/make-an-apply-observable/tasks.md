# Tasks

Ordered so that each phase leaves the tree green. The four phases that need no machine land first,
smallest blast radius first: reading a record, measuring a value source, the ordering walk, then
reaching a machine. The step log and the report follow, because both read what those four decided.
The machine layer lands last, when a broken run has something to be broken about.

Each scenario of this change names its test by construction. Three homes are used and each task says
which: `tests/unit/operator.nix` for a fact about the reading, `tests/e2e/test_harness.py` for a
fact about the command's pure half (a recorder in place of a process table, no machine), and
`tests/e2e/wired-pair/` or `tests/e2e/portable-image/` for a fact that needs a booted machine. A
scenario restated from `apply-deployments-with-an-operator-command` keeps the test it already has;
only the scenarios listed below are new.

## 1. Reading a deployment record

- [x] 1.1 `cli/manifest.py`: read `version` and `storeDir`. A version other than the one the command
  implements is an `ApplyError` naming both; a `storeDir` other than the store the command runs
  against is an `ApplyError` naming both. Both are read before any entry, so a record of another
  shape is refused before its fields are interpreted.
  Verify: `tests/e2e/test_harness.py` gains
  `test_a_record_states_a_version_the_command_does_not_implement` and
  `test_a_record_names_a_store_the_command_does_not_run_against`, each over a record written into
  `tmp_path`, and each asserts the recorder was handed no argv.
- [x] 1.2 `cli/manifest.py:read`: stop defaulting a missing table. `interface.get("entries", {})`
  becomes a refusal naming the record and the field when the key is absent, while an empty table
  stays a deployment that places nothing.
  Verify: `test_a_record_carries_no_table_of_entries` in `tests/e2e/test_harness.py`, over a record
  whose key is misspelled, asserts the refusal names the record; a record with `"entries": {}` still
  reads.
- [x] 1.3 `cli/manifest.py:_entry`: the address becomes optional, carried as an absence, because
  `report-every-refusal-as-a-row` makes `operator-entry-machine-no-address` a warning. Every place
  that dials resolves the address and refuses there.
  Verify: `test_a_record_carrying_an_entry_with_no_address_is_read` in `tests/e2e/test_harness.py`:
  the read succeeds and an apply of that entry refuses naming the entry and the machine.
- [x] 1.4 `cli/manifest.py:resolve`: a target that names a path under the store directory and does
  not exist is refused as a collected build, naming the path and the reference to build again,
  before `nix build` is invoked. Nothing else about resolution changes, and no garbage-collection
  root is taken (design D10).
  Verify: `test_a_target_that_was_collected_is_named_as_collected` in `tests/e2e/test_harness.py`,
  over a plausible store path that is absent, asserts the message names the path and does not carry
  nix's own wording; `subprocess.run` is not reached.

## 2. The value source, measured where files are declared

- [x] 2.1 `cli/values.py`: `held` takes the delivered value entries and enumerates the files under
  each entry's own directory rather than `rglob("*")` over the source. `check` reports every
  undeclared file it finds, sorted, in one refusal.
  Verify: `tests/e2e/test_harness.py` gains
  `test_a_file_outside_every_values_own_directory_is_left_alone` (a `README` and a `.gitignore`
  beside the entry directories, and the apply proceeds) and
  `test_two_undeclared_files_are_both_named` (both names in the message). The existing
  `test_a_value_source_carries_bytes_the_plan_does_not_name` stays unchanged and stays red against a
  measurement that stopped looking inside a value's own directory: its spare file is
  `issuer:vars/session/spare` (`tests/e2e/test_harness.py:246-249`).

## 3. The ordering walk

- [x] 3.1 `cli/order.py:walk`: replace the `remaining[0]` tie-break with the rule of design D4. When
  no entry is ready, take the entries whose every unapplied provider is reachable from the entry
  itself, choose the lowest by key sort order, contradict only the edges into it from its own
  unapplied providers, and report each sorted by provider. The docstring states the rule and drops
  the sentence that describes the old one.
  Verify: `test_an_entry_off_the_cycle_keeps_its_order` in `tests/e2e/test_harness.py`, over the
  plan of the review's own case (`a:x@m` reads `b:y@m`; `b:y@m` and `c:z@m` read each other),
  asserts the order is `(b, c, a)` and the broken list holds exactly the edge between the pair.
  `test_two_entries_each_read_the_others_capability` stays green unchanged.

## 4. Reaching a machine

- [x] 4.1 `cli/remote.py:ssh_opts`: append `BatchMode=yes`, a `ConnectTimeout` and a server-alive
  bound after the inherited options, never before, because ssh takes the first value given for an
  option. `copy_env` carries the same string, so `nix copy` inherits them.
  Verify: `test_an_unreachable_machine_is_refused_without_a_prompt` in `tests/e2e/test_harness.py`
  asserts the argv carries the three options, that a caller's own `ConnectTimeout` in `NIX_SSHOPTS`
  appears before the command's, and that `test_a_throwaway_guest_is_reached_with_no_host_config`
  still passes with the guest's options first.
- [x] 4.2 `cli/remote.py:Subprocess`: `run` and `output` stop letting `CalledProcessError` escape.
  Each raises `ApplyError` naming the step's subject, the machine and what the machine printed, and
  the argv is not part of the message (`deliver-a-secret-without-exposing-it` owns why).
  Verify: `test_a_step_that_fails_names_the_machine_and_what_it_said` in
  `tests/e2e/test_harness.py`, with a runner that fails one step, asserts the message names the
  entry, the machine and the output, and that `planner.main` returns 1 rather than raising.

## 5. The step log, the restriction and the second run

- [x] 5.1 `cli/apply.py:apply`: move each `record(...)` before its step, and add a failure line
  naming the step, the machine and the machine's output when a step raises. The returned tuple holds
  the same lines in the same order, and the run attempts nothing after the failed step.
  Verify: `test_a_step_is_announced_before_it_is_attempted` and
  `test_the_run_stops_at_the_step_that_broke` in `tests/e2e/test_harness.py`, both with a runner
  that fails the second entry's copy: the log's last step line is that copy, and the recorder holds
  no argv after it.
- [x] 5.2 `cli/apply.py:writes` with `cli/values.py:reaching`: a restricted run resolves addresses
  and writes only for the machines of the selected entries, plus the delivery set of a value entry
  the restriction names directly. `values.check` keeps measuring the whole source (that property is
  unchanged); what narrows is the set of machines dialled.
  Verify: `test_a_restricted_run_contacts_only_the_machines_of_the_entries_it_applies` and
  `test_a_restriction_that_names_a_value_entry_reaches_its_delivery_set` in
  `tests/e2e/test_harness.py`, both by reading the addresses out of the recorder's argv.
- [x] 5.3 `cli/apply.py`: before running an image entry's attach script, ask the machine whether it
  already holds that image attached, using the same script `cli/remote.py:image_status_script`
  builds. An attached image is reported as already attached and the walk continues; anything else
  attaches.
  Verify: `test_an_image_the_machine_already_holds_attached_is_not_attached_twice` in
  `tests/e2e/test_harness.py`, with a runner answering `running`, asserts the attach script is in no
  argv and the following entry is still applied.

## 6. What a machine is asked, and what the answer says

- [x] 6.1 `cli/remote.py`: the two status scripts stop discarding standard error and stop turning
  every failure into the empty list. Each answers with what the machine said and its exit status, so
  the reading can tell an endpoint's answer from a machine that could not run one (design D6).
  Verify: the scripts hold no `2>/dev/null` and no `|| printf`, and
  `tests/e2e/wired-pair/test_wired_pair.py`'s existing use of `remote.flakelet_status_script` on a
  machine that registers nothing still yields the empty list.
- [ ] 6.2 `cli/report.py:_read_status`: read the endpoint's record whole. A flakelet line carries
  the generation, the identity the endpoint stores and `last_error` where the endpoint holds one; an
  image line carries the word `portablectl is-attached` printed, with only `detached` read as
  absence.
  Verify: `test_the_identity_a_machine_holds_is_in_its_report_line` in
  `tests/e2e/wired-pair/test_wired_pair.py` (against the machine's own record, as
  `test_the_command_reports_what_a_machine_holds` already reads it),
  `test_an_entry_the_endpoint_recorded_a_failure_for_is_not_reported_as_healthy` in
  `tests/e2e/test_harness.py` over a recorded answer carrying an error, and
  `test_an_image_reports_the_attachment_word_the_machine_printed` in
  `tests/e2e/portable-image/test_portable_image.py`, which asserts the line for an entry the command
  applied is not absence.
- [ ] 6.3 `cli/report.py:status`: four answers, one line each - absent, no endpoint, unreachable,
  and the endpoint's own record - and an entry whose machine declares no address reported as one the
  command will not dial.
  Verify: `test_an_entry_the_endpoint_does_not_register_is_reported_as_absent` in
  `tests/e2e/wired-pair/test_wired_pair.py` (the consumer's machine asked for the producer's entry,
  as the file already does it), and `test_a_machine_with_no_endpoint_is_not_reported_as_absent`,
  `test_a_machine_that_cannot_be_reached_is_reported_as_unreachable` and
  `test_an_entry_whose_machine_records_no_address_is_not_dialled` in `tests/e2e/test_harness.py`.
- [x] 6.4 `cli/report.py:status` and `cli/planner.py:_status`: print each line as it is known rather
  than after the last machine, and return a non-zero status when any machine could not be asked.
  Verify: `test_one_unreachable_machine_does_not_hide_the_others` and
  `test_a_report_that_could_not_ask_every_machine_exits_non_zero` in `tests/e2e/test_harness.py`,
  the first asserting the answering machine's line is printed with the other reported unreachable,
  the second asserting `planner.main` returns 1 there and 0 for a report whose entries are all
  absent.

## 7. What a build reports

- [x] 7.1 `cli/report.py:describe` and `cli/planner.py:_build`: print the rendered diagnostics table
  beside the entries and the values, and exit non-zero when a row is an error. The rows come from
  the tree, which `report-every-refusal-as-a-row` now leaves in place for an inapplicable
  deployment.
  Verify: `test_a_build_of_a_deployment_carrying_warnings_prints_them` and
  `test_a_build_of_a_deployment_carrying_an_error_prints_the_table_and_refuses` in
  `tests/e2e/test_harness.py`, over built directories written into `tmp_path`.

## 8. The record a build publishes

- [x] 8.1 `operator/read.nix`: `version` and `storeDir` stay where they are and become stated
  behaviour. Confirm both are read back from the built record rather than from the reading only.
  Verify: `testABuildStatesTheShapeOfItsRecordAndTheStoreItUsed` in `tests/unit/operator.nix`
  asserts both fields of the reading, and that neither depends on an entry being present.

## 9. The machine layer

- [ ] 9.1 `tests/e2e/wired-pair/test_wired_pair.py`: a final phase that cuts the route to the second
  machine, applies the deployment, and reads the broken run's report. It runs after every existing
  phase, restores the route, and leaves both entries applied from the same build, in the idiom
  `test_cutting_the_wires_far_end_is_visible` already uses. The break is deterministic, because the
  route is cut before the run starts and no thread races the walk (design D11).
  Verify: `test_a_run_broken_between_two_machines_names_the_step_that_broke`,
  `test_a_second_run_finishes_what_the_broken_run_left` and
  `test_a_machine_the_broken_run_never_reached_holds_what_it_held_before`, all in that folder, with
  `nix run .#planner-e2e -- wired-pair` green and the count recorded here.

## 10. Registration and documentation

- [x] 10.1 The four spec files of this change go in `accountable` in `tests/unit/coverage.nix`.
  Verify: the coverage cross-walk reports an empty difference rather than a specification it cannot
  read, and `nix build .#checks.x86_64-linux.planner-tests` is green.
- [x] 10.2 `docs/operator.md`: what a broken run leaves, why the recovery is a second apply rather
  than an undo, which steps cost nothing when repeated, how `--only` narrows the second run, the
  four answers `status` gives, and the ssh options the command adds. The document's `status` example
  is replaced by one a successful run can produce.
  Verify: the words interrupt, partial, resume and unreachable each appear, every command in the
  document runs as written, and `testAFileNamesAPathThatIsNotThere` passes.
- [x] 10.3 `CLAUDE.md`: the invariants this change creates - a step line precedes its step; a
  machine's refusal is the command's own error; absence is an endpoint's answer and nothing else;
  the walk contradicts only an edge on a cycle; the value source is measured under the value
  entries' own directories; a record is refused by version and by store; and ssh options are
  appended so a caller's own value wins.
  Verify: `nix build .#checks.x86_64-linux.treefmt` passes with the file edited.

## 11. Verification

- [ ] 11.1 `nix build .#checks.x86_64-linux.planner-tests -L` and `nix build
  .#checks.x86_64-linux.planner-delivery -L`: both green, with every new test present.
- [ ] 11.2 `nix build .#checks.x86_64-linux.treefmt -L`: no change to any file this change touched.
- [ ] 11.3 `nix run .#planner-e2e`: green for every folder, with the count recorded here against the
  count before the change.
- [ ] 11.4 Prove the new assertions can fail: put `record(...)` back after its step and confirm only
  the step-log cases fail; restore `remaining[0]` and confirm only the cycle case fails; restore
  `2>/dev/null || printf '[]'` and confirm only the endpoint cases fail; compare an image status
  against the literal `attached` and confirm only the attachment case fails. Revert each and confirm
  the tree is byte-identical to before the mutation.
