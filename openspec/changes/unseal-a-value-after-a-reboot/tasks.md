## 1. Seams with other open changes

This change owns `sealRecipient` and consumes no field of any other open change. What it reads from
`run-an-entry-without-root` is a seam, and the whole cross-machine order is INTEGRATION.md's.

- [x] 1.1 Confirm the change directory and its diff consume nothing from any parked change: no
  machine-identity registry field beyond this change's own, no `known_hosts` handling, no edit of
  `remote.ssh_opts`, no guest-image credential edit. Connection pinning is a separate, currently
  unowned concern. Verify by grepping this change's directory and diff for the parked
  machine-identity change's name and its registry field: both print nothing, before and after the
  implementation.
- [x] 1.2 Read the machine's scope where `run-an-entry-without-root` records it and add none of it:
  the unit is a system oneshot where the recorded scope is `system` or absent and a user unit where
  it is `user`, and until that change lands every machine reads as system scope, so the user-scope
  half is inert rather than blocked. Lingering is that change's preflight fact; this change asks no
  runtime question of its own. Verify by reading this change's diff for an edit to the `scope`
  reading or any preflight code: there must be none.
- [x] 1.3 Take no decision that belongs to another open change: the retire step's place in the walk
  is `retire-an-entry-a-build-no-longer-names`'s, and the per-machine order - preflight, retirement,
  unsealer install, value writes, copy, activation, restarts - is written out once in
  INTEGRATION.md. This change states only its own step. Verify by reading the diff for a `--retire`
  or preflight edit: there must be none.

## 2. Baseline and registration, before `lib/` is touched

- [x] 2.1 Record the perf baseline before editing anything under `lib/`: run `bash perf/measure.sh`
  (or `~/.claude/outputs/measure-perf.sh worked 0`) and paste the nine counters into the change's
  working notes. This change adds one registry key read per machine, one warning row per delivery-set
  machine without a recipient, and two definitions nothing calls per entry, so the gated per-entry
  counters are expected to stay inside the margin; the recorded baseline is what proves it. The gate
  is two-sided with a 0.15 margin, so a movement either way is a task to fix and never a re-recorded
  budget.
- [x] 2.2 Confirm this change's six delta specs are in `excused` in `tests/unit/coverage.nix`, one
  line per file, each reason naming this change in the shape `excuseNamesChange`
  (`tests/unit/coverage.nix:373-378`) matches, for
  `changes/unseal-a-value-after-a-reboot/specs/planner/machine-platform/spec.md`,
  `.../specs/planner/secret-delivery/spec.md`, `.../specs/delivery/generated-values/spec.md`,
  `.../specs/operator/deployment-build/spec.md`, `.../specs/operator/apply-command/spec.md` and
  `.../specs/operator/machine-report/spec.md`. Verify with
  `nix build .#checks.x86_64-linux.planner-tests`: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [x] 2.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` (`tests/unit/coverage.nix:380-385`) reads this `tasks.md` for a single line
  beginning with a ticked checkbox, and `staleExcuses` (`:387-397`) fails the suite for an excuse
  whose change has landed, so ticking one box while the six paths are excused turns the suite red
  for a reason that reads like a missing test. The paths move to `accountable` and the boxes are
  ticked in the one edit task 11.4 makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [x] 2.4 `git add` every new file of this change before evaluating anything - the flake does not see
  an untracked path and the failure reads as a missing file. That is the six spec files,
  `design.md`, `proposal.md`, `tasks.md`, and every new file a later task creates. Verify with
  `nix eval --json '.#debug.failures'` returning something other than a file-not-found error.

## 3. The registry key, in `lib/`

- [x] 3.1 Add `ageRecipientRule` to `lib/util.nix` beside `wordRule` (`lib/util.nix:129-167`): `age1`
  followed by 58 characters of the bech32 alphabet (`qpzry9x8gf2tvdw0s3jn54khce6mua7l`), one word,
  no spaces. State in the comment that the class is a subset of `wordRule`'s, which is what lets the
  rendered step of section 7 carry a recipient as an ordinary word. Verify with `nix eval --json
  '.#debug.failures'` returning `[]`.
- [x] 3.2 Add the `ageRecipient` atom to `lib/atoms.nix`, reading `ageRecipientRule` the way
  `restartPolicy` reads `restartPolicies` (`lib/atoms.nix:17-101`): the grammar has one home and the
  atom and the row both read it.
- [x] 3.3 In `lib/resolve.nix`, read `sealRecipient` in the third projection of the machine reading,
  beside `reserves` (`machineReservations`, `lib/resolve.nix:617-619`): not into `machineRecords`
  (`:576-593`), not into `targetOf` (`:599-613`), into no key input. A line the atom refuses is
  `machine-seal-recipient-malformed`, an error row naming the machine and the registry file, and the
  value is left out of every projection; it sits in no target, so no placement is dropped for it.
- [x] 3.4 In `lib/plan.nix`, record the recipient on the `machine:<name>` record
  (`lib/plan.nix:1404-1419`) as an explicit absence beside `address`: the field is present and null
  where none is declared, kept the way a placed entry's `closure` and `units` are kept through
  `pruned`, because an absent field means the plan does not know. `machineKey` (`lib/plan.nix:31`,
  applied at `:1342`) is untouched. The machine-record field list in `tests/unit/resolution.nix`
  (`:3101-3104`) gains the field.
- [x] 3.5 In `lib/plan.nix`, produce `machine-receives-a-value-unsealed` where the delivery set is
  built: a warning row per delivery-set machine whose reading states no recipient, subject
  `machine:<name>`, naming the values delivered there - one row per machine however many values.
- [x] 3.6 In `tests/unit/platform.nix`, add the nix-unit tests named after the machine-platform delta's
  scenario headings: `testAMachineStatesASealRecipientAndKeysAsItDid` (declare a recipient, require
  the machine key, every placed entry key and every value entry key unchanged, and the machine's
  plan record to carry the line) and `testASealRecipientTheGrammarRefuses` (a malformed line earns
  `machine-seal-recipient-malformed`, appears in no projection, and every entry on the machine is
  still planned).
- [x] 3.7 In `tests/unit/resolution.nix`, add `testAMachineInADeliverySetStatesNoRecipient` and
  `testOneMachineWithTwoValuesEarnsOneRow` for the secret-delivery delta's warning scenarios, each
  named after its heading.

## 4. Two roots with one home, in `lib/util.nix`

- [x] 4.1 Add `sealedRoot = "/var/lib/planner/sealed"` immediately beside `varsRoot`
  (`lib/util.nix:331-334`) with the two reasons in the comment: a service manager does not clear it
  across a reboot, and it lies outside the root `varsPathsIn` reads. Add `sealedPathOf`, which
  answers a file's sealed path from its runtime path by replacing the root and appending the `age`
  extension, so a sealed path is derived from the value's identity exactly as far as the runtime
  path is. Nothing in `lib/` may call either per entry. Verify with `nix eval --json
  '.#debug.failures'` returning `[]`.
- [x] 4.2 In `tests/unit/vars.nix`, add `testAPersistentPathIsDerivedFromTheValuesOwnPath` (nix-unit
  layer) for the scenario of that name: the sealed path of a worked value's file is
  `sealedPathOf` of its recorded path, and two evaluations answer one string.
- [x] 4.3 In `tests/unit/vars.nix`, add `testAPersistentPathIsNotAValuePathToTheScanThatRecognisesOne`
  (nix-unit layer): `util.varsPathsIn` of a string carrying a sealed path answers `[ ]`, and a unit
  record carrying one earns neither `vars-path-off-delivery-set` nor `vars-not-deployed-opened`.
  This is the check that would catch a sealed root placed under `/run/vars`.
- [x] 4.4 In `tests/unit/vars.nix`, add `testAPlanIsUnchangedByTheDerivationOfAPersistentPath`
  (nix-unit layer): no record of the worked plan carries a sealed path or a marker that a copy is
  kept. The trap this pins is `fileKeyInput` (`lib/plan.nix:148`), which would re-key every
  generated value if the sealed path were a field of `fileRecord`.
- [x] 4.5 In `tests/unit/vars.nix`, add `testARotatedIdentityReKeysNothing` (nix-unit layer): plan a
  deployment twice with two different `sealRecipient` lines on one machine and require every value
  entry key and every placed entry key on that machine to be equal across the two.

## 5. The build reading, in `operator/read.nix`

- [x] 5.1 Add the per-machine half of the reading beside the per-entry one: for every machine a
  delivered value reaches whose plan record states a recipient, record the value file records
  delivered there (path, sealed path, owner, group, mode), the machine's scope, and the unit files
  the boot-time unit must precede. The recipient and the scope are read with `machineRecordOf` the
  way the address is (`operator/read.nix:138-140`). It stays total and raises nothing. Verify with
  `nix build .#checks.x86_64-linux.planner-tests`.
- [x] 5.2 Derive the ordering list from `planner.util.varsPathsDeep` of each placed entry's own
  `units` and `configData`, the way `imageReader.hostPaths` is asked of the same records
  (`operator/read.nix:163`), so one rule covers a declared read and an owner's own file. Do not
  restate the read index the command builds (`cli/apply.py:125-178`).
- [x] 5.3 Publish the `machines` table in the manifest, one record per machine a delivered value
  reaches, carrying whether that machine's values are sealed, the machine's scope and, where they
  seal, the unsealer's artifact path `machines/<name>`. Do not restate the recipient: the plan's
  machine record carries it. Bump the record's `version` to 2.
- [x] 5.4 In `tests/unit/operator.nix`, add these nix-unit tests, one per scenario of
  `specs/operator/deployment-build/spec.md`, each named after its heading:
  `testAMachineThatReceivesAValueHasAnUnsealer`, `testAMachineThatReceivesNoValueHasNone`,
  `testTwoBuildsOfOneDeploymentProduceOneUnsealer` (two readings of one plan produce equal unsealer
  records, changing one machine's values leaves the others' records equal, and changing a recipient
  changes no record - the reading is asserted rather than a derivation, because this suite evaluates
  without `pkgs`), `testAUserScopeMachineReceivesAUserUnit`,
  `testTheUnitIsOrderedBeforeAnEntryThatReadsAValue`,
  `testNoEntryCanDeriveTheUnsealingUnitsFileName` (over `imageReader.unitFilesOf`: every derivable
  name carries at least two hyphens outside its components and the machine unit's name carries one),
  `testTheRecordNamesTheMachinesAValueReaches` and
  `testADeploymentThatDeliversNothingCarriesTheTableAnyway`. Every one of these is the unit layer
  and none of them has a pytest twin.

## 6. The unsealer, in `operator/default.nix`

- [x] 6.1 Build one artifact per machine of the reading's per-machine record and put it in the same
  link farm as the entries, at `machines/<name>`. It carries `bin/unseal`, `bin/check` and
  `planner-unseal.service`, and `age` is in its closure so the program arrives with the artifact
  rather than off the machine's `PATH`. The artifact is a function of the value file records and the
  scope and never of the recipient, so a rotation rebuilds nothing. Verify by building the
  `secret-delivery` deployment and listing `machines/`.
- [x] 6.2 `bin/unseal`: for each value file in plan key order, leave a plaintext that is already
  there untouched; otherwise open the sealed copy with `/var/lib/planner/age.key` into a temporary
  created `0600` inside the plaintext's own `0711` parent chain, own it, chmod it to the record and
  move it into place; in user scope the ownership step is a no-op, the account owning what it
  writes. Print one line per value restored, `nothing to unseal` when none, name every seal it could
  not open, and exit non-zero if any could not be opened while still restoring the rest. Every
  interpolated value is escaped as one word, messages included.
- [x] 6.3 `bin/check`: per sealed copy, print whether the copy is there and whether it opens, and
  nothing about any byte of it. This is the one question `planner status` asks a machine about its
  seals, so it answers for every value of that machine in one run.
- [x] 6.4 `planner-unseal.service`: a oneshot running `bin/unseal`, `After=local-fs.target`, and
  `Before=` every unit file the reading's ordering list names. On a system-scope machine it is a
  system unit, `WantedBy=multi-user.target`; on a user-scope one it is a user unit,
  `WantedBy=default.target`, run as the account. The unit orders and does not require, so a machine
  whose seals do not open still starts its readers and they still fail on the file that is not
  there.

## 7. The rendered deploy step, in `secrets/read.nix` and `secrets/backend.nix`

- [x] 7.1 Add two file-scope entries to `renderedWords` (`secrets/read.nix:280-324`): the sealed path
  and its parent, both derived from `path` with `derivedFrom` set, so the rows about them exist by
  construction - `secrets-rendered-word-refused` for a word outside `util.wordRule`, and the
  `id = null` account `pathNamesNoDirectory` for a path naming no directory. Read the sealed path
  from `util.sealedPathOf` rather than restating the root.
- [x] 7.2 Add the recipient as a per-machine rendered word, read off the plan's `machine:<name>`
  record inside the secrets reading, checked by the same table: `ageRecipientRule` is a subset of
  `util.wordRule`'s class, so the word passes by construction, and a machine whose record states no
  recipient contributes no word. There is no recipients file and no store object per machine - that
  was the first draft's workaround for an SSH public key line that carried spaces, deleted with the
  mechanism that needed it.
- [x] 7.3 Give `render` one more caller argument beside `get`: the sealing program, because the plan
  holds no store path to a tool.
- [x] 7.4 Render the sealing half: after the backend's `get` has written the plaintext into the
  step's one temporary, seal it to that machine's recipient word and send the ciphertext with a
  second `ssh` writing the sealed path at `0400` under a `0700` parent, then the existing plaintext
  `deliver`. Sealed copy first, so an interrupted run never leaves a sealed copy older than the
  plaintext beside it. The ciphertext temporary is removed by the same trap
  (`secrets/backend.nix:78-79`), and a machine whose record states no recipient keeps today's
  single `deliver`.
- [x] 7.5 In `tests/unit/secrets.nix`, add `testTheRenderedStepWritesASealedCopyForAMachineThatSeals`
  and `testTheRenderedStepForAMachineWithoutARecipientIsUnchanged` (nix-unit layer), each named
  after its scenario heading, asserting the rendered text and that it carries no byte of any value.

## 8. The command, in `cli/`

- [x] 8.1 `cli/manifest.py`: implement record version 2, read the required `machines` table, and
  refuse a record carrying none the way a record carrying no `entries` table is refused. A
  `ValueFile` gains its sealed path from the record; the recipient is read off the plan's
  `machine:<name>` record with a reader of this change's own, beside the one that reads a value's
  machine address (`cli/manifest.py:241-258`), because a value's machine need run no entry.
- [x] 8.2 `cli/flake-module.nix`: name the sealing program in the command's own wrapper, off the
  module's own attributes the way `PLANNER_CLI` and `PLANNER_CLI_SRC` are, so what a run seals with
  is the build's answer and not the caller's `PATH`.
- [x] 8.3 `cli/apply.py`: before the first value of a machine is written, copy that machine's
  unsealer with the same store-to-store copy an entry's artifact uses and install its unit into the
  manager the machine's scope names - the system manager, or the account's own for a user-scope
  machine - for exactly the machines the run writes a value to whose record says they seal. The
  step is announced before it is attempted and says whether it changed anything.
- [x] 8.4 `cli/remote.py` and `cli/apply.py`: seal in the process that read the value source and send
  the ciphertext on a step of its own, before the plaintext step, on the step's input stream. The
  recipient is one public word off the plan's machine record and may appear in the step's argument
  vector; no byte of a value, sealed or plain, ever does. The plaintext step, its line, its record
  reading and its `changed`/`unchanged` answer do not move. The sealed copy is written on every
  apply, because two sealings of one file differ.
- [x] 8.5 `cli/values.py` or `cli/apply.py`: refuse before the first dial where the record says a
  machine seals and the invocation names no sealing program, naming the program and the machines.
- [x] 8.6 `cli/report.py`: extend the one per-machine value question to the machine's own `bin/check`
  and print the three new lines - a sealed copy that does not open, a value with no sealed copy, and
  a machine holding no unsealer whose copies were therefore not checked. None of them changes the
  exit status, and none of them reads a byte of a value.
- [x] 8.7 In `tests/e2e/test_harness.py`, add the pytest tests for the scenarios the recorder can
  answer, each named after its heading:
  `test_a_machine_that_states_no_recipient_is_delivered_to_as_before`,
  `test_a_run_installs_the_unsealer_of_every_machine_it_seals_a_value_to`,
  `test_a_run_that_writes_no_value_installs_no_unsealer`,
  `test_a_sealed_payload_enters_no_argument_vector` (two payloads of equal length and different
  bytes produce equal vectors, and no element holds a value byte),
  `test_a_value_whose_bytes_did_not_move_restarts_nothing` and
  `test_a_machine_that_holds_no_unsealer_is_not_reported_either_way`. In `cli/` add
  `test_a_run_that_must_seal_and_has_no_sealing_program` and
  `test_a_record_carrying_no_table_of_machines`. Every one of these is the pytest layer and none has
  a nix-unit twin.

## 9. The machine layer, in `tests/e2e/secret-delivery/`

- [x] 9.1 Generate the throwaway identity once, at authoring time, and commit both halves: the
  private half as `tests/e2e/secret-delivery/throwaway-age-identity.txt` with a comment naming it a
  throwaway that opens nothing but this folder's test tokens on an offline guest - the precedent
  being the guest image's snakeoil login key (`tests/e2e/guest.nix:67-70`, on the record as "NOT a
  security issue") - and the public line as the `sealRecipient` literal in
  `deployment/machines.nix` for `alpha`, `beta` and `gamma`. The line is one alphanumeric word, so
  the no-host-path scan of `tests/unit/layers.nix` is untouched. `gamma` receives no value, which is
  what proves the unsealer follows the delivery set and not the placement.
- [x] 9.2 Add the folder's first phase: provision each machine the way an operator would,
  `install -d -m 0700` and the identity file at `/var/lib/planner/age.key` at `0400`, from the
  committed private half. A phase and **never** a snapshot preparation - a preparation body runs no
  program and does not run on a cache hit, so the evidence would be a replay. No guest image edit
  and no `rookery snapshot gc` is needed: the cut does not move.
- [x] 9.3 Add to the `applied` phase, after
  `test_a_value_delivered_to_one_of_two_machines_is_named_where_it_is_missing` and before the
  `rotated` fixture: `test_a_delivery_writes_a_sealed_copy_beside_the_value`,
  `test_a_sealed_copy_is_readable_by_the_unsealing_account_alone` and
  `test_a_machine_that_already_holds_the_unsealer_is_reported_as_unchanged`. Each reads the sealed
  path off the deployment record rather than restating it.
- [x] 9.4 Add `test_a_machine_holding_a_sealed_copy_it_cannot_open`: replace `beta`'s sealed copy of
  the session token with bytes it cannot open, read the report, then let its own apply repair it.
  Every later apply rewrites the seal, so the damage is self-healing and the phases below are
  unaffected - say so in the test's docstring, because the file order is the order and nothing is
  restored between phases.
- [x] 9.5 Add `test_a_machine_that_seals_and_holds_no_sealed_copy`, and rewrite the body of
  `test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them` so that it clears
  **both** copies on `beta` rather than relying on a reboot, which no longer loses a value there.
  Move it up beside the other `applied`-phase report tests. Its heading in
  `specs/operator/machine-report/spec.md` and its alias entry in `tests/unit/coverage.nix` stay as
  they are; only the condition it produces changes.
- [x] 9.6 Add `test_a_copy_the_machine_cannot_open_leaves_the_value_absent_and_names_it`: clear one
  plaintext, replace its sealed copy with bytes that do not open, run the machine's own
  `bin/unseal` on the machine, and observe that it names that value, leaves its path empty and
  restores the others. Run the artifact's own program on the machine rather than on this host, the
  way `tests/e2e/portable-image/` runs an attach script.
- [x] 9.7 Rewrite the `rebooted` phase's test into
  `test_a_machine_that_rebooted_holds_its_values_again` and
  `test_a_reader_started_after_a_reboot_reads_the_delivered_bytes`: after the reboot and with no
  command run against the machine, every value is back at its own path with the record's ownership
  and mode, and the reader starts and reads the rotated token the phases above wrote. The phase
  stays last, because `/run` is still what a reboot empties, and it leaves the machine holding every
  value with a started reader.
- [x] 9.8 In `tests/e2e/delivery.py`, add the sealing-tool guard beside `endpoint_refusal`, and
  assert it from `tests/e2e/test_harness.py` as
  `test_the_resolved_tool_round_trips_a_native_recipient` and
  `test_a_tool_that_cannot_be_resolved_skips_rather_than_passes`: mint a throwaway pair with the
  resolved `age-keygen`, seal a known string to the printed recipient, open it with the identity
  file, compare, with a failure naming `design.md` D1 when the round trip stops working and a skip
  naming the reference when the tool cannot be resolved.
- [x] 9.9 Check whether `tests/e2e/secret-delivery/`'s stage needs more disk for the sealed copies
  and the unsealer closure, through `delivery.cluster_stage`'s `disk_gib` and never the shared
  image's `additionalSpace`: growing the image re-keys every other folder's cut and growing one
  stage re-keys only its own. Verify with one cold run of the folder.
- [x] 9.10 Check the cross-walk by hand before 11.4: every new test of sections 3 to 9 is named the
  exact `snakeName` or `camelName` of its own scenario heading (`tests/unit/coverage.nix:52-53`), so
  no new entry in `aliased` is needed and none may be added - it is one of two escape hatches and
  not a registration point. The three alias entries this change inherits stay untouched:
  `A machine that lost its values` keeps pointing at
  `test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them`, whose body 9.5
  rewrites, and `A machine holding every value` and `A value delivered to one of two machines` keep
  pointing at the tests they point at now, both carried unchanged in the MODIFIED block and neither
  needing an edit.

## 10. Documentation

- [x] 10.1 `docs/operator.md`: the unsealer install step in the apply's step list, the sealed write
  beside the value write, the three new `status` lines, the sealing program the wrapper names, and
  the provision-time one-liner - `install -d -m 0700` of the parent, `age-keygen -o
  /var/lib/planner/age.key`, paste the printed line into the registry as `sealRecipient` - run as
  root on a system-scope machine and as the account on a user-scope one. Say plainly that a machine
  recovers its own values and that a machine stating no recipient does not.
- [x] 10.2 `docs/cluster.md`: the provisioning phase and the new phases of
  `tests/e2e/secret-delivery/`, what each leaves behind, since the file order is the order, and the
  committed throwaway identity beside the snakeoil paragraph it echoes.

## 11. Gates, the fixture, and the one edit

- [x] 11.1 Regenerate the golden fixture: `fixtures/minimal-typed-edge`'s declarations do not
  change, but its machine records gain the explicit `sealRecipient` absence and its delivery-set
  machines earn `machine-receives-a-value-unsealed`, so `plan/backup.json` is regenerated with
  `nix eval --json .#debug.worked.plan | jq -S .` and `plan/diagnostics.txt` with
  `nix eval --raw .#debug.rendered`, and both are committed. Verify with the two suites that compare
  them byte for byte going green.
- [x] 11.2 Run `nix build .#checks.x86_64-linux.planner-perf`. The gate is two-sided with a 0.15
  margin: compare against the counters recorded in 2.1 and fix a movement rather than re-recording a
  budget.
- [x] 11.3 Run `nix eval --json '.#debug.failures'` and require `[]`, then `nix build
  .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`. Build the
  individual check; never `nix flake check` the whole flake.
- [x] 11.4 In **one** edit, now that every heading of this change's six delta specs has its test in
  the layer sections 3 to 9 name: delete this change's six `excused` entries from
  `tests/unit/coverage.nix`, add the same six paths to `accountable`, and tick every checkbox of
  this file. The three steps are one edit because `changeHasLanded` reads a single ticked checkbox
  at the start of a line as the change having landed and `accountable` is unsatisfiable until the
  tests exist, so any other order puts the suite red in between. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [x] 11.5 Add this change's invariants to `CLAUDE.md`, and name the hand-maintained registration
  points it touches - which are `accountable`/`excused` in `tests/unit/coverage.nix` (11.4) and
  nothing else: no new suite, so `suites` in `tests/default.nix` is untouched; no new top-level file
  or directory, so `classOf` in `tests/unit/layers.nix` is untouched; no new python import root, so
  `programs.mypy.directories` in `treefmt.nix` and `src` in `ruff.toml` are untouched; no directory
  kind, so `directoryKinds` in `lib/module.nix` is untouched; no excluded construct, so
  `lib/excluded.nix` is untouched; and no new top-level directory, so the `README.md` literals are
  untouched. The invariants to write down: under **Purity and totality**, that `sealedRoot` lives
  beside `varsRoot` because `varsPathsIn` reads the second and must not see the first; under **Keys
  and identity**, that `sealRecipient` is read in the third projection beside `reserves` and enters
  no key, that a seal and its path enter no plan record and no key input for the reason the delivery
  set is not in a value's key, and that `varsState` stays keyed by the value's entry; under
  **Realisers**, that the unsealer is a per-machine artifact of the deployment build realised by no
  realiser, that its unit name is one hyphen wide and therefore outside the namespace an entry can
  spell, that the sealed copy is `0400` under `0700` while the plaintext keeps its record and its
  `0711` chain, and that the sealed copy is rewritten on every apply because a seal is not
  reproducible; under **The operator's command**, that a machine restores its own values before its
  readers start and that `status` reports a copy that does not open, replacing the sentence that
  says a reboot's recovery is a second apply; and under **End-to-end layer**, that the throwaway age
  identity is committed on the snakeoil precedent and installed by a phase, never a preparation.
