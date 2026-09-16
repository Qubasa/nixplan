<!--
A delta against `tooling/repository-shape`, whose base text lives in the unarchived changes
`clean-up-transplant-residue`, `open-the-repository-to-a-consumer` and `hold-every-stated-guarantee`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The requirement below is ADDED. The existing requirements about which directories the root document
names and which commands it lists are unchanged; this adds one rule the document has to state,
because it is a rule every new deployment and every new folder re-decides otherwise.
-->

## ADDED Requirements

### Requirement: The root document states how a host path reaches a unit

`README.md` SHALL state that a deployment declares intent and never plumbing: a host path a unit
needs SHALL be derived by the module that needs it, from the identity of its own entry, or SHALL
reach the module through an export and a wire. The document SHALL state the two consequences a
reader can check - that no deployment declaration carries a host path, and that a test asserting one
reads it out of the plan - and SHALL state them beside the design goal they serve, that a service can
be instantiated more than once.

The rule SHALL be asserted rather than remembered: a literal from the document SHALL be read by the
suite that checks the tree's shape, so that deleting the rule from the document fails a check naming
the document.

#### Scenario: The root document states how a path reaches a unit

- **WHEN** the repository shape suite reads `README.md`
- **THEN** it SHALL find the rule about deriving a host path from the entry's identity
- **AND** the check SHALL fail if that text is removed
