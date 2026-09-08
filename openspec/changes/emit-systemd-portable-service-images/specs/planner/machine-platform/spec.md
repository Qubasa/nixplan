## Purpose

Defines what a machine declares about itself — the system it runs and the service manager that runs its units — and the form the plan records those facts in. An artifact built for a placement, whether an image, a closure or a rendered unit, has to be built for a target, and a placement carries no answer today. This capability makes the target a typed fact of the plan rather than an assumption of whatever consumes it, and makes a module's declared `platforms` meet it.

## ADDED Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager` and an optional microarchitecture, and SHALL refuse any other key with an error row naming the registry file. A selected machine that declares no `system`, or no `serviceManager`, SHALL produce an error row naming the machine and the registry file, because a placement on it has no derivable target. The plan SHALL still be emitted in that case, containing the machine's entry and every entry placed on it, so that a deployment mid-migration is diagnosable rather than unevaluable.

A machine's key SHALL be a function of the values it declares, so that changing a machine's architecture re-keys every entry placed on it.

#### Scenario: A fully declared machine

- **WHEN** the registry declares a machine with an `address`, a `tags` entry, a `system` and a `serviceManager`
- **THEN** the planner SHALL emit no registry row
- **AND** the machine's plan entry SHALL record all four values

#### Scenario: A machine omits its system

- **WHEN** the registry declares a machine with no `system` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL still contain the machine's entry and every entry placed on it

#### Scenario: A machine omits its service manager

- **WHEN** the registry declares a machine with no `serviceManager` and a placement selects it
- **THEN** the planner SHALL emit an error row naming the machine and the registry file
- **AND** the plan SHALL still contain the machine's entry and every entry placed on it

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
