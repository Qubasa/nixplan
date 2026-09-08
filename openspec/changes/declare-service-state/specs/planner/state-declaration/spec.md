<!--
`openspec/specs/` is empty in this repository, so this new capability is written here and the
two deltas beside it are written against the change that introduced their text, the same way
`emit-systemd-portable-service-images` writes against `implement-minimal-typed-edge`.
-->

## Purpose

Defines how a module declares the mutable state it writes, how the units that dump and restore
that state are named, and every way the declaration is refused. The declaration is a portable
fact that lands in the plan, so a snapshot, a machine replacement or a state migration can be
sequenced by a reader that never evaluates Nix and never parses a unit file.

## ADDED Requirements

### Requirement: A module declares the state it writes

A module's implementation SHALL be able to declare the folders it writes, keyed by absolute
path, each carrying the account that owns it and whether its contents are durable or derived. A
declaration SHALL be portable: it SHALL be readable without knowing which service manager runs
the unit, and it SHALL NOT be expressed as a field of one service manager's unit extension. A
module that writes no state SHALL declare none, and its entry SHALL carry no state.

#### Scenario: A declared folder reaches the plan

- **WHEN** a placed service declares a durable folder with an owner
- **THEN** the entry SHALL record that path, its owner and its disposition
- **AND** the record SHALL name no service manager

#### Scenario: A service that writes nothing

- **WHEN** a placed service declares no state
- **THEN** its entry SHALL carry no state field

#### Scenario: The declaration survives a round trip

- **WHEN** a plan carrying a state declaration is written to JSON and read back
- **THEN** the read-back declaration SHALL equal the written one

### Requirement: The hooks that dump and restore state are units the module declared

A module SHALL name the unit that dumps its state and the unit that restores it, and each name
SHALL be a unit that same module declared. A hook naming a unit the module did not declare SHALL
be a row naming the hook, the name it used and the units it declared. A module that names no
hooks SHALL record none, and its state SHALL still be recorded.

#### Scenario: A hook names an own unit

- **WHEN** a module declares a dump unit and names it as its dump hook
- **THEN** the entry SHALL record that unit name as the dump hook

#### Scenario: A hook names a stranger's unit

- **WHEN** a module names a dump hook that is not among the units it declared
- **THEN** the planner SHALL emit a row naming the hook and the units the module declared
- **AND** the entry SHALL record no dump hook

### Requirement: A folder's disposition decides whether it is snapshot material

A folder SHALL declare its contents durable or derived, and an omitted disposition SHALL mean
durable. A derived folder SHALL be recorded as derived so that a snapshot skips it. A
disposition outside that domain SHALL be a row naming the value read and the domain, and the
folder SHALL be recorded as durable.

#### Scenario: A cache is declared derived

- **WHEN** a module declares one durable folder and one derived folder
- **THEN** the entry SHALL record both with their dispositions distinguished

#### Scenario: A disposition outside the domain

- **WHEN** a module declares a folder whose disposition is neither durable nor derived
- **THEN** the planner SHALL emit a row naming the value and the two accepted values

### Requirement: A malformed declaration is a row and evaluation continues

Evaluation SHALL remain total over every malformed state declaration. A state declaration that
is not an attribute set, a key outside its shape, a path that is not absolute, a path under the
store directory, and an owner that is not a portable account name SHALL each be a row naming the
declaring subject, and the plan SHALL still be produced with the offending folder absent from
the entry.

#### Scenario: A relative path

- **WHEN** a module declares a state folder whose key is not an absolute path
- **THEN** the planner SHALL emit a row naming that key
- **AND** the entry SHALL record no folder for it

#### Scenario: A path under the store directory

- **WHEN** a module declares a state folder under the store directory the entry is planned against
- **THEN** the planner SHALL emit a row stating that state is not store-resident

#### Scenario: An owner that is not an account name

- **WHEN** a module declares an owner that is not a portable account name
- **THEN** the planner SHALL emit a row naming the value and the shape an account name has

#### Scenario: An unknown key under a folder

- **WHEN** a module declares a key under a state folder that the shape does not carry
- **THEN** the planner SHALL emit a row naming the key and the keys the shape carries

### Requirement: One directive has one source

A unit's state directive SHALL have exactly one declaration site. A module that declares a state
folder and also sets the same directive through a service manager's unit extension SHALL be a
row naming both sites, and the rendered unit SHALL carry the directive derived from the state
declaration.

#### Scenario: Both sites declare one directory

- **WHEN** a module declares a state folder and sets the equivalent unit-extension field on the same unit
- **THEN** the planner SHALL emit a row naming the folder, the unit and the extension field

### Requirement: A folder no target can express without an owner is refused before delivery

A state folder SHALL be checked against the service manager of the machine the entry is placed
on. A folder the target expresses only for an account it can name, declared without an owner,
SHALL be a row naming the path, the machine and the service manager, and SHALL be recorded so
that no binding has to guess an owner.

#### Scenario: An out-of-convention path without an owner

- **WHEN** an entry placed on a systemd machine declares a durable folder outside the location that service manager owns, and declares no owner
- **THEN** the planner SHALL emit a row naming the path, the machine and the service manager

### Requirement: Two entries on one machine may not claim one folder

Two entries placed on one machine SHALL NOT claim the same state folder, and SHALL NOT claim
folders where one contains the other. Such a claim SHALL be a row naming both entries and both
paths. The check SHALL run after placement, because it is a fact about a machine rather than
about a module.

#### Scenario: Two services claim one folder

- **WHEN** two entries on one machine declare the same state path
- **THEN** the planner SHALL emit a row naming both entries and the path

#### Scenario: One claim contains the other

- **WHEN** one entry declares a folder that contains a folder declared by another entry on the same machine
- **THEN** the planner SHALL emit a row naming both entries and both paths

#### Scenario: The same path on two machines

- **WHEN** two entries on different machines declare the same state path
- **THEN** the planner SHALL emit no row for it
