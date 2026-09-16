<!--
A delta against `operator/apply-command`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change and was last restated by `make-an-apply-observable`.
The MODIFIED requirement below is that change's `One command applies a whole deployment`, copied whole
and edited: its wording already says the edges come from "the reads the plan resolved", and
`cli/order.py:131` reads only `slot["entry"]` while `lib/plan.nix:227` records a `reach = "all"` read
as `entries`, so an implementation that misses every set-valued read reads as satisfying it. The
reach-independence sentence and the set-read scenario close that. The rollback path is the same
requirement's announcement rule, which `cli/report.py:183-190` does not hold.
-->

## Purpose

Defines applying a built deployment to real machines as one command whose order comes from the plan,
whose every step is announced before it is attempted, and whose every refusal that needs no machine
is made before a machine is dialled.

## MODIFIED Requirements

### Requirement: One command applies a whole deployment

Applying a deployment SHALL be one command over a built deployment. It SHALL derive the order of its
steps from the plan and SHALL NOT require the caller to state it: an artifact SHALL be on its
machine before it is activated there, every generated value a machine receives SHALL be written
before any unit that may read it is activated, and an entry that provides a capability SHALL be
activated before an entry that reads it.

The provider-before-consumer edges SHALL be taken from the reads the plan resolved, not from the key
provenance the plan records for other purposes. Every read the plan resolved SHALL contribute its
edges whatever its reach: a read of one entry and a read of a set of entries SHALL each be ordered
against, and a consumer of a set-valued read SHALL be activated after every entry in that set. No
shape a resolved read is recorded in SHALL leave a provider unordered.

Where the edges form a cycle - which two instances wiring each other legitimately do - the command
SHALL break it deterministically and SHALL report the edge it broke, rather than refusing a
deployment the planner accepted. An edge the command reports as contradicted SHALL lie on a cycle:
the provider of that edge SHALL be reachable from its consumer through the reads of the entries the
run has still to apply. An edge on no cycle SHALL be satisfied by the order the command walks.

Each step SHALL be announced before it is attempted, so that the last step line a run printed names
the step that was running when the run ended. This SHALL hold for every step the command takes
against a machine, whichever subcommand takes it.

#### Scenario: An entry is copied before it is activated

- **WHEN** the command applies one entry
- **THEN** the copy of its artifact to its machine SHALL precede the activation on that machine
- **AND** the address dialled SHALL be the one the plan records for that machine

#### Scenario: A provider is applied before its consumer

- **WHEN** one entry reads a capability another provides
- **THEN** the provider SHALL be activated before the consumer
- **AND** the order SHALL come from the plan rather than from the order the caller named the entries
  in

#### Scenario: An entry reading a set of providers follows all of them

- **WHEN** one entry reads a capability with a reach of every entry that provides it
- **THEN** every entry in that set SHALL be activated before the entry that reads it
- **AND** the edges SHALL be taken from the same resolved read whatever shape the plan records it in
- **AND** an entry the run does not apply SHALL contribute no edge

#### Scenario: Two entries each read the other's capability

- **WHEN** two entries each read a capability the other provides
- **THEN** the command SHALL apply both
- **AND** SHALL report which edge it ordered against
- **AND** SHALL NOT refuse the deployment

#### Scenario: A mutual pair is reported however each side reads the other

- **WHEN** two entries read each other and one of the two reads the other as a set of providers
- **THEN** the command SHALL report the edge it ordered against
- **AND** SHALL NOT present the pair as an order it satisfied

#### Scenario: An entry off the cycle keeps its order

- **WHEN** one entry reads a capability provided by one of two entries that read each other
- **THEN** the command SHALL activate the mutual pair before the entry that reads into it
- **AND** the only edge it reports as contradicted SHALL be one between the two entries of the pair
- **AND** the read the third entry declared SHALL be satisfied by the order walked

#### Scenario: A step is announced before it is attempted

- **WHEN** the command takes a step against a machine
- **THEN** the line naming that step SHALL be printed before the step is attempted
- **AND** a run that ends during a step SHALL have that step's line as the last step it named

#### Scenario: A step the machine refuses is named by the run that took it

- **WHEN** a step fails on the machine, on any subcommand that takes a step
- **THEN** the line naming that step SHALL already have been printed
- **AND** the failure SHALL name the machine and the step rather than the call that raised

## ADDED Requirements

### Requirement: Every refusal a run can make without a machine precedes the first machine

A refusal the command can make from the build and its own arguments alone SHALL be made before the
first machine is dialled, so that a deployment the command will not finish changes nothing. This
SHALL cover every artifact the run will need on any machine, not only the ones the first machine
needs: a record the command cannot read, an artifact the build does not name, and a file inside the
build that is malformed SHALL each be refused before the run mutates a machine.

A malformed file inside a built directory SHALL be a refusal naming the file, never an unhandled
error from the reader.

#### Scenario: An artifact the run needs later is missing

- **WHEN** a run will need an artifact for an entry on a machine after the first
- **AND** the build does not name that artifact
- **THEN** the command SHALL refuse before it dials the first machine
- **AND** no value SHALL have been written and no artifact copied

#### Scenario: A file inside the build is malformed

- **WHEN** a file the command reads from a built directory is not the shape the command needs
- **THEN** the command SHALL refuse naming that file
- **AND** the refusal SHALL be the command's own, not the reader's error
