## 1. Registration and discipline

- [x] 1.1 Register this change's one delta spec in `excused` in `tests/unit/coverage.nix`:
  `changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md`, the reason naming
  this change in the shape `excuseNamesChange` matches. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [x] 1.2 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` reads this `tasks.md` for a line beginning with a ticked checkbox and
  `staleExcuses` fails the suite for an excuse whose change has landed. The path moves to
  `accountable` and the boxes are ticked in the one edit task 5.2 makes.
- [x] 1.3 `git add` every new file of this change before evaluating anything - the flake does not
  see an untracked path. Verify with `nix eval --json '.#debug.failures'` returning something
  other than a file-not-found error.
- [x] 1.4 Do not start this change before the four production changes have landed:
  `run-an-entry-without-root` owns the scope, the preflight and the user-scope image this
  change's folder places on the friend machine.

## 2. The guest image and the hub

- [x] 2.1 Add headscale and tailscale to `tests/e2e/guest.nix`, then run `rookery snapshot gc
  --all` before anything else - a stale cut resumes RAM naming a system generation the new disk
  does not carry. Record the image note in `docs/cluster.md`. Verify by any folder passing on a
  cold cut.
- [x] 2.2 Write the hub's headscale service as a leaf module of the new folder's deployment: a
  system-scope entry on the hub machine, its configuration under `configData`, and the mesh
  names it serves stated from the deployment's own machine names. Every host path derives from
  the entry's own identity - the folder's deployment is inside the host-path scan. Verify with
  the folder's plan evaluating with no error row.

## 3. The credential

- [x] 3.1 Declare the credential generator on the hub entry: a single-use, expiring pre-auth key,
  its file record `secrecy = "secret"` and `deploy = false`, minted with the server's own tool
  under `runtimeInputs`. Verify with a unit case asserting the plan records the value's path and
  delivery facts and no plan field carries bytes.
- [x] 3.2 Prove the argv discipline: a `tests/e2e/test_harness.py` case over the recorded argv of
  an apply against the folder's deployment, asserting no argv contains the credential's bytes -
  the recorder keeps the argv and drops payloads, so the assertion is over what it keeps.

## 4. The proof

- [x] 4.1 Add `tests/e2e/friend-enrollment/`, discovered from its `deployment/default.nix` like
  every other folder: the hub machine at system scope, one friend machine declared `scope =
  "user"` whose `address` is its mesh name, and one user-scope entry placed on the friend
  machine. Verify with `nix run .#planner-e2e -- friend-enrollment` once the phases below exist.
- [x] 4.2 Phase: the friend machine joins the mesh with the credential; the hub's node list names
  it, echoed as `key=value` lines through one ssh command per case.
- [x] 4.3 Phase: a second join presenting the same credential is refused by the server, and the
  node list still names the first machine alone.
- [x] 4.4 Phase: an apply dials the friend machine by its mesh name - the user-scope preflight
  runs first, the entry activates under the account's manager, and the report reads the holdings
  over the same name.
- [x] 4.5 Phase: the operator expires the friend machine's node; a report names the machine as one
  it could not ask and exits non-zero. Run this phase last - it removes the wire the earlier
  phases stand on.

## 5. Documents and close

- [x] 5.1 In `docs/operator.md`, state the enrollment order of work: declare the row, generate,
  hand the credential over outside the tree, verify the node list, apply. State D2's one-way
  sync and D3's verification ceremony beside it. Verify with `nix build
  .#checks.x86_64-linux.treefmt`.
- [x] 5.2 In **one** edit: move this change's path from `excused` to `accountable` in
  `tests/unit/coverage.nix` and tick every checkbox of this file - any other order puts the suite
  red in between. Cross-check the `CLAUDE.md` enrollment bullets against what landed. Verify with
  `nix build .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`.
- [x] 5.3 Gates: `nix eval --json '.#debug.failures'` returns `[]`, `planner-tests` and `treefmt`
  green. `lib/` is untouched by this change, so the perf gate is expected byte-stable: treat any
  counter movement as a defect, never as a re-recorded budget.
