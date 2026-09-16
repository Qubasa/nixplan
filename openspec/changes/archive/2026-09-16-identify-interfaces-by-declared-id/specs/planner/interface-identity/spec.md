## Purpose

Defines what makes two interfaces one interface: the value an author imported, or an identity that
author claimed with a declared `id`. States what an identity is made of, what two disagreeing claims
produce, which side verifies a matched edge's values, and what a claim deliberately does not prove.
This is what lets a service written by one author be wired to a service written by another, whose
evaluation of this library is not the same evaluation.

## ADDED Requirements

### Requirement: An interface may claim an identity

An interface SHALL be able to declare an `id` beside its name and exports. A declared `id` SHALL be a
non-empty string carrying no whitespace. An interface that declares no `id` SHALL be identified by its
value exactly as it is today, and SHALL NOT be reported for the absence.

A declared `id` that is not a non-empty whitespace-free string SHALL produce an error row whose
subject is the interface's declaring file, and the claim SHALL be disregarded: that interface SHALL
then be identified by its value.

#### Scenario: An interface claims no identity

- **WHEN** an interface declares no `id`
- **THEN** the planner SHALL identify it by its value
- **AND** no row SHALL be emitted for the absent claim

#### Scenario: One claim spans two evaluations

- **WHEN** two interfaces of one shape are built by two independent evaluations of this library and
  both declare the same `id`
- **THEN** a slot declaring one SHALL match a capability declaring the other
- **AND** no mismatch row SHALL be emitted for that edge

#### Scenario: A malformed claim is refused and disregarded

- **WHEN** an interface declares an `id` that is not a non-empty string free of whitespace
- **THEN** the planner SHALL emit an error row whose subject is that interface's declaring file
- **AND** that interface SHALL be identified by its value for every edge it takes part in

### Requirement: An identity is the claim and the shape it claims to have

An interface's identity SHALL be its `id`, the set of its export names, each export's korora type
name and secrecy, and the name of its fold, which SHALL be absent when it declares none. Two
interfaces declaring one `id` SHALL match when and only when the rest of that identity is equal.

Two interfaces declaring one `id` whose identities differ SHALL produce an error row naming the `id`,
both interfaces and what differs between them, and an edge between them SHALL be refused. The plan
SHALL still be produced for every other entry, and the table SHALL report the plan as not applicable.

#### Scenario: One claim and one shape match

- **WHEN** a slot and a capability declare interfaces carrying one `id`, one export keyset, one type
  name and one secrecy per export, and one fold name
- **THEN** the planner SHALL treat them as one interface
- **AND** the read SHALL resolve as it does for two ends holding one value

#### Scenario: One claim and two export keysets

- **WHEN** two interfaces declare one `id` and one declares an export the other does not
- **THEN** the planner SHALL emit an error row naming the `id` and the differing export
- **AND** an edge between them SHALL be refused
- **AND** the table SHALL report the plan as not applicable

#### Scenario: One claim and two types for one export

- **WHEN** two interfaces declare one `id` and one export whose korora type names differ
- **THEN** the planner SHALL emit an error row naming the `id`, the export and both type names

#### Scenario: One claim and two secrecies for one export

- **WHEN** two interfaces declare one `id` and one export whose secrecies differ
- **THEN** the planner SHALL emit an error row naming the `id`, the export and both secrecies
- **AND** the row SHALL be emitted whether or not either secrecy was written explicitly

#### Scenario: One claim and two folds

- **WHEN** two interfaces declare one `id` and folds carrying different names
- **THEN** the planner SHALL emit an error row naming the `id` and both fold names

### Requirement: A claim decides only whether an edge exists

When two interfaces match by claim, each side SHALL continue to use the value its own author
imported: a provider's exports SHALL be verified against the provider's own interface, and a slot's
declared reads SHALL be checked against the consumer's own interface. Matching by claim SHALL NOT
change which exports a slot reads, which machines a generated value is delivered to, or any value the
plan records.

The planner SHALL NOT verify that two matched interfaces agree on anything an identity does not carry.
Two korora types sharing one name SHALL be treated as one type for the purpose of identity, however
their verification differs.

#### Scenario: Each side verifies against its own value

- **WHEN** a slot and a capability match by claim across two evaluations, and the provider publishes a
  value its own interface's type refuses
- **THEN** the planner SHALL emit the export type row against the provider
- **AND** the row SHALL quote the verification the provider's own interface performed

#### Scenario: A claim does not widen a read

- **WHEN** a slot matching by claim declares that it reads one of two exports
- **THEN** the consuming implementation SHALL receive only the export the slot named
- **AND** the delivery set of any generated value behind the unread export SHALL be unchanged

#### Scenario: Two type names agree and two predicates do not

- **WHEN** two interfaces declare one `id` and one export whose korora types carry one name and verify
  different sets of values
- **THEN** the planner SHALL treat the two interfaces as one
- **AND** each side SHALL verify the values it publishes or reads against its own imported type

### Requirement: A conflicting claim is reported once and deterministically

The planner SHALL report a conflicting claim between two interfaces it can see, whether or not a wire
names them: two interfaces attributed through the deployment's declaring-file map that claim one `id`
with differing identities SHALL produce the row without any edge between them. The same conflict
SHALL produce one row however many times it is observed, and two evaluations of one deployment SHALL
render that row identically.

#### Scenario: Two attributed interfaces conflict with no wire

- **WHEN** the deployment attributes two interfaces that claim one `id` and differ in shape, and no
  slot is wired to either
- **THEN** the planner SHALL emit the conflict row
- **AND** the row's subject SHALL be one of the two declaring files, chosen the same way on every
  evaluation

#### Scenario: One conflict observed twice is one row

- **WHEN** a conflicting claim is observable both from the deployment's attribution and from a wire
- **THEN** the diagnostics table SHALL carry exactly one row for that conflict

### Requirement: A claimed identity requires a nameable fold

An interface that declares an `id` and a fold SHALL declare that fold with a name, because a fold's
name is part of the identity and a bare function cannot supply one. An interface that declares an `id`
and a fold carrying no name SHALL produce an error row against its declaring file, and its claim SHALL
be disregarded: that interface SHALL then be identified by its value.

An interface that declares no `id` SHALL be free to declare a fold with or without a name.

#### Scenario: A claim carries an unnamed fold

- **WHEN** an interface declares an `id` and a fold that carries no name
- **THEN** the planner SHALL emit an error row naming the interface and stating that a claim needs a
  named fold
- **AND** that interface SHALL be identified by its value

#### Scenario: A named fold is part of the claim

- **WHEN** two interfaces declare one `id`, one shape and folds carrying one name
- **THEN** the planner SHALL treat them as one interface
- **AND** the fold the consuming read applies SHALL be the one the consumer's own interface declared

#### Scenario: An unclaimed interface keeps an unnamed fold

- **WHEN** an interface declares a fold carrying no name and no `id`
- **THEN** no row SHALL be emitted for the unnamed fold

### Requirement: Attribution follows identity

The declaring file a row prints beside an interface's name SHALL be found by value first and by
claimed identity second, so that a row about an interface built by another evaluation names that
interface's own file when its author's declaring-file map was given to the planner. An interface that
neither match finds SHALL keep today's rendering, which states that no declaring file was recorded.

#### Scenario: A row names a third party's declaring file

- **WHEN** a row concerns an interface built by another evaluation, and the deployment's
  declaring-file map attributes an interface claiming the same identity
- **THEN** the row SHALL print that declaring file beside the interface's name

#### Scenario: An unattributed interface renders as it does today

- **WHEN** a row concerns an interface that the declaring-file map neither holds by value nor by claim
- **THEN** the row SHALL state that the declaring file was not recorded

### Requirement: An unqualified claim is a warning

An `id` carrying no namespace separator SHALL produce a warning row naming the interface, because a
claim is made in a namespace shared with every other author and an unqualified one collides silently.
The row SHALL be a warning: an unqualified `id` identifies an interface exactly as a qualified one
does, and the plan SHALL remain applicable.

#### Scenario: An unqualified claim

- **WHEN** an interface declares an `id` carrying no namespace separator
- **THEN** the planner SHALL emit a warning row naming the interface and the `id`
- **AND** the plan SHALL remain applicable
- **AND** the `id` SHALL identify the interface exactly as a qualified one would

#### Scenario: A qualified claim is not reported

- **WHEN** an interface declares an `id` carrying a namespace separator
- **THEN** no unqualified-claim row SHALL be emitted for it
