# realiser/flakelet-artifact Specification

## Purpose
Defines the service artifact built from one placed plan entry for a host that runs a service out
of its own store rather than out of an image: what the artifact contains, who decides that a unit
is enabled, what identity it carries so an endpoint can tell whether anything changed, what it
refuses, and what a real service manager does with it. This is the first realiser in this
repository whose output is activated by something other than a test double.

## Requirements

### Requirement: An artifact is built from one plan entry, outside the planner

An artifact SHALL be built by a component outside `mkPlan`, and plan evaluation SHALL remain free
of derivations. The builder SHALL take one placed entry and the plan it belongs to, and SHALL
derive every fact it needs from them: the units to render, the timers a scheduled unit implies,
and the identity to stamp. The artifact SHALL contain the rendered unit files and a metadata
document and nothing else, so that activating it requires no evaluation, no network and no
knowledge of Nix on the machine.

#### Scenario: One entry becomes one artifact

- **WHEN** a placed entry with one long-running unit is built
- **THEN** the artifact SHALL contain that unit's file under a directory of units
- **AND** SHALL contain a metadata document
- **AND** SHALL contain no other file

#### Scenario: A scheduled unit brings its trigger

- **WHEN** a placed entry declares a unit with a schedule
- **THEN** the artifact SHALL contain both that unit's file and its timer file

#### Scenario: Nothing is evaluated to activate it

- **WHEN** an artifact is activated on a machine
- **THEN** the machine SHALL require no evaluator, no service-flake source and no network to do it

### Requirement: Enablement is the backend's decision, not the plan's

The plan SHALL say when a unit runs and the artifact SHALL say what that means for the endpoint
that starts it. A long-running unit SHALL be rendered so that the endpoint starts it on
activation and again after a reboot. A scheduled unit SHALL be rendered so that only its timer is
enabled: deploying a scheduled service SHALL NOT run it immediately.

#### Scenario: A long-running unit is started

- **WHEN** an artifact whose entry declares a long-running unit is activated
- **THEN** that unit SHALL be running

#### Scenario: A long-running unit returns after a reboot

- **WHEN** the machine reboots after an activation
- **THEN** that unit SHALL be running again without any activation being re-run by hand

#### Scenario: A scheduled unit is not fired by deploying it

- **WHEN** an artifact whose entry declares a scheduled unit is activated
- **THEN** its timer SHALL be enabled
- **AND** its service SHALL NOT have been started by the activation

### Requirement: The artifact carries the plan's identity

The artifact SHALL record the key of the entry it was built from and that entry's content-derived
version, in the fields the endpoint already reads. An endpoint comparing a newly delivered
artifact against what it is running SHALL therefore compare plan facts, and an artifact built
twice from one unchanged entry SHALL compare equal.

#### Scenario: An unchanged entry is a no-op

- **WHEN** an artifact is activated and then an artifact built from the same unchanged entry is offered
- **THEN** the endpoint SHALL report that there is nothing to do
- **AND** SHALL NOT restart the running units

#### Scenario: A changed unit field is a new generation

- **WHEN** a unit field changes and an artifact built from the changed entry is offered
- **THEN** the endpoint SHALL activate it as a new generation

#### Scenario: The running artifact names its entry

- **WHEN** an operator asks the endpoint what it is running
- **THEN** the answer SHALL contain the plan key of the entry the running artifact was built from

### Requirement: A name the endpoint cannot accept is refused before bytes exist

The names an artifact derives - the service name and every unit file name - SHALL satisfy the
endpoint's own naming rules, and the builder SHALL refuse an entry whose derived names do not,
naming the entry, the offending name and the rule it breaks. A refusal SHALL be a raise, as every
refusal on this side is, and it SHALL happen before any file is produced.

This realiser SHALL be the author of both rules, and SHALL publish each as a predicate a caller can
ask before building, so that the deployment build reports the same condition as a row without
restating the rule. A raise here SHALL therefore be reachable only by a caller that did not ask, and
the sentence a raise prints SHALL be the sentence the row states.

Both rules are restatements of rules the endpoint owns, and a restated rule SHALL refuse everything
the rule it restates refuses. A name this realiser admits and the endpoint rejects is a defect of
the restatement and not of the declaration: the refusal then arrives from the endpoint, on a
machine, naming neither the entry nor the deployment, and the artifact has already been built and
delivered.

A restatement SHALL be anchored over the whole name, so that no character the endpoint treats as a
terminator passes as an ordinary one. A rule stated as a pattern SHALL match the name end to end and
its wildcards SHALL admit no line break, because a name carrying one satisfies a rule about a single
line while naming a file whose second line is a directive the plan does not record. Where the two
rules cannot be shown to agree, the restatement SHALL be the narrower of the two.

#### Scenario: An unusable instance name

- **WHEN** an entry's instance or service name contains a character the endpoint's service names may
  not carry
- **THEN** the build SHALL fail naming the entry, the derived name and the rule
- **AND** a caller that reads the deployment build instead SHALL have received a row naming the same
  three

#### Scenario: A unit name outside the service's namespace

- **WHEN** an entry would render a unit file whose name does not begin with the derived service name
- **THEN** the build SHALL fail naming the entry and that unit

#### Scenario: A unit name carrying a line break is refused by the restated rule

- **WHEN** an entry derives a unit file name whose text carries a line break, so that its first line
  alone satisfies the restated rule
- **THEN** the published predicate SHALL answer that the name is unusable and the build SHALL fail
  naming the entry and that name
- **AND** no artifact of that entry SHALL carry a unit file whose name spans two lines
- **AND** the deployment build SHALL have reported the same condition as an error row

#### Scenario: A well-formed entry is not refused

- **WHEN** an entry's instance, service and unit names are all made of characters the endpoint
  accepts
- **THEN** the build SHALL succeed

### Requirement: A host path this realiser can show is decided by its bytes and its record

This realiser SHALL refuse an entry shown a host path whose bytes do not exist before the entry is
activated, and SHALL refuse an entry shown a configuration file whose record it cannot install:
this realiser runs no step on the machine, so the file the unit opens is a store object, and a store
object carries one ownership and one mode. A record that is the store object's own SHALL be
accepted; any other SHALL be refused, naming the entry, the path, the record the declaration stated
and the record a store object carries.

The refusal SHALL state the rule rather than the file's kind, and its resolution SHALL name both
ways out: state the record a store object carries, or state the realiser that installs files on the
machine for that entry.

A generated value's file SHALL be unaffected. Its record is installed by whoever delivers the bytes
rather than by a realiser, and its bytes arrive before activation, which is why it is accepted
whatever its ownership.

This narrows `A host path this realiser cannot carry is refused`, which decided the question by when
the bytes exist alone. When the bytes exist still decides whether the path can be shown at all; the
record now decides whether this realiser can show it as the declaration asked.

#### Scenario: An entry shown a configuration file stating an ownership

- **WHEN** an entry stated to be realised by this realiser declares a configuration file of
  literals stating an owner other than the superuser
- **THEN** the build SHALL refuse naming the entry, the path, the stated record and the store's
- **AND** the planner SHALL have reported the same condition as an error row
- **AND** the resolution SHALL name stating the store's record and stating the other realiser

#### Scenario: An entry shown a file at a mode no store object has

- **WHEN** the same entry declares that file at the store's ownership and a mode no store object has
- **THEN** the build SHALL refuse naming the entry, the path and both records

#### Scenario: An entry shown a file whose record the store carries

- **WHEN** the same entry declares that file at the ownership and the mode a store object carries
- **THEN** the reading SHALL accept the entry
- **AND** the unit SHALL bind the artifact's own path at the declared host path

#### Scenario: A delivered file's record is not this realiser's to install

- **WHEN** an entry is shown the host path of a generated file whose record names an account other
  than the superuser
- **THEN** the reading SHALL accept the entry
- **AND** the acceptance SHALL rest on the bytes and the record both arriving from the delivery
  rather than from the artifact

#### Scenario: An entry shown a configuration file

- **WHEN** an entry is shown a configuration file whose `render` list carries a `ref`
- **THEN** the build SHALL refuse naming the entry, the path and the reference
- **AND** the planner SHALL have reported the same condition as a row

#### Scenario: An entry shown a generated file

- **WHEN** an entry's unit reads a generated file by reference
- **THEN** the artifact SHALL be built
- **AND** it SHALL carry no bytes of that file and no step that would create it

#### Scenario: An entry shown no host file is built

- **WHEN** an entry records no configuration data and reads no generated file
- **THEN** the artifact SHALL be built

### Requirement: An artifact is a function of its entry alone

Two builds of one entry SHALL produce byte-identical artifacts. A change to an entry SHALL change
that entry's artifact, and SHALL leave every other entry's artifact unchanged.

#### Scenario: A rebuild is identical

- **WHEN** one entry is built twice
- **THEN** the two artifacts SHALL be byte-identical

#### Scenario: An unrelated edit changes nothing

- **WHEN** a setting is changed on one service and a second service reads nothing from it
- **THEN** the second service's artifact SHALL be byte-identical to the one built before the edit

### Requirement: A real endpoint runs the artifact and can go back

The change SHALL be proved against a real service manager and a real endpoint rather than test
doubles: an artifact is activated, the service it describes is reachable, it survives a reboot,
and an endpoint holding two generations of one entry SHALL be able to return to the previous one.

#### Scenario: The service is reachable

- **WHEN** an artifact whose unit serves requests is activated on a real machine
- **THEN** a request to that service SHALL succeed

#### Scenario: Rollback returns the previous generation

- **WHEN** a second artifact of one entry has been activated and the endpoint is asked to roll back
- **THEN** the units of the previous generation SHALL be running
- **AND** the endpoint SHALL report the previous generation as active

#### Scenario: No test double is involved

- **WHEN** the end-to-end check runs
- **THEN** it SHALL use the endpoint's real binary and the machine's real service manager

### Requirement: An unchanged artifact's activation is a no-op, and what that implies is stated

Activating an artifact the machine already holds SHALL leave the entry's processes untouched, and
this realiser SHALL NOT attempt to detect a change in anything outside the artifact. An artifact is
a function of the plan entry; bytes delivered beside it are not part of it, and making an activation
depend on them would make one entry's identity depend on a file no artifact carries.

It SHALL therefore be stated, as a property of this realiser rather than as an omission, that a
change in a delivered value produces no change in the artifact and no change in what an activation
does. The layer that wrote the value is the layer that knows it moved, and it is where the reader's
restart belongs.

#### Scenario: An artifact activated twice

- **WHEN** an unchanged artifact is activated twice
- **THEN** the entry's units SHALL keep the same main processes
- **AND** the endpoint SHALL record no new generation

#### Scenario: A delivered value moves under an unchanged artifact

- **WHEN** a value an entry reads is rewritten with different bytes and the unchanged artifact is
  activated
- **THEN** the activation SHALL change nothing
- **AND** the entry's processes SHALL still hold the previous bytes until something restarts them

### Requirement: A unit's reload is available to the layer that needs it

Where a plan entry records the units a configuration file's `reload` list names, this realiser SHALL
render the units so that reloading one is possible without re-activating the entry: a unit that
declared a reload command SHALL carry the corresponding directive, and a unit that did not SHALL be
restartable.

Nothing in this realiser SHALL issue a reload. It renders units and the endpoint links and starts
them; which unit to reload, and when, is the caller's decision, and stating it here would put a
second activation model beside the endpoint's.

#### Scenario: A unit declaring a reload command

- **WHEN** an entry's unit records a reload command
- **THEN** the rendered unit file SHALL carry the corresponding directive
- **AND** reloading that unit on the machine SHALL not require the artifact to be re-activated

#### Scenario: The realiser issues nothing

- **WHEN** an artifact is activated
- **THEN** the activation SHALL consist of what the endpoint does with the artifact
- **AND** no reload or restart of any unit SHALL be issued by this realiser

### Requirement: A host path whose bytes exist before activation is accepted

This realiser SHALL accept a host path whose bytes exist before the entry is activated, and SHALL
refuse one whose bytes would have to be assembled on the machine. It still runs no step on the
machine, so the rule is unchanged; what it is applied to is the file's disposition rather than the
file's kind.

A configuration file recorded as a `source` store path SHALL be accepted. A configuration file
recorded as a `render` list of nothing but `text` items SHALL be accepted, and the bytes SHALL be
assembled into the artifact at build time so that the path shown to the unit is a path the machine
holds once the artifact's closure has been copied. A generated file SHALL continue to be accepted,
because its bytes arrive by delivery before activation.

A configuration file whose `render` list carries a `ref` SHALL be refused, naming the entry, the host
path, and the reference whose bytes exist only on the machine. The refusal SHALL state that rule
rather than stating that the file is a configuration file, so that an author can tell which of their
files this realiser can carry.

#### Scenario: A configuration file copied from a store path

- **WHEN** an entry records a configuration file as a `source` store path
- **THEN** the reading SHALL accept the entry
- **AND** the rendered unit SHALL bind that store path at the declared host path
- **AND** the store path SHALL be reachable from the artifact, so copying the artifact copies the
  bytes

#### Scenario: A configuration file assembled from literals

- **WHEN** an entry records a configuration file whose `render` list holds `text` items only
- **THEN** the artifact SHALL carry the assembled file
- **AND** the reading SHALL accept the entry
- **AND** the rendered unit SHALL bind the artifact's own path at the declared host path

#### Scenario: A configuration file referencing a delivered path

- **WHEN** an entry records a configuration file whose `render` list carries a `ref`
- **THEN** the reading SHALL refuse naming the entry, the host path and the reference
- **AND** the refusal SHALL state that the bytes do not exist until the referenced path is written
- **AND** the planner SHALL have reported the same condition as a row

#### Scenario: A delivered generated file is still accepted

- **WHEN** an entry is shown the host path of a generated file its plan records as deployed
- **THEN** the reading SHALL accept the entry
- **AND** the acceptance SHALL rest on the bytes arriving before activation rather than on the file's
  kind

### Requirement: The artifact carries what it assembled and nothing else new

Where this realiser assembles a configuration file at build time, the artifact SHALL carry that file
beside the metadata and the unit files it already carries, and SHALL carry no other new content. An
artifact for an entry that records no such file SHALL be byte-identical to what this realiser
produced before the rule changed.

#### Scenario: An entry with no configuration file is unchanged

- **WHEN** an entry records no configuration file
- **THEN** the artifact SHALL hold exactly the metadata and the unit files
- **AND** its content SHALL be identical to what this realiser produced before this change

### Requirement: Every unit directive this realiser emits comes from the one renderer

A unit file this realiser writes SHALL be the unit file the image realiser's renderer produces plus
the install section this realiser decides, so that a unit field added to the vocabulary and mapped
once is emitted by both realisers or by neither. This realiser SHALL hold no second mapping of a
unit field to a directive.

An artifact of an entry whose units declare none of the fields a change added SHALL be identical to
the artifact produced before those fields existed.

#### Scenario: A flakelet unit carries the directory and condition directives

- **WHEN** an entry's unit records a directory, a mode for its kind and a condition on a path
- **THEN** the unit file in the artifact SHALL carry all three directives
- **AND** it SHALL carry the install section this realiser decides for a unit of that shape

#### Scenario: A unit declaring none of the new fields is byte-identical

- **WHEN** an entry's units record no directory, no directory mode and no condition
- **THEN** the artifact SHALL be identical to the one this realiser produced before those fields
  existed
