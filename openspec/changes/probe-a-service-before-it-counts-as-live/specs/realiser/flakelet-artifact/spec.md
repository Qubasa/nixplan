<!--
A delta against `realiser/flakelet-artifact`, whose current text is
`openspec/specs/realiser/flakelet-artifact/spec.md`. Everything here is ADDED.

`Enablement is the backend's decision, not the plan's` is unchanged and not restated: the derived
probe unit is the third case of that rule and the requirement below states it as such rather than
recopying the block. `A name the endpoint cannot accept is refused before bytes exist` is unchanged
too, and is the precedent for the last paragraph of the first requirement: a derived name is held to
the endpoint's rule and the deployment build reports the same condition as a row, which is why this
delta states the row's obligation here rather than opening a delta on a capability another change
owns.

The conditions. flakelet starts exactly one file after switching, `<name>-health.service`, and then
requires that no unit of the entry is `failed`; either failure deletes the new generation, switches
back to the previous one, records a hold keyed on the artifact and exits non-zero
(`docs/design.md` "Health checks are units" and update-flow steps 5 and 6,
`docs/reference/service-module.md` "Activation semantics" and "Sugar units",
`docs/reference/cli.md` "Exit status", all at the locked revision). Upstream's own sugar gives the
probe the main unit's `User`, `Group`, `DynamicUser` and `StateDirectory`, and `Type=oneshot` with
`TimeoutStartSec=1min`, because a probe that talks to a `0660` socket or runs a read-only self-test
is the common case.

nixplan renders no `<name>.service`: every unit file is `${name}-${unit}.service`
(`image/read.nix:243`), so `<name>-health.service` collides with no file the vocabulary can spell
except a declared unit literally named `health`, and it is the only name the endpoint's step 5
starts. `flakelet/read.nix:72-75` accepts it, `image/read.nix:268-269` accepts it, and
`operator/read.nix:121` and `:257` read the names off one derivation (`image/read.nix:250-253`) so
the per-machine index at `operator/read.nix:469-508` sees it by existing.

`flakelet/read.nix:99-102` and `:129-134` are where the install section is added, per unit and per
timer; the probe goes through neither wrapper, because an install section is the one thing both
realisers agree the probe must not carry and a file rendered in one place cannot disagree with
itself. `image/read.nix:818-820` renders the entry's host-path binds identically on every unit,
which is what a probe inside the same namespace needs to reach a delivered value.
`cli/manifest.py:288` reads the artifact's unit files, and `cli/remote.py:421-427` runs
`flakelet activate` as one step, so a rolled-back deploy is already the command's own failure and
this change asks nothing of `cli/`.
-->

## ADDED Requirements

### Requirement: An artifact carries the probe unit the endpoint starts

Where a unit of the entry records a probe, the artifact SHALL carry one unit file beyond the ones its
units already render, and its name SHALL be the artifact's own service name followed by `-health` and
the service suffix. The name SHALL be derived rather than declared, and SHALL be derived by the same
function that derives every other unit file name of the entry, so that the endpoint's unit rule, the
builder's refusal and the deployment build's per-machine namespace index all read one derivation.

The derived unit SHALL be a job that runs once and exits, ordered after and requiring the unit it
probes, so that starting it on a machine where that unit is not active fails rather than reports
success. It SHALL carry the probe's command as its start command and the probe's bound as its start
timeout, and it SHALL carry the account the probed unit declared, because a probe that reads what the
service reads is the case the field exists for.

The derived unit SHALL carry no install section. The endpoint starts it by name after switching, and
an install section would additionally queue it at every boot, which is the reason a scheduled unit's
service carries none either.

The derived unit SHALL declare no directory of any kind and SHALL claim no host resource. A runtime
directory declared on a job that exits is deleted when it exits, which would take the probed unit's
own directory with it; a directory a static account may read needs no declaration to be read. The
derived unit SHALL therefore add no claimant to the shared-directory index, and whether the probe may
open the entry's files SHALL be the question already answered for the probed unit's account.

The derived name SHALL be held to the endpoint's unit rule, and SHALL take part in the unit-file
namespace of the machine the entry is placed on. An entry one of whose declared units already spells
the derived file SHALL be an error row of the deployment build naming the entry, the declared unit
and the file: two things deriving one name is the condition that namespace already owns, and the
same-entry case earns its own sentence because the existing row's sentence is about two entries. Two
entries on one machine deriving one probe file SHALL remain the condition the existing index
reports.

#### Scenario: A probed entry carries one more unit file

- **WHEN** an artifact is built for an entry one of whose units records a probe
- **THEN** the artifact SHALL carry the probed unit's own file and one derived probe unit file
- **AND** the derived file's name SHALL be the service name followed by `-health` and the service
  suffix
- **AND** an entry recording no probe SHALL carry no such file

#### Scenario: The derived probe unit is ordered against the unit it probes

- **WHEN** the derived probe unit of an entry is rendered
- **THEN** it SHALL be a job that runs once
- **AND** it SHALL be ordered after and require the unit whose probe it was derived from
- **AND** its start timeout SHALL be the bound the plan records and nothing else

#### Scenario: The derived probe unit takes the probed unit's account

- **WHEN** the probed unit declares an account
- **THEN** the derived probe unit SHALL run as that account
- **AND** where the probed unit declares none, the derived unit SHALL declare none either

#### Scenario: The derived probe unit carries no install section

- **WHEN** the derived probe unit is rendered
- **THEN** it SHALL carry no install section
- **AND** the endpoint SHALL be the only thing that starts it

#### Scenario: The derived probe unit claims no directory

- **WHEN** the probed unit declares a runtime directory, a state directory and a cache directory
- **THEN** the derived probe unit SHALL declare none of them
- **AND** the entry SHALL earn no row about two units sharing a directory

#### Scenario: A declared unit spelling the derived probe file

- **WHEN** an entry declares a probe and also declares a unit whose own file name is the derived
  probe file
- **THEN** the deployment build SHALL report an error row naming the entry, that unit and the file
- **AND** renaming either SHALL remove the row

#### Scenario: The derived name is one the endpoint accepts

- **WHEN** the derived probe file name of any entry the endpoint's service-name rule admits is asked
  of the endpoint's unit rule
- **THEN** the rule SHALL accept it
- **AND** no artifact SHALL be built carrying a unit file the rule refuses

### Requirement: A probe that fails takes the activation with it

A probe exists to make a failed activation fail, so this SHALL be proved against the real endpoint
and the real service manager rather than a double. An artifact whose probe command fails SHALL leave
the endpoint running the generation it was running before, and the applying command SHALL report the
entry as failed, with the machine's own words, and exit non-zero. An artifact whose probe command
succeeds SHALL leave the new generation active.

The realiser SHALL add no rollback of its own. Deleting the new generation, switching back and
recording the hold are the endpoint's, and the command reports what the endpoint printed.

#### Scenario: A failing probe leaves the previous generation running

- **WHEN** an artifact whose probe command fails is activated on a machine already running a
  previous generation of that entry
- **THEN** the endpoint SHALL report the previous generation as active
- **AND** the units running SHALL be the previous generation's

#### Scenario: A failing probe is a failed apply

- **WHEN** the same activation is performed by the operator's command
- **THEN** the command SHALL report the entry, the machine and what the machine printed
- **AND** the run SHALL exit non-zero
- **AND** the report SHALL carry no traceback and no argument vector

#### Scenario: A passing probe activates the new generation

- **WHEN** an artifact whose probe command succeeds is activated
- **THEN** the endpoint SHALL report the new generation as active
- **AND** the probe unit SHALL have run

### Requirement: A probe is part of the artifact's identity and of what a report compares

A probe is a unit field, so adding one, changing its command or changing its bound SHALL move the
entry's key and the artifact's content-derived version, and the endpoint SHALL therefore activate the
changed artifact as a new generation rather than report that there is nothing to do.

The derived probe unit SHALL be among the unit files the artifact publishes, so that an endpoint
comparing the unit files of the active generation against the artifact's own compares it with the
rest. A machine running a generation built before the probe existed SHALL therefore read as not
running this build's units.

#### Scenario: A changed probe moves the artifact's identity

- **WHEN** a unit's probe command changes and nothing else does
- **THEN** that entry's key SHALL change
- **AND** the artifact's recorded version SHALL differ
- **AND** no other entry's artifact SHALL differ

#### Scenario: A probe is published among the artifact's unit files

- **WHEN** an artifact of a probed entry is asked for the unit files it carries
- **THEN** the derived probe unit SHALL be one of them
