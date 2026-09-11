<!--
A delta against `operator/apply-command`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`open-the-repository-to-a-consumer`, `hold-every-stated-guarantee`,
`order-a-cycle-by-its-strong-components` and `deliver-a-secret-without-exposing-it`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The order the command walks, the refusals it makes before the first
dial, the step-per-line report and the rule that values are written before any entry is activated are
all unchanged. What this delta adds is what the command does when the thing it is applying is already
partly there.

The conditions: `cli/apply.py:154-190` and `:308-312` skip an image entry the machine already holds
attached, and the attach script is the only step that assembles configuration bytes
(`image/default.nix:229-246`); `cli/apply.py:295-310` writes a value and then activates an unchanged
artifact, which the endpoint answers with a no-op.
-->

## ADDED Requirements

### Requirement: No entry is skipped for being already present

The command SHALL activate every entry of the selection it was given, and SHALL NOT skip one because
the machine already holds it. Whether an entry's activation is a change SHALL be the activation's own
answer, reported by the step, rather than a question the command decides before running it.

An activation SHALL therefore be idempotent: applying an unchanged deployment twice SHALL leave the
machine as it was after the first apply, and the second run's report SHALL say that nothing changed
rather than that nothing was attempted.

#### Scenario: An unchanged deployment applied twice

- **WHEN** a deployment is applied twice with nothing changed between the runs
- **THEN** both runs SHALL report an activation step for every entry
- **AND** the machine SHALL hold the same units, the same images and the same configuration bytes
  after the second run
- **AND** no unit's main process SHALL have been replaced by the second run

#### Scenario: An entry whose configuration bytes changed

- **WHEN** a deployment is applied, one entry's configuration file is edited, and the deployment is
  built and applied again
- **THEN** the machine SHALL hold the new bytes at the declared path
- **AND** the step SHALL report that the file changed

#### Scenario: An entry whose artifact identity changed

- **WHEN** a deployment is applied, an entry's artifact identity moves, and the deployment is applied
  again
- **THEN** the machine SHALL run the new artifact
- **AND** SHALL NOT hold the previous one
- **AND** the step SHALL report the replacement

### Requirement: A value write says whether the bytes moved

The step that writes a value SHALL report whether the bytes on the machine changed, and SHALL make
that comparison on the machine rather than from a record of what a previous run wrote: the command
holds no state between runs, and the only authority on what a machine holds is the machine.

The comparison SHALL NOT put the value's bytes anywhere a second process can read them, and SHALL NOT
print them: what is reported is that the file changed, never what it changed to.

#### Scenario: A value whose bytes are unchanged

- **WHEN** a value is written whose bytes on the machine are already those bytes
- **THEN** the step SHALL report that the value was unchanged
- **AND** the file's ownership and mode SHALL still be set

#### Scenario: A value whose bytes moved

- **WHEN** a value is written whose bytes on the machine differ
- **THEN** the step SHALL report that the value changed
- **AND** no report line SHALL contain the value's bytes

### Requirement: A changed value restarts the entries that read it

After every value has been written and before the run ends, the command SHALL restart the units of
every entry that declared a read of a value whose bytes moved, on the machine that entry is placed
on. A unit that is not running SHALL NOT be started by this step: the activation is what decides
whether a unit runs, and this step only replaces a process holding bytes that are no longer current.

The entries restarted SHALL be derived from the reads the plan resolved, the same source the
activation order is derived from. A value whose bytes did not move SHALL cause no restart, and a run
that wrote no value SHALL contain no such step.

Each restart SHALL be its own reported step naming the entry, the machine and the value that caused
it, so that an operator reading the log can tell a restart caused by a rotation from one caused by a
new artifact.

#### Scenario: A rotated secret restarts its reader

- **WHEN** a value's bytes are changed in the value source and the deployment is applied
- **THEN** the units of every entry that declared a read of that value SHALL be restarted
- **AND** each restart SHALL be reported naming the entry, the machine and the value
- **AND** the reading process SHALL be a new process afterwards

#### Scenario: A reader that is not running is not started

- **WHEN** a value's bytes change and one reading entry's unit is stopped on its machine
- **THEN** that unit SHALL NOT be started by the restart step
- **AND** the run SHALL still report the restart step for the entries whose units were running

#### Scenario: An unchanged value restarts nothing

- **WHEN** a deployment is applied twice with unchanged values
- **THEN** the second run SHALL contain no restart step
- **AND** no reading process SHALL have been replaced

#### Scenario: A value read by two entries on two machines

- **WHEN** a value delivered to two machines changes and an entry on each declared a read of it
- **THEN** both entries' units SHALL be restarted
- **AND** each restart SHALL name its own machine
