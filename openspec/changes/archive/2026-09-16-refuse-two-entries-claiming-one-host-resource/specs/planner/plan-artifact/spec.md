<!--
A delta against `planner/plan-artifact`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `prove-plan-on-real-machines`, `declare-service-state`,
`generate-values-with-nixos-secrets`, `open-a-delivered-value-to-its-reader`,
`cut-a-member-and-wire-its-place` and `hold-every-stated-guarantee`. `openspec/specs/` is empty in
this repository, so the base text is read from those changes.

The requirement below is ADDED beside the existing `An implementation is handed the machine it was
planned for`, which it does not change. `prove-plan-on-real-machines` states that an implementation
learns the machine and the target it was planned for; this adds the other half of the entry's own
identity, so that a module can name a resource after the entry rather than after the module.
-->

## ADDED Requirements

### Requirement: An implementation is handed the member it belongs to

A module's implementation SHALL be handed the name of the member it is, beside the instance it
belongs to and the machine it was planned for. The pair SHALL be the same pair the entry's plan key
is built from, so that a name derived from it is unique among the entries of one machine by
construction rather than by convention.

The name handed SHALL be the member's identity in its composing root - the attribute key the root
declared it under - and never a second spelling carried inside the member, so that a name a module
derives is the name every plan key, settings namespace and diagnostics subject already uses. A member
name that could make the pair ambiguous is refused before any key exists, so a module SHALL be able
to interpolate what it is handed without escaping it.

Adding the argument SHALL move no entry key and no plan record: the instance and the member are
already inputs to every entry's key, so a module that ignores the new argument SHALL plan exactly as
it did.

#### Scenario: An implementation derives a name from its own entry

- **WHEN** a placed member's implementation reads the instance and the member it was handed
- **THEN** both SHALL equal the instance and the member its plan key is built from

#### Scenario: Two members of one instance derive two names

- **WHEN** one root composes two members of one leaf module and both are placed on one machine
- **THEN** each implementation SHALL be handed its own member name
- **AND** a path each derives from it SHALL differ between the two entries

#### Scenario: The member handed is the attribute key of the member

- **WHEN** a member is composed under one attribute key and carries a different name inside itself
- **THEN** the implementation SHALL be handed the attribute key
- **AND** the disagreement SHALL remain the row it already is

#### Scenario: A module that ignores the argument plans as it did

- **WHEN** a deployment whose modules read neither the instance nor the member is planned
- **THEN** every entry key SHALL be the key it was before the argument existed
