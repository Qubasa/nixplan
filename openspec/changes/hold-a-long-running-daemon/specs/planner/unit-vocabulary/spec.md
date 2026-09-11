<!--
A delta against `planner/unit-vocabulary`, whose base text lives in the unarchived change
`emit-systemd-portable-service-images`. `openspec/specs/` is empty in this repository, so the base
text is read from there.

Every requirement below is ADDED, and deliberately. The enumeration in `A unit carries a typed
vocabulary and nothing else` is what this change widens, and restating it here would put a second
edited copy of that block in a second unarchived change - the reason
`order-a-cycle-by-its-strong-components` gives for the same decision. The first requirement below
therefore names that requirement and states the two fields it gains; everything else about it - the
allow-list reading, the absent-rather-than-defaulted rule, the unit reference rule - is unchanged and
is what the new fields are read under.

`A configuration file names its bytes rather than carrying them` is left alone: its dispositions are
unchanged, and what this change adds about them - that two of the three hold bytes that exist before
the machine does anything - is a requirement of its own below.

The conditions: `lib/module.nix:58-70` carries eleven fields and no restart policy;
`lib/interface.nix:421-432` accepts an extension declaring arbitrary `fields`, so `restart` written
as an extension field is a deployment the planner calls applicable and `image/read.nix:406` refuses.
-->

## ADDED Requirements

### Requirement: The unit vocabulary carries a restart policy

The vocabulary `A unit carries a typed vocabulary and nothing else` enumerates SHALL additionally
carry `restart` and `restartSec`, read under every rule that requirement states: each is typed, a
value failing its type is an error row naming the module, the unit, the field and the type, and a
field a unit did not declare is absent from the record rather than recorded as a null or as a service
manager's default.

`restart` SHALL take one of `no`, `on-failure`, `on-abnormal` and `always`, and a value outside that
domain SHALL be an error row naming the module, the unit, the value and the four it may take. The
domain SHALL be the planner's own rather than a service manager's spelling, so that a renderer maps
it to what its service manager calls the same thing.

`restartSec` SHALL be a duration, and SHALL be recordable only beside a `restart`: a unit declaring a
delay and no policy SHALL be an error row naming the module and the unit, because a delay alone
changes nothing about a unit that is never restarted.

Both fields SHALL be part of the entry's key, as every other unit field is.

#### Scenario: A unit that is restarted when it fails

- **WHEN** a module declares a unit with `restart = "on-failure"` and a `restartSec`
- **THEN** the plan SHALL record both fields on that unit
- **AND** a unit of the same entry that declared neither SHALL record neither

#### Scenario: A restart policy outside its domain

- **WHEN** a module declares `restart` with a value that is none of the four the domain admits
- **THEN** the planner SHALL emit an error row naming the module, the unit, the value and the four
- **AND** the plan SHALL NOT record the failing value

#### Scenario: A restart delay with no policy

- **WHEN** a module declares `restartSec` on a unit that declares no `restart`
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL NOT record the delay

#### Scenario: A unit that declares no policy keeps its key

- **WHEN** an entry's units declare neither field
- **THEN** the entry's key SHALL be what it was before the vocabulary carried them
- **AND** the plan SHALL record neither field on any unit

### Requirement: A restart policy that contradicts the unit's shape is a row

A unit's restart policy SHALL be read against the shape the unit already declared, and a policy that
contradicts it SHALL be an error row rather than a value a renderer has to reconcile.

A `oneShot` unit declaring `restart = "always"` SHALL be `unit-restart-contradicts-one-shot`, naming
the module and the unit: a unit that applies and exits successfully is restarted for as long as it
keeps succeeding. `restart = "on-failure"` on a `oneShot` unit SHALL NOT be a row - a job that failed
and may be retried is a legitimate shape.

A unit declaring a `schedule` and any `restart` but `no` SHALL be `unit-restart-on-scheduled`, naming
the module and the unit: what decides when a scheduled unit runs is its schedule, and a restart
policy on it is a second, unstated schedule.

#### Scenario: A one-shot unit asking to be restarted always

- **WHEN** a module declares a unit with `oneShot` and `restart = "always"`
- **THEN** the planner SHALL emit `unit-restart-contradicts-one-shot` naming the module and the unit
- **AND** the plan SHALL NOT record the policy

#### Scenario: A one-shot unit retried on failure

- **WHEN** a module declares a unit with `oneShot` and `restart = "on-failure"`
- **THEN** the planner SHALL emit no row
- **AND** the plan SHALL record the policy

#### Scenario: A scheduled unit asking for a restart policy

- **WHEN** a module declares a unit with a `schedule` and `restart = "on-failure"`
- **THEN** the planner SHALL emit `unit-restart-on-scheduled` naming the module and the unit
- **AND** the plan SHALL NOT record the policy

### Requirement: A configuration file's disposition states when its bytes exist

The plan SHALL let a reader tell, from a configuration file's record alone, whether its bytes exist
before anything runs on the machine. A `source` file's bytes are a store path. A `render` list of
nothing but `text` items is bytes the plan itself holds, which is why that case carries
`contentHash`. A `render` list carrying any `ref` names a path on a machine, and its bytes therefore
do not exist until the referenced file has been delivered.

No new field SHALL be added to say this: the disposition and the presence of a `ref` already do, and
a realiser that cannot assemble bytes SHALL decide what it accepts from them. A file whose bytes
exist at build time SHALL NOT be refused by a realiser on the grounds of having no assemble step.

#### Scenario: A file whose bytes exist at build time

- **WHEN** a configuration file records a `source` store path, or a `render` list of `text` items only
- **THEN** the record SHALL permit a reader to conclude that the bytes exist before the machine is
  dialled
- **AND** no field beyond the disposition and the recipe SHALL be needed to conclude it

#### Scenario: A file whose bytes exist only on the machine

- **WHEN** a configuration file's `render` list carries a `ref`
- **THEN** the record SHALL name the reference path
- **AND** a reader SHALL be able to conclude that the assembled bytes exist on no machine until that
  path has been written
