## 1. Settle the serialisation mechanism

- [x] 1.1 Write a throwaway deployment whose consumer dereferences a slot that did not deliver, and confirm from a `nix eval` whether `builtins.tryEval (builtins.deepSeq result result)` returns `{ success = false; }` or propagates; record the answer in design.md under Decisions
- [x] 1.2 If it propagates, adopt the fallback from design.md — one store file per scenario plus a documented rule that a scenario module must not dereference a slot whose delivery is not guaranteed — and note the switch in design.md before writing any harness file

## 2. The evaluating half

- [x] 2.1 Add `tests/scenarios.nix`: `readDir` discovery over `scenarios/`, each directory imported through its `scenario.nix` as a function of `{ planner, folder }` returning `{ args }`, mapped to `{ plan, diagnostics, applicable }` wrapped by the mechanism task 1 settled; verify `nix eval --json .#planner.scenarios --apply builtins.attrNames` lists the directories
- [x] 2.2 Expose `flake.planner.scenarios` in `flake-module.nix` and a `pkgs.writeText` artifact carrying the serialised document; verify `nix build .#packages.x86_64-linux.planner-scenarios-json` produces a file that `jq` parses
- [x] 2.3 Add a scenario-shaped failure for a directory missing `scenario.nix`, naming the directory and the file it expected; verify by adding an empty directory, observing the message, and removing it

## 3. The first scenario

- [x] 3.1 Create `tests/scenarios/shared-postgres/` with `interfaces/default.nix`, `modules/postgresql/{default.nix,cluster.nix}`, `modules/app/{default.nix,server.nix}`, `deployment/machines.nix`, `deployment/instances.nix` and `scenario.nix`, porting the fleet from `tests/suites/sharing.nix`; `git add` the directory and verify `nix eval --json .#planner.scenarios.shared-postgres.diagnostics` is `[]`
- [x] 3.2 Confirm the ported scenario's plan matches the values the nix-unit tests assert today — the two dsns, both `readBy` lists, the single `pg:main@one` entry and `dependsOn` — by reading them out of `nix eval --json .#planner.scenarios.shared-postgres.plan`

## 4. The asserting half

- [x] 4.1 Add `tests/python/plan.py`: frozen dataclasses for `Plan`, `Entry`, `Capability`, `Export`, `Read`, `Row`, with `services()`, `rows(id=...)`, `one_row(id)` and unknown fields carried through untyped; verify `mypy --strict` passes on the file
- [x] 4.2 Add `tests/python/conftest.py`: a session fixture that loads the artifact from `$PLANNER_SCENARIOS` and falls back to `nix eval --json .#planner.scenarios`, records which scenarios each test requested, and fails at session end naming any discovered scenario nothing requested; verify by requesting no scenario in a scratch test and observing the named failure
- [x] 4.3 Add `tests/python/test_shared_postgres.py` asserting the sharing behaviours as separate tests — one database per application, disjoint `readBy`, the single cluster entry, the off-machine read under `reach = "one"`, and the wire adding no `dependsOn` edge; verify all pass against the artifact
- [x] 4.4 Add a test for the unserialisable case that task 1 settled: a scenario recorded as not serialisable fails naming itself and naming the per-row suite as its home, while the other scenarios still assert; verify with a deliberately raising scenario, then decide from the outcome whether it stays committed or is deleted

## 5. Wire it into the checks

- [x] 5.1 Add `checks.planner-scenarios` to `flake-module.nix`: pytest over the copied Python files with `PLANNER_SCENARIOS` pointing at the `writeText` artifact; verify `nix build .#checks.x86_64-linux.planner-scenarios -L` passes and its build log shows no network or evaluator use
- [x] 5.2 Add the new Python files to `checks.planner-python` and verify `nix build .#checks.x86_64-linux.planner-python -L` passes `ruff format --check`, `ruff check` and `mypy --strict` over all of them
- [x] 5.3 Assert that the two paths to the artifact agree: a test comparing the parsed `$PLANNER_SCENARIOS` document against the document `nix eval` prints, skipped when no evaluator is available; verify it passes in a dev shell and skips inside the check

## 6. Move the golden comparison

- [x] 6.1 Extract the golden traversal into `tests/python/golden.py` — which paths participate, prose keys (`note`, `why`) excluded at every depth, differences reported as paths — and verify it reports zero differences against the committed `fixtures/minimal-typed-edge/plan/backup.json`
- [x] 6.2 Rewrite `tests/regenerate.py` to call that traversal instead of walking the plan itself; verify a run leaves `backup.json` byte-identical on an unchanged tree
- [x] 6.3 Add pytest tests replacing the seven tests of `tests/suites/golden.nix`, and prove equivalence by perturbing one field of one entry in the fixture and checking the Python failure names the same entry and field the Nix test named; restore the fixture afterwards
- [x] 6.4 Delete `tests/suites/golden.nix`, remove it from `tests/default.nix`, and verify `nix eval --json .#planner.failuresBySuite` is empty for every remaining suite

## 7. Close the cross-walk

- [x] 7.1 Generalise `externalExists` in `tests/suites/coverage.nix` to accept `<file>::<name>` for any test file under `tests/`, keeping the `<file>::<class>::<name>` form working for `perf/check_test.py`; verify both forms resolve and a misspelled name fails
- [x] 7.2 Repoint the `golden.*` entries in `tests/mapping.nix` at the pytest tests; verify `nix eval --json .#planner.failuresBySuite.coverage` is `[]`
- [x] 7.3 Break one mapping entry on purpose and confirm the coverage check names it, then restore it

## 8. Documentation and cleanup

- [x] 8.1 Add the scenario suite to `docs/tooling.md`: how to run it, how to add a scenario directory, the `git add` trap, and the corrected nix-unit test count read from the check's own output
- [x] 8.2 Write the layer rule in `docs/tooling.md` beside the commands — one malformed declaration and its row text belongs to the per-row suite, a fleet or the artifact's shape belongs to the scenario suite
- [x] 8.3 Delete `tests/suites/sharing.nix` and its aggregator entry once the scenario tests cover both of its tests, and verify no coverage mapping entry referenced them
- [x] 8.4 Run `nix fmt` over the changed Nix files only, then verify `nix build .#checks.x86_64-linux.planner-tests -L`, `.#checks.x86_64-linux.planner-scenarios -L`, `.#checks.x86_64-linux.planner-python -L` and `.#checks.x86_64-linux.planner-perf -L` all pass
