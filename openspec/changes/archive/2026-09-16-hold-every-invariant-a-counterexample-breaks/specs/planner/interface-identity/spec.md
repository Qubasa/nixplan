<!--
A delta against `planner/interface-identity`, whose base text lives in the unarchived change
`identify-interfaces-by-declared-id` and whose row-scope half is held by
`hold-every-stated-guarantee`. `openspec/specs/` is empty in this repository, so the base text is
read from those changes.

The requirement below is ADDED. It reads against `An identity is the claim and the shape it claims
to have` and `A claim decides only whether an edge exists`, both of which stand: a claim is still
the declared identifier, each export's name, each export's type name and resolved secrecy, and the
fold's name, two claims are still compared by equality of exactly that, and a matched claim still
decides only that an edge exists. What is added is the depth that claim has, stated rather than
implied. `korora/types.nix:485-489` builds a record type as a name, a verifier and an override, so
two record types of one name over two member sets are equal to anything that cannot hash a
function, and the whole schema is outside the claim: `tests/unit/counterexamples.nix:566` claims one
identifier over two member sets, the wire resolves, and the consumer is rendered from a record its
own declared type refuses.

That counterexample also asserts that the two claims do not compare equal, which is a statement
about how deep a type's own name is and is left to the implementation. This requirement does not
rest on it: the refusal it points at is made at the wire by `A delivered read is verified against
the consuming interface's own type`, which this change adds to `planner/typed-edge`, and that
refusal holds whether or not two record types can be told apart by name.
-->

## ADDED Requirements

### Requirement: A claimed identity is nominal and name-deep, and says so

A claimed identity SHALL be documented as nominal and name-deep. It SHALL carry the claimed
identifier, each export's name, each export's declared type name and resolved secrecy, and the fold's
name, and it SHALL carry nothing about the values any of those names admits.

A claimed identity SHALL NOT be presented as a structural fingerprint. Nothing SHALL rest on a claim
having told apart two interfaces whose declared record shapes differ: the planner SHALL NOT be
required to distinguish them, and no refusal SHALL be conditioned on its having done so. Where two
claims compare equal, an edge between those two ends SHALL resolve exactly as an edge between two
ends holding one value does, whatever the shapes behind the names are.

Deepening the claim SHALL NOT be required of the planner, and the reason SHALL be recorded beside the
trade rather than left for a reader to rediscover: the type library this planner is written against
exposes a record type as a name, a verifier and an override, so a shape is a function a claim cannot
see and two evaluations cannot compare. A claim that could see a record shape is not a claim this
planner can compute, and a refusal conditioned on one is not a refusal it can make.

The structural check SHALL instead be made where a value crosses the wire, against the consuming
interface's own declared export type. That check SHALL catch two disagreeing shapes whatever the two
interfaces are named and whether or not either end claims an identifier, so the failure a claimed
identifier exists to catch SHALL be caught by the value it delivers rather than by the claim.

#### Scenario: A claimed identity does not collapse two struct schemas

- **WHEN** a provider and a consumer claim one identifier, each declaring one export as a record type
  of one name over a different member set, and the provider publishes a record its own declaration
  accepts
- **THEN** the claim SHALL NOT be taken as evidence that the two record shapes agree
- **AND** the value delivered SHALL be verified against the consuming interface's own declared type,
  and a record that type refuses SHALL leave the slot unfilled with an error row naming the consuming
  entry and the slot
- **AND** the table SHALL report the plan as not applicable
- **AND** every other entry of the deployment SHALL still be planned
