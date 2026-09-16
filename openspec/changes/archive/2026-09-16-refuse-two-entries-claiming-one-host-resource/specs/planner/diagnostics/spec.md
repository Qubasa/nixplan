<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`,
`report-every-refusal-as-a-row`, `open-a-delivered-value-to-its-reader`,
`normalise-folds-and-report-refused-reads` and `hold-every-stated-guarantee`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The existing requirements about a row's shape, its ordering, its
deduplication and the totality of evaluation are unchanged: these rows are ordinary rows and are
subject to all of them. What is new is that a row may be about two entries rather than one, which is
why the requirement states which of the two is the subject.
-->

## ADDED Requirements

### Requirement: A host resource two entries of one machine both claim is a row

The planner SHALL report a row when two entries placed on one machine both claim one host resource.
Three claims SHALL be read, and each SHALL be read from what the plan already records, so that no
plan field and no module vocabulary is introduced by this rule:

- a host path a configuration file is written to, which SHALL be an error;
- a fixed port claimed with one protocol, which SHALL be an error;
- a unit directory name a unit extension application records under `runtimeDirectory`,
  `stateDirectory` or `cacheDirectory`, which SHALL be a warning.

An error SHALL block an apply, because two entries writing one file is two renderings of one file and
two entries claiming one port is a daemon that cannot bind. The directory claim SHALL be a warning,
because two entries sharing one state directory is a handoff a deployment may intend while two
entries sharing one runtime directory loses one of their records at the next restart: the row SHALL
name it and the deployment SHALL still build.

A row SHALL name both entries, the machine, and the resource they both claim, and its resolution
SHALL name deriving the resource from the entry's own identity. The row SHALL be reported once for
one collision rather than once per claimant, and its subject SHALL be the first of the colliding plan
keys in the plan's own order, so that two evaluations of one deployment render one table byte for
byte.

Reading a unit extension's directory fields by name SHALL NOT name a realiser: the field names are
the ones a realiser's directive table and this rule both read, which is how the library already reads
a unit's declared groups.

#### Scenario: Two entries on one machine write one host path

- **WHEN** two entries placed on one machine each declare a configuration file at the same host path
- **THEN** the planner SHALL emit an error row naming both entries, the machine and the path
- **AND** the row SHALL appear once in the table

#### Scenario: Two entries on one machine claim one port

- **WHEN** two entries placed on one machine each claim the same fixed port with the same protocol
- **THEN** the planner SHALL emit an error row naming both entries, the machine, the protocol and the
  port

#### Scenario: Two entries on one machine share one unit directory

- **WHEN** two entries placed on one machine each apply a unit extension recording the same runtime
  directory name
- **THEN** the planner SHALL emit a warning row naming both entries, the machine and the directory
- **AND** the table SHALL carry no error on account of it

#### Scenario: One member placed on two machines claims its path on each

- **WHEN** one member is placed on two machines and declares one configuration file
- **THEN** the planner SHALL emit no collision row
- **AND** each entry SHALL record that file

#### Scenario: Two units of one entry share its directory

- **WHEN** two units of one entry apply a unit extension recording the same directory name
- **THEN** the planner SHALL emit no collision row, the claim being the entry's own

#### Scenario: A collision is reported once and names both entries

- **WHEN** three entries placed on one machine all claim one fixed port
- **THEN** the table SHALL carry one row for that port
- **AND** the row SHALL name all three plan keys and be subjected to the first of them in the plan's
  order
