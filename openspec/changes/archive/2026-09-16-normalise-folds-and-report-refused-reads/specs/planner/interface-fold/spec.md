## MODIFIED Requirements

### Requirement: A malformed or raising fold refuses the read, not the evaluation

The planner SHALL force a fold's result under a guard. A fold that raises a catchable error SHALL
produce an error row naming the interface and the slot, and the read SHALL then be undelivered: the
slot SHALL be absent from the values the consuming implementation receives, never present and empty.
A declared fold that is not a function SHALL produce an error row against the interface's declaring
file. Evaluation SHALL remain total: the rest of the plan SHALL still be produced, and the table SHALL
report the plan as not applicable.

That totality SHALL be understood against what the absence of the slot means for the consumer. A
refused read leaves the slot absent so that nothing can default against it, and an implementation that
reads an absent slot fails with a missing attribute, which is not catchable. The planner's rows SHALL
therefore be produced for every entry whose implementation does not force the refused slot, and an
implementation that reads the slot unconditionally SHALL end the evaluation of the whole table rather
than appear in it. Which of the two happens SHALL be the consuming module's decision and SHALL NOT be
a planner behaviour that varies: the row, the undelivered read and the inapplicable plan are produced
identically in both cases, and only the forcing of the absent slot decides whether anything can be
rendered.

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

#### Scenario: A guarded consumer still reports a refused fold

- **WHEN** every consumer of a refused set-valued read reaches its slot only where the slot is present
- **THEN** the planner SHALL emit one row per consuming entry and SHALL record that read as not
  delivered
- **AND** the table SHALL render, the plan SHALL report as not applicable, and every entry the
  refusal did not touch SHALL still be produced

#### Scenario: An unguarded consumer of a refused fold ends the evaluation

- **WHEN** a consumer of a refused set-valued read reads that slot unconditionally
- **THEN** the evaluation SHALL fail with the missing attribute rather than produce a table
- **AND** that failure SHALL be the documented consequence of a refused read, not a separate defect

## ADDED Requirements

### Requirement: One fold serves every consumer of the interface

A fold SHALL be a property of the interface and SHALL NOT vary by consumer. Every consumer that reads
the interface with set reach SHALL receive the result of that one fold. A consumer's own declared reads
SHALL still decide what enters its own fold input, so two consumers naming different reads of one
interface SHALL each receive the fold of their own projection under one policy.

Because one policy serves consumers whose outputs differ, a fold SHALL be able to return any value the
consuming implementations can use, and the rendering of bytes from a folded value SHALL remain the
consuming implementation's. Nothing SHALL require an interface to be declared twice for two consumers
that render one folded value differently.

#### Scenario: Two consumers of one fold receive one value

- **WHEN** two entries read one interface with set reach over the same providers and the same exports
- **THEN** each SHALL receive the same folded value
- **AND** each SHALL be free to produce different output from it, with both outputs recorded in the
  plan

#### Scenario: Two consumers reading different exports fold different sets

- **WHEN** two entries read one interface with set reach and declare different exports as their reads
- **THEN** each fold input SHALL carry only that consumer's declared exports
- **AND** both SHALL be folded by the interface's one fold
