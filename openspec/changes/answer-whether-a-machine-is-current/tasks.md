## 1. Record what a report says today

- [ ] 1.1 Apply the wired-pair deployment, run `planner status` against it and record the lines, so
  the added clause can be compared against the current text rather than against a description
- [ ] 1.2 Edit one entry of that deployment, build it again without applying, run `status` against
  the new build and record that the line is indistinguishable from the line in 1.1
- [ ] 1.3 Read one machine's `flakelet status --json` for that entry and record whether the
  generation record carries `settings_hash`, so the flakelet comparison is written against an
  observed answer

## 2. The record's identity reaches the command

- [ ] 2.1 Add `digest` to `Entry` in `cli/manifest.py` and read it in `_entry` through `_text`, and
  verify a record with no `key` for a placed entry is refused naming the entry and the field
- [ ] 2.2 Verify every existing subcommand still reads a current build's record, by running `plan`,
  `build` and `status --dry-run`-equivalent paths over the wired-pair build

## 3. The verdict

- [ ] 3.1 Pass the entry's published identity into `_read_status` and compare it against the
  generation record's `settings_hash`, and verify against the answers recorded in 1.3 that a matching
  identity reads `current`
- [ ] 3.2 Report a differing identity as `holds <machine identity>, built <record identity>`, and
  verify with the second build from 1.2 that the line now distinguishes the two cases
- [ ] 3.3 Report an endpoint answer carrying no identity as the endpoint reporting none, and verify it
  is neither `current` nor a differing identity
- [ ] 3.4 Extend the image status script to report which image the machine holds attached beside the
  attachment state, and verify against the portable-image folder that the answer carries both
- [ ] 3.5 Compare the attached image's name against the name the build published, and verify an image
  attached from an earlier build reports both identities while still stating that an image is attached
- [ ] 3.6 Verify a listing the command cannot parse is reported as the machine's own answer rather
  than as a verdict

## 4. Tests

- [ ] 4.1 Add the comparison scenarios to `tests/e2e/test_harness.py` over a fake endpoint answer
  carrying a matching identity, a differing one, and none; verify each fails against the pre-change
  reader
- [ ] 4.2 Add the refusal scenario for a record publishing no identity, and verify it names the entry
  and the field
- [ ] 4.3 Add to `tests/e2e/wired-pair` a report after an apply that asserts `current`, and a report
  after building an edited deployment that asserts both identities on the line; verify the second
  fails before the change
- [ ] 4.4 Add to `tests/e2e/portable-image` a report asserting the attached image's identity, and
  verify the attachment state is still reported
- [ ] 4.5 Verify a report whose machines all answered exits zero even when every entry is stale
- [ ] 4.6 Replace the hand comparison in `tests/e2e/wired-pair/test_wired_pair.py:739-741` with an
  assertion on the command's own verdict, and verify the folder still proves the identities line up
- [ ] 4.7 Register every new scenario in `tests/unit/coverage.nix`, and verify
  `nix build .#checks.x86_64-linux.planner-unit` reports no unmapped scenario

## 5. Documents

- [ ] 5.1 Extend the report vocabulary table in `docs/operator.md:395-399` with the verdict clauses
  and update the worked report at `:386-389`, and verify
  `nix build .#checks.x86_64-linux.treefmt` passes
- [ ] 5.2 State in `docs/operator.md`'s recovery section that `status` now says which machines a
  broken run left behind, and verify the claim matches the lines recorded in 1.1 and 1.2
- [ ] 5.3 Add to `CLAUDE.md` that the record's `key` is read by the command and compared, so a future
  reader does not remove it as unused, and verify the literal assertions in `tests/unit/layers.nix`
  still hold
