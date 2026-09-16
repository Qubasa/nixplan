# planner/unit-vocabulary Specification

## Purpose
Defines the typed vocabulary a module writes when it implements a service: the fields a unit may carry, the typed per-backend extensions that add fields beyond them, the target a module learns its service manager from, the environment each unit runs with, and the record a configuration file gets. A binding can render a service manager's unit file only from facts the plan carries, so this vocabulary is the contract between the planner and every binding that renders from it. Reading a module's implementation is allow-listed against it, so a fact a module wrote and the plan cannot hold is a diagnostic row rather than a silent omission.

## Requirements

### Requirement: A unit carries a typed vocabulary and nothing else

A plan entry SHALL record, for each unit it produces, every field of the unit vocabulary that unit declared and no other field. The vocabulary SHALL be `command`, `env`, `after`, `requires`, `user`, `oneShot`, `remainAfterExit`, `schedule`, `timeout`, `stopCommand` and `reloadCommand`. Each field SHALL carry a type, and a value failing its field's type SHALL be an error row naming the module, the unit, the field and the type it failed. A field a unit did not declare SHALL be absent from the record rather than recorded as a null or as a service manager's default, so a renderer can distinguish "not asked for" from "asked for and empty".

`after` and `requires` SHALL each name units. A unit reference SHALL be producible only by the module that declared the unit it names, so that no module can order itself against a unit a stranger may rename, and a reference to a unit the module does not own SHALL be an error row naming the module and the reference. `requires` SHALL be a requirement and `after` SHALL be an ordering only: a required unit SHALL be started, and a unit that is only ordered SHALL NOT be.

#### Scenario: A long-running unit

- **WHEN** a module declares a unit with a `command` and an `env`
- **THEN** the plan SHALL record that unit with exactly those two fields
- **AND** the record SHALL carry no `oneShot`, no `after` and no `requires` key at all

#### Scenario: A unit that applies and exits

- **WHEN** a module declares a unit with `oneShot`, `remainAfterExit` and a `timeout`
- **THEN** the plan SHALL record all three fields on that unit
- **AND** a renderer SHALL be able to tell it from a long-running unit without inspecting its `command`

#### Scenario: A mistyped field value

- **WHEN** a module declares a unit whose `oneShot` is a string or whose `timeout` is not a duration
- **THEN** the planner SHALL emit an error row naming the module, the unit, the field and the type it failed
- **AND** the plan SHALL NOT record the failing value

#### Scenario: A unit reference to a unit the module does not own

- **WHEN** a module's `after` or `requires` names a unit that module did not declare
- **THEN** the planner SHALL emit an error row naming the module and the reference
- **AND** the plan SHALL NOT record the ordering or the requirement

### Requirement: A backend extension is typed and refused when it does not apply

A unit extension SHALL be constructed as `planner.unitExtension { backend; name; fields; }`, where `backend` names the service manager whose fields it adds, `name` is used only in diagnostic output, and `fields` declares each added field with a type. An extension SHALL be identified by the value a module imported and never by a name resolved at composition time, so two extensions MAY declare the same `name` and SHALL remain distinct values.

An extension SHALL be applied on a unit as `extends = [ { extension = <the imported value>; values = { … }; } ]`. `values`' keyset SHALL be a subset of the extension's `fields` rather than equal to it, so a partial application SHALL produce no row; a key outside `fields` SHALL be an error row naming the module, the unit, the extension's `name` and the key; a value failing its field's type SHALL be an error row. An extension whose `backend` is not the `serviceManager` of the machine the placement selected SHALL be `unit-extension-backend-mismatch` naming the module, the unit, the extension and both backends. The plan SHALL record a unit's extension fields grouped by backend, so a renderer for another backend refuses knowingly rather than dropping fields.

#### Scenario: A systemd extension on a systemd target

- **WHEN** a unit placed on a machine whose `serviceManager` is `systemd` applies an extension whose `backend` is `systemd`
- **THEN** the plan SHALL record the applied fields under that backend on that unit
- **AND** the planner SHALL emit no row

#### Scenario: The same extension on a launchd target

- **WHEN** the same module is placed on a machine whose `serviceManager` is `launchd` and applies that extension unconditionally
- **THEN** the planner SHALL emit `unit-extension-backend-mismatch` naming the module, the unit, the extension and both backends
- **AND** the plan SHALL still record the applied fields under the extension's own `backend`
- **AND** the row SHALL be what refuses them; no field SHALL be dropped without a row

#### Scenario: An unknown key inside an extension application

- **WHEN** a `values` set carries a key the extension's `fields` does not declare
- **THEN** the planner SHALL emit an error row naming the module, the unit, the extension's `name` and the key
- **AND** the key SHALL NOT be recorded and SHALL NOT be discarded without a row

#### Scenario: A partial extension application

- **WHEN** a `values` set assigns two of an extension's many `fields`
- **THEN** the plan SHALL record exactly those two fields
- **AND** the planner SHALL emit no row
- **AND** the fields left unset SHALL be absent rather than recorded with a default

#### Scenario: Two extensions sharing a name

- **WHEN** two modules import two different extension values from different files that declare the same `name`
- **THEN** each unit's fields SHALL be recorded against the extension its module imported
- **AND** neither extension's `values` SHALL be checked against the other's `fields`

### Requirement: A module learns its target from its implementation arguments

A module's implementation SHALL receive `target = { system = <the reduced platform record of the machine the placement selected>; serviceManager = <that machine's service manager>; }`, so a module MAY declare its portable fields once and apply a backend extension only where `target.serviceManager` matches. A member no placement selected SHALL have no `target`, consistently with its entry carrying no machine and no closure.

#### Scenario: One module placed on two service managers

- **WHEN** one module is placed on a machine whose `serviceManager` is `systemd` and on a machine whose `serviceManager` is `launchd`, and applies a systemd extension only when `target.serviceManager` is `systemd`
- **THEN** the plan SHALL contain two entries whose portable unit fields agree
- **AND** the extension fields SHALL be recorded on the systemd entry only
- **AND** the planner SHALL emit no row

#### Scenario: An unplaced member

- **WHEN** no placement selects a member
- **THEN** that member's implementation arguments SHALL carry no `target`
- **AND** its entry SHALL carry no machine and no closure

### Requirement: An unrecognised implementation key is a row, not a silence

A module's implementation SHALL be read against an allow-list the way its declaration is. An unrecognised key at the implementation's top level, under a unit, inside an extension application or under a configuration file SHALL produce `implementation-unknown-key` naming the module, the location of the key, the key and the vocabulary that was read. Such a key SHALL NOT be discarded.

A key whose name collides with a construct this subset deliberately excludes SHALL produce that construct's exclusion row naming the condition that would bring it back, in preference to `implementation-unknown-key`. Reading SHALL remain total: an unrecognised key SHALL NOT stop the rest of the implementation being read, and the entry SHALL still appear in the plan.

#### Scenario: A raw service-manager stanza written on a unit

- **WHEN** a module writes a service manager's own stanza directly on a unit instead of through an extension
- **THEN** the planner SHALL emit `implementation-unknown-key` naming the module, the unit, the key and the vocabulary
- **AND** the stanza SHALL NOT be recorded and SHALL NOT be dropped without a row

#### Scenario: A misspelled vocabulary field

- **WHEN** a unit carries a key that is a misspelling of a vocabulary field
- **THEN** the planner SHALL emit `implementation-unknown-key` naming the key and the vocabulary
- **AND** the plan SHALL NOT record the unit as though that field had never been asked for

#### Scenario: One malformed unit beside one well-formed unit

- **WHEN** one unit of a module carries an unrecognised key and a second unit is well formed
- **THEN** the diagnostics SHALL carry exactly one row for the unrecognised key
- **AND** the plan SHALL record the second unit in full
- **AND** the plan SHALL still contain the entry

#### Scenario: A key naming an excluded construct

- **WHEN** a module's implementation carries a key whose name is that of a deliberately excluded construct
- **THEN** the planner SHALL emit that construct's exclusion row naming the condition that would bring it back
- **AND** the planner SHALL NOT emit `implementation-unknown-key` for that key

### Requirement: Each unit runs with its own environment

A plan entry SHALL record each unit's `env` on that unit. Two units of one entry declaring different values for one variable SHALL NOT be an error, and both values SHALL be recorded. The entry SHALL additionally record the environment its units agree on, so that a backend with one environment per service and a backend with one environment per unit are both served by one plan. Every unit's environment SHALL be part of the entry's key.

#### Scenario: Two units disagree about a variable

- **WHEN** two units of one entry declare different values for one environment variable
- **THEN** the plan SHALL record each unit with its own value
- **AND** the planner SHALL emit no row
- **AND** the entry's agreed environment SHALL NOT contain that variable

#### Scenario: Two units agree about a variable

- **WHEN** two units of one entry declare the same value for one environment variable
- **THEN** the plan SHALL record the variable on both units
- **AND** the entry's agreed environment SHALL contain it

#### Scenario: One unit's environment changes

- **WHEN** a value read into one unit's `env` changes and nothing else does
- **THEN** the entry's key SHALL change
- **AND** the entry's closure SHALL be unchanged

### Requirement: A configuration file names its bytes rather than carrying them

A configuration file SHALL record `mode`, `reload` — the units the module named — and exactly one of `source`, a store path holding the rendered file, or `render`, an ordered list whose items are `{ text = "<public literal>" }` or `{ ref = "<path>" }` that the machine concatenates. A record carrying both dispositions or neither SHALL be an error row naming the module and the file path. A file that names no unit SHALL record an empty `reload` rather than every unit of the entry.

A `source` file's identity SHALL be its store path, and no digest SHALL be taken over its bytes. A `render` list of nothing but `text` items SHALL carry `contentHash` over those literals, which the plan itself holds. A `render` list containing any `ref` SHALL carry a structure hash over its fragments and its reference paths and SHALL NOT carry `contentHash` or any other digest over assembled bytes. A file whose `render` list is computed from a set-valued read with an entry absent SHALL be recorded as not computed, with the row that absence produced, and SHALL NOT be assembled from the entries that do have values.

#### Scenario: A file copied from a store path

- **WHEN** a module records a configuration file as a `source` store path
- **THEN** the plan SHALL record that path with the file's `mode` and `reload`
- **AND** the plan SHALL record no `render` list and no digest over the file's bytes

#### Scenario: A file assembled from public literals

- **WHEN** a configuration file's `render` list contains `text` items only
- **THEN** the plan SHALL record the list in order together with `contentHash` over its literals
- **AND** a renderer SHALL be able to write the file without re-evaluating the module

#### Scenario: A recipe that references a secret path

- **WHEN** a configuration file's `render` list contains a `ref` naming a generated secret's path
- **THEN** the plan SHALL record the fragments, the reference path and a structure hash over them
- **AND** the plan SHALL NOT record `contentHash` or any other digest over the assembled file
- **AND** the secret's bytes SHALL appear nowhere in the plan

#### Scenario: A file reloading one of two units

- **WHEN** a module declares two units and one configuration file whose `reload` names only the first
- **THEN** the plan SHALL record that file's `reload` as the first unit alone
- **AND** a file that names no unit SHALL record an empty `reload`

#### Scenario: A file rendered over an incomplete set

- **WHEN** a configuration file's `render` list is computed from a set-valued read with one entry absent
- **THEN** the plan SHALL record the file as not computed, with the row that absence produced
- **AND** the plan SHALL record neither a hash nor a fragment list assembled from the entries that do have values

#### Scenario: Both dispositions on one file

- **WHEN** a configuration file record carries both `source` and `render`
- **THEN** the planner SHALL emit an error row naming the module and the file path
- **AND** the plan SHALL still contain the entry

### Requirement: The unit vocabulary carries a restart policy

The vocabulary `A unit carries a typed vocabulary and nothing else` enumerates SHALL additionally
carry `restart` and `restartSec`, read under every rule that requirement states: each is typed, a
value failing its type is an error row naming the module, the unit, the field and the type, and a
field a unit did not declare is absent from the record rather than recorded as a null or as a service
manager's default.

`restart` SHALL take one of `no`, `on-failure`, `on-abnormal` and `always`, and a value outside that
domain SHALL be an error row naming the module, the unit, the value and the four it may take. The
domain SHALL be the planner's own rather than a service manager's spelling, so that a renderer maps
it to what its service manager calls the same thing.

`restartSec` SHALL be a duration, and SHALL be recordable only beside a `restart`: a unit declaring a
delay and no policy SHALL be an error row naming the module and the unit, because a delay alone
changes nothing about a unit that is never restarted.

Both fields SHALL be part of the entry's key, as every other unit field is.

#### Scenario: A unit that is restarted when it fails

- **WHEN** a module declares a unit with `restart = "on-failure"` and a `restartSec`
- **THEN** the plan SHALL record both fields on that unit
- **AND** a unit of the same entry that declared neither SHALL record neither

#### Scenario: A restart policy outside its domain

- **WHEN** a module declares `restart` with a value that is none of the four the domain admits
- **THEN** the planner SHALL emit an error row naming the module, the unit, the value and the four
- **AND** the plan SHALL NOT record the failing value

#### Scenario: A restart delay with no policy

- **WHEN** a module declares `restartSec` on a unit that declares no `restart`
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL NOT record the delay

#### Scenario: A unit that declares no policy keeps its key

- **WHEN** an entry's units declare neither field
- **THEN** the entry's key SHALL be what it was before the vocabulary carried them
- **AND** the plan SHALL record neither field on any unit

### Requirement: A restart policy that contradicts the unit's shape is a row

A unit's restart policy SHALL be read against the shape the unit already declared, and a policy that
contradicts it SHALL be an error row rather than a value a renderer has to reconcile.

A `oneShot` unit declaring `restart = "always"` SHALL be `unit-restart-contradicts-one-shot`, naming
the module and the unit: a unit that applies and exits successfully is restarted for as long as it
keeps succeeding. `restart = "on-failure"` on a `oneShot` unit SHALL NOT be a row - a job that failed
and may be retried is a legitimate shape.

A unit declaring a `schedule` and any `restart` but `no` SHALL be `unit-restart-on-scheduled`, naming
the module and the unit: what decides when a scheduled unit runs is its schedule, and a restart
policy on it is a second, unstated schedule.

#### Scenario: A one-shot unit asking to be restarted always

- **WHEN** a module declares a unit with `oneShot` and `restart = "always"`
- **THEN** the planner SHALL emit `unit-restart-contradicts-one-shot` naming the module and the unit
- **AND** the plan SHALL NOT record the policy

#### Scenario: A one-shot unit retried on failure

- **WHEN** a module declares a unit with `oneShot` and `restart = "on-failure"`
- **THEN** the planner SHALL emit no row
- **AND** the plan SHALL record the policy

#### Scenario: A scheduled unit asking for a restart policy

- **WHEN** a module declares a unit with a `schedule` and `restart = "on-failure"`
- **THEN** the planner SHALL emit `unit-restart-on-scheduled` naming the module and the unit
- **AND** the plan SHALL NOT record the policy

### Requirement: A configuration file's disposition states when its bytes exist

The plan SHALL let a reader tell, from a configuration file's record alone, whether its bytes exist
before anything runs on the machine. A `source` file's bytes are a store path. A `render` list of
nothing but `text` items is bytes the plan itself holds, which is why that case carries
`contentHash`. A `render` list carrying any `ref` names a path on a machine, and its bytes therefore
do not exist until the referenced file has been delivered.

No new field SHALL be added to say this: the disposition and the presence of a `ref` already do, and
a realiser that cannot assemble bytes SHALL decide what it accepts from them. A file whose bytes
exist at build time SHALL NOT be refused by a realiser on the grounds of having no assemble step.

#### Scenario: A file whose bytes exist at build time

- **WHEN** a configuration file records a `source` store path, or a `render` list of `text` items only
- **THEN** the record SHALL permit a reader to conclude that the bytes exist before the machine is
  dialled
- **AND** no field beyond the disposition and the recipe SHALL be needed to conclude it

#### Scenario: A file whose bytes exist only on the machine

- **WHEN** a configuration file's `render` list carries a `ref`
- **THEN** the record SHALL name the reference path
- **AND** a reader SHALL be able to conclude that the assembled bytes exist on no machine until that
  path has been written

### Requirement: The unit vocabulary carries the directories a unit is given

The vocabulary `A unit carries a typed vocabulary and nothing else` enumerates SHALL additionally
carry the three kinds of directory a service manager creates for a unit and owns on its behalf -
state, runtime and cache - and one mode per kind. Each SHALL be read under every rule that
requirement states: each is typed, a value failing its type is an error row naming the module, the
unit, the field and the type, and a field a unit did not declare is absent from the record rather
than recorded as a service manager's default.

A kind SHALL take any number of directories, because a unit may be given more than one, and a
directory SHALL be named relative to the root its kind implies: the kind decides where the
directory lives and a name that states a root of its own is a value failing its type. A mode SHALL
be one mode per kind rather than one per directory, because that is the grain at which a service
manager applies one.

A mode SHALL be recordable only beside a directory of its own kind: a unit declaring a mode for a
kind it declares no directory of SHALL be an error row naming the module and the unit, because a
mode alone creates nothing. Every field SHALL be part of the entry's key, as every other unit field
is.

#### Scenario: A unit declaring a state directory and its mode

- **WHEN** a module declares a unit with one state directory and a mode for that kind
- **THEN** the plan SHALL record both on that unit
- **AND** a unit of the same entry that declared neither SHALL record neither

#### Scenario: A directory mode with no directory of its kind

- **WHEN** a module declares a cache directory mode on a unit that declares no cache directory
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL NOT record the mode

#### Scenario: A directory name that is not relative

- **WHEN** a module declares a state directory whose name states a root of its own
- **THEN** the planner SHALL emit an error row naming the module, the unit, the field and the type
- **AND** the plan SHALL NOT record the failing name

#### Scenario: A unit declaring no directory keeps its key

- **WHEN** an entry's units declare none of the six fields
- **THEN** the entry's key SHALL be what it was before the vocabulary carried them
- **AND** the plan SHALL record none of them on any unit

### Requirement: A directory a unit declares is the same claim however it was declared

A directory a unit declares SHALL be a claim that unit's entry makes on its machine, whether the
declaration was the vocabulary's or a backend extension's, so that two entries placed on one
machine declaring one directory earn the warning the planner already reports for a shared unit
directory either way. A claim SHALL keep carrying the kind it was declared under, so a state
directory and a runtime directory of one name are two claims and not a collision.

One kind declared both in the vocabulary and in a backend extension application on one unit SHALL
be an error row naming the module, the unit and the kind, and the plan SHALL record neither
declaration: a renderer handed two statements about one directory has no way to choose, and the
deployment can say it once.

#### Scenario: Two entries sharing a directory declared through the vocabulary

- **WHEN** two entries placed on one machine each declare the same runtime directory through the
  vocabulary
- **THEN** the planner SHALL emit the warning it reports for a shared unit directory, naming both
  entries, the machine and the directory
- **AND** the deployment SHALL still build

#### Scenario: A state directory and a runtime directory of one name

- **WHEN** two entries placed on one machine declare one name, one as a state directory and one as
  a runtime directory
- **THEN** the planner SHALL emit no row, the two being two directories on the machine

#### Scenario: One directory kind declared twice

- **WHEN** a module declares a unit with a state directory in the vocabulary and a state directory
  in a backend extension application
- **THEN** the planner SHALL emit an error row naming the module, the unit and the kind
- **AND** the plan SHALL record neither declaration

### Requirement: A unit may state a path its start is conditional on

A unit SHALL be able to state that it starts only while a path is absent, or only once a path is
present, and each SHALL be an absolute path. A unit MAY state one of each, in which case both hold.
A unit whose condition does not hold SHALL be skipped rather than failed, so a unit ordered after
it and requiring it still starts: the fact stated is when the unit has work to do, not whether the
machine is fit to run it.

One path stated as both present and absent SHALL be an error row naming the module, the unit and
the path, because it is a unit that can never start, and the plan SHALL record neither condition.

#### Scenario: A unit that starts only while a path is missing

- **WHEN** a module declares a unit that starts only while a path is absent
- **THEN** the plan SHALL record the path and the polarity on that unit
- **AND** the polarity SHALL be recorded as the planner's own fact rather than as a service
  manager's spelling of it

#### Scenario: A unit that starts only once a path exists

- **WHEN** a module declares a unit that starts only once a path is present
- **THEN** the plan SHALL record the path and that polarity
- **AND** a unit of the same entry that declared neither SHALL record neither

#### Scenario: A condition that contradicts itself

- **WHEN** a module declares one path as both present and absent on one unit
- **THEN** the planner SHALL emit an error row naming the module, the unit and the path
- **AND** the plan SHALL record neither condition

#### Scenario: A condition path that is not absolute

- **WHEN** a module declares a condition over a path that is not absolute
- **THEN** the planner SHALL emit an error row naming the module, the unit, the field and the type
- **AND** the plan SHALL NOT record the failing path

### Requirement: A configuration file's source is a store object or the file has no bytes

A configuration file's stated source SHALL be read for its kind and held to the store before it is
recorded. A source that is not a string, or that is a string naming a path outside the store, SHALL
be an error row naming the entry, the file's host path and what a source may be.

The file SHALL then have no bytes rather than bytes from somewhere else. The entry SHALL record the
host path, the mode and the ownership the declaration states and no disposition at all, so that a
reader cannot mistake a refused source for a file whose bytes exist, and nothing shows a unit a host
file the deployment never rendered under the name of its own configuration.

This SHALL be the rule `A generated value may declare the program that produces it` already states
for the other store path a declaration writes: the library records a literal string, resolves
nothing and reads nothing, and a value outside that grammar is a row rather than a path a builder
dereferences. One field of a plan SHALL NOT be held to two standards because two layers read it.

The check SHALL be the library's, so every realiser and every plan reader inherits it. The entry
SHALL still be planned and the deployment SHALL NOT be applicable, and every other entry of the
deployment SHALL still be read.

#### Scenario: A configuration file source is read for its kind and held to the store

- **WHEN** an implementation states a configuration file whose source is a host path outside the
  store, or a value of another kind entirely
- **THEN** the planner SHALL emit one error row naming the entry, the host path and what a source may
  be
- **AND** the file SHALL be recorded with no bytes and no disposition, so no realiser and no plan
  reader is handed the stated value
- **AND** the deployment SHALL NOT be applicable, and every other entry SHALL still be planned

### Requirement: A host path a unit binds carries nothing a service manager reads as its own

A host path a configuration file is written to SHALL be held to what a rendered bind can carry
literally, beside what a rendered shell word can carry. A service manager gives two characters a
meaning of its own inside such a value: the one that separates one bind from the next within a single
directive, and the one that introduces a specifier the manager expands before the bind is made. A
path carrying either is bound somewhere the entry never declared - a directive dropped for a field
count the author did not intend, or a mount at an expanded name - so each SHALL be an error row
naming the entry, the path and what the grammar admits, and the path SHALL NOT be recorded on the
entry.

The grammar SHALL be stated as what every renderer of the path can carry, not as what one of them
can. A recorded host path reaches a rendered shell word, the value of a bind and a plan reader that
resolves it, so a character any one of them reads as its own is a character none of them can be
handed.

The grammar SHALL keep exactly one home. Every realiser and every plan reader SHALL inherit it from
the library rather than state it again, and the reading that renders a delivery step SHALL read it
rather than restate it, so no grammar can admit a character in one rendered script and refuse it in
another. Narrowing it SHALL narrow it for all of them at once.

A refused path SHALL earn one row and not one per renderer that could not carry it, because the fact
is one: the deployment stated a path no renderer accepts.

#### Scenario: A configuration file path is a word a unit file can bind

- **WHEN** an implementation states a configuration file whose host path carries the character a bind
  list separates on, or the character a service manager expands as a specifier
- **THEN** the planner SHALL emit exactly one error row naming the entry, the path and what the
  grammar admits
- **AND** that row SHALL be the one every out-of-grammar host path already earns rather than an
  identifier of its own
- **AND** the path SHALL NOT be recorded on the entry, and the deployment SHALL NOT be applicable

### Requirement: A unit's own name and an environment name are held to the rule their values are

A unit's own name and the name of an environment variable SHALL be held to the rule the strings
inside a unit record are held to, so a line break in either SHALL be an error row. A renderer writes
both into a unit file with no escape of its own, so a line break in either forges a free directive
line, and a unit that carries a directive no module wrote does something no declaration states.

The row SHALL be the one a unit field's value carrying a line break already earns, naming the entry,
the unit and the name at fault, rather than an identifier of its own: one class of defect is one
identifier, and the row names its site. The entry SHALL still be read and the deployment SHALL NOT be
applicable, on the same terms that rule already states for the values it covers.

An environment variable's name SHALL additionally be held to the grammar a service manager can carry
for one, and a name outside it SHALL be an error row naming the entry, the unit and the name, with
neither the name nor its value recorded. The assignment a renderer would write from such a name is a
directive the manager refuses in part, after which the unit starts without the variable, and a unit
running with an environment the deployment did not declare is the silence this row replaces.

One name SHALL earn one row. A name the environment grammar refuses SHALL be reported by that rule
alone, including where the character it carries is a line break, so a reader is not told twice about
one name.

#### Scenario: A unit name carrying a line break is a row

- **WHEN** an implementation declares a unit whose own name contains a line break
- **THEN** the planner SHALL emit one error row naming the entry and that unit
- **AND** the row SHALL be the one a unit field's value carrying a line break already earns
- **AND** the deployment SHALL NOT be applicable, and every other entry SHALL still be planned

#### Scenario: An environment name is held to the environment name grammar

- **WHEN** a unit declares an environment variable whose name is outside the grammar a service
  manager can carry for an environment name
- **THEN** the planner SHALL emit one error row naming the entry, the unit and the name
- **AND** neither the name nor its value SHALL be recorded on the unit, so no renderer writes an
  assignment from it
- **AND** the name SHALL earn no second row about a character that grammar already refused
