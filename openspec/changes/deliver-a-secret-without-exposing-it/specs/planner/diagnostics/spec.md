<!--
A delta against `planner/diagnostics`, which lives in the unarchived `implement-minimal-typed-edge`
change and is already modified by `deliver-secrets-across-machines`.
`report-every-refusal-as-a-row` also modifies this capability: it restates "No evaluation path
raises" as the layering rule for where a refusal is produced, and adds its own requirement about a
row staying one line however it was built. This delta restates nothing, and adds one requirement
about what a row may print, so the two do not contradict.

The trigger is that three rows interpolate the type library's own message
(`lib/module.nix:655-664`, `lib/resolve.nix:822-830`, `lib/interface.nix:264-273`), and that message
pretty-prints the offending value: evaluated against the pinned revision it reads
`Expected type 'int' but value '"hunter2-db-password"' is of type 'string'`. The same rows tell the
reader the failing value is not recorded, as does `docs/diagnostics.md:109`. A mistyped secret
export therefore prints its bytes into a table that reaches a terminal, a log, and for a
warning-severity row a world-readable store file.
-->

## Purpose

Defines what a row about a typed value may say about that value: the type it was declared as, the
type it turned out to be, and the size or the field names of the thing, and never its content. A
diagnostics table is rendered to a terminal, written to a store file, and compared against a
committed golden file, so a row that quotes a value is a leak into all three.

## ADDED Requirements

### Requirement: A row names the type it expected and the type it received

A row about a value that failed a declared type SHALL state the type the declaration named and the
type the value turned out to be, and SHALL NOT state the value. What a row MAY state about the value
besides its type is its size in the terms of that type - the length of a string or a list, the field
names of a record - because those are structure the author wrote and never bytes a generator
produced.

The rule SHALL hold for every row about a typed value, whatever declared it: a unit field, an
extension field, or an export atom. A row's resolution SHALL be able to claim the value is not
recorded and be right.

A row's text SHALL be a function of the declared type and the received type rather than of the
value, so that two values of one wrong type against one declaration render one table. The library
SHALL obtain both type names from the declaration and from the interpreter, and SHALL NOT read them
out of the type library's message: a row whose text is parsed from a dependency's prose is a row
that changes when the dependency does, and the table is compared byte for byte against a committed
file.

#### Scenario: A type mismatch row names two types and no value

- **WHEN** a unit field, an extension field, or an export atom is given a value of the wrong type
- **THEN** each row SHALL name the declared type and the received type
- **AND** no part of the value SHALL appear in the row's message, evidence, or resolution
- **AND** the row SHALL still name the subject and the field, so the author knows where to edit

#### Scenario: A secret published with the wrong type

- **WHEN** an export an interface declares secret is published with a value that fails its atom's
  type
- **THEN** the rendered table SHALL contain no byte of that value
- **AND** the row SHALL name the export, the declared type, and the received type

#### Scenario: Two values of one wrong type produce one row text

- **WHEN** the same declaration is given two different values of the same wrong type
- **THEN** the two rendered tables SHALL be equal
- **AND** editing a fixture's offending value to another value of that type SHALL leave the
  committed table unchanged
