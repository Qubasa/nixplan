## Purpose

Defines the consumer half of a typed cross-service edge: how an interface is identified, what an export declares, what a provider must publish, what a slot may ask for, and which of those the planner refuses. This is the smallest set of constructs that changes an outcome, so every requirement here names a refusal that a flat untyped export map cannot state.

## ADDED Requirements

### Requirement: An interface is a value and its name is a label

An interface SHALL be identified by the value an author imported, never by a name resolved at composition time, and SHALL NOT be validated against any registry of known interfaces. An interface's `name` SHALL be used only in diagnostic output. Two interfaces declared in different files MAY carry the same `name`.

#### Scenario: Two interfaces share a name

- **WHEN** two distinct interface values carry the same `name` and a slot on one is wired to a capability declaring the other
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL render the declaring file of each interface beside its name, so the two are distinguishable in output

#### Scenario: An interface nobody upstreamed

- **WHEN** a module declares an interface that no other module or library file references
- **THEN** the planner SHALL accept it
- **AND** SHALL NOT require it to appear in any list the planner owns

#### Scenario: A misspelled capability reference

- **WHEN** a module re-exports a capability under a name its member does not provide
- **THEN** the failure SHALL occur while evaluating that module file
- **AND** SHALL NOT be deferred to wire resolution

### Requirement: An export atom declares a type and a secrecy and nothing else

An export atom SHALL declare `type` and MAY declare `secrecy`. An omitted `secrecy` SHALL mean `public`. `secrecy` SHALL take exactly the values `public` and `secret`. An atom carrying any other key, including `locality` or `lifecycle`, SHALL produce an error row naming the key and stating the condition that would introduce it.

#### Scenario: An atom omits secrecy

- **WHEN** an atom declares only `type`
- **THEN** the export SHALL be treated as `public`
- **AND** no row SHALL be emitted

#### Scenario: An atom declares a locality

- **WHEN** an atom declares `locality`
- **THEN** the planner SHALL emit an error row naming the atom and the key
- **AND** the row SHALL state that the field is absent until an export in the target carries a value that cannot leave its machine
- **AND** the planner SHALL NOT silently accept and discard the key

#### Scenario: A value does not match its declared type

- **WHEN** a provider publishes an export whose value fails its atom's type
- **THEN** the planner SHALL emit an error row at the provider that produced it
- **AND** the row SHALL name the provider rather than any consumer that reads the export

### Requirement: A provider's export keyset equals its interface's keyset

A capability's published exports SHALL have exactly the key set its interface declares. An omitted export SHALL be an error row and an extra export SHALL be an error row. No superset of a narrower interface's keyset SHALL satisfy that interface.

#### Scenario: A provider omits an export

- **WHEN** a capability declares an interface with two exports and publishes one
- **THEN** the planner SHALL emit an error row naming the missing export, the publishing file and the interface's declaring file

#### Scenario: A provider publishes an extra export

- **WHEN** a capability publishes an export its interface does not declare
- **THEN** the planner SHALL emit an error row naming the extra export
- **AND** SHALL NOT deliver that export to any consumer

### Requirement: A slot declares an interface, an arity and the exports it reads

A slot SHALL declare `interface`, MAY declare `reach`, and MAY declare `reads`. An omitted `reach` SHALL mean `one`. `reach` SHALL take the values `one` and `all` in this capability; `local` SHALL be refused with a row stating that it requires the co-placement machinery this subset does not carry. An omitted `reads` SHALL mean every export of the interface. A `reads` entry naming an export the interface does not declare SHALL be an error row.

#### Scenario: A slot is never wired

- **WHEN** a module declares a slot and no deployment wires it
- **THEN** the planner SHALL emit an error row naming the slot and the interface's declaring file
- **AND** the slot SHALL NOT resolve to an empty value that a consumer could read

#### Scenario: A slot declares reach local

- **WHEN** a slot declares `reach = "local"`
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL state that `local` derives from a locality this subset does not declare

#### Scenario: reads names an export that does not exist

- **WHEN** a slot's `reads` names an export absent from its interface
- **THEN** the planner SHALL emit an error row naming the slot, the entry and the interface

### Requirement: A slot may not read a secret export

A `reads` entry naming an export whose `secrecy` is `secret` SHALL be refused outright, on every machine and regardless of placement. A secret export SHALL remain declarable, so that the refusal is producible and the pair is visible. A service SHALL be able to use a secret value it produced itself without routing it through a slot.

#### Scenario: A consumer asks for the private half

- **WHEN** a slot's `reads` names an export declared `secret`
- **THEN** the planner SHALL emit an error row naming the slot, the export and the interface's declaring file
- **AND** the refusal SHALL NOT depend on whether the provider and the consumer are placed on one machine

#### Scenario: A producer uses its own secret

- **WHEN** a service reads a secret value it generated and passes it to one of its own units
- **THEN** the planner SHALL accept it
- **AND** the value SHALL appear in the plan as a reference rather than as content

#### Scenario: A secret export with no reader

- **WHEN** a capability declares a secret export that no slot reads
- **THEN** the planner SHALL accept the declaration
- **AND** SHALL record the export as declared and delivered to nobody

### Requirement: A wire names an exposed capability of a named instance

A deployment SHALL fill a slot by naming an instance and one of its exposed capabilities. A capability that an instance does not expose SHALL NOT be addressable from outside that instance. When a wire names an instance or a capability that does not exist, the planner SHALL emit an error row carrying the candidate list it holds.

#### Scenario: A wire names a capability that is not exposed

- **WHEN** a wire names a capability a target instance provides but does not list in `exposes`
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL list the capabilities that instance does expose

#### Scenario: A wire names an unknown instance

- **WHEN** a wire names an instance absent from the deployment
- **THEN** the planner SHALL emit an error row naming the wire and listing the deployment's instance names

#### Scenario: Two instances wire each other

- **WHEN** two instances each wire a slot to a capability the other exposes, and every export involved is known at evaluation
- **THEN** the planner SHALL resolve both reads
- **AND** neither entry SHALL appear in the other's dependency list
- **AND** the pair SHALL NOT be reported as a cycle

### Requirement: Reach is checked against the placements of the wired capability

The planner SHALL count the placements of the wired capability after placement is decided and check that count against the slot's `reach`. Under `one` the consumer SHALL receive a single export set. Under `all` the consumer SHALL receive an attribute set keyed by machine, including when the wired capability has exactly one placement.

#### Scenario: A single-valued read of a set

- **WHEN** a slot declares `reach = "one"` and the wired capability has two placements
- **THEN** the planner SHALL emit an error row naming the slot and both placements
- **AND** SHALL NOT deliver either placement to the consumer

#### Scenario: A set-valued read of one placement

- **WHEN** a slot declares `reach = "all"` and the wired capability has one placement
- **THEN** the consumer SHALL receive an attribute set with one entry keyed by machine
- **AND** the shape SHALL NOT collapse to a single export set

#### Scenario: An entry of a set has no value

- **WHEN** a slot declares `reach = "all"` and one placement of the wired capability declares an export whose bytes do not exist yet
- **THEN** the collected set SHALL contain a named entry for that placement
- **AND** the planner SHALL emit an error row naming that entry
- **AND** the set SHALL NOT be shortened by dropping the entry

### Requirement: A composition decides which settings a deployment may move

A root SHALL key each member's settings under that member's own name, including when it owns exactly one member, and SHALL forward nothing. A root SHALL declare each knob it owns as either a default a deployment may overwrite or a fixed value it may not. A deployment definition against a fixed path SHALL be an error row naming both files.

A member's declaration SHALL be read exactly once per instance, against the settings that instance resolved, so that the capabilities a root publishes and the exports a placement produces are derived from one value. The set of capabilities a member provides MAY therefore be derived from that member's resolved settings, and a knob such a set is derived from SHALL be an ordinary default or fixed value with no additional status. What an instance may expose, what a wire may name, and what the plan publishes SHALL agree for every deployment.

#### Scenario: A deployment overwrites a default

- **WHEN** a deployment sets a member setting the root declared as a default
- **THEN** the deployment's value SHALL be used
- **AND** the plan SHALL record the deployment as the source of that value

#### Scenario: A deployment writes to a fixed path

- **WHEN** a deployment sets a member setting the root declared as fixed
- **THEN** the planner SHALL emit an error row naming the deployment file and the module file
- **AND** neither value SHALL silently win

#### Scenario: A single-member root still keys its namespace

- **WHEN** a root owns one member named `server` and a deployment sets that member's `quota`
- **THEN** the deployment SHALL address it as the member's `quota` under the member's name
- **AND** a definition written without the member name SHALL be an error row

#### Scenario: A deployment decides the capability set

- **WHEN** a member derives the capabilities it provides from a setting, and a deployment overwrites that setting with a longer list than the member's default
- **THEN** every capability the resolved setting names SHALL be exposable by the instance and namable by a wire
- **AND** the plan SHALL publish exactly those capabilities with their exports
- **AND** no row SHALL claim the root does not provide a capability the resolved setting names

#### Scenario: A wire names a capability the deployment added

- **WHEN** a deployment adds a capability through such a setting and wires a consuming slot to it
- **THEN** the read SHALL be delivered and the plan SHALL record the consumer on that capability's exports
- **AND** evaluation SHALL NOT fail on a missing slot

#### Scenario: A capability set derived from a knob nobody declared

- **WHEN** a deployment writes a setting the member declares neither as a default nor as fixed, and the member derives its capability set from that setting
- **THEN** the planner SHALL emit the undeclared-knob error row naming the member and the knob
- **AND** the capability set SHALL be derived from the member's own declared value
