<!--
A delta against `planner/typed-edge`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `unify-declaration-and-implementation-readings`,
`deliver-secrets-across-machines`, `hold-declaration-shape-and-fold-set-reads` and
`identify-interfaces-by-declared-id`. `openspec/specs/` is empty in this repository, so the base text
is read from those changes.

Every requirement below is ADDED. How an interface is identified, how a slot's reach is checked
against placement, how an export is typed and how a refused read leaves a slot absent are all
unchanged. What this delta adds is which members of an instance exist, and what a reference inside a
root means when its target is not one of them.

The conditions: `lib/excluded.nix:37-44` refuses `members.<n>.enable` and `wire.<member>.<use>`, and
`lib/resolve.nix:1436-1444` is the row; `lib/module.nix:107` is `capabilityKeys = [ "interface"
"severity" ]`, so no capability can say it may be taken once.
-->

## ADDED Requirements

### Requirement: A root may bind a member's slot to a capability it holds

A root SHALL be able to fill one member's slot from inside the module, by naming a capability it
holds: `service "<name>" { module = …; wire.<slot> = <capability>; }`. The value written SHALL be a
capability of a member of the same root, taken from that member's handle, so that a mistyped
reference is an error in the module's own file rather than a name resolved at composition time.

A slot a root binds SHALL resolve to that capability with no deployment statement, and SHALL be
checked the way a deployment's wire is: the two interfaces SHALL be one interface, the reach SHALL be
checked against the bound capability's placements, and every read the slot declares SHALL be
resolved against the bound provider's exports. A binding SHALL NOT be exempt from any check a wire is
subject to.

A binding SHALL carry no deployment name: a root that wrote one would be a module naming an
instance, which is what a wire exists to keep out of module source. The capability a binding names
SHALL therefore be reachable only from the root's own member handles.

A root's members and its slots SHALL remain one namespace with disjoint names, so that a member
name and a slot name cannot collide and a deployment addressing either addresses one thing.

#### Scenario: A root binding a consumer to its own provider

- **WHEN** a root declares two members and binds one member's slot to the other's capability
- **THEN** the consuming member's entry SHALL record the read against the providing member's entry
- **AND** the deployment SHALL need no wire for that slot
- **AND** the planner SHALL emit no row

#### Scenario: A binding whose interfaces do not match

- **WHEN** a root binds a slot to a capability declaring another interface
- **THEN** the planner SHALL emit the interface-mismatch row naming both declaring files
- **AND** the row SHALL be the same row a deployment's wire earns for the same mistake

#### Scenario: A binding to a capability placed twice against a single-valued slot

- **WHEN** a root binds a slot whose reach is one to a capability whose member the deployment places
  twice
- **THEN** the planner SHALL emit the placement-count row
- **AND** the binding SHALL be subject to every check a wire is subject to

### Requirement: A deployment may cut a member of an instance

An instance SHALL be able to state, per member of the module it names, that the member does not
exist: `members.<name>.enable = false`. A cut member SHALL take no placement, SHALL need no settings
namespace, SHALL own no generated value, SHALL contribute no closure and SHALL produce no plan entry
of any kind.

A member the deployment does not mention SHALL exist, so that an instance naming no `members` block
keeps the whole composition and every deployment written before this construct means what it meant.

Naming a cut member anywhere else in the instance SHALL be an error row naming the member and the
cut: a `placement` entry for it, a `settings` namespace for it, or a wire naming it as a consumer.
A row SHALL NOT be produced for a *binding* inside the module that named it - that is the next
requirement.

#### Scenario: An instance that keeps every member

- **WHEN** an instance names a module and writes no `members` block
- **THEN** every member of that module SHALL produce its entries
- **AND** the plan SHALL be what it was before this construct existed

#### Scenario: A member the deployment cuts

- **WHEN** an instance writes `members.<name>.enable = false`
- **THEN** the plan SHALL carry no entry for that member
- **AND** no generated value of that member SHALL be recorded
- **AND** no closure of that member SHALL appear in any entry

#### Scenario: A placement for a cut member

- **WHEN** an instance cuts a member and writes a placement for it
- **THEN** the planner SHALL emit an error row naming the member and the cut
- **AND** the plan SHALL carry no entry for that member

#### Scenario: Settings for a cut member

- **WHEN** an instance cuts a member and writes a settings namespace for it
- **THEN** the planner SHALL emit an error row naming the member and the cut

### Requirement: A reference to a kept sibling is a binding and a reference to a cut one is an address

A reference a root writes from one member's slot to another member's capability SHALL be a binding
while the referenced member is kept: the deployment SHALL NOT be able to wire it, and a deployment
that writes a wire for it SHALL earn an error row naming the slot, the member it is bound to, and the
deployment file.

Where the referenced member is cut, the same reference SHALL become an unfilled slot of the referring
member, and the deployment SHALL fill it with `wire.<member>.<slot> = { instance; provides; }`. A
slot opened by a cut and left unwired SHALL earn the same unwired-slot row any other unwired slot
earns, subjected to the referring member's entry.

No line of the module SHALL differ between the two cases: what decides whether a reference is a
binding or an address is whether its target is a kept member of the same instance, and nothing else.

#### Scenario: A wire for a slot bound to a kept sibling

- **WHEN** a deployment writes a member-scoped wire for a slot the module binds to a member the
  instance keeps
- **THEN** the planner SHALL emit an error row naming the slot, the bound member and the deployment
  file
- **AND** the slot SHALL resolve to the binding the module wrote

#### Scenario: A slot opened by a cut and wired

- **WHEN** a deployment cuts the member a slot was bound to and writes a member-scoped wire naming
  another instance's exposed capability
- **THEN** the slot SHALL resolve to that capability
- **AND** the referring member's entry SHALL record the read against the wired provider
- **AND** the planner SHALL emit no row

#### Scenario: A slot opened by a cut and left unwired

- **WHEN** a deployment cuts the member a slot was bound to and writes no wire for it
- **THEN** the planner SHALL emit the unwired-slot row subjected to the referring member's entry
- **AND** the slot SHALL be absent from that member's resolved reads

#### Scenario: One module, two instances, two shapes

- **WHEN** two instances name one module, one keeping every member and one cutting a member that a
  kept member was bound to and wiring its place
- **THEN** both instances SHALL resolve
- **AND** the module source SHALL be identical for both
- **AND** the kept-member entries of the second SHALL read the wired provider where the first reads
  its sibling

### Requirement: A capability may be declared to be taken once

A provided capability SHALL be able to declare `consumers = "one"`, meaning that at most one slot
across the whole deployment may be wired to it. A second wire to it SHALL be an error row naming the
capability, its providing instance, and both consuming slots.

The check SHALL be made across the deployment rather than per slot, and it SHALL count wires rather
than placements or reads: a slot wired to the capability counts once however many placements either
end has, and a capability declaring nothing SHALL admit any number of consumers as it does today.

Where one instance publishes one capability per entry of a settings-valued declaration, each SHALL be
counted on its own, so two consumers taking two of them SHALL produce no row.

#### Scenario: Two instances wiring one single-consumer capability

- **WHEN** two instances wire slots to one capability declaring `consumers = "one"`
- **THEN** the planner SHALL emit an error row naming the capability, its instance and both slots
- **AND** the row SHALL be produced once rather than once per consumer

#### Scenario: Two consumers taking two capabilities of one instance

- **WHEN** one instance publishes two capabilities each declaring `consumers = "one"`, and two
  instances wire one each
- **THEN** the planner SHALL emit no row
- **AND** each slot SHALL resolve to the capability it named

#### Scenario: A capability declaring nothing

- **WHEN** two instances wire slots to one capability that declares no `consumers`
- **THEN** the planner SHALL emit no row

#### Scenario: One consumer of a single-consumer capability placed twice

- **WHEN** one slot is wired to a capability declaring `consumers = "one"` and the consuming member
  is placed on two machines
- **THEN** the planner SHALL emit no row for the consumer count
- **AND** both placements SHALL resolve the read
