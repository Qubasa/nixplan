## Why

A generated value's bytes arrive from nowhere. `varsState` is an argument of `mkPlan`
(`lib/default.nix:87`) that the caller fills in, read once at `lib/resolve.nix:554`, and every
suite and every end-to-end folder supplies it by hand: `tests/e2e/secret-delivery/serve.py` hands
the harness a literal, and `tests/e2e/delivery.py:deliver_value` takes a `files: dict[str, str]`
from the test. So the planner derives *which machines receive which value and why*
(`delivery`, `deliveryDerivedFrom`) over bytes nothing generated, stored, encrypted or rotated.

The other half exists and is under review: NixOS vars, nixpkgs PR
[#547171](https://github.com/NixOS/nixpkgs/pull/547171), head
`e6af758a5745ac4adef763deb0f1771cec58c461`. It has generator scripts, dependency ordering, prompts,
garbage collection and a store-backend contract (`get`, `set`, `exists`, `delete`, `list`, `fixup`,
`deploy.local`, `deploy.remote`), and it has **no machine dimension at all**: its unit of work is
one configuration, and its own module text concedes that a backend spanning machines must scope
`list` itself or the CLI will delete the other machines' files.

The two halves join at a seam neither project invented for the other:

| this library | nixos-secrets at `e6af758` |
| --- | --- |
| `varsState.<key>.<file> = { present, content }` | `exists` (exit 0 or 42) and `get` (bytes to `$out`) |
| `plan.<key>.delivery`, `.files.<f>.path` | `deploy.remote`, given a file list and nothing else |
| a plan | `_type = "secrets-configuration"`, which `--json` consumes without evaluating Nix |

## What Changes

- **A generator gains the one field it is missing: the program that produces it.**
  `generatorKeys` in `lib/module.nix:118-123` is `files`, `per`, `deploy`, `reads`, and a
  `nightly:vars/hostKey@alpha` entry of the worked plan carries `delivery`,
  `deliveryDerivedFrom`, `dependsOn`, `deploy`, `files`, `key`, `per` - so **nothing in a plan
  says how a value's bytes come to exist**, while the external contract requires a store
  derivation per store entry. `vars.<gen>` gains that store path, the entry carries it, and the
  planner still neither runs nor reads it. Omitting it stays valid: the library described values
  before anything could produce them, and it is the reader wanting a program that refuses, not
  the planner.
- **The program is not a closure root.** A generator runs where the plan is read, never on a
  machine that receives its output, so it is exempt from the scan that holds every other store
  path in the plan to a declared closure. Making it a root would ship every deployment's
  generators to every machine.
- **A fourth realiser, `secrets/`.** `secrets/read.nix` reads one plan and produces a
  `SecretsConfiguration` - the JSON object `secrets-config.schema.json` describes at the pinned
  revision - so the CLI needs no NixOS configuration and no module system to run against a plan.
- **The machine dimension is closed by generating the deploy script.** The schema carries no path
  and `deploy.remote` receives a file list and no target, so `secrets/backend.nix` renders that one
  script *from the plan*: for each projected name, the machines of the value's `delivery` set, each
  machine's address out of its machine entry, and the `path` the plan already fixed. nixos-secrets
  keeps generation and storage; this library keeps targeting. No change to nixpkgs is required.
- **A name projection with a refusal, not a mangling.** A plan key is `<instance>:vars/<gen>` or
  `<instance>:vars/<gen>@<machine>`; a `safe-name` is `^[a-zA-Z0-9:_\.-]+$`, which admits a colon
  and admits neither `/` nor `@`. The projection is `<instance>:<gen>` and `<instance>:<gen>:<machine>`,
  and a component already carrying a colon, or two entries projecting onto one name, is an error row
  naming both entries - never a silent overwrite of one instance's secret by another's.
- **`reads` becomes `dependencies`** under the same projection, so the CLI's topological order is
  the order the planner already resolved and checked for cycles.
- **The bytes of a secret never reach the operator's plan.** The driver calls `exists` for every
  declared file and `get` only for a file whose atom is `public`. A secret file's `content` is
  already `null` by construction (`lib/resolve.nix:571`); this makes it true of the process too.
- **A stale value is a refusal, not a success.** The CLI has no provenance: an interrupted or failed
  run leaves a dependency new and its consumer old, and the next invocation reports success
  (PR review `r3821143332`). The driver records, beside the state it read, the plan key hash each
  value was generated from, and refuses a run whose recorded hash disagrees with the plan's -
  naming the value and the two hashes.
- **A guard that fails when upstream fixes it.** The projection is written against one revision's
  schema. A check compares the pinned `secrets-config.schema.json` against the one the resolved
  flake carries and fails naming the file to edit, so a merged and renamed API cannot be silently
  outlived.
- **The end-to-end layer stops fixturing bytes.** A new folder, `tests/e2e/generated-secret/`,
  boots three machines and generates its token with a real `age` store backend on the operator side.
  The delivery-set assertions are the existing ones: the reader authenticates with the delivered
  file, the third machine holds nothing, no artifact carries the bytes.
- The `secrets` unit suite is renamed `vars`, freeing the realiser's own directory name for the
  suite that reads it, as `image` and `flakelet` already do.

## Capabilities

### New Capabilities

- `realiser/secrets-configuration`: what a plan becomes when it is read as a nixos-secrets
  configuration - the store entries, the name projection and its refusals, the generated
  `deploy.remote` backend, and what the reading refuses outright.
- `delivery/generated-values`: the operator-side driver - how `varsState` is obtained from a
  backend, which files it may read the bytes of, how generation is invoked, and what makes a run
  refuse rather than report success.

### Modified Capabilities

- `delivery/real-cluster`: the machine layer's "no test double" requirement gains the generator.
  A value's bytes are produced by a real backend on the operator side rather than written by the
  test, and the run's own artifacts still carry none of them.
- `planner/secret-delivery`: a generator may declare the program that produces it, and omitting it
  stays valid.
- `planner/plan-artifact`: a value's entry carries that program, and the program is a mention the
  closure scan does not hold against a declared closure.

No `tooling/*` capability changes. A fourth realiser directory and a new suite are already what
`tooling/repository-shape` and `tooling/nix-unit-suite` require of any addition; this change
exercises those rules rather than altering them.

## Impact

- **New**: `secrets/read.nix`, `secrets/backend.nix`, `tests/unit/secrets.nix` (the realiser's
  suite), `tests/e2e/generation.py`, `tests/e2e/generated-secret/`, `docs/secrets.md`.
- **Renamed**: `tests/unit/secrets.nix` (the vars suite) to `tests/unit/vars.nix`.
- **Modified**: `tests/default.nix` (suite registration), `tests/unit/layers.nix` (`classOf`),
  `tests/unit/coverage.nix` (`accountable`), `flake-module.nix` (`e2eArtifactPaths`, the folder's
  artifacts, the guard check), `treefmt.nix` (the mypy root for the new folder),
  `docs/{README,cluster,tooling}.md`, `README.md`, `CLAUDE.md`.
- **External dependency**: the nixos-secrets CLI, resolved at run time from `$NIXOS_SECRETS_FLAKE`
  the way `tests/e2e/runner.py:resolve_rookery` resolves rookery, not added as a flake input. An
  unresolvable flake skips the folder with a reason, as an absent `PLANNER_*` path already does.
- **`lib/` changes**, in two places and no more: `generatorKeys` and the program's shape in
  `lib/module.nix`, and the entry field and closure-scan exemption in `lib/plan.nix`. Everything
  else this change adds is a fact about bytes on disk, which the library cannot see and gains no
  field for. `lib/` stays total: a malformed program is a row, and an omitted one is not.
- **Known upstream defects this change inherits and does not fix**: garbage collection keyed on
  `networking.hostName` colliding across checkouts (`r3820900132`), `--file` and `--flake` deriving
  different secret paths (`r3820972963`), and the absent rollback above. Each is recorded in
  `design.md` with the review comment it came from.
