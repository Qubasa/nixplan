<!--
A delta against `planner/machine-platform`, whose current text is
`openspec/specs/planner/machine-platform/spec.md`. Two requirements are modified and one is added.

The registry-keys requirement is modified by a second open change too:
`unseal-a-value-after-a-reboot` adds `sealRecipient` to the same sentence. Each delta states its
own key only and reads the other as a seam - whichever lands second restates the requirement text
over the amended base. `openspec/changes/INTEGRATION.md` records that seam.

The conditions. `lib/resolve.nix:576-593` builds `machineRecords` out of the declared fields and
adds `microarchitecture` only where one was declared, which is the precedent the `scope` key
follows: a field enters a key only where its value differs from the default it would resolve to
unstated. The completeness reading is the `address = 22` precedent the live text already states -
a refused value is as incomplete as none, and the placements are dropped in the stratum the row is
produced in. The domain has one home the way `restartPolicies` does (`lib/atoms.nix:17`, the atom
at `:99`, the domain export at `:101`), so the atom's predicate and the row read one list.

The four scope-crossing rows sit where `placement-platform-mismatch` sits: machine-platform owns
the crossings between a placement and the machine it selects, and each row is a refusal rather
than a filter, so the entry stays in the plan and the operator sees what they wrote and why it
cannot run. A user manager cannot switch accounts, which covers both a unit's `user` and the
`supplementaryGroups` an extension application records; a fixed port claim below 1024 needs a
capability the account does not hold, and the claim is read after normalisation so the row and the
allocation index agree on what was claimed; a delivered file cannot be chowned by the account, so
a generated file record stating an `owner` or a `group` is a statement the scope cannot honor,
while `mode` is the account's own to set and stays honoured.
-->

## ADDED Requirements

### Requirement: A statement a user scope cannot honor is refused

On a placement whose machine's scope is `user`, the planner SHALL refuse every declared fact the
scope cannot honor with an error row, produced in the same walk that crosses a placement against
its machine, and SHALL NOT collapse any of them to the account silently. Each row SHALL be a
refusal and not a filter: the entry SHALL still appear in the plan for the placement the
deployment asked for.

- A unit that declares `user` SHALL be `unit-account-in-user-scope`: a user manager runs every
  unit as the account and cannot switch to another.
- A unit whose extension application records `supplementaryGroups`, under any backend, SHALL be
  `unit-groups-in-user-scope`: a group is granted by a system manager and the account cannot
  grant one to itself.
- A normalised fixed port claim below 1024 SHALL be `port-privileged-in-user-scope`: binding a
  privileged port is a capability the account does not hold.
- A generated file record that states an `owner` or a `group` SHALL be
  `value-ownership-in-user-scope`, its subject the value entry: the delivery cannot chown, so a
  stated ownership is a statement the scope cannot honor. A stated `mode` SHALL stay honoured.

The same declarations on a placement whose machine's scope is `system` SHALL earn none of these
rows.

#### Scenario: A unit declaring an account meets a user-scope machine

- **WHEN** a placed module declares a unit with a `user` and the placement's machine declares
  `scope = "user"`
- **THEN** the planner SHALL emit an `unit-account-in-user-scope` error row naming the entry and
  the unit
- **AND** the plan SHALL still contain that placement's entry

#### Scenario: A unit declaring groups meets a user-scope machine

- **WHEN** a placed unit's extension application records `supplementaryGroups` and the placement's
  machine declares `scope = "user"`
- **THEN** the planner SHALL emit an `unit-groups-in-user-scope` error row naming the entry and
  the unit
- **AND** the same declaration on a system-scope machine SHALL earn no such row

#### Scenario: A privileged port claim meets a user-scope machine

- **WHEN** a placed entry claims a fixed port below 1024 and the placement's machine declares
  `scope = "user"`
- **THEN** the planner SHALL emit a `port-privileged-in-user-scope` error row naming the entry and
  the port
- **AND** the claim SHALL be read after normalisation, so the row and the allocation index agree

#### Scenario: A value stating an ownership is delivered to a user-scope machine

- **WHEN** a generated file record states an `owner` and the value's delivery set names a machine
  declaring `scope = "user"`
- **THEN** the planner SHALL emit a `value-ownership-in-user-scope` error row whose subject is the
  value entry
- **AND** a record stating a `mode` and no ownership SHALL earn no such row

## MODIFIED Requirements

### Requirement: A machine declares the system it runs and the service manager that runs its units

The machine registry SHALL read `address`, `tags`, `system`, `serviceManager`, an optional
microarchitecture, an optional `scope` and an optional statement of the host resources the machine
already holds, and SHALL refuse any other key with an error row naming the registry file. A
selected machine that declares no `system`, or no `serviceManager`, SHALL produce an error row
naming the machine and the registry file, because a placement on it has no derivable target. The
plan SHALL still be emitted in that case, containing the machine's entry and every entry placed on
it, so that a deployment mid-migration is diagnosable rather than unevaluable.

`scope` SHALL take `system` or `user`, unstated meaning `system`, and the domain SHALL be stated
once in the library beside the other value domains, so the atom's predicate and the row read one
list. A value outside the domain SHALL be a `machine-scope-unknown` error row naming the machine
and the registry file, and the machine's target SHALL be incomplete - a refused value is as
incomplete as no value, so its placements are dropped as an unaddressed machine's are.

A machine's key SHALL be a function of the facts the plan records about the machine - what a consumer
dials, what a placement selects on, what a target is elaborated from - so that changing a machine's
architecture re-keys every entry placed on it. `scope` SHALL enter the machine's record and the
target only when it is `user`, so a machine stating the default SHALL key as a machine stating
nothing, and a machine flipping to `user` SHALL re-key every entry placed on it, because rendered
units, attach argv and profiles all change with it. A statement of what the machine already holds
SHALL NOT be one of those facts and SHALL NOT enter that key, nor the key of any entry or generated
value placed on the machine: it says nothing about what is built for the machine, and re-keying an
entry on account of it would ask for a redelivery, and a generated value for a regeneration, of
bytes that are still correct.

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

#### Scenario: A machine declares a scope outside the domain

- **WHEN** the registry declares `scope = "global"` and a placement selects that machine
- **THEN** the planner SHALL emit a `machine-scope-unknown` error row naming the machine and the
  registry file
- **AND** no entry SHALL be planned for that machine

#### Scenario: A machine stating the default scope keys as it did

- **WHEN** a machine's declaration gains `scope = "system"` and nothing else changes
- **THEN** the machine's key SHALL be the key it had
- **AND** every entry placed on that machine SHALL keep its key

#### Scenario: A machine changes scope

- **WHEN** a machine's declared `scope` changes from unstated to `user` and nothing else does
- **THEN** the machine's key SHALL change
- **AND** every entry placed on that machine SHALL be re-keyed

### Requirement: An entry records the target it was planned for

A placed entry SHALL record the platform record of the machine it is placed on and that machine's
`serviceManager`, and both SHALL be part of the entry's key. A downstream consumer SHALL be able to
determine an entry's target from the entry alone, without consulting the machine registry. A
placement's target SHALL be derived from the machine the placement selected, and the same target
SHALL be what a unit extension's backend is checked against.

The target SHALL carry `scope` only when the machine's scope is `user`, and a target carrying it
SHALL enter the entry's key with it, so a consumer of the entry alone knows which manager runs the
units and a machine stating the default re-keys nothing. An implementation SHALL read the scope
from `target.scope`, absent meaning `system`.

An entry for a member no placement selects SHALL record neither a platform record nor a
`serviceManager`.

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

#### Scenario: A user-scope target records its scope

- **WHEN** one service of one instance is placed on a machine declaring `scope = "user"` and on a
  machine declaring no scope
- **THEN** the first entry's target SHALL record `scope = "user"` and the second SHALL record no
  scope
- **AND** the two entry keys SHALL differ

#### Scenario: A system-scope target carries no scope field

- **WHEN** an entry is placed on a machine declaring `scope = "system"`
- **THEN** its target SHALL carry no `scope` field
- **AND** the entry's key SHALL be the key it has with the scope unstated
