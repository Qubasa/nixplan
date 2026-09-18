# Showing a deployment

`nix run .#planner-view -- <target>` serves one built deployment on the loopback
interface and opens no other surface. A target is what the operator's command
takes: a directory a build wrote, holding `manifest.json` beside `plan.json`, or
a flake reference naming an attribute that builds one.

```bash
nix build .#planner-e2e-wired-pair          # a built deployment to look at
nix run .#planner-view -- result            # then open http://127.0.0.1:8099/
```

The target resolves once, before the port is open. A flake reference therefore
builds in the foreground, where the operator can see it, and no request the view
answers is ever a build.

## What it answers

One document per question, each served as JSON and rendered into one page:

| Route | What it holds |
| --- | --- |
| `/` | the page: the machines, the graph, the values and the rows |
| `/documents/machines.json` | each machine, its address, its scope, its sealing, and the entries placed on it with their realiser, units, digest and artifact |
| `/documents/values.json` | each generated value, its delivery set, and each file's path, secrecy, ownership and mode |
| `/documents/graph.json` | the cells, the edges and every coordinate of both |
| `/documents/diagnostics.json` | every row with all six fields, and what the build realised |
| `/live` and `/documents/live.json` | what the machines hold now, and when they were asked |
| `/page.css` | the one asset the page names |

Every route but the last two answers out of the build alone. A view of a
deployment whose machines are all switched off is complete: no static route runs
an evaluation and none dials a machine, which is why the picture is worth having
while a fleet is down.

An entry realised into nothing is shown as holding no artifact rather than as an
entry with an empty path, because the build's record omits the path on purpose.
A deployment the planner refused is shown too: its rows, and the statement that
no entry was realised.

## The layout rule

One axis is dependency depth and the other is name order, and nothing moves for
any other reason.

- The column of an entry is the index of its strong component in the order the
  command applies in, which is provider before consumer.
- The row is plan key order within the column, which no two cells share.
- A value is a cell in the column before its readers, because a value is written
  before any entry is activated.
- An edge is an SVG path from the right edge of the provider's cell to the left
  edge of the consumer's, labelled with the slot the read was recorded under. A
  read naming one provider is one edge and a read of every provider of a
  capability is one edge per provider, so a set-valued read is as visible as a
  single-valued one.
- A cycle the walk had to break is a column of more than one entry, and the edges
  that order contradicted are drawn the way the walk records them.
- The cell size is fixed, so a fleet renders a larger page rather than a tangled
  one.

The server computes all of it, so two showings of one build are byte-equal and a
test asserts the picture rather than a reader trusting it. The page carries no
script and names no asset the view does not serve itself.

A read recorded in a shape the view does not recognise is named - the consumer
and the slot - rather than dropped. A missing edge nobody mentions is
unreadable as a defect.

## The live half

`/live` asks the machines exactly what `planner status` asks, through the record
the machine report answers with, and defines no question, no remote script and
no verdict of its own. A rendered sentence is a sentence for a reader rather than
an interface for a program, so the record is what the route renders.

It asks when a reader asks. No timer, no background poll and no answer kept from
an earlier request: the answer carries the time it was taken, and a reader who
wants a newer one reloads. A machine that answered nothing is shown
as unasked rather than as holding nothing, because absence is an endpoint's own
answer and silence is not one.

A fact the report does not answer is not obtained here by other means. It is a
requirement against the report's own capability.

## What it does not do

The view changes nothing. No route applies, retires, rolls back, builds or
writes a value, and every method but `GET` and `HEAD` is refused. An apply is a
long-running walk over machines whose recovery is running it again, so offering
one needs a run identity, a log a reader can follow, a rule for two readers at
once and an answer for a browser that closed mid-walk. That is a change of its
own, and changing a machine stays the operator's command:
[operator.md](operator.md).

It binds the loopback interface, and an instruction to listen anywhere else is
refused naming the reason: an unauthenticated picture of a fleet's live state is
not a surface to publish on a network. It authenticates nobody and serves one
reader, because the view is a program an operator runs beside their own
checkout.

It shows one build rather than a series of them. Nothing in the tree records a
build's predecessor.

## The layer itself

`view/` is python over the standard library and a page with no client-side
dependency, which is what keeps the toolchain at one formatter, one linter, one
type checker and one test runner. Its own `flake-module.nix` publishes the
program as `planner-view`, its source root as `planner-view-src` for the tests
to import with no wrapper, and the check that runs those tests as
`planner-view-tests` - a name of its own, because a name that names a program a
reader runs must not also name a check.

The tests are pytest beside the modules, over built deployments fabricated on
disk and read back through the command's own reader, with a recorder in place of
the machines. `nix build .#checks.x86_64-linux.planner-view-tests -L` runs them
in a build sandbox with no nix and no machine.

What they do not cover, and do not pretend to: whether a reader finds the
picture legible. A test asserts that an edge's path element runs between two
cells; a human asserts the rest by opening the page.
