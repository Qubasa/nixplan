<!--
A delta against `tooling/test-layers`, whose base text lives in the unarchived changes
`strip-planner-tests-to-unit-and-e2e`, `add-scenario-test-harness`,
`resume-e2e-machines-from-snapshots`, `run-a-shared-database-on-real-machines`,
`report-a-secrets-refusal-as-a-row` and `hold-every-stated-guarantee`. `openspec/specs/` is empty in
this repository, so the base text is read from those changes.

Both requirements below are ADDED. `run-a-shared-database-on-real-machines` states that a folder
writing state on a machine declares the space its stage needs; this delta states how such a folder is
recognised, now that the knob naming a data directory is deleted in favour of a derived path, and what
one folder has to hold for the instancing goal to be proven by an artifact rather than by prose.
-->

## ADDED Requirements

### Requirement: A folder that writes state is recognised by what its modules declare

The check that a stateful folder declares its own disk space SHALL recognise such a folder from a
fact its modules still carry once every host path is derived rather than stated. A folder that writes
state on a machine and is not recognised SHALL fail the check rather than pass it vacuously, so that
deleting a settings knob cannot silently remove a folder from the set the check covers.

The space SHALL be declared on the folder's own stage and nowhere else. Nothing about the shared guest
image SHALL carry it, because every property of that image is part of every folder's snapshot cut key.

#### Scenario: A folder writing state is recognised by what it declares

- **WHEN** the folder whose modules derive their state directories is checked
- **THEN** it SHALL be counted as a folder that writes state
- **AND** the check SHALL require its stage to declare disk space

#### Scenario: A stateful folder declares its space on its own stage

- **WHEN** every folder that writes state is read
- **THEN** each SHALL declare its space where its stage is declared
- **AND** the shared guest image SHALL declare no per-folder space

### Requirement: One folder proves both halves of the instancing goal

The machine layer SHALL hold one folder in which one service module is instantiated twice in one
deployment: once shared between consumers on two machines and once owned by a single application,
with both instances placed on one machine. The two instances SHALL be backed by one module file, so
that what the folder proves is instantiation rather than two modules that happen to resemble each
other.

#### Scenario: One module file backs both instances

- **WHEN** the folder's modules are read
- **THEN** the module the application composes its own database from SHALL be the same file the
  shared instance is built from
- **AND** the folder SHALL hold no second copy of it
