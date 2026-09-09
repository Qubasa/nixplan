<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `operator/deployment-build` in this same change, which owns what a build produces, and
against `delivery/real-cluster` in `prove-plan-on-real-machines`, which owns what a real machine is
asked and what may not be a double. This capability owns the command: the order, the refusals, and
what an operator types.
-->

## Purpose

Defines the one command that puts a built deployment on the machines it names, so that the steps
between a plan and a running service are a program with a contract rather than a script each caller
writes. It owns the order the steps happen in, where the bytes of a generated value come from, what is
refused before a machine is dialled, and what the command does on a machine it reaches.

## ADDED Requirements

### Requirement: One command applies a whole deployment

Applying a deployment SHALL be one command over a built deployment. It SHALL derive the order of its
steps from the plan and SHALL NOT require the caller to state it: an artifact SHALL be on its machine
before it is activated there, every generated value a machine receives SHALL be written before any
unit that may read it is activated, and an entry that provides a capability SHALL be activated before
an entry that reads it.

The provider-before-consumer edges SHALL be taken from the reads the plan resolved, not from the key
provenance the plan records for other purposes. Where the edges form a cycle — which two instances
wiring each other legitimately do — the command SHALL break it deterministically and SHALL report the
edge it broke, rather than refusing a deployment the planner accepted.

#### Scenario: An entry is copied before it is activated

- **WHEN** the command applies one entry
- **THEN** the copy of its artifact to its machine SHALL precede the activation on that machine
- **AND** the address dialled SHALL be the one the plan records for that machine

#### Scenario: A provider is applied before its consumer

- **WHEN** one entry reads a capability another provides
- **THEN** the provider SHALL be activated before the consumer
- **AND** the order SHALL come from the plan rather than from the order the caller named the entries
  in

#### Scenario: Two entries each read the other's capability

- **WHEN** two entries each read a capability the other provides
- **THEN** the command SHALL apply both
- **AND** SHALL report which edge it ordered against
- **AND** SHALL NOT refuse the deployment

### Requirement: The bytes of a generated value come from outside the plan

The command SHALL take the bytes of a generated value from a source the operator names, never from
the plan or an artifact. For each value entry it SHALL write each declared file to every machine the
entry's delivery set names, at the path the entry records, outside the store, readable only by the
user the units run as. A value whose delivery set is empty SHALL be written nowhere.

The source SHALL be checked against the plan before anything is dialled: a file the plan names that
the source does not hold, and a file the source holds that the plan does not name, SHALL both be
refusals naming the entry and the file.

#### Scenario: A value the plan names has no bytes in the source

- **WHEN** the command is given a value source missing a file the plan declares
- **THEN** it SHALL refuse naming the value entry and the file
- **AND** no machine SHALL have been dialled

#### Scenario: A value source carries bytes the plan does not name

- **WHEN** the value source holds a file no value entry of the plan declares
- **THEN** the command SHALL refuse naming the file
- **AND** SHALL NOT write it to any machine

#### Scenario: A secret is applied from the operator's value source

- **WHEN** a deployment whose consumer reads a secret export is applied with a value source holding
  that secret
- **THEN** the file SHALL be present on each machine of the delivery set and on no other machine
- **AND** the consuming unit SHALL authenticate to the provider with it
- **AND** the bytes SHALL appear in no artifact the command built

### Requirement: The command refuses before it dials

Every refusal the command can make from the plan and the manifest alone SHALL happen before the first
machine is contacted, and SHALL name the entry, the field and the value at fault. A deployment the
planner reports as inapplicable SHALL NOT be applied, and an entry the caller names that the plan does
not carry SHALL be refused naming the entries that exist.

#### Scenario: A deployment the planner refuses is not applied

- **WHEN** the command is asked to apply a deployment whose diagnostics carry an error
- **THEN** it SHALL refuse with the rendered diagnostics table
- **AND** no machine SHALL have been dialled

#### Scenario: An entry named on the command line is not in the plan

- **WHEN** the caller restricts the command to an entry the plan does not carry
- **THEN** it SHALL refuse naming the entry given and the entries the plan carries
- **AND** no machine SHALL have been dialled

### Requirement: What the command does on a machine

On a machine the command SHALL use what is already there: the machine's own service manager, the
endpoint's own binary for an artifact the endpoint activates, and the artifact's own attach script for
a portable-service image. It SHALL report what each machine reported. It SHALL be able to ask a
machine what it holds and to return one entry to its previous generation.

#### Scenario: An image entry is attached by the command

- **WHEN** the command applies an entry realised as a portable-service image
- **THEN** the attachment SHALL be performed by the script the artifact carries
- **AND** every unit the attachment names SHALL be running on the machine afterwards

#### Scenario: The command rolls one entry back

- **WHEN** the command is asked to roll one entry back after a second generation was applied
- **THEN** the machine SHALL run the previous generation again
- **AND** the command SHALL report the generation it came from

#### Scenario: The command reports what a machine holds

- **WHEN** the command is asked for the status of an applied deployment
- **THEN** it SHALL report, per entry, what the machine's own endpoint reports for it
- **AND** an entry the machine does not hold SHALL be reported as absent rather than as an error
