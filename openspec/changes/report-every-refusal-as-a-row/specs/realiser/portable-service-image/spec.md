<!--
A delta against `realiser/portable-service-image`, which lives in the unarchived
`emit-systemd-portable-service-images` change. Two requirements are restated. `The image is built
outside the planner from the plan alone` is where the header claim of `image/read.nix:5-8` lives -
"Every refusal here is a condition mkPlan reports too, so a caller that wants the row already has
it" - and this delta restates it as what will be true rather than as what is claimed. `A rendered
environment value is one value` was added by `deliver-secrets-across-machines`, and this delta
restates that version: the newline refusal keeps its wording and gains the row that precedes it.

The rows that precede the raises are required by `planner/diagnostics` and
`operator/deployment-build`, both in this same change. `No secret and no configuration content
enters an image` and `Attachment is a named, recorded operation` are restated by
`deliver-a-secret-without-exposing-it` and are untouched here; the confinement denial of
`image/read.nix:346-350` is preceded by the row `A confinement profile is checked against the entry
it confines` requires.
-->

## Purpose

Defines what a portable-service image is built from, and what a refusal on this side means now that
the layers above it report the same conditions as rows. The builder adds no facts of its own, and it
is no longer the first thing a user hears about a fact one of those layers can see.

## MODIFIED Requirements

### Requirement: The image is built outside the planner from the plan alone

An image SHALL be built by a component outside `mkPlan`, and plan evaluation SHALL remain free of
derivations. The builder SHALL take one placed plan entry and the plan it belongs to, and SHALL
derive every fact it needs from them: the units to render, the extensions to render, the declared
closure roots to populate, the store directory to populate them under, the `target` to build for,
the configuration files to show and the generated files to expect.

The builder SHALL NOT re-evaluate the module the entry came from, and SHALL NOT read any value the
plan does not carry. A fact the builder needs and the plan does not carry SHALL be reported as a
missing plan field naming the entry, and SHALL NOT be inferred, defaulted, or read from the
surrounding evaluation.

Every refusal this builder makes SHALL be a condition an error row of the planner's table or of the
deployment build's table already reported, and a refusal about a fact the realisation statement
carries SHALL be reported by the deployment build rather than here. A refusal here SHALL therefore
be the answer a caller reaching this builder directly receives, and no path through a deployment
build SHALL reach one without a row. A field the plan records as empty SHALL NOT be refused as a
field the plan does not record.

#### Scenario: A plan entry becomes an image

- **WHEN** the builder is given a placed entry and the plan it belongs to
- **THEN** it SHALL produce one image for that entry
- **AND** the plan SHALL be the only input it read

#### Scenario: The planner stays derivation-free

- **WHEN** the planner is evaluated for a deployment whose entries are built into images
- **THEN** the plan SHALL carry no derivation and no function
- **AND** no image SHALL be built by evaluating the plan

#### Scenario: A fact the plan does not carry

- **WHEN** the builder needs a fact the entry does not record
- **THEN** it SHALL fail naming the entry and the missing field
- **AND** SHALL NOT substitute a default
- **AND** an entry recording that field as empty SHALL NOT be refused

### Requirement: A rendered environment value is one value

A rendered `Environment=` assignment SHALL carry the whole value the plan records, whatever
characters it contains, or the entry SHALL be refused. A value containing a space, a double quote
or a backslash SHALL be rendered so that the service manager reads back exactly the bytes the plan
holds. A value containing a newline SHALL be refused, naming the entry, the unit and the variable,
because a unit file is line-oriented and has no line to put it on.

A newline in a unit value is a fact the plan carries, so the planner SHALL report it as an error row
and this refusal SHALL follow that row rather than stand alone. A caller that reads the table SHALL
learn of every such value in one pass, and the refusal here SHALL remain for a caller that reached
the builder directly.

#### Scenario: An environment value carries a space

- **WHEN** a unit's environment holds a value containing a space, a double quote and a backslash
- **THEN** the rendered unit SHALL carry one assignment per variable
- **AND** each assignment SHALL round-trip to the value the plan records

#### Scenario: An environment value carries a newline

- **WHEN** a unit's environment holds a value containing a newline
- **THEN** the build SHALL fail naming the entry, the unit and the variable
- **AND** the same bytes on one line SHALL build
