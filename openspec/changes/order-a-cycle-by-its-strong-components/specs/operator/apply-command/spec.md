<!--
A delta against `operator/apply-command`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change, was restated by `make-an-apply-observable` and is
restated again by `hold-every-stated-guarantee`. `openspec/specs/` is empty in this repository, so
the base text is read from those changes.

Every requirement below is ADDED, and deliberately: `hold-every-stated-guarantee` holds a MODIFIED
copy of `One command applies a whole deployment` that states which reads contribute edges, and this
delta states how the resulting graph is walked. Restating that requirement here would put two
edited copies of one block in two unarchived changes.

The conditions: `cli/order.py:69` and `:80-81` rescan `remaining` per entry; `cli/order.py:85-102`
rebuilds the forward adjacency and calls `_reaches` per candidate; `cli/order.py:102` is a `next`
with no default, so the invariant its docstring argues at `:93-96` fails as `StopIteration` rather
than as `ApplyError`, which `cli/planner.py:209` is the only handler for; and
`cli/apply.py:278` prints one line per contradicted edge and never names the cycle.

"An entry the run does not apply SHALL contribute no edge", in
`hold-every-stated-guarantee`, is unchanged by this delta and is what the announcement requirement
below is about: the edge stays absent, and the run says so.
-->

## ADDED Requirements

### Requirement: A cycle is broken at a component and reported as one

Where the reads the plan resolved form a cycle, the entry the command orders first among the
unorderable ones SHALL be a member of a strong component of the remaining read graph that no entry
outside it reads into. The edges the order contradicts SHALL be edges inside that component, and no
edge between two entries that are not on one cycle SHALL be contradicted.

The report SHALL name the cycle as a cycle: the entries of the component whose edge was contradicted
SHALL be named together, so that an operator can tell two entries that read each other from a
provider that an earlier decision left behind. Naming the contradicted edge alone SHALL NOT be the
whole report.

Entries within one component SHALL be ordered deterministically by plan key, and components SHALL be
walked in the dependency order between them, so that one deployment always walks one way.

#### Scenario: Two entries that read each other are named as one cycle

- **WHEN** two entries each read a capability the other provides
- **THEN** the report SHALL name both entries as a cycle the order was broken at
- **AND** SHALL name the edge or edges the order contradicted
- **AND** the deployment SHALL be applied

#### Scenario: An entry reading into a cycle is not contradicted

- **WHEN** one entry reads a capability provided by one of two entries that read each other
- **THEN** the contradicted edges SHALL all lie between the two entries that read each other
- **AND** the read the third entry declared SHALL be satisfied by the order walked
- **AND** the third entry SHALL NOT be named as part of the cycle

#### Scenario: Two separate cycles are two reports

- **WHEN** a deployment carries two disjoint pairs of entries that read each other
- **THEN** each pair SHALL be named as its own cycle
- **AND** no entry SHALL be named in a cycle it is not on

### Requirement: The order costs no more than the graph it is read from

Computing the order SHALL cost no more than the size of the read graph: the entries to apply plus the
resolved reads between them. The command SHALL NOT rescan the entries still to apply once per entry
applied, and SHALL NOT recompute a reachability question once per candidate entry.

A deployment an operator can build SHALL be a deployment the command can order without a
super-linear cost, so that ordering is never the reason a large fleet cannot be applied.

#### Scenario: A large deployment is ordered without a per-entry rescan

- **WHEN** the command orders a deployment of a thousand placed entries whose reads form a chain
- **THEN** the order SHALL be produced
- **AND** the cost of producing it SHALL grow no faster than the entries and the reads between them

#### Scenario: A large deployment carrying a cycle is ordered at the same cost

- **WHEN** the command orders a deployment of a thousand placed entries in which one pair reads each
  other
- **THEN** the order SHALL be produced with that pair's edge contradicted
- **AND** the cost SHALL be of the same order as for the same deployment without the cycle

### Requirement: An order the command cannot compute is a refusal

If the command reaches a state in which no entry can be ordered, it SHALL refuse naming the entries
it could not order and the reads between them. The refusal SHALL be the command's own, of the same
kind as every other refusal it makes, and SHALL NOT be an unhandled error or a traceback.

No state of the command SHALL depend for its correctness on an argument stated only in prose: where an
invariant decides which entry is ordered next, its violation SHALL be a refusal rather than an
unhandled error.

#### Scenario: No entry can be ordered

- **WHEN** the command reaches a state in which no entry of those remaining can be ordered
- **THEN** it SHALL refuse naming those entries and the reads between them
- **AND** the refusal SHALL be reported the way every other refusal of the command is
- **AND** no machine SHALL have been dialled after the refusal

### Requirement: A read the run will not satisfy is announced

A read whose provider the run is not applying SHALL be announced, naming the reading entry and the
provider it reads. The announcement SHALL be printed where the report of a contradicted edge is
printed, before the first machine is dialled.

Such a read SHALL remain no ordering constraint: an entry the run does not apply cannot be ordered,
so the run SHALL apply the selection it was given. What changes is that the run states which read it
is not honouring, so that a restricted apply and a broken cycle are equally visible.

#### Scenario: A restricted run activates a consumer without its provider

- **WHEN** a run is restricted to a selection that holds a consumer and not a provider it reads
- **THEN** the run SHALL announce that read, naming the consumer and the provider
- **AND** SHALL apply the consumer
- **AND** the announcement SHALL precede the first machine dialled

#### Scenario: A full run announces nothing about unapplied providers

- **WHEN** a run applies every placed entry of a deployment
- **THEN** no read SHALL be announced as unsatisfied
- **AND** the only reads reported SHALL be the edges a cycle made the order contradict
