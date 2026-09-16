# planner/interface-fold Specification

## Purpose
Defines the interface-owned fold of a set-valued read: where the fold is declared, what values it
receives, what it may never see, what a raising or malformed fold produces, and what an interface
whose fold is never applied is reported as. One policy per interface replaces one hand-written fold
per consuming module.

## Requirements

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

### Requirement: A fold may carry a name

The planner SHALL provide a constructor that builds a fold from a name and a function, and an
interface SHALL be able to declare either such a named fold or a bare function. A named fold SHALL
behave in every respect as the bare function it carries: it is applied to the same set, under the same
guard, with the same result, and every row about a fold SHALL read the same for both spellings.

A fold's name SHALL be a non-empty string carrying no whitespace. A named fold whose name is not one
SHALL produce an error row against the interface's declaring file, and the fold SHALL then not be
applied: a set-valued read of that interface SHALL deliver the provider-keyed set unchanged.

A fold's name SHALL exist so that two interfaces built by two evaluations can be compared. Two folds
carrying one name SHALL NOT be required to be one function, and the planner SHALL NOT compare their
behaviour.

#### Scenario: A named fold folds

- **WHEN** a slot reads with set reach an interface declaring a named fold
- **THEN** the consuming implementation SHALL receive the fold's result as that slot's value
- **AND** the outcome SHALL be the one the same fold declared as a bare function produces

#### Scenario: A raising named fold

- **WHEN** an interface's named fold raises a catchable error for the set it is given
- **THEN** the planner SHALL emit the same row it emits for a bare fold that raises
- **AND** the slot SHALL be absent from the values the consuming implementation receives

#### Scenario: A fold name that is not a name

- **WHEN** an interface declares a fold whose name is empty or carries whitespace
- **THEN** the planner SHALL emit an error row whose subject is the interface's declaring file
- **AND** a set-valued read of that interface SHALL deliver the provider-keyed set unchanged

#### Scenario: A bare fold stays legal

- **WHEN** an interface declaring no `id` declares a fold as a bare function
- **THEN** the planner SHALL apply it
- **AND** SHALL NOT emit a row for the missing name

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

### Requirement: A fold's refusal is a marker its own result cannot imitate

A fold's refusal SHALL be distinguishable from every value that fold can successfully return. The
channel a refusal travels through SHALL be a marker the planner hands the fold's author, built the
way a named fold itself is built, and a fold's own successfully computed result SHALL NOT be able to
imitate it however that result is shaped and whatever its attributes are named.

A fold SHALL therefore be free to return a record carrying an attribute of any name, including the
name the refusal channel is spelled with today, and such a result SHALL be delivered to every
consumer of that read as an accepted value. A deployment whose fold accepts every value it was given
SHALL be applicable, and the planner SHALL emit no refusal row for it.

A refusal SHALL still carry the sentence an operator reads, and the division of the row SHALL be
unchanged: the fold supplies the message, the planner supplies the identifier, the consuming entry is
the subject, and the severity is the planner's, which a module SHALL NOT be able to state. A refusal
carrying no sentence, or carrying something other than a sentence, SHALL remain a row of its own
naming the interface and the slot rather than a coerced message or a row with nothing in it.

A refused read SHALL leave the slot absent from the values the consuming implementation receives,
never present and empty, exactly as a raising fold does, and the rest of the plan SHALL still be
produced with the table reporting the plan as not applicable.

#### Scenario: A fold may return an attribute called refused

- **WHEN** a fold partitions the set it is given and its successful result carries an attribute named
  the way the refusal channel is spelled
- **THEN** the planner SHALL deliver that result to the consuming implementation as the slot's value
- **AND** no refusal row SHALL be emitted for that read
- **AND** the plan SHALL be applicable

#### Scenario: A fold refuses the set it was given

- **WHEN** a fold refuses the set it is given, through the marker the planner provides, with a
  sentence naming what it refused
- **THEN** the planner SHALL emit an error row whose message is that sentence, whose subject is the
  consuming entry and whose identifier and severity are the planner's
- **AND** the slot SHALL be absent from the values that consumer's implementation receives
- **AND** the table SHALL report the plan as not applicable
- **AND** every entry the refusal did not touch SHALL still be planned
