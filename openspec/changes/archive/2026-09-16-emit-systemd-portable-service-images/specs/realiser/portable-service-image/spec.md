## Purpose

Defines the systemd portable service image built from one plan entry: what the image carries, what may never enter it, how it is named, targeted and attached, and what makes two evaluations of one deployment produce the same image. The planner realises nothing, so this capability is the first consumer that turns a plan into bytes, and its whole job is to add no facts of its own. How a module declares those facts, and how they are typed, belongs to the planner capabilities this one consumes.

## ADDED Requirements

### Requirement: The image is built outside the planner from the plan alone

An image SHALL be built by a component outside `mkPlan`, and plan evaluation SHALL remain free of derivations. The builder SHALL take one placed plan entry and the plan it belongs to, and SHALL derive every fact it needs from them: the units to render, the extensions to render, the declared closure roots to populate, the store directory to populate them under, the `target` to build for, the configuration files to show and the generated files to expect.

The builder SHALL NOT re-evaluate the module the entry came from, and SHALL NOT read any value the plan does not carry. A fact the builder needs and the plan does not carry SHALL be reported as a missing plan field naming the entry, and SHALL NOT be inferred, defaulted, or read from the surrounding evaluation.

#### Scenario: A plan entry becomes an image

- **WHEN** the builder is given a placed entry and the plan it belongs to
- **THEN** it SHALL produce one image for that entry
- **AND** the plan SHALL be the only input it read

#### Scenario: The planner stays derivation-free

- **WHEN** the planner is evaluated for a deployment whose entries are built into images
- **THEN** the plan SHALL carry no derivation and no function
- **AND** no image SHALL be built by evaluating the plan

#### Scenario: A fact the plan does not carry

- **WHEN** the builder needs a fact the entry does not record
- **THEN** it SHALL fail naming the entry and the missing field
- **AND** SHALL NOT substitute a default

### Requirement: An image is a self-contained tree naming its own identity

An image SHALL carry an operating-system identity file recording the image's own portable identity and a human-readable name derived from the entry it was built from, and one rendered unit file per unit the entry records. It SHALL be populated from the entry's declared closure roots, placed under the store directory the plan records in `storeDir`, so that every command and environment value the units name resolves inside the image. The builder SHALL NOT derive the population list by scanning the entry, and SHALL NOT populate a store directory the plan does not name.

Every unit file name SHALL be prefixed with the image's own name, and that prefix SHALL be derived from the entry's instance and service, so two entries of one deployment cannot contribute a same-named unit to one machine. A unit file the builder would write unprefixed SHALL be refused at build time. A store path a unit names and the declared closure roots do not contain SHALL fail the build naming the entry, the unit and the path.

#### Scenario: The identity file is present

- **WHEN** an image is built
- **THEN** it SHALL carry an operating-system identity file naming the image's portable identity and its derived human-readable name
- **AND** an attachment requiring that file SHALL succeed

#### Scenario: A command resolves inside the image

- **WHEN** a unit's command names a store path the entry declares as a closure root
- **THEN** that path SHALL be present in the image under the plan's `storeDir`
- **AND** the unit SHALL be startable with no path from the host

#### Scenario: A store path named but not declared

- **WHEN** a unit names a store path the entry's declared closure roots do not contain
- **THEN** the build SHALL fail naming the entry, the unit and the path

#### Scenario: A machine whose store directory is relocated

- **WHEN** the plan records a `storeDir` other than the builder's own
- **THEN** the image SHALL populate the directory the plan names
- **AND** SHALL NOT populate a hardcoded store directory

#### Scenario: Two services of one instance on one machine

- **WHEN** two entries of one instance are placed on one machine and each records a unit of the same name
- **THEN** each image's unit file SHALL carry its own entry's prefix
- **AND** the two attached units SHALL NOT collide

### Requirement: A unit file carries exactly what the entry recorded

Each rendered unit SHALL express the portable fields the entry recorded for that unit and no others. A field the entry did not record SHALL be absent from the unit file rather than rendered as a service-manager default, so the unit file is a function of the plan and a reader can tell what the deployment asked for. The entry's per-unit environment SHALL be rendered on that unit and on no other.

`after` and `requires` SHALL be rendered as the distinct relations they are: an ordering SHALL NOT start the unit it orders against, and a requirement SHALL.

#### Scenario: An apply-and-exit unit

- **WHEN** an entry records a unit with `oneShot`, `remainAfterExit` and a `timeout`
- **THEN** the rendered unit SHALL express all three
- **AND** SHALL express no restart policy the entry did not record

#### Scenario: Two units with different environments

- **WHEN** an entry records two units whose `env` differs for one variable
- **THEN** each rendered unit SHALL carry its own value for that variable

#### Scenario: An ordering is not a requirement

- **WHEN** an entry records a unit with `after` naming another unit and no `requires`
- **THEN** the rendered unit SHALL express the ordering only
- **AND** starting the ordered unit SHALL NOT pull in the other

#### Scenario: A scheduled unit

- **WHEN** an entry records a unit with a `schedule`
- **THEN** the image SHALL carry both the service and the timer that triggers it
- **AND** both SHALL carry the image's prefix

### Requirement: Backend extensions are rendered or refused, never dropped

A unit's fields are the portable vocabulary plus extension fields the plan records grouped by backend. Extension fields recorded for the `systemd` backend SHALL be rendered into the unit file this builder writes.

An extension recorded for a backend this builder does not implement SHALL fail the build naming the entry, the unit and the `backend`, and SHALL NOT be dropped. An extension field the builder does not know how to render SHALL fail the build naming the field; an unrendered field SHALL NOT produce a unit that merely lacks it.

#### Scenario: A systemd extension is rendered

- **WHEN** a unit records extension `values` under the `systemd` backend
- **THEN** the rendered unit SHALL express each recorded field

#### Scenario: An extension for another backend

- **WHEN** a unit records an extension whose `backend` this builder does not implement
- **THEN** the build SHALL fail naming the entry, the unit and the `backend`

#### Scenario: An unknown extension field

- **WHEN** a unit records an extension field this builder has no rendering for
- **THEN** the build SHALL fail naming the field
- **AND** SHALL NOT emit a unit file omitting it

### Requirement: No secret and no configuration content enters an image

An image SHALL contain no secret bytes and no configuration file content. A generated file the entry records as a reference SHALL reach the units from the host at attach time, at the path the plan records, and SHALL NOT be copied into the image. A configuration file recorded with a `source` store path SHALL be copied out of the store to the host and shown to the image; one recorded with a `render` list SHALL be assembled on the host from its `text` fragments and `ref` paths and then shown, at the file's recorded `mode`.

Placing either inside the image SHALL fail the build naming the entry and the value. The consequence SHALL be that changing a configuration file, or regenerating a secret, leaves every image byte-identical.

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
- **AND** the units the file names in `reload` SHALL reload without the image being rebuilt or reattached

#### Scenario: A secret would be baked in

- **WHEN** a build would place inside an image the bytes of a value the plan records as a reference
- **THEN** the build SHALL fail naming the entry and the value

### Requirement: An image is built for the target its entry records

An image SHALL be built for the platform record the entry's `target` carries, and SHALL be named such that two entries differing only in platform produce two distinct images. An image SHALL NOT be attached on a machine whose `system` or `serviceManager` differs from the one it was built for, and the attempt SHALL be refused before any unit is started.

#### Scenario: One service on two architectures

- **WHEN** one service is placed on two machines whose platform records differ
- **THEN** two images SHALL be built, one per platform
- **AND** their names SHALL differ

#### Scenario: An image meets the wrong architecture

- **WHEN** an image built for one platform is presented to a machine running another
- **THEN** the attachment SHALL be refused naming both platforms
- **AND** no unit SHALL be started

#### Scenario: An image meets a different service manager

- **WHEN** an image built for `serviceManager = "systemd"` is presented to a machine running another service manager
- **THEN** the attachment SHALL be refused naming both service managers

### Requirement: Attachment is a named, recorded operation

Attaching an image SHALL be described by a record naming the image, the units it contributes, the confinement profile it is attached under, and every host path made visible to it. That description SHALL be derived from the plan entry and SHALL be recorded beside the image, so what a machine will run is reviewable before anything is attached.

The confinement profile SHALL be stated rather than inferred. An entry needing an access the stated profile denies SHALL fail the build naming the access and the profile, and SHALL NOT be attached under a broader profile chosen on its behalf. Detaching SHALL leave no unit behind and SHALL leave the host paths untouched.

#### Scenario: The description is reviewable

- **WHEN** an image is built for an entry
- **THEN** the builder SHALL also produce the attachment description naming the units, the profile and every host path shown
- **AND** the description SHALL name no path the entry does not imply

#### Scenario: A profile denies what a unit needs

- **WHEN** an entry's unit needs an access the stated profile denies
- **THEN** the build SHALL fail naming the unit, the access and the profile
- **AND** SHALL NOT widen the profile

#### Scenario: Detaching leaves nothing behind

- **WHEN** an image is detached
- **THEN** every unit it contributed SHALL be gone from the machine
- **AND** the host paths it was shown SHALL be untouched

### Requirement: Two evaluations of one deployment produce one image

An image SHALL be a function of the plan entry it was built from. Two builds from equal entries SHALL produce byte-identical images, and an entry whose key is unchanged SHALL NOT produce a different image. An edit that changes no entry's key SHALL change no image.

#### Scenario: A rebuild is identical

- **WHEN** the same entry is built twice
- **THEN** the two images SHALL be byte-identical

#### Scenario: An unrelated edit

- **WHEN** a setting is changed on one service and a second service reads nothing from it
- **THEN** the second service's image SHALL be byte-identical to the one built before the edit

#### Scenario: A unit field changes

- **WHEN** a unit's recorded `timeout` changes and nothing else does
- **THEN** that entry's key SHALL change
- **AND** its image SHALL differ
- **AND** no other entry's image SHALL differ
