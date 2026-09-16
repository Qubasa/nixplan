## 1. The dependency on `name-the-machine-a-run-dials`

This change consumes `hostKey` and restates none of that change's work. Do not start section 3 until
the three facts below are in the tree.

- [ ] 1.1 Confirm `hostKey` is the machine registry's field and reaches this change where it is
  needed, and add none of it: `grep -n hostKey lib/resolve.nix lib/plan.nix operator/read.nix` must
  show it read in the third projection of the machine reading beside `reserves`
  (`lib/resolve.nix:617-619`), recorded on the `machine:<name>` plan record with `address` and
  `tags` (`lib/plan.nix:1404-1419`) and therefore outside `machineKey` (`lib/plan.nix:31`, applied
  at `:1342`), and read in `operator/read.nix` with `machineRecordOf` the way the address is
  (`:138-140`). Verify with `nix eval --json '.#debug.failures'` returning `[]` before any edit of
  this change.
- [ ] 1.2 Confirm the guest image carries a static sshd host key and that each folder's
  `deployment/default.nix` is handed its public line as an argument. That edit is
  `name-the-machine-a-run-dials`'s: it re-keys every snapshot cut and needs
  `rookery snapshot gc --all` plus one cold run, and this change must not make it a second time.
  Verify with `grep -n sshHostPublicKey tests/e2e/guest.nix flake-module.nix`.
- [ ] 1.3 Consume that change's python-side reader of the plan's machine record host key rather than
  writing a second one - the recipient is read where `cli/manifest.py:241-258` already reads a
  value's machine address, because a value's machine need run no entry. Verify with
  `grep -n "def machine_host_key" cli/manifest.py` before section 7 writes any seal.
- [ ] 1.4 Take no decision that belongs to another open change: the channel every remote step goes
  through and the options it connects with are `name-the-machine-a-run-dials`'s (contract C4), the
  retire step and what a report says about an entry the build does not name are
  `retire-an-entry-a-build-no-longer-names`'s, and state declaration is `declare-service-state`'s.
  Verify by reading this change's diff for an edit to `known_hosts` handling, `remote.ssh_opts`, or
  any `--retire` path: there must be none.

## 2. Baseline and registration, before `lib/` is touched

- [ ] 2.1 Record the perf baseline before editing anything under `lib/`: run `bash perf/measure.sh`
  (or `~/.claude/outputs/measure-perf.sh worked 0`) and paste the nine counters into the change's
  working notes. This change adds no registry key, no atom, no vocabulary field and no plan field,
  and nothing in `lib/` calls the two new definitions per entry, so the gated counters are expected
  not to move; the recorded baseline is what proves it. The gate is two-sided with a 0.15 margin, so
  a movement either way is a task to fix and never a re-recorded budget.
- [ ] 2.2 Register this change's five delta specs in `excused` in `tests/unit/coverage.nix`, one line
  per file, each reason naming this change in the shape `excuseNamesChange`
  (`tests/unit/coverage.nix:373-378`) matches - "an unimplemented change: no task of
  unseal-a-value-after-a-reboot has been done, ..." - for
  `changes/unseal-a-value-after-a-reboot/specs/planner/secret-delivery/spec.md`,
  `.../specs/delivery/generated-values/spec.md`, `.../specs/operator/deployment-build/spec.md`,
  `.../specs/operator/apply-command/spec.md` and `.../specs/operator/machine-report/spec.md`.
  Verify with `nix build .#checks.x86_64-linux.planner-tests` after 2.4: an unclassified `spec.md`
  fails `testEverySpecificationIsClassified`.
- [ ] 2.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` (`tests/unit/coverage.nix:380-385`) reads this `tasks.md` for a single `- [x]`
  line, and `staleExcuses` (`:387-397`) fails the suite for an excuse whose change has landed, so
  ticking one box while the five paths are excused turns the suite red for a reason that reads like
  a missing test. The paths move to `accountable` and the boxes are ticked in the one edit task 10.4
  makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [ ] 2.4 `git add` every new file of this change before evaluating anything - the flake does not see
  an untracked path and the failure reads as a missing file. That is the five spec files,
  `design.md`, `proposal.md`, `tasks.md`, and every new file a later task creates. Verify with
  `nix eval --json '.#debug.failures'` returning something other than a file-not-found error.

## 3. Two roots with one home, in `lib/util.nix`

- [ ] 3.1 Add `sealedRoot = "/var/lib/planner/sealed"` immediately beside `varsRoot`
  (`lib/util.nix:331-334`) with the two reasons in the comment: a service manager does not clear it
  across a reboot, and it lies outside the root `varsPathsIn` reads. Add `sealedPathOf`, which
  answers a file's sealed path from its runtime path by replacing the root and appending the `age`
  extension, so a sealed path is derived from the value's identity exactly as far as the runtime
  path is. Nothing in `lib/` may call either per entry. Verify with `nix eval --json
  '.#debug.failures'` returning `[]`.
- [ ] 3.2 In `tests/unit/vars.nix`, add `testAPersistentPathIsDerivedFromTheValuesOwnPath` (nix-unit
  layer) for the scenario of that name: the sealed path of a worked value's file is
  `sealedPathOf` of its recorded path, and two evaluations answer one string.
- [ ] 3.3 In `tests/unit/vars.nix`, add `testAPersistentPathIsNotAValuePathToTheScanThatRecognisesOne`
  (nix-unit layer): `util.varsPathsIn` of a string carrying a sealed path answers `[ ]`, and a unit
  record carrying one earns neither `vars-path-off-delivery-set` nor `vars-not-deployed-opened`.
  This is the check that would catch a sealed root placed under `/run/vars`.
- [ ] 3.4 In `tests/unit/vars.nix`, add `testAPlanIsUnchangedByTheDerivationOfAPersistentPath`
  (nix-unit layer): no record of the worked plan carries a sealed path, a recipient or a seal
  marker, and the plan equals the committed golden. The trap this pins is `fileKeyInput`
  (`lib/plan.nix:148`), which would re-key every generated value if the sealed path were a field of
  `fileRecord`.
- [ ] 3.5 In `tests/unit/vars.nix`, add `testARotatedIdentityReKeysNothing` (nix-unit layer): plan a
  deployment twice with two different `hostKey` lines on one machine and require every value entry
  key and every placed entry key on that machine to be equal across the two.

## 4. The build reading, in `operator/read.nix`

- [ ] 4.1 Add the per-machine half of the reading beside the per-entry one: for every machine a
  delivered value reaches, record the value file records delivered there (path, sealed path, owner,
  group, mode), whether the declared `hostKey`'s type can be sealed to, the identity file that type
  implies (`/etc/ssh/ssh_host_ed25519_key` for `ssh-ed25519`, `/etc/ssh/ssh_host_rsa_key` for
  `ssh-rsa`), and the unit files the oneshot must precede. It stays total and raises nothing. Verify
  with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 4.2 Derive the ordering list from `planner.util.varsPathsDeep` of each placed entry's own
  `units` and `configData`, the way `imageReader.hostPaths` is asked of the same records
  (`operator/read.nix:163`), so one rule covers a declared read and an owner's own file. Do not
  restate the read index the command builds (`cli/apply.py:125-178`).
- [ ] 4.3 Add the warning row `operator-machine-host-key-unsealable`, subject `machine:<name>`,
  naming the machine, the type it declared and the two types that can be sealed to, with the
  resolution being to rotate that host key. Produce no row for a machine that declares no host key
  at all: `machine-receives-a-value-unauthenticated` is that fact and the same fact produced twice
  is one row.
- [ ] 4.4 Publish the `machines` table in the manifest, one record per machine a delivered value
  reaches, carrying whether that machine's values are sealed and, where they are, the unsealer's
  artifact path `machines/<name>`. Do not restate the recipient: the plan's machine record carries
  it. Bump the record's `version` to 2.
- [ ] 4.5 In `tests/unit/operator.nix`, add these nix-unit tests, one per scenario of
  `specs/operator/deployment-build/spec.md`, each named after its heading:
  `testAMachineThatReceivesAValueHasAnUnsealer`, `testAMachineThatReceivesNoValueHasNone`,
  `testTwoBuildsOfOneDeploymentProduceOneUnsealer` (two readings of one plan produce equal unsealer
  records, and changing one machine's values leaves the others' records equal - the reading is
  asserted rather than a derivation, because this suite evaluates without `pkgs`),
  `testTheUnitIsOrderedBeforeAnEntryThatReadsAValue`,
  `testNoEntryCanDeriveTheUnsealingUnitsFileName` (over `imageReader.unitFilesOf`: every derivable
  name carries at least two hyphens outside its components and the machine unit's name carries one),
  `testAMachineDeclaresAnIdentityOfATypeTheSealCannotUse`,
  `testAMachineThatDeclaresNoIdentityEarnsNoSecondRow`,
  `testTheRecordNamesTheMachinesAValueReaches` and
  `testADeploymentThatDeliversNothingCarriesTheTableAnyway`. Every one of these is the unit layer
  and none of them has a pytest twin.

## 5. The unsealer, in `operator/default.nix`

- [ ] 5.1 Build one artifact per machine of the reading's per-machine record and put it in the same
  link farm as the entries, at `machines/<name>`. It carries `bin/unseal`, `bin/check` and
  `planner-unseal.service`, and `age` is in its closure so the program arrives with the artifact
  rather than off the machine's `PATH`. Verify by building the `secret-delivery` deployment and
  listing `machines/`.
- [ ] 5.2 `bin/unseal`: for each value file in plan key order, leave a plaintext that is already
  there untouched; otherwise open the sealed copy with the identity file the type implies into a
  temporary created `0600` inside the plaintext's own `0711` parent chain, own it, chmod it to the
  record and move it into place. Print one line per value restored, `nothing to unseal` when none,
  name every seal it could not open, and exit non-zero if any could not be opened while still
  restoring the rest. Every interpolated value is escaped as one word, messages included.
- [ ] 5.3 `bin/check`: per sealed copy, print whether the copy is there and whether it opens, and
  nothing about any byte of it. This is the one question `planner status` asks a machine about its
  seals, so it answers for every value of that machine in one run.
- [ ] 5.4 `planner-unseal.service`: a oneshot running `bin/unseal`, `WantedBy=multi-user.target`,
  `After=local-fs.target`, and `Before=` every unit file the reading's ordering list names. The unit
  orders and does not require, so a machine whose seals do not open still starts its readers and
  they still fail on the file that is not there.
- [ ] 5.5 Build the recipients file the rendered secrets step needs: one store object per machine of
  a delivery set holding that machine's declared host key line, built in `mkGeneration` where the
  secrets reading is already built, and handed to `secrets/backend.nix`'s `render` beside `get`. A
  public key in the store is public information; state that in the comment.

## 6. The rendered deploy step, in `secrets/read.nix` and `secrets/backend.nix`

- [ ] 6.1 Add two file-scope entries to `renderedWords` (`secrets/read.nix:280-324`): the sealed path
  and its parent, both derived from `path` with `derivedFrom` set, so the rows about them exist by
  construction - `secrets-rendered-word-refused` for a word outside `util.wordRule`, and the
  `id = null` account `pathNamesNoDirectory` for a path naming no directory. Read the sealed path
  from `util.sealedPathOf` rather than restating the root.
- [ ] 6.2 Give `render` two more caller arguments beside `get`: the sealing program and a
  machine-keyed set of recipients-file store paths. The recipient is not a rendered word: a public
  key line carries spaces, `util.wordRule` admits none, and the fourteen re-parsed positions of that
  step's remote half forbid widening it.
- [ ] 6.3 Render the sealing half: after the backend's `get` has written the plaintext into the
  step's one temporary, seal it to that machine's recipients file and send the ciphertext with a
  second `ssh` writing the sealed path at `0400 root:root` under a `0700` parent, then the existing
  plaintext `deliver`. Sealed copy first, so an interrupted run never leaves a sealed copy older
  than the plaintext beside it. The ciphertext temporary is removed by the same trap
  (`secrets/backend.nix:78-79`), and a machine the caller names no recipient for keeps today's
  single `deliver`.
- [ ] 6.4 In `tests/unit/secrets.nix`, add `testTheRenderedStepWritesASealedCopyForAMachineThatSeals`
  and `testAMachineTheCallerNamesNoRecipientForIsDeliveredWithoutASeal` (nix-unit layer), each named
  after its scenario heading, asserting the rendered text and that it carries no byte of any value.

## 7. The command, in `cli/`

- [ ] 7.1 `cli/manifest.py`: implement record version 2, read the required `machines` table, and
  refuse a record carrying none the way a record carrying no `entries` table is refused. A
  `ValueFile` gains its sealed path from the record; the recipient is read with the plan-side reader
  of 1.3.
- [ ] 7.2 `cli/flake-module.nix`: name the sealing program in the command's own wrapper, off the
  module's own attributes the way `PLANNER_CLI` and `PLANNER_CLI_SRC` are, so what a run seals with
  is the build's answer and not the caller's `PATH`.
- [ ] 7.3 `cli/apply.py`: before the first value of a machine is written, copy that machine's
  unsealer with the same store-to-store copy an entry's artifact uses and install its unit, for
  exactly the machines the run writes a value to whose record says they seal. The step is announced
  before it is attempted and says whether it changed anything.
- [ ] 7.4 `cli/remote.py` and `cli/apply.py`: seal in the process that read the value source and send
  the ciphertext on a step of its own, before the plaintext step, on the step's input stream. The
  plaintext step, its line, its record reading and its `changed`/`unchanged` answer do not move. The
  sealed copy is written on every apply, because two sealings of one file differ.
- [ ] 7.5 `cli/values.py` or `cli/apply.py`: refuse before the first dial where the record says a
  machine seals and the invocation names no sealing program, naming the program and the machines.
- [ ] 7.6 `cli/report.py`: extend the one per-machine value question to the machine's own `bin/check`
  and print the three new lines - a sealed copy that does not open, a value with no sealed copy, and
  a machine holding no unsealer whose copies were therefore not checked. None of them changes the
  exit status, and none of them reads a byte of a value.
- [ ] 7.7 In `tests/e2e/test_harness.py`, add the pytest tests for the scenarios the recorder can
  answer, each named after its heading:
  `test_a_machine_with_no_sealable_identity_is_delivered_to_as_before`,
  `test_a_run_installs_the_unsealer_of_every_machine_it_seals_a_value_to`,
  `test_a_run_that_writes_no_value_installs_no_unsealer`,
  `test_a_sealed_payload_enters_no_argument_vector` (two payloads of equal length and different
  bytes produce equal vectors, and no element holds a value byte or the recipient),
  `test_a_value_whose_bytes_did_not_move_restarts_nothing` and
  `test_a_machine_that_holds_no_unsealer_is_not_reported_either_way`. In `cli/` add
  `test_a_run_that_must_seal_and_has_no_sealing_program` and
  `test_a_record_carrying_no_table_of_machines`. Every one of these is the pytest layer and none has
  a nix-unit twin.

## 8. The machine layer, in `tests/e2e/secret-delivery/`

- [ ] 8.1 `deployment/machines.nix`: declare `hostKey` for `alpha`, `beta` and `gamma` from the
  argument `name-the-machine-a-run-dials` hands each folder's `deployment/default.nix`, so the line
  is the guest image's own and no key literal sits in a deployment. `gamma` receives no value, which
  is what proves the unsealer follows the delivery set and not the placement.
- [ ] 8.2 Add to the `applied` phase, after
  `test_a_value_delivered_to_one_of_two_machines_is_named_where_it_is_missing` and before the
  `rotated` fixture: `test_a_delivery_writes_a_sealed_copy_beside_the_value`,
  `test_a_sealed_copy_is_readable_by_the_privileged_account_alone` and
  `test_a_machine_that_already_holds_the_unsealer_is_reported_as_unchanged`. Each reads the sealed
  path off the deployment record rather than restating it.
- [ ] 8.3 Add `test_a_machine_holding_a_sealed_copy_it_cannot_open`: replace `beta`'s sealed copy of
  the session token with bytes it cannot open, read the report, then let its own apply repair it.
  Every later apply rewrites the seal, so the damage is self-healing and the phases below are
  unaffected - say so in the test's docstring, because the file order is the order and nothing is
  restored between phases.
- [ ] 8.4 Add `test_a_machine_that_seals_and_holds_no_sealed_copy`, and rewrite the body of
  `test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them` so that it clears
  **both** copies on `beta` rather than relying on a reboot, which no longer loses a value there.
  Move it up beside the other `applied`-phase report tests. Its heading in
  `specs/operator/machine-report/spec.md` and its alias entry in `tests/unit/coverage.nix` stay as
  they are; only the condition it produces changes.
- [ ] 8.5 Add `test_a_copy_the_machine_cannot_open_leaves_the_value_absent_and_names_it`: clear one
  plaintext, replace its sealed copy with bytes that do not open, run the machine's own
  `bin/unseal` on the machine, and observe that it names that value, leaves its path empty and
  restores the others. Run the artifact's own program on the machine rather than on this host, the
  way `tests/e2e/portable-image/` runs an attach script.
- [ ] 8.6 Rewrite the `rebooted` phase's test into
  `test_a_machine_that_rebooted_holds_its_values_again` and
  `test_a_reader_started_after_a_reboot_reads_the_delivered_bytes`: after the reboot and with no
  command run against the machine, every value is back at its own path with the record's ownership
  and mode, and the reader starts and reads the rotated token the phases above wrote. The phase
  stays last, because `/run` is still what a reboot empties, and it leaves the machine holding every
  value with a started reader.
- [ ] 8.7 In `tests/e2e/delivery.py`, add the sealing-tool guard beside `endpoint_refusal`, and
  assert it from `tests/e2e/test_harness.py` as
  `test_the_resolved_tool_seals_to_an_ssh_recipient_and_opens_it_with_the_ssh_identity` and
  `test_a_tool_that_cannot_be_resolved_skips_rather_than_passes`: a round trip through the resolved
  binary with an `ssh-ed25519` pair, a refusal for a type the design does not admit, a failure
  naming `design.md` D1 when the round trip stops working, and a skip naming the reference when the
  tool cannot be resolved.
- [ ] 8.8 Check whether `tests/e2e/secret-delivery/`'s stage needs more disk for the sealed copies
  and the unsealer closure, through `delivery.cluster_stage`'s `disk_gib` and never the shared
  image's `additionalSpace`: growing the image re-keys every other folder's cut and growing one
  stage re-keys only its own. Verify with one cold run of the folder.
- [ ] 8.9 Check the cross-walk by hand before 10.4: every new test of sections 3 to 8 is named the
  exact `snakeName` or `camelName` of its own scenario heading (`tests/unit/coverage.nix:52-53`), so
  no new entry in `aliased` is needed and none may be added - it is one of two escape hatches and
  not a registration point. The three alias entries this change inherits stay untouched:
  `A machine that lost its values` keeps pointing at
  `test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them`, whose body 8.4
  rewrites, and `A machine holding every value` and `A value delivered to one of two machines` keep
  pointing at the tests they point at now, both carried unchanged in the MODIFIED block and neither
  needing an edit.

## 9. Documentation

- [ ] 9.1 `docs/operator.md`: the unsealer install step in the apply's step list, the sealed write
  beside the value write, the three new `status` lines, and the sealing program the wrapper names.
  Say plainly that a machine recovers its own values and that a machine whose host key cannot be
  sealed to does not.
- [ ] 9.2 `docs/cluster.md`: the new phases of `tests/e2e/secret-delivery/` and what each leaves
  behind, since the file order is the order.

## 10. Gates, the fixture, and the one edit

- [ ] 10.1 `fixtures/minimal-typed-edge` is **not** touched and
  `fixtures/minimal-typed-edge/plan/backup.json` is **not** regenerated: no declaration of that
  folder changes, and this change adds no plan field, so the golden plan and
  `plan/diagnostics.txt` are byte-identical. Verify with `nix eval --json .#debug.worked.plan |
  jq -S . | diff - fixtures/minimal-typed-edge/plan/backup.json` printing nothing.
- [ ] 10.2 Run `nix build .#checks.x86_64-linux.planner-perf`. The gate is two-sided with a 0.15
  margin, and this change is expected to move nothing: compare against the counters recorded in 2.1
  and fix a movement rather than re-recording a budget.
- [ ] 10.3 Run `nix eval --json '.#debug.failures'` and require `[]`, then `nix build
  .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`. Build the
  individual check; never `nix flake check` the whole flake.
- [ ] 10.4 In **one** edit, now that every heading of this change's five delta specs has its test in
  the layer sections 3 to 8 name: delete this change's five `excused` entries from
  `tests/unit/coverage.nix`, add the same five paths to `accountable`, and tick every checkbox of
  this file. The three steps are one edit because `changeHasLanded` reads a single `- [x]` as the
  change having landed and `accountable` is unsatisfiable until the tests exist, so any other order
  puts the suite red in between. Verify with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 10.5 Add this change's invariants to `CLAUDE.md`, and name the hand-maintained registration
  points it touches - which are `accountable`/`excused` in `tests/unit/coverage.nix` (10.4) and
  nothing else: no new suite, so `suites` in `tests/default.nix` is untouched; no new top-level file
  or directory, so `classOf` in `tests/unit/layers.nix` is untouched; no new python import root, so
  `programs.mypy.directories` in `treefmt.nix` and `src` in `ruff.toml` are untouched; no directory
  kind, so `directoryKinds` in `lib/module.nix` is untouched; no excluded construct, so
  `lib/excluded.nix` is untouched; and no new top-level directory, so the `README.md` literals are
  untouched. The invariants to write down: under **Purity and totality**, that `sealedRoot` lives
  beside `varsRoot` because `varsPathsIn` reads the second and must not see the first; under **Keys
  and identity**, that a seal, its recipient and its path enter no plan record and no key input, for
  the reason the delivery set is not in a value's key, and that `varsState` stays keyed by the
  value's entry; under **Realisers**, that the unsealer is a per-machine artifact of the deployment
  build realised by no realiser, that its unit name is one hyphen wide and therefore outside the
  namespace an entry can spell, that the sealed copy is `0400` under `0700` while the plaintext keeps
  its record and its `0711` chain, and that the sealed copy is rewritten on every apply because a
  seal is not reproducible; under **The operator's command**, that a machine restores its own values
  before its readers start and that `status` reports a copy that does not open, replacing the
  sentence that says a reboot's recovery is a second apply; and under **Known bugs**, that `age`'s
  ssh support is documented as a convenience feature and is guarded by a round trip rather than by a
  version comparison.
