## Context

See `proposal.md` - Why. What shapes the approach is which of the facts an author needs already
exist as values, and where the tree has already decided how such a value is published.

Three things already exist and are not published in a shape an author reaches. The table is a value:
`mkPlan` returns `diagnostics` beside `plan` and `applicable` (`lib/default.nix:221-225`), the
deployment build carries the same rows plus its own (`operator/default.nix:341-347`), and the
rendered text is one function of the table alone (`lib/diagnostics.nix:173-182`,
`docs/diagnostics.md:78-93`), written into the farm at `operator/default.nix:328`. The vocabulary is
data: key lists at `lib/module.nix:26-35`, `:130-135`, `:137-144` and `lib/resolve.nix:37-61`, a
directory table at `lib/module.nix:63-67`, and a unit record whose every field is a korora typedef
carrying a name (`lib/module.nix:84-103`, the name read for a row at `:1149`). And a
package-set-free entry point is an established convention with exactly one user:
`tests/e2e/generated-secret/deployment/args.nix`, for the reason `operator/default.nix:351-362`
writes out.

What is published is narrow. `flake-module.nix:50-79` publishes `lib`, `mkLib`, `operator` and
`debug`; `lib/default.nix:57-98` publishes `atoms`, `excluded`, `platform`, `platformSource`,
`util`, the interface constructors, the composition helpers and the four diagnostics helpers, and
does not publish `module`. So the unit vocabulary, the key lists and the directory table are
unreachable from outside the library, and the registry key list is a `let` binding inside
`lib/resolve.nix`. That is the whole reason a projection needs an edit under `lib/` rather than a
reader over the published surface.

The command's shape decides the rest. `manifest.resolve` reads a directory holding `manifest.json`
with no nix at all (`cli/manifest.py:231-233`) and otherwise runs `nix build`
(`cli/manifest.py:248-255`); `_plan` is the only subcommand that prints JSON
(`cli/planner.py:35-38`); and `_build` returns 1 where the rows carry an error
(`cli/planner.py:41-47`). An inapplicable deployment's per-entry and per-machine attributes are
`throw reading.refusal` (`operator/default.nix:71-75`, `:299-303`), so which attribute an answer is
read off is not a matter of taste.

## Goals / Non-Goals

**Goals:**

- An author gets the table from an evaluation: no artifact realised, no image built, no closure
  copied, and no package set instantiated for the question that does not need one.
- One text stays one text. Every fact this change publishes is projected from the table that already
  holds it, and nothing is transcribed into a second place a check does not hold.
- The scaffold is reached by a name rather than by a path, and the name hands a reader exactly the
  bytes two documents show and one end-to-end folder proves on a machine.
- The failures the interpreter does not let the library catch are named in one place, with what they
  print and the edit that fixes them, rather than being discovered by a reader whose table vanished.
- The published vocabulary states its own limit: it is a description and never a validator, because
  the validator is `mkPlan` and its answer is rows.

**Non-Goals:**

- A second diagnostics table. Nothing here computes, re-renders or re-orders rows: the rows are the
  ones `lib/diagnostics.nix:141-169` ordered and the text is the one `planner.render` produced.
- A machine-readable copy of the 172 row identifiers. Their home is the production sites and
  `docs/diagnostics.md` is the table they are already crossed against
  (`tests/unit/diagnostics.nix:511-541`).
- A validator outside `mkPlan`. Nothing consumes the published vocabulary to accept or reject a
  deployment; a deployment is judged by planning it.
- Restoring `evidence` and `resolution` in `cli/manifest.py`. That is
  `answer-a-machine-question-as-a-record`, and `openspec/changes/INTEGRATION.md` records the seam.
- A row for any of the three interpreter traps, and a row for the fourth. The fourth is reducible
  and named below with the trigger that would make it somebody's task.
- Moving `tests/e2e/newcomer/template/`. A copy elsewhere is a second convention, and the directory
  is where four checks and two documents already read it.

## Decisions

### D1 - The table an author reads is two published attributes, and never the record

`mkDeployment` publishes the rendered text beside the rows it already publishes, bound once from the
expression `operator/default.nix:328` already evaluates for `diagnostics.txt`, so one deployment has
one table in one rendering. An answer is read off those two attributes by name. It is never read
off the record as a whole, because an inapplicable deployment's entry and machine attributes are
`throw reading.refusal` (`operator/default.nix:71-75`, `:299-303`): a caller who asked for
everything would be handed the refusal instead of the table it is about, which is precisely the
deployment an author is iterating on.

Nothing carries a marker of its own. `An inapplicable deployment is not built` already forbids one -
"a second statement of a fact the table carries is a statement that can disagree with it" - so the
answer carries no `applicable` field and a caller reads the severities, the way
`tests/unit/operator.nix:911-912` already asserts the reading itself does.

Rejected: **rendering the table in python.** The rendered table is the planner's own words
(`docs/diagnostics.md:73-76`, `:78-93`), and a second renderer would be a second format that drifts
from the one `fixtures/minimal-typed-edge/plan/diagnostics.txt` is compared against byte for byte.
The command prints what it was handed.

Rejected: **a third file in the farm.** The two files exist already
(`operator/default.nix:309-330`); what was missing is an answer that costs no farm.

### D2 - Both a subcommand and a recipe, because they answer for two different callers

`planner diagnose <target>` prints the rendered table and exits non-zero where a row carries an
error, mirroring `_build` (`cli/planner.py:41-47`); `--json` prints the rows instead, in the order
`lib/diagnostics.nix:141-169` put them, which is the one deliberate widening of "the only JSON a
subcommand prints is `planner plan`" (`cli/planner.py:35-38`) and is why a flag rather than a second
default. A target that is a built directory is answered from its two committed files with no nix
invocation, the `cli/manifest.py:231-233` branch; a target that is a flake reference is answered by
evaluating the two attributes, in one invocation with `--apply`, which is how `perf/measure.sh`
already passes arguments to an evaluation.

The recipe is the other caller. An author with the scaffold and no `planner` on their PATH has a
flake, so the scaffold's own flake publishes the rows-only output and the documents show the one
command that reads it. It is a recipe and not a second implementation: both spend the same published
attributes, and the subcommand adds the target resolution, the exit status and the rendering choice
that a bare `nix eval` does not have.

Rejected: **the subcommand alone.** It puts a python program between an author and an answer that is
one attribute of their own flake, and it cannot be the loop for an agent operating on a checkout
that has not built this repository's command yet.

Rejected: **the recipe alone.** Then the exit status - the one thing a loop branches on - is a
reader's own `jq` expression, and a built directory, which needs no evaluation at all, has no route
to an answer.

### D3 - The scaffold is published under a name and does not move

`templates.default` names `tests/e2e/newcomer/template`, so `nix flake init -t` writes exactly the
bytes `tests/unit/layers.nix:389-407` asserts against the fenced blocks of `README.md` and
`docs/README.md`, and the directory stays inside the scan at `tests/unit/layers.nix:715` that
refuses a host path in a deployment. What was missing is a name: `README.md:48-50` and `:82-84` tell
a reader to read a path under `tests/`, and a published template makes the path an implementation
detail a reader never types.

Rejected: **a top-level `template/` directory with the folder importing it.** It buys nothing and
costs four registrations and a loss: `classOf` and `scannedDirectories` in `tests/unit/layers.nix`,
the four entries of `shownTexts` (`:389-407`), the file list at `:1084-1090`, and the deployment
scan at `:715`, whose regex reads `tests/e2e/*/template/deployment/**` - a top-level directory would
leave the scaffold outside the one check that keeps a host path out of it.

Rejected: **a second copy under a published path.** Two texts kept equal by hand is the failure
`The example a document shows is the example a test builds` exists to prevent.

### D4 - The scaffold carries two entry points, and `packages` is an argument of the inner one

The scaffold gains `args.nix`, whose formals are the three
`tests/e2e/generated-secret/deployment/args.nix:6-10` states and whose result is `{ args }`, and its
`default.nix` composes it and hands `mkDeployment` the same value, the way
`tests/e2e/newcomer/deployment/default.nix:1-7` composes the template today. The rows-only output of
the scaffold's flake plans those args with store-shaped placeholder strings for the packages, which
is `tests/unit/worked.nix:6-9` exactly: literal store paths by default, and the argument exists so
the same deployment can be handed real ones.

The placeholders are the caller's and live in the flake, not in `args.nix`: `args.nix` is the
deployment's own text, and which package set answers it is the question the two entry points differ
on. A placeholder is store-shaped rather than a bare name because `util.storePathsIn` recognises a
store path by its store directory and 32 characters of Nix's base 32 (`lib/util.nix:282-296`), so a
placeholder that is not one makes the closure family (`docs/diagnostics.md:217-227`) silently find
nothing and the cheap answer is then clean for the wrong reason.

Rejected: **one entry point taking `pkgs` and a rows-only output reading `passthru`.** It answers,
and it answers through `nixpkgs.legacyPackages` (`tests/e2e/newcomer/template/flake.nix:18`) and
through the instantiation of every artifact derivation the deployment places, which is the cost the
change exists to remove. That route stays available and is the authority; it is not the loop.

Rejected: **bare names as placeholders.** Rejected on the evidence above: it turns a family of rows
off rather than answering them.

### D5 - The vocabulary is projected from the tables that hold it, and the library publishes it

A new `lib/vocabulary.nix` reads the tables `lib/atoms.nix`, `lib/module.nix` and `lib/resolve.nix`
already hold and assembles one record; `lib/default.nix` publishes it beside `atoms`, `excluded`,
`platform` and `util` (`:57-64`); `packages.planner-schema` is that record as one JSON file. The
projection reads each table rather than a list of names written beside it, which is the rule
`unitVocabulary` itself follows for the directory kinds (`lib/module.nix:69-82`, the fourth-kind
lesson `CLAUDE.md` records under Registration points), so a field added to a table is described by
existing.

It is published by the library because the library is what enforces it, and it is published rather
than read by a reader over source text because there is no reader: `lib/default.nix:57-98` does not
publish `module`, and `machineRegistryKeys` is a `let` binding in `lib/resolve.nix`. The two
additive exports - `moduleKeys` from the `rec` at `lib/module.nix:212-220`, and the four key lists
from the attrset at `lib/resolve.nix:206-207` - are evaluated once per library import and sit
outside `mkPlan`, so no gated counter reads them. The one sensitive shape is untouched: nothing is
added to the right of `korora // { … }` in `lib/atoms.nix:77-78`, where one new top-level key costs
one copied value per plan.

Rejected: **a schema expression outside `lib/` importing `lib/module.nix` directly.** It needs the
argument wiring `lib/default.nix:20-48` performs, so it is a second copy of the library's own import
graph, and the first argument added to a module there makes the projection's copy wrong in a way
nothing reports.

Rejected: **a hand-written schema file.** It is the second copy this change exists to refuse, and
the registry table at `docs/authoring.md:809-818` is the evidence of what happens to one: six keys
where `lib/resolve.nix:52-61` admits eight.

### D6 - A type is published by its name; a predicate is not published at all

Every atom is a korora typedef whose validator is a function (`lib/module.nix:944` applies it) and
whose name is a string (`:1149` reads it for a row). The projection publishes the name and, where
the atom is an enumeration, the domain list beside it (`lib/atoms.nix:128-157`). It publishes no
predicate and no regular expression, which is the same limit `CLAUDE.md` records twice: `identityOf`
compares korora type names because "a predicate cannot be hashed", and the platform record omits the
`is*` predicates because each is a function of `parsed`.

`domains` is filtered to its list-valued members rather than published whole, because
`domains.isZeroDuration` (`lib/atoms.nix:111`) is a predicate riding that table for a recorded
reason, and serialising a function aborts the evaluation that would report it - the hazard
`CLAUDE.md` records for the platform record's upstream guard, where "serialising a function aborts
the suite".

So the published vocabulary states what a key is called, what kind of value it takes, which values
an enumerated kind admits, and which keys a declaration may carry at all. It does not state whether
a particular string satisfies `bindAddress`. The schema says so in its own text, and the answer to
that question is one `planner diagnose` away.

### D7 - The row catalogue is not projected

An author does not need the 172 identifiers; they need the rows their deployment earned, which
`planner diagnose` gives with all six fields. Projecting the catalogue would mean either
transcribing `docs/diagnostics.md` or scanning the library's source for string literals, and the
second is what `tests/unit/diagnostics.nix:511-541` already does to keep the document honest. A
third copy would be a third thing to keep equal for no question it answers better.

`excluded` is the opposite case and is embedded: it is already data with one home
(`lib/excluded.nix`, published at `lib/default.nix:60`, described at `docs/diagnostics.md:351-370`),
so the schema carries that value rather than a copy of it.

### D8 - None of the three interpreter traps becomes a row, and the fourth is not this change's

`builtins.tryEval` catches a `throw` and a failed `assert`, and none of an abort, a missing
attribute, or a function called without an argument its pattern requires (`CLAUDE.md`, Purity and
totality; `lib/diagnostics.nix:84-86` states the same beside the guard that depends on it). So none
of the three can be answered by a row, and the cost of hitting one is not one missing row but the
whole table: `applicable` forces every row of every entry, so one unguarded read leaves nothing
rendered for any entry (`docs/authoring.md:659-662`).

Each therefore becomes a sentence in the section that already holds two of them
(`docs/authoring.md:644-673`): what ends the evaluation, what the interpreter prints, and the edit.
Two of the three already have their mechanism recorded there and at `docs/diagnostics.md:372-386`;
what is added is the third's and, for each, the line an author actually sees. The published schema
names that section and copies none of it.

The one structural half that is available is already spent: an `impl` whose argument pattern is
closed is read for its pattern and earns `implementation-formals-closed` rather than being applied
(`docs/diagnostics.md:380-382`). Nothing analogous exists for a body, because a function's body is
not a value Nix lets a library read, so `results.<slot>` cannot be found before it is forced.

The fourth trap is reducible to a row and is deliberately left: a derivation handed to a module
instead of `"${drv}"` is an attrset the line-break walk descends into (`lib/util.nix:398-413`, gated
at `:435-444`), and the walk could recognise one by the attributes it carries before forcing an
input. That row's subject is a unit field of a plan, so its home is a planner capability this change
does not own; it is named here with its trigger - the first deployment outside this repository that
hits it, or the change that next opens `planner/unit-vocabulary`.

### D9 - Every fact another change owns is cited rather than restated

The restored `evidence` and `resolution` fields, and the structured record `report.status` answers,
are `answer-a-machine-question-as-a-record`'s. This change consumes them: `planner diagnose --json`
prints whatever the row carries, so it prints six fields the moment that change lands and four
before it, and no reading here decodes a row of its own. `openspec/changes/INTEGRATION.md` is where
this set's order and its seams are written out, and this change is behind
`bind-a-value-an-entry-did-not-generate` and `answer-a-machine-question-as-a-record` and beside the
other two.

## Risks / Trade-offs

- **The cheap answer is not the whole answer.** With placeholder packages, the closure family
  (`docs/diagnostics.md:217-227`) is answered about the placeholders: `closure-path-undeclared` and
  `closure-root-unmentioned` compare the store paths an entry's own strings mention against its
  declared roots, and those strings are the caller's placeholders. -> The placeholders are
  store-shaped so the comparison happens rather than silently matching nothing, the scaffold's
  documents state that the build is the authority for that family, and the end-to-end folder asserts
  the two answers agree for the scaffold as shipped and for one mutation both can decide.
- **The published path is a path under `tests/`.** A reader who inspects the template output sees
  `tests/e2e/newcomer/template`. -> That is the point: the bytes a reader gets are the bytes a
  machine proves, and `openspec/specs/tooling/test-layers/spec.md:209-229` already makes that folder
  the newcomer's route and licenses other changes to add scenarios to it. A reader types the name,
  never the path.
- **A sixth subcommand widens a surface whose help is somebody's only document.** The help is
  asserted as such (`tests/e2e/newcomer/test_newcomer.py:390-417`). -> The new subcommand states
  what a target may be from the same `TARGET` and `EPILOG` strings every other subcommand states it
  from (`cli/planner.py:112-132`), and the same test gains its phrases rather than a count.
- **Publishing `vocabulary` widens the library's own interface.** A consumer can now depend on the
  shape of a projection. -> The projection is a description with its limit written into it, it is
  derived from tables a check crosses, and it is outside `mkPlan`, so it constrains no plan, no key
  and no row. The baseline task records that no gated counter moved.
- **The scaffold a reader is handed doubles in entry points.** Two files where there was one. ->
  `default.nix` becomes a composition of `args.nix` and nothing else, which is the shape
  `tests/e2e/newcomer/deployment/default.nix:1-7` already has, and both are in the documents' shown
  blocks, so a reader reads the pair or the check fails.
- **A projection can go silently stale if it enumerates.** -> It reads the tables. The unit test
  crosses the projected key sets against `unitKeys`, `moduleKeys`, `implKeys`, `configFileKeys`,
  `machineRegistryKeys` and `instanceKeys` directly, so a table that grows without the projection
  growing is a failure rather than an omission.

## Migration Plan

Nothing migrates and nothing is removed. `passthru.diagnostics` keeps its shape and its meaning; the
rendered text is a new attribute beside it, so a consumer reading the rows today reads the same rows
afterwards. The five existing subcommands are untouched, and `diagnose` is additive. The scaffold
gains `args.nix` and a `diagnostics` output, and its `default.nix` and `flake.nix` change in the
same edit as the fenced blocks of `README.md` and `docs/README.md` that are those files
(`tests/unit/layers.nix:389-407`) and as the file list at `:1084-1090` - one edit, because the check
compares the bytes and any other order is red in between. The published vocabulary is new surface
nothing existing reads.
