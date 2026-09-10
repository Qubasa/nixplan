# Tasks

Ordered so that each phase leaves the tree green. The plan gains the fields a safe delivery reads
before the command reads them, the command's channel changes while the plan can already answer for a
mode and an owner, and the machine layer moves last, when there is something for it to observe. Each
scenario of this change's specifications is named here with the layer its test belongs to: a
nix-unit suite under `tests/unit/` for a fact about evaluation, `tests/e2e/test_harness.py` for a
fact about the command that needs no machine, and a folder under `tests/e2e/` for a fact that needs
a booted machine or a real ssh.

## 1. The plan states what a delivery needs

- [ ] 1.1 `lib/module.nix:352-361`: a generated file declaration takes `mode` and `owner` beside
  `secrecy`, with the key list and the `keyRow` allowance extended to all three. `mode` is a
  four-digit string, the vocabulary a configuration file's `mode` already uses; `owner` is the
  privileged user or a reference to a unit of the declaring member. Add the domain rows for both,
  beside `vars-file-secrecy-domain`. Verify by evaluating a module declaring each malformed shape
  and reading the rows, with no other file changed.
- [ ] 1.2 `lib/resolve.nix:552-574` and `lib/plan.nix:89-99`: the file record carries `mode` and
  `owner`, resolved, on every file, whether or not the declaration wrote either, defaulting to the
  mode and the privileged owner the command writes today. An `owner` naming a unit resolves through
  that unit's own `user`; a reference to a unit declaring no `user`, or to a unit of an entry no
  machine of the delivery set runs, is an error row. Verify `nix eval --json .#planner.worked.plan`
  shows both fields on every file of every value entry, and that removing the default leaves no
  record without them.
- [ ] 1.3 `lib/plan.nix:344-390`: the undeployed-value walk gains the readability check. A unit that
  opens a generated file's path and declares a `user` the recorded mode and owner grant nothing is
  an error row naming the entry, the unit, and the file. The comparison is name equality plus the
  group and other digits of the mode, and reads nothing about any machine's accounts. Verify the row
  fires for the combination `image/read.nix:301-318` refuses under a confining profile and that the
  same declaration with the file owned by that unit produces none.
- [ ] 1.4 `lib/resolve.nix:783-840` and `lib/plan.nix:160-174`: an export the planner refuses with
  `export-secret-not-a-reference` records no value. The record still states the export, its secrecy,
  and its readers. Verify a plan built from a module publishing a secret as a value carries the row
  and that a recursive search of the plan for the offending bytes finds none.
- [ ] 1.5 `tests/unit/secrets.nix`, one test per scenario of `specs/planner/plan-artifact/spec.md`:
  `testADeliveredFileRecordsTheModeAndTheOwnerItLandsWith`, `testAFileIsOwnedByTheUnitThatReadsIt`,
  `testAUnitCannotReadTheFileItOpens`, and `testASecretPublishedAsAValueCarriesNoBytesInThePlan`.
  The three scenarios restated from `deliver-secrets-across-machines` keep the tests they already
  have. Verify `nix build .#checks.x86_64-linux.planner-tests` is green and each new test fails when
  its subject is mutated.
- [ ] 1.6 Regenerate `fixtures/minimal-typed-edge/plan/` with `nix eval --json .#planner.worked.plan
  | jq -S .`, and state in the fixture's own prose what the two new fields are for. Verify the
  golden comparison in `tests/unit/plan.nix` passes and that the only difference against the
  previous golden is the two fields.

## 2. A row names types, not values

- [ ] 2.1 `lib/module.nix:655-664`, `lib/resolve.nix:822-830`, and `lib/interface.nix:264-273`: each
  row's evidence states the declared type, the received type, and the size of the value in the terms
  of its own type, and interpolates the type library's message nowhere. The type names come from the
  declaration's `type.name` and from the interpreter, never from parsing the message. Verify a
  deployment whose secret export is mistyped renders a table containing none of the offending bytes,
  and that changing that value to another value of the same type renders an identical table.
- [ ] 2.2 `tests/unit/diagnostics.nix`, one test per scenario of
  `specs/planner/diagnostics/spec.md`: `testATypeMismatchRowNamesTwoTypesAndNoValue`,
  `testASecretPublishedWithTheWrongType`, and `testTwoValuesOfOneWrongTypeProduceOneRowText`. Verify
  the suite is green and that restoring the interpolation fails all three.
- [ ] 2.3 `docs/diagnostics.md:109` and the two rows beside it: the claim that the failing value is
  not recorded now describes the code. Verify the document names each of the three rows and that
  every row identifier it lists is produced by the library.

## 3. The machine registry states an identity

- [ ] 3.1 `lib/resolve.nix:42-48` and `:184-193`: `machineRegistryKeys` gains `hostKeys`, a list of
  the public keys a machine presents, defaulting to the empty list, with a row for a malformed
  shape. It enters neither `machineTargetKeys` nor `targetOf`, because no unit renders from it.
  Verify a registry stating it produces the field and a registry stating none produces an empty list
  rather than an absent key.
- [ ] 3.2 `lib/plan.nix:25` and `:774-788`: the `machine:<name>` entry records `hostKeys`, and
  `machineKey` hashes the machine record without it (D3). Verify that adding, changing, or removing
  a machine's `hostKeys` leaves every key in the plan equal and changes only that machine's own
  entry.
- [ ] 3.3 `tests/unit/plan.nix`, one test per evaluation scenario of
  `specs/operator/machine-identity/spec.md`: `testARegistryStatesAMachinesHostIdentity` and
  `testRotatingAHostIdentityMovesNoKey`. Verify the second fails when `hostKeys` is folded back into
  the hashed record.
- [ ] 3.4 Regenerate the golden plan and record the difference: one field per machine entry, and no
  key moved. Verify `tests/unit/plan.nix` is green and the diff against the phase 1 golden touches
  the machine entries alone.

## 4. The delivery channel and the operator's own store

- [ ] 4.1 `cli/remote.py:30-57`: `Runner` gains an input channel, and `Subprocess` writes it without
  echoing it. A non-zero exit becomes a refusal naming the step, the machine, the exit status, and
  the machine's own error output, and carries neither the argument vector nor the input. Verify a
  step against a machine that refuses the write reports all four facts and no argument vector.
- [ ] 4.2 `cli/remote.py:125-145`: `write_script` stops taking content. The script names the path,
  the mode, and the owner the value entry records, and reads the bytes from its own input. Verify
  the script's text is equal for two different values of one file, and that the file lands with the
  entry's mode and owner rather than with a constant.
- [ ] 4.3 `cli/apply.py:99-126,206-218`: a write passes the bytes as input and the mode and owner
  from the record, and the step line names the value, the file, the machine, and the mode. Verify
  the recorded log of an apply over a deployment with two values of different modes names both
  modes.
- [ ] 4.4 `cli/values.py:78-123`: the source check reads `ValueFile.secrecy`. For a file of a secret
  value the source must hold a regular file the invoking user owns, whose mode grants nothing to
  group or other, under directories satisfying the same; a path leaving the source is refused rather
  than followed. A public file is held to none of it. Verify each refusal fires before any dial and
  names the entry, the file, and what was refused.
- [ ] 4.5 `tests/e2e/test_harness.py`, one test per machine-free scenario of
  `specs/operator/apply-command/spec.md`: `test_a_write_fails_on_a_read_only_path`,
  `test_a_machine_refuses_the_login`, `test_a_value_source_another_user_can_read`,
  `test_a_secret_file_in_the_source_is_group_readable`, `test_a_link_leaves_the_value_source`, and
  `test_the_bytes_of_a_value_never_enter_an_argument_vector`. The recording runner records the
  digest of an input rather than the input. Verify `nix build
  .#checks.x86_64-linux.planner-delivery` is green and that restoring the encoded content to the
  script fails the last test alone.

## 5. Machine identity in the command

- [ ] 5.1 `cli/remote.py:60-85`: the connection options come from the plan and from the invocation.
  `NIX_SSHOPTS` is no longer read for them, the known-hosts file of the run is written from the
  plan's `hostKeys`, and verification is demanded. `--known-hosts` names identities held elsewhere
  and `--accept-new-host-key` accepts an unverified machine, both explicit and both reported (D2).
  Verify a run whose environment disables verification still verifies, and that a machine presenting
  an unstated identity is refused for that machine.
- [ ] 5.2 `cli/apply.py:156-230` and `cli/planner.py:100-136`: an apply, a status, and a rollback
  report the options they connected with as their first line, and an invocation that accepted an
  unverified machine says so. A machine with no stated identity and no such argument is refused
  before the first dial, naming the machine and the field. Verify the refusal reaches no machine,
  including the machines that do state an identity.
- [ ] 5.3 `tests/e2e/test_harness.py`, one test per machine-free scenario of
  `specs/operator/machine-identity/spec.md`: `test_a_machine_states_no_host_identity`,
  `test_an_inherited_option_set_does_not_reach_the_connection`, and
  `test_the_report_names_the_options_the_run_used`. Verify each fails against the command as it
  stands before this phase.

## 6. The image carries what its units name

- [ ] 6.1 `image/read.nix:196-242`: the host paths of generated files come from the generated paths
  the entry's units, configuration files, and resolved reads name, rather than from `entry.vars`
  filtered to the files recorded as a reference. A generated path the entry names that matches no
  value entry of the plan fails the build naming the entry, the unit, and the path. Verify a
  consumer reading another instance's secret gets a mount point and a bind mount, that a public
  delivered file gets one too, and that the unaccounted path fails.
- [ ] 6.2 `image/read.nix:301-318`: the denial names the units that name the file, rather than every
  unit of the entry. The raise follows the row `report-every-refusal-as-a-row` produces under "A
  confinement profile is checked against the entry it confines". Verify an entry with two units, one
  of which opens a root-only file, fails naming that unit alone, and that an entry whose units open
  no such file builds under the same profile.
- [ ] 6.3 `tests/unit/image.nix`, one test per scenario of
  `specs/realiser/portable-service-image/spec.md` this change adds:
  `testAUnitNamesAValueAnotherInstanceOwns`, `testAUnitNamesAPublicDeliveredFile`,
  `testAUnitNamesAGeneratedPathNoValueAccountsFor`, and `testOneUnitOfAnEntryNamesARootOnlyFile`.
  The four restated scenarios keep the tests they have. Verify the suite is green and each new test
  fails against the reader as it stands before 6.1.

## 7. The machine layer

- [ ] 7.1 `tests/e2e/secret-delivery/deployment/default.nix`: state `hostKeys` for the three
  machines where the run can know them, and declare a `mode` and an `owner` on the delivered token
  so the folder exercises a value a unit reads as its own user rather than as the privileged one.
  Verify the deployment builds and the plan records both fields.
- [ ] 7.2 `tests/e2e/secret-delivery/`: a sampler unit on each machine, started before the deliver
  phase and stopped after it, recording each observed process as its command name and the digest of
  its argument vector (D8). Verify the sampler runs during the apply, carries no needle of its own,
  and that its own arguments are constant.
- [ ] 7.3 `tests/e2e/secret-delivery/test_secret_delivery.py`, one test per scenario of
  `specs/delivery/real-cluster/spec.md`:
  `test_no_process_on_either_host_carries_the_delivered_bytes`,
  `test_the_observation_names_a_digest_and_never_the_value`, and
  `test_a_machines_own_log_holds_no_delivered_byte`. Verify each fails against the command as it
  stands before phase 4 and passes after it.
- [ ] 7.4 `tests/e2e/secret-delivery/test_secret_delivery.py`, the scenarios of this change that
  need a real ssh: `test_a_delivered_file_carries_the_mode_the_plan_states`,
  `test_a_machine_answers_with_another_identity`, and
  `test_a_throwaway_guests_accommodation_is_named_on_the_command_line`. The existing assertion on
  the file's mode and owner becomes an assertion against the plan's own record rather than against
  `400` and the login user. Verify `nix run .#planner-e2e secret-delivery` is green and record the
  count against the count before this change.
- [ ] 7.5 `tests/e2e/delivery.py:185-206`: the throwaway guest's accommodation moves out of
  `NIX_SSHOPTS` and into the arguments the harness passes. `LOCKED_URL_PREFIX` and the rest stay as
  they are. Verify no folder's run relies on an inherited option and that the other folders are
  green.

## 8. Documentation and invariants

- [ ] 8.1 `docs/authoring.md` and `docs/README.md`: `mode` and `owner` on a generated file, what an
  owner naming a unit resolves through, and the value-file record's new shape. Verify every path
  each document names resolves and `testAFileNamesAPathThatIsNotThere` passes.
- [ ] 8.2 `docs/operator.md`: the value source's posture, the two identity arguments, the reported
  options line, and what a failed remote step prints. Verify every command in it runs as written.
- [ ] 8.3 `docs/diagnostics.md`: the new rows of phases 1 and 3, and the type-mismatch claim. Verify
  the identifier list matches the library's.
- [ ] 8.4 `CLAUDE.md`: the invariants this change creates - a value's bytes travel on the remote
  command's input and never in an argument vector; a delivered file's mode and owner are the plan's
  and an owner naming a unit resolves through that unit's own `user`; `hostKeys` is a registry field
  outside the hashed machine record; a row states two type names and no value; an image's host paths
  come from the paths its units name rather than from the generators it declares; a confinement
  denial is per unit. Verify the file passes vale under `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 8.5 Register the six spec files of this change under `accountable` in
  `tests/unit/coverage.nix`, with the new files staged so the flake can read them. Verify the
  coverage cross-walk reports an empty difference.

## 9. Verification

- [ ] 9.1 `nix build .#checks.x86_64-linux.planner-tests -L`: green, with the coverage cross-walk
  empty over the six new spec files.
- [ ] 9.2 `nix build .#checks.x86_64-linux.treefmt -L` and `nix fmt`: no change to any file this
  change touched.
- [ ] 9.3 `nix run .#planner-e2e`: green for every folder, with the count recorded here against the
  count before the change.
- [ ] 9.4 Prove the new assertions can fail: restore the encoded content to the remote script and
  confirm the process-table tests fail and nothing else does; fold `hostKeys` into the hashed
  machine record and confirm the rotation test fails alone; return the entry-level denial and
  confirm the per-unit image test fails alone; make the value source group-readable and confirm the
  run refuses before dialling. Revert each and confirm the tree is byte-identical to before the
  mutation.
- [ ] 9.5 Confirm the obsolescence is total: no file under `cli/` encodes a value into a script or a
  argument vector, `values.check` reads `secrecy`, `NIX_SSHOPTS` is read nowhere for a connection
  option, and no realiser derives a generated host path from `entry.vars`.
