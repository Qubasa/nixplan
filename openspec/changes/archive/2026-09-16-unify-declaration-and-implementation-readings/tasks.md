## 1. One reading in the library

- [x] 1.1 Change `compose.resolveSettings` in `lib/compose.nix` to take `name`, `defaults` and `fixed` instead of `member`, keeping `values`, `sources` and `rows` identical apart from `member.name` becoming `name` in the two row messages; verify `nix eval --json .#planner.failuresBySuite` reports the same failures as before the edit and no new `settings-*` message text
- [x] 1.2 Close `compose.service` over a `settingsOf` resolver as its first argument, evaluate the declaration once against `settings.values`, and return `settings` and `declaration` alongside today's `name`, `module`, `defaults`, `fixed`, `unknownKeys` and `provides`; verify `nix eval .#planner.service` is a function of three arguments by applying it in a throwaway `nix eval --expr` against a stub resolver
- [x] 1.3 Change `compose.mkRoot` to `root: settingsOf: root { service = service settingsOf; }`; verify `nix eval --json .#planner.suites.interfaces --apply 'builtins.attrNames'` still lists every test after task 1.5 updates its one caller
- [x] 1.4 Build the per-member resolver in `mkInstance` (`lib/resolve.nix:98`) from `idecl.settings`, `deploymentFile`, `moduleFileOf iname` and the `${iname}:${name}` subject, and hand it to `compose.mkRoot`; verify `nix eval --json .#planner.worked.diagnostics` is `[]`
- [x] 1.5 Delete the second reading in `mkMember` (`lib/resolve.nix:193-204`): take `settings` from `member.settings` and pass `member.declaration` into `module.read`; verify the golden comparison still passes with `nix build .#checks.x86_64-linux.planner-pytest` and that no field of `.#planner.worked.plan` changed
- [x] 1.6 Update the one in-tree caller of the published surface, `tests/suites/interfaces.nix:392`, to pass a resolver that returns `{ values = { }; sources = { }; rows = [ ]; }`; verify `nix eval --json .#planner.failuresBySuite.interfaces` is `{}`

## 2. The behaviour the delta spec names

- [x] 2.1 Add a per-row test to `tests/suites/composition.nix` for a member whose `provides` is derived from a setting the deployment overwrote with a longer list, asserting the instance may expose every resolved name and that no `exposes-unknown-capability` row is produced; verify it fails on `git stash` of task 1 and passes after
- [x] 2.2 Add a per-row test asserting that a wire to a capability the deployment added delivers, records the consumer on that capability's exports and produces no row; verify `nix eval --json .#planner.failuresBySuite.composition` is `{}`
- [x] 2.3 Add a per-row test for the undeclared-knob case: the deployment writes a knob the member declares neither as a default nor as fixed and the member derives its capability set from it, asserting the `settings-undeclared-knob` row and that the set comes from the member's own value; verify the row id and the member and knob names appear in the message
- [x] 2.4 Record each of the three delta-spec scenarios in the coverage mapping (`tests/mapping.nix`) against the tests from 2.1-2.3; verify `nix eval --json .#planner.failuresBySuite.coverage` is `{}`

## 3. The scenarios stop carrying deployment names

- [x] 3.1 Rewrite `tests/scenarios/shared-postgres/modules/postgresql/cluster.nix` to fold `each` over `settings.databases`, dropping the `databases` closure argument and deleting the file-head comment that documents the two-reading workaround; verify no name from any deployment appears in the file
- [x] 3.2 Rewrite that scenario's `modules/postgresql/default.nix` to declare `defaults.databases = [ ]` and forward `provides = main.provides;`, with no `databases` list in the file; verify `grep -n '"eu"\|"us"' tests/scenarios/shared-postgres/modules` finds nothing
- [x] 3.3 Add `settings.main.databases = [ "eu" "us" ]` to that scenario's `deployment/instances.nix` beside the existing `exposes`; verify `nix eval --json .#planner.scenarios.shared-postgres.diagnostics` is `[]` and the two DSNs in `.plan` are unchanged from the values `tests/python/test_shared_postgres.py:32-33` asserts
- [x] 3.4 Apply the same three edits to `tests/scenarios/two-readers-one-database/`, and update its `deployment/instances.nix` comment so it describes the one line that differs from `shared-postgres` rather than the deleted closure; verify `nix eval --json .#planner.scenarios.two-readers-one-database.diagnostics` is `[]`
- [x] 3.5 Add a pytest to `tests/python/test_shared_postgres.py` asserting that the published capability set of `pg:main@one` equals the deployment's `settings.main.databases`, and that the setting's source is recorded as the deployment; verify it fails against the pre-change scenario files and passes after
- [x] 3.6 Update `tests/scenarios/*/scenario.nix` only where the root import's argument list changed, keeping the glue's rule that it closes package strings and injects no deployment decision; verify both `scenario.nix` files pass no `databases` argument

## 4. Budgets, docs and the invariant that is gone

- [x] 4.1 Run `nix build .#checks.x86_64-linux.planner-perf -L`, take the replacement figures from the ratchet failure message, and write them into `perf/budgets.json` with the interpreter version and today's date; verify the check passes on a rerun. The direction the task assumed does not hold: measured, six gated counters fell and `nrFunctionCalls`, `envs.bytes` and `gc.totalBytes` rose by at most 0.4%, so the budgets are re-pinned in both directions (design D4 corrected, user decision)
- [x] 4.2 State in `docs/authoring.md` §3 that a member's declaration is read once against resolved settings, that a capability set may therefore be derived from a member's settings, and that a root forwards a settings-derived set (`provides = main.provides;`) rather than naming it; verify the section's existing re-export example still type-checks against `fixtures/minimal-typed-edge/modules/borg-push/default.nix`
- [x] 4.3 Update the published-surface row in `docs/README.md:171` for the new `service`/`mkRoot` shape; verify the described arity matches `lib/compose.nix`
- [x] 4.4 Grep `pkgs/planner` and `notes/` for prose asserting that a root declares what it provides before a deployment has said anything, and delete or correct each occurrence; verify the phrase survives nowhere by re-running the grep

## 5. Verification

- [x] 5.1 Reproduce the probe from proposal.md as a throwaway scenario — a deployment adding a database over a shorter default, with a consumer wired to the added capability — and verify it now evaluates to `[]` diagnostics with the consumer's `DATABASE_URL` naming the added database, then delete the directory
- [x] 5.2 Run `nix eval --json .#planner.failures` and confirm `{}`, then `nix build .#checks.x86_64-linux.planner-pytest .#checks.x86_64-linux.planner-perf -L` and confirm both pass
- [x] 5.3 Run `nix fmt` and confirm the only changes are formatting of files this change touched
