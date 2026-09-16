<!--
A delta against `planner/unit-vocabulary`, whose current text is
`openspec/specs/planner/unit-vocabulary/spec.md`. Everything here is ADDED. The base requirement
`A unit carries a typed vocabulary and nothing else` is not restated: the two requirements that
already widened its enumeration, `The unit vocabulary carries a restart policy` and `The unit
vocabulary carries the directories a unit is given`, did it by adding a requirement that names the
enumeration and states the fields it additionally carries, and this follows them rather than
recopying a block that is unchanged.

The conditions. `lib/module.nix:83-100` is the whole vocabulary: `command`, `env`, `after`,
`requires`, `user`, `oneShot`, `remainAfterExit`, `schedule`, `timeout`, `stopCommand`,
`reloadCommand`, `restart`, `restartSec`, the two condition polarities and the six directory fields
`lib/module.nix:62-81` derives. None of them says whether the service works, so a unit whose start
job succeeds and whose process then crash-loops is recorded as a running service and nothing
downstream can tell. `flakelet` gates an activation on exactly one file and rolls the generation
back where it fails (`docs/design.md` "Health checks are units" and update-flow step 5,
`docs/reference/service-module.md` "Activation semantics", at the locked revision), so the missing
fact is the entry's and this is where it belongs.

The pair and the rows read the existing idiom. `restart` is four values stated once at
`lib/atoms.nix:17-22` and read by both the atom (`lib/atoms.nix:99`) and the row about a value
outside the domain; `restartSec` is recordable only beside a `restart`
(`lib/module.nix:1119`); a policy contradicting the unit's own shape is a row rather than a value a
renderer reconciles (`lib/module.nix:1128`, `:1137`); a directory mode is refused without its
directory (`lib/module.nix:1147`) and one kind declared twice records neither statement
(`lib/module.nix:1159`).

The scans are asked nothing new. `lib/plan.nix:566-573` hands the closure scan the unit record with
`env` and `extends` removed, so a store path or a value path named in a new field is reached by
existing (`lib/plan.nix:682-710`, `:635-677`), and `lib/module.nix:1042-1043` walks every string of
the record at any depth for `unit-value-newline`. `lib/plan.nix:815-820` reads directory claims off
the declared fields and the extension applications, which is why the derived unit the realisers
render declares none.

`lib/atoms.nix:80-82` admits `0` as a duration, and `TimeoutStartSec=0` is how systemd spells no
bound at all, which is why a zero bound is a row of its own rather than a value the type already
refused.
-->

## ADDED Requirements

### Requirement: The unit vocabulary carries a probe and its bound

The vocabulary `A unit carries a typed vocabulary and nothing else` enumerates SHALL additionally
carry `probe`, the command that decides whether the unit is serving what it exists to serve, and
`probeTimeout`, the bound on how long that command may take. Each SHALL be read under every rule
that requirement states: each carries a type, a value failing its type SHALL be an error row naming
the module, the unit, the field and the type it failed, and a field a unit did not declare SHALL be
absent from the record rather than recorded as a null or as a service manager's default.

`probe` SHALL be a command, typed as every other command of the vocabulary is, so that what a probe
does is the module's and the vocabulary states only that it is one word-bearing command line.

`probeTimeout` SHALL be a duration in the vocabulary's own spelling. It SHALL be recordable only
beside a `probe`, and a `probe` SHALL be recordable only beside a `probeTimeout`: each direction
SHALL be an error row naming the module and the unit, and neither field SHALL be recorded where the
other is missing. The second direction differs from the restart pair on purpose - a policy with no
delay is a complete statement, while an unbounded probe is a start job whose only bound would be a
service manager's default, and a default this vocabulary does not record is a fact no reader can
see.

A `probeTimeout` that spells zero SHALL be an error row naming the module, the unit and the value.
A service manager reads a zero duration as no bound at all, so the value that looks like the
tightest bound is the absence of one. The check SHALL cover every spelling of zero the duration type
admits rather than the literal `0`, and the spelling SHALL have one home that both the type layer
and the row read, as the restart domain does.

Both fields SHALL be part of the entry's key, as every other unit field is.

#### Scenario: A unit that says how it is probed

- **WHEN** a module declares a long-running unit with a `probe` and a `probeTimeout`
- **THEN** the plan SHALL record both fields on that unit
- **AND** a unit of the same entry that declared neither SHALL record neither
- **AND** the planner SHALL emit no row

#### Scenario: A probe whose value is not a command

- **WHEN** a module declares a `probe` that is not a command, or a `probeTimeout` that is not a
  duration
- **THEN** the planner SHALL emit an error row naming the module, the unit, the field and the type
  it failed
- **AND** the plan SHALL NOT record the failing value

#### Scenario: A probe with no bound

- **WHEN** a module declares a `probe` on a unit that declares no `probeTimeout`
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL record neither field
- **AND** the row SHALL say that the bound is what keeps a hanging probe from holding the activation

#### Scenario: A bound with no probe

- **WHEN** a module declares a `probeTimeout` on a unit that declares no `probe`
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL NOT record the bound

#### Scenario: A bound that spells no bound

- **WHEN** a module declares a `probeTimeout` whose value spells zero, in any spelling the duration
  type admits
- **THEN** the planner SHALL emit an error row naming the module, the unit and the value
- **AND** the plan SHALL record neither field
- **AND** a bound of one second SHALL earn no row

#### Scenario: An entry that declares no probe keeps its key

- **WHEN** no unit of an entry declares either field
- **THEN** the entry's key SHALL be what it was before the vocabulary carried them
- **AND** the plan SHALL record neither field on any unit

### Requirement: A probe the unit's shape cannot carry is a row

A probe SHALL be read against the shape the unit already declared and against the entry it belongs
to, and a probe neither can carry SHALL be an error row rather than a file nothing starts.

A `oneShot` unit declaring a `probe` SHALL be an error row naming the module and the unit: a job
that applies and exits reports whether it worked in its own exit status, and a second job ordered
after it answers a question the first already answered.

A unit declaring a `schedule` and a `probe` SHALL be an error row naming the module and the unit:
what decides when a scheduled unit runs is its schedule, the unit is not running between elapses,
and a probe of it would report the schedule rather than the service.

Two units of one entry declaring a probe SHALL be an error row naming the module and both units, and
neither statement SHALL be recorded. An entry is activated and rolled back as one, so whether it is
serving is one question with one answer, and a second probe would be a second answer only one of
which any realiser starts.

A probe on a unit declaring a restart policy SHALL be no row. A policy says what happens after the
service stops and a probe says whether it is serving while it runs, and the two together are the
shape this change exists for.

#### Scenario: A one-shot unit asking to be probed

- **WHEN** a module declares a unit with `oneShot` and a `probe`
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL record neither the probe nor its bound

#### Scenario: A scheduled unit asking to be probed

- **WHEN** a module declares a unit with a `schedule` and a `probe`
- **THEN** the planner SHALL emit an error row naming the module and the unit
- **AND** the plan SHALL record neither the probe nor its bound

#### Scenario: Two units of one entry declaring a probe

- **WHEN** two units of one entry each declare a `probe`
- **THEN** the planner SHALL emit an error row naming the module and both units
- **AND** the plan SHALL record no probe on either unit
- **AND** the plan SHALL still record both units and the entry

#### Scenario: A probed unit that is also restarted on failure

- **WHEN** a module declares a long-running unit with `restart = "on-failure"`, a `restartSec`, a
  `probe` and a `probeTimeout`
- **THEN** the planner SHALL emit no row
- **AND** the plan SHALL record all four fields on that unit

### Requirement: A probe is a command and a bound and nothing else

The plan SHALL record what to run and how long it may take, and no third fact about health. No plan
field SHALL say whether a unit is healthy, ready or live: the plan is a function of a declaration and
health is a fact about a running machine, so a field for it would be the planner restating an answer
it cannot have. The planner SHALL evaluate no probe, SHALL run no probe, and SHALL derive no
ordering, no enablement and no delivery decision from one.

The vocabulary SHALL carry no repeat interval, no failure threshold and no account of the probe's
own. A repeating probe is a service manager's watchdog or a second schedule, neither of which this
vocabulary carries, and an account beside a probe is a second identity on a unit the vocabulary
reads as one unit's. Liveness stays with `restart`, which already says what happens when the service
stops.

A probe-shaped key the vocabulary does not carry SHALL be `implementation-unknown-key` under the
rule that already covers an unrecognised key, and SHALL NOT be discarded.

What the plan records SHALL be enough for each realiser to decide what starting the probe means, and
the plan SHALL take none of those decisions: it says neither which file a realiser derives, nor
whether that file is enabled, nor what a realiser does when the probe fails.

#### Scenario: The plan says how to probe and never whether it is healthy

- **WHEN** an entry's unit declares a `probe` and a `probeTimeout`
- **THEN** the entry SHALL record exactly those two fields for that unit
- **AND** the plan SHALL carry no field stating a health, readiness or liveness state
- **AND** the plan SHALL carry no field stating whether the probe is enabled

#### Scenario: A probe adds no unit to the plan

- **WHEN** an entry's unit declares a `probe`
- **THEN** the entry's recorded unit set SHALL be exactly the units the module declared
- **AND** no unit reference of the entry SHALL have been rewritten

#### Scenario: A probe interval is not a vocabulary field

- **WHEN** a module declares a probe interval or a failure threshold on a unit
- **THEN** the planner SHALL emit `implementation-unknown-key` naming the key and the vocabulary
- **AND** the key SHALL NOT be recorded

### Requirement: A probe is read by every scan a unit's strings are read by

A probe is a string of the unit record, so every scan the record already goes through SHALL reach it
with no scan extended for it. A store path a probe names and the entry's declared closure roots do
not contain SHALL be `closure-path-undeclared` naming the entry and the unit's own site. A generated
value's path a probe names on a machine the value's delivery set does not contain SHALL be
`vars-path-off-delivery-set`. A line break anywhere in the probe or its bound SHALL be
`unit-value-newline` naming the field path.

No scan SHALL be given a list of fields to read, because a list is what a field added later is left
out of.

#### Scenario: A probe naming an undeclared store path

- **WHEN** a unit's `probe` names a store path the entry's declared closure roots do not contain
- **THEN** the planner SHALL emit `closure-path-undeclared` naming the entry, the path and the unit
- **AND** declaring that path as a closure root SHALL remove the row

#### Scenario: A probe naming a value the machine does not receive

- **WHEN** a unit's `probe` names a generated value's path on a machine the value's delivery set
  does not contain
- **THEN** the planner SHALL emit `vars-path-off-delivery-set` naming the entry, the path and the
  machine

#### Scenario: A probe carrying a line break

- **WHEN** a unit's `probe` holds a value containing a line break
- **THEN** the planner SHALL emit `unit-value-newline` naming the field path inside the unit record
- **AND** the entry SHALL still be planned
