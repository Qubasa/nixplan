<!--
A delta against `realiser/portable-service-image`, whose base text lives in the unarchived changes
`emit-systemd-portable-service-images`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `generate-values-with-nixos-secrets`, `declare-service-state`,
`deliver-a-secret-without-exposing-it` and `hold-every-stated-guarantee`. `openspec/specs/` is empty
in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The profile table itself, the empty mount point at every shown host
path, and the refusal-with-a-row rule are unchanged. What this delta changes is the condition one
denial is read against.

The condition: `image/read.nix:256-258` denies a deployed `secrecy = "secret"` reference to every
unit of the entry whenever the profile denies "a host file only root may read", which is `default`,
`nonetwork` and `strict` (`:45-57`). The denial is therefore a function of the file's secrecy, and
the fact that actually decides it - whether the unit's reader may open the file - is one the
deployment could not state until the file record carried an ownership and a mode.
-->

## ADDED Requirements

### Requirement: A deployed value is denied to a unit only where its record cannot admit that unit's reader

The denial of a deployed generated file SHALL be read from the file's recorded ownership and mode
together with the account the unit runs under this profile, and SHALL NOT be read from the file's
secrecy alone.

A profile that runs a unit under a transient account SHALL deny a file whose record admits only its
owner. It SHALL NOT deny a file the unit's reader can open: a file whose recorded group is one the
unit declares, at a mode with group read, is readable by a transient account, and a file with world
read is readable by any.

A profile that denies nothing SHALL continue to deny nothing. Where a denial stands, the refusal and
the row that reports it SHALL name the unit, the file, the record's ownership and mode, and the
account the profile imposes, so that the resolution is a fact the deployment can change rather than
a choice between confinement and secrets.

#### Scenario: A root-only value under a confining profile

- **WHEN** an entry realised under a confining profile reads a deployed file recorded as owned by
  `root` at mode `0400`
- **THEN** the realiser SHALL refuse naming the unit, the file, the record and the imposed account
- **AND** the layer that holds the realisation statement SHALL have reported the same condition as a
  row

#### Scenario: A group-readable value under a confining profile

- **WHEN** the same entry's file records a group the unit declares, at a mode with group read
- **THEN** the realiser SHALL NOT deny it
- **AND** the entry SHALL be built with the file shown at the path the plan records

#### Scenario: A root-only value under the unconfined profile

- **WHEN** an entry realised under the profile that denies nothing reads a root-only deployed file
- **THEN** the realiser SHALL NOT deny it

#### Scenario: A secret is no longer denied for being secret

- **WHEN** two entries under one confining profile read two deployed files whose records differ only
  in ownership and mode
- **THEN** exactly one SHALL be denied
- **AND** the denial SHALL name the record rather than the secrecy

### Requirement: A unit's supplementary groups are renderable

The directive table SHALL carry the field that grants a unit membership of an existing group, so that
a unit under a transient account can read a file a static group owns. A unit that declares no such
field SHALL render no such directive.

A group a unit declares SHALL be what the denial above is read against, so that the deployment's two
statements - the file's group and the unit's groups - are compared in one place rather than
discovered at run time.

#### Scenario: A unit declaring a supplementary group

- **WHEN** a unit applies the extension field naming a supplementary group
- **THEN** the rendered unit file SHALL carry the corresponding directive with that group
- **AND** the denial of a file that group owns SHALL NOT stand

#### Scenario: A unit declaring none

- **WHEN** a unit applies no such field
- **THEN** the rendered unit file SHALL carry no such directive
- **AND** the rendered bytes SHALL be unchanged from what this realiser produced before the field
  existed
