<!--
A delta against `realiser/flakelet-artifact`, whose base text lives in the unarchived changes
`emit-flakelet-service-artifacts`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `take-effect-on-a-second-apply` and `hold-a-long-running-daemon`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The MODIFIED requirement below replaces `A host path this realiser cannot carry is refused`
(`hold-a-long-running-daemon`), which decided the question by when the bytes exist. That half is
kept; what it gains is the record, because a bind shows the ownership and the mode of what it binds
and this realiser binds store objects. `A host path whose bytes exist before activation is
accepted` and `The artifact carries what it assembled and nothing else new` keep every acceptance
they state for a file whose record is the store's, which is every configuration file declared under
`tests/e2e/` and `perf/`; the one declaration in this repository that states another record is a
fixture file at `0600`, whose realisation this change's task list settles.

The row that reports the new refusal is `operator-entry-path-not-installable`. No
`operator/deployment-build` delta accompanies it: `The realiser of an entry is stated, never
inferred` and `An inapplicable deployment is not built` (`report-every-refusal-as-a-row`) already
require every refusal of the stated realiser to be an error row of the table, and this is one of
them.

The conditions: `flakelet/read.nix:128-133` decides acceptance from the disposition alone;
`flakelet/default.nix:75-78` carries an assembled file as a store object of the artifact; and a
store object is `root:root` at `0444`, which is why a private key has to be copied out of the store
before it can be used.
-->

## ADDED Requirements

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

## MODIFIED Requirements

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
