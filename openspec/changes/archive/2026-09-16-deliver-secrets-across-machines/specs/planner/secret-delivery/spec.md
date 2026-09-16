<!--
A new capability. It owns what a module says about a generated value - how many of it exist,
whether any machine receives it, and which siblings it reads - and the set of machines the planner
derives for it. The entry that carries the result is `planner/plan-artifact`'s; the read that puts a
consumer's machine in the set is `planner/typed-edge`'s.
-->

## ADDED Requirements

### Requirement: A generated value declares how many of it exist

`vars.<generator>.per` SHALL take exactly `"instance"` and `"placement"`. An omitted `per` SHALL
mean `"placement"`. `"instance"` SHALL mean one value for the instance, independent of how many
machines the owning member is placed on; `"placement"` SHALL mean one value per machine it is placed
on. A `per` outside the domain SHALL produce an error row naming the generator, the value written
and the two values it takes.

Two members of one instance SHALL NOT declare the same generator name, because a generator is
addressed by instance and name and the two declarations would be one address for two values. The
second SHALL produce an error row naming the instance, the generator and both members.

#### Scenario: A generator states one value for the instance

- **WHEN** a member placed on three machines declares a generator with `per = "instance"`
- **THEN** the planner SHALL resolve one value for that generator
- **AND** every placement of that member SHALL read the same path for each of its files

#### Scenario: A generator states one value per placement

- **WHEN** a member placed on three machines declares a generator with `per = "placement"`
- **THEN** the planner SHALL resolve one value per placement
- **AND** each placement's value SHALL be identified by that placement's machine

#### Scenario: A cardinality outside the domain

- **WHEN** a generator declares a `per` that is neither `"instance"` nor `"placement"`
- **THEN** the planner SHALL emit an error row naming the generator, the value written and both
  admitted values
- **AND** the rest of the deployment SHALL still be planned

#### Scenario: Two members claim one generator name

- **WHEN** two members of one instance each declare a generator called `app`
- **THEN** the planner SHALL emit an error row naming the instance, the generator name and both
  members
- **AND** the row SHALL be produced once for the instance rather than once per placement

### Requirement: A generated value is delivered to the machines that need it

The planner SHALL record, for each generated value, the set of machines that receive its bytes. That
set SHALL be the machines the owning member is placed on, plus the machine of every entry that
declares a read of an export whose published value is a file of that generator. It SHALL be derived
from nothing else: not from the value, not from the interface, and not from what `impl` interpolates.

The planner SHALL also record, in a stable order, the reason each machine is in the set, naming the
entry and — for a reader — the slot and export it declared.

#### Scenario: The owner receives its own value

- **WHEN** a member declares a generator and no slot anywhere reads an export backed by it
- **THEN** the delivery set SHALL be exactly the machines that member is placed on

#### Scenario: A declared read adds the reader's machine

- **WHEN** a consumer on another machine declares a read of a secret export whose value is a file of
  that generator
- **THEN** the delivery set SHALL contain the consumer's machine as well as the owner's
- **AND** the recorded reason SHALL name the consuming entry, its slot and the export

#### Scenario: An undeclared export delivers to nobody

- **WHEN** a consumer's `uses.<slot>.reads` omits an export whose value is a file of that generator
- **THEN** the consumer's machine SHALL NOT be in that generator's delivery set
- **AND** the export SHALL be absent from the consumer's `results`, so the omission cannot be
  defaulted around

#### Scenario: A machine running neither is not in the set

- **WHEN** a third machine runs a member of neither the owning nor the reading instance
- **THEN** it SHALL NOT appear in the delivery set of either value

### Requirement: A value nobody receives is stated, not implied

`vars.<generator>.deploy` SHALL be a boolean defaulting to `true`, and SHALL decide whether any
machine receives that generator's bytes. `per` and `deploy` SHALL be independent: one value may
exist and no machine receive it.

A `deploy = false` generator's public files SHALL still carry their value in the plan, because a
value the plan holds needs no file on a machine. Anything that would open one of its files on a
machine SHALL be refused: a unit or configuration file of the owning module naming the path, and a
consumer's declared read of a secret export backed by it. Each refusal SHALL name the generator, the
file and the site that opens it.

#### Scenario: A value nobody receives

- **WHEN** a generator declares `deploy = false`
- **THEN** its delivery set SHALL be empty
- **AND** the entry SHALL record that the value exists

#### Scenario: A unit opens a value nobody receives

- **WHEN** a unit of the owning module names the path of a file of a `deploy = false` generator
- **THEN** the planner SHALL emit an error row naming the generator, the file and the unit
- **AND** the row SHALL state that the path resolves to nothing at run time

#### Scenario: A consumer reads a value nobody receives

- **WHEN** a slot's `reads` names a secret export whose value is a file of a `deploy = false`
  generator
- **THEN** the planner SHALL emit an error row naming the consuming slot, the export and the
  generator

#### Scenario: A public file of an undeployed generator still travels

- **WHEN** a `deploy = false` generator declares a public file whose bytes the planner was given,
  and the module publishes that file's value as a public export
- **THEN** the export SHALL carry the value
- **AND** no machine SHALL be in that generator's delivery set

### Requirement: A generator may read its siblings within its own cardinality

`vars.<generator>.reads` SHALL name generators of the same module. A generator SHALL be able to read
a sibling of the same or a coarser cardinality: `"placement"` may read `"instance"`, `"instance"`
may read `"instance"`, `"placement"` may read `"placement"`. A `"instance"` generator reading a
`"placement"` one SHALL produce an error row, because the placements hold one value each and the
reader is one value, so the read has no single answer. A `reads` entry naming a generator the module
does not declare SHALL produce an error row listing the generators it does declare.

#### Scenario: A machine-specific value reads a shared one

- **WHEN** a `per = "placement"` generator reads a `per = "instance"` sibling
- **THEN** the planner SHALL accept it
- **AND** each placement's entry SHALL depend on the one shared value's entry

#### Scenario: A shared value reads a machine-specific one

- **WHEN** a `per = "instance"` generator reads a `per = "placement"` sibling
- **THEN** the planner SHALL emit an error row naming both generators and both cardinalities
- **AND** the resolution SHALL state that reversing the direction is the shape that works

#### Scenario: A generator reads a sibling that is not declared

- **WHEN** a generator's `reads` names a generator the module does not declare
- **THEN** the planner SHALL emit an error row naming the generator, the name read and the
  generators the module declares

### Requirement: Delivery moves bytes the plan never holds

A delivered value SHALL be named by the plan and carried by nothing in it: for every secret file, the
plan SHALL hold the path and the delivery set and no content, on the provider's entry, on every
reader's entry and on the value's own entry.

#### Scenario: A delivered secret carries no bytes

- **WHEN** a secret is delivered to two machines and read by a consumer on one of them
- **THEN** the plan SHALL record the path, the delivery set and the reason for each machine
- **AND** the bytes the planner was given SHALL appear in no entry of the plan
