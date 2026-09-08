<!--
`openspec/specs/` is empty: `realiser/portable-service-image` exists only in the unarchived
`emit-systemd-portable-service-images` change, so this delta is written against that change's
text and only adds to it.
-->

## ADDED Requirements

### Requirement: The rendered unit carries the state directives the plan declared

A unit rendered from an entry SHALL carry the state directives derived from that entry's state
declaration, and SHALL derive them in that direction only: the declaration is the source and the
directive is its rendering, so no unit field is the second place a folder is stated. A durable
folder inside the location the service manager owns SHALL render as that manager's state
directive naming the folder relative to it. A derived folder inside the location the service
manager owns for disposable data SHALL render as that manager's cache directive. A declared owner
SHALL render as the account the unit runs as.

#### Scenario: A durable folder renders

- **WHEN** an entry declares a durable folder inside the location its service manager owns for state
- **THEN** the rendered unit SHALL carry that manager's state directive naming the folder relative to that location

#### Scenario: A derived folder renders

- **WHEN** an entry declares a derived folder inside the location its service manager owns for disposable data
- **THEN** the rendered unit SHALL carry that manager's cache directive rather than its state directive

#### Scenario: An owner renders

- **WHEN** an entry declares a state folder with an owner
- **THEN** the rendered unit SHALL run as that account

### Requirement: A state declaration the builder cannot express is a refusal

The builder SHALL refuse a state declaration it cannot render, naming the entry, the path and the
field, rather than dropping the folder or inventing an owner. A refusal SHALL be a raise, as
every refusal on this side is: the planner has already produced a row for what it can see, so a
declaration reaching the builder unexpressed means the plan was written by something other than
the planner.

#### Scenario: A folder with no expressible rendering

- **WHEN** a plan entry declares a state folder the entry's service manager cannot express and no owner
- **THEN** the build SHALL fail naming the entry and the path

#### Scenario: A disposition the builder does not know

- **WHEN** a plan entry declares a state folder whose disposition is outside the recorded domain
- **THEN** the build SHALL fail naming the entry, the path and the value

### Requirement: State participates in the image's identity

An entry's state declaration SHALL be part of what the image is built from, so two builds of one
entry SHALL produce byte-identical images and a change to a declared folder SHALL change the
bytes. A change to another entry's state SHALL leave this entry's image unchanged.

#### Scenario: A rebuild is identical

- **WHEN** the same entry declaring state is built twice
- **THEN** the two images SHALL be byte-identical

#### Scenario: An owner changes

- **WHEN** a state folder's owner changes and nothing else does
- **THEN** that entry's image SHALL differ
- **AND** no other entry's image SHALL differ
