## 1. Record the four failures

- [ ] 1.1 List this change's four spec files under `excused` in `tests/unit/coverage.nix` with the
  reason the tree uses for an unimplemented change, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unclassified specification
- [ ] 1.2 On a `tests/e2e/portable-image/` machine, apply, edit the host file the recipe reads,
  rebuild, apply again, and record that the machine still holds the old bytes and that `status` says
  `current` - the failure this change fixes, measured
- [ ] 1.3 Record what happens when the `changed` build of that folder is applied over the attached
  one: the step printed, the images the machine then holds, and the units' state
- [ ] 1.4 On a `tests/e2e/secret-delivery/` machine, rewrite the value with different bytes, apply,
  and record that the reading unit's main process did not move
- [ ] 1.5 Reboot a machine holding a delivered value and record what `status` prints

## 2. The script becomes the whole decision

- [ ] 2.1 Make `assemble` compare the staged temporary against the existing file and install only
  when they differ, reporting the path when it did, and verify the mode guarantees still hold under
  two umasks and under an interrupted run
- [ ] 2.2 Add the replacement step: read the entry's image from the service manager, and where it is
  neither empty nor this artifact's, stop the units and detach that image; verify against 1.3 that
  the machine then holds exactly one image for the entry
- [ ] 2.3 Make the attach conditional on the image not already being attached, and verify running the
  script twice leaves the units' main processes unchanged
- [ ] 2.4 Add the reload step after the units are started: reload each unit named by a configuration
  file whose bytes changed, reload where the unit declared a reload command and restart otherwise,
  and never start a stopped unit
- [ ] 2.5 Make the script report one line per step performed and a line saying nothing changed when
  nothing did, and verify the output is stable enough to assert against
- [ ] 2.6 Verify the not-computed refusal and the reference checks still happen before anything is
  assembled

## 3. The command stops skipping

- [ ] 3.1 Delete `holds_attached` and the `attached … already` branch from `cli/apply.py`, and verify
  no caller outside it referenced either
- [ ] 3.2 Fold the script's reported lines into the step report, and verify
  `tests/e2e/portable-image/`'s step-log assertions are updated to the new lines rather than deleted
- [ ] 3.3 Verify against 1.2 that an edited configuration file now reaches the machine on the next
  apply, and against 1.3 that a changed build replaces the attached one

## 4. A changed value and its readers

- [ ] 4.1 Make the value write compare the bytes on the machine by hash before writing and report
  `changed` or `unchanged`, and verify no report line and no argv carries the bytes or the hash of a
  secret into a printed step
- [ ] 4.2 Derive the readers of each changed value from the resolved reads `cli/order.py`'s edges are
  built from, and restart those entries' units with the service manager's restart-if-running; verify
  a stopped unit is not started
- [ ] 4.3 Report each restart as its own step naming the entry, the machine and the value, and verify
  an apply with unchanged values contains no such step
- [ ] 4.4 Verify against 1.4 that a rotated value now replaces the reading process, and that a value
  read on two machines restarts both

## 5. The report

- [ ] 5.1 Ask each machine which of the values delivered to it exist, and print one line per missing
  value naming the value and the machine; verify against 1.5 that a rebooted machine is diagnosed and
  that the exit status is zero
- [ ] 5.2 Verify no line reports anything about the bytes of a value the machine holds
- [ ] 5.3 Compare the bytes the machine holds at each configuration path against what the build would
  assemble, and print a word other than `current` when they differ; verify against 1.2 that the
  pre-fix state is reported as not current

## 6. Tests

- [ ] 6.1 Add the script scenarios to `tests/unit/image.nix`: the two-run no-op, the
  configuration-only change, the replacement, the three reload cases
- [ ] 6.2 Add the command scenarios to `tests/e2e/test_harness.py` against the recorder: no entry
  skipped, the value write's two answers, the restart of readers, the stopped-unit case, the
  two-machine case
- [ ] 6.3 Add the report scenarios to `tests/e2e/test_harness.py` and `tests/unit/operator.nix`
- [ ] 6.4 Register every new scenario in `tests/unit/coverage.nix`, move this change's spec files to
  `accountable`, and verify the suite reports no unmapped scenario

## 7. On machines, and documents

- [ ] 7.1 In `tests/e2e/portable-image/`, add the phases the folder was missing: apply the `changed`
  build over the attached one and read back one image and the new unit script; edit the host file the
  recipe reads, apply, and read back the new bytes and the reload
- [ ] 7.2 In `tests/e2e/secret-delivery/`, add a rotation phase: rewrite the value, apply, and read
  back a new main process on the reader and the restart step in the log
- [ ] 7.3 In `tests/e2e/wired-pair/`, add a reboot phase that reports the missing values and an apply
  that restores them, and verify the units are working again afterwards
- [ ] 7.4 Update `docs/operator.md` (the new steps and report lines), `docs/plan.md` (`reload` is now
  acted on, so `:265` is true), and verify `nix build .#checks.x86_64-linux.treefmt` passes
- [ ] 7.5 Update `CLAUDE.md`: the script owns the machine's state for an entry, the replacement is
  read from `RootImage`, a changed value restarts its readers coarsely and why, values stay on tmpfs
  and the report is how a reboot is diagnosed; remove the note that an attached image is never
  re-attached
- [ ] 7.6 Run the whole end-to-end layer and verify every folder passes: `nix run .#planner-e2e`
