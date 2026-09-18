## Context

See `proposal.md` - Why. What shapes the approach is what a built deployment already holds, what the
command already computes from it, and what this repository's toolchain is.

The data is there. `operator/default.nix:309-330` writes `plan.json`, `manifest.json`,
`diagnostics.json` and `diagnostics.txt` into the farm for every build, a refused deployment
included. `operator/read.nix:751-805` is what `manifest.json` holds: `realisers` with each
realiser's `scopes` and `holdings` (`:763`), `entries` with `realiser`, `profile`, `machine`,
`address`, `units`, the artifact's version digest as `key` and `path` where the entry was realised
into something (`:764-780`), `values` with `delivery` and `files` (`:781-787`), and `machines` with
`sealed`, `scope` and the unsealer's path (`:798-804`). The plan carries the graph twice, once
forward and once back: `provides.<cap>.exports.<n>.readBy` lists the consumers of one export
(`fixtures/minimal-typed-edge/plan/backup.json:66-81`), `reads.<slot>` records `entry`, `reach`,
`reads`, `values` and `wire` for a single-valued read (`:86-104`), and `reads.<slot>.entries` keyed
by provider plan key for a `reach = "all"` one (`:634-662`), where a provider that has not generated
its value yet carries its own row inside the read (`:645-651`).

The reading of that graph is already written and already pure. `order.reads` returns one `Read` per
slot whichever shape it was recorded in (`cli/order.py:266-285`, the dataclass at `:46-57`),
`order.edges` returns the provider-before-consumer pairs (`:225-245`), and `order.walk` returns the
strong components in application order (`:69-101`, the condensation at `:104-121`). None of it dials
a machine. `manifest.resolve` reads a prebuilt directory with no nix invocation where the target is
a directory holding `manifest.json` (`cli/manifest.py:219-233`) and shells out to `nix build` only
for a flake reference (`:248-253`).

The toolchain is nix and python and nothing else. `git ls-files '*.ts' '*.tsx' '*.js' '*.html'
'*.css'` returns nothing. The python has no third-party dependency: `cli/*.py` imports the standard
library and its own modules, and the only package the test interpreter carries is pytest
(`pytest-env.nix:6`). The formatter runs deadnix, nixfmt, shellcheck, yamlfmt, ruff, mypy and vale
(`treefmt.nix:60-69`, `:117-120`), the flake has four inputs (`flake.nix:4-29`), and the one shell
carries the test interpreter, the command and the machine-layer environment printer
(`devshells.nix:14-22`).

What is missing is one thing the view must not invent: a structured answer from a machine.
`report.status` returns `Report(lines, unasked)` with `lines: tuple[str, ...]`
(`cli/report.py:81-86`, `:115-168`), and the verdict is computed and then f-stringed in `_answered`
(`:364-375`) and `_read_status` (`:422-436`). `cli/manifest.py:664-679` decodes a diagnostics row
into four fields and drops the `evidence` and `resolution` that `lib/diagnostics.nix:45-63` requires
on every row. Both are owned by `answer-a-machine-question-as-a-record`, and
`openspec/changes/INTEGRATION.md` is where this set's order and seams are written out.

## Goals / Non-Goals

**Goals:**

- A program written against no particular deployment draws the infrastructure out of the plan and
  the manifest alone, which is the claim about the plan this change exists to demonstrate.
- The static half is offline: no route runs nix and no route dials a machine, so a view of a build
  works with every machine of the fleet switched off.
- The live half consumes the record `answer-a-machine-question-as-a-record` publishes and defines no
  machine question, no remote script and no second verdict vocabulary.
- One toolchain. No second formatter, no second lockfile, no dependency that is not already in the
  pinned package set.
- Every layout decision is data the server computed, so a test asserts the picture rather than
  trusting it.
- The diagnostics table shows all six fields of a row, because a row with no resolution is a row
  nobody can act on (`lib/diagnostics.nix:41-45`).

**Non-Goals:**

- Mutating anything. No apply, no retire, no rollback, no build and no value write from the browser.
  An apply is a long-running walk over machines whose recovery is running it again
  (`cli/order.py:69-101` decides the order, and the command's own contract is that a failed step is
  followed by a second apply), so a button would need a job model: a run identity, a log a reader
  can follow, a concurrency rule for two readers, and an answer for a browser that closed
  mid-walk. That is a change of its own and not a corner of this one.
- Authentication, authorisation and multi-user access. The view binds the loopback interface and is
  a program an operator runs beside their own checkout.
- A second machine question. If the picture wants a fact the report does not answer, that is a seam
  for `openspec/changes/INTEGRATION.md` and a requirement in the report's own capability, not a
  script this directory renders.
- Editing a deployment. The view reads a build; the deployment's text is
  `author-a-deployment-from-outside`, and `openspec/changes/INTEGRATION.md` records that boundary.
- History. The view shows one build and what the machines hold now, not a series of builds over
  time: nothing in the tree records a build's predecessor.

## Decisions

### D1 - The view is python over the standard library and a page with no dependency

The server is python, in a new top-level directory, using `http.server` and `json` from the standard
library, and the page it serves is HTML plus CSS plus inline SVG the server rendered. Nothing is
fetched by the browser beyond what the server itself serves, and the page carries no script.

Rejected: **a TypeScript stack.** The conventions this harness applies to TypeScript work are Node
22, oxlint and vitest, and adopting them here costs, item by item: a second formatter and linter in
`treefmt.nix` beside its seven `programs` entries and the vale wrapper (`treefmt.nix:60-69`,
`:117-120`); a second type checker beside the mypy roots (`:74-102`); a lockfile and a node_modules
supply chain the flake would have to pin, against four inputs today (`flake.nix:4-29`); a build
step producing a bundle, which is an artifact `tests/unit/layers.nix` has to classify and the path
scan has to read (`:295-312`); a second test runner beside pytest, which is the only package the
test interpreter carries (`pytest-env.nix:6`); and a second language in the one shell
(`devshells.nix:14-22`). The benefit is a component model and a graph library for a page that draws
at most a few dozen boxes. For a presentational surface that is the wrong trade, and the trade is
not reversible by taste: a lockfile in this tree is a thing every later contributor maintains.

Rejected: **a client-side graph library with no build step**, a single vendored script served from
the directory. It removes the lockfile and keeps the supply chain: a vendored bundle is a
third-party artifact in the tree that nothing here reviews, and it would be the first file in the
repository the path scan and the formatter both have to be told to ignore. It also moves the layout
into the browser, which D4 rejects for its own reason.

### D2 - The view is a new top-level directory with its own flake module

The view lives in its own top-level directory and wires itself, with a `flake-module.nix` imported
from `flake.nix:43-48` exactly as the command's is (`cli/flake-module.nix:1-10`). That is the stated
registration point for a deliverable with its own flake wiring, and it keeps the root module the
place where suites, the performance harness and the machine layer are registered.

Rejected: **inside `cli/`.** The command's published source is a fileset of python files only
(`cli/flake-module.nix:15-18`), so a page template or a stylesheet placed there is silently dropped
from `planner-src` and from the wrapper's source root (`:20`, `:36`). Beyond the mechanics, `cli` is
classified as the operator's command (`tests/unit/layers.nix:61`) and a server that opens a port is
not that command - `planner`'s subcommands are `plan build apply status rollback`
(`cli/planner.py:100-106`), and adding a sixth that never returns would make `planner --help` read
as if the command served things.

Rejected: **inside `tests/`.** The view is a deliverable an operator runs, not a check, and putting
it there would make `nix run` reach into the test tree for a program.

### D3 - The flake publishes the server, its source and its check under three names

`planner-view` names the server in every namespace that answers for a program a reader runs, the way
`planner` does (`cli/flake-module.nix:44-51`); `planner-view-src` names the same source root the
wrapper runs, published so the tests import the view's pure half with no wrapper, the `planner-src`
precedent (`cli/flake-module.nix:20`, `:45`); and the check that runs those tests takes a third name
rather than the program's.

The third name is the decision. `A published name means one thing` says a value that exists for the
repository's own development must not occupy a name a runnable output uses, because the commands
that reach the two namespaces differ and a reader cannot see which one answered
(`openspec/specs/tooling/consumer-surface/spec.md:39-45`). Today's one pair under a single name is
`planner-perf`: `packages.planner-perf` is the measurement harness and `checks.planner-perf` runs
it (`flake-module.nix:358-367`, `:390-396`), which is one subject reached two ways and no program.
A server and the pytest layer over it are two subjects, so the check is named for the tests and not
for the server.

Rejected: **`checks.planner-view` beside `apps.planner-view`.** A reader who types `nix build
.#checks.x86_64-linux.planner-view` and one who types `nix run .#planner-view` would get a test
result and a server from one name, which is exactly the confusion the requirement names.

### D4 - The layout is computed by the server from the order the command already computes

Machines and their entries are a table: machines in name order, entries within a machine in plan key
order, each entry's units listed under it. The graph is a grid with one column per layer and one row
per entry within a layer. The layer of an entry is the index of its strong component in the order
`order.walk` returns (`cli/order.py:69-101`), which is already provider-before-consumer, and the row
is plan key order within the column, which no two entries share. An edge is an SVG path from the
right edge of the provider's cell to the left edge of the consumer's, with the slot name as its
label; a cycle is a column of more than one entry and its contradicted edges are drawn back the way
the walk records them (`:88-101`). A value is a cell of its own in the column before its readers,
because a value is written before any entry is activated. Cell size is fixed, so a fleet renders a
larger page rather than an unreadable one.

The rule is stated because it is the picture's whole grammar: x is dependency depth, y is name
order, and nothing moves for any other reason. Two renders of one build are byte-equal, which is
what makes the layout assertable.

Rejected: **a force-directed layout in the browser.** It needs the library D1 rejected, and its
output is not a value a test can assert: the picture would be verified by looking at it.

Rejected: **shelling out to graphviz.** It is in the pinned package set, so it costs no lockfile,
and its layout is better than a grid. It loses on two counts: the coordinates become the output of
a program whose version rides the package set, so the only assertion left is a golden that
re-records on a nixpkgs bump, and a runtime input the server executes per request is a second
process in a surface whose whole claim is that it reads data and dials nothing.

### D5 - The live half asks through the report and owns no question

The live route calls the report's own status reading with the same runner the command uses, and
renders the record it returns. It holds no script, no argv, no verdict vocabulary and no parsing of
another layer's sentences. That record is `answer-a-machine-question-as-a-record`'s: today
`report.status` answers `lines: tuple[str, ...]` (`cli/report.py:81-86`) with the verdict f-stringed
at `:364-375` and `:422-436`, so a view over today's shape would re-parse prose, and a rendered
sentence is not an interface. This change is ordered behind that one for that reason, and
`openspec/changes/INTEGRATION.md` records the set's order and every seam between the five.

A fact the record does not carry is not added here. The view asks the questions `planner status`
asks and no others, so a picture that wants one more fact is a requirement in the report's own
capability, raised as a seam in `openspec/changes/INTEGRATION.md`.

Rejected: **the view asking the machines itself.** It would be a second place a remote script is
written, and `CLAUDE.md` already holds the cost of a rule with two homes: the fourth site is a place
to forget it. It would also make the view's answers disagree with `planner status` for the same
fleet, which is the worst possible property for a picture.

### D6 - One question per reader-requested refresh, and no ambient asking

The static routes answer from the deployment the server read at startup. The live route asks the
machines when a reader asks for it, one question per machine as the report folds them
(`cli/report.py:161-167`), and the answer is what that request renders. There is no timer, no
background poll and no cached answer served as if it were current: a reader who wants a newer
picture reloads, and the page states when its answer was taken.

Rejected: **a page that refreshes itself.** A meta refresh or a poll makes a browser tab left open
overnight dial every machine of a fleet forever, which is a load nobody asked for and an ssh login
burst the guests' socket-activated sshd reads as a failure (`CLAUDE.md`, End-to-end layer). A reader
asking is the trigger.

### D7 - The target is resolved once, before the port is open

The server takes the same target the command takes - a directory holding `manifest.json`, or a flake
reference - and resolves it through `manifest.resolve` (`cli/manifest.py:219-262`) once, before it
listens. A flake reference therefore builds exactly once, in the foreground, where the operator can
see it, and no request ever runs nix: the sole build path in that function is the flake-reference
branch (`:248-253`), and it is behind the startup.

Rejected: **refusing a flake reference.** It would make the view the one program in the tree whose
target is narrower than the command's, for no gain: one resolve before listening has the same
property.

Rejected: **resolving per request.** A route that builds is a job model with none of a job model's
parts, and it turns a reload into a nix evaluation.

### D8 - The tests are a pytest layer over fabricated builds, and what is smoke is said

The view is tested by pytest beside its own modules, the way the command's counterexamples are
(`cli/counterexample_test.py`, run by `checks.planner-counterexamples-cli`,
`flake-module.nix:347-356`), over built deployments fabricated on disk the way the harness already
fabricates them (`tests/e2e/test_harness.py:275-347`): a directory holding `plan.json`,
`manifest.json`, `diagnostics.json`, `diagnostics.txt` and one artifact link per entry, read back
through `manifest.read`. No nix and no machine, so the check runs in a build sandbox like
`checks.planner-delivery` (`flake-module.nix:379-388`).

What is genuinely asserted: the JSON each route serves, field by field, against a build whose plan
the test wrote - every machine, every entry under its machine, every unit, every value with its
delivery set, every edge including the `reach = "all"` shape and the unrecognised shape that must be
named rather than dropped, and every diagnostics row with six fields; that two renders of one build
are byte-equal; that the page's parsed structure names every entry and every edge the JSON does,
read with `html.parser` from the standard library; that no route dials or builds, asserted by a
recording runner and by the absence of any subprocess; and that the live route renders the record
the report returned, with a fabricated answer.

What is smoke and is stated as smoke: that the picture is legible to a human. A pytest layer can
assert that an edge's path element exists between two cells and cannot assert that a reader
understands the drawing. The tasks record one manual observation - the served page opened in a
browser against the worked fixture - as the evidence for that, and nothing in the suite pretends to
cover it.

Rejected: **a nix-unit suite.** The view is python and its subject is a served document; nix-unit
evaluates expressions in a pure evaluation and cannot serve or fetch one.

Rejected: **a headless browser check.** It would pin a browser into the closure of a check for a
screenshot comparison that fails on a font change, which is the golden-that-re-records trap D4
already refuses.

## Risks / Trade-offs

- **A presentational change earns none of the protections the other four do.** It fixes no refusal,
  so nothing it breaks shows up as a red suite in another layer. → It is confined: one new
  directory, one `imports` line, four registration points, and no field of the plan, the deployment
  record or any realiser. Deleting the change is deleting the directory and the line, the property
  `cli/flake-module.nix:1-4` states for the command.
- **A picture invites control.** A reader looking at a stale entry wants a button. → No route
  mutates, the page says that changing a machine is the command's work, and the reason is written in
  the Non-Goals rather than left as an omission somebody later reads as an oversight.
- **The live half is unusable until `answer-a-machine-question-as-a-record` lands.** → The static
  half is the whole of the offline picture and stands alone, the live route is the last phase of the
  tasks, and the order is recorded in `openspec/changes/INTEGRATION.md`.
- **A plan holds paths and export values, and the view serves them over HTTP.** An export's `value`
  is in the plan (`fixtures/minimal-typed-edge/plan/backup.json:73-80`), and a secret's is not: a
  secret export must publish a generated file rather than a bare value, which
  `export-secret-not-a-reference` refuses. → The view adds no secrecy hazard the plan does not
  already carry, it shows the plan's own fields and no byte of any machine's value, and it binds the
  loopback interface so the surface is the operator's own host.
- **A hand-written layout will look poor for a fleet of hundreds.** → The rule is stated and boring,
  the cell size is fixed so the page grows rather than tangles, and a fleet that outgrows a grid is
  a reason to revisit the layout with a measurement rather than a reason to take a dependency now.
- **A new top-level directory trips four hand-maintained registration points, each of which fails
  quietly in a different way.** An unclassified entry fails
  `testATopLevelEntryBelongsToNoStatedClass` (`tests/unit/layers.nix:54-56`, `:98-100`), an unnamed
  mypy root is not type-checked at all
  (`treefmt.nix:74-102`), an absent `ruff.toml` `src` entry mis-sorts imports rather than failing
  (`ruff.toml:4`), and a directory outside `scannedDirectories` has its paths unread
  (`tests/unit/layers.nix:295-312`). → Each is its own task with its own verification, and the
  modified `Every top-level entry has a stated purpose` requirement makes the crossing between the
  classification and those roots a check rather than a habit.

## Migration Plan

Nothing migrates. No existing file changes behaviour: the change adds a directory, one `imports`
line in `flake.nix`, one class in `classOf`, one entry in `scannedDirectories`, one mypy root, one
`ruff.toml` `src` entry, the cases the two modified tooling requirements name, one document and one
row in the commands table of `README.md:86-93`. Nothing under `lib/**` is touched, so no counter
`perf/eval.nix` evaluates moves and the change records no perf baseline. Every plan, fixture,
golden and deployment record is byte-identical, because the view reads them and writes none of them.
The live route is written against the record `answer-a-machine-question-as-a-record` publishes and
lands after it; until then the static half is the view.

## Open Questions

- Whether the view gets an end-to-end folder of its own once the friend-enrollment demo exists, or
  whether the browser-level evidence stays one manual observation beside the pytest layer. An e2e
  folder is discovered from `tests/e2e/*/deployment/default.nix` and its machines are the cluster's,
  so a folder for the view would be a folder about the view's own live route against real machines -
  which is the seam `openspec/changes/INTEGRATION.md` records between this change and
  `enroll-a-friend-outside-the-harness`, and is an operator decision about what the demo has to
  prove rather than a design question this change can settle alone.
