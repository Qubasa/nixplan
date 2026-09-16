<!--
A delta against `operator/apply-command`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change and is implemented by `cli/`. That change owns
the command: the order, the refusals, and what an operator types.
`open-the-repository-to-a-consumer` restates one requirement of it, "The command refuses before it
dials", for a dry run, and `deliver-a-secret-without-exposing-it` restates another, "The bytes of a
generated value come from outside the plan", for the channel the bytes travel on and the mode they
land at; this delta restates neither, and refines the second from a requirement of its own.
`operator/machine-report` in this same change owns what asking a machine answers, so the status
scenario restated here states that the command can ask and nothing about what the answer
distinguishes. `operator/deployment-build` owns what a build publishes, including the version and
store this delta has the command refuse on.

Two requirements are restated whole, as they read after this change; five are added.
-->

## Purpose

Defines the one command that puts a built deployment on the machines it names, so that the steps
between a plan and a running service are a program with a contract rather than a script each caller
writes. It owns the order the steps happen in, where the bytes of a generated value come from, what
is refused before a machine is dialled, and what the command does on a machine it reaches. This
delta adds what an operator needs while it runs and after it breaks: a step named before it is
attempted, a failure that names itself, a restriction that reaches only the machines it names, and a
second run that finishes the first.

## MODIFIED Requirements

### Requirement: One command applies a whole deployment

Applying a deployment SHALL be one command over a built deployment. It SHALL derive the order of its
steps from the plan and SHALL NOT require the caller to state it: an artifact SHALL be on its
machine before it is activated there, every generated value a machine receives SHALL be written
before any unit that may read it is activated, and an entry that provides a capability SHALL be
activated before an entry that reads it.

The provider-before-consumer edges SHALL be taken from the reads the plan resolved, not from the key
provenance the plan records for other purposes. Where the edges form a cycle - which two instances
wiring each other legitimately do - the command SHALL break it deterministically and SHALL report
the edge it broke, rather than refusing a deployment the planner accepted. An edge the command
reports as contradicted SHALL lie on a cycle: the provider of that edge SHALL be reachable from its
consumer through the reads of the entries the run has still to apply. An edge on no cycle SHALL be
satisfied by the order the command walks.

Each step SHALL be announced before it is attempted, so that the last step line a run printed names
the step that was running when the run ended.

#### Scenario: An entry is copied before it is activated

- **WHEN** the command applies one entry
- **THEN** the copy of its artifact to its machine SHALL precede the activation on that machine
- **AND** the address dialled SHALL be the one the plan records for that machine

#### Scenario: A provider is applied before its consumer

- **WHEN** one entry reads a capability another provides
- **THEN** the provider SHALL be activated before the consumer
- **AND** the order SHALL come from the plan rather than from the order the caller named the entries
  in

#### Scenario: Two entries each read the other's capability

- **WHEN** two entries each read a capability the other provides
- **THEN** the command SHALL apply both
- **AND** SHALL report which edge it ordered against
- **AND** SHALL NOT refuse the deployment

#### Scenario: An entry off the cycle keeps its order

- **WHEN** one entry reads a capability provided by one of two entries that read each other
- **THEN** the command SHALL activate the mutual pair before the entry that reads into it
- **AND** the only edge it reports as contradicted SHALL be one between the two entries of the pair
- **AND** the read the third entry declared SHALL be satisfied by the order walked

#### Scenario: A step is announced before it is attempted

- **WHEN** the command takes a step against a machine
- **THEN** the line naming that step SHALL be printed before the step is attempted
- **AND** a run that ends during a step SHALL have that step's line as the last step it named

### Requirement: What the command does on a machine

On a machine the command SHALL use what is already there: the machine's own service manager, the
endpoint's own binary for an artifact the endpoint activates, and the artifact's own attach script
for a portable-service image. It SHALL report what each machine reported. It SHALL be able to ask a
machine what it holds and to return one entry to its previous generation.

A step that the machine refuses SHALL be reported as the command's own refusal, naming the entry,
the machine and what the machine printed, and SHALL NOT reach the operator as an unhandled failure
of the program the command ran.

Reaching a machine SHALL bound silence and SHALL NOT bound work: the command SHALL ask no question
of a terminal nobody is watching, SHALL give up on a machine that does not answer a connection, and
SHALL place no limit on how long a step that keeps making progress may take. An option the caller
stated for the connection SHALL win over the command's own value for the same option.

#### Scenario: An image entry is attached by the command

- **WHEN** the command applies an entry realised as a portable-service image
- **THEN** the attachment SHALL be performed by the script the artifact carries
- **AND** every unit the attachment names SHALL be running on the machine afterwards

#### Scenario: The command rolls one entry back

- **WHEN** the command is asked to roll one entry back after a second generation was applied
- **THEN** the machine SHALL run the previous generation again
- **AND** the command SHALL report the generation it came from

#### Scenario: The command reports what a machine holds

- **WHEN** the command is asked for the status of an applied deployment
- **THEN** it SHALL report, per entry, what the machine's own endpoint reports for it
- **AND** an entry the machine does not hold SHALL be reported as absent rather than as an error

#### Scenario: A step that fails names the machine and what it said

- **WHEN** a machine refuses a step of a run
- **THEN** the command SHALL report a failure naming the entry, the machine and the machine's output
- **AND** the run SHALL exit non-zero
- **AND** no traceback of the program the command ran SHALL reach the operator

#### Scenario: An unreachable machine is refused without a prompt

- **WHEN** a step is taken against an address that answers nothing
- **THEN** the connection SHALL be given up on rather than waited on indefinitely
- **AND** the command SHALL ask nothing of a terminal
- **AND** a connection option the caller stated SHALL be the one used

## ADDED Requirements

### Requirement: A restriction bounds the machines a run contacts

A restriction on which entries a run applies SHALL bound which machines the run contacts. The
machines contacted SHALL be the machines of the entries selected, plus the delivery machines of a
value entry the restriction names directly, and no others - a machine that receives a value only
because some unselected entry reads it SHALL NOT be dialled.

#### Scenario: A restricted run contacts only the machines of the entries it applies

- **WHEN** a run is restricted to one entry of a deployment placed on two machines, and a value the
  entry's machine receives is delivered to both
- **THEN** the run SHALL contact the entry's own machine
- **AND** SHALL open no connection to the other machine

#### Scenario: A restriction that names a value entry reaches its delivery set

- **WHEN** a run is restricted to a value entry rather than a placed entry
- **THEN** every machine of that value's delivery set SHALL receive its files
- **AND** no entry SHALL be activated

### Requirement: The value source is measured where the deployment declares files

A file of the value source is a claim about a value only where it lies under the directory of a
value entry the deployment delivers. The refusal of a file the plan does not name, which "The bytes
of a generated value come from outside the plan" states, SHALL be measured over those directories
and SHALL NOT be measured over the rest of the source. Every file so found SHALL be named, not the
first of them.

#### Scenario: A file outside every value's own directory is left alone

- **WHEN** the value source holds a file that lies under no delivered value entry's directory
- **THEN** the command SHALL apply the deployment
- **AND** SHALL write that file to no machine

#### Scenario: Two undeclared files are both named

- **WHEN** a delivered value's directory holds two files the value does not declare
- **THEN** the refusal SHALL name both
- **AND** no machine SHALL have been dialled

### Requirement: The command refuses a deployment record it cannot read

A deployment record states the version of its own shape and the store its artifact paths live in.
The command SHALL read both and SHALL refuse a record whose version it does not implement, naming
the version read and the version it implements, and a record whose store is not the store it runs
against, naming both. A record carrying no table of entries SHALL be refused as a record it cannot
read, never read as a deployment that places nothing.

A target naming a path under the store directory that does not exist SHALL be refused as a build
that was collected, naming the path, rather than reported as a reference that does not build.

An entry whose machine declares no address SHALL NOT make a record unreadable: the reading SHALL
carry that absence, and the refusal SHALL stay at the point where the machine would be dialled.

#### Scenario: A record states a version the command does not implement

- **WHEN** the command is given a deployment record whose stated version is not the one it
  implements
- **THEN** it SHALL refuse naming both versions
- **AND** no machine SHALL have been dialled

#### Scenario: A record names a store the command does not run against

- **WHEN** the record states a store directory other than the one the command runs against
- **THEN** it SHALL refuse naming both store directories
- **AND** no artifact SHALL be copied

#### Scenario: A record carries no table of entries

- **WHEN** the record holds no table of placed entries under the name the shape gives it
- **THEN** the command SHALL refuse naming the record and the table
- **AND** SHALL NOT report a run that applied nothing as successful

#### Scenario: A target that was collected is named as collected

- **WHEN** the target names a path under the store directory that is no longer there
- **THEN** the command SHALL refuse naming that path as a build that was collected
- **AND** the refusal SHALL tell the operator to build the reference again

#### Scenario: A record carrying an entry with no address is read

- **WHEN** the record places an entry on a machine whose registry record declares no address
- **THEN** reading the record SHALL succeed
- **AND** the refusal SHALL come when that entry's machine would be dialled, naming the entry and
  the machine

### Requirement: A build reports the table the deployment holds

Reporting what a built deployment holds SHALL include the diagnostics the build wrote, rendered as
the planner renders them, beside the entries and the values. A deployment whose rows are warnings
SHALL be reported with those warnings and SHALL be reported as successful; a deployment whose rows
carry an error SHALL be reported with the rendered table and SHALL exit non-zero. The rows are the
ones the tree already carries, because "An inapplicable deployment is not built" in
`report-every-refusal-as-a-row` requires a build to publish its plan and its rows whether or not any
entry was realised, and what the command prints is that refusal rather than a second one of its own.

#### Scenario: A build of a deployment carrying warnings prints them

- **WHEN** a built deployment whose diagnostics hold warnings and no error is reported
- **THEN** every warning row SHALL appear in the output beside the entries and the values
- **AND** the report SHALL exit zero

#### Scenario: A build of a deployment carrying an error prints the table and refuses

- **WHEN** a built deployment whose diagnostics hold an error row is reported
- **THEN** the rendered table SHALL be the output
- **AND** the report SHALL exit non-zero

### Requirement: A run that broke is finished by a second run

A run SHALL stop at the first step a machine refuses and SHALL attempt no step after it, so that a
broken run leaves one boundary rather than a set of them. A second run over the same built
deployment and the same value source SHALL be the recovery: a step whose effect is already on its
machine SHALL be taken again with no effect on that machine, and the command SHALL NOT re-run an
attachment for an image the machine already holds attached at that path.

#### Scenario: The run stops at the step that broke

- **WHEN** a machine refuses a step of a run that has further entries to apply
- **THEN** no step after the failed one SHALL be attempted
- **AND** the steps taken before it SHALL be the ones the log named

#### Scenario: An image the machine already holds attached is not attached twice

- **WHEN** a run applies an image entry the machine already holds attached at the path the record
  names
- **THEN** the artifact's attach script SHALL NOT be run again
- **AND** the entry SHALL be reported as already attached
- **AND** the run SHALL continue with the entries after it
