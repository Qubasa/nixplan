<!--
A delta against `realiser/portable-service-image`, which lives in the unarchived
`emit-systemd-portable-service-images` change and is already modified by
`deliver-secrets-across-machines` and `declare-service-state`. `report-every-refusal-as-a-row` also
modifies it, restating "The image is built outside the planner from the plan alone" and "A rendered
environment value is one value"; this delta touches neither.

Two requirements are restated. "No secret and no configuration content enters an image" says a
generated file recorded as a reference reaches the units from the host at the path the plan records,
and `image/read.nix:228-242` derives those host paths from `entry.vars` alone, filtered to the files
the plan records as a reference. A consumer reading another instance's secret has no such record and
a delivered public file is filtered out, so `image/default.nix:96-99` creates no mount point and the
rendered unit gets no bind mount for the path its own environment names
(`image/read.nix:390-394`). A portable service runs with the image as its root, so the path is
absent at run time and neither realiser refuses it.

"Attachment is a named, recorded operation" says an entry needing a denied access fails the build.
`image/read.nix:301-318` computes the root-only files from the entry's own secret generated files
and maps each across `attrNames units`, so one unit's need refuses every unit of the entry, and an
entry that owns a secret cannot be confined at all. The restatement makes the denial name the units
that name the file. The build-time raise follows the row that
`report-every-refusal-as-a-row` produces under "A confinement profile is checked against the entry
it confines" in `specs/operator/deployment-build/spec.md`; this delta decides which units that row
names.
-->

## Purpose

Defines what an image has to carry for a unit's own environment to resolve inside it, and how a
confinement profile is applied to the units of an entry rather than to the entry as a whole.

## MODIFIED Requirements

### Requirement: No secret and no configuration content enters an image

An image SHALL contain no secret bytes and no configuration file content. A generated file the entry
records as a reference SHALL reach the units from the host at attach time, at the path the plan
records, and SHALL NOT be copied into the image. A configuration file recorded with a `source` store
path SHALL be copied out of the store to the host and shown to the image; one recorded with a
`render` list SHALL be assembled on the host from its `text` fragments and `ref` paths and then
shown, at the file's recorded `mode`.

Placing either inside the image SHALL fail the build naming the entry and the value. The consequence
SHALL be that changing a configuration file, or regenerating a secret, leaves every image
byte-identical.

An image SHALL carry a mount point for every generated file its own units, its configuration files,
and the reads the plan resolved for it name. The set SHALL be derived from the paths the entry names
and not from the generators the entry declares, so a file the entry reads rather than owns is
carried, and a file the plan records as a value rather than as a reference is carried too: what
decides is whether a unit of this entry opens the path, never who generated it or whether it is
secret. A generated path the entry names that no value entry of the plan accounts for SHALL fail the
build naming the entry, the unit, and the path, rather than producing an image whose unit opens a
path that is not there.

#### Scenario: A secret is referenced, not carried

- **WHEN** an entry's unit names a generated file the plan records as a reference
- **THEN** the image SHALL carry no bytes of that file
- **AND** the attachment SHALL make the host's copy visible at the path the plan records

#### Scenario: A render recipe is assembled on the host

- **WHEN** a configuration file records a `render` list containing a `ref`
- **THEN** the list SHALL be assembled on the host at attach time and shown to the image
- **AND** no fragment and no assembled byte SHALL enter the image

#### Scenario: A configuration change leaves the image byte-identical

- **WHEN** a configuration file's `source` or `render` recipe changes and nothing else does
- **THEN** the image SHALL be byte-identical to the one built before the change
- **AND** the units the file names in `reload` SHALL reload without the image being rebuilt or
  reattached

#### Scenario: A secret would be baked in

- **WHEN** a build would place inside an image the bytes of a value the plan records as a reference
- **THEN** the build SHALL fail naming the entry and the value

#### Scenario: A unit names a value another instance owns

- **WHEN** an entry's unit opens the path of a generated file of another instance, through a read
  the plan resolved
- **THEN** the image SHALL carry a mount point at that path
- **AND** the rendered unit SHALL be shown the host's copy of it
- **AND** the image SHALL carry no bytes of the file

#### Scenario: A unit names a public delivered file

- **WHEN** an entry's unit opens the path of a generated file the plan records as a value rather
  than as a reference
- **THEN** the image SHALL carry a mount point at that path
- **AND** the decision SHALL NOT depend on the file's secrecy

#### Scenario: A unit names a generated path no value accounts for

- **WHEN** an entry's unit opens a generated path that matches no value entry of the plan
- **THEN** the build SHALL fail naming the entry, the unit, and the path
- **AND** SHALL NOT emit an image carrying a unit that opens an absent path

### Requirement: Attachment is a named, recorded operation

Attaching an image SHALL be described by a record naming the image, the units it contributes, the
confinement profile it is attached under, and every host path made visible to it. That description
SHALL be derived from the plan entry and SHALL be recorded beside the image, so what a machine will
run is reviewable before anything is attached.

The confinement profile SHALL be stated rather than inferred. A unit needing an access the stated
profile denies SHALL fail the build naming that unit, the access, and the profile, and SHALL NOT be
attached under a broader profile chosen on its behalf. The denial SHALL be decided per unit: a unit
that names a host file only the privileged user may read is denied by a profile that denies that
access, and a unit of the same entry that names no such file is not, so an entry may own a value and
confine the units that do not open it. The build-time refusal SHALL follow the row the deployment
build already produced for the same condition rather than standing alone as the first report of it.

Detaching SHALL leave no unit behind and SHALL leave the host paths untouched.

#### Scenario: The description is reviewable

- **WHEN** an image is built for an entry
- **THEN** the builder SHALL also produce the attachment description naming the units, the profile
  and every host path shown
- **AND** the description SHALL name no path the entry does not imply

#### Scenario: A profile denies what a unit needs

- **WHEN** an entry's unit needs an access the stated profile denies
- **THEN** the build SHALL fail naming the unit, the access and the profile
- **AND** SHALL NOT widen the profile

#### Scenario: Detaching leaves nothing behind

- **WHEN** an image is detached
- **THEN** every unit it contributed SHALL be gone from the machine
- **AND** the host paths it was shown SHALL be untouched

#### Scenario: One unit of an entry names a root-only file

- **WHEN** an entry declares two units under a confining profile and only one of them opens a host
  file the privileged user alone may read
- **THEN** the build SHALL fail naming that unit and no other
- **AND** an entry whose units open no such file SHALL build under the same profile
- **AND** removing the opening unit's reference to the file SHALL make the entry build
