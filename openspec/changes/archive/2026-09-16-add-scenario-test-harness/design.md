## Context

See proposal.md — Why. What matters for the approach is four facts about the code as it stands.

`checks.planner-tests` runs `nix-unit` inside a build sandbox over a generated entry point (`flake-module.nix`). That works because `nix-unit` is an evaluator reading store paths: it needs no daemon and no flake. **Python cannot be substituted into that arrangement**, because a Python test runner would have to shell out to `nix eval`, and inside a sandbox there is no daemon socket and no flake to evaluate. Any design that has pytest call Nix works in a dev shell and cannot be a check.

`docs/plan.md` states the plan is flat, free of expressions, and round-trips through `builtins.toJSON`. The diagnostics table is a list of flat records. So the artifact needed on the Python side already exists as a promise the library keeps, and no new serialisation format has to be invented.

`tests/fixtures/worked.nix` already loads `fixtures/minimal-typed-edge/` as committed — it imports that folder's own `interfaces/default.nix`, `deployment/instances.nix` and `deployment/machines.nix`, and supplies only the package strings and the `varsState`. The glue for a directory-shaped scenario is therefore a known quantity: about thirty lines, most of it package literals.

A refused read leaves the consuming module without the slot (`docs/authoring.md`), so a module that dereferences it raises a missing attribute. The consumer helper in `tests/suites/resolution.nix` records slot *names* into a unit's environment precisely to avoid this. A scenario built from realistic modules will not have that guard, so the harness has to have an answer for a scenario whose result cannot be forced.

## Goals / Non-Goals

**Goals:**
- A whole-fleet test whose input is a directory a reader recognises as a deployment.
- A failure that names a field, produced by the test runner's own diffing rather than by hand-written comparison code.
- One implementation of the golden traversal, shared by the comparison and the regeneration command.
- A hermetic check: no network, no daemon, no evaluator at test time.

**Non-Goals:**
- Replacing nix-unit. The per-row suite, the source-text check and the specification cross-walk stay in Nix; the source-text check reads Nix files and the cross-walk reads specification headings, so neither has a Python form.
- Snapshot-first testing. The library's argument is *which* row appears and *why*; a snapshot accepts a changed row by regenerating it, which is the failure mode `docs/tooling.md` warns about for the golden fixture.
- Any library change. If a scenario cannot be expressed, that is a finding about the subset.
- Migrating the `plan` suite in this change. It is a candidate, decided after the first scenarios are readable.

## Decisions

### Nix evaluates and serialises; Python only asserts

The evaluating half produces one JSON document per scenario carrying `plan`, `diagnostics` and `applicable`. Two paths reach the same document:

- **Hermetic**: a store file written at evaluation time from the flake attribute, passed to the pytest check as an environment variable. No nested Nix, no daemon.
- **Iteration**: `nix eval --json .#planner.scenarios`, the same attribute, printed to stdout.

The pytest side prefers the environment variable and falls back to the `nix eval` call, so one test file serves both. *Alternative rejected*: pytest invoking `nix eval` always — cannot run as a check, as above. *Alternative rejected*: a Nix-side scenario loader with nix-unit assertions — it fixes the combinator problem but keeps `expr`/`expected` whole-record diffing and the hand-rolled substring search in `tests/support.nix`, which is half the complaint.

### Scenarios live under `tests/scenarios/`, not in `examples/`

`examples/` folders are design-corpus documents: `instance-as-group/` deliberately writes `locality`, `consumers`, `state.per`, port ranges and member cuts, all of which this subset refuses. They are the right thing for the golden fixture to point at and the wrong thing to own test scenarios.

Keeping scenarios inside the flake's tree also settles a purity question: pure evaluation refuses an absolute path outside the store, so a scenario directory reachable only from outside the flake could not be imported at all. The cost is that a new scenario must be `git add`ed before the flake sees it — already documented in `docs/tooling.md` as a trap with a misleading error.

### One `scenario.nix` per directory as the only glue

Discovery is `readDir` over the scenarios directory; each entry must contain `scenario.nix`, a function of `{ planner, folder }` returning `{ args }` — the exact shape `tests/fixtures/worked.nix` already has. It closes the package strings, imports the directory's own modules and interfaces, and supplies `sources`, `interfaces` and `varsState`.

*Alternative rejected*: convention-only auto-wiring, where the harness imports `modules/*/default.nix` and calls `mkPlan` itself. A root is a function whose package arguments only the author knows, and `sources` is per-instance attribution; guessing either would put test-only inference between the reader and the configuration.

### Serialisation per scenario, and a rule instead of a catch

**Settled by measurement (task 1.1, Nix 2.35.2): `tryEval` does not catch it.** A throwaway deployment whose consumer wrote `results.far.publicKey` with nothing wired propagated `error: attribute 'far' missing` straight through `builtins.tryEval (builtins.deepSeq result result)`. `tryEval` catches a `throw` and a failed `assert`; an evaluation error is neither.

**The fallback of the Risks section is therefore adopted (task 1.2).** Two consequences:

- **One store file per scenario.** The artifact is a directory: `index.json`, listing every discovered scenario directory and computed from `readDir` alone so that it evaluates whatever the scenarios do, and one `<name>.json` beside it. A Nix attribute set is lazy per attribute, so a scenario that raises leaves `nix eval --json .#planner.scenarios.<other>` and every other scenario's file untouched. The asserting half fails naming a scenario the index carries and no file backs, and states that the per-row suite is where such a case is asserted.
- **A rule, written down, instead of a catch.** A scenario module must not dereference a slot whose delivery is not guaranteed. The harness cannot contain such a scenario: the directory is one evaluation, a raise inside it takes that evaluation down, and what names the scenario is the trace — the attribute path and the name of the store file being written. The rule goes in `docs/tooling.md` beside the layer rule.

*Alternative rejected*: the original `builtins.tryEval (builtins.deepSeq result result)` wrapper — measured above, it catches nothing and would only hide the trace that does name the scenario.

*Alternative rejected*: one document for all scenarios. A raising scenario takes the evaluation down either way, but with one file per scenario the healthy ones stay individually buildable and inspectable.

### pytest, not stdlib `unittest`

`perf/check_test.py` uses `unittest` today, so pytest is a new dependency in this repository. It earns it: assertion rewriting is what produces "this field of this entry differs" without comparison code, and parametrisation over scenarios keeps one test per behaviour rather than one per fixture. `checks.planner-python` already runs `ruff` and `mypy --strict` over the Python files, so the new files inherit the existing bar; pytest is added to the scenario check's inputs only.

### A typed reader, not dictionaries

A small module of frozen dataclasses — `Plan`, `Entry`, `Capability`, `Export`, `Read`, `Row` — parses the JSON once per session. Assertions then read `plan["pg:main@one"].provides["eu"].exports["dsn"].read_by` and `plan.one_row("set-entry-absent").subject`. This is what makes a test readable, and `mypy --strict` over frozen dataclasses is the repository's stated Python style.

### The golden comparison moves, `golden.nix` is deleted

The traversal — which paths participate, which prose keys (`note`, `why`) are excluded at every depth — becomes one Python function used by the comparison and by `tests/regenerate.py`. `tests/suites/golden.nix` is deleted rather than left in place: two implementations of one comparison is the duplication this change exists to remove. The mapping entries in `tests/mapping.nix` that name `golden.*` tests are repointed at the pytest tests, which requires `externalExists` in `tests/suites/coverage.nix` to accept `<file>::<name>` for any test file under `tests/` — it currently hardcodes `perf/check_test.py` and requires a `class` and a `def`.

### The layer rule, written where the commands are

`docs/tooling.md` gains the rule: *a test about one malformed declaration and the text of its row belongs to the per-row suite; a test about a whole fleet or the shape of the artifact belongs to the scenario suite.* Without it the two suites drift into asserting the same behaviour, and the cross-walk cannot tell which entry to keep.

### An unread scenario fails the suite

A session fixture records which scenarios were requested and compares that against what was discovered, failing at session end and naming the unread directories. Fixtures that nothing asserts are how a test tree rots quietly.

## Risks / Trade-offs

- **`tryEval` does not catch a missing attribute raised under `deepSeq`** — measured, not feared; see the decision above. The fallback is in force: one store file per scenario, and a written rule that a scenario module must not dereference a slot whose delivery is not guaranteed.
- **Two languages, two places to add a test** → the layer rule in `docs/tooling.md`, plus the cross-walk which fails if a mapped test of either layer disappears.
- **The two paths to the artifact could drift** → they are the same flake attribute; the iteration path prints it and the check writes it. A test asserts the check's artifact parses to the same document the attribute evaluates to.
- **A scenario directory is invisible until `git add`** → already a documented trap; the discovery failure names the directory it expected to find `scenario.nix` in.
- **JSON to typed dataclasses under `mypy --strict`** is boilerplate that can drift from the plan's shape → the reader parses lazily and only the fields tests touch; an unknown field is carried through untyped rather than rejected, so a new plan field does not break the reader.
- **The scenario suite is slower than nix-unit** → the whole artifact is produced by one evaluation and parsed once per session; per-test cost is a dictionary lookup. The evaluation is the same order of work the existing suite already does.
- **Test count in `docs/tooling.md` will be wrong again** → it was already stale by two before this change; the count is stated once, beside the command that prints it.

## Migration Plan

1. Verify the `tryEval` mechanism against a raising scenario. **Done: it propagates, and the fallback is adopted.**
2. Land the harness with one scenario (`shared-postgres`, portable from `tests/suites/sharing.nix`) and the `sharing` suite still in place. Both green at this point.
3. Port the golden comparison to Python and prove it reports the same differences as `tests/suites/golden.nix` on a deliberately perturbed fixture, then delete `golden.nix` and repoint the mapping.
4. Delete `tests/suites/sharing.nix` once its two tests read better as scenarios. Rollback at any step is deleting the new files: nothing in `lib/` changes, and the per-row suite is untouched until step 3.
