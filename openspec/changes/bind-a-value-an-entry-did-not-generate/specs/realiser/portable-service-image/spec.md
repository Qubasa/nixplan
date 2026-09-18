<!--
A delta against `realiser/portable-service-image`, whose current text is
`openspec/specs/realiser/portable-service-image/spec.md`. Two requirements are modified and two are
added. Each MODIFIED block below is the current text copied whole and then edited, so the detail it
already carries survives the archive.

What this delta deliberately does not decide. It does not narrow which units a denial names - that
is task 6.2 of `deliver-a-secret-without-exposing-it`, and it changes which units a denial lists
rather than which files are compared. It defines no machine question and no record a report returns:
`answer-a-machine-question-as-a-record` owns that, and it is the neighbouring change in the order
`openspec/changes/INTEGRATION.md` states. It adds no plan field, so the relation between a read and
the value behind it stays where it is. It widens no delivery set: a declared read is already what
puts a machine in one (`lib/plan.nix:165-168`).

The conditions. `generatedOf` (`image/read.nix:435-454`) walks `entry.vars`, which
`lib/plan.nix:1080` fills from `placement.vars` through `varsRecord` (`lib/plan.nix:150-151`) over
`member.declaration.vars.generators` (`lib/resolve.nix:1476`, `:1696-1699`) - the entry's own
generators and nothing else. `hostPathsOf` (`:562-591`), `denialsOf` (`:602-635`, handed that walk
at `:704` and `:884`), `referencePaths` (`:809-814`) and the attachment description's `generated`
table (`:1169-1174`) all read it. A value another entry generates reaches a consumer through the
resolved read `readsRecord` publishes (`lib/plan.nix:239-283`), recorded as the reference
`{ path, secrecy }` the export's own `read` field carries (`lib/resolve.nix:2077-2083`). Evaluated
over a consumer declaring such a read and placed on the owner's machine, `mkPlan` answers
`applicable = true` with no error row, the value entry records that machine in `delivery`, and
`imageReader.hostPaths` answers `[ ]`, `imageReader.denials` under `strict` answers `[ ]` and the
attachment description carries `hostPaths = [ ]` - while the same file under the same profile earns
the owning entry one denial. No `BindReadOnlyPaths` line is rendered (`:640-642`, spent at `:1008`
and `:1115`) and no mount point is created (`image/default.nix:103-109`), so the path the unit's own
environment names is absent from the unit's view of the filesystem: outside `/run` a missing mount
point on a read-only squashfs, which `CLAUDE.md:396-398` records as `226/NAMESPACE`, and under
`util.varsRoot` (`lib/util.nix:345`) a bare `ENOENT` on the service manager's own tmpfs. Neither
names the value or the declaration.

The digest needs no rule of its own: `versionFor` takes it over `hostPathsOf`
(`image/read.nix:733-747`) and the requirement that owns it already names "the host paths it is
shown" (`openspec/specs/realiser/portable-service-image/spec.md:767-774`), so widening the set
widens the digest by construction. The one-time consequence is the one that requirement already
records for a widening (`:782-784`), and a scenario below states it rather than leaving it implicit.
-->

## MODIFIED Requirements

### Requirement: A path is shown only where bytes arrive at it

The reading SHALL show a host path for every generated file the entry's own declaration generates
and for every generated file a declared read of the entry names, and for no other. A declared read
is what puts the reading entry's machine in the value's delivery set, so the bytes of a value a read
names arrive at the machine before any entry is activated, and a unit shown no path for it is a unit
that cannot reach a file the plan told it to read.

The reading SHALL show a host path for a generated file only where the plan records that the file is
deployed, whether the entry generated it or read it. A value no machine receives has no bytes at its
path, so mounting it would mount nothing: the service manager refuses the namespace and the unit
fails with neither the value nor the declaration named.

An entry that owns such a value SHALL still be readable, and every other path it is shown SHALL be
unaffected. The undeployed file's path SHALL remain in the plan, because a site that opens it is a
row the planner reports.

A value the entry neither generates nor declares a read of SHALL be shown at no path, however many
of them the plan carries: the two statements are the whole set, and a value no statement of this
entry reaches is a value on a machine and not a value in this entry's view of it.

#### Scenario: An undeployed value is shown at no path

- **WHEN** an entry owning both a deployed and an undeployed generated value is read
- **THEN** the entry SHALL be shown the deployed file's path
- **AND** it SHALL be shown no path for the undeployed one
- **AND** the plan SHALL still record the undeployed file's path

#### Scenario: A value another entry generated is shown at its path

- **WHEN** an entry declaring a read of a deployed value another entry generates is read
- **THEN** it SHALL be shown that value's path at the record the value's own entry states
- **AND** the rendered unit files SHALL carry one bind for it
- **AND** the image SHALL carry a mount point for it

#### Scenario: A read of an undeployed value is shown at no path

- **WHEN** an entry declaring a read of a value the plan records as undeployed is read
- **THEN** it SHALL be shown no path for that value
- **AND** every other path it is shown SHALL be unaffected

#### Scenario: A value the entry neither generated nor read is shown at no path

- **WHEN** an entry is read from a plan carrying a deployed value of a third instance that this
  entry neither generates nor declares a read of
- **THEN** the entry SHALL be shown no path for it
- **AND** the set of paths it is shown SHALL be the same set as in a plan that value is absent from

### Requirement: A deployed value is denied to a unit only where its record cannot admit that unit's reader

The denial of a deployed generated file SHALL be read from the file's recorded ownership and mode
together with the account the unit runs under this profile, and SHALL NOT be read from the file's
secrecy alone.

The files compared SHALL be every deployed generated file the entry is shown, which is the entry's
own and the ones its declared reads name, and SHALL NOT be the entry's own alone. A file a unit is
shown is a file that unit can be denied, whichever declaration put it there, and a comparison over
half the shown files is a profile that denies nothing about the other half.

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

#### Scenario: A peer's value only its owner may read is denied to its reader

- **WHEN** an entry under a confining profile declares a read of a deployed value another entry
  generates, recorded as owned by `root` at mode `0400`
- **THEN** the realiser SHALL deny it naming the unit, the path, the record and the imposed account
- **AND** the denial SHALL be the same denial the owning entry earns for that file

#### Scenario: A peer's value a reader's group may read is not denied

- **WHEN** that value records a group the reading unit declares, at a mode with group read
- **THEN** the realiser SHALL deny nothing about it
- **AND** the entry SHALL be built with the value shown at the path the plan records

## ADDED Requirements

### Requirement: A value an entry is shown is one record however many statements reach it

A value the reading shows an entry SHALL be one record whatever number of the entry's statements
reach it, so a value named by two declared reads, or by a declared read and the entry's own
generator, SHALL be shown one path, bound by one directive, given one mount point, guarded once
before the attach writes anything and compared once against the confinement profile.

That one list SHALL be what every reading about a shown value asks: the host paths, the profile
denial table, the paths held to be references rather than closure roots, and the attachment
description a machine's operator reviews. A reading that walks the entry's own declaration instead
answers about half the files the unit is shown, and a description naming half of them describes a
different attachment.

The list SHALL carry one field set whichever statement reached a record, because a reader of it
may index any field, and SHALL carry the statement that reached each record so that a refusal
about one can name it.

#### Scenario: A value two reads name is shown once

- **WHEN** an entry declares two reads that resolve to one generated file of one provider
- **THEN** the entry SHALL be shown that file's path once
- **AND** each rendered unit file SHALL carry one bind for it
- **AND** the image SHALL carry one mount point for it

#### Scenario: A value an entry both generated and read is shown once

- **WHEN** an entry generates a value and also declares a read that resolves to that same file
- **THEN** the entry SHALL be shown its path once
- **AND** the record shown SHALL be the record the value's own entry states

#### Scenario: Every reading of a shown value asks one list

- **WHEN** an entry declaring a read of a deployed value another entry generates is read
- **THEN** the profile denial table, the reference paths and the attachment description SHALL each
  account for that value
- **AND** none of them SHALL account for a value the entry neither generates nor reads

#### Scenario: A read of a peer's value moves the entry's version digest

- **WHEN** one entry is read twice, differing only in declaring a read of a deployed value another
  entry generates
- **THEN** the two readings SHALL publish two different version digests
- **AND** the reading that declares the read SHALL be shown the value's path
- **AND** an apply of the deployment carrying that read SHALL replace the artifact once and report
  that nothing changed on the next apply

### Requirement: A shown value path with no delivered bytes is refused with the row that reports it

Where a declared read of an entry names a generated value's path and the plan's value records
account for no bytes delivered to that entry's machine at it, the reading SHALL refuse naming the
entry, the slot that named it and the path, and SHALL NOT omit the path silently. A path omitted
without a word is the failure this rule removes: the unit then starts, the machine names neither the
value nor the declaration, and a program that reads an unopenable credential as an absent one
reports success.

The refusal SHALL carry the identifier of the error row that reports the same condition, and the
layer that holds the whole plan SHALL produce that row before anything is built, the way the
profile denial of that layer already mirrors this realiser's. The condition SHALL be a fact about a
plan the reading was handed rather than a fact a deployment can declare: the delivery set is derived
from the reads that name a value, so a read naming a value the plan does not deliver is a plan whose
records disagree with each other.

A value the plan records as undeployed SHALL NOT be this refusal. It is shown at no path by the rule
that governs the shown set, and the row an operator receives for declaring a read of one is the
planner's own.

#### Scenario: A read naming a value the plan does not deliver there

- **WHEN** an entry is read from a plan whose read record names a generated value's path and whose
  value record for that path names another machine in its delivery set
- **THEN** the reading SHALL refuse naming the entry, the slot and the path
- **AND** the layer that holds the plan SHALL report the same condition as an error row
- **AND** no artifact of that entry SHALL be built

#### Scenario: A read naming a path no value record carries

- **WHEN** an entry is read from a plan whose read record names a generated value's path that no
  value record of the plan declares
- **THEN** the reading SHALL refuse naming the entry, the slot and the path
- **AND** the refusal SHALL NOT be a missing attribute or an evaluation error

#### Scenario: The unaccounted refusal is preceded by its row

- **WHEN** the refusals this realiser can make are crossed against the rows the producing layers
  build
- **THEN** this refusal SHALL name a row identifier a producing layer produces
- **AND** the row and the refusal SHALL state one condition, computed by the reading rather than
  restated in two places
