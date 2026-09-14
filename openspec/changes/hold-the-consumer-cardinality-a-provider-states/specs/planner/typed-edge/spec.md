<!--
A delta against `planner/typed-edge`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `unify-declaration-and-implementation-readings`,
`deliver-secrets-across-machines`, `hold-declaration-shape-and-fold-set-reads`,
`identify-interfaces-by-declared-id` and `cut-a-member-and-wire-its-place`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The one requirement below is `cut-a-member-and-wire-its-place`'s "A capability may be declared to be
taken once", restated rather than joined by a second requirement about the same rule. What that text
said about the count is unchanged word for word in substance: deployment-wide, over wires, a binding
counted as a wire, one consumer placed on many machines counted once, a capability declaring nothing
taken by any number, and one capability per entry of a settings-valued declaration counted on its
own. What it did not say is by which name the declared cardinality is read, and a reading that takes
the name a root published finds nothing wherever the root renamed the capability, which reads as a
provider that never declared a limit. Its four scenarios are kept with their titles, so the tests
they name keep answering for them; the first gains the words "under the member's own name", because
that is the case the tree exercised and the case a fix must not regress.
-->

## MODIFIED Requirements

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
