## Purpose

Defines the typed vocabulary a module writes when it implements a service: the fields a unit may carry, the typed per-backend extensions that add fields beyond them, the target a module learns its service manager from, the environment each unit runs with, and the record a configuration file gets. A binding can render a service manager's unit file only from facts the plan carries, so this vocabulary is the contract between the planner and every binding that renders from it. Reading a module's implementation is allow-listed against it, so a fact a module wrote and the plan cannot hold is a diagnostic row rather than a silent omission.

## ADDED Requirements

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
