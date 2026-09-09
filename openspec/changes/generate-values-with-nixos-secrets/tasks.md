# Tasks

Ordered end-to-end first: the folder that proves the composition is written before the library field
and the reading that satisfy it, so the target is a run rather than a shape. Tasks 1.x are expected
to fail until 3.x and 4.x land, and each states the failure it should be showing.

## 1. The machine layer

- [ ] 1.1 Write `tests/e2e/generated-secret/deployment/` - three machines (`alpha`, `beta`,
  `gamma`), one instance whose module declares a `per = "instance"` generator with a secret file and
  a public file, a consumer module on `beta` declaring a read of the secret export, and a service on
  `gamma` that declares neither. Verify with
  `nix eval --json '.#packages.x86_64-linux.planner-e2e-generated-secret.passthru.plan.diagnostics'`
  returning `[]`.
- [ ] 1.2 Add the generator script package the deployment declares, producing both files under
  `$out` from `$prompts` never and `$in` never, and verify it builds and writes exactly the two
  declared file names.
- [ ] 1.3 Write `tests/e2e/generated-secret/artifacts.nix` rendering the plan, the flakelet
  artifacts of each placed entry, and the `SecretsConfiguration` JSON, following
  `tests/e2e/secret-delivery/artifacts.nix`. Verify `nix build .#planner-e2e-generated-secret`
  succeeds once 3.x exists, and until then fails naming the missing reading rather than a Nix error.
- [ ] 1.4 Write `tests/e2e/generated-secret/test_generated_secret.py` with the cluster stage, one
  test per scenario of `delivery/generated-values` and the new scenario of `delivery/real-cluster`.
  Verify each test name matches its scenario heading under `test_<snake_case>`.
- [ ] 1.5 Add the folder to `flake-module.nix` (`e2eArtifactPaths`, `packages.planner-e2e-generated-secret`)
  and `treefmt.nix`'s mypy roots. Verify `nix run .#planner-e2e -- nosuchfolder` still refuses and
  `nix run .#planner-e2e` lists three folders.

## 2. The operator-side driver

- [ ] 2.1 Add `tests/e2e/generation.py` with a pure half: given a `SecretsConfiguration` and a
  backend's answers, build the `varsState` argument. Verify with pure tests in
  `tests/e2e/test_harness.py` covering a held file, an unheld file and an unreadable status.
- [ ] 2.2 Implement the backend calls: `exists` per declared file, `get` only where the plan records
  the file public. Verify a test asserts `get` is never invoked for a secret file and that no secret
  byte appears in the built state.
- [ ] 2.3 Implement generation: resolve the tool from `$NIXOS_SECRETS_FLAKE` with `--refresh` the way
  `runner.py:resolve_rookery` does, invoke `generate`, and fail naming the value on a non-zero exit
  or on declared files still unheld. Verify by pointing the folder at a generator that exits 1 and
  observing the named failure.
- [ ] 2.4 Implement the provenance record and comparison per design D5: write each stored value's
  plan key beside the state, and refuse the run naming the value and both identities on a
  disagreement or an absent record. Verify with a test that edits a declaration, regenerates only
  the dependency, and asserts the refusal.
- [ ] 2.5 Probe the sandbox `bubblewrap` needs and skip the folder with a reason naming the missing
  kernel feature. Verify the skip reason is printed by `pytest.ini`'s `-rs`.
- [ ] 2.6 Declare a prompt backend that fails on any invocation. Verify a configuration that would
  ask a prompt fails naming the value rather than blocking.

## 3. The declaration

- [ ] 3.1 Add the program to `generatorKeys` in `lib/module.nix`, with a row for a declaration that
  is not a store path and no row for an omitted one. Verify with three nix-unit tests in the `vars`
  suite: a declared program, an omitted one, a malformed one.
- [ ] 3.2 Carry the program on the value's entry in `lib/plan.nix`, absent where none was declared.
  Verify a nix-unit test reads it off the entry and a second asserts an entry without one carries
  no such key.
- [ ] 3.3 Exempt the program from the closure scan in `lib/plan.nix`. Verify a nix-unit test that a
  declared program produces no undeclared-mention row and appears in no entry's closure.
- [ ] 3.4 Confirm the worked fixture declares no program, so the golden plan and
  `fixtures/minimal-typed-edge/plan/diagnostics.txt` are unchanged. Verify
  `plan.testTheGoldenPlanMatches` and `plan.testAGoldenFixtureDrifts` pass without regenerating
  either file.

## 4. The reading

- [ ] 4.1 Add `secrets/read.nix`: one store entry per generated value of a plan, its declared files,
  `dependencies` from the value's reads, `prompts = {}`, the declared program, and
  `_type = "secrets-configuration"`. Verify the output validates against the pinned revision's
  schema, read from the resolved tool rather than from a copy.
- [ ] 4.2 Implement the name projection and its three refusals - a colliding pair, a component
  carrying the separator, a component outside `safe-name` - each naming both sides. Verify one
  nix-unit test per refusal.
- [ ] 4.3 Mark an undeployed value's files as not to be deployed, and refuse an entry with no
  program naming the entry and the field. Verify with two nix-unit tests.
- [ ] 4.4 Add `secrets/backend.nix` rendering `deploy.remote` from the plan: per file, the delivery
  set's machines, their recorded addresses and the path the plan fixed. Refuse a delivery target the
  plan gives no address for. Verify a nix-unit test asserts the rendered script names exactly the
  delivery set and carries none of the plan's bytes.
- [ ] 4.5 Record the pinned revision and the digest
  `sha256:44408bcdca7e59af6f9f05e4fe30ef6aa6df004f97e3df68d8e8d2062a4876cf`, and add the guard
  check comparing it against the digest of the resolved tool's `secrets-config.schema.json`,
  failing loudly with `secrets/read.nix`, the revision and the upstream path to diff, and not
  failing when the tool is unresolvable. Verify by pointing `$NIXOS_SECRETS_FLAKE` at a revision
  with a different schema and observing the named failure, then at nothing and observing the check
  pass.

## 5. Registration and naming

- [ ] 5.1 Rename the `secrets` unit suite to `vars`: `tests/unit/secrets.nix` to
  `tests/unit/vars.nix`, its entry in `tests/default.nix`, and the suite table in
  `docs/tooling.md`. Verify `nix eval --json '.#planner.suites' --apply 'builtins.attrNames'` lists
  `vars` and no `secrets` until 5.2.
- [ ] 5.2 Add `tests/unit/secrets.nix` for the reading and register it in `tests/default.nix`.
  Verify `nix build .#checks.x86_64-linux.planner-tests` runs it.
- [ ] 5.3 Add `secrets` to `classOf` in `tests/unit/layers.nix` as a realiser. Verify
  `layers.testEveryTopLevelEntryBelongsToAStatedClass` passes.
- [ ] 5.4 Register the five spec files in `accountable` in `tests/unit/coverage.nix`. Verify
  `coverage.testEverySpecificationIsClassified` and `coverage.testAScenarioGainsNoTest` pass.

## 6. Documentation

- [ ] 6.1 Write `docs/secrets.md`: the seam, the projection, the rendered deploy script, the pinned
  revision and the guard, and the upstream defects the composition inherits with their review
  comments. Verify it is named from `docs/README.md`'s reading order and that
  `layers.testAFileNamesAPathThatIsNotThere` passes.
- [ ] 6.2 Document the program field in `docs/authoring.md` and `docs/plan.md` - the declaration
  table and the entry's field table - and name the new directory and the third folder in
  `README.md`, `docs/README.md`, `docs/cluster.md` and `docs/tooling.md`. Verify the literal
  assertions in `tests/unit/layers.nix` pass.
- [ ] 6.3 Add the invariants to `CLAUDE.md`: the program is recorded and never run, it is no
  closure root, the projection and its refusals, the path's single owner, provenance living in the
  driver, and the pinned revision with where its guard is. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included.

## 7. Verification

- [ ] 7.1 `nix build -L .#checks.x86_64-linux.planner-tests` - every suite, including the renamed
  `vars` and the new `secrets`.
- [ ] 7.2 `nix build -L .#checks.x86_64-linux.planner-perf .#checks.x86_64-linux.planner-perf-checker` -
  re-record `perf/budgets.json` only if the added field moved a counter, and state why in the
  `note` field.
- [ ] 7.3 `nix run .#planner-e2e generated-secret` - the new folder against real machines, with a
  real generator and a real store backend.
- [ ] 7.4 `nix run .#planner-e2e` - all three folders, and `nix build -L .#checks.x86_64-linux.treefmt`.
