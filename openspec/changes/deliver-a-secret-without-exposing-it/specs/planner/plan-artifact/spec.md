<!--
A delta against `planner/plan-artifact`, which lives in the unarchived
`implement-minimal-typed-edge` change and is already modified by
`emit-systemd-portable-service-images`, `prove-plan-on-real-machines`, `declare-service-state`,
`deliver-secrets-across-machines`, and `generate-values-with-nixos-secrets`.

Two things change. The record of a generated file (`lib/plan.nix:89-99`) carries `path`, `secrecy`,
and `inPlan`, so a delivery has nothing to read about how the file should land and
`cli/remote.py:140-145` supplies constants instead; the record gains the two facts a delivery needs.
And `lib/resolve.nix:799` sets an export's `value` before `export-secret-not-a-reference` is
decided, so `lib/plan.nix:171-174` copies the bytes the row complains about into the plan beside the
row: an operator build refuses, and a direct `mkPlan` consumer receives them.

"Secret values appear as references and public values as content" is restated as
`deliver-secrets-across-machines` leaves it, plus the refused export. `operator/apply-command` in
this same change owns what a delivery does with the two new fields.
-->

## Purpose

Defines what a plan states about a delivered file beyond where it goes: the mode and the owner it
lands with, which unit answers for that owner, and the guarantee that a record refusing to publish
a secret publishes no part of it.

## ADDED Requirements

### Requirement: A delivered file states what it lands as

Each file of a generated value SHALL record the mode it lands with and the owner it lands as, and
SHALL record both whether or not the author wrote either, so that no reader can mistake the field
for an absence. A delivery SHALL have no reason to choose either, and a realiser SHALL have no
reason to infer them.

The owner SHALL be stated without the plan acquiring a notion of users beyond the one it holds: it
is either the machine's own privileged user, or a reference to a unit the plan carries, whose own
declared user answers for the file. A reference naming a unit that declares no user, or a unit of an
entry no machine of the value's delivery set runs, SHALL be an error row naming the file and the
reference.

A unit that opens the path of a generated file whose recorded mode and owner do not admit that
unit's own declared user SHALL be an error row naming the entry, the unit, and the file. The check
SHALL be a comparison of recorded facts, and SHALL read nothing about any machine's accounts.

#### Scenario: A delivered file records the mode and the owner it lands with

- **WHEN** a generator declares a file and states neither a mode nor an owner
- **THEN** the file's record in the plan SHALL carry both fields with the values a delivery will
  apply
- **AND** a file stating a mode SHALL carry that mode instead

#### Scenario: A file is owned by the unit that reads it

- **WHEN** a generated file states its owner as a reference to a unit of the declaring member, and
  that unit declares a user
- **THEN** the file's record SHALL resolve the owner to that unit's declared user
- **AND** a reference to a unit declaring no user SHALL produce an error row naming the file and the
  unit

#### Scenario: A unit cannot read the file it opens

- **WHEN** a unit declares a user and opens the path of a generated file whose recorded mode and
  owner grant that user nothing
- **THEN** the diagnostics table SHALL carry an error row naming the entry, the unit, and the file
- **AND** the same declaration with the file owned by that unit SHALL produce no row

## MODIFIED Requirements

### Requirement: Secret values appear as references and public values as content

An export declared `secret` SHALL appear in the plan as a path reference and never as content. An
export declared `public` MAY appear as content. A generated file declared `secret` SHALL appear as a
reference; its public counterpart MAY appear as a value.

A generated file's path SHALL name the instance that owns the generator, the generator and the file,
because a machine may hold values it does not own and two instances of one module would otherwise
name one file. The path SHALL be the same on every machine that receives the value, so that one
delivery of one value has one name.

An export the planner refuses because it publishes a secret as a value rather than as a generated
file SHALL carry no value in the plan. The refusal and the bytes it refuses SHALL NOT travel
together: the record for such an export SHALL state the export, its secrecy, and its readers, and
SHALL omit the content, so that a consumer reading the plan directly is in the same position as one
reading a build that refused.

#### Scenario: A private key in the plan

- **WHEN** a module publishes a generated file declared `secret` as an export
- **THEN** the plan SHALL record the export's path and secrecy and no bytes of the file

#### Scenario: A secret with no reader

- **WHEN** a secret export is declared and no slot reads it
- **THEN** the plan SHALL record it with an empty reader list

#### Scenario: A generated file's path names its instance

- **WHEN** two instances of one module, each declaring a generator called `app`, are placed on one
  machine
- **THEN** the two files' paths SHALL differ by the instance segment
- **AND** each path SHALL be the one recorded on every machine that receives that value

#### Scenario: A secret published as a value carries no bytes in the plan

- **WHEN** a module publishes a value rather than a generated file for an export its interface
  declares secret
- **THEN** the diagnostics table SHALL carry the error row for it
- **AND** the export's record in the plan SHALL carry no content
- **AND** the bytes SHALL be findable nowhere in the plan
