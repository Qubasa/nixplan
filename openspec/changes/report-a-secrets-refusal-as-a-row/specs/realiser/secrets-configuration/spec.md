<!--
A delta against `realiser/secrets-configuration`, which lives in the unarchived
`generate-values-with-nixos-secrets` change. `openspec/specs/` is empty in this repository, so the
three MODIFIED requirements below are that change's own, copied whole and edited: each one currently
says the reading "SHALL fail" or "SHALL be refused", and `secrets/read.nix` holds thirteen `fail`
sites against an empty diagnostics table, so an implementation that raises with no row above it reads
as satisfying them.

The subjects are `secrets/read.nix:59-64` (`required`), `:90-97` (`component`), `:126-133`
(`fileName`), `:140-148` (`collisionsOf`), `:167-171` (the program), `:203-213` (`addressOf`),
`secrets/backend.nix:30-39` (the shell word rule) and `:59-67` (`parentOf`), and
`operator/default.nix:230`, which renders the table only when the plan is inapplicable.

The layered rule this delta holds the reading to is `planner/diagnostics` in
`report-every-refusal-as-a-row`, which states that a refusal belongs to the layer holding the fact
and that a realiser is never the first to speak. Which conditions the *planner* rows about is not
this capability: a name that cannot enter a plan key belongs to `planner/plan-artifact` in
`hold-every-stated-guarantee`, and this delta rows about the external contract's grammar, which no
layer above the reading knows.
-->

## ADDED Requirements

### Requirement: The reading of a plan as a configuration is total

Reading a plan as a generator configuration SHALL be total: it SHALL answer with a diagnostics table
beside its result, and SHALL NOT raise for a condition it can report. Every condition the reading
refuses SHALL be a row naming the value entry it is about, and the row SHALL carry a resolution
naming the declaration to change.

Rows the reading produces SHALL be built through the same row constructors the planner's own rows
are, so that one condition renders as one line whatever the deployment interpolated into it, and so
that the severity of a row is the producing layer's to state and never the author's.

A reading asked for its rows SHALL realise nothing: no derivation, no filesystem read, and no
rendered script.

#### Scenario: A plan the reading refuses still answers with a table

- **WHEN** a plan carrying a condition the reading refuses is read for its rows
- **THEN** the reading SHALL answer with a table carrying a row for that condition
- **AND** SHALL NOT raise
- **AND** the row SHALL name the value entry and what has to change

#### Scenario: Every condition of one plan is reported, not the first

- **WHEN** one plan carries two conditions the reading refuses
- **THEN** the table SHALL carry a row for each of them
- **AND** neither row SHALL depend on which condition was read first

### Requirement: The conditions only this reading knows are its own rows

The external contract's requirements are facts no layer above this reading holds, so each SHALL be a
row of this reading rather than a raise or a planner row:

- a value entry recording no program to run, where the contract runs one program per stored value;
- a generated file whose name the contract does not admit, and a file carrying the name the contract
  reserves for its own provenance record;
- two plan keys projecting onto one stored name;
- a recipient machine whose plan record carries no address, where the rendered step has to dial it;
- an address or a path the rendered step cannot carry as a single shell word.

Each row SHALL name both sides of the fact it reports: the value entry and the field, the file and
the grammar, both plan keys and the name they collide on, or the value and the machine.

A row about a recipient machine's address SHALL be an error of this reading even though the same
absence is a warning of a deployment build, because the rendered deploy step is the one artifact that
carries an address and it cannot be rendered without one.

#### Scenario: A value with no program is a row

- **WHEN** a plan carries a generated value whose entry records no program
- **THEN** the reading SHALL report a row naming the entry and the program field
- **AND** the resolution SHALL name declaring a program on the generator, or reading the plan with
  something that needs none

#### Scenario: A file name outside the contract's grammar is a row

- **WHEN** a generated value declares a file whose name the external contract does not admit
- **THEN** the reading SHALL report a row naming the file, the value and the characters the contract
  admits

#### Scenario: The contract's reserved provenance name is a row

- **WHEN** a generated value declares a file carrying the name the contract keeps for its own
  provenance record
- **THEN** the reading SHALL report a row naming the file and the value
- **AND** the row SHALL state that the file is what has to be renamed

#### Scenario: A recipient machine with no address is an error row

- **WHEN** a deployed value's delivery set names a machine whose plan record carries no address
- **THEN** the reading SHALL report an error row naming the value and the machine
- **AND** a deployment build of the same plan SHALL still report that absence as a warning and build
  every artifact

#### Scenario: An address the rendered step cannot carry is a row

- **WHEN** a machine of a delivery set records an address the rendered step cannot carry as one
  shell word
- **THEN** the reading SHALL report a row naming the machine, the address and the characters a
  rendered word admits

### Requirement: A generation build carries the table it was refused by

A build that reads a plan as a generator configuration SHALL produce the diagnostics it produced in
both a machine-readable and a rendered form, beside the configuration, the name mapping and the
expression it writes. Both SHALL be present whether or not the table holds a row.

A table carrying an error SHALL refuse the build with the rendered table, and the refusal SHALL be
that table rather than a message from the reading. A table carrying warnings and no error SHALL
build, because a warning that stopped a build would be an error.

The refusal SHALL cover the rows of the plan and the rows of the reading alike, so that an operator
reading one table sees every reason the generation was refused.

#### Scenario: A refused generation names every reason in one table

- **WHEN** a generation build is refused
- **THEN** the refusal SHALL be the rendered table of the plan's rows and the reading's rows together
- **AND** SHALL NOT be a message naming one condition

#### Scenario: A generation build carries both halves of its table

- **WHEN** a generation build succeeds
- **THEN** its result SHALL carry the diagnostics in a machine-readable form and in a rendered form
- **AND** both SHALL be present when the table is empty

#### Scenario: A warning does not refuse a generation

- **WHEN** the table of a generation build carries warnings and no error
- **THEN** the build SHALL produce the configuration, the name mapping and the expression
- **AND** the warnings SHALL be readable in both halves of its table

## MODIFIED Requirements

### Requirement: A plan is readable as a generator configuration

The reading SHALL take one plan and produce a configuration the external generator consumes without
evaluating any of this library's Nix: one store entry for each generated value the plan carries,
and nothing for an entry that is not a generated value.

Each store entry SHALL carry the value's declared files, the sibling values it declared reads of as
that entry's dependencies, and the generator the deployment declared. A file the plan records as
undeployed SHALL be marked as not to be deployed, so that a value which exists for other values to
read is generated and stored and sent to no machine.

The reading SHALL NOT invent a field the plan does not record. A configuration key the external
contract requires and the plan cannot answer SHALL be reported as a row naming the entry and the
field, and no store entry for that value SHALL be emitted.

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
- **THEN** the reading SHALL report a row naming the entry and the field
- **AND** it SHALL NOT emit an entry with an absent or empty generator
- **AND** it SHALL NOT raise

### Requirement: The name projection holds or the reading refuses

A plan key is structured and the external contract accepts a restricted name, so the reading SHALL
project each key onto a name that contract admits, and the projection SHALL be injective over one
plan. Two values projecting onto one name SHALL be reported as a row naming both plan keys, because
one would otherwise overwrite the other's stored bytes.

A projection SHALL be refused where a component of the key already contains the separator the
projection uses, and where a component contains a character the external contract does not admit.
Neither SHALL be silently substituted or stripped, and each SHALL be a row rather than a raise.

A per-machine value's projected name SHALL name its machine, so that two machines' values of one
generator remain two stored values.

#### Scenario: Two values projecting onto one name are refused

- **WHEN** two plan keys project onto the same external name
- **THEN** the reading SHALL report a row naming both keys and the name they collide on
- **AND** neither entry SHALL appear in the configuration

#### Scenario: A name component carrying the separator is refused

- **WHEN** an instance, generator or machine name contains the character the projection separates on
- **THEN** the reading SHALL report a row naming the component and the character
- **AND** the row SHALL state that the name is what has to change

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

A value whose delivery set names a machine the plan gives no address for SHALL be reported as a row
before any script exists, and no step SHALL be rendered for that value.

An address or a path the rendered step cannot carry as a single shell word SHALL be a row naming the
value, the offending text and what a rendered word admits. The reading SHALL NOT quote its way around
one, and SHALL NOT render a step it cannot render safely.

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
- **THEN** the reading SHALL report a row naming the value and the machine
- **AND** the row SHALL state that the machine's address is what is missing
- **AND** no step SHALL be rendered for that value
