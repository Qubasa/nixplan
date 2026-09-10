## Why

Three findings out of a read of ThermOS, an adios-based system builder that rejects the same global
`config` fixpoint this library rejects and therefore hits the same questions one layer down. Each
finding is a fact about a *set* that has no place to live here.

**A slot set may disappear with settings, and nothing records it.** `lib/compose.nix:26-27` reads a
member's declaration once, against resolved settings:

```nix
settings    = settingsOf { inherit name defaults fixed; };
declaration = module { settings = settings.values; };
```

That single reading is decided and implemented (`unify-declaration-and-implementation-readings`),
and for `provides` it is the point: a deployment may decide how many databases a cluster publishes.
The same freedom applies to `uses`, where nobody examined it. A module writing
`uses = if settings.offsite then { repo = { interface = borgRepository; }; } else { };` deletes a
dependency when a knob is false: no wire is needed, `slot-unwired` never fires, and the plan holds
no evidence that the slot was ever declared. That is `excluded.constructs.enable`'s own trigger -
"a module publishing a composition whose coherent cuts an operator wants" (`lib/excluded.nix:37-44`) -
happening inside a module with no row. The deployment surface refuses the cut; the module can take it
silently.

**Every consumer of a set-valued read writes its own fold.** `lib/resolve.nix:960-969` hands
`results.<slot>` to `impl` as an attrset keyed by provider entry key when `reach = "all"`, and the
consumer folds it by hand - `fixtures/minimal-typed-edge/modules/borg-repo/server.nix:45-49` maps
over `results.clients` to build one `authorized_keys`. One consumer is fine. Ten are ten answers to
"what if two providers export the same key", in ten files, with no place a conflict could be reported
from. ThermOS puts that fold on the schema instead: `contract.merge` in its `contracts/units.nix` is
one function per contract, and its `publishers` argument is keyed by publisher, which is what lets a
conflict name the offender.

**A module cannot refuse a provider.** A declaration that writes `severity` is read and discarded
(`lib/module.nix:190-192`, "a module does not decide the severity of a planner row"); a module that
raises becomes one generic row (`lib/diagnostics.nix:74-81`, `module-raised`, message "raised a
catchable error", resolution "fix the expression in the module file"). Both are right as far as they
go. But ThermOS's single fan-in transformer needs exactly the missing thing - its PAM middleware
throws `unknown module '<x>'. Provide a 'package' field.`, which is a `message` and a `resolution` -
and `add-collect-slot-chain-rules` will multiply that need by every collector. The channel has to be
decided before collect slots land, or it gets decided twelve times inside `resolve.nix`.

## What Changes

- **An interface may own the fold of a set-valued read.** `interface { name, exports }`
  (`lib/interface.nix:47-54`) gains an optional `fold`. When a slot declares `reach = "all"` against
  an interface that declares a `fold`, the planner applies it to the entry-keyed set and `impl`
  receives the folded value in `results.<slot>`. One policy per interface instead of one per
  consumer. An interface without a `fold` keeps today's entry-keyed attrset, so nothing in the tree
  changes shape.
- **The fold sees exactly what the slot declared it reads, and nothing more.** Its input is the same
  `picked` values a read already produces (`lib/resolve.nix:937-949`), so a fold cannot widen a read,
  cannot name a secret export the slot may not name, and cannot change which machines a generated
  value is delivered to.
- **The fold is guarded, never trusted.** It is applied inside `diag.guard`, so an author's raising
  fold is an error row naming the interface and the slot, and the slot is then undelivered - absent
  from `results`, which is already the refused-read convention. No raising call enters `lib/`.
- **A settings-derived slot set becomes a warning row rather than a silence.** When a member's `uses`
  keyset differs between its own defaults and its resolved settings, the planner emits one warning
  row naming the member and the slots that disappeared, and states the trigger that would turn
  member cuts into a first-class construct. The plan is still produced: the module is publishing a
  cut, which is not an error, and `provides` derived from settings keeps the status
  `unify-declaration-and-implementation-readings` gave it.
- **The refusal channel is decided and written down: the fold is the only one.** A module may refuse
  a provider inside an interface fold, where the planner guards it and supplies id, subject and
  severity. `impl` gains no `refusals` key - a module writing one already gets
  `implementation-unknown-key` from `module.implKeys` - and a module still may not tag a row's
  severity. Recording the decision now is what keeps `add-collect-slot-chain-rules` from inventing a
  second answer.
- **No plan field is added and no golden moves.** A fold changes what a consumer's `impl` saw, not
  any fact about the far end; the `reads` record keeps `entries`, `reach` and `reads`, and the
  consumer's output is already in the plan. `fixtures/minimal-typed-edge/plan/backup.json` and
  `plan/diagnostics.txt` are unchanged by this change.

## Capabilities

### New Capabilities

- `planner/interface-fold`: what an interface-owned fold of a set-valued read is - where it lives,
  what it receives, what it may not see, what a raising fold produces, and what an unread fold is.

### Modified Capabilities

- `planner/typed-edge`: the single-reading requirement gains its missing half. A capability set
  derived from settings stays blessed; a *slot* set derived from settings is recorded as a published
  cut rather than passing unobserved.
- `planner/diagnostics`: gains the rule that says where a row may originate - the library, or an
  interface fold under the planner's guard, and nowhere else.

No `planner/plan-artifact` change: this change adds no entry field. No `tooling/*` change: a new row
id, a new spec and new per-row tests are what `tooling/nix-unit-suite` already requires of any
addition.

## Impact

- **`lib/interface.nix`**: the constructor gains `fold ? null`; `foldOf` and a shape check beside
  the existing `isType`/atom checks.
- **`lib/resolve.nix`**: the `reach = "all"` branch at `960-969` applies a declared fold inside
  `diag.guard`; the unread-fold observation is derived from the reads that were resolved.
- **`lib/compose.nix`**: `service` compares the slot keyset of the declaration it already reads
  against the same module read under its own `defaults`, and returns the row. The second read is
  taken only where a deployment actually wrote a knob, so a member nobody configured costs nothing.
- **`docs/`**: `authoring.md` gains the `fold` field beside `reach`, and a section stating where a
  refusal lives; `diagnostics.md` gains the new rows.
- **`tests/unit/`**: per-row and per-scenario tests in the `interfaces`, `resolution`, `composition`
  and `diagnostics` suites; the three spec files registered in `coverage.nix`.
- **`perf/budgets.json`**: the conditional second read is a measurable cost on any fixture whose
  deployment writes settings, so the nine budgets are re-measured and re-pinned with fresh
  provenance, in whichever direction the measurement reports.
- **Not in scope**: `collects`, `contributes` and `answers` stay excluded (`lib/excluded.nix:49-60`).
  This change gives the collect family the fold and the refusal rule it will need; it does not open
  it.
