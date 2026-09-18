## 1. Baseline and registration, before anything is edited

- [ ] 1.1 Record no perf baseline, and record why: this change edits nothing `perf/eval.nix`
  evaluates. It touches `cli/planner.py`, a new `cli/enrollment.py`, `cli/manifest.py`,
  `cli/remote.py`, `operator/read.nix`, a new top-level `modules/` directory, `flake.nix`,
  `flake-module.nix`, `tests/unit/layers.nix`, a new `tests/unit/modules.nix`,
  `tests/unit/operator.nix`, `tests/e2e/guest.nix`, `tests/e2e/friend-enrollment/`,
  `tests/e2e/test_harness.py` and the documents - and no file under `lib/`. The gate is therefore
  expected byte-stable, which is what `openspec/changes/INTEGRATION.md:158-163` records for every
  change of this set: verify with `nix build .#checks.x86_64-linux.planner-perf` at the end of
  task 9.1 and treat any counter movement as a defect of this change, never as a re-recorded
  budget.
- [ ] 1.2 Verify that this change's five delta specs are already registered in `excused` in
  `tests/unit/coverage.nix`, one line each, each reason naming this change in the shape
  `excuseNamesChange` matches (`tests/unit/coverage.nix:397-402`), for
  `changes/enroll-a-friend-outside-the-harness/specs/operator/enrollment-command/spec.md`,
  `.../specs/operator/machine-provisioning/spec.md`,
  `.../specs/tooling/consumer-surface/spec.md`, `.../specs/tooling/repository-shape/spec.md` and
  `.../specs/delivery/real-cluster/spec.md`. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [ ] 1.3 **Leave every checkbox of this file unchecked for as long as those excuses stand.**
  `changeHasLanded` (`tests/unit/coverage.nix:406-412`) reads this file for a single line beginning
  with a ticked checkbox, and `staleExcuses` (`:414-424`) then fails the suite for an excuse whose
  change has started landing - so ticking one box while the five paths are excused turns the suite
  red for a reason that reads like a missing test. The marker `- [x]` may be named in prose, the
  reading being anchored at the start of a line. The paths move to `accountable` and every box is
  ticked in the one edit task 9.2 makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [ ] 1.4 `git add` every new file of this change before evaluating anything - the flake does not
  see an untracked path and the coverage cross-walk then reports the spec it cannot read rather
  than the file you forgot to stage. That is the five spec files, `proposal.md`, `design.md`,
  `tasks.md`, and every file a task below creates: `modules/**`, `cli/enrollment.py` and
  `tests/unit/modules.nix`. Verify with `nix eval --json '.#debug.failures'` returning something
  other than a file-not-found error.

## 2. Where a published module lives

- [ ] 2.1 Create the top-level `modules/` directory with the two modules' homes -
  `modules/coordination/` for the leaf module a deployment composes and `modules/provisioning/`
  for the machine module a machine's configuration imports - and register the directory in
  `classOf` in `tests/unit/layers.nix:56-86` under a class of its own, and in
  `scannedDirectories` (`:296-307`) so its files are held to the path scan. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`: an unclassified top-level entry fails
  `testATopLevelEntryBelongsToNoStatedClass` (`tests/unit/layers.nix:98-100`).
- [ ] 2.2 Add `modules/flake-module.nix` and name it in the `imports` of `flake.nix:43-48`, the way
  `cli/flake-module.nix` is: a deliverable with its own flake wiring is registered there. Publish
  the leaf module beside the library and the machine module under the output name that kind of
  module is published under, the way `flake.operator` is published rather than pointed at
  (`flake-module.nix:65-70`). Verify with `nix flake show` naming both outputs and with `nix eval
  --json '.#debug.failures'` returning `[]`.
- [ ] 2.3 Register a new unit suite `tests/unit/modules.nix` in `suites` in `tests/default.nix` -
  the only registration point for a suite, whose key names feed the coverage cross-walk - holding
  the module cases tasks 4 and 6 write. Verify with `nix build
  .#checks.x86_64-linux.planner-tests` reporting the new suite's cases.
- [ ] 2.4 Verify no other registration point is tripped: `cli/enrollment.py` is inside a directory
  `programs.mypy.directories` in `treefmt.nix` and `src` in `ruff.toml` already name, and no new
  end-to-end folder is added, so `flake-module.nix` names none - naming one would fail
  `testAnEndToEndFolderIsAddedWithoutEditingTheFlake`. Verify with `nix build
  .#checks.x86_64-linux.treefmt` and `nix build .#checks.x86_64-linux.planner-tests`.

## 3. The coordination statement and what the record publishes

- [ ] 3.1 In `operator/read.nix`, take one more statement beside `realise` in the argument set at
  `:637-650`, naming the plan key of the entry that runs the coordination server. A statement
  naming a key the plan places no entry for is one error row naming the statement and the
  addressable keys, the way `:690-703` already refuses a `realise` key naming no entry. Verify
  with `tests/unit/operator.nix` cases for the row, for a statement naming a value entry rather
  than a service entry, and for a deployment that states none earning no row.
- [ ] 3.2 In `operator/read.nix`, publish the coordination facts into the deployment record beside
  the `realisers` table (`:753-763`): the stated entry's key and the administrative program a verb
  runs, which is a store path of that entry's own closure. Publish nothing a realiser derives -
  no staged path and no per-realiser rule - so the command reproduces no rule of a realiser's.
  Verify with a `tests/unit/operator.nix` case reading the table off a generation of the
  end-to-end folder's deployment.
- [ ] 3.3 In `cli/manifest.py`, decode the coordination record and refuse a malformed one where the
  record is read, naming the field. Read the record's current `version` off `cli/manifest.py`
  rather than assuming a number - the seam is the one `openspec/changes/INTEGRATION.md:33-39`
  records for a record three changes added to - and move it only if the shape a previous reader
  saw cannot serve a verb. Verify with `tests/e2e/test_harness.py` cases over a record stating a
  coordination entry, one stating a malformed one, and one stating none.
- [ ] 3.4 Register the new row identifier in the row tables of `docs/diagnostics.md` and confirm
  `tests/unit/diagnostics.nix` sees the new constructor through the file lists it already walks -
  `operator/read.nix` is in `totalFiles` and in `producingFiles`, so no list edit is expected and
  the task is to verify, not to edit. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`, which fails a row identifier no document tabulates.

## 4. The published coordination module

- [ ] 4.1 Write `modules/coordination/` as a leaf module whose function arguments are the facts it
  refuses to default - the url a client is configured with and the admission policy - beside the
  packages it needs, the shape the folder's own module already has
  (`tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix:9`). Verify with a
  `tests/unit/modules.nix` case asserting the module composed without one of those two fails the
  evaluation naming the argument, and one asserting a composition stating both plans with no
  error row.
- [ ] 4.2 In `modules/coordination/`, make every other cluster-only choice a setting whose default
  is the value the module can defend outside a cluster, and state the cluster's own values nowhere
  in it: the listener (`hub.nix:72`), the relay's client verification and its empty url and path
  lists (`:97-104`), the embedded relay region (`:88-96`), the metrics listener (`:75`), the
  prefixes (`:80-83`), the node expiry (`:108-112`) and the name-service statements (`:133-143`).
  Verify with `tests/unit/modules.nix` cases asserting each default and asserting that a stated
  setting reaches the rendered configuration.
- [ ] 4.3 In `modules/coordination/`, render both objects from one derivation of the facts the
  module derived: the configuration the serving unit reads, declared as a `configData` file whose
  bytes the plan holds and whose record is the store's own so a realiser binds it
  (`hub.nix:152-163`, the realiser's choice at `image/read.nix:555-559`), and the object an
  administrative invocation reads, whose name carries the extension the server's loader requires -
  the fact `tests/e2e/friend-enrollment/test_friend_enrollment.py:192-203` states and works around
  at `:393`. Derive every host path inside `impl` from the entry's own identity; the module is
  inside the host-path scan of nothing today, and it must still state none. Verify with
  `tests/unit/modules.nix` cases asserting the two objects name one socket, that the
  administrative object's name carries the extension, and that no declaration of the module
  carries a host path literal.
- [ ] 4.4 In `modules/coordination/`, declare the credential generator and its program so that the
  program reads nothing from an environment nobody sets - it names the administrative object of
  4.3 and reads the numeric owner id back itself, the way the folder reads it
  (`test_friend_enrollment.py:456-462`, asserted at `:485-503`), replacing the two names
  `tests/e2e/friend-enrollment/deployment/mint.sh:25-32` reads. Keep the value single-use and
  expiring, `secrecy = "secret"` and delivered to no machine, which is what
  `openspec/changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md:34-41`
  requires. Verify with a `tests/unit/modules.nix` case asserting the plan records the value's
  path, its `deploy` and its program and carries no byte of a credential, and with `git grep
  HEADSCALE_CONFIG\|HEADSCALE_OWNER` answering nothing.

## 5. The verbs

- [ ] 5.1 Add `cli/enrollment.py`: read the coordination entry off the deployment record, refuse
  the command's own refusal naming the statement to add where the record states none, and refuse
  naming the entry and the path where the machine does not hold the program this build names.
  Verify with `tests/e2e/test_harness.py` cases over the recorded argv for each refusal, each
  asserting no machine was dialled.
- [ ] 5.2 In `cli/remote.py`, add the one step a verb takes, addressed by the machine's scope in
  the record: `--user` and an explicitly stated `XDG_RUNTIME_DIR` where the scope is `user`, and
  neither where it is `system`. Verify with harness cases asserting the step's argv carries each
  exactly where the scope states it.
- [ ] 5.3 In `cli/enrollment.py`, implement the minting verb: run the credential value's own
  declared `program` on the coordination entry's machine with an output directory the run names -
  the contract a generator's program is already run under (`secrets/read.nix:518-543`,
  `tests/e2e/generation.py:562-572`) - read the files it wrote back on the step's stream, refuse a
  file set the plan does not name, and write the files into the value source at the paths the plan
  names. Print the path written and the expiry minted under, and no byte of the key. Verify with
  harness cases for the written source, for the refused file set, and with an argv case asserting
  every encoding of the bytes is absent from every recorded vector, the way
  `tests/e2e/test_harness.py:3602-3645` already asserts it for a delivered credential.
- [ ] 5.4 In `cli/enrollment.py`, implement the listing and the expulsion: the listing prints what
  the server answered, whose credentials the server itself masks to a leading fragment
  (`test_friend_enrollment.py:237-245`), and the expulsion takes the identifier the listing
  printed and refuses a registry machine name in its place. Verify with harness cases over a
  fabricated answer for the printed lines and for the refusal.
- [ ] 5.5 In `cli/planner.py`, register the three verbs in the one subcommand table at `:145-151`
  with help that states every constraint each parser enforces - the target, the identifier the
  expulsion takes, and where a minted credential goes - and the document `:127-132` names. Verify
  with a harness case reading each subcommand's help for its own constraints, and with `planner
  --help` naming the three beside the five.
- [ ] 5.6 Assert the verbs write nothing into the deployment: a harness case planning the folder's
  deployment before and after a recorded verb run and comparing the plans equal. Verify with `nix
  build .#checks.x86_64-linux.planner-delivery`.

## 6. The published provisioning module and the guest

- [ ] 6.1 Write `modules/provisioning/` as a machine module carrying exactly the facts
  `cli/remote.py:670-729` verifies: the deploying account with lingering and a home traversable by
  a uid that owns none of it, that login in the machine's trusted logins, the three roots of
  `cli/remote.py:86-88` made writable by it and no fourth, the certificate an image's signature is
  verified against as an argument of the consumer's own, the authorization rule admitting the
  account's portable and mount actions, the two delegating daemons enabled, and the account's own
  portable-service daemon with its activation. Carry no credential and no private key. Verify with
  `tests/unit/modules.nix` cases crossing the roots the module writes against the three
  `cli/remote.py` states, and asserting the module names no login credential.
- [ ] 6.2 In `modules/provisioning/`, assert the two facts the module cannot create, each naming
  what a reader does where it fails: a service manager whose build exposes the user-namespace
  interface - the property `tests/e2e/guest.nix:70-82` explains and `:196-201` asserts - and a
  kernel permitting an unprivileged user namespace. Do not rebuild the consumer's service manager.
  Verify with `tests/unit/modules.nix` cases evaluating the module against a manager without the
  interface and asserting the failure names it.
- [ ] 6.3 Make `tests/e2e/guest.nix` a consumer: import the published module, hand it the account,
  the roots' modes, the verity certificates it already reads out of the folders (`:51-68`) and the
  authorization it needs, and delete its own copies - the account (`:319-328`), the trusted login
  (`:335`), the tmpfiles roots (`:337-341`), the certificate install (`:343-347`), the
  authorization rule (`:349-362`), the two sockets (`:364-385`) and the user portabled
  (`:387-392`) - keeping only the two guest facts: the snakeoil credential (`:147-150`, `:327`)
  and the rebuilt service manager (`:70-98`, `:368`). Keep the assertions that are about a fact
  the guest still states and move the rest into the module beside the fact they are about. Verify
  by `nix build .#checks.x86_64-linux.planner-tests` staying green - `tests/unit/layers.nix:486`
  reads this file for accounts (`:523-524`, `:573-575`) and homes (`:585-590`), so an account that
  moved out of it must still be readable there or those readers follow the import - and then run
  `rookery snapshot gc --all` before anything else, a stale cut resuming RAM that names a system
  generation the new disk does not carry. This change is the only one of its set permitted to edit
  that file (`openspec/changes/INTEGRATION.md:152-156`).
- [ ] 6.4 Drop `pkgs.headscale` from the guest's system profile and its assertion
  (`tests/e2e/guest.nix:245-246`), which exists because the operator's acts were `headscale`
  invocations over ssh: once a verb runs the entry's own administrative program, the tool arrives
  in the entry's closure, which that assertion already says is one store path and not two. The
  mesh client stays, being the machine's own daemon (`:248-252`). Verify by the friend-enrollment
  folder passing on a cold cut, and by `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 6.5 Prove the module provisions a machine it did not write: one `tests/unit/modules.nix` case
  evaluating a machine configuration that imports the module and nothing else of this repository,
  and asserting every fact the preflight asks about is declared. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.

## 7. The folder proves the verbs

- [ ] 7.1 Hand the published leaf module to every folder as an argument the way `operator` is
  handed (`flake-module.nix:155-173`), and rewrite
  `tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix` as a composition of it: the two
  arguments stated, the four cluster-only choices stated as settings of the instance
  (`deployment/instances.nix:5-21`), and the folder's own `mesh.nix:9-31` still the one file both
  halves read. Verify with `nix run .#planner-e2e -- friend-enrollment` and by the folder's plan
  carrying no error row.
- [ ] 7.2 Rewrite the folder's membership phases as verbs: the credential is minted by the verb of
  task 5.3 rather than by `test_friend_enrollment.py:456-469`, the node list is read by the verb of
  5.4 rather than by `:237-245`, and the expiry is taken by the verb of 5.4 rather than by
  `:825-828`. Delete the hand-installed configuration copy (`:192-203`, `:393`). Verify with `nix
  run .#planner-e2e -- friend-enrollment`, every phase of the landed folder still asserting what
  it asserted.
- [ ] 7.3 Keep what only a test needs and assert it is all that is left: the throwaway presenter
  that spends a spent credential (`test_friend_enrollment.py:248-263`), the operator's own
  userspace membership and its dialing path (`tests/e2e/delivery.py:574-611`, `:614-696`,
  `:784-813`), and the machines. Verify with a `tests/unit/layers.nix` case asserting the folder's
  text holds no invocation of the coordination server's own verbs, in the shape the builder-needle
  scan already has (`tests/unit/layers.nix:256-277`).
- [ ] 7.4 Verify the folder still holds the enrollment invariants it landed with: a plan key
  comparison asserting the friend machine's `target.address` is its mesh name
  (`deployment/machines.nix:27-33`), and the phase order unchanged - the expiry phase last, since
  it removes the wire the earlier phases stand on. Verify with `nix run .#planner-e2e --
  friend-enrollment` on a cold cut.

## 8. Documents

- [ ] 8.1 In `docs/operator.md`, state the enrollment order of work as verbs an operator types:
  state the coordination entry, mint, hand over outside the tree, read the listing, apply, and end
  a membership. State what a verb prints and what it never prints, and that a failed verb is the
  command's own refusal naming the machine and what it answered. Verify with `nix build
  .#checks.x86_64-linux.treefmt`.
- [ ] 8.2 In `docs/operator.md`, state the provisioning declaration beside the invariant it serves
  - root at provision time, never at deploy time - naming the published module, the facts it
  carries, the two it asserts, and the honest limit: a machine can receive a user-scope entry only
  where all six facts hold, and on the pinned nixpkgs one of them is a rebuilt service manager.
  Verify with `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 8.3 In `docs/cluster.md`, state that the guest is a consumer of the published provisioning
  module and what stays its own, and in `README.md` name the two published modules where the
  consumer surface is described. Verify with `nix build .#checks.x86_64-linux.treefmt` and with
  `nix build .#checks.x86_64-linux.planner-tests`, which reads literals of the root document
  (`tests/unit/layers.nix:103-104`).

## 9. Gates and close

- [ ] 9.1 `nix eval --json '.#debug.failures'` returns `[]`; `nix build
  .#checks.x86_64-linux.planner-tests`; `nix build .#checks.x86_64-linux.treefmt`; `nix build
  .#checks.x86_64-linux.planner-perf` against the byte-stable expectation of 1.1; `nix build
  .#checks.x86_64-linux.planner-delivery`; `nix run .#planner-e2e -- friend-enrollment` and one
  other folder on a cold cut, because task 6.3 re-keys every cut. The golden fixture states no
  coordination entry, so `nix eval --json .#debug.worked.plan | jq -S .` compares equal to the
  committed file, and a difference is a defect of task 3.1 rather than a regeneration.
- [ ] 9.2 In **one** edit, now that every scenario has its test: delete this change's five
  `excused` entries from `tests/unit/coverage.nix`, add the same five paths to `accountable`, and
  tick every checkbox of this file. One edit because the excuse is stale the moment a box is
  ticked and `accountable` is unsatisfiable until the tests exist, so any other order puts the
  suite red in between. Verify with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 9.3 Add this change's invariants to `CLAUDE.md`: under "Enrollment and the mesh", that a
  membership act is a verb of the command and that the coordination entry is stated beside the
  deployment and never inferred, that the credential is still the declared generator's own bytes
  run where the server answers, and that the operator's configuration is a store object named for
  the loader rather than a copy installed at a host path; under "Registration points", the
  `modules/` class and scan and the flake import; and under "Deployment scope", the published
  provisioning module, the two facts it asserts and the six-fact limit on which machines can
  receive a user-scope entry. Verify with `nix build .#checks.x86_64-linux.treefmt`, which lints
  that file, and with `nix build .#checks.x86_64-linux.planner-tests`.
