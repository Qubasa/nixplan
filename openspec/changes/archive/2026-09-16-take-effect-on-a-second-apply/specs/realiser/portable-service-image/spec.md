<!--
A delta against `realiser/portable-service-image`, whose base text lives in the unarchived changes
`emit-systemd-portable-service-images`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `generate-values-with-nixos-secrets`, `declare-service-state`,
`deliver-a-secret-without-exposing-it` and `hold-every-stated-guarantee`. `openspec/specs/` is empty
in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The image's content, its version digest, the empty mount points,
the architecture guard, the refusal of a file recorded as not computed and the assembly's mode
guarantees are all unchanged, and the assembly guarantee is restated as a condition the new steps
must not weaken.

The conditions: `image/default.nix:229-246` assembles, attaches and starts unconditionally and in
that order, with no check for an image already attached and no detach of a previous one;
`image/read.nix:211` carries each configuration file's `reload` list and no step reads it.
-->

## ADDED Requirements

### Requirement: The artifact's script makes the machine match the artifact, or refuses

The script the artifact carries SHALL be the whole decision about what the machine holds of that
entry, and running it twice SHALL be indistinguishable from running it once. In order, it SHALL:
check its guards and its refusals; assemble every configuration file whose bytes it must assemble;
replace an image of the same entry that is not this artifact's; attach this image if it is not
attached; start the entry's units; and reload the units a configuration file whose bytes changed
named.

The script SHALL report what it did, one line per step it performed, so that a caller that ran it
learns whether anything changed without asking the machine a second question. A run that changed
nothing SHALL say so.

The assembly's existing guarantees SHALL hold unchanged: a file is created at its declared mode
before its first byte, the mode SHALL NOT depend on the environment's umask, and an interrupted run
SHALL leave no file at a wider mode.

#### Scenario: The script run twice over an unchanged entry

- **WHEN** the script is run twice with nothing changed between the runs
- **THEN** the machine SHALL hold the same image, the same units and the same configuration bytes
- **AND** no unit's main process SHALL have been replaced by the second run
- **AND** the second run SHALL report that nothing changed

#### Scenario: An entry whose configuration bytes changed and whose image did not

- **WHEN** the script of a build differing from the machine's only in a configuration file's bytes is
  run
- **THEN** the machine SHALL hold the new bytes
- **AND** the image SHALL NOT be detached or re-attached
- **AND** the run SHALL report the file as changed

#### Scenario: An interrupted run leaves no widened file

- **WHEN** the script is interrupted during the assembly of a configuration file
- **THEN** no file SHALL exist at a mode wider than the declared one
- **AND** a subsequent run SHALL complete the assembly

### Requirement: An older image of the same entry is replaced

Where the machine holds an image of this entry that is not this artifact's, the script SHALL stop
that entry's units, detach that image, and then attach its own. The image the machine currently runs
the entry from SHALL be read from the service manager rather than guessed from a name, because the
unit file names carry no version and two builds of one entry therefore render the same names.

An image that is already this artifact's SHALL NOT be detached and re-attached: the replacement is
for a different image, not for every run.

Where the machine holds no image of this entry, the script SHALL attach without a replacement step
and SHALL report that it attached.

#### Scenario: A second build of an attached entry

- **WHEN** the script of a build whose image identity differs from the attached one is run
- **THEN** the previous image SHALL be stopped and detached
- **AND** this artifact's image SHALL be attached and its units started
- **AND** the machine SHALL report exactly one image for that entry

#### Scenario: The same build run again

- **WHEN** the script of the build the machine already holds attached is run
- **THEN** the image SHALL NOT be detached
- **AND** the units' main processes SHALL be unchanged

#### Scenario: A first attachment

- **WHEN** the script is run on a machine holding no image of that entry
- **THEN** it SHALL attach and start
- **AND** it SHALL report the attachment and no replacement

### Requirement: A configuration file whose bytes changed reloads the units it named

Where a configuration file's assembled bytes differ from what the machine held, the script SHALL
reload the units that file's `reload` list named, after the entry's units are running. A file whose
assembled bytes are unchanged SHALL reload nothing, and a file naming no unit SHALL reload nothing.

Reloading SHALL be the service manager's reload where the unit declared a reload command and a
restart otherwise, and SHALL NOT start a unit that is not running.

A file recorded as not computed SHALL continue to be a refusal before anything is assembled, so no
reload is ever issued over bytes that were not written.

#### Scenario: An edited file reloads the unit it named

- **WHEN** a configuration file naming one unit is edited and the entry's script is run
- **THEN** that unit SHALL be reloaded
- **AND** the run SHALL report the reload naming the file and the unit

#### Scenario: A file whose bytes did not change

- **WHEN** the script is run with the configuration file's bytes unchanged
- **THEN** no reload SHALL be issued
- **AND** the run SHALL report no reload

#### Scenario: A file naming no unit

- **WHEN** an edited configuration file's `reload` list is empty
- **THEN** the bytes SHALL be written
- **AND** no unit SHALL be reloaded or restarted

#### Scenario: A unit that is not running is not started by a reload

- **WHEN** a configuration file naming a stopped unit is edited and the script is run
- **THEN** that unit SHALL NOT be started
- **AND** the run SHALL report the file as changed
