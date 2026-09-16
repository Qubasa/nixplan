# realiser/portable-service-image Specification

## Purpose
Defines the systemd portable service image built from one plan entry: what the image carries, what may never enter it, how it is named, targeted and attached, and what makes two evaluations of one deployment produce the same image. The planner realises nothing, so this capability is the first consumer that turns a plan into bytes, and its whole job is to add no facts of its own. How a module declares those facts, and how they are typed, belongs to the planner capabilities this one consumes.

## Requirements

### Requirement: The image is built outside the planner from the plan alone

An image SHALL be built by a component outside `mkPlan`, and plan evaluation SHALL remain free of
derivations. The builder SHALL take one placed plan entry and the plan it belongs to, and SHALL
derive every fact it needs from them: the units to render, the extensions to render, the declared
closure roots to populate, the store directory to populate them under, the `target` to build for,
the configuration files to show and the generated files to expect.

The builder SHALL NOT re-evaluate the module the entry came from, and SHALL NOT read any value the
plan does not carry. A fact the builder needs and the plan does not carry SHALL be reported as a
missing plan field naming the entry, and SHALL NOT be inferred, defaulted, or read from the
surrounding evaluation.

Every refusal this builder makes SHALL be a condition an error row of the planner's table or of the
deployment build's table already reported, and a refusal about a fact the realisation statement
carries SHALL be reported by the deployment build rather than here. A refusal here SHALL therefore
be the answer a caller reaching this builder directly receives, and no path through a deployment
build SHALL reach one without a row. A field the plan records as empty SHALL NOT be refused as a
field the plan does not record.

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
- **AND** an entry recording that field as empty SHALL NOT be refused

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

### Requirement: An image carries no bytes the host holds

An image SHALL carry no generated bytes, and SHALL carry a configuration file's bytes only where
the plan itself holds them. Placing a generated value's bytes inside an image SHALL fail the build
naming the entry and the value.

This narrows `An image carries neither configuration bytes nor generated bytes`, whose consequence
was that changing any configuration file left every image byte-identical. That consequence now
holds for a file whose `render` list carries a `ref`, whose bytes the host writes at attach time,
and not for a `source` path or a literal recipe, which are store objects the image's closure
reaches. The image's version digest SHALL be taken over what the artifact holds, so an edit to a
literal recipe SHALL move it and an edit to a `ref`-bearing one SHALL NOT.

#### Scenario: A configuration change leaves the image byte-identical

- **WHEN** a configuration file whose `render` list carries a `ref` has its literal fragments
  changed
- **THEN** the image SHALL be byte-identical to the one built before the change
- **AND** the entry's key SHALL have moved

#### Scenario: A secret would be baked in

- **WHEN** an entry declares a generated value's path as a closure root
- **THEN** the build SHALL fail naming the entry and the value

#### Scenario: A secret is referenced, not carried

- **WHEN** an entry's unit names a generated file the plan records as a reference
- **THEN** the image SHALL carry no bytes of that file
- **AND** the attachment SHALL make the host's copy visible at the path the plan records

#### Scenario: A render recipe is assembled on the host

- **WHEN** a configuration file records a `render` list containing a `ref`
- **THEN** the list SHALL be assembled on the host at attach time and shown to the image
- **AND** no fragment and no assembled byte SHALL enter the image

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

### Requirement: A rendered environment value is one value

A rendered `Environment=` assignment SHALL carry the whole value the plan records, whatever
characters it contains, or the entry SHALL be refused. A value containing a space, a double quote
or a backslash SHALL be rendered so that the service manager reads back exactly the bytes the plan
holds.

A value containing a line break SHALL be refused, and the refusal SHALL hold for every value this
realiser interpolates into a unit file and not for an environment value alone: a command, a stop or
reload command, a user, a unit reference, a schedule, a duration, a restart policy and every field
of every extension application reach the same line-oriented file. The refusal SHALL name the entry,
the unit and the field the value sits at.

A line break in a unit value is a fact the plan carries, so the planner SHALL report it as an error
row first and this refusal SHALL follow that row rather than stand alone. The refusal here SHALL
remain for a caller that reached the builder directly, and SHALL carry the identifier of that row.

#### Scenario: An environment value carries a space

- **WHEN** a unit's environment holds a value containing a space, a double quote and a backslash
- **THEN** the rendered unit SHALL carry one assignment per variable
- **AND** each assignment SHALL round-trip to the value the plan records

#### Scenario: An environment value carries a newline

- **WHEN** a unit's environment holds a value containing a newline
- **THEN** the build SHALL fail naming the entry, the unit and the variable
- **AND** the same bytes on one line SHALL build

#### Scenario: A command carries a newline

- **WHEN** a unit's command holds a value containing a newline
- **THEN** the build SHALL fail naming the entry, the unit and the field
- **AND** the rendered unit SHALL NOT be produced with a second directive line the module wrote

### Requirement: A path is shown only where bytes arrive at it

The reading SHALL show a host path for a generated file only where the plan records that the file is
deployed. A value no machine receives has no bytes at its path, so mounting it would mount nothing:
the service manager refuses the namespace and the unit fails with neither the value nor the
declaration named.

An entry that owns such a value SHALL still be readable, and every other path it is shown SHALL be
unaffected. The undeployed file's path SHALL remain in the plan, because a site that opens it is a
row the planner reports.

#### Scenario: An undeployed value is shown at no path

- **WHEN** an entry owning both a deployed and an undeployed generated value is read
- **THEN** the entry SHALL be shown the deployed file's path
- **AND** it SHALL be shown no path for the undeployed one
- **AND** the plan SHALL still record the undeployed file's path

### Requirement: A staged file carries its declared mode before it carries bytes

A file the realiser assembles on the host SHALL have its declared mode before any byte is written
into it, so that no window exists in which the assembled file is readable by anyone the declaration
did not admit. The mode SHALL NOT depend on the environment the attach runs in.

A failure part way through assembling a file SHALL NOT leave that file readable more widely than its
declaration states. A file whose assembly did not complete SHALL either carry its declared mode or
not exist.

#### Scenario: A staged file renders a secret

- **WHEN** a configuration file declares a mode and renders a reference to a generated secret
- **THEN** the file on the host SHALL carry that mode from the moment it exists
- **AND** at no point SHALL it be readable by a user the mode excludes

#### Scenario: The assembly of a file fails part way

- **WHEN** the assembly of a declared file stops after some bytes are written
- **THEN** what remains on the host SHALL NOT be readable more widely than the declared mode
- **AND** the next attach SHALL be able to assemble the file again

#### Scenario: The mode does not depend on the attaching environment

- **WHEN** the attach runs with a permissive file-creation mask
- **THEN** the staged file's mode SHALL be the declared one
- **AND** SHALL NOT be widened by the environment

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

### Requirement: A restart policy a unit declared is rendered, and one it did not is absent

Where a unit records `restart`, the rendered unit file SHALL carry the service manager's own restart
directive with the policy the plan recorded, and where it records `restartSec`, the rendered file
SHALL carry the delay directive. A unit that recorded neither SHALL produce a unit file carrying
neither, so that a unit asking for nothing keeps the service manager's default rather than being
pinned to this realiser's opinion of one.

The mapping SHALL be stated in the same table the extension directives are stated in, so that a
field the plan can carry and this realiser cannot render fails the build the way an unknown extension
field does rather than being silently dropped.

#### Scenario: A unit that is restarted on failure

- **WHEN** an entry's unit records `restart = "on-failure"` and a `restartSec`
- **THEN** the rendered unit file SHALL carry both directives with those values
- **AND** the image's version digest SHALL differ from the same entry's digest without them

#### Scenario: A unit that declared no policy

- **WHEN** an entry's unit records neither `restart` nor `restartSec`
- **THEN** the rendered unit file SHALL carry neither directive
- **AND** the rendered bytes SHALL be unchanged from what this realiser produced before the fields
  existed

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

#### Scenario: A file copied from a store path is not staged

- **WHEN** an entry records a configuration file as a `source` store path
- **THEN** the entry SHALL be shown that store path as the source of the bind
- **AND** the attach step SHALL assemble nothing for that file
- **AND** the store path SHALL be part of the entry's closure

#### Scenario: A file assembled from literals is assembled at build time

- **WHEN** an entry records a configuration file whose `render` list holds `text` items only
- **THEN** the realiser SHALL assemble those literals into a store path at build time
- **AND** the entry SHALL be shown that path
- **AND** the attach step SHALL assemble nothing for that file

#### Scenario: A file referencing a delivered path is still assembled on the machine

- **WHEN** an entry records a configuration file whose `render` list carries a `ref`
- **THEN** the attach step SHALL assemble it on the machine at its declared mode
- **AND** the file SHALL never exist at a mode wider than the declared one
- **AND** the image SHALL carry an empty file at the host path it is shown

### Requirement: An extension field this realiser cannot render is refused with the row that reports it

Where an entry records an extension field this realiser has no rendering for, the refusal SHALL name
the entry, the unit, the field and the backend, and SHALL carry the identifier of the diagnostic row
that reports the same condition. No refusal of this reading SHALL account for itself as having no row
above it while a deployment the planner calls applicable can reach it.

#### Scenario: A field the directive table does not carry

- **WHEN** an entry's unit records an extension field this realiser's directive table does not carry
- **THEN** the realiser SHALL refuse naming the entry, the unit, the field and the backend
- **AND** the refusal SHALL carry the identifier of the row that reports the condition
- **AND** no deployment the planner calls applicable SHALL reach that refusal without the row having
  been produced

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

### Requirement: A unit file name this realiser derives is held to a rule it states itself

This realiser derives a service name and a unit file name from the entry's own identity, and both
SHALL be held to a rule this realiser states as the sentence its refusal prints, so that the rule and
the message cannot drift apart. A derived name outside the rule SHALL be a refusal naming the entry
and the name, and that refusal SHALL carry the identifier of the row that reports the same condition,
the way the other realiser's name rule already does.

The rule SHALL be the realiser's own and SHALL NOT be stated by the library: which realiser realises
an entry is a fact beside the deployment and no plan field carries it, so a rule in the library would
refuse a name the stated realiser accepts.

A reading that is handed a realisation statement SHALL ask the stated realiser for that rule rather
than testing which realiser it is, so that a realiser publishing the rule is asked by existing, and
SHALL report the refused name as an error row before anything is built. A name outside the rule SHALL
NOT be left to be refused by the build system that happens to receive it: such a refusal names
neither the entry nor the declaration.

#### Scenario: A unit name outside the rule is refused naming the entry

- **WHEN** an entry's identity derives a unit file name carrying a character the rule does not admit
- **THEN** the realiser SHALL refuse naming the entry, the derived name and the rule
- **AND** the deployment build SHALL report an error row for it and build no artifact of that entry

#### Scenario: The name refusal is preceded by its row

- **WHEN** the refusals this realiser can make are crossed against the rows the producing layers
  build
- **THEN** the name refusal SHALL name a row identifier a producing layer produces
- **AND** the row and the refusal SHALL state one rule, asked of the realiser rather than restated

#### Scenario: A name the rule admits builds

- **WHEN** an entry's identity derives a service name and unit file names the rule admits
- **THEN** the realiser SHALL refuse nothing on their account
- **AND** the rendered unit file names SHALL be the ones the entry recorded

### Requirement: A value a generated script interpolates is escaped, grammar or no grammar

Every value this realiser interpolates into a generated shell script SHALL be escaped as one word,
whether or not a grammar elsewhere already constrains that value. This SHALL hold for a value in a
message as well as for a value in an argument: a message is not a place to rely on a grammar,
because a grammar and an escape fail independently and the escape is what holds when a new field
reaches a script before its rule does.

A list of derived names a script hands to a command SHALL be escaped word by word rather than joined
into one string, so that a name carrying a shell metacharacter is a word the command refuses rather
than a pattern the shell expands.

This requirement is a property of the rendered script and SHALL NOT be satisfied by a row: a plan the
library refused is a plan this realiser is never handed, and a caller reaching the realiser directly
is exactly the caller the escape protects.

#### Scenario: Every path a generated script names is escaped

- **WHEN** an entry's scripts are rendered for an entry whose configuration file paths are ordinary
- **THEN** every occurrence of a path in those scripts SHALL be escaped, in messages as well as in
  arguments
- **AND** no occurrence SHALL be a bare interpolation inside a quoted string

#### Scenario: A unit list is escaped word by word

- **WHEN** the attach script stops, starts or detaches the units of an entry
- **THEN** each unit file name SHALL appear as its own escaped word
- **AND** the list SHALL NOT be rendered as one unquoted string

### Requirement: The staging directory is traversable and not listable

A directory this realiser's attach script creates to hold what the host shows an image SHALL be
created traversable by any account and listable by none, which is the mode the two writers of a
delivered value already create their directories at. A unit reads a staged file by its full path, so
traversal is the only access any account needs, and the file's own declared mode still decides its
bytes.

The directory SHALL be created at that mode before it holds a file, and no later step SHALL widen it.
A listable directory would publish the configuration file names of every entry on the machine to any
account, which is a fact about the deployment that no declaration asked to be published.

#### Scenario: The staging directory is traversable and not listable

- **WHEN** the attach script creates the directory it stages configuration files in
- **THEN** the directory SHALL be traversable by any account and listable by none
- **AND** each staged file SHALL still carry its own declared mode

#### Scenario: A staged file is readable through a directory nobody may list

- **WHEN** a unit reads a staged configuration file whose declared mode admits its account
- **THEN** the read SHALL succeed
- **AND** listing the staging directory as that account SHALL be refused

### Requirement: The version digest an artifact publishes covers every statement its bytes depend on

An artifact's version digest is the identity an endpoint stores and the identity a report compares,
so it SHALL move whenever a statement the artifact was built from changes a byte the artifact
carries, and SHALL NOT move for a statement that changes none. The stated confinement profile is
such a statement: it decides directives the rendered unit files carry, so it SHALL be part of the
digest, beside the entry's name, its units, its closure, the store directory, the service manager,
the host paths it is shown and the platform it is built for.

Two artifacts of one entry whose rendered bytes differ SHALL NOT share a digest, SHALL NOT share an
image file name, and SHALL NOT be reported as one build a machine already holds. A statement a
reader can change and see no consequence is the failure this requirement removes: an apply that
reports nothing changed and a report that says the machine is current, over an entry whose
confinement the operator has just tightened.

Widening the digest re-keys every artifact once, which is one stop, detach and attach per entry on
the first apply after this change and nothing afterwards. That is the intended consequence: a
digest that was wrong for one statement was wrong for every artifact built under it.

#### Scenario: The version digest carries the confinement profile

- **WHEN** one entry is read twice, differing only in the confinement profile stated for it
- **THEN** the two readings SHALL publish two different version digests
- **AND** the two artifacts SHALL carry two different image file names
- **AND** neither reading SHALL report the other's identity as its own

#### Scenario: A tightened profile is a build the machine does not hold

- **WHEN** an operator tightens the confinement stated for an entry and applies the deployment
- **THEN** the machine SHALL be told it holds a build that is not this one
- **AND** the entry's units SHALL be stopped, its previous image detached and this one attached
- **AND** a second apply of the same statement SHALL report that nothing changed

#### Scenario: An entry whose statement did not change keeps its digest

- **WHEN** a deployment is edited so that neither an entry's own record nor the statement beside it
  changes
- **THEN** that entry's version digest SHALL be the digest it published before the edit
- **AND** its artifact SHALL be byte-identical
- **AND** an apply SHALL neither detach nor re-attach it

### Requirement: Every part of a rendered directive is escaped the way every other part is

A rendered directive carries more than one part - a variable's name beside its value - and every
part SHALL be carried through the escape the others are carried through, so that no part can end
the quoting another part sits inside. A name containing the quote character, the backslash or a
character the service manager reads as a separator SHALL read back as exactly the bytes the plan
records, the way the value on the same line already does.

Where the renderer has no escape that carries a part of a directive, the entry SHALL be refused
naming the entry, the unit and the part, and SHALL NOT be rendered into a file whose remaining
directives are the declaration's to choose. A part the renderer drops, truncates or renders into a
line the service manager answers with a syntax complaint SHALL NOT be taken to satisfy this
requirement: a unit that starts without the variable a declaration asked for is the silent failure
this rule exists to remove.

The plan reports such a value as an error row first and this refusal SHALL follow that row rather
than stand alone, the way this realiser's other refusals do. The refusal SHALL remain as the answer
a caller that reached this realiser directly receives, and SHALL carry the identifier of the row
that reports the same condition.

#### Scenario: An environment name is escaped the way its value is

- **WHEN** a unit's environment holds a variable whose name carries the quote character
- **THEN** the planner SHALL report an error row for that name, or the rendered directive SHALL
  escape the name the way it escapes the value on the same line
- **AND** the rendered line SHALL carry no directive the declaration did not write
- **AND** the service manager SHALL read back the name and the value the plan records

#### Scenario: A rendered directive reads back as the name and the value the plan records

- **WHEN** a unit's environment holds a value carrying a space, a quote character and a backslash,
  under a name the name grammar admits
- **THEN** the rendered unit SHALL carry one assignment for that variable
- **AND** that assignment SHALL round-trip to the name and the value the plan records
- **AND** the name SHALL have been carried through the escape the value was carried through

#### Scenario: An environment name the renderer cannot carry is refused

- **WHEN** an entry reaches this realiser with an environment name the renderer has no escape for
- **THEN** the build SHALL fail naming the entry, the unit and the name
- **AND** the refusal SHALL carry the identifier of the row that reports the same condition
- **AND** no unit file of that entry SHALL be produced
