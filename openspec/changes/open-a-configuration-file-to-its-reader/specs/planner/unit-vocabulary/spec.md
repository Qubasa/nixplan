<!--
A delta against `planner/unit-vocabulary`, whose base text lives in the unarchived changes
`emit-systemd-portable-service-images` and `hold-a-long-running-daemon`. `openspec/specs/` is empty
in this repository, so the base text is read from those two.

Every requirement below is ADDED, for the reason `hold-a-long-running-daemon` gives for the same
decision: the enumeration in `A unit carries a typed vocabulary and nothing else` is what this
change widens, and restating that block would put a second edited copy of it in a second unarchived
change. The first requirement below names it and states the fields it gains; everything else about
it - the allow-list reading, the absent-rather-than-defaulted rule, the type-mismatch row - is
unchanged and is what the new fields are read under.

`A backend extension is typed and refused when it does not apply` is left alone: an extension may
still declare a field of any name, and what changes is that one of those names may now also be a
vocabulary field, which the second requirement below refuses on one unit.

The conditions: the vocabulary carries thirteen fields and none of them is a directory or a
condition (`lib/module.nix:58-72`); the three directory kinds exist only as names in a realiser's
directive table (`image/read.nix:82-84`), so the directory a unit is given is a fact only a
systemd-tagged extension can state; and nothing in either directive table names the `Condition*`
family (`image/read.nix:76-94,101-116`).
-->

## ADDED Requirements

### Requirement: The unit vocabulary carries the directories a unit is given

The vocabulary `A unit carries a typed vocabulary and nothing else` enumerates SHALL additionally
carry the three kinds of directory a service manager creates for a unit and owns on its behalf -
state, runtime and cache - and one mode per kind. Each SHALL be read under every rule that
requirement states: each is typed, a value failing its type is an error row naming the module, the
unit, the field and the type, and a field a unit did not declare is absent from the record rather
than recorded as a service manager's default.

A kind SHALL take any number of directories, because a unit may be given more than one, and a
directory SHALL be named relative to the root its kind implies: the kind decides where the
directory lives and a name that states a root of its own is a value failing its type. A mode SHALL
be one mode per kind rather than one per directory, because that is the grain at which a service
manager applies one.

A mode SHALL be recordable only beside a directory of its own kind: a unit declaring a mode for a
kind it declares no directory of SHALL be an error row naming the module and the unit, because a
mode alone creates nothing. Every field SHALL be part of the entry's key, as every other unit field
is.

#### Scenario: A unit declaring a state directory and its mode

- **WHEN** a module declares a unit with one state directory and a mode for that kind
- **THEN** the plan SHALL record both on that unit
- **AND** a unit of the same entry that declared neither SHALL record neither

#### Scenario: A directory mode with no directory of its kind

- **WHEN** a module declares a cache directory mode on a unit that declares no cache directory
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL NOT record the mode

#### Scenario: A directory name that is not relative

- **WHEN** a module declares a state directory whose name states a root of its own
- **THEN** the planner SHALL emit an error row naming the module, the unit, the field and the type
- **AND** the plan SHALL NOT record the failing name

#### Scenario: A unit declaring no directory keeps its key

- **WHEN** an entry's units declare none of the six fields
- **THEN** the entry's key SHALL be what it was before the vocabulary carried them
- **AND** the plan SHALL record none of them on any unit

### Requirement: A directory a unit declares is the same claim however it was declared

A directory a unit declares SHALL be a claim that unit's entry makes on its machine, whether the
declaration was the vocabulary's or a backend extension's, so that two entries placed on one
machine declaring one directory earn the warning the planner already reports for a shared unit
directory either way. A claim SHALL keep carrying the kind it was declared under, so a state
directory and a runtime directory of one name are two claims and not a collision.

One kind declared both in the vocabulary and in a backend extension application on one unit SHALL
be an error row naming the module, the unit and the kind, and the plan SHALL record neither
declaration: a renderer handed two statements about one directory has no way to choose, and the
deployment can say it once.

#### Scenario: Two entries sharing a directory declared through the vocabulary

- **WHEN** two entries placed on one machine each declare the same runtime directory through the
  vocabulary
- **THEN** the planner SHALL emit the warning it reports for a shared unit directory, naming both
  entries, the machine and the directory
- **AND** the deployment SHALL still build

#### Scenario: A state directory and a runtime directory of one name

- **WHEN** two entries placed on one machine declare one name, one as a state directory and one as
  a runtime directory
- **THEN** the planner SHALL emit no row, the two being two directories on the machine

#### Scenario: One directory kind declared twice

- **WHEN** a module declares a unit with a state directory in the vocabulary and a state directory
  in a backend extension application
- **THEN** the planner SHALL emit an error row naming the module, the unit and the kind
- **AND** the plan SHALL record neither declaration

### Requirement: A unit may state a path its start is conditional on

A unit SHALL be able to state that it starts only while a path is absent, or only once a path is
present, and each SHALL be an absolute path. A unit MAY state one of each, in which case both hold.
A unit whose condition does not hold SHALL be skipped rather than failed, so a unit ordered after
it and requiring it still starts: the fact stated is when the unit has work to do, not whether the
machine is fit to run it.

One path stated as both present and absent SHALL be an error row naming the module, the unit and
the path, because it is a unit that can never start, and the plan SHALL record neither condition.

#### Scenario: A unit that starts only while a path is missing

- **WHEN** a module declares a unit that starts only while a path is absent
- **THEN** the plan SHALL record the path and the polarity on that unit
- **AND** the polarity SHALL be recorded as the planner's own fact rather than as a service
  manager's spelling of it

#### Scenario: A unit that starts only once a path exists

- **WHEN** a module declares a unit that starts only once a path is present
- **THEN** the plan SHALL record the path and that polarity
- **AND** a unit of the same entry that declared neither SHALL record neither

#### Scenario: A condition that contradicts itself

- **WHEN** a module declares one path as both present and absent on one unit
- **THEN** the planner SHALL emit an error row naming the module, the unit and the path
- **AND** the plan SHALL record neither condition

#### Scenario: A condition path that is not absolute

- **WHEN** a module declares a condition over a path that is not absolute
- **THEN** the planner SHALL emit an error row naming the module, the unit, the field and the type
- **AND** the plan SHALL NOT record the failing path
