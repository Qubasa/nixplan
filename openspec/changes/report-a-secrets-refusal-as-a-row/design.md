## Context

See proposal.md - Why. Three facts shape the approach:

- `operator/read.nix` already is the pattern this change applies to `secrets/`. It is "on `lib/`'s
  side": total, row-producing, handed the realisation statement no plan carries, and imported by
  `operator/default.nix`, which raises above it. The secrets reading is handed the external
  contract's grammar, which no plan carries, and is the same kind of layer with none of the
  behaviour.
- `secrets/read.nix` already separates the two halves once, deliberately: `collisionsOf` returns the
  colliding pairs as a value and `valuesOf` raises over it (`:140-159`), "so that what the refusal is
  about can be read without catching it". The change generalises that one case to all thirteen.
- `mkGeneration` (`operator/default.nix:129-231`) has no table of its own. It renders the plan's
  table only when the plan is inapplicable, and everything the secrets reading refuses happens on the
  applicable path.

## Goals / Non-Goals

**Goals:**

- One reading, two halves: rows for a caller that wants the table, a raise only under a row.
- A generation build that carries a table like a deployment build does, so an operator reads one
  artifact set whichever build refused.
- An accounting that cannot be left behind by a new realiser or broken by a reworded message.

**Non-Goals:**

- No new row of `lib/`. The library gains no knowledge of the external contract, and a name that
  cannot enter a plan key stays `hold-every-stated-guarantee`'s subject.
- No change to the projection, the grammar, the rendered step or the pinned contract digest. Which
  conditions are refused is unchanged; where they are reported is what changes.
- No change to `image/` or `flakelet/` refusals beyond the identifier each one carries.

## Decisions

### The reading answers `{ result, rows }`, and the raise stays

The reading gains `rows { plan, backend }` beside `store`, `configuration` and `deliveriesOf`, and
every `fail` becomes reachable only for a condition `rows` reported. The raise is not deleted:
`image/read.nix` and `flakelet/read.nix` keep theirs for exactly the same reason, which is that a
caller reaching a realiser directly gets a sentence rather than a missing attribute, and
`tests/unit/diagnostics.nix` is what holds the row above it.

Alternative considered and rejected: make the reading return rows only and have `mkGeneration`
refuse. That deletes the sentence a direct caller of `secrets/read.nix` gets, and it makes the
reading the only realiser of three with a different shape.

### Each `fail` carries its account as data

`fail` becomes `fail { id, message }` where `id` is the row identifier that reports the same
condition, or `id = null` with a `because` naming why no deployment reaches it. The realiser exports
the accounts it carries as a value, and the suite reads that value instead of grepping `fail "` lines
and matching message fragments.

Alternatives considered:

- **Keep the fragment table and add the two secrets files to `realiserFiles`.** Rejected: it leaves
  the coupling textual, and the file list is the thing that failed. Twenty fragments plus thirteen
  more is a bigger hand-maintained list, not a fixed mechanism.
- **Derive the account from the row's own message.** Rejected: a row's message names the deployment's
  files and a refusal's names the plan's key, so they are not the same sentence and never should be.

### The address row is an error of the generation and a warning of a deployment build

`report-every-refusal-as-a-row` states that a machine with no address SHALL NOT refuse a build,
because no build step dials a machine. The rendered deploy step is the counterexample: it is a build
artifact that carries addresses, so the same absence has two severities in two readings. This is
stated in the spec rather than resolved, because collapsing it either way is wrong: making it an error
of the deployment build would refuse artifacts that need no address, and making it a warning of the
generation would emit a step that cannot dial.

The rule this follows is already the project's: a refusal belongs to the layer that holds the fact,
and the fact here is that a step is being rendered.

### `mkGeneration` builds the table from both halves

`table = planner.mkTable (result.diagnostics ++ reader.rows { … })`, then `diagnostics.json` and
`diagnostics.txt` join the farm, and the build is `if hasError then throw (planner.render table)`.
This is the shape `operator/read.nix` plus `operator/default.nix` already have, and it makes the two
builds answer the same way: the farm exists for an inapplicable deployment too, carrying both halves
and no artifact.

## Risks / Trade-offs

- **A row and a raise state one condition twice.** → The row and the refusal are built from one
  description per condition, the way `operator/read.nix` already calls into
  `imageReader.nameOf`, `hostPaths`, `denials` and `profileNames` rather than restating them. The
  suite's account is what fails if they separate.
- **Thirteen new rows widen the row table `docs/diagnostics.md` documents.** → They are documented
  under the secrets reading rather than among the planner's, because a caller who never reads a plan
  as a generator configuration cannot produce one.
- **`rows` walks the plan a second time.** → The walk is over generated-value entries only, which is
  a small fraction of a plan, and `perf/` gates the planner rather than the realisers. No budget
  moves.
- **A caller that catches the current throw text breaks.** → There is none in this tree;
  `tests/unit/secrets.nix` asserts through the reading's own values, and the e2e folder builds through
  `mkGeneration`.
