<!--
A delta against `operator/deployment-build`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change and was last restated by
`report-every-refusal-as-a-row`. The reading is `operator/read.nix`; `CLAUDE.md` puts it on `lib/`'s
side, where every refusal is a row. Two conditions break that today: `operator/read.nix:326` reads
`entry.files` bare while `lib/plan.nix:737` prunes an empty `files` out of a value entry, and
`operator/read.nix:206` records `artifact = null` for a placed entry that declares no unit, which
`cli/manifest.py:328` then refuses for the whole deployment. The second is a disagreement between two
sides of one record, so the requirement below states the record once.
-->

## Purpose

Defines reading a plan into a build as total over every shape the plan can take, and defines the
record a build publishes for an entry as one both the build and the command that reads it agree on.

## ADDED Requirements

### Requirement: The reading is total over a plan the planner pruned

The plan omits a field whose value carries nothing, and the reading SHALL treat every such omission
as the absence it is. No field the plan may omit SHALL be read in a way that ends the evaluation:
where the reading needs a fact the plan does not record, it SHALL produce a row naming the entry and
the field, and the rest of the plan SHALL still be read.

A plan the planner accepted SHALL therefore always produce a table, and a reader SHALL never be shown
an evaluation error in place of one.

#### Scenario: A value entry records no files

- **WHEN** a generator declares no files, so its value entry carries no file record at all
- **THEN** the reading SHALL produce a row naming that value entry
- **AND** the reading SHALL still produce records for every other entry
- **AND** the evaluation SHALL NOT end with an error in place of the table

#### Scenario: A field the plan omits is needed by the reading

- **WHEN** the reading needs a field that the plan omits because its value was empty
- **THEN** the reading SHALL report it as a row rather than raising
- **AND** the row SHALL name the entry and the field

### Requirement: The record a build publishes is one every command can read

An entry's record in the manifest SHALL be readable by every command that reads the manifest,
whatever the entry declares. Where an entry legitimately has no artifact - a placed entry that
declares no unit is one the planner accepts - the record SHALL say so in a shape the reading side
accepts, and SHALL NOT be a value the reading side refuses.

A record of one entry SHALL NOT make a command refuse the whole deployment: a command that needs an
artifact only for some entries SHALL refuse only when it needs the one that is absent.

#### Scenario: An entry declares no unit

- **WHEN** a deployment places an entry that publishes an export and runs nothing
- **THEN** the build SHALL publish a record for that entry
- **AND** every command that reads the manifest SHALL read it without refusing
- **AND** a command that does not need an artifact for that entry SHALL proceed

#### Scenario: A command needs the artifact an entry does not have

- **WHEN** a command needs an artifact for an entry whose record names none
- **THEN** the refusal SHALL name that entry
- **AND** SHALL NOT be a refusal of the entries whose records the command can read
