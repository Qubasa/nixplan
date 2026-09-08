<!--
`openspec/specs/` is empty: `planner/plan-artifact` exists only in the unarchived
`implement-minimal-typed-edge` change, so this delta is written against that change's text.
`An entry's key is a hash of everything that affects it` is stated there over the values an
entry was handed rather than as a closed list, so state enters the key without that
requirement changing, and this delta only adds.
-->

## ADDED Requirements

### Requirement: The entry records the state its service writes

A placed entry SHALL record the state folders its service declared, keyed by absolute path, each
carrying its owner when one was declared and its disposition, together with the unit names that
dump and restore it. The record SHALL be readable without evaluating Nix and SHALL name no
service manager, so that the party sequencing a snapshot, a migration or a machine replacement
reads the plan rather than a unit file. An entry whose service declares no state SHALL carry no
state field, as an absent value is not written.

#### Scenario: A stateful service is placed

- **WHEN** a service declaring a durable folder, an owner and a restore unit is placed
- **THEN** its entry SHALL record the path, the owner, the disposition and the restore unit name

#### Scenario: A stateless service is placed

- **WHEN** a service declaring no state is placed
- **THEN** its entry SHALL carry no state field

#### Scenario: A service that runs nowhere

- **WHEN** no placement selects a service that declares state
- **THEN** its entry SHALL carry no state field, because it writes nothing on no machine

### Requirement: Moving state re-keys the entry that writes it

A state folder's path, owner and disposition SHALL be inputs to the entry's key, because each
changes the unit the machine runs and the folders the machine must carry. A change to one
entry's state SHALL change that entry's key and no other entry's key.

#### Scenario: A folder moves

- **WHEN** a service's state folder is declared at a different path and nothing else changes
- **THEN** that entry's key SHALL change

#### Scenario: An owner changes

- **WHEN** a state folder's declared owner changes and nothing else changes
- **THEN** that entry's key SHALL change

#### Scenario: A neighbour is untouched

- **WHEN** one entry's state declaration changes
- **THEN** the key of an entry that reads nothing from it SHALL be unchanged
