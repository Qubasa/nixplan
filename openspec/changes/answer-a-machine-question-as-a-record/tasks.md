## 1. Baseline and registration, before anything is edited

- [ ] 1.1 Record no perf baseline, and record why: this change touches nothing `perf/eval.nix`
  evaluates. It edits `cli/report.py`, `cli/remote.py`, `cli/apply.py` and `cli/manifest.py`, plus
  `docs/operator.md` and `tests/e2e/test_harness.py`, and no file under `lib/**`, so no plan field,
  no row, no registry key and no key input moves and the nine gated counters cannot. Verify by
  `nix build .#checks.x86_64-linux.planner-perf` passing against the committed
  `perf/budgets.json` with nothing re-recorded, and treat any counter movement as a defect of this
  change rather than as a budget to re-record.
- [ ] 1.2 Register this change's two delta specs in `excused` in `tests/unit/coverage.nix`, one line
  per file, each reason naming this change in the shape `excuseNamesChange` matches
  (`tests/unit/coverage.nix:389-394`), for
  `changes/answer-a-machine-question-as-a-record/specs/operator/machine-report/spec.md` and
  `changes/answer-a-machine-question-as-a-record/specs/operator/deployment-build/spec.md`. Verify
  with `nix build .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [ ] 1.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` in `tests/unit/coverage.nix:398-404` reads this `tasks.md` for a single line
  beginning with a ticked checkbox, and `staleExcuses` (`:406-416`) then fails the suite for an
  excuse whose change has landed, so ticking one box while the two paths are excused turns the
  suite red for a reason that reads like a missing test. The paths move to `accountable` and every
  box is ticked in the one edit task 8.2 makes, which is the last task of this file. Verify by
  ticking nothing until then, and by `nix build .#checks.x86_64-linux.planner-tests` staying green
  through every task below.
- [ ] 1.4 `git add` every new file of this change before evaluating anything - the flake does not
  see an untracked path and the coverage cross-walk then reports the spec it cannot read rather
  than the file you forgot to stage. That is the two spec files, `proposal.md`, `design.md` and
  `tasks.md`. Verify with `nix eval --json '.#debug.failures'` returning something other than a
  file-not-found error.

## 2. The records a question answers

- [ ] 2.1 In `cli/report.py`, add the frozen record one entry's answer is. Its fields are the ones
  the readings already compute and no others: the plan key, the machine and the realiser the line
  names (`cli/report.py:144`); how the machine was reached, one closed value per condition
  `_answered` tells apart (`:364-375`, over the sentinels at `:77-78`, `remote.UNREACHABLE` and
  `remote.MISSING` at `cli/remote.py:59-60`); what the machine printed, which the no-endpoint
  answer carries (`:372`); whether the endpoint answered and registered nothing (`:426-427`,
  `:513-514`); the identity the machine holds; the identity the build published; the unit
  comparison's three answers (`:482-486`); the attachment state the machine's own tool printed
  (`:514`, `:520-521`); the configuration paths that disagree (`:524-526`); and the last error
  (`:435`). A field the reading did not compute for a given way of being reached is absent rather
  than empty. Verify with a `tests/e2e/test_harness.py` case asserting the field set of a record
  for each of the five ways an entry can be answered, and one asserting an unreachable machine's
  record carries no identity field at all.
- [ ] 2.2 In `cli/report.py`, add the frozen record one value's answer on one machine is: the value
  key, the machine, whether every declared path is present (`:266-282`) and the machine's own
  verdict on the sealed copy, one closed value per word `_seals` reads (`:319-337`, over
  `remote.OPENS`, `remote.MISSING_COPY` and `remote.UNCHECKED` at `cli/remote.py:128-131`,
  including the machine that holds no unsealer). Verify with harness cases over fabricated machine
  answers for a present value, a missing path, a copy that does not open, a copy that is not there
  and a machine with no unsealer.
- [ ] 2.3 In `cli/remote.py`, delete `Holding.sentence` (`cli/remote.py:938-940`) from the record,
  and in `cli/report.py` carry the holding beside the machine it was asked of as the third record
  shape. `Holding`'s four fields stay as they are (`cli/remote.py:920-941`). Verify with a harness
  case asserting the record escapes `status` and that no call site of `sentence` remains, by
  `grep -rn 'sentence(' cli/` returning nothing.

## 3. The readings answer with records

- [ ] 3.1 In `cli/report.py`, make `_answered` (`:364-375`) return the record rather than a string:
  the five conditions become the five values of the reached field, and the branch that is the
  command's own refusal stays a refusal (`_registered`, `:439-468`) rather than becoming a sixth
  value. Verify with harness cases asserting each of the five records, and one asserting an
  endpoint answer that is not a status still raises the command's own error naming the entry and
  what the machine said.
- [ ] 3.2 In `cli/report.py`, make `_read_status` (`:422-436`) and `_running` (`:471-486`) fill the
  record's identity, unit-comparison and last-error fields instead of composing
  `generation <n> of <url> ...`. The generation, the locked url and the last error come off the
  first registration (`:432-435`) and the comparison is still against `unit_files(entry)` (`:484`).
  Verify with harness cases asserting the record for an endpoint that runs this build's units, one
  that runs others, one that reports nothing to compare, and one carrying a last error.
- [ ] 3.3 In `cli/report.py`, make `_read_attachment` (`:489-521`) fill the held identity, the
  built identity, the attachment state and the disagreeing configuration paths, keeping `_held`
  (`:529-548`) as the projection of the entry's own image out of the listing and `entry.digest` as
  the identity the build published (`:517`). `_beside` (`:524-526`) becomes part of the renderer,
  not of the reading: the record carries the pairs and the renderer joins them. Verify with harness
  cases asserting the record for a machine holding this build's image, one holding an earlier
  build's, one holding a detached image, one whose configuration bytes disagree, and one whose
  listing cannot be read.
- [ ] 3.4 In `cli/report.py`, make `_absent` (`:266-282`) and `_seals` (`:298-337`) answer with the
  value records of 2.2 instead of lines, keeping the marker-split of the one login's two halves
  (`_halves`, `:254-263`) and asking nothing new of the machine. Verify with a harness case
  asserting the value question's argv is unchanged byte for byte against the recorded vector, and
  the cases of 2.2.

## 4. The one renderer

- [ ] 4.1 In `cli/report.py`, add the one function that renders a record into the line the command
  prints, covering all three record shapes and every condition of each: the five ways an entry is
  answered, the two identity comparisons and their words, the configuration join `_beside` made,
  the missing-value line, the three seal lines and the holding line. No reading composes a line of
  its own after this task. Verify by `grep -n 'record(f"' cli/report.py` returning nothing and by
  the byte-identity task 5.1.
- [ ] 4.2 In `cli/report.py`, make `status` (`:139-168`) collect the records and hand each rendered
  line to `log` as it is known (`:140`, `:144`), and make `Report` (`:81-86`) carry the records
  beside `lines` and `unasked`. `unasked` stays exactly what it is, so `planner status` exits
  non-zero for the machines it could not ask and for nothing else (`cli/planner.py:69-82`). Verify
  with harness cases asserting one record per question asked, `lines` equal to the rendered records
  in order, and the exit status of a report whose every machine answered staying zero however stale
  the records are.
- [ ] 4.3 In `cli/apply.py`, make `holding_lines` (`:205-215`) render through the function of 4.1
  and keep appending `; not retired` onto that one string (`:212-215`). Verify with the harness's
  own retirement cases, whose asserted lines are
  `tests/e2e/test_harness.py:3312`, `:3391-3392` and `:3464`.

## 5. The compatibility contract

- [ ] 5.1 Assert byte identity against the end-to-end folders that already match on those strings,
  without editing one of their assertions: the flakelet verdict
  (`tests/e2e/wired-pair/test_wired_pair.py:703-706`, `:747-749`,
  `tests/e2e/newcomer/test_newcomer.py:681-684`, `tests/e2e/test_harness.py:2487-2488`), the last
  error (`tests/e2e/test_harness.py:2338-2341`), the four non-answers
  (`tests/e2e/test_harness.py:2390`, `:2422`,
  `tests/e2e/friend-enrollment/test_friend_enrollment.py:862-866`), the image verdicts
  (`tests/e2e/portable-image/test_portable_image.py:690`, `:878-881`, `:1058-1059`) and the holding
  line (`tests/e2e/wired-pair/test_wired_pair.py:965-966`,
  `tests/e2e/portable-image/test_portable_image.py:1446`). Verify with
  `nix build .#checks.x86_64-linux.planner-counterexamples-cli`, the harness cases above, and
  `nix run .#planner-e2e -- wired-pair portable-image`; an edited assertion in any of those files
  is a failure of this task and not a fix.
- [ ] 5.2 Add the harness case that holds the contract in one place: render every record shape and
  every condition of each and compare against the literal lines
  `docs/operator.md:515-519`, `:521-528`, `:541-547`, `:573-578` and `:607-609` document, so a
  reworded sentence fails here rather than in a folder that needs a machine. Verify with that case
  in `tests/e2e/test_harness.py`.

## 6. The diagnostics decode

- [ ] 6.1 In `cli/manifest.py`, give `Diagnostic` (`:123-131`) the `evidence` and `resolution`
  fields `lib/diagnostics.nix:45-63` requires of every row, and decode them in `_rows`
  (`:664-679`) the way the four it already reads are decoded (`:670-676`). The fix is in the decode
  and nowhere else: `_rows` is the only reader of `diagnostics.json`, which
  `operator/default.nix:319-329` writes whole, and `Deployment.rendered` (`:206-210`) already
  composes its fallback lines out of the decoded rows. Verify with a harness case reading a built
  deployment whose plan the planner refused and asserting every row carries all six fields with the
  bytes the build wrote, and by `grep -rn 'diagnostics.json\|ROWS' cli/` showing one decode.

## 7. Documents

- [ ] 7.1 In `docs/operator.md`, state under "The command" that every line of a report is the
  rendering of one record and that the record is what the library function returns, and document
  the record's fields beside the tables that document the lines (`:515-519`, `:521-528`,
  `:541-547`, `:573-578`, `:607-609`), leaving every documented line byte-identical. State that
  staleness is a field of the record and still never an exit status. Verify with
  `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 7.2 In `docs/diagnostics.md`, state that a row reaches a program with all six fields and that
  the command's one decode is where they are read, so an author's tool names the declaration to
  edit out of the row rather than out of the rendered table. Verify with
  `nix build .#checks.x86_64-linux.treefmt`.

## 8. Gates and close

- [ ] 8.1 `nix eval --json '.#debug.failures'` returns `[]`; `nix build
  .#checks.x86_64-linux.planner-tests`; `nix build
  .#checks.x86_64-linux.planner-counterexamples-cli`;
  `nix build .#checks.x86_64-linux.planner-perf` with nothing re-recorded, which is what 1.1
  predicted; `nix run .#planner-e2e -- wired-pair portable-image newcomer`. Verify by each command
  exiting zero.
- [ ] 8.2 In **one** edit, now that every scenario has its test: delete this change's two `excused`
  entries from `tests/unit/coverage.nix`, add the same two paths to `accountable`, and tick every
  checkbox of this file. One edit because the excuse is stale the moment a box is ticked and
  `accountable` is unsatisfiable until the tests exist, so any other order puts the suite red in
  between. Then add this change's invariants to `CLAUDE.md`: under "The operator's command", that a
  machine question is answered as a record and every line is one rendering of one record, that the
  four non-answers are four values of one field rather than four spellings, and that staleness is a
  field and still never an exit status; and that the command's one decode of `diagnostics.json`
  carries all six fields a producer builds a row with. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`.
