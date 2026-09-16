<!--
A delta against `operator/deployment-build`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change. This delta restates four of its requirements and
adds six. It reads against `planner/diagnostics` in this same change, which states the rule that a
refusal about the realisation statement is this layer's row, and against
`realiser/flakelet-artifact` and `realiser/portable-service-image`, also in this change, whose
refusals are narrowed to conditions the rows required here already reported.

The subjects are `operator/read.nix` throughout: the two text classifications at `:49` and `:51`, the
statement resolution at `:70-82` and `:102-106`, the profile row at `:135-142`, the address row at
`:143-149`, the record at `:236-245`, and the refusal `operator/default.nix:88-92` acts on.

One requirement title and two scenario headings are quoted from the original rather than reworded,
because a restatement has to carry the title it restates and because those two headings name tests
that exist. Each therefore keeps the word the local terminology rule swaps, and the prose this
delta writes for itself says "deployment record" instead.
-->

## Purpose

Defines what building a whole deployment produces and every way a build is refused, so that a
realisation statement is answered in full by the layer that holds it and a realiser is never the
first to speak. One reading decides which entries are realised, which realiser realises each, and
what the result is addressed by; one record states the answer for a consumer that evaluates no Nix.

## ADDED Requirements

### Requirement: Every record of a plan is classified by the shape of its record

The reading SHALL decide what a record of the plan is from what the record holds, never from the
text of its key. A record carrying a delivery set SHALL be a generated value, a record carrying a
placement SHALL be a service entry, and a record carrying neither SHALL be a machine record. The
reading SHALL read a key only for the instance, the service and the machine of a placed service
entry, which the plan's key grammar defines, and SHALL split such a key at its last separator.

A record matching none of the three shapes SHALL be an error row naming the key and the shapes the
reading knows, because a build that passes over a record it does not understand cannot know whether
it passed over an artifact somebody needs. No record of the plan SHALL be dropped without a row.

A placed service entry declaring no unit SHALL be realised into nothing: it SHALL appear in the
deployment record, contribute no artifact, and produce no row of its own.

#### Scenario: An instance is named machine

- **WHEN** a deployment declares an instance called `machine` and places a service of it
- **THEN** the reading SHALL classify that entry as a service entry
- **AND** an artifact SHALL be built for it
- **AND** the machine it names SHALL be the one after the last separator of its key

#### Scenario: A member is named inside the value namespace

- **WHEN** a root declares a member whose name begins with the generated-value namespace
- **THEN** the reading SHALL classify its placed entry as a service entry rather than as a generated
  value
- **AND** reading the deployment SHALL produce a result rather than fail on a field the entry does
  not carry

#### Scenario: A key matches no shape the plan carries

- **WHEN** the plan carries a record matching none of the three shapes the reading knows
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the key and the shapes the reading knows

#### Scenario: A placed entry declares no unit

- **WHEN** a service is placed on a machine, publishes an export and declares no unit
- **THEN** the deployment record SHALL name that entry with its machine
- **AND** no artifact SHALL be built for it
- **AND** the build SHALL NOT be refused

### Requirement: A statement that names nothing is a refusal

Every key of the realisation statement other than the default SHALL name a plan key the plan carries
or a prefix of one. A key naming neither SHALL be an error row giving the key stated and the keys the
plan carries, because a statement about nothing is a decision the user made and the build ignored. A
statement that is not a record SHALL be an error row naming the key and what was found there.

#### Scenario: A statement names an entry the plan does not carry

- **WHEN** the realisation statement names a key that is neither a plan key of the deployment nor a
  prefix of one
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the key stated and the keys the plan carries
- **AND** no entry SHALL have been realised under the default statement instead

#### Scenario: A statement is not a record

- **WHEN** a realisation statement for an entry is a bare string rather than a record
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the entry and what the statement held

### Requirement: A statement is checked against the entry it is about

A statement and an entry are two halves of one decision, and the reading holds both, so every
refusal that needs both SHALL be a row from the reading rather than a raise from the realiser that
would meet it later. The reading SHALL obtain what a realiser accepts from the realiser itself,
rather than restating the rule, so that the row and the realiser's own refusal cannot drift apart.

An entry stated to use a realiser that runs no step on the machine, shown a host path it would have
to assemble, SHALL be an error row naming the entry, the path and the realiser. An entry stated to
use a realiser that emits for a service manager the entry's machine does not run SHALL be an error
row naming both. An entry whose derived service name or rendered unit file name the stated realiser
refuses SHALL be an error row naming the entry, the name and the rule.

#### Scenario: A configuration file meets a realiser with no assemble step

- **WHEN** an entry records configuration data its unit reads and is stated to use a realiser that
  runs no step on the machine
- **THEN** the build SHALL be refused before any artifact is realised
- **AND** the refusal SHALL name the entry, the host path and the realiser

#### Scenario: An entry with configuration data is realised as an image

- **WHEN** the same entry is stated to use a realiser that assembles a configuration file
- **THEN** the build SHALL NOT be refused
- **AND** the artifact SHALL be built

#### Scenario: An entry is stated for a realiser its machine cannot run

- **WHEN** an entry planned for a machine running one service manager is stated to use a realiser
  that emits for another
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the entry, the service manager the plan recorded and the one the
  realiser emits for

#### Scenario: A name the endpoint refuses is a row before it is a raise

- **WHEN** an entry's derived service name or one of its rendered unit file names is one the stated
  realiser's endpoint refuses
- **THEN** the build SHALL be refused with a row naming the entry, the name and the rule
- **AND** the rule the row states SHALL be the rule the realiser's own refusal states

### Requirement: A confinement profile is checked against the entry it confines

A confinement profile is stated and the accesses an entry needs are recorded in the plan, so the
reading SHALL cross them and SHALL report a denial as an error row naming the entry, the unit, the
access and the profile. The row SHALL say that the profile is not widened on the entry's behalf, so
that the resolution is to change the statement or the unit rather than to expect the builder to
choose.

#### Scenario: A unit needing a host user meets a confining profile

- **WHEN** an entry declaring a unit that runs as a host user is stated to be realised under a
  profile that denies a static host user
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the entry, the unit, the access and the profile stated

#### Scenario: An entry owning a root-only file meets a confining profile

- **WHEN** an entry that reads a secret generated file by reference is stated to be realised under a
  profile that denies a host file only root may read
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the entry, the access and the profile stated

### Requirement: The identity a build publishes for an entry is the identity the machine stores

The identity a build publishes for a placed entry SHALL be the identity the machine's own endpoint
records for the artifact of that entry, so that a report can compare what a machine holds against
what a build holds. It SHALL be a function of the artifact's own content, so that two builds
producing equal bytes publish one identity and a build producing different bytes publishes another.

The plan entry key SHALL remain in the plan, which travels beside the deployment record, and SHALL
NOT be the identity a machine is asked for. A fact that moves a plan key without moving a byte of
any artifact SHALL therefore leave every published identity unchanged.

#### Scenario: A machine address changes and no artifact byte does

- **WHEN** a machine's declared address changes and no entry's units, closure or host paths change
- **THEN** every plan entry key on that machine SHALL move
- **AND** the identity the build publishes for each of those entries SHALL be unchanged

#### Scenario: The endpoint reports the identity the build published

- **WHEN** an applied entry is asked for on its machine
- **THEN** the identity the endpoint reports SHALL be the identity the build published for that entry
- **AND** applying the same build again SHALL report the same identity

### Requirement: An address is needed to apply and not to build

An address is read by the step that dials a machine and by no step that builds one, so a machine
record declaring no address SHALL NOT refuse a build. The reading SHALL report it as a warning
naming the entry and the machine, SHALL record the absence in the deployment record rather than
omitting the field, and SHALL build every artifact of the deployment. Refusing to apply such an
entry belongs to the command, under "The command refuses before it dials" in
`operator/apply-command`.

#### Scenario: A machine of a placed entry declares no address

- **WHEN** an entry is placed on a machine whose registry record declares no address
- **THEN** the build SHALL produce every artifact the deployment places
- **AND** the diagnostics table SHALL carry a warning naming the entry and the machine
- **AND** the deployment record SHALL carry that entry with its address stated as absent

## MODIFIED Requirements

### Requirement: One reading builds every deployment

Building a deployment SHALL be a function of the deployment alone: the arguments the planner takes,
plus a statement of how each entry is realised. It SHALL NOT require code written for a particular
deployment, and two deployments SHALL be built by the same function.

The result SHALL hold the plan, a deployment record, the diagnostics in both a machine-readable and
a rendered form, and one artifact per entry the reading realises. It SHALL hold nothing that is not
derived from those. An entry the plan did not place SHALL contribute no artifact, and neither SHALL
an entry the reading realises into nothing.

#### Scenario: Two deployments are built by one function

- **WHEN** two unrelated deployments are built
- **THEN** the same function SHALL build both
- **AND** each result SHALL hold the plan, the deployment record and one artifact per realised entry
  of that deployment
- **AND** neither SHALL require a declaration written beside it

#### Scenario: An artifact is addressed by its plan key

- **WHEN** a consumer holds a plan key and wants the artifact built for it
- **THEN** the deployment record SHALL name the artifact for that key
- **AND** the consumer SHALL NOT have to reconstruct the name from the key

#### Scenario: Two entries project onto one artifact name

- **WHEN** two plan keys project onto one artifact name
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name both keys and the name they collided on

### Requirement: The realiser of an entry is stated, never inferred

The realiser an entry is built with SHALL be a stated fact of the deployment, because no plan field
records it and the same entry may legitimately be realised either way. A realisation statement SHALL
be addressable per entry and SHALL carry a default for the entries it does not name.

Where a realiser requires a fact the plan does not carry, that fact SHALL be part of the statement,
and its absence SHALL be a refusal naming the entry and the fact - never a default chosen by the
builder. A stated fact SHALL be checked against the values the realiser implements, and a value
outside them SHALL be a refusal naming the entry, the value stated and the values that exist.

The statement SHALL be resolved field by field, down the same steps for every field: the plan key,
then the instance and service prefix, then the default statement. A field an entry's own statement
omits SHALL therefore be taken from the default statement, whichever field it is, so that no reader
has to know which fields inherit and which do not.

#### Scenario: An entry states no realiser

- **WHEN** the deployment's realisation statement does not name an entry
- **THEN** that entry SHALL be built by the default realiser
- **AND** the deployment record SHALL record which realiser built it

#### Scenario: An image entry states its confinement profile

- **WHEN** an entry is stated to be realised as a portable-service image
- **THEN** the profile the attachment runs under SHALL come from the statement
- **AND** an image entry for which no step of the statement carries a profile SHALL be refused
  naming the entry and the profile

#### Scenario: A realiser name nothing implements

- **WHEN** an entry is stated to use a realiser that does not exist
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the entry, the name given, and the realisers that exist

#### Scenario: A profile is inherited from the default statement

- **WHEN** the default statement carries a realiser and a profile, and an entry's own statement
  carries the realiser alone
- **THEN** the entry SHALL be realised under the profile the default statement carries
- **AND** the build SHALL NOT be refused

#### Scenario: A stated profile is outside the domain

- **WHEN** a statement carries a profile that is not one the image realiser implements
- **THEN** the build SHALL be refused by the reading
- **AND** the refusal SHALL name the entry, the profile stated and the profiles that exist

### Requirement: An inapplicable deployment is not built

No entry of a deployment whose diagnostics carry an error SHALL be realised. The build SHALL still
produce the plan and both halves of the diagnostics, because a table nobody can read is of no use to
the deployment it describes, and the machine-readable half SHALL be reachable for exactly the
deployments it exists to describe. A caller asking for the artifact of an entry of such a deployment
SHALL be refused with the rendered table, so the reason is the planner's own words.

Applicability SHALL be read from the rows and never from the shape of the result: the result SHALL
carry no marker of its own about being refused, because a second statement of a fact the table
carries is a statement that can disagree with it. A table carrying no error SHALL build every entry
the reading realises, whatever else the table carries.

#### Scenario: A deployment whose diagnostics carry an error

- **WHEN** a build is asked for a deployment the planner reports as inapplicable
- **THEN** no artifact of any entry SHALL be produced
- **AND** a caller asking for one SHALL be refused with the rendered diagnostics table

#### Scenario: A deployment whose diagnostics carry only warnings

- **WHEN** a build is asked for a deployment whose table holds warnings and no error
- **THEN** every entry the reading realises SHALL be built
- **AND** the table SHALL still be part of the result

#### Scenario: Both halves of the table are reachable for a refused deployment

- **WHEN** a deployment the planner reports as inapplicable is built
- **THEN** the result SHALL hold the plan, the rows and the rendered table
- **AND** it SHALL hold no artifact of any entry
- **AND** nothing in the result SHALL state its applicability other than the rows themselves

### Requirement: The manifest is the whole interface to a build

A consumer of a deployment build SHALL be able to apply it by reading the plan and the deployment
record, with no Nix evaluation. The record SHALL state, for each placed entry the reading realises,
the artifact built for it, the realiser that built it, the machine it is placed on, the address
recorded for that machine or the absence of one, the units it declares, and the identity the
machine's endpoint records for its artifact; and for each generated value, its files, their paths and
the machines its delivery set names.

The record SHALL be a function of the plan and the realisation statement alone, so that reading one
deployment twice yields one answer.

#### Scenario: The manifest names every entry the plan placed

- **WHEN** the deployment record of a built deployment is read
- **THEN** every placed entry of the plan SHALL appear in it exactly once
- **AND** each SHALL carry its artifact where one was built, its realiser, its machine, that
  machine's address and its unit names
- **AND** an entry the plan placed on a machine the registry gives no address for SHALL carry that
  absence rather than be left out

#### Scenario: The manifest names every value a machine receives

- **WHEN** the deployment declares generated values
- **THEN** the record SHALL name every value entry the plan carries, with its files and their paths
- **AND** each SHALL carry the delivery set the plan derived, including when that set is empty
- **AND** the record SHALL carry no bytes of any value

#### Scenario: The same deployment is read twice

- **WHEN** one deployment is read twice with no edit between
- **THEN** the two records SHALL be equal
- **AND** the two readings SHALL name the same artifact for each key
