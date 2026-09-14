<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`,
`report-every-refusal-as-a-row`, `open-a-delivered-value-to-its-reader`,
`normalise-folds-and-report-refused-reads`, `hold-declaration-shape-and-fold-set-reads`,
`hold-every-stated-guarantee`, `cut-a-member-and-wire-its-place`,
`deliver-a-secret-without-exposing-it`, `deliver-secrets-across-machines` and
`refuse-two-entries-claiming-one-host-resource`. `openspec/specs/` is empty in this repository, so
the base text is read from those changes.

Both requirements are ADDED. Neither restates the row's shape, its ordering, its deduplication or
the totality of evaluation: these are ordinary rows and are subject to all of them.

The first requirement generalises a rule the base text states only about an environment value. That
rule lives in `realiser/portable-service-image` as `A rendered environment value is one value`
(added by `deliver-secrets-across-machines`, restated by `report-every-refusal-as-a-row`), and its
row identifier - `unit-env-value-newline`, named in
`openspec/changes/report-every-refusal-as-a-row/tasks.md:235` - is replaced here by one identifier
covering every field a unit file carries. The realiser delta of this change restates its half. No
requirement of `planner/diagnostics` names the old identifier, so nothing here is MODIFIED.
-->

## ADDED Requirements

### Requirement: A value a unit file cannot carry is a row for every field the file carries

A unit file is line-oriented, so a line break in a value is a fact the file cannot carry, and the
planner SHALL report one error row for such a value wherever the unit record holds it. The rule
SHALL hold for every string the record carries at any depth - a plain field, an element of a list
field, a value of an attribute-set field, and a field of an extension application - and SHALL NOT be
written against an enumerated list of fields, because a field added to the vocabulary or a field an
extension author declares is then covered by existing rather than by a second edit.

The row SHALL name the entry, the unit and the path of the field the value sits at, so that a reader
who wrote a newline into a command is not told about an environment variable. One identifier SHALL
cover every field, because a reader meeting two identifiers for one class of defect has to learn
which field belongs to which, and a table carrying both would report one mistake twice for a value
that appears in two fields.

A value carrying a space, a quote or a backslash SHALL NOT be a row: those are facts a unit file can
carry, and carrying them is the renderer's work.

A value whose own field type already refuses a line break SHALL be reported by that type and by this
rule nowhere, so that one fact earns one row. A field the planner withheld from the record for any
other reason SHALL likewise earn no row from this rule: the rule is about what a file will be
rendered from, and a withheld value is rendered from nothing.

#### Scenario: A newline in a command is a row

- **WHEN** a unit declares a command whose value contains a line break
- **THEN** the planner SHALL emit one error row naming the entry, the unit and the field
- **AND** the deployment SHALL NOT be applicable
- **AND** the entry SHALL still be read, with the rest of its units recorded

#### Scenario: A newline in an extension value is the same row

- **WHEN** a unit applies an extension whose field value contains a line break, at any depth of that
  value
- **THEN** the planner SHALL emit the same error row, naming the extension and the field
- **AND** the row's identifier SHALL be the one an environment value with a line break earns

#### Scenario: A newline in a user name is reported once by its type

- **WHEN** a unit declares a user name whose value contains a line break
- **THEN** the planner SHALL report the field's own type failure
- **AND** SHALL emit no second row about the line break
- **AND** the value SHALL NOT be recorded

#### Scenario: A value carrying a space and a quote is no row

- **WHEN** a unit declares a command and an environment value each carrying a space, a double quote
  and a backslash
- **THEN** the planner SHALL emit no row about them
- **AND** both values SHALL be recorded as the bytes the module wrote

### Requirement: A configuration file's host path is held to the grammar a rendered step can carry

A host path a configuration file is written to SHALL be held to the grammar of one word a rendered
shell step can carry, and a path outside it SHALL be an error row naming the entry, the path and
what the grammar admits. The check SHALL be made by the library, so that every realiser and every
plan reader inherits it and none of them has to state it again.

The grammar SHALL be the one the other rendered step of this repository already states for the paths
and addresses it renders, and that grammar SHALL have exactly one home: the reading that renders a
delivery step SHALL read it rather than restate it, so that a widened grammar cannot admit a
character in one rendered script and refuse it in another.

A refused path SHALL NOT be recorded on the entry. A path the library has just said no rendered step
can carry is not a fact to hand a reader, and a reader may be handed a plan whose table it did not
read; the file is therefore left out of the record the way a name carrying a key separator is left
out of every key it would have entered. Nothing else about the entry SHALL be withheld: its units,
its closure and its other configuration files SHALL be recorded as they were.

A row SHALL be produced whether the path was written by a deployment or derived inside an
implementation, because both reach the same rendered script.

#### Scenario: A newline in a configuration file path is a row

- **WHEN** an implementation declares a configuration file whose host path contains a line break
- **THEN** the planner SHALL emit an error row naming the entry, the path and what the grammar
  admits
- **AND** the entry SHALL record no configuration file at that path

#### Scenario: A configuration file path carrying a shell metacharacter is a row

- **WHEN** an implementation declares a configuration file whose host path contains a command
  substitution
- **THEN** the planner SHALL emit the error row before anything is built
- **AND** the deployment SHALL NOT be applicable

#### Scenario: A configuration file path carrying a quote is a row

- **WHEN** an implementation declares a configuration file whose host path contains a double quote
- **THEN** the planner SHALL emit the error row
- **AND** the row SHALL name the path in a subject a rendered table can carry

#### Scenario: A refused path is left out of the entry record

- **WHEN** one of an entry's two configuration files is declared at a refused path
- **THEN** the entry SHALL record the other file and its units unchanged
- **AND** the refused path SHALL appear in no field of the plan

#### Scenario: One grammar answers for both rendered steps

- **WHEN** the grammar of a renderable word is widened or narrowed
- **THEN** the path a configuration file is written to and the path a delivery step renders SHALL be
  held to the same admitted characters
- **AND** neither reading SHALL carry a second statement of it
