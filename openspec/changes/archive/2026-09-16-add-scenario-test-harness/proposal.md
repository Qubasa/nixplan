## Why

The planner's 104 tests are unreadable to the person who has to trust them. A nix-unit test is one `expr` record paired with one `expected` record, so a failure reports that two records differ and leaves the reader to find the field; `tests/suites/resolution.nix` spends twenty lines of nested `expected` on the single fact that an absent generator produces one row. Worse, the deployment under test is not a deployment: it is a call to a combinator. `edge`, `soleRoot` and `fleet` in `tests/suites/resolution.nix` and `tests/suites/sharing.nix` synthesise instances in the argument position of a function, so nobody reading a test ever sees the `instances.nix` that a real fleet would write. Row text is asserted through `support.hasInfix`, a substring search hand-rolled over `genList` in `tests/support.nix:137`, because the language has no regex.

The library already produces the artifact that fixes this. `docs/plan.md` states that a plan is flat, free of expressions, and that `builtins.toJSON` round-trips it, and `tests/fixtures/worked.nix` already loads `fixtures/minimal-typed-edge/` **as committed** rather than synthesising it. The two halves of the answer exist; they have never been put together, and the golden comparison is currently implemented twice — in Nix by `tests/suites/golden.nix` and in Python by `tests/regenerate.py`, over the same fixture.

## What Changes

- **A scenario is a directory, not a function call.** New `tests/scenarios/<name>/` in the shape `examples/` already uses — `interfaces/`, `modules/`, `deployment/instances.nix`, `deployment/machines.nix` — plus one `scenario.nix` whose only job is to close packages and return `mkPlan` arguments, exactly as `tests/fixtures/worked.nix` does today for the worked example.
- **Nix evaluates, Python asserts, JSON is the boundary.** `tests/scenarios.nix` discovers every scenario directory with `readDir` and maps it to its `mkPlan` result. A sandboxed check serialises that with `writeText`, and pytest reads the file. **A check never invokes Nix**: a build sandbox has no daemon and no flake, and Python cannot evaluate Nix, so the existing `nix-unit` arrangement in `flake-module.nix` does not generalise to a Python runner.
- **`nix eval --json .#planner.scenarios` is the iteration path** to the same JSON, so a scenario can be inspected without building anything.
- **New `checks.planner-scenarios`**, pytest over the serialised scenarios, and the first use of pytest in this repository — `perf/check_test.py` uses stdlib `unittest` today.
- **The golden comparison moves to Python**, deleting the duplication between `tests/suites/golden.nix` and `tests/regenerate.py`: one traversal, used both to compare and to regenerate.
- **The layer boundary is written down.** A test about one malformed declaration and the exact text of its row stays in nix-unit; a test about a fleet or about the shape of the artifact belongs to the scenario suite. Without the rule the two suites drift into testing the same thing twice.
- **The specification cross-walk learns to name a pytest test.** `tests/suites/coverage.nix` already accepts an external reference, but `externalExists` hardcodes `perf/check_test.py` and requires a `class` and a `def`; a pytest module has functions and no class.
- **Refusals that raise stay in Nix, by construction.** A refused read leaves the slot out of `results` (`docs/authoring.md`), so forcing the consumer raises a missing attribute that no `tryEval` catches — which is why the consumer in `tests/suites/resolution.nix` records slot *names* instead of values. Such a scenario cannot be serialised at all, and a scenario written defensively enough to serialise would stop looking like a real config. The scenario suite therefore carries the deployments that resolve and the ones whose rows do not poison a value anybody forces.

No **BREAKING** changes. `checks.planner-tests` keeps running, and the tests that move are replaced field for field rather than dropped.

## Capabilities

### New Capabilities

- `tooling/scenario-suite`: how a whole-fleet test is written and run — the directory shape of a scenario, the JSON contract between the evaluating half and the asserting half, which of the two suites a given test belongs to, what a failure has to report, and which scenarios cannot exist because forcing them raises.

### Modified Capabilities

None in `openspec/specs/`, which is empty. The nix-unit contract lives in the unarchived change `implement-minimal-typed-edge` under `specs/tooling/nix-unit-suite/spec.md`; its "Golden comparisons print a usable difference" requirement is satisfied by the Python traversal after this change rather than by `tests/suites/golden.nix`, and its coverage requirement is unchanged in intent and widened in mechanism. Both are recorded in Impact rather than as a delta against a spec that is not yet the source of truth.

## Impact

**New files**
- `tests/scenarios.nix` — `readDir` discovery, one attribute per scenario directory.
- `tests/scenarios/<name>/` — one directory per scenario, `git add`ed before the flake can see it (`docs/tooling.md` already documents that trap).
- `tests/python/conftest.py`, `plan.py`, `test_*.py` — the typed reader over the JSON and the tests themselves.

**Changed files**
- `flake-module.nix` — `flake.planner.scenarios`, the serialised artifact, `checks.planner-scenarios`, and `pytest` in the Python check's inputs.
- `tests/default.nix` — `golden` leaves the nix-unit aggregator.
- `tests/regenerate.py` — regeneration becomes a caller of the shared traversal instead of its own walk.
- `tests/suites/coverage.nix` — `externalExists` accepts `<file>::<name>` for any test file under `tests/`.
- `tests/mapping.nix` — the headings that pointed at `golden.*` point at the pytest tests instead.
- `docs/tooling.md` — the scenario suite, its commands, the layer rule, and the corrected test count.

**Deleted files**
- `tests/suites/golden.nix` — replaced, not deprecated.

**Not affected**
- `lib/` — no library change. The plan and the diagnostics table are already the contract this harness reads; if a scenario cannot be expressed, that is a finding about the subset and not a reason to edit the library.
- `perf/` — budgets are recorded from a Nix evaluation and gated by `perf/check.py`; nothing here moves a counter.
- `examples/` — read by the harness, edited by nobody.
