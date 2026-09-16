## Why

A review of the tree at `9ce69dc` - six read-only passes over `lib/`, the realisers, `cli/`, the
secret path, the test layers and every document - found that the repository states guarantees it does
not hold. This is the same defect class `report-every-refusal-as-a-row` was written for, and the
guarantees at issue are the four the project rests on: `lib/` never raises, the reading is total, an
entry is activated after the entries it reads, and a check that is green has been exercised.

Two findings were reproduced end to end against the committed fixtures, so neither is speculative:

- **A set-valued read produces no ordering edge.** `cli/order.py:131` reads `slot["entry"]`, but
  `lib/plan.nix:227` records a `reach = "all"` read as `entries`, an attrset keyed by provider. Run
  against `fixtures/minimal-typed-edge/plan/backup.json`, `order.walk` returns
  `order = (vault-repo:server@vault, nightly:client@alpha, beta, gamma)` with `broken = ()`: the
  server is activated before all three entries it reads, and because that fixture is genuinely mutual
  the walk should have reported the edge it ordered against. It reports nothing. On a real machine a
  hub that reads every agent with `reach = "all"` starts before its providers.
- **A value entry with no files aborts the reading.** `files` passes through `pruned`
  (`lib/plan.nix:737`), so a generator declaring no files emits an entry with no `files` key, and
  `operator/read.nix:326` reads `entry.files` bare: `error: attribute 'files' missing`, which
  `tryEval` cannot catch. Three lines below the pruning, `delivery` is deliberately kept "always
  present, empty or not" because a reader "must not be able to mistake" it for an absence. The
  reasoning was applied to that field and not to the neighbouring one a reader trusts.

Four more were confirmed at their source and are stated as conditions to reproduce first, not as
facts already observed: a name carrying `@` misroutes a delivery silently, seven readings of the
deployment half raise where the module half rows, an entry that declares no unit is recorded with
`path = null` and refused by the command that reads it, and a staged configuration file holding a
secret exists at the login umask while it is written.

Alongside them, checks that cannot fail: `tests/unit/vars.nix:872` asserts
`unsafeDiscardStringContext s == s`, which is true of every string because Nix equality ignores
context, so the one check on a generator's closure-freedom proves nothing; the e2e provenance guard
compares a record against the values it was just written from; and `perf/check.py` prints
`0 failures` having compared 9 of 81 gated figures when eight result files are missing.

## What Changes

- The activation order takes every read the plan resolved, single- and set-valued alike, so a
  consumer of a `reach = "all"` slot is ordered after every provider in it and a genuine cycle is
  reported rather than silently ordered against.
- The reading of a plan becomes total again: a value entry with no `files`, and every other field the
  plan prunes, is a row naming the entry rather than an abort. **BREAKING** for any caller that
  relies on the current abort as a signal - there is none in this tree.
- `lib/` stops raising on the deployment half of a declaration. Each of the seven confirmed bare
  reads becomes a row, and an export declaring no `type` becomes `export-atom-missing-type` on the
  path where it matters rather than an abort.
- A name is held to a grammar that the key it enters can carry: a machine, instance or member name
  containing `@`, `:` or `/` is a row, so a delivery set is never derived from a key that parses as
  another key.
- An entry that declares no unit is recorded so that every command can read it, and the record's
  shape is stated once for both the producing and the consuming side.
- A staged configuration file is created with its declared mode before any byte of a secret reaches
  it, so no window exists in which it is world-readable and no failure leaves it that way.
- Every check named above either asserts what it claims or is deleted. A budget entry that was never
  measured is refused rather than skipped.
- Every falsifiable claim the documents make is either true or mechanically enforced. Twenty-two are
  currently false; the row table, the field shapes and the recorded counts get a cross-check so the
  next one fails a suite instead of a reader.

## Capabilities

### New Capabilities

None. Every guarantee here is already stated by an existing capability; what is missing is that the
tree holds it.

### Modified Capabilities

- `operator/apply-command`: the order is taken from every resolved read including a set-valued one; a
  refusal a run can make locally is made before the first dial; a step line precedes the step it
  names on the rollback path too; a malformed artifact in a built directory is a refusal.
- `operator/deployment-build`: the reading is total over every field the plan prunes; the record of an
  entry that declares no unit is readable by the command.
- `planner/diagnostics`: the rows for a malformed deployment-half declaration, an export with no
  atom type, a refusal that is not a string, and a name that cannot enter a key.
- `planner/plan-artifact`: a name's grammar as part of key identity, and the fields a reader must not
  be able to mistake for an absence.
- `realiser/portable-service-image`: a staged file carries its declared mode before its bytes.
- `tooling/test-layers`: a check must be capable of failing, and a budget figure that was not
  measured is refused.
- `tooling/repository-shape`: the claims a document makes about row identifiers, field shapes and
  recorded counts are mechanically cross-checked against the tree.

## Impact

- `cli/order.py`, `cli/apply.py`, `cli/manifest.py`, `cli/report.py`
- `lib/plan.nix`, `lib/resolve.nix`, `lib/interface.nix`, `lib/diagnostics.nix`
- `operator/read.nix`, `image/default.nix`
- `tests/unit/{vars,interfaces,operator,perf,coverage,layers,resolution,plan,diagnostics}.nix`,
  `tests/e2e/generation.py`, `tests/e2e/generated-secret/test_generated_secret.py`
- `perf/check.py`, `perf/budgets.json` (new rows and new fields move the recorded cost)
- `docs/README.md`, `docs/plan.md`, `docs/diagnostics.md`, `docs/operator.md`, `docs/tooling.md`,
  `docs/flakelet.md`, `fixtures/minimal-typed-edge/README.md`, `CLAUDE.md`, `treefmt.nix`
- `fixtures/minimal-typed-edge/plan/backup.json`: new rows and a new field re-key entries, so the
  golden is regenerated and the budgets re-recorded.
