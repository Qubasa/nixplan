<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`, `report-every-refusal-as-a-row`,
`open-a-delivered-value-to-its-reader`, `normalise-folds-and-report-refused-reads`,
`hold-every-stated-guarantee`, `deliver-a-secret-without-exposing-it`, `deliver-secrets-across-machines`,
`cut-a-member-and-wire-its-place`, `hold-declaration-shape-and-fold-set-reads` and
`refuse-two-entries-claiming-one-host-resource`. `openspec/specs/` is empty in this repository, so the
base text is read from those changes.

The requirement below is ADDED and widens no row: `refuse-two-entries-claiming-one-host-resource`
states what two entries of one machine claiming one resource earn, and this states that the machine's
own record is a third kind of claimant of the same resources, earning the same rows. Everything the
base capability says about a row's shape, its ordering, its deduplication and the totality of
evaluation is unchanged and applies to these rows unchanged. What is new is that a claimant may be a
machine rather than an entry, which is why the requirement states how the row names it and what its
subject is.
-->

## ADDED Requirements

### Requirement: A resource a machine reserves and an entry claims earns that resource's own row

A host resource a machine states that it already holds and a placed entry on that machine claims
SHALL earn the row that resource's kind already has, with no identifier of its own: the reservation
is a claimant like any other, and a reader learns which claimants collided from the row's text rather
than from two families of identifier. A reserved port a placed entry claims with the same protocol
SHALL therefore be the same error as two entries claiming it, and a reserved host path a placed
entry's configuration file is written to SHALL be the same error as two entries writing it.

The machine SHALL be named in the row by the key its own plan record carries, which is distinct from
every entry key by construction and is a valid row subject. The machine's key SHALL be ordered with
the entry keys by the one rule the collision row already follows - a row is reported once for one
collision and is subjected to the first of the colliding plan keys in the plan's order - so the
machine is the subject exactly when it sorts first, and is a named claimant of the row either way. A
row SHALL only ever name a machine whose record the plan carries, so that its subject addresses
something a reader can find in the plan.

The row's resolution SHALL name both declarations a reader can edit: the claim the entry declares and
the reservation the registry declares. Where the claimants are two entries and no reservation, the
resolution SHALL be the one that requirement already states.

A reservation SHALL earn no row on its own. A reserved resource no placed entry claims is a
statement the deployment agrees with, and a reservation on a machine no placement selects is a
statement about a machine that runs nothing: both SHALL leave the table as it was. The planner SHALL
NOT check a reservation against the machine, so a reserved path that does not exist and a reserved
port nothing listens on are not rows either.

A reservation SHALL collide only where it can be compared. A port SHALL compare by its protocol and
its number together, so a reserved port and a claim of the same number on another protocol are two
resources and no row, which is the rule the entry-to-entry comparison already makes. A reservation
SHALL NOT be compared against a unit directory name a unit extension records, that name being in the
service manager's own namespace rather than a host path the plan states.

#### Scenario: A machine reserves a port an entry claims

- **WHEN** a machine states that it already holds a port with a protocol and an entry placed on that
  machine claims the same port with the same protocol
- **THEN** the planner SHALL emit the error row a port claimed twice earns, naming the machine, the
  entry, the protocol and the port
- **AND** the row SHALL appear once in the table
- **AND** its resolution SHALL name the entry's claim and the machine's reservation

#### Scenario: A machine reserves a port nothing claims

- **WHEN** a machine states that it already holds a port and no entry placed on it claims that port
- **THEN** the planner SHALL emit no collision row
- **AND** the deployment SHALL be applicable

#### Scenario: A machine reserves a path an entry writes

- **WHEN** a machine states that it already holds a host path and an entry placed on that machine
  declares a configuration file at that path
- **THEN** the planner SHALL emit the error row a host path claimed twice earns, naming the machine,
  the entry and the path

#### Scenario: A reservation on a machine no placement selects

- **WHEN** a machine states that it already holds a port and a path, and no placement selects that
  machine
- **THEN** the planner SHALL emit no collision row about it
- **AND** no row of the table SHALL be subjected to that machine

#### Scenario: A reserved port and a claim on another protocol

- **WHEN** a machine states that it already holds a port on one protocol and an entry placed on it
  claims the same number on another protocol
- **THEN** the planner SHALL emit no collision row, the two being two resources

#### Scenario: A machine and two entries claim one port

- **WHEN** a machine states that it already holds a port and two entries placed on it both claim it
  with that protocol
- **THEN** the table SHALL carry one row for that port
- **AND** the row SHALL name the machine and both entries
- **AND** its subject SHALL be the first of those three plan keys in the plan's order
