<!--
A delta against `planner/plan-artifact`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`, `prove-plan-on-real-machines`,
`deliver-a-secret-without-exposing-it`, `deliver-secrets-across-machines`,
`generate-values-with-nixos-secrets`, `identify-interfaces-by-declared-id`,
`report-every-refusal-as-a-row`, `hold-every-stated-guarantee`, `cut-a-member-and-wire-its-place`,
`declare-service-state` and `refuse-two-entries-claiming-one-host-resource`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Every requirement below is ADDED. `A delivered file states what it lands as`
(`deliver-a-secret-without-exposing-it`) is the requirement this change mirrors for the second
file-writing channel, and it is left alone: nothing about a generated value's file record changes,
including its `0400` default, which differs from a configuration file's because a configuration
file's mode is stated by every declaration already.

`An entry's key is a hash of everything that affects it` (`implement-minimal-typed-edge`) is stated
over the values an entry was handed rather than as a closed list, so the first requirement below
narrows it for one field the way `A generated value's program is carried` already does: a field the
declaration did not state is not an input.
-->

## ADDED Requirements

### Requirement: A configuration file states the account that may read it

A configuration file's record SHALL state the account and the group that may read it beside the
mode it already states, in the same words a generated value's file record states them. Both SHALL
be recorded on every configuration file, whether the declaration stated them or not, so that a
reader cannot mistake an unstated field for a record that does not say. Where a declaration states
neither, the record SHALL state the account and the group the plan defaults to, which SHALL be the
superuser's.

Only the fields a declaration actually stated SHALL be inputs to the entry's key. An entry whose
declarations state no ownership SHALL therefore carry the key it carried before a configuration
file's record could state one, and an entry that states an ownership SHALL carry a different key,
because it asks for a different file on the machine.

An owner or a group whose value fails its type SHALL be an error row naming the module, the file
and the type, and the failing value SHALL NOT be recorded: the defaulted record is what the plan
carries and what a realiser installs.

#### Scenario: A configuration file stating an owner and a group

- **WHEN** a module declares a configuration file stating an owner and a group beside its mode
- **THEN** the entry's record of that file SHALL state all three
- **AND** the entry's key SHALL differ from the key of the same deployment with the ownership
  omitted

#### Scenario: A configuration file stating no ownership

- **WHEN** a module declares a configuration file stating only a mode, a reload list and a recipe
- **THEN** the record SHALL state the superuser as both the owner and the group
- **AND** the record SHALL state them as fields rather than omitting them

#### Scenario: Only the ownership stated enters the key

- **WHEN** a deployment whose configuration files state no ownership is planned
- **THEN** every entry's key SHALL be the key that deployment had before the record could carry an
  ownership
- **AND** adding a group to one file SHALL move that entry's key and no other entry's key

#### Scenario: An ownership that fails its type

- **WHEN** a module declares a configuration file whose owner is not an account name
- **THEN** the planner SHALL emit an error row naming the module, the file and the type
- **AND** the record SHALL state the defaulted owner rather than the failing value

### Requirement: A unit that cannot open a configuration file its entry shows it is a row

A configuration file's record SHALL be read against the account each unit of its own entry runs as,
and a unit that could not open the file SHALL be an error row naming the unit, the account, the
file and the record it is shown at. The comparison SHALL be the one the planner already makes for a
delivered value a consumer declared a read of: the owner bit admits the account that owns the file,
the group bit admits an account whose unit declares that group, and the world bit admits any
account.

The row SHALL be reported whether or not any confinement profile is involved, because a service
whose units run under no profile is still a service whose units fail to start. A unit declaring no
account SHALL earn no row, the account it runs as then being the superuser's.

#### Scenario: A unit that cannot open its own configuration file

- **WHEN** an entry declares a configuration file the superuser alone may read and a unit of that
  entry runs as another account
- **THEN** the planner SHALL emit an error row naming the unit, the account, the file and its record
- **AND** the resolution SHALL name both stating an ownership the unit admits and running the unit
  as the account the file names

#### Scenario: A unit admitted by the file's group

- **WHEN** an entry declares a configuration file readable by its group and a unit of that entry
  declares that group
- **THEN** the planner SHALL emit no row for that file
- **AND** the record SHALL state the group the unit was admitted by

#### Scenario: A unit that declares no account

- **WHEN** an entry declares a configuration file the superuser alone may read and its units
  declare no account
- **THEN** the planner SHALL emit no row for that file
