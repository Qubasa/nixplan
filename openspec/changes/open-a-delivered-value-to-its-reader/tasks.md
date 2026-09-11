## 1. Record what exists

- [ ] 1.1 List this change's four spec files under `excused` in `tests/unit/coverage.nix` with the
  reason the tree uses for an unimplemented change, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unclassified specification
- [ ] 1.2 Record the value entry keys, the `files` records and the rendered `deploy.remote` step of
  `tests/e2e/secret-delivery/` and `tests/e2e/generated-secret/` before any edit, so "unchanged for a
  record that declares nothing" is a byte comparison
- [ ] 1.3 Record the current denial list for one entry under each of the four profiles
  (`image/read.nix:288-297`), so the narrowed rule is compared against a measurement

## 2. The record

- [ ] 2.1 Add a `fileMode` atom to `lib/atoms.nix` and verify it accepts `"0400"`/`"0640"` and
  refuses `640`, `"0999"` and `"rw-r-----"`
- [ ] 2.2 Widen the generated-file allow-list in `lib/module.nix` to `secrecy`, `owner`, `group`,
  `mode` with the three defaults, and verify a file declaring nothing records `root`/`root`/`0400`
  and a file declaring a bad mode produces the row
- [ ] 2.3 Carry the three fields through `lib/resolve.nix`'s file record and into `lib/plan.nix`'s
  value entry `files` and `keyInput`, and verify the keys recorded in 1.2 are unchanged for the
  defaults and differ when a mode is declared
- [ ] 2.4 Verify one value delivered to two machines records one ownership and one mode, by planning
  a two-recipient value and comparing the records

## 3. The planner's row

- [ ] 3.1 Add `slot-reads-value-unreadable-by-user` in `lib/module.nix`, comparing a unit's `user`
  and declared groups against the record of every file backing an export the entry reads, and verify
  the row names the entry, the unit, the account, the slot, the export and the record
- [ ] 3.2 Verify the four negative cases produce no row: the unit is the file's owner, the file's
  group is one the unit declares at a mode with group read, the mode has world read, and the unit
  declares no `user`
- [ ] 3.3 Verify one row for one offending unit beside a privileged unit of the same entry, and that
  the entry and both units are still recorded

## 4. The two writers

- [ ] 4.1 Change `cli/remote.py`'s value write to create the file at the recorded mode before the
  first byte, then set group and owner, and verify with a two-umask test that the mode is the
  recorded one in both cases
- [ ] 4.2 Verify an interrupted write leaves either the previous file or none, and never a readable
  fragment, by interrupting the script between creation and completion
- [ ] 4.3 Refuse, as the command's own error naming the value, the machine and the account, a
  recorded owner the machine does not have, and verify the file is not left owned by the login
- [ ] 4.4 Set ownership and mode on every apply rather than only when bytes moved, and verify a
  widened mode and a changed owner are both restored by a re-apply with unchanged bytes
- [ ] 4.5 Change `secrets/backend.nix`'s rendered step to read the record, and verify the rendered
  step recorded in 1.2 is byte-identical for the defaults and carries the declared values otherwise

## 5. The narrowed denial

- [ ] 5.1 Add `supplementaryGroups` to `systemdDirectives` in `image/read.nix` and verify a unit
  declaring it renders the directive and a unit declaring none renders nothing new
- [ ] 5.2 Rewrite `denialsOf`'s file half to read the record and the account the profile imposes, and
  verify against 1.3 that a root-only file is still denied under the three confining profiles and a
  group-readable one is not
- [ ] 5.3 Verify the refusal and `operator-entry-access-denied` name the unit, the file, the record
  and the imposed account, and that `tests/unit/diagnostics.nix` still crosses every refusal against
  a row
- [ ] 5.4 Verify two entries under one confining profile whose files differ only in ownership and
  mode produce exactly one denial

## 6. Tests

- [ ] 6.1 Add the record scenarios to `tests/unit/{module,vars,plan}.nix`, including the two
  same-key/different-key cases, and verify each fails against the pre-change tree
- [ ] 6.2 Add the row scenarios to `tests/unit/diagnostics.nix`
- [ ] 6.3 Add the denial and directive scenarios to `tests/unit/image.nix` and
  `tests/unit/operator.nix`
- [ ] 6.4 Add the write scenarios to `tests/e2e/test_harness.py` against the recorder: the mode, the
  two-umask case, the interrupted write, the missing account and the restoring re-apply
- [ ] 6.5 Register every new scenario in `tests/unit/coverage.nix`, move this change's spec files to
  `accountable`, and verify the suite reports no unmapped scenario

## 7. On machines, and documents

- [ ] 7.1 In `tests/e2e/shared-postgres/`, deliver the database passwords at an ownership the server
  and the consumers can read, delete the root-unit indirection, and verify each service reads its own
  credential
- [ ] 7.2 Add a machine scenario that widens a delivered value's mode on the machine, re-applies with
  unchanged bytes, and reads the mode back
- [ ] 7.3 Add a machine scenario realising one entry as a confined image reading a group-readable
  generated secret, and verify it builds, attaches and reads the bytes
- [ ] 7.4 Update `docs/authoring.md`, `docs/secrets.md`, `docs/plan.md`, `docs/diagnostics.md` and
  `docs/operator.md`, and verify `nix build .#checks.x86_64-linux.treefmt` passes
- [ ] 7.5 Update `CLAUDE.md`: the denial is about permission rather than secrecy, the two-layer
  split for the two rows, the write order and why owner is set after mode, and remove the note that
  every secret consumer must be root
- [ ] 7.6 Run `nix run .#planner-e2e -- shared-postgres secret-delivery generated-secret` and verify
  no folder regressed
