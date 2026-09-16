<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `deliver-secrets-across-machines`,
`deliver-a-secret-without-exposing-it`, `report-every-refusal-as-a-row`,
`open-a-delivered-value-to-its-reader`, `hold-declaration-shape-and-fold-set-reads`,
`cut-a-member-and-wire-its-place`, `hold-every-stated-guarantee` and
`refuse-two-entries-claiming-one-host-resource`. `openspec/specs/` is empty in this repository, so
the base text is read from those changes.

The ADDED requirement is the three refusals a port claim can earn. The MODIFIED requirement is
`A host resource two entries of one machine both claim is a row`, whose base text is
`refuse-two-entries-claiming-one-host-resource`: its path and directory halves are restated
unchanged, and its port half is amended, because the claim that half compares is now typed and can
carry an address. The identifiers of the three collision rows do not move, and the requirements
about a row's shape, its ordering and its deduplication are unchanged.
-->

## ADDED Requirements

### Requirement: A port claim outside the vocabulary's domains is a row

The planner SHALL report a row for each part of a port claim that falls outside what the vocabulary
admits, and each row SHALL name the claim, the module that wrote it and what the field may take:

- a number that is not a port, which SHALL be an error and SHALL leave the claim unrecorded;
- a protocol outside the named domain, which SHALL be an error and SHALL leave the number recorded
  with no protocol;
- an address that is not an address, which SHALL be an error and SHALL leave the number recorded
  with no address.

A row about a protocol SHALL name every value the domain admits, the way a row about any other
enumerated field of this vocabulary does, so that the refusal states the answer rather than only the
mistake.

The wildcard SHALL NOT be spellable. An address whose text is a wildcard SHALL be refused with a
resolution naming the absence of the field as the way to say it, because two spellings of one
reading is the defect that let a number be claimed twice.

A refused protocol or address SHALL widen the claim rather than narrow it: the claim SHALL then be
compared as though the field had not been stated, so a deployment carrying one of these rows is
never checked less than a deployment carrying none.

#### Scenario: A protocol outside the domain

- **WHEN** a module claims a port with a protocol the domain does not admit
- **THEN** the planner SHALL emit an error row naming the claim, the value and every value the
  domain admits

#### Scenario: A refused protocol collides with every protocol

- **WHEN** one entry claims a number with a protocol outside the domain and a second entry on the
  same machine claims the same number with a protocol inside it
- **THEN** the planner SHALL emit the claimed-twice error beside the protocol row

#### Scenario: An address spelled as the wildcard

- **WHEN** a module states an address whose text means every address of the machine
- **THEN** the planner SHALL emit an error row whose resolution names omitting the field
- **AND** the number SHALL still be recorded

#### Scenario: An address outside the address grammar

- **WHEN** a module states an address that is not a string, or is a string the grammar refuses
- **THEN** the planner SHALL emit an error row naming the claim and the grammar
- **AND** the claim SHALL be compared as though it bound every address of the machine

## MODIFIED Requirements

### Requirement: A host resource two entries of one machine both claim is a row

The planner SHALL report a row when two entries placed on one machine both claim one host resource.
Three claims SHALL be read, and each SHALL be read from what the plan already records or from what
the declaration states, so that no plan field is introduced by this rule:

- a host path a configuration file is written to, which SHALL be an error;
- a port claimed on a protocol and an address that another entry's claim overlaps, which SHALL be an
  error;
- a unit directory name a unit extension application records under `runtimeDirectory`,
  `stateDirectory` or `cacheDirectory`, which SHALL be a warning.

An error SHALL block an apply, because two entries writing one file is two renderings of one file and
two entries claiming one port is a daemon that cannot bind. The directory claim SHALL be a warning,
because two entries sharing one state directory is a handoff a deployment may intend while two
entries sharing one runtime directory loses one of their records at the next restart: the row SHALL
name it and the deployment SHALL still build.

Two port claims of one machine SHALL collide when they claim one number and both their protocols and
their addresses overlap. Two protocols SHALL overlap when they are the same protocol or when either
claim states none. Two addresses SHALL overlap when they are the same address or when either claim
states none, the absence being every address of the machine. Two claims of one number that bind two
different addresses SHALL NOT collide, because two listeners on two addresses of one machine is a
deployment that runs.

Because overlap is not equality, one claim MAY take part in more than one collision, and each
collision SHALL be one row naming its own claimants, its own protocol and its own address. Claims
that state one protocol and one address SHALL be one collision however many claimants they have, so
that a number claimed by three entries is one row and not three.

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

- **WHEN** two entries placed on one machine each claim the same port number with the same protocol
- **THEN** the planner SHALL emit an error row naming both entries, the machine, the protocol and the
  port

#### Scenario: One claim states a protocol and the other states none

- **WHEN** two entries placed on one machine claim one number and only one of them states a protocol
- **THEN** the planner SHALL emit the error row for that number
- **AND** two entries stating two different protocols of the domain on that number SHALL produce no
  row

#### Scenario: Two claims of one number bind two addresses

- **WHEN** two entries placed on one machine claim one number and one protocol and each states a
  different address
- **THEN** the planner SHALL emit no collision row
- **AND** the deployment SHALL be applicable

#### Scenario: A wildcard claim and a specific claim of one number

- **WHEN** two entries placed on one machine claim one number and one protocol and only one of them
  states an address
- **THEN** the planner SHALL emit an error row naming both entries, the number and the address the
  contention is on

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

- **WHEN** three entries placed on one machine all claim one number on one protocol and one address
- **THEN** the table SHALL carry one row for that port
- **AND** the row SHALL name all three plan keys and be subjected to the first of them in the plan's
  order
