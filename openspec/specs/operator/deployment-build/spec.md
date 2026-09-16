# operator/deployment-build Specification

## Purpose
Defines what building a whole deployment produces, so that no deployment needs code written for it.
One reading decides which entries are built, which realiser builds each, and what the result is
addressed by; one manifest states the answer for a consumer that evaluates no Nix; and a deployment
the planner called inapplicable is refused rather than partially realised.

## Requirements

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

A consumer of a deployment build SHALL be able to apply it by reading the plan and `manifest.json`,
with no Nix evaluation. `manifest.json` SHALL state, for each placed entry, the artifact built for
it, the realiser that built it, the machine it is placed on, that machine's address as the registry
declared it or as an absence, the units it declares, and the artifact identity the endpoint records;
and for each generated value, its files, their paths and the machines its delivery set names.

`manifest.json` SHALL also state the version of its own shape and the store directory its artifact
paths live in, so that a reader can tell a record it implements from one it does not, and a record
built against another store from one it can copy from. The version SHALL change when a reader that
implements the previous one would misread the new one.

`manifest.json` SHALL be a function of the plan and the realisation statement alone, so that reading
one deployment twice yields one answer.

#### Scenario: The manifest names every entry the plan placed

- **WHEN** the `manifest.json` of a built deployment is read
- **THEN** every placed entry of the plan SHALL appear in it exactly once
- **AND** each SHALL carry its artifact, its realiser, its machine, that machine's address as the
  registry declared it or as an absence, its unit names, and the artifact identity the endpoint
  records
- **AND** an entry whose machine declares no address SHALL be recorded with that absence and
  reported by a warning row, neither left out nor refused

#### Scenario: The manifest names every value a machine receives

- **WHEN** the deployment declares generated values
- **THEN** `manifest.json` SHALL name every value entry the plan carries, with its files and their
  paths
- **AND** each SHALL carry the delivery set the plan derived, including when that set is empty
- **AND** `manifest.json` SHALL carry no bytes of any value

#### Scenario: The same deployment is read twice

- **WHEN** one deployment is read twice with no edit between
- **THEN** the two records SHALL be equal
- **AND** the two readings SHALL name the same artifact for each key

#### Scenario: A build states the shape of its record and the store it used

- **WHEN** a deployment is built
- **THEN** the record it publishes SHALL state the version of its own shape
- **AND** SHALL state the store directory the artifact paths in it live in
- **AND** both SHALL be readable without reading any entry of the record

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
record declaring no address SHALL NOT refuse a build and SHALL NOT produce a row of the deployment
build. The planner refuses such a placement before a plan exists, so the condition is reported once,
by the layer that holds the fact, against the file that declares it.

The reading SHALL nevertheless carry the absence rather than raise on it or omit the field, because
a plan and a deployment record may be handed to it by a caller the planner did not produce them
for, and SHALL build every artifact of the deployment. Refusing to apply an entry whose machine
record states no address belongs to the command, under "The command refuses before it dials" in
`operator/apply-command`, and SHALL stay there.

A build of a deployment the registry made inapplicable SHALL still publish the plan and both forms
of the diagnostics and SHALL publish no entry artifact, so that the operator reads the rendered
table naming the machine and the registry file rather than a build they cannot apply.

#### Scenario: A machine of a placed entry declares no address

- **WHEN** the reading is handed a plan whose machine record for a placed entry declares no address
- **THEN** the build SHALL produce every artifact the deployment places
- **AND** the diagnostics table SHALL carry no row about the address
- **AND** the deployment record SHALL carry that entry with its address stated as absent

#### Scenario: A build of a deployment the registry made inapplicable

- **WHEN** a deployment whose registry declares no address for a machine a placement selects is
  built
- **THEN** the build SHALL produce the plan, the machine-readable diagnostics and the rendered
  diagnostics
- **AND** SHALL produce no artifact for any entry of the deployment
- **AND** the rendered table SHALL name the machine and the file that declares it

### Requirement: The reading is total over a plan the planner pruned

The plan omits a field whose value carries nothing, and the reading SHALL treat every such omission
as the absence it is. No field the plan may omit SHALL be read in a way that ends the evaluation:
where the reading needs a fact the plan does not record, it SHALL produce a row naming the entry and
the field, and the rest of the plan SHALL still be read.

A plan the planner accepted SHALL therefore always produce a table, and a reader SHALL never be shown
an evaluation error in place of one.

#### Scenario: A value entry records no files

- **WHEN** a generator declares no files, so its value entry carries no file record at all
- **THEN** the reading SHALL produce a row naming that value entry
- **AND** the reading SHALL still produce records for every other entry
- **AND** the evaluation SHALL NOT end with an error in place of the table

#### Scenario: A field the plan omits is needed by the reading

- **WHEN** the reading needs a field that the plan omits because its value was empty
- **THEN** the reading SHALL report it as a row rather than raising
- **AND** the row SHALL name the entry and the field

### Requirement: The record a build publishes is one every command can read

An entry's record in the manifest SHALL be readable by every command that reads the manifest,
whatever the entry declares. Where an entry legitimately has no artifact - a placed entry that
declares no unit is one the planner accepts - the record SHALL say so in a shape the reading side
accepts, and SHALL NOT be a value the reading side refuses.

A record of one entry SHALL NOT make a command refuse the whole deployment: a command that needs an
artifact only for some entries SHALL refuse only when it needs the one that is absent.

#### Scenario: An entry declares no unit

- **WHEN** a deployment places an entry that publishes an export and runs nothing
- **THEN** the build SHALL publish a record for that entry
- **AND** every command that reads the manifest SHALL read it without refusing
- **AND** a command that does not need an artifact for that entry SHALL proceed

#### Scenario: A command needs the artifact an entry does not have

- **WHEN** a command needs an artifact for an entry whose record names none
- **THEN** the refusal SHALL name that entry
- **AND** SHALL NOT be a refusal of the entries whose records the command can read

### Requirement: An extension field the stated realiser cannot render is an error row

The reading that turns a plan and a realisation statement into a deployment SHALL report, as an
error row, every extension field an entry records that the realiser stated for it has no rendering
for. The row SHALL name the entry, the unit, the field and the backend, and its resolution SHALL
name both ways out: write a field the realiser renders, or state a realiser that renders this one.
The extension's own name SHALL NOT be required of the row: the plan folds an application's values
into one attrset per backend and records no extension name, so naming it would need a plan field
that moves every entry's key.

No entry SHALL reach a realiser's own refusal for this condition without the row having been
produced first. The rule the row is read against SHALL be the realiser's own table rather than a
list restated here, so that a directive added to a realiser is a field the row stops naming without
an edit in this layer.

A deployment carrying such a row SHALL be inapplicable and SHALL build its plan and both halves of
its table and no artifact, the way every other error row of this reading behaves.

#### Scenario: A field no builder renders

- **WHEN** an entry's unit records an extension field the realiser stated for it has no rendering for
- **THEN** the reading SHALL produce an error row naming the entry, the unit, the field and the
  backend
- **AND** the deployment SHALL be inapplicable
- **AND** the build SHALL produce the plan and both halves of the table and no artifact

#### Scenario: The same field under a realiser that renders it

- **WHEN** the realisation statement names a realiser whose table carries that field
- **THEN** the reading SHALL produce no row for it
- **AND** the entry's artifact SHALL be built

#### Scenario: A field added to a realiser's table stops being reported

- **WHEN** a realiser's directive table gains a field an entry records
- **THEN** the reading SHALL stop reporting that field without this layer restating the table
- **AND** no row SHALL name a field the realiser can render

### Requirement: Two entries of one machine do not share a derived unit file name

Every unit file name a realiser derives for the entries of one machine SHALL name one entry. Where
two entries placed on one machine derive one unit file name, the reading SHALL produce one error row
naming both entries and the name they collided on, and the deployment SHALL be inapplicable: two
entries publishing one unit file name means the second replaces the first on the machine, so one
entry runs the other's unit and neither declaration is honoured.

The comparison SHALL be made over the names the realisers actually spend. A name that carries a fact
the derived name drops SHALL NOT stand in for it: an artifact name carries the machine and so cannot
collide inside one machine, while a derived unit file name joins the instance, the member and the
unit name into one string, so two members whose names and unit names differ can spell one file name.

The check SHALL belong to the reading that derives those names and already refuses two entries whose
artifact names collide, not to the planner: the planner derives no unit file name and is handed no
statement of which realiser renders an entry. One check SHALL therefore cover every realiser,
because every realiser spends the same derived names, and a realiser SHALL NOT be the first to speak
about a collision the reading can see.

#### Scenario: Two entries of one machine do not share a unit file name

- **WHEN** two members of one instance are placed on one machine, and one member's name together
  with its unit name spells the other member's name together with its unit name
- **THEN** the reading SHALL produce one error row naming both entries and the unit file name
- **AND** the deployment SHALL be inapplicable, so no artifact of it is realised
- **AND** the row SHALL be produced whichever of the two entries the reading reads first

#### Scenario: A unit file name collision is reported under either realiser

- **WHEN** one such pair of entries is stated for the realiser that emits an image, and then for the
  realiser that emits a service artifact
- **THEN** both readings SHALL produce the row, naming the same two entries and the same name
- **AND** a deployment whose derived unit file names are all distinct SHALL be refused by neither
- **AND** neither realiser's own refusal SHALL be what an operator meets first

### Requirement: Every field the reading indexes is read for its kind

Every value the reading indexes or coerces SHALL be read for its kind before it is indexed or
coerced, whether the value comes from the realisation statement beside the deployment or from a
record of the plan. A value of another kind SHALL be one error row naming the statement or the record
it was found in and the field inside it, and SHALL contribute nothing to the build.

A reading that answers a diagnostics table SHALL NOT end the evaluation instead. An evaluation error
in place of a table names neither the statement nor the field, and it takes the one thing that
explains the mistake with it, so a caller holding a statement of the wrong kind SHALL still be handed
a table naming what to edit.

A stated fact of another kind SHALL be reported the way a stated fact outside the values a realiser
implements is reported, naming the entry and what the statement held, and SHALL NOT be taken as a
fact the builder chose on the deployment's behalf. A field of a plan record the reading needs SHALL
be read for its kind as well, including where the planner already refused that record and recorded it
incompletely: such a deployment is inapplicable, so the table is the only thing left to produce.

#### Scenario: A realisation statement names a realiser of another kind

- **WHEN** a realisation statement states a realiser as a number rather than as a name
- **THEN** the reading SHALL produce one error row naming the statement and the field
- **AND** no entry SHALL be realised under a realiser chosen on the statement's behalf
- **AND** the reading SHALL still answer a table

#### Scenario: A statement carries a profile of another kind

- **WHEN** a statement for an entry realised as an image carries a confinement profile that is a
  value of another kind
- **THEN** the reading SHALL produce one error row naming the entry and the field
- **AND** the row SHALL be the one a profile outside the values the realiser implements earns
- **AND** the value SHALL index nothing the realiser holds about a profile

#### Scenario: A configuration file record carries no mode

- **WHEN** a plan carries a configuration file record that states no mode, which is what the planner
  records for a file it already refused
- **THEN** the reading SHALL produce one error row naming the entry and the field
- **AND** the reading SHALL still answer the table the deployment's other rows are in
- **AND** the absence SHALL NOT be coerced into a rendered decision about that file
