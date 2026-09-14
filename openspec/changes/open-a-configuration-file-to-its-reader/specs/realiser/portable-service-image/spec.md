<!--
A delta against `realiser/portable-service-image`, whose base text lives in the unarchived changes
`emit-systemd-portable-service-images`, `deliver-secrets-across-machines`,
`report-every-refusal-as-a-row`, `generate-values-with-nixos-secrets`, `declare-service-state`,
`deliver-a-secret-without-exposing-it`, `hold-every-stated-guarantee`,
`open-a-delivered-value-to-its-reader`, `take-effect-on-a-second-apply` and
`hold-a-long-running-daemon`. `openspec/specs/` is empty in this repository, so the base text is
read from those changes.

The MODIFIED requirement below replaces `A configuration file whose bytes are a store path is shown
from that path` (`hold-a-long-running-daemon`), whose rule was about where the bytes come from
alone. That rule is kept and given its second half: a bind shows the source's ownership and mode,
so a record a store object cannot carry is a file this realiser installs rather than binds. The
requirements about the empty mount point, the profile denial table, the identity digest and the
attach script's comparison are unchanged, and the two rules `hold-every-stated-guarantee` and
`take-effect-on-a-second-apply` state about a file the script writes are what the installation is
held to.

The conditions: a configuration file reaches a unit as a read-only bind of `from` onto `path`
(`image/read.nix:681-683`) and `from` is the file's own store object for a `source` file and the
assembled store object for a literal recipe (`image/read.nix:300-310`); the projected record carries
`mode` and no account (`image/read.nix:252-261`); the profile denial table reads generated files
alone (`image/read.nix:375-407`); and `unitDirectives` names no directory and no condition
(`image/read.nix:101-116`).
-->

## ADDED Requirements

### Requirement: The directory and condition fields a unit declared are rendered

Where a unit records a directory of one of the three kinds, the rendered unit file SHALL carry the
service manager's own directive for that kind with the names the plan recorded, and where it records
a mode for that kind, the rendered file SHALL carry the directive that states it. Where a unit
records a condition on a path, the rendered file SHALL carry the service manager's own condition
directive with the polarity the plan recorded. A unit that recorded none of them SHALL produce a
unit file carrying none.

The mapping SHALL be stated in the one table every unit field is mapped in, so that a field the
vocabulary carries and this realiser has no directive for fails the build rather than being dropped:
a vocabulary that grew and a realiser that did not is the realiser's defect. That refusal SHALL
keep its recorded account rather than claiming a row above it, because no deployment can produce a
field the vocabulary does not carry.

#### Scenario: A unit declaring a directory renders both directives

- **WHEN** an entry's unit records a state directory and a mode for that kind
- **THEN** the rendered unit file SHALL carry the directory directive with that name and the mode
  directive with that mode
- **AND** the image's version digest SHALL differ from the same entry's digest without them

#### Scenario: A condition rendered with the polarity stated

- **WHEN** an entry's unit records a condition on a path it starts only while that path is absent
- **THEN** the rendered unit file SHALL carry the service manager's condition directive naming that
  path with that polarity
- **AND** a unit recording the present polarity on the same path SHALL render the same directive
  with the other polarity

#### Scenario: A vocabulary field with no directive fails the build

- **WHEN** a unit records a vocabulary field this realiser's directive table does not name
- **THEN** the build SHALL fail naming the entry, the unit and the field
- **AND** the refusal SHALL state that the defect is the realiser's table rather than the
  deployment's declaration

### Requirement: A configuration file only its owner may read joins the profile denial table

A configuration file's record SHALL be read against the account the stated confinement profile
imposes and the groups its unit declares, the same comparison this realiser already makes for a
delivered value's file, and a profile that denies a host file only the superuser may read SHALL deny
a configuration file whose record admits no other account. The denial SHALL name the entry, the
unit, the path, the record and the account that would read it, so that the row mirroring it names
the facts a deployment can change.

A configuration file whose record admits the unit's account, by owning it or through a group the
unit declares, SHALL NOT be denied under any profile, and no profile SHALL be widened on an entry's
behalf.

#### Scenario: A configuration file only root may read under a confining profile

- **WHEN** an entry stated to run under a confining profile declares a configuration file the
  superuser alone may read
- **THEN** the realiser SHALL deny it naming the entry, the unit, the path, the record and the
  account
- **AND** the deployment build SHALL report the same denial as an error row

#### Scenario: A group-readable configuration file under a confining profile

- **WHEN** the same entry declares that file readable by a group its unit declares
- **THEN** the realiser SHALL deny nothing about that file
- **AND** the image SHALL be built

#### Scenario: A configuration file under the unconfined profile

- **WHEN** an entry stated to run under the profile that denies nothing declares a configuration
  file the superuser alone may read
- **THEN** the realiser SHALL deny nothing about that file

## MODIFIED Requirements

### Requirement: A configuration file is shown at the record it states

A configuration file SHALL be shown to its entry at the ownership and the mode its record states.
Where the record is the record a store object carries, the file SHALL be shown from a store path:
a `source` file from its own, and a `render` list of nothing but `text` items from the path this
realiser assembled at build time. Where the record is any other, the file SHALL be installed onto
the host at the stated ownership and mode and shown from there, because showing a store object
shows the ownership and the mode the store gives it and not the ones the declaration stated.

A configuration file whose `render` list carries a `ref` SHALL continue to be installed on the
machine whatever its record, because its bytes name a path the machine holds.

Every file this realiser installs SHALL keep the guarantees the attach step already gives: it is
created closed before its first byte is written, its ownership and mode are set before it is moved
into place, it never exists at a record wider than the declared one, and neither its mode nor its
ownership depends on the attaching login's environment. Each installed file SHALL be written only
where it differs from the file the machine already holds, and its record SHALL be re-applied either
way.

This narrows `A configuration file whose bytes are a store path is shown from that path`, whose rule
decided where a file was shown from by the disposition alone. The disposition still decides where
the bytes come from; the record now decides who puts them at the path. The image SHALL still carry
an empty file at every host path it is shown, whatever the source of the bytes, because the image
root is read-only and a missing mount point is a unit that cannot start.

#### Scenario: A file whose record the store carries is shown from the store

- **WHEN** an entry records a configuration file, as a `source` path or as literals only, whose
  record is the one a store object carries
- **THEN** the entry SHALL be shown that store path as the source of the bind
- **AND** the attach step SHALL install nothing for that file

#### Scenario: A file stating an ownership is installed on the host

- **WHEN** an entry records a configuration file of literals stating an owner and a group
- **THEN** the attach step SHALL install it on the host at that owner, that group and its mode
- **AND** the entry SHALL be shown the installed path rather than the store path
- **AND** the bytes SHALL still travel with the artifact rather than being written by the script

#### Scenario: A file stating a mode the store cannot carry is installed on the host

- **WHEN** an entry records a configuration file of literals stating a mode no store object has
- **THEN** the attach step SHALL install it on the host at that mode
- **AND** the file the unit opens SHALL be at that mode rather than at the store's

#### Scenario: A referenced recipe is installed at the record it states

- **WHEN** an entry records a configuration file whose `render` list carries a `ref`
- **THEN** the attach step SHALL assemble it on the machine and install it at its stated ownership
  and mode
- **AND** the image SHALL carry an empty file at the host path it is shown

#### Scenario: An interrupted install leaves no file at a wider record

- **WHEN** the assembly or installation of a configuration file stops part way
- **THEN** no file at that path SHALL be readable by an account the record does not admit
- **AND** a second run SHALL install it completely
