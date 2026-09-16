# planner/typed-edge Specification

## Purpose
Defines the consumer half of a typed cross-service edge: how an interface is identified, what an export declares, what a provider must publish, what a slot may ask for, and which of those the planner refuses. This is the smallest set of constructs that changes an outcome, so every requirement here names a refusal that a flat untyped export map cannot state.

## Requirements

### Requirement: An interface is a value and its name is a label

An interface SHALL be identified by the value an author imported, or by an identity that author
claimed with a declared `id`, never by a name resolved at composition time, and SHALL NOT be validated
against any registry of known interfaces. An interface's `name` SHALL be used only in diagnostic
output. Two interfaces declared in different files MAY carry the same `name`.

Where either end of an edge declares no `id`, the two SHALL be one interface only when they are one
value. Where both ends declare an `id`, the two SHALL be one interface when the whole of the identity
those claims carry is equal, and their values SHALL NOT be compared. A claim SHALL NOT make an
interface known to the planner, required to appear in any list the planner owns, or valid for having
been claimed.

#### Scenario: Two interfaces share a name

- **WHEN** two distinct interface values carry the same `name`, neither declares an `id`, and a slot on
  one is wired to a capability declaring the other
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL render the declaring file of each interface beside its name, so the two are
  distinguishable in output

#### Scenario: Two interfaces share a name and one identity

- **WHEN** two distinct interface values carry the same `name` and declare one `id` with one identity,
  and a slot on one is wired to a capability declaring the other
- **THEN** the planner SHALL resolve the edge
- **AND** SHALL NOT emit a mismatch row for it

#### Scenario: An interface nobody upstreamed

- **WHEN** a module declares an interface that no other module or library file references
- **THEN** the planner SHALL accept it
- **AND** SHALL NOT require it to appear in any list the planner owns
- **AND** SHALL accept it whether or not it declares an `id`

#### Scenario: A misspelled capability reference

- **WHEN** a module re-exports a capability under a name its member does not provide
- **THEN** the failure SHALL occur while evaluating that module file
- **AND** SHALL NOT be deferred to wire resolution

#### Scenario: A refused edge names the rule that refused it

- **WHEN** a slot's interface and the capability's interface are not one interface
- **THEN** the row SHALL state whether they were compared as values or as claims
- **AND** the resolution SHALL name the fix that applies to the rule that was used

### Requirement: An export atom declares a type and a secrecy and nothing else

An export atom SHALL declare `type` and MAY declare `secrecy`. An omitted `secrecy` SHALL mean `public`. `secrecy` SHALL take exactly the values `public` and `secret`. An atom carrying any other key, including `locality` or `lifecycle`, SHALL produce an error row naming the key and stating the condition that would introduce it.

#### Scenario: An atom omits secrecy

- **WHEN** an atom declares only `type`
- **THEN** the export SHALL be treated as `public`
- **AND** no row SHALL be emitted

#### Scenario: An atom declares a locality

- **WHEN** an atom declares `locality`
- **THEN** the planner SHALL emit an error row naming the atom and the key
- **AND** the row SHALL state that the field is absent until an export in the target carries a value that cannot leave its machine
- **AND** the planner SHALL NOT silently accept and discard the key

#### Scenario: A value does not match its declared type

- **WHEN** a provider publishes an export whose value fails its atom's type
- **THEN** the planner SHALL emit an error row at the provider that produced it
- **AND** the row SHALL name the provider rather than any consumer that reads the export

### Requirement: A provider's export keyset equals its interface's keyset

A capability's published exports SHALL have exactly the key set its interface declares. An omitted export SHALL be an error row and an extra export SHALL be an error row. No superset of a narrower interface's keyset SHALL satisfy that interface.

#### Scenario: A provider omits an export

- **WHEN** a capability declares an interface with two exports and publishes one
- **THEN** the planner SHALL emit an error row naming the missing export, the publishing file and the interface's declaring file

#### Scenario: A provider publishes an extra export

- **WHEN** a capability publishes an export its interface does not declare
- **THEN** the planner SHALL emit an error row naming the extra export
- **AND** SHALL NOT deliver that export to any consumer

### Requirement: A slot declares an interface, an arity and the exports it reads

A slot SHALL declare `interface`, MAY declare `reach`, and MAY declare `reads`. An omitted `reach` SHALL mean `one`. `reach` SHALL take the values `one` and `all` in this capability; `local` SHALL be refused with a row stating that it requires the co-placement machinery this subset does not carry. An omitted `reads` SHALL mean every export of the interface. A `reads` entry naming an export the interface does not declare SHALL be an error row.

#### Scenario: A slot is never wired

- **WHEN** a module declares a slot and no deployment wires it
- **THEN** the planner SHALL emit an error row naming the slot and the interface's declaring file
- **AND** the slot SHALL NOT resolve to an empty value that a consumer could read

#### Scenario: A slot declares reach local

- **WHEN** a slot declares `reach = "local"`
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL state that `local` derives from a locality this subset does not declare

#### Scenario: reads names an export that does not exist

- **WHEN** a slot's `reads` names an export absent from its interface
- **THEN** the planner SHALL emit an error row naming the slot, the entry and the interface

### Requirement: A slot that reads a secret export decides its delivery

A `reads` entry naming an export whose `secrecy` is `secret` SHALL be accepted, and SHALL be the
only thing that puts the reader's machine in that value's delivery set. A consumer SHALL receive
such an export as the record its atom's type describes — `{ path, secrecy }` for `atoms.secretRef` —
so a module writes `results.<slot>.<export>.path` and interpolating the export itself fails rather
than yielding a path under the name of a value. A service SHALL still be able to use a secret value
it produced itself without routing it through a slot.

Nothing in this subset caps an export at machine-local, so a consumer naming a private half in
`reads` SHALL have it delivered. Refusing that read is the `locality` change's, whose recorded
trigger is the first export whose value is a unix socket path or a loopback port.

#### Scenario: A consumer asks for the private half

- **WHEN** a slot's `reads` names an export declared `secret` and the provider is placed on another
  machine
- **THEN** the planner SHALL accept it and produce no row about the secrecy
- **AND** the consumer's machine SHALL be in the delivery set of the value behind that export
- **AND** the consumer SHALL read it as a reference record whose `path` is the delivered path
- **AND** the acceptance SHALL NOT depend on whether the provider and the consumer are placed on one
  machine

#### Scenario: A producer uses its own secret

- **WHEN** a service reads a secret value it generated and passes it to one of its own units
- **THEN** the planner SHALL accept it
- **AND** the value SHALL appear in the plan as a reference rather than as content
- **AND** the path SHALL name the instance that owns the generator

#### Scenario: A secret export with no reader

- **WHEN** a capability declares a secret export that no slot reads
- **THEN** the planner SHALL accept the declaration
- **AND** SHALL record the export as declared and delivered to nobody
- **AND** the value behind it SHALL still be delivered to the machines its owner is placed on

### Requirement: A wire names an exposed capability of a named instance

A deployment SHALL fill a slot by naming an instance and one of its exposed capabilities. A capability that an instance does not expose SHALL NOT be addressable from outside that instance. When a wire names an instance or a capability that does not exist, the planner SHALL emit an error row carrying the candidate list it holds.

#### Scenario: A wire names a capability that is not exposed

- **WHEN** a wire names a capability a target instance provides but does not list in `exposes`
- **THEN** the planner SHALL emit an error row
- **AND** the row SHALL list the capabilities that instance does expose

#### Scenario: A wire names an unknown instance

- **WHEN** a wire names an instance absent from the deployment
- **THEN** the planner SHALL emit an error row naming the wire and listing the deployment's instance names

#### Scenario: Two instances wire each other

- **WHEN** two instances each wire a slot to a capability the other exposes, and every export involved is known at evaluation
- **THEN** the planner SHALL resolve both reads
- **AND** neither entry SHALL appear in the other's dependency list
- **AND** the pair SHALL NOT be reported as a cycle

### Requirement: Reach is checked against the placements of the wired capability

The planner SHALL count the placements of the wired capability after placement is decided and check that count against the slot's `reach`. Under `one` the consumer SHALL receive a single export set. Under `all` the consumer SHALL receive an attribute set keyed by machine, including when the wired capability has exactly one placement.

#### Scenario: A single-valued read of a set

- **WHEN** a slot declares `reach = "one"` and the wired capability has two placements
- **THEN** the planner SHALL emit an error row naming the slot and both placements
- **AND** SHALL NOT deliver either placement to the consumer

#### Scenario: A set-valued read of one placement

- **WHEN** a slot declares `reach = "all"` and the wired capability has one placement
- **THEN** the consumer SHALL receive an attribute set with one entry keyed by machine
- **AND** the shape SHALL NOT collapse to a single export set

#### Scenario: An entry of a set has no value

- **WHEN** a slot declares `reach = "all"` and one placement of the wired capability declares an export whose bytes do not exist yet
- **THEN** the collected set SHALL contain a named entry for that placement
- **AND** the planner SHALL emit an error row naming that entry
- **AND** the set SHALL NOT be shortened by dropping the entry

### Requirement: A composition decides which settings a deployment may move

A root SHALL key each member's settings under that member's own name, including when it owns exactly one member, and SHALL forward nothing. A root SHALL declare each knob it owns as either a default a deployment may overwrite or a fixed value it may not. A deployment definition against a fixed path SHALL be an error row naming both files.

A member's declaration SHALL be read exactly once per instance, against the settings that instance resolved, so that the capabilities a root publishes and the exports a placement produces are derived from one value. The set of capabilities a member provides MAY therefore be derived from that member's resolved settings, and a knob such a set is derived from SHALL be an ordinary default or fixed value with no additional status. What an instance may expose, what a wire may name, and what the plan publishes SHALL agree for every deployment.

#### Scenario: A deployment overwrites a default

- **WHEN** a deployment sets a member setting the root declared as a default
- **THEN** the deployment's value SHALL be used
- **AND** the plan SHALL record the deployment as the source of that value

#### Scenario: A deployment writes to a fixed path

- **WHEN** a deployment sets a member setting the root declared as fixed
- **THEN** the planner SHALL emit an error row naming the deployment file and the module file
- **AND** neither value SHALL silently win

#### Scenario: A single-member root still keys its namespace

- **WHEN** a root owns one member named `server` and a deployment sets that member's `quota`
- **THEN** the deployment SHALL address it as the member's `quota` under the member's name
- **AND** a definition written without the member name SHALL be an error row

#### Scenario: A deployment decides the capability set

- **WHEN** a member derives the capabilities it provides from a setting, and a deployment overwrites that setting with a longer list than the member's default
- **THEN** every capability the resolved setting names SHALL be exposable by the instance and namable by a wire
- **AND** the plan SHALL publish exactly those capabilities with their exports
- **AND** no row SHALL claim the root does not provide a capability the resolved setting names

#### Scenario: A wire names a capability the deployment added

- **WHEN** a deployment adds a capability through such a setting and wires a consuming slot to it
- **THEN** the read SHALL be delivered and the plan SHALL record the consumer on that capability's exports
- **AND** evaluation SHALL NOT fail on a missing slot

#### Scenario: A capability set derived from a knob nobody declared

- **WHEN** a deployment writes a setting the member declares neither as a default nor as fixed, and the member derives its capability set from that setting
- **THEN** the planner SHALL emit the undeclared-knob error row naming the member and the knob
- **AND** the capability set SHALL be derived from the member's own declared value

### Requirement: A member's slot set is observed against its own defaults

A member's declaration is read once, against resolved settings. The planner SHALL additionally
determine whether the set of slots that declaration asks for is the same set the member asks for
under its own declared defaults, and SHALL emit one warning row per member whose slot set differs,
naming the member, the slots present under one reading and absent under the other, and the condition
under which member cuts would become a construct of their own.

The row SHALL be a warning and SHALL NOT refuse the plan: a module deriving its own slot set from a
knob is publishing a cut, which is a decision a module is allowed to take. What the row exists for is
that a slot removed this way leaves no other trace - no wire is required for it, no unwired-slot row
is emitted, and the plan records nothing about a dependency that was never asked for.

The set of capabilities a member provides MAY be derived from that member's resolved settings and
SHALL NOT be reported by this row. A value inside a slot, a claim, a generator or an export MAY be
derived from resolved settings, and SHALL NOT be reported by this row: only the set of slot names is
observed.

#### Scenario: A knob removes a slot

- **WHEN** a member asks for a slot under its own defaults and asks for no such slot under the
  settings its instance resolved
- **THEN** the planner SHALL emit a warning row naming the member and that slot
- **AND** the row SHALL state the condition under which member cuts become a construct
- **AND** the plan SHALL still be produced, and SHALL remain applicable if nothing else refuses it

#### Scenario: A knob adds a slot

- **WHEN** a member asks for no such slot under its own defaults and asks for one under the settings
  its instance resolved
- **THEN** the planner SHALL emit a warning row naming the member and that slot
- **AND** the added slot SHALL be resolved, wired and reported exactly as any declared slot is

#### Scenario: A member nobody configured is not reported

- **WHEN** every resolved setting of a member came from that member's own defaults or fixed values
- **THEN** no slot-set row SHALL be emitted for that member

#### Scenario: A claim derived from a setting value is not a shape difference

- **WHEN** a member derives a port claim's fixed value from a resolved setting the deployment wrote
- **THEN** no slot-set row SHALL be emitted for that member
- **AND** the claim SHALL be allocated from the resolved value

#### Scenario: A capability set derived from settings is not reported here

- **WHEN** a member derives the set of capabilities it provides from a resolved setting the
  deployment wrote, and asks for the same slots under both readings
- **THEN** no slot-set row SHALL be emitted for that member
- **AND** every capability the resolved setting names SHALL stay exposable and namable by a wire

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

The declared cardinality SHALL be a property of the capability the member declared, and SHALL be read
by the member's own capability name. What an instance root's `provides` decides is which name a wire
may address; how many wires may take the capability SHALL remain the member's statement. Re-exposing
a capability under a name other than the member's own SHALL therefore neither widen nor narrow it:
the same capability exposed under the member's name, under another name, or under two names at once
SHALL admit the same number of consumers, and a wire naming any of those names SHALL count against
that one capability.

The check SHALL be made across the deployment rather than per slot, and it SHALL count wires rather
than placements or reads: a slot wired to the capability counts once however many placements either
end has, a binding a root wrote counts as a wire, and a capability declaring nothing SHALL admit any
number of consumers.

Where one instance publishes one capability per entry of a settings-valued declaration, each SHALL be
counted on its own, so two consumers taking two of them SHALL produce no row.

The row SHALL be produced once for the capability rather than once per consumer, and SHALL name the
capability by the name its member declared, which is the name the declaration a reader has to edit is
written under.

#### Scenario: Two instances wiring one single-consumer capability

- **WHEN** two instances wire slots to one capability declaring `consumers = "one"`, which its
  instance's root exposes under the member's own name
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

#### Scenario: A root renaming a capability taken twice

- **WHEN** a root exposes a capability declaring `consumers = "one"` under a name other than the
  member's own, and two instances wire slots to that name
- **THEN** the planner SHALL emit the same error row the deployment earns where the exposed name is
  the member's own
- **AND** the row SHALL name the capability by the name its member declared

#### Scenario: A root renaming a capability taken once

- **WHEN** a root exposes a capability declaring `consumers = "one"` under another name and one
  instance wires a slot to that name
- **THEN** the planner SHALL emit no row
- **AND** the read SHALL be delivered

#### Scenario: One capability exposed under two names

- **WHEN** a root exposes one member capability declaring `consumers = "one"` under two names and one
  instance wires a slot to each of them
- **THEN** the planner SHALL emit one error row for that capability
- **AND** both wires SHALL count against it

#### Scenario: A root binding and a wire taking one capability

- **WHEN** a root binds one member's slot to a sibling's capability declaring `consumers = "one"`,
  exposes that capability under another name, and another instance wires a slot to that name
- **THEN** the planner SHALL emit an error row naming the capability, the bound slot and the wired
  slot
- **AND** the binding SHALL count as one of the two consumers

### Requirement: A wire resolves only to a far end carrying an interface

A wire and a binding SHALL resolve only to a far end that carries an interface value. A far end that
carries none SHALL be one error row naming the consuming entry, the slot and the capability, and the
slot SHALL be left undelivered - absent from the consumer's results rather than present and empty.

The absence SHALL be read before the two ends are compared. Neither the value comparison nor the
claimed-identity comparison SHALL be reached for a far end with no interface, because a comparison
that indexes the missing value is what ends the evaluation instead of filling a row.

This is the condition the provider already earns `capability-interface-missing` for, and that row
SHALL keep its subject and its resolution: it names the module file that declared the capability and
says to pass the interface value in. The wire's row is a second row about a second subject - the
consumer that cannot resolve a slot - and SHALL NOT be suppressed because the provider's row exists.
Two entries have a problem, and a table filtered to either one of them SHALL show it.

A binding SHALL be refused unless it carries an interface. A hand-written record naming a member and
a capability is not a capability taken off a sibling's handle, so it SHALL earn the same
malformed-binding row a name or a record of any other shape earns, with the same message and the same
resolution, and the reading below the binding SHALL NOT index into it.

#### Scenario: A wire resolves to a capability declaring no interface

- **WHEN** a deployment wires a slot to an exposed capability whose declaration carries no interface
  value
- **THEN** the planner SHALL emit an error row naming the consuming entry, the slot and the capability
- **AND** the slot SHALL be absent from that consumer's resolved reads
- **AND** the table SHALL also carry the provider's own row naming the module file that declared the
  capability
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A root binds a slot to a record carrying no interface

- **WHEN** a root binds a member's slot to a hand-written record naming a member and a capability and
  carrying no interface
- **THEN** the planner SHALL emit the malformed-binding row naming the root, the member and the slot
- **AND** the slot SHALL be treated as one the deployment may fill, not as one the root bound
- **AND** every other entry of the deployment SHALL still be planned

### Requirement: A delivered read is verified against the consuming interface's own type

A value a read delivers SHALL be verified against the export type the consuming interface declares,
where the value crosses the wire, and that verification SHALL be the structural check of a typed
edge. A value the consumer's own declaration refuses SHALL leave the slot unfilled - absent from the
consumer's resolved reads rather than present and empty - and SHALL be one error row naming the
consuming entry, the slot and what the consuming interface's type reported.

Identity equality SHALL NOT be taken as a structural check. The verification SHALL be made whether
the two ends matched by value or by a claimed identity, and whether or not either end claims one, so
a provider publishing a value its consumer's declaration refuses SHALL be reported even where the two
ends agree on every name an identity carries.

The verification a provider already makes against its own interface SHALL stand and SHALL keep its
subject: a value failing the provider's own declared type is the provider's row and names no
consumer. The two SHALL be rows about two subjects, and a value one end accepts and the other refuses
SHALL earn only the row of the end that refused it.

What is compared SHALL be a value against a type and never a type against a type: the planner SHALL
still not verify that two matched interfaces agree on anything an identity does not carry. A value
both ends accept SHALL be delivered unchanged, and the verification SHALL change no delivery set, no
plan key and no read the plan records.

#### Scenario: A provider publishes a record the consuming interface refuses

- **WHEN** a provider and a consumer declare interfaces that match, one export is declared as a
  record on both sides, and the provider publishes a record its own declaration accepts and the
  consumer's declaration refuses
- **THEN** the planner SHALL emit an error row naming the consuming entry, the slot and what the
  consuming interface's type reported
- **AND** the slot SHALL be absent from that consumer's resolved reads
- **AND** the table SHALL report the plan as not applicable
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A consuming interface accepts the record it is delivered

- **WHEN** a read delivers a value the consuming interface's declared type accepts
- **THEN** the consuming implementation SHALL receive that value unchanged
- **AND** no row SHALL be emitted for the verification
- **AND** the delivery set of any generated value behind that export SHALL be the one the declared
  read produces without it

#### Scenario: A set-valued read verifies each provider against the consuming interface

- **WHEN** a slot reads one interface with set reach over several providers and one of them publishes
  a value the consuming interface's declared type refuses
- **THEN** the planner SHALL emit one error row naming the consuming entry, the slot and the
  contributing provider
- **AND** the slot SHALL be left unfilled rather than delivered as the set the refused provider was
  dropped from
- **AND** every other entry of the deployment SHALL still be planned

### Requirement: Attribution decides what a row says and never which rows exist

The interface attribution a deployment passes SHALL be attribution and never a registry. Every row an
interface can earn - about its claimed identity, about its fold, about its exports - SHALL be reached
from the modules that imported that interface, and an interface the attribution does not name SHALL
earn each of those rows exactly as a named one does.

Attribution SHALL change only what a row says about the file an interface was declared in. Adding or
removing an attribution entry SHALL NOT change whether the plan is applicable, SHALL NOT change any
value the plan records, and SHALL NOT change which conditions the table reports.

An interface the attribution names that no module of the deployment imported SHALL therefore earn no
row at all. Its declarations reach no entry, no wire and no export, so a malformed one SHALL be
neither checked nor reported: naming an interface registers nothing, and a list of names is not a set
of declarations the planner is asked to hold to anything.

#### Scenario: Attribution does not decide applicability

- **WHEN** one applicable deployment is planned twice, the second time with an interface named in its
  attribution that no module of it imports and whose declaration would earn an error row were a
  module to import it
- **THEN** both plans SHALL be applicable
- **AND** both SHALL record the same entries with the same keys and the same values
- **AND** no row SHALL be emitted about the named interface

#### Scenario: Attribution changes only the file a row names

- **WHEN** one deployment is planned twice, once with an imported interface named in its attribution
  and once without
- **THEN** each row either plan carries SHALL be carried by the other for the same condition
- **AND** the two SHALL differ only in how each such row names the declaring file
- **AND** both SHALL report the same plan and the same applicability
