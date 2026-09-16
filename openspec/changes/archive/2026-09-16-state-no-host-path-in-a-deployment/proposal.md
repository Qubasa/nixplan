## Why

A deployment is what an operator writes, and a host path is not something an operator knows. The
machine layer currently asks for one seventeen times. Two of them are in files an operator would
edit - `tests/e2e/secret-delivery/deployment/instances.nix:18` and
`tests/e2e/shared-postgres/deployment/instances.nix:34,50,66` - and the rest are literal defaults in
module compositions (`tests/e2e/wired-pair/deployment/modules/probe/default.nix:10`,
`.../sweep/default.nix:7`, `tests/e2e/generated-secret/deployment/modules/{probe,idle}/default.nix`,
`tests/e2e/portable-image/deployment/default.nix:14-16`,
`tests/e2e/newcomer/template/deployment/modules/hello/default.nix:8`). Each one is a fact the module
already has and is asking somebody else to restate, and each is a path two instances of that module
on one machine would both claim.

The same restatement happens one layer up: a test writes the path out again as a constant
(`tests/e2e/secret-delivery/test_secret_delivery.py:68`,
`tests/e2e/generated-secret/test_generated_secret.py:68`,
`tests/e2e/portable-image/test_portable_image.py:71-72`,
`tests/e2e/newcomer/test_newcomer.py:89`, `tests/e2e/shared-postgres/test_shared_postgres.py:77-82`).
A test that writes the path its deployment writes proves that two files agree with each other. A test
that reads the path out of the plan proves the deployment put it where the machine will look, which
is the claim worth making, and it goes red when a module's derivation breaks rather than silently
asserting the old convention.

Nothing in the repository states this rule, so every new folder re-decides it. `README.md:17-20`
states the goal the rule serves - instances are instantiable more than once - and says nothing about
how a path gets to a unit.

## What Changes

- **The rule is written down in `README.md`**: a deployment states intent, never plumbing. A host
  path a unit needs is derived by the module from its own identity (`instance` and `member`) or
  reaches it through an export and a wire. No `instances.nix` carries one, and a test that has to
  assert one reads it off the plan.
- **`tests/unit/layers.nix` holds the rule mechanically**, in two checks:
  - no `.nix` file under any folder's `deployment/` carries an interpolation-free host path - a
    quoted string whose first segment is one of the machine's own roots (`etc`, `var`, `run`, `srv`,
    `opt`, `tmp`, `usr`, `home`, `root`, `nix`). A URL path such as
    `tests/e2e/wired-pair/deployment/default.nix:22`'s `"/index.html"` is not a host path and stays;
  - no folder's `test_*.py` carries a host path that the folder's own `deployment/` also carries. A
    path the test alone knows - a fake root such as `portable-image`'s `/run/planner-assembly`, or a
    path the machine refuses such as `newcomer`'s `/opt/vendor/greeter` - is the test's own claim and
    stays.
- **Every folder is brought to the rule.** `wired-pair`, `secret-delivery`, `generated-secret`,
  `portable-image` and `newcomer`'s template derive their record, marker, greeting, shown and
  assembled paths from `instance` and `member`; the `recordPath`, `markerPath` and `greetingPath`
  knobs are deleted rather than defaulted, since nothing states them any more; and each folder's test
  reads the path out of the plan it built.
- **The documented example moves with it.** `tests/e2e/newcomer/template/deployment/modules/hello/greet.nix`
  is shown in `docs/README.md` byte for byte (`tests/unit/layers.nix:386-404`), so the derivation is
  what a reader outside this repository is shown first.
- **No library change.** The identity a module derives from is `instance` and `member` in the
  implementation arguments; `member` arrives with
  `openspec/changes/refuse-two-entries-claiming-one-host-resource`, and that change's rows are what
  catch a collision the rule is meant to prevent.

## Capabilities

### New Capabilities

<!-- none: both halves belong to capabilities that exist -->

### Modified Capabilities

- `tooling/repository-shape`: the root document states how a host path reaches a unit, and the rule is
  asserted rather than remembered.
- `tooling/test-layers`: no deployment of the machine layer states a host path, and no test restates
  one its deployment carries.

## Impact

- `README.md`: the rule, beside the design goals it serves.
- `tests/unit/layers.nix`: the two checks and the host-root list they read; the literal from
  `README.md` the rule is asserted by.
- `tests/e2e/wired-pair/deployment/modules/{probe,sweep}/default.nix`, `.../modules/probe/client.nix`,
  `.../modules/sweep/job.nix`: derived paths, knobs deleted.
- `tests/e2e/secret-delivery/deployment/instances.nix`, `.../modules/{probe,idle}/**`: the same, and
  one deployment statement deleted.
- `tests/e2e/generated-secret/deployment/modules/{probe,idle}/**`: the same. The folder evaluates its
  plan twice (`deployment/args.nix`, `deployment/default.nix`), and a derived path is a function of
  the entry rather than of `varsState`, so both readings still agree.
- `tests/e2e/portable-image/deployment/default.nix` and its two modules: the shown, assembled and
  quiet paths derived. The folder's own subject is what an image is shown, so its test keeps asserting
  the path - read from the plan's `configData` keyset and the entry's recipe rather than written out.
- `tests/e2e/newcomer/template/deployment/modules/hello/{default.nix,greet.nix}` and `docs/README.md`:
  the derivation and the document that shows it, kept byte-equal. `tests/e2e/newcomer/test_newcomer.py`
  reads the greeting path out of the plan the workstation built, which is one more command on the
  workstation and no new host-side computation.
- `tests/e2e/*/test_*.py`: path constants deleted in favour of plan reads.
- `tests/unit/coverage.nix`: this change's two spec files in `accountable`.
- `CLAUDE.md`: the rule as an invariant, and the two checks that hold it.
- Nothing under `lib/`, `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes, and no
  golden plan moves: `fixtures/` is not the machine layer and is excluded from the checks by scope.
