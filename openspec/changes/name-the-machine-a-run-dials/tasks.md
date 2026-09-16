# Tasks

Ordered so that each phase leaves the tree green: the grammar, then the registry reading, then the
plan's record and the golden, then the warning, then the deployment record, then the command, then
the machine layer, then the documents. The command cannot be written before the plan carries the
field, and no folder can pin before the guest image has a known host key.

Every scenario of this change's three delta specs is named below with the one layer its test belongs
to. A nix-unit suite under `tests/unit/` for a fact about evaluation, `tests/e2e/test_harness.py`
for a fact about the command that needs no machine - it hands the command a recorder, so an argv and
a printed line are assertable with nothing booted - and a folder under `tests/e2e/` for a fact that
needs a real sshd. No heading appears in two layers.

**Do not tick a box until task 9.1.** `changeHasLanded` (`tests/unit/coverage.nix:380-385`) reads
this file and treats a single `- [x]` line as the change having landed, and `staleExcuses`
(`:387-397`) then fails the suite for an `excused` entry whose change has landed. Ticking as you go
therefore turns the excuse registered in 1.1 into a red suite whose message reads like a missing
test and is not. Task 9.1 deletes the excuses, adds the paths to `accountable` and ticks every box
in one commit.

## 1. Registration and the baseline

- [ ] 1.1 `tests/unit/coverage.nix`: register this change's three delta spec files in `excused`,
  each with a reason naming this change, in the shape lines 87-98 already use for
  `declare-service-state` and `deliver-a-secret-without-exposing-it`:
  `changes/name-the-machine-a-run-dials/specs/planner/machine-platform/spec.md`,
  `changes/name-the-machine-a-run-dials/specs/planner/secret-delivery/spec.md` and
  `changes/name-the-machine-a-run-dials/specs/operator/apply-command/spec.md`. `git add` the three
  spec files first: the flake does not see an untracked path, and the coverage cross-walk then
  reports the spec it cannot read rather than the file that was not staged. Verify
  `nix build .#checks.x86_64-linux.planner-tests` is green with the three files present and no box
  of this file ticked.
- [ ] 1.2 Record the perf baseline before touching `lib/`: `bash perf/measure.sh`, or
  `~/.claude/outputs/measure-perf.sh worked 0`, and paste the nine figures into this task. The gate
  is two-sided with a 0.15 margin, so a refactor that costs evaluation and one that cheapens it both
  fail, and a new registry key plus a new atom cost thunks. Verify the figures are recorded here
  before any file under `lib/` is edited.

## 2. The grammar and the atom

- [ ] 2.1 `lib/util.nix`, beside `keySeparators`, `wordRule` and `envNameRule`: add
  `sshPublicKeyRule` as the composition of an algorithm name, a padded base64 blob whose length is
  a multiple of four, and an optional comment of no control character, with `sshPublicKeyAdmits`
  for the row text and `unpinnable` as the predicate (design D3 carries the exact expressions).
  One home, no second copy: the atom and the row below both read these. Verify by evaluating
  `unpinnable` against the two nixpkgs snakeoil lines (both admitted), a line carrying `\n`
  anywhere, a `@revoked` marker, a `known_hosts` line with a host field in front, a blob of length
  not a multiple of four, and a trailing space (all refused).
- [ ] 2.2 `lib/atoms.nix`: add `sshPublicKey = korora.typedef "sshPublicKey" (v: !util.unpinnable v)`
  and take `util` as an argument; `lib/default.nix`: pass it. `korora.verify` is the only entry
  point, never `check`. Verify `nix eval --json '.#debug.failures'` is `[]` and
  `nix build .#checks.x86_64-linux.planner-tests` is green, which is what proves nothing else
  constructs `atoms` by hand.
- [ ] 2.3 `lib/resolve.nix`: add `sshPublicKey` to `shapes` (`:87-124`) as
  `v: atoms.sshPublicKey.verify v == null`. Verify a machine stating a line of the wrong kind is a
  row and not a type error.

## 3. The registry reading and the projection

- [ ] 3.1 `lib/resolve.nix:52-59`: `machineRegistryKeys` gains `hostKey`, so a registry stating it
  no longer earns `declaration-unknown-key`. Verify the row list of a registry stating the field is
  empty, and that a misspelling of it still earns the unknown-key row.
- [ ] 3.2 `lib/resolve.nix:459-466`: read `hostKey` in `machineFields` with `shapes.text`, and
  project it in the third projection beside `machineReservations` (`:617-619`) - not in
  `machineRecords` (`:576-593`), not in `targetOf` (`:599-613`), and in no key input (design D2).
  The projection records the line where the grammar admits it and `null` where it does not or where
  nothing was stated. Verify `resolved.machines` is byte-identical to what it was for a registry
  stating the field, which is what keeps `machineKey` (`lib/plan.nix:31`, applied `:1342`) off it.
- [ ] 3.3 `lib/resolve.nix`: the row `machine-host-key-malformed`, an error, naming the machine, the
  field and `util.sshPublicKeyAdmits`, produced where the stated value is neither absent nor
  admitted. It reads the grammar rather than restating it, the way `unit-env-name-malformed` does.
  Verify the refused line is in no projection and that every other machine of the registry and every
  entry placed on this one is still read.
- [ ] 3.4 `tests/unit/platform.nix`, beside `testAFullyDeclaredMachine` (`:79`): two tests,
  `testAMachineStatesTheKeyItsHostPresents` and `testAMachineStatesNoHostKey`, for the two scenarios
  of those names in `specs/planner/machine-platform/spec.md`. Verify each fails against the reading
  as it stands before 3.2.
- [ ] 3.5 `tests/unit/resolution.nix`: `testAHostKeyCarryingALineBreak` and
  `testAHostKeyOutsideTheGrammarAnIdentityLineCarries`, for the two scenarios of those names. The
  second covers a value of another kind and a line the grammar refuses in each of its three
  positions. Verify both fail against the reading as it stands before 3.3.
- [ ] 3.6 Confirm the seven scenarios of the MODIFIED requirement `A machine declares the system it
  runs and the service manager that runs its units` keep the tests they already have and that none
  of them asserted `hostKey` was an unknown key. Verify by name: the suites still hold
  `testAFullyDeclaredMachine` and its six siblings, unrenamed, and
  `nix build .#checks.x86_64-linux.planner-tests` is green.

## 4. The plan's machine record

- [ ] 4.1 `lib/plan.nix:1404-1419`: the `machine:<name>` record carries `hostKey` in the
  unconditional group with `address` and `tags`, `null` where none was stated or the statement was
  refused, never pruned - a reader must not be able to mistake the field for a plan that does not
  carry it, which is why the deployment record carries `address` as an explicit absence. Verify
  `nix eval --json .#debug.worked.plan | jq '."machine:alpha"'` shows the key on every machine
  record and that `key` is unchanged.
- [ ] 4.2 `tests/unit/plan.nix`, beside `testAMachineThatReservesAPortKeysAsItDid` (`:3262`):
  `testRotatingAHostKeyMovesNoKeyOfThePlan`, for the scenario of that name - adding, changing and
  removing the field leaves every key of the plan equal and the machine's own record the only record
  whose content differs. Verify it fails when the field is folded into `machineRecords`.
- [ ] 4.3 Regenerate `fixtures/minimal-typed-edge/plan/backup.json` with
  `nix eval --json .#debug.worked.plan | jq -S .`. **The fixture's own declarations do not change**;
  the golden moves anyway, because every machine record gains one always-present key. Verify the diff
  against the previous golden is exactly `"hostKey": null` on the four machine records
  (`machine:alpha`, `machine:beta`, `machine:gamma`, `machine:vault`) and nothing else, no `key`
  included, and that `fixtures/minimal-typed-edge/plan/diagnostics.txt` is unchanged.

## 5. The warning row

- [ ] 5.1 `lib/plan.nix`, in the walk that computes `delivery` (`:1314-1320`):
  `machine-receives-a-value-unauthenticated`, a warning, one row per machine over the union of the
  delivery sets grouped by machine, subject `machine:<name>`, naming the machine and the values it
  receives. One grouped pass over lists the walk already built; no new index and nothing per placed
  entry. Verify the deployment stays applicable and that the delivery sets are unchanged by the row.
- [ ] 5.2 `tests/unit/vars.nix`, beside `testTheOwnerReceivesItsOwnValue` (`:321`): five tests, one
  per scenario of `specs/planner/secret-delivery/spec.md` - `testAMachineInADeliverySetStatesNoHostKey`,
  `testOneMachineReceivesTwoValues`, `testEveryMachineOfADeliverySetStatesAHostKey`,
  `testAMachineThatReceivesNoValueStatesNoHostKey` and `testAValueNobodyReceivesReportsNobody`.
  Verify each fails against the walk as it stands before 5.1, and that the second fails if the row
  is produced per value rather than per machine.
- [ ] 5.3 Verify the two rows one mistaken line earns are both produced and are not deduplicated
  into one: a machine whose stated line the grammar refused and which receives a value carries both
  `machine-host-key-malformed` and `machine-receives-a-value-unauthenticated`, the way `address = 22`
  carries both the malformed declaration and the incomplete target. Assert it in the test of 3.5
  rather than as a sixth test in `vars.nix`.

## 6. The deployment record

- [ ] 6.1 `operator/read.nix`: read `hostKey` off the plan's machine record with `machineRecordOf`
  the way the address is read (`:138-140`), the empty string normalising to an absence, and publish
  it per entry in the manifest beside `address` (`:608-621`). No row about it here: the planner holds
  that fact one stratum up. Verify `tests/unit/operator.nix` sees the field on an entry of a machine
  that states one and an absence on one that does not.
- [ ] 6.2 `cli/manifest.py`: `Entry` gains the field, read as optional the way `address` is - `null`
  and an absent key are one reading and only the empty string is refused - and a `machine_host_key`
  function beside `machine_address` (`:241-257`) reads it off the plan's own `machine:<name>` record
  for a value's machine, which need run no entry at all. `unseal-a-value-after-a-reboot` consumes
  that function; do not write a second reader. Verify `mypy --strict` over `cli/` passes and that a
  record carrying no field reads as a machine that states none.

## 7. The command's channel and its report

- [ ] 7.1 `cli/remote.py:262-296`: `channel` stops returning one option string for a whole run and
  returns a value that answers, per machine, the option string and the `nix copy` environment. For a
  machine that states a `hostKey` the string is the caller's own `NIX_SSHOPTS`, then `-i`, then
  `-o UserKnownHostsFile=<the run's file> -o GlobalKnownHostsFile=/dev/null -o
  StrictHostKeyChecking=yes -o CheckHostIP=no`, then `BOUNDS`; for a machine that states none it is
  byte-identical to today's. Verify the composed string for a machine stating none is equal to the
  string the current code composes for the same inputs.
- [ ] 7.2 `cli/remote.py`: write the run's known-hosts file once, before the first dial, under a
  directory the run owns, one `<address> <hostKey>` entry per machine that states one, and remove it
  when the run ends. It is written in both modes, because `--dry-run` replaces the channel every
  remote step goes through and nothing else (`cli/apply.py:182-207`). Verify the file holds one line
  per pinned machine and no line for a machine stating none.
- [ ] 7.3 `cli/remote.py`: read the caller's `NIX_SSHOPTS` for the two option names that decide host
  verification, in every `-o` spelling (`-o Name=value`, `-oName=value`), and refuse naming the
  machine and the option where the run would dial a machine that states a `hostKey`. A configuration
  file named with `-F` is deliberately out of scope and the refusal says nothing about it (design
  D7). Verify a run whose machines all state none makes no refusal, and that the refusal reaches no
  machine, including the machines that do state one.
- [ ] 7.4 `cli/apply.py:254,266-268` and `cli/report.py:116,250`: every step takes its options and
  its environment for its own machine, the `nix copy` of an artifact included, so one machine is one
  option set for the whole run. Verify the recorded argv of a write, a copy and an activation against
  one machine carry the same options.
- [ ] 7.5 `cli/apply.py` and `cli/report.py`: report one line per machine the run will contact,
  before the first step line, naming the machine, the address and either the algorithm and the
  `SHA256:` fingerprint of the stated key or that the machine states none and the caller's own
  options decide. The fingerprint is the digest of the decoded blob, which the grammar of 2.1
  guarantees decodes. Verify the lines of a real run and of a dry run of one deployment are equal.
- [ ] 7.6 `tests/e2e/test_harness.py`: seven tests, one per machine-free scenario of
  `specs/operator/apply-command/spec.md` -
  `test_a_machine_that_states_a_host_key_is_dialled_pinned_to_it`,
  `test_every_step_against_one_machine_uses_one_option_set`,
  `test_an_inherited_option_that_would_disable_the_pinning_is_refused`,
  `test_an_inherited_option_reaches_a_run_whose_machines_state_no_identity`,
  `test_a_machine_that_states_no_host_key_is_dialled_as_before`,
  `test_the_run_reports_what_it_connected_with_before_its_first_step` and
  `test_a_dry_run_reports_the_connection_its_real_run_would_make`. Verify
  `nix build .#checks.x86_64-linux.planner-delivery` is green and that each fails against the
  command as it stands before 7.1.
- [ ] 7.7 `tests/e2e/test_harness.py:838-854`: `test_a_throwaway_guest_is_reached_with_no_host_config`
  asserts that `command_env` carries `UserKnownHostsFile=/dev/null`, which is the behaviour 8.3
  removes. Move the two known-hosts assertions to the harness's own helper and assert in the
  `command_env` test that neither of the two option names is present, which is now a contract: the
  harness must not hand the operator's command an option the command would refuse. Verify the moved
  assertions still hold for the harness's own options.
- [ ] 7.8 Confirm the MODIFIED requirements `The command refuses before it dials` and `What the
  command does on a machine` keep every scenario test they have, `An unreachable machine is refused
  without a prompt` included: the caller still wins for the three bounds on silence, and only the
  two verification options are refused. Verify by name that no existing test in
  `tests/e2e/test_harness.py` was renamed and that the suite is green.

## 8. The machine layer

- [ ] 8.1 `tests/e2e/guest.nix`: install `sshKeys.snakeOilEd25519PrivateKey` as the guest's only
  sshd host key - `services.openssh.hostKeys` naming `/etc/ssh/ssh_host_ed25519_key` with type
  `ed25519`, `environment.etc` installing that path as a copy at mode `0600` because sshd refuses a
  host key others can read and a store file is `0444` - and export
  `sshHostPublicKey = sshKeys.snakeOilEd25519PublicKey` beside the `sshPrivateKey` the file already
  exports. Add the assertion saying why the image's host identity and the client credential it
  authorizes are one published pair: `unseal-a-value-after-a-reboot` seals to this line and its
  backend seals to `ssh-ed25519` and `ssh-rsa` alone, and nixpkgs publishes exactly one ed25519
  snakeoil pair. Verify `nix build .#packages.x86_64-linux.planner-e2e-guest` builds and that a
  booted guest's `/etc/ssh/ssh_host_ed25519_key.pub` matches the exported line.
- [ ] 8.2 Run `rookery snapshot gc --all` before the next machine-layer run and record here that the
  following run was cold. Editing `tests/e2e/guest.nix` re-keys every snapshot cut, and a resumed
  stale cut presents a frozen RAM naming a system generation the new disk does not carry, which
  reads as a broken write script and is not. Verify `rookery snapshot list` is empty afterwards.
- [ ] 8.3 `flake-module.nix:169-173`: hand each folder's `deployment/default.nix` the exported line
  as a fourth argument beside `pkgs`, `planner` and `operator` - an argument and not an import,
  because a folder resolves no path outside itself, and the line rather than the guest attrset, so
  that evaluating a folder's deployment cannot drag the image's system closure into it. Every
  folder's `deployment/default.nix` takes the new argument. Verify
  `nix eval .#packages.x86_64-linux.planner-e2e-wired-pair.drvPath` resolves and that
  `testAReaderOpensAnEndToEndDirectory` still passes.
- [ ] 8.4 `tests/e2e/delivery.py:311-359`: `command_env` carries the guest's properties minus the
  two options the command now owns - `-F /dev/null`, `-i`, `GlobalKnownHostsFile=/dev/null`,
  `BatchMode=yes` - and a new `harness_env` keeps the full unpinned set for the harness's own `ssh`
  and `nix copy`. `guest_ssh_options` itself is unchanged. Repoint the harness's own remote work at
  `harness_env`, including `tests/e2e/newcomer/test_newcomer.py:491`, and leave every planner-command
  call site on `command_env`. Verify every call site of either helper under `tests/e2e/` is
  classified by whether the command or the harness performs the step, and that none is left reading
  the wrong one.
- [ ] 8.5 `tests/e2e/wired-pair/`, `tests/e2e/secret-delivery/`, `tests/e2e/portable-image/`,
  `tests/e2e/shared-postgres/` and `tests/e2e/generated-secret/`: state `hostKey` from the new
  argument for every machine of each deployment. `newcomer` states none and keeps
  `guest_ssh_options` as its workstation's `NIX_SSHOPTS`: its template is byte-compared against
  `docs/README.md` and is a standalone flake with no access to the image's exports, so it is the
  folder that proves the compatible answer on a real machine. Verify each folder's plan carries the
  line on its machine records and that no folder's build carries
  `machine-receives-a-value-unauthenticated`.
- [ ] 8.6 `tests/e2e/secret-delivery/deployment/default.nix`: a second build stating a `hostKey` no
  machine presents, the way `portable-image` builds `changed`, so that the pinning can be shown to
  be effective rather than assumed. Verify the second build's plan differs from the first in that
  one line and in no key.
- [ ] 8.7 `tests/e2e/secret-delivery/test_secret_delivery.py`: two tests, one per machine-layer
  scenario of `specs/operator/apply-command/spec.md` -
  `test_a_pinned_run_reaches_a_machine_that_presents_the_stated_key` and
  `test_a_machine_presenting_another_key_ends_the_step`, the second over the build of 8.6. Verify
  `nix run .#planner-e2e secret-delivery` is green and record the count against the count before
  this change.
- [ ] 8.8 `tests/unit/layers.nix`: cross a folder's stated `hostKey` against the image's own export,
  the way a folder's unit accounts are crossed against the guest's declarations (`:485-547`) - a
  folder's `.nix` text may carry no public key literal, the line having to arrive as the argument of
  8.3. Verify a literal pasted into a folder's deployment fails the check naming the folder.
- [ ] 8.9 `nix run .#planner-e2e`: green for every folder on the cold run after 8.2, with the count
  recorded here against the count before this change.

## 9. Registration, documents and verification

- [ ] 9.1 One atomic edit: in `tests/unit/coverage.nix` delete the three `excused` lines of 1.1, add
  the same three paths to `accountable`, and tick every box of this file in the same commit. This is
  the task the warning at the top of this file is about: `accountable` is unsatisfiable until the
  tests of 3.4, 3.5, 4.2, 5.2, 7.6 and 8.7 exist, and an `excused` entry naming a change that has
  landed fails `staleExcuses`. Verify the coverage cross-walk reports an empty difference and that
  every scenario heading of the three delta specs resolves to a test in exactly one layer.
- [ ] 9.2 `CLAUDE.md`: add this change's invariants under the sections that own them. Under "Keys and
  identity", beside the paragraph about the reservation: `hostKey` is read in the third projection of
  the machine reading for the same reason and is in no key, the plan's machine record carries it as
  an explicit absence, and a refused line is recorded nowhere. Under "The operator's command": the
  append of the command's own options stays, and the two options that decide host verification are a
  refusal naming the machine rather than an override, with `-F` out of scope; one machine is one
  option set for every step; the run reports its posture per machine. Under "End-to-end layer": the
  guest image carries a static ed25519 host key, why it is the same published pair it authorizes,
  and that a folder's `hostKey` arrives as the fourth argument of its `deployment/default.nix`.
  Under "Registration points": nothing new is registered by hand except the coverage entries of 9.1
  - `suites` in `tests/default.nix`, `classOf` and `scannedDirectories` in `tests/unit/layers.nix`,
  `programs.mypy.directories` in `treefmt.nix`, `src` in `ruff.toml`, `directoryKinds` in
  `lib/module.nix`, `lib/excluded.nix` and the `README.md` literals are all untouched, and the two
  hand-maintained points this change does edit are `lib/default.nix`'s wiring of `atoms` and
  `flake-module.nix`'s argument set for a folder's deployment. Verify the file passes vale under
  `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 9.3 `docs/operator.md:625-638` and the table at `:416`: the section on reaching a machine
  states the pinning, the refusal and its boundary, the per-machine report line and the compatible
  answer for a machine stating none, and keeps the reason the bounds are appended. `docs/authoring.md`
  and `docs/diagnostics.md`: the registry field and the two new row identifiers. Verify every path
  each document names resolves, `testAFileNamesAPathThatIsNotThere` passes, and the identifier list
  matches the library's.
- [ ] 9.4 `nix eval --json '.#debug.failures'` returns `[]`;
  `nix build .#checks.x86_64-linux.planner-tests` and
  `nix build .#checks.x86_64-linux.treefmt` are green; `nix fmt` changes no file this change
  touched. Verify each of the four, and `git add` every new file before evaluating: the flake does
  not see an untracked path and the failure reads as a missing file.
- [ ] 9.5 `nix build .#checks.x86_64-linux.planner-perf`: green against the figures recorded in 1.2.
  The gate is two-sided with a 0.15 margin and a growth bound of 1.25 across sizes 4, 16, 64 and
  256. A regression is a task to fix - gate the grammar check on a stated value, or narrow the
  grouped pass of 5.1 - and never a re-recorded budget. Verify the check passes and record the nine
  figures beside 1.2's.
- [ ] 9.6 Prove the new assertions can fail: fold `hostKey` into `machineRecords` and confirm 4.2
  fails alone; delete the line-break class from the grammar and confirm 3.5 fails alone; prepend the
  verification options instead of refusing and confirm 7.6's refusal test fails alone; point 8.6's
  wrong key at the real one and confirm 8.7's second test fails alone. Revert each and confirm the
  tree is byte-identical to before the mutation.
- [ ] 9.7 Confirm the obsolescence is total: no file under `cli/` composes one option string for a
  whole run, `tests/e2e/delivery.py` sends neither of the two verification options through the
  environment the operator's command is handed, and nothing outside `lib/util.nix` states the ssh
  public key grammar. Verify by search and record the result here.
