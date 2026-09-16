<!--
A delta against `realiser/portable-service-image`, whose current text is
`openspec/specs/realiser/portable-service-image/spec.md`. Everything here is ADDED.

Why this capability is touched at all: a field missing from the directive table fails the build on
purpose (`image/read.nix:67-70` and `:90-93`, the refusal at `:686-687` computed from
`:673`), because an extension exists to add a field and dropping one would make the extension a
comment. A vocabulary field is therefore not addable to one realiser: this one must render the probe
too. `A unit file carries exactly what the entry recorded` and `Backend extensions are rendered or
refused, never dropped` are unchanged and not restated - the probe is not an extension field, and
what it renders into is a second file rather than a directive of the probed unit's.

What this realiser can honestly do. `portablectl` attaches an image and starts the entry's units
(`image/default.nix:362-366`), the unit list it starts being the attachment description's
(`image/read.nix:932-935`, `image/default.nix:327`). There is no generation to return to
(`cli/report.py:30-32`), so there is nothing to roll back and this delta says so rather than
inventing one. A failing probe is a failed step of the attach script, which runs under `set -eu`,
and the command's own error names the entry, the machine and what the machine printed.

The rendering has one home. `image/read.nix:897-915` renders one file per unit and one per scheduled
unit's timer through the two renderers a realiser hands over, and flakelet's wrappers
(`flakelet/read.nix:129-134`) add the install section. The probe unit carries none under either
realiser, so it is rendered by the shared reading and by neither wrapper, and the two realisers'
probe unit text for one entry is one text. The binds a unit needs to see a delivered value are
entry-wide already (`image/read.nix:818-820`).

The version digest is taken over what the artifact holds (`image/read.nix`'s `versionFor`, read by
`operator/read.nix:260-263`), so a probe that changed is a new digest and therefore a replacement at
the next apply.
-->

## ADDED Requirements

### Requirement: The image carries the derived probe unit and renders it once

An image of an entry one of whose units records a probe SHALL carry the derived probe unit file
beside the unit files its units already render, under the same derived name every other realiser of
that entry derives. The image's directive table SHALL name both probe fields, so that neither is a
vocabulary field this builder fails the build on, and the directives they render as SHALL be the ones
the derived unit carries rather than directives added to the probed unit.

The derived unit SHALL be rendered by the reading both realisers share and by neither realiser's own
wrapper, because the one thing both realisers state about it is the same: it carries no install
section. Two realisers reading one entry SHALL therefore produce one probe unit text.

The derived unit SHALL be shown every host path the entry's other units are shown, so that a probe
reading a delivered value or a configuration file reaches it inside the same namespace. It SHALL
claim no directory, for the reason the other realiser states: a job that exits would take a runtime
directory it declared with it.

A probe SHALL be part of the image's version digest, as every unit field is, so an entry whose probe
changed is a different image and is replaced at the next apply rather than compared equal.

#### Scenario: An image of a probed entry carries the probe unit

- **WHEN** an image is built for an entry one of whose units records a probe
- **THEN** the image SHALL carry the derived probe unit file
- **AND** its name SHALL carry the image's own prefix
- **AND** an entry recording no probe SHALL make the image carry no such file

#### Scenario: A probe field the directive table does not name

- **WHEN** the builder reads a unit recording a probe and its bound
- **THEN** the build SHALL NOT fail for a vocabulary field the directive table does not name
- **AND** the probed unit's own file SHALL carry neither the probe command nor its bound

#### Scenario: The probe unit is the one file both realisers render alike

- **WHEN** one entry is read by both realisers and its unit records a probe
- **THEN** the derived probe unit text SHALL be identical under both
- **AND** neither text SHALL carry an install section

#### Scenario: An image's probe is shown what the entry is shown

- **WHEN** an entry recording a probe is shown a host path
- **THEN** the derived probe unit SHALL be shown that path as the entry's other units are
- **AND** the derived unit SHALL declare no directory of any kind

#### Scenario: A changed probe is a different image

- **WHEN** a unit's probe command changes and nothing else does
- **THEN** the entry's version digest SHALL differ
- **AND** the image SHALL differ

### Requirement: The image starts the probe and rolls nothing back

The attachment description SHALL name the derived probe unit among the units it contributes, so that
attaching the entry starts the probe with the rest and a probe that fails fails the step that started
it. The failure SHALL be reported as the applying command reports any step a machine refused: the
entry, the machine and what the machine printed.

It SHALL be stated, as a property of this realiser rather than as an omission, that nothing rolls
back. An attached image is the only thing the entry has, there is no previous generation to return
to, and asking this realiser to roll one back is already a refusal naming the entry and its
realiser. The machine therefore keeps running what it holds, and the recovery is a second apply of
a corrected build.

A probe under this realiser is therefore evidence and not a gate: what it buys is a failing apply
and a journal entry naming the probe, where a passing start job would otherwise have been the only
answer.

#### Scenario: The probe is attached and started with the entry's units

- **WHEN** an image of a probed entry is built
- **THEN** the attachment description SHALL name the derived probe unit among the entry's units
- **AND** attaching the entry SHALL start it with them

#### Scenario: A failing probe fails the attach and changes nothing else

- **WHEN** an entry whose probe command fails is applied to a machine
- **THEN** the step that starts the entry's units SHALL fail
- **AND** the command SHALL name the entry, the machine and what the machine printed
- **AND** the image the machine holds SHALL still be attached
