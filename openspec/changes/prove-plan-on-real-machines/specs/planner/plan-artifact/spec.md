<!--
`openspec/specs/` is empty: `planner/plan-artifact` exists only in the unarchived
`implement-minimal-typed-edge` change, so this delta is written against that change's text. `An
entry's key is a hash of everything that affects it` is stated there over the values an entry was
handed rather than as a closed list, so an address entering the key needs no requirement of that
change to be rewritten, and this delta only adds.
-->

## ADDED Requirements

### Requirement: An implementation is handed the machine it was planned for

An implementation SHALL receive the machine a placement was planned for as one value carrying every
fact the planner has about it that a unit may be rendered from: what it is built for, what runs its
units, and the address it is reached at. A machine that declares no address SHALL yield that value
without an address field, so a module that dereferences one on a machine that has none is refused
rather than handed an empty string. A deployment SHALL NOT have to restate the address in settings
for a service to publish its own endpoint.

#### Scenario: A service publishes its own endpoint

- **WHEN** a service is placed on a machine whose record carries an address, and its
  implementation renders that address into an export or a unit
- **THEN** the value it renders SHALL equal the address the plan records for that machine
- **AND** the deployment SHALL have declared the address exactly once, in the machine registry

#### Scenario: A machine with no address

- **WHEN** a service is placed on a machine whose record declares no address
- **THEN** the machine value handed to the implementation SHALL carry no address field
- **AND** an implementation that reads one SHALL produce a row naming the entry and the machine

#### Scenario: The address a consumer reads is the producer's, not its own

- **WHEN** a consuming service reads an endpoint from a wire whose far end is on another machine
- **THEN** the address in the value it reads SHALL be the producing machine's address

### Requirement: A machine's address is an input to the keys of the entries on it

Because a unit may be rendered from a machine's address, the address SHALL be an input to the key
of every entry placed on that machine, so that two renderings of one entry can never share a key.
Changing one machine's address SHALL change the keys of the entries placed on it and no others.

#### Scenario: An address changes

- **WHEN** a machine's address is declared differently and nothing else changes
- **THEN** the keys of the entries placed on that machine SHALL change
- **AND** the keys of entries placed on other machines SHALL be unchanged

#### Scenario: Nothing else changes with it

- **WHEN** a machine's address is declared differently and nothing else changes
- **THEN** the plan SHALL report the same placements, the same allocations and the same wires as
  before
