<!--
A delta against `operator/apply-command`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change and is implemented by `cli/`. That change owns
the order the command applies a deployment in, what it refuses before it dials, and what it does on
a machine it reaches. `make-an-apply-observable` also modifies this capability, for what a run
reports and how it resumes; this delta touches none of the requirements that change restates.

One requirement is restated, "The bytes of a generated value come from outside the plan", because
the sentence about writing a file "readable only by the user the units run as" is what
`cli/remote.py:140-145` turned into the constants `0400` and the login user, and because the channel
the bytes travel on was never stated at all. Two requirements are added: what a failure on a machine
may print, and what the command checks about the operator's own store of bytes before it reads it.

`operator/machine-identity` in this same change owns who the machine at the other end is and which
options the connection uses; a requirement here that says "the machine" means the machine that
capability's verification identified.
-->

## Purpose

Defines how the bytes of a generated value get from an operator's own store to a path on a machine
without becoming readable by anybody else on the way: the channel they travel on, the mode and owner
they land with, the posture the source is held to, and what a failed step may print.

## ADDED Requirements

### Requirement: A failure on a machine is reported without the arguments that produced it

A step the command runs on a machine SHALL be reported by what it was. A failure SHALL name the
step, the entry or value it belongs to, the machine, the exit status, and the output the machine
itself produced. No refusal, no unhandled failure, and no log line SHALL carry the argument vector
of a step or the bytes of a value, whatever the step was and however it failed.

A non-zero exit from a remote step SHALL be reported as a refusal of the command rather than
escaping as an unhandled failure of the process that ran it.

#### Scenario: A write fails on a read-only path

- **WHEN** a machine refuses the write of a delivered file, because the directory is read-only or
  the login user may not create it
- **THEN** the command SHALL report the value entry, the file, the machine, and what the machine
  said
- **AND** the report SHALL carry no byte of the value and no argument vector
- **AND** the exit status SHALL be the command's own refusal status rather than a traceback

#### Scenario: A machine refuses the login

- **WHEN** the connection to a machine fails before any step runs on it
- **THEN** the command SHALL report the machine, the step it was about to take, and the failure
- **AND** SHALL NOT report the options or the arguments it would have used

### Requirement: The operator's own store of a secret is checked before it is read

The command SHALL hold the value source to the posture the bytes in it require, and SHALL do so
before it reads any of them and before it dials a machine. For each file a value entry declares
`secret`, the source SHALL hold it as a regular file that the invoking user owns, whose mode grants
nothing to group or other, under directories from the source root down that satisfy the same. A file
a value entry declares public SHALL be held to none of that, because the plan already carries it.

A path in the source that leaves the source SHALL be refused rather than followed. Every refusal
SHALL name the entry, the file, and what about it was refused, and SHALL NOT print the bytes.

#### Scenario: A value source another user can read

- **WHEN** the command is given a value source whose directory grants read access to group or other
  and which holds a file of a secret value
- **THEN** it SHALL refuse naming the directory and its mode
- **AND** no machine SHALL have been dialled

#### Scenario: A secret file in the source is group-readable

- **WHEN** a file of a value entry that declares it secret is readable by group or other
- **THEN** the command SHALL refuse naming the value entry and the file
- **AND** a file of a public value with the same mode SHALL be accepted

#### Scenario: A link leaves the value source

- **WHEN** the source holds a link whose target is outside the source
- **THEN** the command SHALL refuse naming the link
- **AND** SHALL NOT read the target

## MODIFIED Requirements

### Requirement: The bytes of a generated value come from outside the plan

The command SHALL take the bytes of a generated value from a source the operator names, never from
the plan or an artifact. For each value entry it SHALL write each declared file to every machine the
entry's delivery set names, at the path the entry records, outside the store, at the mode and the
owner the entry's own record for that file states. A value whose delivery set is empty SHALL be
written nowhere.

The bytes SHALL reach a machine as the input of the remote command that writes them, and SHALL NOT
appear in the argument vector of any process on either host. The argument vector of a write SHALL be
a function of the plan alone: the path, the mode, and the owner it names are recorded facts, so two
runs delivering two different values SHALL run the same arguments.

The mode and the owner SHALL be the entry's, never the command's: the command SHALL NOT substitute a
constant for either, and SHALL NOT fall back to the user it logged in as.

The source SHALL be checked against the plan before anything is dialled: a file the plan names that
the source does not hold, and a file the source holds that the plan does not name, SHALL both be
refusals naming the entry and the file.

#### Scenario: A value the plan names has no bytes in the source

- **WHEN** the command is given a value source missing a file the plan declares
- **THEN** it SHALL refuse naming the value entry and the file
- **AND** no machine SHALL have been dialled

#### Scenario: A value source carries bytes the plan does not name

- **WHEN** the value source holds a file no value entry of the plan declares
- **THEN** the command SHALL refuse naming the file
- **AND** SHALL NOT write it to any machine

#### Scenario: A secret is applied from the operator's value source

- **WHEN** a deployment whose consumer reads a secret export is applied with a value source holding
  that secret
- **THEN** the file SHALL be present on each machine of the delivery set and on no other machine
- **AND** the consuming unit SHALL authenticate to the provider with it
- **AND** the bytes SHALL appear in no artifact the command built

#### Scenario: The bytes of a value never enter an argument vector

- **WHEN** the command writes a delivered file to a machine
- **THEN** the arguments of the local process and the arguments of the remote command SHALL both be
  derivable from the plan without the bytes
- **AND** replacing the bytes with different bytes of the same length SHALL leave both argument
  vectors identical

#### Scenario: A delivered file carries the mode the plan states

- **WHEN** a value entry records a file with a mode and an owner
- **THEN** the file on each machine of the delivery set SHALL carry that mode and that owner
- **AND** a second value entry recording a different mode SHALL land with its own
