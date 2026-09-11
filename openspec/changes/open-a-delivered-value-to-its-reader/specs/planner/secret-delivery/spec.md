<!--
A delta against `planner/secret-delivery`, whose base text lives in the unarchived changes
`deliver-secrets-across-machines` and `generate-values-with-nixos-secrets`. `openspec/specs/` is
empty in this repository, so the base text is read from those changes.

Every requirement below is ADDED. What derives a delivery set, that a secret's bytes never enter the
plan, and that a value is its own entry are all unchanged. What this delta adds is the one fact about
a delivered file the deployment could not state: who may read it.

The condition: `lib/module.nix:365` is `allowed = [ "secrecy" ]`, so a generated file record carries
no ownership and no mode, and `cli/remote.py:284` writes every one of them `chmod 0400` as root.
-->

## ADDED Requirements

### Requirement: A generated file records the ownership and mode it is delivered at

A generated file's record SHALL carry `owner`, `group` and `mode`, each optional and each defaulting
to what the delivery writes today: `root`, `root` and `0400`. A file declaring none of the three
SHALL be recorded with those values and SHALL be delivered exactly as it is delivered before this
change.

`owner` and `group` SHALL be account names rather than numeric identifiers, for the reason
`lib/atoms.nix` already gives for a unit's `user`: an identifier is the machine's answer and a name
is what a deployment can state portably. `mode` SHALL be a file mode, and a value that is not one -
a decimal integer, a three-digit string, a mode with bits outside the permission set - SHALL be an
error row naming the generator, the file and the form a mode takes.

The record SHALL be part of the value entry's key input: two values differing only in the mode they
are delivered at are two values, because the bytes on a machine differ in a way a reader can
observe.

A file's record SHALL be readable from the plan by every layer that delivers or reads one, so that no
layer has to restate the default.

#### Scenario: A file that declares nothing

- **WHEN** a generator declares a file with a `secrecy` and no ownership and no mode
- **THEN** the plan SHALL record that file as owned by `root`, grouped `root`, at mode `0400`
- **AND** the value entry's key SHALL be what it was before the record carried the three fields

#### Scenario: A file readable by an account

- **WHEN** a generator declares a file with `owner`, `group` and `mode`
- **THEN** the plan SHALL record all three on that file
- **AND** the value entry's key SHALL differ from the same value declaring the defaults

#### Scenario: A mode that is not a mode

- **WHEN** a generator declares a file whose `mode` is a decimal integer or a malformed string
- **THEN** the planner SHALL emit an error row naming the generator, the file and the form a mode
  takes
- **AND** the plan SHALL NOT record the failing value

#### Scenario: Two values differing only in mode

- **WHEN** one deployment declares a file at `0400` and another declares the same file at `0440`
- **THEN** the two value entries SHALL carry different keys
- **AND** each entry's recorded mode SHALL be its own

### Requirement: The record travels with the value to every machine that receives it

The ownership and mode a file records SHALL reach every machine in the value's delivery set, and
SHALL be the same on each: one value has one answer about who may read it, however many machines
receive it, the way it already has one answer about whether it exists.

A layer that writes a value SHALL take the ownership and mode from the record rather than from a
literal of its own, so that the deployment's statement and the bytes on every machine cannot
disagree.

#### Scenario: One value on two machines

- **WHEN** a value is delivered to two machines
- **THEN** the file SHALL carry the recorded owner, group and mode on both
- **AND** neither machine SHALL hold it at a mode the record does not state
