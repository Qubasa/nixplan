<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `deliver-secrets-across-machines`,
`hold-declaration-shape-and-fold-set-reads`, `report-every-refusal-as-a-row`,
`hold-every-stated-guarantee` and `deliver-a-secret-without-exposing-it`. `openspec/specs/` is empty
in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The row contract - six fields, one line, ordered by identifier then
subject then message, deduplicated, a subject that is a plan key or a relative path - is unchanged
and is what the new row is built with.

The condition: the planner holds a unit's `user` (`lib/module.nix:58-70`) and, after
`openspec/changes/open-a-delivered-value-to-its-reader` widens the file record, the ownership and
mode a value is delivered at. Today it compares them nowhere, and the failure is a unit that starts
and dies with `EACCES` on a path the plan told it to read.
-->

## ADDED Requirements

### Requirement: A unit that cannot open a value it reads is an error row

Where an entry declares a read of an export backed by a generated file that will be delivered, and a
unit of that entry runs as an account the file's recorded ownership and mode do not admit, the
planner SHALL emit an error row naming the reading entry, the unit, the account the unit runs as, the
slot, the export and the ownership and mode the file records.

The comparison SHALL be made from the plan alone: the file's `owner`, `group` and `mode`, and the
unit's `user`. A unit that declares no user runs as the machine's privileged account and SHALL NOT
earn the row. A file whose mode admits a reader other than its owner - by group where the unit's
declared groups include the file's, or by the mode's world bits - SHALL NOT earn the row.

The row SHALL be an error, because the outcome it predicts is a unit that cannot start, and its
resolution SHALL name both ways out: deliver the file at an ownership the unit's account admits, or
run the unit as the account the file names.

Producing the row SHALL NOT depend on which realiser reads the entry. A realiser whose confinement
imposes a different account is a second, separate condition reported by the layer that holds the
realisation statement.

#### Scenario: A unit running as an account reads a root-only value

- **WHEN** an entry's unit declares `user` and the entry declares a read of an export backed by a
  file recorded as owned by `root` at mode `0400`
- **THEN** the planner SHALL emit an error row naming the entry, the unit, the account, the slot, the
  export and the file's ownership and mode
- **AND** the deployment SHALL be inapplicable

#### Scenario: A unit running as the account the file names

- **WHEN** the file records that account as its `owner`
- **THEN** the planner SHALL emit no row
- **AND** the plan SHALL record the read

#### Scenario: A unit reading a group-readable value

- **WHEN** the file records a `group` the unit's declared groups include, at a mode with group read
- **THEN** the planner SHALL emit no row

#### Scenario: A privileged unit reads a root-only value

- **WHEN** an entry's unit declares no `user` and reads a root-only value
- **THEN** the planner SHALL emit no row

#### Scenario: One unit of two cannot open the value

- **WHEN** one unit of an entry runs as an account the file does not admit and a second unit of the
  same entry runs privileged
- **THEN** the diagnostics SHALL carry exactly one row, naming the first unit
- **AND** the plan SHALL still record the entry and both units
