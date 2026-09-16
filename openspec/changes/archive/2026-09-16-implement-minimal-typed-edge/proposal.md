## Why

`fixtures/minimal-typed-edge/` argues that five constructs change an outcome on a target that already exists, and it argues it entirely on paper. `korora.interface`, `provides`, `uses`, `wire` and `reach` exist in no tree, `plan/backup.json` and `plan/diagnostics.txt` were written by hand, and the claim they rest on is that a set-valued read naming its entries produces a row where a fold produces a shorter list. Nothing has run.

The folder also states why prose is the wrong medium for this particular claim. `posts/07-reading-real-fleets.md` measures adoption of three mechanisms in one repository written by people who agreed the typed edge was the better idea: the checked producing half has nine services, the declared-only consuming half has two, and the untyped path carries 34 call sites. Types get used in proportion to what enforces them. A consumer-side check that exists only in a design note enforces nothing, so the first thing to build is the thing that does the refusing.

Performance and tests are in this change rather than after it for the same reason. `posts/05-probes-in-the-graph.md` commits the planner to being "fast enough to run on every keystroke in a user interface", and nobody has measured what that costs today. A budget added to a library that already evaluates a fleet is a budget fitted to whatever the library happens to cost.

## What Changes

- **New the repository root source tree**, a pure-Nix library evaluating a deployment into a plan and a diagnostics table. `mkPlan { interfaces, instances, machines }` returns `{ plan, diagnostics }` and realises nothing.
- **The five constructs become code.** An interface is an imported value whose `name` is a diagnostic label with no matching authority. An export atom is `{ type, secrecy }`. `provides.<cap>` declares an interface, `uses.<slot>` declares `{ interface, reach, reads }`, and `wire.<slot>` names `{ instance, provides }` in the deployment.
- **Three checks the target cannot state become refusals.** A `reads` entry naming an export whose `secrecy` is `secret` is refused outright. A provider's export keyset must equal its interface's keyset, so an omission and an extra are both rows and no superset satisfies a narrower slot. A slot's `reach` is checked against the placements of the wired capability, so `one` against two placements is a row naming the slot and both placements.
- **Evaluation never throws.** Every check returns a diagnostic record. `korora.verify` returns null-or-string and is the only entry point the library uses; `korora.check` throws and is banned in library source by a test.
- **The folder's hand-written plan artifacts become the acceptance fixture.** Evaluating `fixtures/minimal-typed-edge/deployment/` must reproduce `plan/backup.json` and the row set of `plan/diagnostics.txt`, including the `gamma` error row that blocks the apply and the re-keying warning beside it.
- **nix-unit suite** at `tests/`, run through `pkgs.nix-unit` from the pinned nixpkgs. Covers each construct, each of the five counterfactual rejections the folder writes out, the golden plan, and one property test asserting that a deployment carrying every authoring mistake at once still returns a diagnostics list under `builtins.tryEval` over a `deepSeq` of the whole plan.
- **Evaluation-performance harness** at `perf/`, with budgets committed in the first commit that adds the library. Gates on deterministic `NIX_SHOW_STATS` counters, reports wall clock as advisory, and asserts a growth bound across a synthetic fleet at four sizes so that a quadratic in `reach = "all"` resolution fails the build rather than the demo.
- **New flake input `korora`**, pinned by revision because upstream publishes no tags. `nix-unit` needs no input: it is already in the pinned nixpkgs at 2.35.1.
- **Two atom types the library owns.** `url` and `secretRef` appear in `interfaces/exports.nix` and exist in korora under neither name, so the library defines them with `korora.typedef` and the folder's declaration becomes evaluable as written.

Scope decisions recorded here because each one narrows what follows.

- **`§32.1` is not narrowed.** The library implements a two-field export because that is what the subset needs, and `§32` stays ADOPTED with its quadruple. The six sibling folders keep their atom tables. The library refuses a `locality` or `lifecycle` key on an atom with a row naming the trigger that would add it, rather than accepting and ignoring it.
- **Plan artifacts only.** Package inputs arrive as fixture store path strings, `impl`'s `units` and `configData` are recorded as plan data, and no derivation is built. This is the line `posts/02-the-deployment-plan.md` draws.
- **The clan-core conversion is a follow-on.** The README's falsifiable claim needs a clan-core checkout and an upstream change this repository cannot gate on.

No **BREAKING** changes. `openspec/specs/` is empty, the six sibling example folders are untouched, and no section of `notes/clan-portable-services-design.md` changes status.

## Capabilities

### New Capabilities

- `planner/typed-edge`: the five constructs and what each one refuses. Interface identity by value, the export atom's two fields and the omission rule, capability re-export and `exposes`, wire resolution across an instance boundary, keyset equality at the provider, the secrecy rule over `reads`, and `reach` checked against readable placements.
- `planner/diagnostics`: evaluation is total. The diagnostic record's fields, the two severities and what each one does to an apply, the rule that no library path calls `throw`, and the rendering that produces the row format `plan/diagnostics.txt` already uses.
- `planner/plan-artifact`: what a plan entry contains and how its key is derived, the split between hashed `env` and unhashed prose, the `configData` reload plane, how an absent value is recorded rather than dropped, and the requirement that the folder's deployment reproduce its committed fixture.
- `tooling/evaluation-performance`: which counters gate and which report, budgets expressed per plan entry, the ratchet that refuses a stale budget in either direction, and the growth bound over a synthetic fleet.
- `tooling/nix-unit-suite`: how tests are laid out and run, the coverage obligation tying each spec scenario to a named test, and the total-evaluation property test.

`planner/` is the grouping `add-collect-slot-chain-rules` established for the deployment planner. `tooling/` is new and holds capabilities about this repository's own build rather than about a deployment.

### Modified Capabilities

None. `openspec/specs/` contains no specs today.

## Impact

**New source**

- `lib/` — the library. Entry point plus modules for interfaces and atoms, the module schema, composition, resolution, diagnostics and plan emission.
- `tests/` — nix-unit suites and fixtures, including the completed golden plan.
- `perf/` — synthetic fleet generator, measurement harness, committed budgets, and the checker that compares against them.
- `docs/` — how to use the library: the entry point and a worked minimal example, authoring interfaces, modules, roots and deployments, the diagnostics reference, the plan artifact contract, and the commands. `tests/suites/source.nix` asserts the diagnostics reference tabulates every row identifier the library emits and no identifier it does not.
- `flake-module.nix` — imported by `flake.nix` beside `pkgs/qubasa-blog/flake-module.nix`.

**Modified**

- `flake.nix` — the `korora` input and the new flake module import.
- `flake.lock` — one added node.
- `treefmt.nix` — unchanged. the repository root is formatter-clean and needs no exclusion. `treefmt.nix` configures no Python formatter at all, so `check.py`, `check_test.py` and `regenerate.py` are held to `ruff format`, `ruff check` and `mypy --strict` by `checks.<system>.planner-python` instead of by a claim; the measurement harness is shell and the existing `shellcheck` covers it.

**Design record**

- `notes/clan-portable-services-design.md` — no section changes status. The library is the first implementation of constructs `§28` and `§31` adopted, and `§32` is implemented in the narrowed form the example folder proposes, which the folder already records as an open gap against `universe-k8m`.
- `fixtures/minimal-typed-edge/plan/backup.json` — regenerated with all eight entries the deployment produces, because a fixture cannot elide what the evaluator produces. The `elided` block and its reasoning move to the README, where the argument for eliding them still holds for a reader.
- `fixtures/minimal-typed-edge/plan/diagnostics.txt` — the two row messages of this deployment are replaced by what the library renders. Subject and severity already matched, and the prose under each row is untouched.
- `fixtures/minimal-typed-edge/README.md` — the `Files` table's `backup.json` row is recounted, the opening claim that the folder is not executable is replaced by where the planner and the regeneration command are, and the `elided` block's reasoning lands in `What it produces`.
- `openspec/changes/implement-minimal-typed-edge/reconciliation.md` — the field-by-field comparison of the hand-written plan against the produced one, every difference in exactly one of placeholder, correction to the folder, and defect in the library.

**Beads**

- `universe-bki` owns this change, and carries the reconciliation outcome as a note.
- `universe-dpr` is opened by this change and depends on `universe-bki`: the clan-core conversion the README's falsifiable claim names.
- Related and untouched: `universe-k8m` (`§32`, still owes the narrowing), `universe-28p` (`§31` reach), `universe-qja` (typed slots), `universe-dse` (machine-scoped collect slots, which is the read this subset cannot express).

**Not affected**

- The blog series. It is closed at seven parts and this change adds no post and edits none.
- The six sibling example folders.
- `pkgs/qubasa-blog/`.
