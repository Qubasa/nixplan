# planner/machine-platform Specification

## Purpose
Defines what a machine declares about itself — the system it runs and the service manager that runs its units — and the form the plan records those facts in. An artifact built for a placement, whether an image, a closure or a rendered unit, has to be built for a target, and a placement carries no answer today. This capability makes the target a typed fact of the plan rather than an assumption of whatever consumes it, and makes a module's declared `platforms` meet it.

## Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager`, an optional
microarchitecture and an optional statement of the host resources the machine already holds, and
SHALL refuse any other key with an error row naming the registry file. A selected machine that
declares no `system`, or no `serviceManager`, SHALL produce an error row naming the machine and the
registry file, because a placement on it has no derivable target. The plan SHALL still be emitted in
that case, containing the machine's entry and every entry placed on it, so that a deployment
mid-migration is diagnosable rather than unevaluable.

A machine's key SHALL be a function of the facts the plan records about the machine - what a consumer
dials, what a placement selects on, what a target is elaborated from - so that changing a machine's
architecture re-keys every entry placed on it. A statement of what the machine already holds SHALL
NOT be one of those facts and SHALL NOT enter that key, nor the key of any entry or generated value
placed on the machine: it says nothing about what is built for the machine, and re-keying an entry on
account of it would ask for a redelivery, and a generated value for a regeneration, of bytes that are
still correct.

#### Scenario: A machine that reserves a port keys as it did

- **WHEN** a machine's declaration gains a statement of the resources it already holds and nothing
  else changes
- **THEN** the machine's key SHALL be the key it had
- **AND** every entry placed on that machine SHALL keep its key
- **AND** every generated value delivered to that machine SHALL keep its key

#### Scenario: A fully declared machine

- **WHEN** the registry declares a machine with an `address`, a `tags` entry, a `system` and a
  `serviceManager`
- **THEN** the planner SHALL emit no registry row
- **AND** the machine's plan entry SHALL record all four values

#### Scenario: A machine omits its address

- **WHEN** the registry declares a machine with no `address` and a placement selects it
- **THEN** the planner SHALL emit one error row naming the machine, the address as the key it did
  not declare, and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine omits its system

- **WHEN** the registry declares a machine with no `system` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine omits its service manager

- **WHEN** the registry declares a machine with no `serviceManager` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL contain the machine's own record and no entry placed on it

#### Scenario: A machine declares an address that is not a name

- **WHEN** the registry declares an `address` as a value of some other kind and a placement selects
  that machine
- **THEN** the planner SHALL emit the row about the malformed declaration and the row about the
  incomplete target
- **AND** no entry SHALL be planned for that machine

#### Scenario: A machine changes architecture

- **WHEN** a machine's declared `system` changes and nothing else does
- **THEN** the machine's key SHALL change
- **AND** every entry placed on that machine SHALL be re-keyed

### Requirement: The plan records a reduced elaboration of a platform, never a raw one

A machine's declared `system` SHALL be recorded in the plan as a reduced platform record: a fixed allow-listed projection naming `system`, `config`, `libc`, `useLLVM`, `linuxArch`, `parsed.cpu`, `parsed.kernel`, `parsed.abi` without its `assertions`, and the codegen group `gcc` — the fields a compiler invocation spends, `abi`, `arch`, `cmodel`, `cpu`, `float`, `float-abi`, `fpu`, `long-double-format`, `mode`, `strict-align`, `thumb` and `tune` — recorded whenever the elaboration carries any of them and absent when it carries none. The record SHALL contain no function at any depth, because a plan contains none — a projection that removes only the functions at its top level SHALL NOT satisfy this.

The record SHALL be what a cross build spends and nothing derivable from it. The `is*` predicates SHALL NOT appear in it: each is a function of `parsed` — `isLinux` is `parsed.kernel.name == "linux"`, `is64bit` is `parsed.cpu.bits == 64` — so recording them would put seventy-five derived booleans in every entry and in every entry's key while telling a consumer nothing `parsed` does not. A consumer that wants one SHALL derive it.

A field the projection does not name SHALL NOT appear in the record even when the underlying platform elaboration grows one, so that an upstream addition requires a decision rather than silently entering every entry's key. A `gcc` field the pinned platform set carries and the projection does not name SHALL fail the library's own tests rather than being dropped from every record. Two machines declaring one `system` SHALL produce equal platform records. This change SHALL record the microarchitecture and SHALL NOT build anything that spends it.

#### Scenario: A platform record is serialisable

- **WHEN** a plan containing a placed entry is serialised to JSON
- **THEN** every platform record in it SHALL serialise without loss
- **AND** no platform record SHALL contain a function at any depth, including inside a nested attribute set or a list

#### Scenario: The upstream elaboration carries a nested function

- **WHEN** the platform elaboration this record is projected from carries a function nested below its top level
- **THEN** the projection SHALL exclude it
- **AND** the plan SHALL still serialise

#### Scenario: An aarch64 machine's platform record

- **WHEN** a machine declares `aarch64-linux` and a placement selects it
- **THEN** its platform record SHALL name `aarch64` as its `parsed.cpu` and `linux` as its `parsed.kernel`
- **AND** the record SHALL carry the facts a cross build is configured with — the target triple, the libc, the kernel's own architecture name and the parsed abi — and no `is*` predicate

#### Scenario: A platform carries its own codegen defaults

- **WHEN** a machine declares a `system` whose platform elaboration carries codegen defaults and no microarchitecture
- **THEN** its platform record SHALL carry those defaults, including fields beyond `gcc.arch` and `gcc.tune`
- **AND** a declared microarchitecture SHALL replace that group rather than merge into it, because the elaboration applies its arguments over the platform's own defaults

#### Scenario: A machine declares a microarchitecture

- **WHEN** a machine declares a `system` and a microarchitecture
- **THEN** its platform record SHALL name the microarchitecture in `gcc.arch` and `gcc.tune`
- **AND** no artifact the planner describes SHALL be specialised for it

#### Scenario: Two machines of one system

- **WHEN** two machines declare the same `system` and no microarchitecture
- **THEN** their platform records SHALL be equal

### Requirement: A placement is refused when the module cannot run on the machine

A module's declared `platforms` SHALL be crossed against the `system` of every machine a placement selects. A placement whose machine's `system` appears in no `platforms` entry of the placed module SHALL produce a `placement-platform-mismatch` error row naming the instance, the member, the machine, the machine's system and the systems the module declares. A module that declares no `platforms` SHALL be treated as running on every system, so that a module which never had to care is not made to.

The row SHALL be a refusal and SHALL NOT be a filter: the entry SHALL still appear in the plan for the placement the deployment asked for, so that an operator sees what they wrote and why it cannot run rather than an entry quietly missing.

#### Scenario: A module is placed on a system it supports

- **WHEN** a module declaring a `platforms` entry is placed on a machine running that system
- **THEN** the planner SHALL emit no `placement-platform-mismatch` row

#### Scenario: A module is placed on a system it does not support

- **WHEN** a module declaring exactly one `platforms` entry is placed on a machine running another system
- **THEN** the planner SHALL emit a `placement-platform-mismatch` error row naming the instance, the member, the machine, the machine's system and the systems the module declares
- **AND** the plan SHALL still contain that placement's entry

#### Scenario: A module declares no platforms

- **WHEN** a module declaring no `platforms` is placed on any machine
- **THEN** the planner SHALL emit no `placement-platform-mismatch` row

#### Scenario: One tag selects two systems

- **WHEN** a placement selects by a tag matching two machines of different systems and the placed module declares only one of those systems
- **THEN** the planner SHALL emit exactly one `placement-platform-mismatch` row, naming the machine whose system the module does not declare
- **AND** the entry for the supported machine SHALL carry no such row

### Requirement: An entry records the target it was planned for

A placed entry SHALL record the platform record of the machine it is placed on and that machine's `serviceManager`, and both SHALL be part of the entry's key. A downstream consumer SHALL be able to determine an entry's target from the entry alone, without consulting the machine registry. A placement's target SHALL be derived from the machine the placement selected, and the same target SHALL be what a unit extension's backend is checked against.

An entry for a member no placement selects SHALL record neither a platform record nor a `serviceManager`.

#### Scenario: One service placed on two systems

- **WHEN** one service of one instance is placed on two machines declaring different systems
- **THEN** the plan SHALL contain two entries, each recording its own machine's platform record
- **AND** the two entry keys SHALL differ

#### Scenario: One service placed on two service managers

- **WHEN** one service of one instance is placed on a machine declaring `systemd` and a machine declaring `launchd`
- **THEN** each entry SHALL record the `serviceManager` of the machine it is placed on
- **AND** the two entry keys SHALL differ

#### Scenario: An unplaced member

- **WHEN** no placement selects a member
- **THEN** its entry SHALL record no platform record
- **AND** SHALL record no `serviceManager`
- **AND** SHALL record no machine

### Requirement: A placement onto a machine whose target is incomplete is not planned

A machine whose target is incomplete SHALL be dropped from what every selector of the deployment
places on, whether the selector named the machine or named a tag the machine carries, and SHALL be
dropped in the stratum the row is produced in, before any plan key is built. Every other machine a
selector matched SHALL be planned as declared, so one machine that has not been told where it lives
SHALL NOT cost the entries of the machines that have.

The row SHALL be produced for the machine the deployment's selectors matched, whether or not any
entry survived on it, and SHALL be one row for one machine however many placements selected it. A
member whose selector matched only machines that were dropped SHALL produce the registry's row and
SHALL NOT also be reported as a member the deployment placed nowhere: the selector matched, and what
it matched is what was refused.

#### Scenario: A tag selects one unaddressed machine beside two addressed ones

- **WHEN** a member is placed by a tag that three machines carry and one of the three declares no
  address
- **THEN** the plan SHALL contain the two entries for the addressed machines and no entry for the
  third
- **AND** the table SHALL carry exactly one row about that machine

#### Scenario: A member placed only onto an unaddressed machine

- **WHEN** a member's selector matches exactly one machine and that machine declares no address
- **THEN** the planner SHALL emit the row naming the machine and the registry file
- **AND** SHALL NOT emit a row saying the member was placed nowhere
- **AND** the member SHALL be recorded in the plan as an unplaced member carrying its selector

#### Scenario: A machine nobody places on declares no address

- **WHEN** the registry declares a machine with no `address` and no selector of the deployment
  matches it
- **THEN** the planner SHALL emit no row about it
- **AND** the deployment SHALL be applicable

### Requirement: An implementation is handed a target carrying every field a module may render

The target a placed entry records and an implementation is handed SHALL carry the machine's address,
its platform record and its service manager, all three, for every entry the plan contains. The
planner SHALL NOT compose a target out of the subset of those facts a machine happened to declare:
an implementation reading a field of a partial target is a missing attribute, which no diagnostics
row can be produced for and no guard can recover, so the entry that would hand one over SHALL NOT
exist.

An implementation SHALL therefore be able to read the address, the platform record and the service
manager of its own entry without guarding for their presence.

#### Scenario: Every planned entry records a target with every field

- **WHEN** a deployment placing members across several machines is planned
- **THEN** every entry of the plan that records a target SHALL record an address, a platform record
  and a service manager in it

#### Scenario: A module needs no guard to render an address

- **WHEN** an implementation renders the address of its own entry with no test for its presence, and
  the deployment places it on every machine of the registry
- **THEN** the planner SHALL emit no row about the module
- **AND** each entry's rendered value SHALL carry the address its own machine declared

### Requirement: A machine declares the host resources it already holds

A machine SHALL be able to state the host resources it already holds outside the deployment: at
minimum the ports it listens on, each with its protocol, and the host paths it owns. The statement
SHALL be optional, and its absence SHALL mean that nothing is stated and nothing is checked, so that
a registry written before the field existed keeps producing the plan and the table it produced. A
machine stating an empty set of resources SHALL produce exactly what a machine stating none produces:
a machine that holds nothing and a machine that says nothing are checked alike, and because no plan
field records the statement no reader can tell the two apart.

A stated resource SHALL be read with the tolerance the deployment's own half is read with: a value of
the wrong kind SHALL be a row naming the machine and the registry file, and the rest of the
deployment SHALL still be read. A port SHALL be stated as a protocol and a number, read the way a
module's own port claim is read, so that there is one protocol domain and not two.

The statement SHALL be a declaration and never a probe. The planner SHALL NOT read the machine, open
a connection to it, or infer a reservation from anything it did not declare, so that a plan is a
function of the deployment's text and of nothing about the host the evaluation runs on. A reservation
the planner discovered for itself SHALL remain out of scope until the excluded lifecycle construct
lands, that being the construct for a value that is not knowable at evaluation.

No realiser SHALL read the statement. It SHALL open no port, render no socket unit, create no file
and appear in no artifact: the plan records it nowhere, and what it changes is only which diagnostics
the planner produces.

#### Scenario: A machine reserves a port and a host path

- **WHEN** a machine declares that it already holds a port with a protocol and a host path, and no
  placed entry claims either
- **THEN** the planner SHALL emit no row about the machine's declaration
- **AND** the plan SHALL record the machine, the entries placed on it and the reservation nowhere

#### Scenario: A machine states no reservation

- **WHEN** a registry declares machines and none of them states the resources it holds
- **THEN** the plan SHALL be the plan that registry produced before the field existed, field for
  field
- **AND** the diagnostics table SHALL be unchanged

#### Scenario: A reservation of the wrong shape

- **WHEN** a machine states the resources it holds as a value of the wrong kind
- **THEN** the planner SHALL emit an error row naming the machine, the field and the kind the reading
  needs
- **AND** every other machine of the registry and every entry placed on this one SHALL still be read

#### Scenario: A reservation is a declaration and not a probe

- **WHEN** two otherwise identical deployments reserve two different host paths, one that exists on
  the evaluating host and one that does not
- **THEN** both SHALL produce the same rows about the reservation, namely none
- **AND** neither evaluation SHALL depend on anything outside the deployment's own declarations
