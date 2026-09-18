## 1. Baseline and registration, before anything is edited

- [ ] 1.1 Record no perf baseline, and record why: this change edits nothing `perf/eval.nix`
  evaluates. That file plans and nothing else - `perf/eval.nix:34` is `planner.mkPlan args` - and
  this change touches `image/read.nix`, `operator/read.nix`, `docs/diagnostics.md`,
  `docs/operator.md`, `tests/unit/image.nix`, `tests/unit/operator.nix`,
  `tests/e2e/portable-image/` and `CLAUDE.md`, no file under `lib/` and no plan field. Verify by
  confirming `git diff --name-only` at the end of this change names no path under `lib/` and that
  `nix build .#checks.x86_64-linux.planner-perf` is not in the gate list of task 8.2.
- [ ] 1.2 This change's two delta specs are already registered in `excused` in
  `tests/unit/coverage.nix`, one line each, in the shape `excuseNamesChange` in that file matches,
  for
  `changes/bind-a-value-an-entry-did-not-generate/specs/realiser/portable-service-image/spec.md`
  and `changes/bind-a-value-an-entry-did-not-generate/specs/delivery/real-cluster/spec.md`. The
  task is to verify, not to edit: run `nix build .#checks.x86_64-linux.planner-tests` after 1.4 and
  confirm `testEverySpecificationIsClassified` is green, which an unclassified `spec.md` fails.
- [ ] 1.3 **Leave every checkbox of this file unchecked until the landing edit of task 8.3.**
  `changeHasLanded` in `tests/unit/coverage.nix` reads this file for a single line beginning with a
  ticked checkbox and `staleExcuses` beside it then fails the suite for an excuse that outlived it,
  so ticking one box while the two paths are excused turns the suite red for a reason that reads
  like a missing test. Verify by ticking nothing until 8.3 and by
  `nix build .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [ ] 1.4 `git add` every new file of this change before evaluating anything: the flake does not see
  an untracked path and the coverage cross-walk then reports the spec it cannot read rather than the
  file you forgot to stage. That is the two spec files, `proposal.md`, `design.md`, `tasks.md`, and
  every new file a later task creates under `tests/e2e/portable-image/`. Verify with
  `nix eval --json '.#debug.failures'` returning something other than a file-not-found error.
- [ ] 1.5 Record the entry point inventory this change changes the signature of, so phase 2 edits
  one list rather than discovering callers: `imageReader.hostPaths` (`image/read.nix:686-691`,
  called at `operator/read.nix:171`), `imageReader.denials` (`:693-706`, called at
  `operator/read.nix:237-244`) and `imageReader.versionFor` (`:713-756`, called at
  `operator/read.nix:280-283`). Verify with a grep for those three names returning those three
  call sites and the three definitions and nothing else.

## 2. The value set the reading answers

- [ ] 2.1 In `image/read.nix`, add `valueIndex`, one index over a plan keyed by the path each
  declared generated file records, answering the value entry's key, the file's name in that record,
  the file record itself and the delivery set. Recognise a value record by what it records -
  `delivery` beside `files` - the way `isVarsFile` is recognised by the record a caller indexes
  (`lib/util.nix:499-518`) and never by the text of a key (`operator/read.nix:59-71`). Keep the
  first record for a path. A record whose `delivery` is not a list, or whose `files` is not an
  attrset of records carrying a string `path`, contributes nothing, so the index is total inside a
  reading that may not raise. Verify with `tests/unit/image.nix` cases asserting the index answers
  for a declared file, answers nothing for a machine record or a service entry, and answers nothing
  for a malformed value record instead of raising.
- [ ] 2.2 In `image/read.nix`, add `valuesOf { valueIndex, key, entry }` answering
  `{ generated, unaccounted }`. `generated` is `generatedOf entry` followed by one record per value
  path the entry's declared reads name that the first half does not already carry, found by asking
  `planner.util.varsPathsDeep` (`lib/util.nix:369-377`) of each slot's own record in `entry.reads`
  so the answer carries the slot that named it - the recogniser `misdeliveredRows`
  (`lib/plan.nix:635-677`) and `opensAValue` (`operator/read.nix:498-503`) already ask. Keep the
  first record for a path. `unaccounted` is the slot-and-path pairs the index answers nothing for,
  or answers with a record whose delivery set does not name this entry's machine. Both halves of
  `generated` carry one field set - the file's `path`, `secrecy`, `deploy`, `inPlan`, `owner`,
  `group`, `mode` and `present`, plus the slot and the value entry's key for a read-derived record
  and the generator and file name for the entry's own, each null on the other half - because
  `required` (`image/read.nix:300-305`) exists to refuse a half-shaped record. Verify with
  `tests/unit/image.nix` cases for a read-derived record, a value reached twice, and the field set
  being equal across both halves.
- [ ] 2.3 In `image/read.nix`, make `hostPathsOf` take `generated` instead of calling
  `generatedOf entry` (`:591`), keeping the `deploy && inPlan == reference` filter unchanged, so a
  value the plan records as undeployed is shown at no path whichever statement reached it. Verify
  with `tests/unit/image.nix` `testAValueAnotherEntryGeneratedIsShownAtItsPath` and
  `testAReadOfAnUndeployedValueIsShownAtNoPath`.
- [ ] 2.4 In `image/read.nix`, make `referencePaths` (`:809-814`) and the attachment description's
  `generated` table (`:1169-1174`) read the same `generated` list, and confirm `denialsOf`
  (`:602-635`) needs no change beyond being handed it at `:704` and `:884`. Verify with
  `tests/unit/image.nix` `testEveryReadingOfAShownValueAsksOneList` and a case asserting a peer's
  value path declared as a closure root is `closure-root-is-delivered` (`:928-929`).
- [ ] 2.5 In `image/read.nix`, change `hostPaths`, `denials` and `versionFor` to take `generated`
  beside what they take today, and drop their internal `generatedOf entry` calls (`:704`,
  and the one inside `hostPathsOf` reached from `:688`). `read` (`:758-770`) builds the index and
  the union from the plan it already has. Verify with `tests/unit/image.nix` cases asserting the
  three entry points and `read` answer the same host path list for one entry.
- [ ] 2.6 In `operator/read.nix`, build the index once per reading between the `{ plan, realise }`
  layer and the `key` layer of `readEntry` (`:127-129`), compute the union once per entry beside the
  denials it already computes (`:237-244`), and hand `generated` to the three entry points (`:171`,
  `:241`, `:280-283`). Do not reuse the reading's own `values` table (`:712-717`): its file records
  carry the five fields a delivery interpolates (`fileFields`, `:437-443`) and neither `deploy` nor
  `inPlan`, and `readMachine`'s filter (`:529`) requires every one of them to be a non-empty string.
  Verify with `tests/unit/operator.nix` cases asserting the reading's host path list for a consumer
  of a peer's value, and with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 2.7 Confirm `image/default.nix` needs no edit: the mount points map `image.hostPaths`
  (`:103-109`) and the attach-time existence guard maps the generated-file half of
  `attachment.hostPaths` (`:344-348`), so both cover the new paths by existing. Verify with a
  `tests/unit/image.nix` case reading the rendered image root and the attach script for a consumer
  of a peer's value and asserting one `install -D` and one guard for it.

## 3. The refusal and the row above it

- [ ] 3.1 In `operator/read.nix`, produce `operator-entry-value-unaccounted`: one error row per
  entry of `unaccounted`, naming the entry as subject, the slot that declared the read and the path,
  with an evidence line stating that a delivery set is derived from the reads that name a value so a
  read naming a value the plan does not deliver is a plan whose records disagree, and a resolution
  naming the value entry to inspect. Its neighbours are `operator-plan-record-unclassified` and
  `operator-plan-field-missing` (`:407-419`), which are rows about the same class of handed-in plan.
  Verify with `tests/unit/operator.nix` `testAReadNamingAValueThePlanDoesNotDeliverThere` and
  `testAReadNamingAPathNoValueRecordCarries`, each asserting the row identifier, the subject, the
  named slot and the named path, and that the deployment is refused with no artifact of that entry.
- [ ] 3.2 In `image/read.nix`, add the account carrying that identifier to the `accounts` table
  (`:183-215`), beside `accessDenied` (`:212`), and refuse in `read` in the ladder the other
  refusals sit in (`:913-944`) naming the entry, the slot and the path. Verify with
  `tests/unit/image.nix` `testTheUnaccountedRefusalIsPrecededByItsRow` and with the cross-walk in
  `tests/unit/diagnostics.nix`, which pairs each realiser refusal against the rows above it off the
  realiser sources it is handed.
- [ ] 3.3 Register `operator-entry-value-unaccounted` in the row tables of `docs/diagnostics.md`,
  beside `operator-entry-access-denied` (`docs/diagnostics.md:321`), and in the short table of
  `docs/operator.md` (`:300`) with the resolution an operator acts on. Verify with
  `nix build .#checks.x86_64-linux.treefmt`.

## 4. The digest, verified rather than widened

- [ ] 4.1 Verify the version digest needs no edit and moves anyway: `versionFor` takes the digest
  over `hostPathsOf` (`image/read.nix:733-747`) and the requirement that owns it already names "the
  host paths it is shown" (`openspec/specs/realiser/portable-service-image/spec.md:767-774`). Add
  `tests/unit/image.nix` `testAReadOfAPeersValueMovesTheEntrysVersionDigest`, reading one entry
  twice and differing only in the declared read, asserting the two digests differ and the two image
  file names differ. Do not edit `versionOf`.
- [ ] 4.2 Verify the golden plan is byte-identical: this change adds no plan field and no key input
  moves. Run `nix eval --json .#debug.worked.plan | jq -S .` and compare against
  `fixtures/minimal-typed-edge/plan/backup.json`, and treat any difference as a defect of phase 2
  rather than as a regeneration. The fixture's one consumer reads `url` and `quota` and no value, so
  nothing of it is in the new path at all.

## 5. The unit layer

- [ ] 5.1 In `tests/unit/image.nix`, add the scenarios of the `realiser/portable-service-image`
  delta that this phase has not already covered:
  `testAValueTheEntryNeitherGeneratedNorReadIsShownAtNoPath`, `testAValueTwoReadsNameIsShownOnce`
  and `testAValueAnEntryBothGeneratedAndReadIsShownOnce`. The two-reads case needs a provider
  publishing two secret exports backed by one generated file; the worked fixture's
  `borgRepository` is the precedent for a provider declaring two exports at all, and neither of
  its two is backed by a file, so the pair has to be declared here. Verify each fails against the
  reading as it stands before 2.3 and passes after 2.6.
- [ ] 5.2 In `tests/unit/image.nix`, add the denial scenarios:
  `testAPeersValueOnlyItsOwnerMayReadIsDeniedToItsReader` and
  `testAPeersValueAReadersGroupMayReadIsNotDenied`. The first asserts the denial a reader earns is
  the denial the owner already earns for that file - observed on this tree before the change as
  `[ ]` for the reader against one denial naming `root:root at mode 0400` and `a transient account`
  for the owner. Verify both, and verify the four existing scenarios of that requirement keep the
  tests they have (`testARootOnlyValueUnderAConfiningProfile` in `tests/unit/operator.nix`, the
  other three in `tests/unit/image.nix`).
- [ ] 5.3 In `tests/unit/operator.nix`, verify the mirrored reading with no edit in it beyond 2.6
  and 3.1: a consumer of a peer's root-only value under a confining profile is an
  `operator-entry-access-denied` row from the builder's own denial list, the way
  `testARootOnlyValueUnderAConfiningProfile` (`tests/unit/operator.nix:2287-2319`) already reads
  one for the owner's own value and asserts the realiser refuses the same condition. Verify with
  `nix build .#checks.x86_64-linux.planner-tests`.

## 6. The machine layer

- [ ] 6.1 In `tests/e2e/portable-image/deployment/interfaces/default.nix` and
  `deployment/modules/report/watch.nix`, publish `vars.upstream.secret` as a secret export on an
  interface the folder declares, beside the `path` export `watch.nix:66-68` already publishes.
  Declare the export secret and leave the file's record as it is - owned by `nobody`, group
  `nogroup`, mode `0440` (`watch.nix:14-22`) - so the reader can be admitted through the group the
  confined unit declares. Verify the deployment still builds and
  `nix eval --json '.#debug.failures'` is `[]`.
- [ ] 6.2 In `tests/e2e/portable-image/deployment/`, add one consumer module and one instance:
  `uses.<slot>` of that interface with `reach = "one"` and a read of the secret export, a unit that
  reads the value at `results.<slot>.<export>.path` and writes what it read to a path it derives
  inside `impl` from its own `instance` and `member`, the extension declaring the group, and a
  statement in `statements` naming `realiser = "image"` with a confining profile. Derive every host
  path inside `impl` - the folder's deployment is inside the host-path scan
  (`tests/unit/layers.nix`, reported by `testADeploymentStatesAHostPath`). Place it on `alpha`, so
  the folder's stage keeps `names=(MACHINE,)` and its default disk figure
  (`test_portable_image.py:298`) and no cut is re-keyed. Verify with
  `nix build .#checks.x86_64-linux.planner-tests` and by the plan recording the read.
- [ ] 6.3 In `tests/e2e/portable-image/test_portable_image.py`, add the phase and its three cases:
  `test_the_consumers_unit_opens_the_peers_value_on_the_machine`,
  `test_the_bind_comes_from_the_artifacts_own_unit_file` and
  `test_one_file_on_the_machine_serves_both_entries`. Read the bind out of the delivered artifact's
  own unit file the way `tests/e2e/friend-enrollment/test_friend_enrollment.py:159-167` reads one,
  and compare the file's bytes inside the unit's own mount namespace the way
  `tests/e2e/shared-postgres/test_shared_postgres.py:887-902` does, because a path that exists on
  the host and not inside the unit is the whole failure. One case is one ssh command with everything
  it observes echoed as `key=value` lines. Verify with `nix run .#planner-e2e -- portable-image`.
- [ ] 6.4 Verify the flakelet half needs no folder and no edit: `tests/e2e/shared-postgres/` already
  reads a peer's value (`deployment/modules/app/client.nix:17-22,49`) under that realiser
  (`test_shared_postgres.py:533`), and its three consumer entries gain one `BindReadOnlyPaths` line
  each - the same self-bind their own values already carry (`tests/unit/image.nix:3090`), admitted
  by flakelet's own `acceptsHostPath` (`flakelet/read.nix:137-142`) and written for by its
  `pathRule` (`:128-135`). Run `nix run .#planner-e2e -- shared-postgres`, record the one new
  flakelet generation the first apply writes for each of those entries, and confirm a second apply
  reports nothing changed.

## 7. The supersession

- [ ] 7.1 In `openspec/changes/deliver-a-secret-without-exposing-it/tasks.md`, mark tasks 6.1
  (`:125-130`) and 6.3 (`:136-141`) superseded by this change, in the shape sections 3 and 5 of that
  file already use for a superseded task (`:72-77`, `:117-121`): the box stays unchecked and the
  text names this change and what it holds instead. 6.2 (`:131-135`) stays that change's - it
  narrows which units a denial names rather than which files are compared - and so does the third
  clause of 9.5 (`:204-206`), which this change makes true and which that change still verifies.
  Edit no other file of that change. Verify by reading the two tasks back and by
  `nix build .#checks.x86_64-linux.treefmt`.

## 8. Documents, gates and close

- [ ] 8.1 In `docs/operator.md`, state which values an entry is shown - the ones its own declaration
  generates and the ones its declared reads name, deployed, one record per path - and the one-time
  artifact consequence: a consumer of a peer's value publishes a new version digest, so the first
  apply after this change replaces those images and writes new flakelet generations, and the next
  reports nothing changed. Verify with `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 8.2 Run the gates: `nix eval --json '.#debug.failures'` returns `[]`;
  `nix build .#checks.x86_64-linux.planner-tests`; `nix build .#checks.x86_64-linux.treefmt`. No
  perf gate is run, for the reason task 1.1 records. Verify all three green before 8.3.
- [ ] 8.3 In **one** edit, now that every scenario has its test: delete this change's two `excused`
  entries from `tests/unit/coverage.nix`, add the same two paths to `accountable`, and tick every
  checkbox of this file. One edit because the excuse is stale the moment a box is ticked and
  `accountable` is unsatisfiable until the tests exist, so any other order puts the suite red in
  between. Then add this change's invariants to `CLAUDE.md` under "Realisers": that a realiser shows
  a host path for every deployed generated file the entry generates **and** for every one a declared
  read of it names; that the union is one list the host paths, the denial table, the reference paths
  and the attachment description all read, a value reached twice being one record; that the join is
  by the path the read record already carries, because `reads` is in the entry's key input and a
  peer's ownership in a read record would re-key every consumer; and that a shown value path no
  delivered bytes are accounted for is `operator-entry-value-unaccounted`. Verify with
  `nix build .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`.
