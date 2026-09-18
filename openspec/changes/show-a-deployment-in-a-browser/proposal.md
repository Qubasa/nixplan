## Why

A built deployment already carries every fact a picture of an infrastructure needs, and nothing
renders it. The build writes a link farm holding `plan.json`, `manifest.json`, `diagnostics.json`
and `diagnostics.txt` (`operator/default.nix:309-330`), the manifest states each realiser's scopes
and holdings, each placed entry's realiser, profile, machine, address, units, digest and artifact
path, each value's delivery set and files, and each machine's sealing and scope
(`operator/read.nix:751-805`). The plan is the graph: a capability's export records the entries
that read it at `provides.<cap>.exports.<n>.readBy`, the fixture's own shape
(`fixtures/minimal-typed-edge/plan/backup.json:66-81`), and a consumer's resolved read records
the provider at `reads.<slot>.entry` with the wire beside it (`:86-104`), or every provider at
`reads.<slot>.entries` keyed by plan key (`:634-662`). The command already turns that into pairs as
pure data with no ssh and no nix: `edges` (`cli/order.py:225-245`) and `reads` (`:266-285`), over a
deployment `manifest.resolve` reads out of a prebuilt directory (`cli/manifest.py:219-262`). What
an operator can do with all of it today is read `planner plan`'s JSON on a terminal
(`cli/planner.py:35-38`), because the only other subcommand that prints machine-readable output is
none: the five are `plan build apply status rollback`
(`cli/planner.py:100-106`).

This change is the only one of the five in this set whose value is presentational. It fixes no
refusal, admits no declaration the planner rejected, and makes no run safer. It is worth building
for one reason that nothing else in the tree demonstrates: a program written against no particular
deployment can read the plan and draw the infrastructure - every machine, every entry on it, every
unit, every value and its delivery set, and every typed edge between entries - which is the claim
that the plan is a complete description rather than an input the realisers happen to be able to
finish. A view that needs one field the plan does not carry is a defect report against the plan, and
that is the second thing it buys: the view is the first consumer of the plan that is not this
repository's own command.

## What Changes

- A new top-level directory holds the view, with its own flake module imported from `flake.nix` the
  way the command's is (`flake.nix:43-48`, `cli/flake-module.nix:1-10`). It is python over the
  standard library and a page with no client-side dependency, because the repository has no
  third-party python (`pytest-env.nix:6`, and `cli/*.py` imports nothing outside the standard
  library and its own modules) and no frontend file at all: `git ls-files '*.ts' '*.tsx' '*.js'
  '*.html' '*.css'` returns nothing.
- The static half is offline. One document per question, served as JSON and rendered by the server
  into one page: the machines, the entries placed on each, the units of each entry, the values with
  their delivery sets and files, the typed edges between entries, and the diagnostics table with all
  six fields of every row. It runs no nix and no ssh per request; the target is resolved once before
  the port is open, through the command's own `manifest.resolve`.
- The graph is laid out by the server, not by a library in the browser. The column of an entry is
  the position of its strong component in the order the command already computes
  (`cli/order.py:69-101`, `:104-121`), the row is plan key order within that column, and an edge is
  an SVG path between two cells. The layout is data a test asserts, and the page carries no script.
- The live half asks the machines exactly the questions `planner status` asks, through the record
  `answer-a-machine-question-as-a-record` introduces, and defines no machine question and no remote
  script of its own. Today `report.status` returns rendered sentences - `Report` carries
  `lines: tuple[str, ...]` and `unasked` (`cli/report.py:81-86`, `:115-168`) and the verdict is
  f-stringed in `_answered` (`:364-375`) and `_read_status` (`:422-436`) - so a view built over
  today's shape would parse prose. It consumes the record instead, and a fact the report does not
  answer is a seam for `openspec/changes/INTEGRATION.md` rather than a question this change invents.
- The six-field diagnostics table depends on the same change: `cli/manifest.py:664-679` decodes a
  row into `id`, `subject`, `severity` and `message`, dropping the `evidence` and `resolution`
  `lib/diagnostics.nix:45-63` requires on every row, and `answer-a-machine-question-as-a-record`
  restores them. The view shows what the reader decodes and restates no field of its own.
- The view mutates nothing. No apply, no retire, no rollback and no build from the browser, and no
  route that writes anywhere. It binds the loopback interface, because an unauthenticated picture of
  a fleet's live state is not a surface to publish on a network.
- The flake publishes the server under one name in the namespaces that answer for a program, the
  `planner` precedent (`cli/flake-module.nix:44-51`), its source under a second name for the tests
  the way `planner-src` is published (`:20`, `:45`), and the check that runs those tests under a
  third, because a check is a value of this repository's own development.

## Capabilities

### New Capabilities

- `operator/deployment-view`: the read-only view over a built deployment and the machines it names -
  what the static half answers with no machine asked, what the graph draws and where its layout
  comes from, that every diagnostics row is shown with all six fields, that the live half asks the
  report's own questions and defines none, and that no route mutates anything.

### Modified Capabilities

- `tooling/consumer-surface`: the view is a layer a consumer reaches by output name rather than by a
  path inside this source, it asks the consumer for no input this repository pins, and a name that
  names a program a reader runs does not also name a check.
- `tooling/repository-shape`: the stated classes of a top-level entry gain the view, a top-level
  directory of python modules is named where the type checker and the linter read their roots as
  well as where it is classified, and a token a served document carries is a route the server
  answers rather than a path of this repository.

## Impact

- A new top-level directory of python modules: the reading over a built deployment, the layout, the
  page, the live half, the server and its own `flake-module.nix`.
- `flake.nix`: one `imports` line (`flake.nix:43-48`).
- `tests/unit/layers.nix`: `classOf` (`:54-85`) and `scannedDirectories` (`:295-306`).
- `treefmt.nix`: one `programs.mypy.directories` root (`:74-102`), reading the config that puts
  `cli` on the type checker's source path (`:55-58`).
- `ruff.toml`: `src` (`:4`).
- `tests/unit/consumer.nix` and `tests/unit/layers.nix`: the cases the two modified tooling
  requirements name.
- `docs/`: one document for the view, and the commands table of `README.md:86-93`.
- `CLAUDE.md`: the registration points the new directory trips, and the rule that a route is not a
  repository path.
- Nothing under `lib/**`, `image/**`, `flakelet/**`, `secrets/**` or `operator/**`, and no field of
  the plan or of the deployment record: the view reads what is already written.
