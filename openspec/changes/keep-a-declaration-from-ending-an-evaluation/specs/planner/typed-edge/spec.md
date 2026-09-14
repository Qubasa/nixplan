<!--
A delta against `planner/typed-edge`, whose base text lives in the unarchived
`implement-minimal-typed-edge` change and was extended by `deliver-secrets-across-machines`,
`identify-interfaces-by-declared-id`, `unify-declaration-and-implementation-readings`,
`cut-a-member-and-wire-its-place` and `hold-declaration-shape-and-fold-set-reads`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The requirement below is ADDED. It does not restate `A wire names an exposed capability of a named
instance` (the base) or `A root may bind a member's slot to a capability it holds`
(`cut-a-member-and-wire-its-place`), both of which stand: a wire still names an exposed capability
and a binding is still subject to every check a wire is. What is added is the step before either
check can run, which is that the far end has to carry an interface value at all. `provides` reaches
the wire as the author's own record rather than as the validated reading, so the absence the provider
already earns `capability-interface-missing` for is, at the wire, an index into nothing.
-->

## ADDED Requirements

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
