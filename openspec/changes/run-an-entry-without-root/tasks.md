## 1. Baseline and registration, before anything is edited

- [x] 1.1 Record the perf baseline before touching anything the planner evaluates: run `bash
  perf/measure.sh` and paste the nine counters into this change's working notes. This change is
  inside `mkPlan` - a registry key, a conditional field in `machineRecords` and `targetOf`, and
  four new row constructors - so the counters are allowed to move within the 0.15 margin and the
  recorded baseline is what tells a real regression from noise. The gate is two-sided, so a
  counter outside the margin is a task to fix and never a re-recorded budget.
- [x] 1.2 Register this change's five delta specs in `excused` in `tests/unit/coverage.nix`, one
  line per file, each reason naming this change in the shape `excuseNamesChange` matches, for
  `changes/run-an-entry-without-root/specs/planner/machine-platform/spec.md`,
  `.../specs/operator/apply-command/spec.md`, `.../specs/operator/deployment-build/spec.md`,
  `.../specs/realiser/portable-service-image/spec.md` and
  `.../specs/realiser/flakelet-artifact/spec.md`. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [x] 1.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` in `tests/unit/coverage.nix` reads this `tasks.md` for a single line beginning
  with a ticked checkbox, and `staleExcuses` fails the suite for an excuse whose change has
  landed, so ticking one box while the five paths are excused turns the suite red for a reason
  that reads like a missing test. The paths move to `accountable` and the boxes are ticked in the
  one edit task 11.2 makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [x] 1.4 `git add` every new file of this change before evaluating anything - the flake does not
  see an untracked path and the coverage cross-walk then reports the spec it cannot read rather
  than the file you forgot to stage. That is the five spec files, `proposal.md`, `design.md`,
  `tasks.md`, and every new file a later task creates. Verify with `nix eval --json
  '.#debug.failures'` returning something other than a file-not-found error.

## 2. The domain and the grammar

- [x] 2.1 In `lib/atoms.nix`, state `scopes = [ "system" "user" ]` beside `restartPolicies`
  (`lib/atoms.nix:17`), with an atom reading it the way `restartPolicy` does (`:99`) and the
  domain exported the way `domains.restartPolicy` is (`:101`), so the atom's predicate and the
  `machine-scope-unknown` row read one list. Verify with a `tests/unit/` case asserting the atom
  admits both values and refuses a third.

## 3. The registry reading and the projection

- [x] 3.1 In `lib/resolve.nix`, read the optional `scope` key from the machine registry beside
  `microarchitecture`, defaulting unstated to `system`, and add it to the allowlist the
  refuse-any-other-key row reads. A value the atom refuses is one `machine-scope-unknown` error
  row naming the machine and the registry file, and the machine's target is incomplete - read
  completeness off the value, the `address = 22` precedent, so the placements are dropped in the
  stratum the row is produced in. Verify with nix-unit cases for the row and for the dropped
  placement.
- [x] 3.2 In `lib/resolve.nix`, enter `scope` into `machineRecords` and `targetOf` only when it is
  `"user"`, the `microarchitecture` precedent (`lib/resolve.nix:587-592`), so stating the default
  re-keys nothing and flipping to `user` re-keys every entry on the machine. Implementations read
  `target.scope`. Verify with nix-unit cases asserting a stated `"system"` leaves every key and
  the machine record byte-identical, and a stated `"user"` moves the machine key and every entry
  key on it.

## 4. The scope-crossing rows

- [x] 4.1 In `lib/resolve.nix`, where `placement-platform-mismatch` is produced, add the three
  entry-side rows on a placement whose machine's scope is `user`: `unit-account-in-user-scope`
  for a unit declaring `user`, `unit-groups-in-user-scope` for an extension application recording
  `supplementaryGroups` under any backend (read the applications the way the delivered-file
  denial already reads them, without naming a realiser), and `port-privileged-in-user-scope` for
  a normalised fixed port claim below 1024 - after normalisation, so the row and the claim index
  agree on what was claimed. Each row is a refusal and not a filter: the entry stays in the plan.
  Verify with one nix-unit case per row and one asserting the same declarations on a system-scope
  machine earn none.
- [x] 4.2 In `lib/plan.nix`, add `value-ownership-in-user-scope`: a generated file record stating
  `owner` or `group`, delivered to a machine whose scope is `user`, is one error row whose
  subject is the value entry, naming the machine and the field; a stated `mode` earns nothing.
  Verify with nix-unit cases for a stated owner, a stated group, and a mode-only record.
- [x] 4.3 Register the four identifiers in the row tables of `docs/diagnostics.md`, and confirm
  `tests/unit/diagnostics.nix` sees the new constructors through the file lists it already walks -
  `lib/**` is in `totalFiles`, so no list edit is expected; the task is to verify, not to edit.
  Verify with `nix build .#checks.x86_64-linux.planner-tests`.

## 5. The published scopes and the reading's crossing

- [x] 5.1 In `image/read.nix`, publish `scopes = [ "system" "user" ]`, and in `flakelet/read.nix`
  publish `scopes = [ "system" ]`, each beside the `nameRule` and `unitRule` the reading already
  asks for. Verify with unit cases asserting each realiser record carries its list.
- [x] 5.2 In `operator/read.nix`, cross the stated realiser's published `scopes` against the
  entry's machine scope, the way the shown-path predicates are asked (`operator/read.nix:180-190`,
  `:313-323`): a mismatch is one `operator-entry-scope-unsupported` error row naming the entry,
  the machine's scope and the scopes the realiser publishes. Publish the scopes into the
  `realisers` table of `manifest.json` the retire change introduces, beside the holdings fact.
  Verify with `tests/unit/operator.nix` cases for the row, for a flakelet entry on a user-scope
  machine, and for the published table.
- [x] 5.3 In `flakelet/read.nix`, make the builder's own refusal for a user-scope target carry
  `operator-entry-scope-unsupported` and name the upstream facts - the unit directory of
  systemd.rs:13 and `/var/lib/flakelet` - in the idiom every realiser refusal already follows.
  Verify with the diagnostics cross-walk in `tests/unit/diagnostics.nix`, which pairs realiser
  refusals against the rows above them.

## 6. The image built for a user-scope target

- [x] 6.1 In `image/default.nix` and `image/read.nix`, place unit files under
  `/usr/lib/systemd/user` when the entry's target records `scope = "user"`, and write
  `PORTABLE_SCOPE=` into the os-release with the target's scope. Verify with unit cases over the
  rendered tree and the identity file for one entry built for each scope.
- [x] 6.2 In `image/default.nix`, build the user-scope image as squashfs plus dm-verity with a
  roothash signed by a key the builder takes as an operator argument - never a plan fact, never a
  file of the value source, written into no artifact. Refuse a user-scope image build handed no
  key, naming the entry and the argument. Verify with a unit case asserting the plan and the
  artifact carry no key material, and a build-level check that the image carries a verity
  partition and a signature.
- [x] 6.3 In `image/read.nix`, read the confinement profiles per scope: the user profiles drop
  `DynamicUser=yes` and `ProtectHome=yes` and keep `PrivateUsers=yes`, `trusted` is
  byte-identical, and `imageReader.denials` follows the scope's profile so the
  `DynamicUser`-derived denials are absent in user scope. One table read per scope, not a second
  table. Verify with unit cases asserting the per-scope denial sets and the byte-identical
  `trusted`.

## 7. The attach script in user scope

- [x] 7.1 In `image/default.nix`, render the attach script for a user-scope entry with
  `systemctl --user` and `portablectl --user` throughout, no `chown` anywhere, and the staging
  discipline unchanged - `install -d -m 0711`, 0600-create, mode, move. Place the image into
  `~/.local/state/portables` and attach by name, because persistent user attach copies to
  `~/.config/portables`, which the user image search path never scans (portable.c:1787-1811
  against discover-image.c:790-813). The script keeps taking no decision from the operator: the
  scope comes from the artifact. Verify with the assembly-style test the portable-image folder
  already runs - the script under a fake root with `portablectl` and `systemctl` answered by a
  refusing `PATH` - asserting the argv carries `--user` and no `chown` is run.

## 8. The command

- [x] 8.1 In `cli/remote.py`, add the one preflight question per user-scope machine: one script
  verifying the values root, the sealed root and the staging root writable by the account,
  lingering active, the user manager reachable, the user portabled reachable where an image entry
  is placed on the machine, `systemd-mountfsd.socket` and `systemd-nsresourced.socket` live, and
  unprivileged user namespaces permitted - one question per machine, folded the way the values
  and holdings questions fold, echoing `key=value` lines. State `XDG_RUNTIME_DIR` explicitly in
  every user-bus step rather than hoping the login shell set it. Verify with
  `tests/e2e/test_harness.py` cases over the recorded argv and fabricated answers.
- [x] 8.2 In `cli/apply.py`, ask the question before any mutation on that machine - before the
  retire step, before any value write, copy or activation - and refuse a failed fact as the
  command's own refusal naming the machine, the requirement and what the machine answered,
  attempting nothing after it on that machine. A system-scope machine is asked nothing new. Under
  `--dry-run` the question goes through the replaced channel (`cli/apply.py:182-207`) and is
  recorded rather than asked. Verify with harness cases for the order, the refusal and the dry
  run.
- [x] 8.3 In `cli/remote.py` and `cli/report.py`, address a user-scope machine's manager and
  portabled with `--user` in every status, holdings and activation step, read off the machine's
  scope in the record and the published `scopes` of the realiser the step belongs to. Verify with
  harness cases asserting `--user` appears exactly where the scope is `user`.

## 9. The machines

- [x] 9.1 Spike first: enable `systemd-mountfsd.socket`, `systemd-nsresourced.socket` and user
  portabled in `tests/e2e/guest.nix`, provision one account with lingering, writable roots and a
  verity public key, and prove by hand-driving one phase that the account attaches a signed image
  over `portablectl --user` - before any folder depends on the stack, because the NixOS wiring
  for user portabled is young. After editing `tests/e2e/guest.nix`, run `rookery snapshot gc
  --all` before anything else - a stale cut resumes RAM naming a system generation the new disk
  does not carry. Verify by the spike phase passing on a cold cut.
- [x] 9.2 Add a user-scope end-to-end folder under `tests/e2e/`, discovered from its
  `deployment/default.nix` like every other folder: one machine declaring `scope = "user"`, one
  image entry attached and served as the account, a value delivered without ownership, and phases
  asserting the preflight ran first, the units run under the user manager, and a reboot brings
  them back through lingering. Derive every host path inside `impl` from the entry's own identity
  - the folder's deployment is inside the host-path scan. Verify with `nix run .#planner-e2e --
  <folder>`.
- [x] 9.3 Add the negative harness coverage that needs no machine: a flakelet entry stated on a
  user-scope machine is `operator-entry-scope-unsupported`; a unit with `user`, a
  `supplementaryGroups` extension, a privileged fixed port and an owned value on a user-scope
  machine each earn their row and the deployment is inapplicable. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.

## 10. Documents

- [x] 10.1 In `docs/operator.md`, state the provisioning invariant - root at provision time, never
  at deploy time - with the one-liners: the tmpfiles.d rule or command that makes the three roots
  writable by the account, `loginctl enable-linger`, and the verity public key install; state the
  signing key's custody - an operator argument to the build, held by the operator, in no plan and
  no value source - and the preflight's place before every other step of the walk. Verify with
  `nix build .#checks.x86_64-linux.treefmt`.
- [x] 10.2 In `docs/plan.md`, document `scope` under the machine record and the target - the
  domain, the default, the only-when-user key participation - and in `docs/diagnostics.md` the
  five new rows (task 4.3 covers the four planner rows; add `operator-entry-scope-unsupported`
  beside the other reading rows). In `docs/cluster.md`, state the new folder and the guest's
  user-portabled stack. Verify with `nix build .#checks.x86_64-linux.treefmt`.

## 11. Gates and close

- [x] 11.1 `nix eval --json '.#debug.failures'` returns `[]`; `nix build
  .#checks.x86_64-linux.planner-tests`; `nix build .#checks.x86_64-linux.treefmt`; `nix build
  .#checks.x86_64-linux.planner-perf` against the baseline of 1.1. The golden fixture states no
  scope, so `fixtures/minimal-typed-edge/plan/backup.json` is expected byte-identical: verify by
  `nix eval --json .#debug.worked.plan | jq -S .` comparing equal to the committed file, and
  treat a difference as a defect of 3.2, never as a regeneration.
- [x] 11.2 In **one** edit, now that every scenario has its test: delete this change's five
  `excused` entries from `tests/unit/coverage.nix`, add the same five paths to `accountable`, and
  tick every checkbox of this file. One edit because the excuse is stale the moment a box is
  ticked and `accountable` is unsatisfiable until the tests exist, so any other order puts the
  suite red in between. Then add this change's invariants to `CLAUDE.md`: the scope key and its
  only-when-user key entry under "Keys and identity", the four rows and the per-scope denial
  reading under "Diagnostics" and "Realisers", the provisioning invariant and the preflight under
  "The operator's command". Verify with `nix build .#checks.x86_64-linux.planner-tests` and `nix
  build .#checks.x86_64-linux.treefmt`.
