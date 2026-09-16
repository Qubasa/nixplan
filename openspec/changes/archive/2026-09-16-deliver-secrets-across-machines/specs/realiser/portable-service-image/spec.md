<!--
A delta against `realiser/portable-service-image`, which lives in the unarchived
`emit-systemd-portable-service-images` change. One requirement is added, and it is a defect this
change's end-to-end run found: the first public export whose value contains a space reached the
unit as two assignments, and the consuming service read back the first word.
-->

## ADDED Requirements

### Requirement: A rendered environment value is one value

A rendered `Environment=` assignment SHALL carry the whole value the plan records, whatever
characters it contains, or the entry SHALL be refused. A value containing a space, a double quote
or a backslash SHALL be rendered so that the service manager reads back exactly the bytes the plan
holds. A value containing a newline SHALL be refused, naming the entry, the unit and the variable,
because a unit file is line-oriented and has no line to put it on.

#### Scenario: An environment value carries a space

- **WHEN** a unit's environment holds a value containing a space, a double quote and a backslash
- **THEN** the rendered unit SHALL carry one assignment per variable
- **AND** each assignment SHALL round-trip to the value the plan records

#### Scenario: An environment value carries a newline

- **WHEN** a unit's environment holds a value containing a newline
- **THEN** the build SHALL fail naming the entry, the unit and the variable
- **AND** the same bytes on one line SHALL build
