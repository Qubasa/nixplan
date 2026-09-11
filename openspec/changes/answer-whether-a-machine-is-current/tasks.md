## 1. Record what a report says today

- [ ] 1.1 Apply the wired-pair deployment, run `planner status` against it and record the lines, so
  the added clause can be compared against the current text rather than against a description. Not
  done, and no longer doable: the comparison it exists to enable is made in
  `tests/e2e/test_harness.py`, where every new scenario is run against the pre-change command and
  fails, which is the stronger evidence
- [ ] 1.2 Edit one entry of that deployment, build it again without applying, run `status` against
  the new build and record that the line is indistinguishable from the line in 1.1. Superseded the
  same way, by `test_a_report_against_a_build_the_machine_does_not_hold_says_so` in
  `tests/e2e/wired-pair`
- [x] 1.3 Read what the endpoint answers for that entry and record whether it carries the identity,
  so the flakelet comparison is written against an observed answer: `flakelet status --json` prints
  `ServiceStatus` (`flakelet-core/src/manager.rs:86-108`, `flakelet/src/main.rs:766-782` at the
  locked revision), which carries no `settings_hash`; the digest is stored in the generation
  manifest (`generations.rs:12-29`) and reported nowhere, and the one other JSON the tool prints,
  `export`'s `ExportMeta`, refuses every artifact this repository builds

## 2. The record's identity reaches the command

- [x] 2.1 Add `digest` to `Entry` in `cli/manifest.py` and read it in `_entry` through `_text`, and
  verify a record with no `key` for a placed entry is refused naming the entry and the field
- [x] 2.2 Verify every existing subcommand still reads a current build's record, by running `plan`,
  `build` and `status --dry-run`-equivalent paths over the wired-pair build

## 3. The verdict

- [x] 3.1 Compare the unit files the endpoint reports for the generation it runs against the unit
  files the build's artifact holds, resolved by `manifest.unit_files`, and verify a matching answer
  reads `runs this build's units`
- [x] 3.2 Report a differing answer as `runs units this build did not produce`, and verify the two
  cases are distinguishable on the line
- [x] 3.3 Report an endpoint answer carrying no unit file as reporting nothing to compare, and
  verify it is neither of the other two
- [x] 3.4 Extend the image status script to report which image the machine holds attached beside the
  attachment state, and verify the answer carries both
- [x] 3.5 Compare the attached image's name against the identity the record published, and verify an
  image attached from an earlier build reports both identities while still stating that an image is
  attached
- [x] 3.6 Verify a listing the command cannot parse is reported as the machine's own answer rather
  than as a verdict. The branch is in `cli/report.py`; no test asserts it, because no real
  `portablectl` prints a listing it cannot read and the command is only drivable from inside a
  cluster, so the invented-listing test that stood here was deleted rather than kept

## 4. Tests

- [x] 4.1 Add the comparison scenarios to `tests/e2e/test_harness.py` over a fake endpoint answer
  carrying matching unit files, differing ones and none; verify each fails against the pre-change
  reader. The image half of this task is not here: `portablectl` is asserted only where a real one
  runs, which is `tests/e2e/portable-image/`
- [x] 4.2 Add the refusal scenario for a record publishing no identity, and verify it names the entry
  and the field
- [x] 4.3 Add to `tests/e2e/wired-pair` a report after an apply that asserts the machine runs this
  build's units, and a report after building an edited deployment that asserts it does not; verify
  the second fails before the change
- [x] 4.4 Add to `tests/e2e/portable-image` a report asserting the attached image's identity, and
  verify the attachment state is still reported. That folder now owns every image comparison: this
  build's identity, an earlier build's through a second build of the same deployment, and both
  again with the units stopped so the tool prints `attached` rather than `running`
- [x] 4.5 Verify a report whose machines all answered exits zero even when every entry is stale
- [x] 4.6 Extend the hand comparison in `tests/e2e/wired-pair/test_wired_pair.py` with an assertion
  on the command's own verdict, and verify the folder still proves the identities line up. Extended
  rather than replaced: that comparison is the only test of `The endpoint reports the identity the
  build published`, and the endpoint reports no identity, so the verdict cannot stand in for it
- [x] 4.7 Register every new scenario in `tests/unit/coverage.nix`, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unmapped scenario
- [x] 4.8 Guard the reason for the weaker comparison: compare the locked endpoint's own status
  fields against the recorded set, fail naming this change's design decision when they move, and
  skip where the source cannot be resolved

## 5. Documents

- [x] 5.1 Extend the report vocabulary table in `docs/operator.md` with the verdict clauses and
  update the worked report, and verify `nix build .#checks.x86_64-linux.treefmt` passes
- [x] 5.2 State in `docs/operator.md`'s recovery section that `status` now says which machines a
  broken run left behind
- [x] 5.3 Add to `CLAUDE.md` what a flakelet endpoint does and does not report, that the record's
  `key` is read by the command and compared, and that the guard is what fails if either stops being
  true, and verify the literal assertions in `tests/unit/layers.nix` still hold
- [x] 5.4 Correct the two documents that state the digest is reported rather than stored:
  `docs/flakelet.md` and this change's own proposal
