<!--
A delta against `planner/machine-platform`, whose base text lives in the unarchived change
`emit-systemd-portable-service-images` (`specs/planner/machine-platform/spec.md`).
`openspec/specs/` is empty in this repository, so the base text is read from there.

The MODIFIED requirement below keeps its heading and its four scenario headings, so the tests those
scenarios name keep their names and change their assertions. What moves in it is one clause: the
base text promises that the plan of a machine whose target is incomplete "SHALL still be emitted in
that case, containing the machine's entry and every entry placed on it". The machine's entry stays;
every entry placed on it does not, because a partial target is what a module aborts on and the plan
that carries the entry is the plan that hands the module the target.

The two requirements about the platform record's projection and about a module's declared
`platforms` are untouched.
-->

## MODIFIED Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager` and an optional
microarchitecture, and SHALL refuse any other key with an error row naming the registry file. A
machine a placement selects SHALL declare an address, a system and a service manager: these are the
three facts a placement's target is derived from, and a module may render any of them. A selected
machine that declares none of one of them SHALL produce one error row naming the machine, every key
it did not declare, the registry file and how many entries were placed on it, and no entry SHALL be
planned for that machine.

Completeness SHALL be decided by the value the registry reading produced for a field and not by the
presence of its key, so that a machine declaring a field as something other than the kind the
reading needs is as incomplete as a machine declaring nothing: such a machine SHALL earn both the
row about the malformed declaration and the row about the incomplete target.

The plan SHALL still be emitted in that case, and SHALL still contain the machine's own record, so
that the registry half of a deployment mid-migration is readable rather than unevaluable. A member
every one of whose placements was dropped SHALL be recorded as the unplaced member it became,
carrying the selector the deployment wrote.

A machine no placement selects SHALL declare whatever it likes and SHALL produce no row: no target
is derived for it, no implementation is evaluated for it, and a registry may therefore list a
machine that has not been provisioned yet without making the deployment inapplicable.

A machine's key SHALL be a function of the values it declares, so that changing a machine's
architecture re-keys every entry placed on it.

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

## ADDED Requirements

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
