## Why

`CLAUDE.md` states the layered rule for refusals: "A realiser raises only for a condition one of
those two already reported as an error row, so no path through a deployment build reaches a raise
before a row", and `tests/unit/diagnostics.nix` crosses every `fail` of the realisers against the
row producers so that "a refusal with no row above it fails the suite". The crosswalk's
`realiserFiles` names two files (`tests/unit/diagnostics.nix:144-153`): `image/read.nix` and
`flakelet/read.nix`. The third realiser is in no crosswalk, produces no row anywhere, and holds
thirteen raises.

Each of the following is a condition `mkPlan` answers `applicable = true` for, whose
`operator.mkGeneration` build then aborts with a bare `planner secrets:` throw above an empty
diagnostics table. `operator/default.nix:230` renders the table only when the plan is inapplicable,
so the table a reader would look at is `[ ]`.

- **A generator declaring no `program`.** `program` is optional in the library and
  `lib/plan.nix:729` records it only where one was declared, precisely so a plan written before the
  field existed stays keyed as it was. `secrets/read.nix:167-171` then refuses: "entry `x:vars/y`
  records no `program`". The plan is correct, the deployment is correct, and the only statement of
  the requirement is a throw from a file the operator never named.
- **A generated file whose name the external contract does not admit.** `lib/` fixes a file's path
  and holds its name to no grammar; `secrets/read.nix:126-133` refuses a name outside
  `[a-zA-Z0-9:_.-]+` and the reserved `.nixos-secrets-metadata`. `files."key@id"` is a legal
  declaration, a legal plan, and an aborted generation build.
- **A recipient machine with no address.** `operator/read.nix` reports a missing address as
  a *warning* and every artifact is still built, because "an address is read by the step that dials
  a machine and by no step that builds one". The rendered deploy step is the one build artifact that
  carries addresses, so `secrets/read.nix:203-213` raises where the table holds a warning at most,
  and for a value delivered to a machine that hosts no placed entry there is not even that.
- **An address or path the rendered step cannot carry as a shell word.**
  `secrets/backend.nix:30-39` refuses an address outside `[a-zA-Z0-9_./:@%+=,~-]+`. The machine
  registry holds an address to no grammar, so `address = "10.0.0.11 "` is a plan the planner
  accepts and a generation build that aborts naming a quoting rule.

`collisionsOf` (`secrets/read.nix:140-148`) shows the intended shape and is the exception that proves
the rule: it is exported as a value "so that what the refusal is about can be read without catching
it", and nothing in `operator/` reads it.

The second half is why this recurred. The accounting is a table of twenty message *fragments* matched
by substring against `fail "` lines (`tests/unit/diagnostics.nix:57-207`), keyed on the file list
above. Rewording a refusal breaks it for the wrong reason, and adding a realiser leaves it silently
uncovered - which is exactly what happened.

## What Changes

- **The secrets reading gains a total half.** Like `operator/read.nix`, which is "on `lib/`'s side",
  the reading answers with rows for the facts only it holds: a value recording no `program`, a file
  name the external contract does not admit, the reserved provenance name, a projection collision, a
  recipient machine with no address, and an address or path the rendered step cannot carry. Reading a
  plan for its rows realises nothing and raises nothing.
- **A generation build renders that table and refuses through it.** `operator.mkGeneration` produces
  `diagnostics.json` and `diagnostics.txt` beside `secrets.json`, `names.json` and `plan.nix`, and an
  error refuses the build with `planner.render` of the whole table rather than with a realiser's
  throw. A table carrying warnings and no error builds, as it does for a deployment.
  **BREAKING** for a caller reading the exact text of a `planner secrets:` throw; there is none in
  this tree.
- **A refusal states its own row identifier.** Each `fail` in every realiser carries the id of the
  row that reports the same condition, or states that no plan can reach it. The crosswalk becomes an
  attrset lookup over that data instead of substring matching over message text, so a reworded
  message cannot break it and a message and its row cannot drift apart.
- **The accounting covers every realiser by construction.** The file list is derived from the
  realiser sources the suite is handed rather than written out, so a fourth realiser is accounted for
  by existing.

## Capabilities

### New Capabilities

None. The rule that a refusal has a row above it is already stated by `realiser/secrets-configuration`
and by `tooling/test-layers`; what is missing is that the third realiser is held to it.

### Modified Capabilities

- `realiser/secrets-configuration`: the reading of a plan as a generator configuration is total and
  reports a row for every condition it refuses; the conditions only this reading knows become rows
  with identifiers; the generation build carries both halves of the table and refuses through it.
- `tooling/test-layers`: the refusal accounting covers every realiser without a hand-maintained file
  list, and pairs a refusal with its row by identity rather than by a fragment of its message.

## Impact

- `secrets/read.nix`, `secrets/backend.nix`: a rows half beside the existing reading; each `fail`
  carries its row identifier.
- `image/read.nix`, `flakelet/read.nix`: each `fail` carries its row identifier. No refusal is added
  or removed.
- `operator/default.nix`: `mkGeneration` builds the table, writes both halves into the farm, and
  refuses through `planner.render`.
- `tests/unit/diagnostics.nix`: the fragment table is replaced by the identifiers the refusals carry;
  `realiserFiles` is derived from the sources the suite is handed.
- `tests/unit/secrets.nix`: the rows the reading produces, and that each refusal has a row above it.
- `docs/secrets.md`, `docs/diagnostics.md`, `CLAUDE.md`: the row table gains the secrets identifiers,
  and the layered rule names three realisers rather than two.
