<!--
A delta against `operator/apply-command`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`open-the-repository-to-a-consumer`, `hold-every-stated-guarantee`,
`order-a-cycle-by-its-strong-components` and `deliver-a-secret-without-exposing-it`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Every requirement below is ADDED. That values are written before any entry is activated, that every
refusal is made before the first dial, and that a machine's refusal is the command's own error are
unchanged.

The condition: `cli/remote.py:282-284` is one script with a literal `chmod 0400`, so the mode a
deployment states reaches no machine.
-->

## ADDED Requirements

### Requirement: A value is written at the ownership and mode its record states

The step that writes a value on a machine SHALL set the owner, the group and the mode the value's
record states, and SHALL take all three from the record rather than from a literal of its own.

The file SHALL never exist at a mode or an ownership wider than the recorded one, not even for the
length of the write: the write SHALL create the file at the recorded mode before its first byte
lands, and SHALL NOT depend on the environment's umask for its answer. A write that is interrupted
SHALL leave either the previous file or no file, never a readable fragment at a wider mode.

Where the recorded owner or group does not exist on the machine, the step SHALL fail as the command's
own refusal naming the value, the machine and the account, rather than leaving the file owned by the
writing login.

#### Scenario: A value delivered to an account

- **WHEN** a value's record names an owner, a group and a mode
- **THEN** the machine SHALL hold the file with that owner, that group and that mode
- **AND** the step SHALL have set all three

#### Scenario: A value delivered with the defaults

- **WHEN** a value's record carries the default ownership and mode
- **THEN** the machine SHALL hold the file exactly as the command delivered it before this change

#### Scenario: An interrupted write

- **WHEN** the write of a value is interrupted after the file is created and before its bytes are
  complete
- **THEN** no file SHALL exist at a mode wider than the recorded one
- **AND** the machine SHALL hold either the previous file or none

#### Scenario: An account the machine does not have

- **WHEN** a value's record names an owner no account on the machine matches
- **THEN** the command SHALL refuse naming the value, the machine and the account
- **AND** the file SHALL NOT be left owned by the login the command used

### Requirement: A re-apply restores a value's ownership and mode

Every apply that delivers a value SHALL set its ownership and mode, whether or not the bytes moved.
A value edited on the machine - its mode widened, its owner changed - SHALL be returned to what the
record states by the next apply, so that what a machine holds is decided by the deployment and not by
whatever last touched the file.

The report SHALL name the write the way it names every other step, so an operator can see that the
value was written.

#### Scenario: A mode widened on the machine

- **WHEN** a value's mode is widened on a machine and the deployment is applied again with unchanged
  bytes
- **THEN** the file SHALL carry the recorded mode afterwards
- **AND** the step SHALL have been reported

#### Scenario: An owner changed on the machine

- **WHEN** a value's owner is changed on a machine and the deployment is applied again
- **THEN** the file SHALL carry the recorded owner afterwards
