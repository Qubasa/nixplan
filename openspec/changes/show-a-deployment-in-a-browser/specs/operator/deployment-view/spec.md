<!--
A new capability. The view reads what a build already wrote and what a machine already answers, so
this delta adds no field to the plan, no field to the deployment record, no diagnostics row and no
machine question. The build's own record stays owned by `operator/deployment-build`, the walk and
its refusals by `operator/apply-command`, and every question a machine is asked - and the record it
answers with - by `operator/machine-report`. This spec states only what a reader of those is held
to, so it MODIFIES none of them.

What it deliberately does not decide: the shape of the structured answer the live half renders. That
record and the two diagnostics fields `cli/manifest.py` restores are owned by
`answer-a-machine-question-as-a-record`, this change is ordered behind it, and
`openspec/changes/INTEGRATION.md` is the one place this set's order and its seams are written out. A
fact the report does not answer is a seam raised there, never a question this capability invents.

The conditions. A build writes `plan.json`, `manifest.json`, `diagnostics.json` and
`diagnostics.txt` for every deployment including a refused one (`operator/default.nix:309-330`), and
the manifest carries each realiser's scopes and holdings, each placed entry's realiser, profile,
machine, address, units, digest and artifact path, each value's delivery set and files, and each
machine's sealing and scope (`operator/read.nix:751-805`). The plan carries the graph in both
directions: `provides.<cap>.exports.<n>.readBy` names the consumers of an export
(`fixtures/minimal-typed-edge/plan/backup.json:66-81`), `reads.<slot>` records `entry`, `reach`,
`reads`, `values` and `wire` for a single-valued read (`:86-104`), and `reads.<slot>.entries` keyed
by provider plan key for a `reach = "all"` one (`:634-662`). Reading that graph needs no machine and
no evaluation: `order.reads` answers one record per slot whichever shape it was recorded in
(`cli/order.py:266-285`), `order.edges` answers the provider-before-consumer pairs (`:225-245`), and
`order.walk` answers the strong components in application order (`:69-101`). `manifest.resolve`
reads a prebuilt directory with no nix invocation and shells out only for a flake reference
(`cli/manifest.py:219-233`, `:248-253`), which is why the resolution is a startup step and no route
is a build. A row carries six required fields (`lib/diagnostics.nix:45-63`) and a row with no
resolution is a row nobody can act on (`:41-42`), which is why the table is held to all six.
-->

## Purpose
Defines the read-only view over one built deployment and over what the machines it names currently
hold: what the view answers with no machine asked and no evaluation run, which facts of the build it
shows, how the graph it draws is derived from the plan's own resolved reads, that the diagnostics
table carries every field of a row, that the live half asks the questions the machine report asks
and defines none of its own, and that nothing a reader can reach from it changes a machine or a
build. A reader who wants to see an infrastructure rather than read a plan reaches it through this
view, and a program that can draw the infrastructure from the plan alone is the evidence that the
plan is a complete description of one.

## ADDED Requirements

### Requirement: The view shows a built deployment without asking anything

The view SHALL answer every question about the build itself from the files the build wrote - the
plan, the manifest and the diagnostics rows - and SHALL run no evaluation and dial no machine to do
it. A view of a deployment whose machines are all switched off SHALL be complete.

The target SHALL be the target the operator's command takes, a directory a build wrote or a
reference that builds one, and it SHALL be resolved once before the view accepts a request, so that
a reference builds in the foreground where the operator can see it and no request of the view is
ever a build. A build the view cannot read SHALL be refused before it accepts a request, naming what
was missing, rather than answered per request with an error.

#### Scenario: A built deployment is shown with no machine asked

- **WHEN** the view is asked for the deployment it was started against
- **THEN** it SHALL answer with the machines, the entries placed on them, their units, the values
  and the diagnostics of that build
- **AND** no machine SHALL have been dialled and no evaluation SHALL have been run

#### Scenario: A route is asked while nothing can build or dial

- **WHEN** every route of the view is asked with no program on the path that could build or connect
- **THEN** each SHALL answer the build's own facts
- **AND** no route SHALL fail for want of a program it could have run

### Requirement: The view shows every machine, entry, unit and value the build names

The view SHALL show each machine the build names, the entries placed on it in plan key order, and
the units of each entry. For each entry it SHALL show the realiser that realises it, the profile
where one is stated, the address the machine is dialled at, the artifact's version digest and the
artifact path, and it SHALL show an entry realised into nothing as holding no artifact rather than
omitting the entry or showing an empty path.

For each value the view SHALL show its delivery set, its files, and each file's path, secrecy,
ownership and mode. It SHALL NOT show the bytes of any value: a plan carries a generated value's
path and never its content, and the view SHALL add no reading that fetches one.

#### Scenario: Every placed entry appears under the machine it is placed on

- **WHEN** a build placing entries on more than one machine is shown
- **THEN** each machine SHALL carry exactly the entries the manifest places on it, in plan key
  order
- **AND** each entry SHALL carry its realiser, its units, its digest and its artifact path

#### Scenario: A value is shown with its delivery set and its files

- **WHEN** a build delivering a generated value to two machines is shown
- **THEN** the value SHALL be shown with both machines as its delivery set
- **AND** each declared file SHALL be shown with its path, secrecy, ownership and mode, and with no
  content

#### Scenario: An entry realised into nothing is shown as holding no artifact

- **WHEN** a build carrying a placed entry that declares no unit is shown
- **THEN** that entry SHALL appear
- **AND** it SHALL be shown as holding no artifact rather than as an entry with an empty path

### Requirement: The edges the view draws are the reads the plan resolved

The graph the view draws SHALL be the resolved reads the plan records and nothing else. A read
naming one provider SHALL be one edge from that provider to the consumer, and a read naming every
provider of a capability SHALL be one edge per provider named, so that a set-valued read is as
visible as a single-valued one. A read the plan refused is absent from the record and SHALL be no
edge. An edge onto an entry the build does not place SHALL NOT be drawn.

A read recorded in a shape the view does not recognise SHALL be named - the consumer and the slot -
and SHALL NOT be silently dropped: a shape that contributes no edge in silence is what makes a
missing edge unreadable as a defect.

#### Scenario: A single valued read is one edge from its provider

- **WHEN** a build whose consumer resolves one read of one provider is shown
- **THEN** the graph SHALL carry exactly one edge, provider to consumer, labelled with the slot

#### Scenario: A read of every provider is one edge per provider

- **WHEN** a build whose consumer reads every provider of a capability is shown, and three entries
  provide it
- **THEN** the graph SHALL carry three edges into that consumer, one per provider named by the read
- **AND** each SHALL be labelled with the same slot

#### Scenario: A read recorded in a shape the view does not know is named

- **WHEN** a build is shown whose consumer records a resolved read in neither recognised shape
- **THEN** the view SHALL name the consumer and the slot
- **AND** it SHALL NOT answer as though that consumer read nothing

### Requirement: The layout of the picture is decided by the build's own data

The position of every element SHALL be a function of the build alone, computed where the view is
served rather than in the reader's browser, so that two showings of one build are identical. The
rule SHALL be stated: dependency depth decides one axis and plan key order decides the other, a
cycle the walk had to break SHALL be drawn with the edges it contradicted, and nothing SHALL move
for any other reason.

The page SHALL need no program the reader's browser has to obtain: it SHALL carry no script and
SHALL reference no asset the view did not serve itself.

#### Scenario: One deployment renders one page

- **WHEN** one build is shown twice
- **THEN** the two pages SHALL be identical
- **AND** every element's position SHALL be derivable from the build's own records

#### Scenario: A page carries no script and no asset it did not serve

- **WHEN** the page the view serves is read
- **THEN** it SHALL carry no script
- **AND** every asset it references SHALL be one the view itself serves

### Requirement: Every diagnostics row is shown with all six fields

A diagnostics row SHALL be shown with its identifier, its subject, its severity, its message, its
evidence and its resolution. A row is required to carry all six, and a row with no resolution is a
row nobody can act on, so a view that shows four of them shows a reader a row they cannot act on
while the build recorded the sentence that says how.

A deployment the planner refused SHALL be shown: its rows, and the statement that it was realised
into no entry, rather than an empty picture or a refusal to answer. Nothing about the rendering
SHALL depend on the deployment being applicable.

#### Scenario: A row is shown with its evidence and its resolution

- **WHEN** a build whose diagnostics carry one warning is shown
- **THEN** that row SHALL be shown with all six of its fields
- **AND** the evidence and the resolution SHALL be the strings the build recorded

#### Scenario: A deployment the planner refused shows its rows and no artifact

- **WHEN** a build the planner refused is shown
- **THEN** the view SHALL show its rows and SHALL state that no entry was realised
- **AND** it SHALL NOT refuse the request

### Requirement: The live half asks the questions the machine report asks and defines none

The view SHALL obtain what a machine currently holds by asking the same questions the machine report
asks, through the record that report answers with, and SHALL define no machine question, no remote
script and no verdict vocabulary of its own. It SHALL NOT parse another layer's rendered sentences:
a rendered line is a sentence for a reader and not an interface for a program.

A machine that could not be asked SHALL be shown as unasked rather than as holding nothing, because
absence is an endpoint's own answer and silence is not one. A fact the report does not answer SHALL
NOT be obtained by the view by any other means; it SHALL be a seam recorded against the report's own
capability.

The view SHALL ask only when a reader asks. It SHALL NOT poll, SHALL NOT refresh itself, and SHALL
NOT serve an answer taken earlier as though it were current: an answer SHALL be shown with when it
was taken.

#### Scenario: The live view asks the questions the report asks

- **WHEN** a reader asks the view for what the machines currently hold
- **THEN** the questions put to the machines SHALL be the questions the machine report puts
- **AND** the view SHALL have added no question and no script of its own

#### Scenario: A machine that answered nothing is shown as unasked

- **WHEN** one machine of the build answers nothing and the others answer
- **THEN** that machine SHALL be shown as unasked
- **AND** the others' answers SHALL be shown

#### Scenario: A live answer carries when it was taken

- **WHEN** a reader is shown what the machines hold
- **THEN** the answer SHALL carry the time it was taken
- **AND** no answer SHALL have been taken without a reader asking for it

### Requirement: Nothing reachable from the view changes anything

No request the view accepts SHALL change a machine, a build, a value source or a file of the
repository. It SHALL offer no apply, no retirement, no rollback and no build: an apply is a
long-running walk over machines whose recovery is running it again, so offering one needs a run
identity, a log a reader can follow, a rule for two readers at once and an answer for a browser that
closed mid-walk, which is a change of its own.

The view SHALL be served where the reader is. It SHALL bind the loopback interface, and an
instruction to listen anywhere else SHALL be refused naming the reason, because an unauthenticated
picture of a fleet's live state is not a surface to publish on a network.

#### Scenario: No route of the view changes a machine or the build

- **WHEN** every route the view accepts is exercised against a build whose machines are recorded
- **THEN** nothing SHALL have been written to any machine, to the build or to the value source
- **AND** the view SHALL offer no route that applies, retires, rolls back or builds

#### Scenario: A view asked to listen beyond the loopback interface is refused

- **WHEN** the view is asked to listen on an address that is not the loopback interface
- **THEN** it SHALL refuse naming the reason
- **AND** it SHALL NOT have accepted a connection
