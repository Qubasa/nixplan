<!--
A delta against `planner/plan-artifact`, which lives in the unarchived `implement-minimal-typed-edge`
change and was last restated by `generate-values-with-nixos-secrets` and
`report-every-refusal-as-a-row`. Two conditions: `lib/plan.nix:160-165` derives a machine from an
entry key by splitting at the last `@`, and nothing under `lib/` refuses `@` in a machine, instance or
member name, so a name carrying the separator produces a delivery set naming a machine that does not
exist; and `lib/plan.nix:737` prunes `files` out of a value entry while `:748-752` deliberately keeps
`delivery` "always present, empty or not" for the reader that must not mistake it for an absence.
`lib/resolve.nix:536` reads a member by `member.name` where `lib/compose.nix:24-30` set it from the
member's own argument rather than its attribute key, which is the same class: one identity spelled
twice.
-->

## Purpose

Defines a plan key as an identity that can be taken apart again, the names that enter one as held to
a grammar the key can carry, and the fields of an entry that a reader must never be able to mistake
for an absence.

## ADDED Requirements

### Requirement: A name entering a key is held to the grammar the key can carry

A plan key is structured text, and a reader recovers an entry's parts by taking that structure apart.
Every name a key is built from - a machine, an instance, a member, a generator - SHALL therefore be
held to a grammar that excludes the characters the key's own structure uses. A name carrying one of
them SHALL be a row naming the declaration and the name.

A plan SHALL NOT be produced in which a key parses as a different key, and no fact derived from a key
- a delivery set above all - SHALL be allowed to name something the deployment never declared.

#### Scenario: A machine name carries the key separator

- **WHEN** a machine is named with a character the key's structure uses
- **THEN** the planner SHALL produce a row naming that machine
- **AND** SHALL NOT record a delivery set derived from a key that name made ambiguous

#### Scenario: An instance or member name carries the key separator

- **WHEN** an instance or a member is named with a character the key's structure uses
- **THEN** the planner SHALL produce a row naming that declaration

#### Scenario: A well-formed name is unaffected

- **WHEN** every name a deployment declares is within the grammar
- **THEN** the planner SHALL produce no row about a name
- **AND** every key SHALL take apart into exactly the parts it was built from

### Requirement: One identity of a member is spelled one way

A member SHALL have one identity, and every reading of that member SHALL use it. Where a member's
declaration offers two spellings - the key it is declared under and a name it carries - the planner
SHALL either hold them to be equal or report the difference as a row naming both, and SHALL NOT read
one where the other was recorded.

#### Scenario: A member is declared under a key other than its own name

- **WHEN** a member is declared under one attribute name and carries another
- **THEN** the planner SHALL produce a row naming both spellings
- **AND** the evaluation SHALL NOT end

### Requirement: A field a reader must not mistake for an absence is always recorded

An entry SHALL record every field a reader has to distinguish from an absence, whether or not that
field carries anything. Where a plan omits a field because its value was empty, no reader SHALL be
required to tell that omission apart from a field the entry never had.

The file record of a value entry SHALL be such a field: a value entry SHALL record its files whether
or not the generator declared any.

#### Scenario: A generator declares no files

- **WHEN** a generator declares no files
- **THEN** its value entry SHALL still record a file set, empty
- **AND** a reader SHALL NOT have to treat the field's absence as a shape of its own

#### Scenario: An entry records an empty collection a reader depends on

- **WHEN** an entry's field is a collection that a documented reader indexes
- **THEN** the plan SHALL record it empty rather than omit it
