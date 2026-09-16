<!--
A delta against `realiser/flakelet-artifact`, which lives in the unarchived
`emit-flakelet-service-artifacts` change. One requirement changes: `A host file this realiser has no
step for is refused` (`emit-flakelet-service-artifacts/specs/realiser/flakelet-artifact/
spec.md:111-133`) refuses both kinds of host file, and one of the two kinds now has a step. The two
are already distinguishable in the reading both realisers share: a configuration file is staged from
the store to the host path (`from != path`, `image/read.nix:226-233`), while a generated file is its
own source (`from == path`, `image/read.nix:234-240`).

The three scenario headings are kept. Each names a situation; it is the outcome of the second that
moves.
-->

## MODIFIED Requirements

### Requirement: A host file this realiser has no step for is refused

The artifact SHALL be everything the machine needs, and this realiser SHALL run nothing on the
machine before the endpoint links and starts the units. An entry whose unit is shown a host file the
realiser would have to produce — a configuration file assembled from the plan, whose bytes come out
of the store and land at a path nothing else creates — SHALL therefore be refused, naming the entry,
the path and the step that does not exist, rather than rendered into a unit that names a path
nothing on the machine creates.

A generated file read by reference SHALL NOT be refused. Its host path is its own source rather than
a staging destination, and its bytes reach the machine by delivery of the value the plan names,
before the entry is activated. The realiser SHALL therefore build the entry and SHALL add no step:
the delivery is the operator's, and an entry whose value no machine receives is already refused by
the planner.

#### Scenario: An entry shown a configuration file

- **WHEN** an entry records configuration data its unit reads
- **THEN** the build SHALL fail naming the entry and that file's path

#### Scenario: An entry shown a generated file

- **WHEN** an entry's unit reads a generated file by reference
- **THEN** the artifact SHALL be built
- **AND** it SHALL carry no bytes of that file and no step that would create it

#### Scenario: An entry shown no host file is built

- **WHEN** an entry records no configuration data and reads no generated file
- **THEN** the artifact SHALL be built
