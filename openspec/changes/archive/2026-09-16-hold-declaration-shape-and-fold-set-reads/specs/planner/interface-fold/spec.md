## Purpose

Defines the interface-owned fold of a set-valued read: where the fold is declared, what values it
receives, what it may never see, what a raising or malformed fold produces, and what an interface
whose fold is never applied is reported as. One policy per interface replaces one hand-written fold
per consuming module.

## ADDED Requirements

### Requirement: An interface may own the fold of a set-valued read

An interface SHALL be able to declare a fold beside its exports. When a slot reads that interface
with set reach, the planner SHALL apply the fold to the set of provider values and SHALL deliver the
fold's result as that slot's value to the consuming implementation. An interface that declares no
fold SHALL deliver the set unchanged, keyed by provider entry, exactly as it does today. A fold SHALL
be optional in every position an interface may be written.

#### Scenario: A fold replaces the provider-keyed set

- **WHEN** a slot reads with set reach an interface that declares a fold
- **THEN** the consuming implementation SHALL receive the fold's result as that slot's value
- **AND** the plan's read record SHALL still name every provider entry that contributed

#### Scenario: An interface without a fold is unchanged

- **WHEN** a slot reads with set reach an interface that declares no fold
- **THEN** the consuming implementation SHALL receive the set keyed by provider entry
- **AND** no row SHALL be emitted for the absence of a fold

#### Scenario: A single-valued read does not apply a fold

- **WHEN** a slot declares single reach against an interface that declares a fold
- **THEN** the consuming implementation SHALL receive the read values directly
- **AND** the fold SHALL NOT be applied to that read
- **AND** no row SHALL be emitted for that slot

### Requirement: A fold receives only what the slot declared it reads

A fold's input SHALL be keyed by provider entry key, and each entry SHALL carry exactly the exports
the consuming slot declared it reads. A fold SHALL NOT be able to observe an export the slot did not
name, and SHALL NOT be able to observe a secret export, which a slot may not name. Applying a fold
SHALL NOT change which entries a read names, which machines a generated value is delivered to, or
any dependency the plan records.

#### Scenario: A fold sees no export the slot did not read

- **WHEN** an interface declares two exports and a slot reading it with set reach names one
- **THEN** each entry of the fold's input SHALL carry only the named export
- **AND** the export the slot did not name SHALL be absent rather than null

#### Scenario: A fold does not widen a delivery set

- **WHEN** a slot with set reach reads an export backed by a generated file, through an interface
  that declares a fold
- **THEN** the delivery set of that generated value SHALL be the one the declared read produces
  without the fold
- **AND** the plan's recorded derivation of that delivery set SHALL name the same reads

#### Scenario: The fold's input is keyed by provider entry

- **WHEN** two placements of one capability contribute to a set-valued read
- **THEN** the fold's input SHALL be keyed by each provider's plan entry key
- **AND** two evaluations of the same deployment SHALL present the same keys

### Requirement: A malformed or raising fold refuses the read, not the evaluation

The planner SHALL force a fold's result under a guard. A fold that raises a catchable error SHALL
produce an error row naming the interface and the slot, and the read SHALL then be undelivered: the
slot SHALL be absent from the values the consuming implementation receives, never present and empty.
A declared fold that is not a function SHALL produce an error row against the interface's declaring
file. Evaluation SHALL remain total: the rest of the plan SHALL still be produced, and the table SHALL
report the plan as not applicable.

#### Scenario: A fold raises

- **WHEN** an interface's fold raises a catchable error for the set it is given
- **THEN** the planner SHALL emit an error row naming the interface and the slot
- **AND** the plan SHALL still be produced for every other entry
- **AND** the table SHALL report the plan as not applicable

#### Scenario: A refused fold leaves the slot absent

- **WHEN** a fold has raised for a slot
- **THEN** that slot SHALL be absent from the values the consuming implementation receives
- **AND** an implementation reading it SHALL fail loudly rather than observe an empty set

#### Scenario: A declared fold is not a function

- **WHEN** an interface declares a fold that is not a function
- **THEN** the planner SHALL emit an error row whose subject is the interface's declaring file
- **AND** the row SHALL name the interface and state what a fold is applied to

### Requirement: An interface whose fold is never applied is reported

When a deployment resolves no set-valued read of an interface that declares a fold, the planner SHALL
emit a warning row naming that interface, because a fold nobody applies is a policy nobody is held
to. The row SHALL be a warning: an unapplied fold refuses nothing.

#### Scenario: A fold nobody reaches

- **WHEN** an interface declares a fold and every resolved read of it declares single reach
- **THEN** the planner SHALL emit a warning row naming the interface
- **AND** the plan SHALL remain applicable

#### Scenario: A fold applied at least once

- **WHEN** at least one resolved read of an interface with a fold declares set reach
- **THEN** no unapplied-fold row SHALL be emitted for that interface
