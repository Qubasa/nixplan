<!--
A delta against `planner/typed-edge`, which lives in the unarchived `implement-minimal-typed-edge`
change and is already modified by `unify-declaration-and-implementation-readings`. One requirement
changes: `A slot may not read a secret export` (`implement-minimal-typed-edge/specs/planner/
typed-edge/spec.md:88-108`) becomes the opposite, because refusing the read was the stand-in for a
delivery mechanism this change adds. The three scenario headings are kept: each names a situation,
and it is the outcome that moves.

The refusal the corpus keeps for a private half rests on `locality`, which is still excluded
(`lib/excluded.nix:18-21`). Under this change a consumer that names a private half in `reads`
therefore receives it, and the requirement says so rather than implying a check that does not exist.
-->

## MODIFIED Requirements

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
