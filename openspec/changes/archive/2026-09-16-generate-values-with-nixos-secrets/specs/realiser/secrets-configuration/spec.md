## Purpose

Says what one plan becomes when it is read as a configuration for an external secret generator: one
store entry per generated value, a name projection that either holds or refuses, and the one deploy
script that carries the machine dimension the external contract does not have. The reading realises
nothing beyond the script it renders, and it refuses rather than mangling a name or guessing a
target.

## ADDED Requirements

### Requirement: A plan is readable as a generator configuration

The reading SHALL take one plan and produce a configuration the external generator consumes without
evaluating any of this library's Nix: one store entry for each generated value the plan carries,
and nothing for an entry that is not a generated value.

Each store entry SHALL carry the value's declared files, the sibling values it declared reads of as
that entry's dependencies, and the generator the deployment declared. A file the plan records as
undeployed SHALL be marked as not to be deployed, so that a value which exists for other values to
read is generated and stored and sent to no machine.

The reading SHALL NOT invent a field the plan does not record. A configuration key the external
contract requires and the plan cannot answer SHALL be refused by name rather than defaulted.

#### Scenario: A generated value becomes one store entry

- **WHEN** a plan carrying a generated value is read
- **THEN** the configuration SHALL hold exactly one store entry for that value
- **AND** that entry SHALL declare exactly the files the value declares
- **AND** an entry of the plan that is not a generated value SHALL contribute none

#### Scenario: A declared read becomes a dependency

- **WHEN** a value declares a read of a sibling value
- **THEN** the sibling SHALL appear as that entry's dependency under the same projected name
- **AND** the order the external tool derives from those dependencies SHALL be an order the plan
  already resolved, so a cycle is refused before the reading rather than during generation

#### Scenario: An undeployed value is generated and sent nowhere

- **WHEN** a value the plan records as undeployed is read
- **THEN** its store entry SHALL exist
- **AND** each of its files SHALL be marked as not to be deployed

#### Scenario: A required field the plan cannot answer is refused

- **WHEN** a value carries no generator for the external tool to run
- **THEN** the reading SHALL fail naming the entry and the field
- **AND** it SHALL NOT emit an entry with an absent or empty generator

### Requirement: The name projection holds or the reading refuses

A plan key is structured and the external contract accepts a restricted name, so the reading SHALL
project each key onto a name that contract admits, and the projection SHALL be injective over one
plan. Two values projecting onto one name SHALL be refused, naming both plan keys, because one
would otherwise overwrite the other's stored bytes.

A projection SHALL be refused where a component of the key already contains the separator the
projection uses, and where a component contains a character the external contract does not admit.
Neither SHALL be silently substituted or stripped.

A per-machine value's projected name SHALL name its machine, so that two machines' values of one
generator remain two stored values.

#### Scenario: Two values projecting onto one name are refused

- **WHEN** two plan keys project onto the same external name
- **THEN** the reading SHALL fail naming both keys and the name they collide on
- **AND** neither entry SHALL appear in the configuration

#### Scenario: A name component carrying the separator is refused

- **WHEN** an instance, generator or machine name contains the character the projection separates on
- **THEN** the reading SHALL fail naming the component and the character
- **AND** the failure SHALL state that the name is what has to change

#### Scenario: A per-machine value keeps its machine in its name

- **WHEN** one generator is declared per machine and placed on two machines
- **THEN** the configuration SHALL hold two store entries
- **AND** each projected name SHALL name its own machine

### Requirement: The deploy script is rendered from the plan

The external contract hands its deploy step a list of files and no target, so the reading SHALL
render that step itself. For each file the rendered step SHALL address exactly the machines the
value's delivery set names, at the addresses the plan records, and SHALL write the file at the path
the plan fixed.

The rendered step SHALL address no machine outside a value's delivery set, and SHALL contain none of
the bytes of any value: it names paths and machines only.

A value whose delivery set names a machine the plan gives no address for SHALL be refused by the
reading, before any script exists.

The rendered step SHALL deliver every pair the list holds, including the last one when the list ends
without a line terminator. The external tool joins the list with newlines, so its last line carries
none, and a step that dropped it would store a file and deliver nothing at the path a unit opens.

#### Scenario: The rendered step targets the delivery set

- **WHEN** the deploy step rendered from a plan is read
- **THEN** for each file it SHALL name exactly the machines the value's delivery set names
- **AND** the path it writes SHALL be the path the plan recorded for that file

#### Scenario: The last pair of the file list is delivered

- **WHEN** the rendered step is given a file list whose last line has no terminator
- **THEN** that pair SHALL be delivered like every other

#### Scenario: The rendered step carries no bytes

- **WHEN** the rendered step is searched for the bytes of any value the plan describes
- **THEN** none SHALL be found

#### Scenario: A delivery target with no address is refused

- **WHEN** a value's delivery set names a machine whose plan entry records no address
- **THEN** the reading SHALL fail naming the value and the machine
- **AND** the failure SHALL state that the machine's address is what is missing

### Requirement: The reading is pinned and fails when the external contract moves

The reading is written against one revision of an external contract that is under review and not
merged. The repository SHALL record which revision, and a check SHALL compare the contract that
revision publishes against the contract the resolved tool carries.

A disagreement SHALL fail the check, naming the file to edit and the revision recorded, so that a
reading written for a superseded contract cannot outlive it silently. Where the comparison cannot be
made at all, the check SHALL NOT fail: an unreadable signal is not evidence that the contract moved.

#### Scenario: The external contract has changed

- **WHEN** the resolved tool publishes a contract differing from the recorded revision's
- **THEN** the check SHALL fail naming the recorded revision and the file that encodes it
- **AND** the message SHALL state what to delete or rewrite

#### Scenario: The external contract cannot be read

- **WHEN** the tool cannot be resolved at all
- **THEN** the check SHALL NOT fail
- **AND** the run depending on the tool SHALL skip itself with a reason instead
