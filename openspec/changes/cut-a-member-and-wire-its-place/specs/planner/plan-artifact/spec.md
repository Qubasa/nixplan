<!--
A delta against `planner/plan-artifact`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`, `prove-plan-on-real-machines`,
`deliver-secrets-across-machines`, `generate-values-with-nixos-secrets`,
`report-every-refusal-as-a-row`, `identify-interfaces-by-declared-id`, `declare-service-state`,
`deliver-a-secret-without-exposing-it` and `hold-every-stated-guarantee`. `openspec/specs/` is empty
in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The entry key's grammar, what an entry records, which fields are
pruned and which are always present, and the input-addressed key input are all unchanged - and that
they are unchanged is what the first requirement below asserts about a cut.
-->

## ADDED Requirements

### Requirement: A cut member produces no entry, and no entry that remains moves

A member an instance cut SHALL contribute nothing to the plan: no placed entry, no unplaced entry, no
generated value entry, and no name in any other entry's `dependsOn`. The absence SHALL be an absence
of records rather than a record marked absent.

Every entry the instance still produces SHALL carry the key it carries when nothing is cut, provided
nothing else about it changed. A deployment that cuts a member SHALL therefore redeliver nothing but
what the cut itself changed: the entries whose reads moved from a sibling's capability to a wired
one.

No field of the plan SHALL record that a composition was cut, or which members an instance kept. A
reader holding the plan SHALL be unable to tell an operator's cut from a module that never published
the member, because the two produce the same entries - which is what makes a cut an authoring
decision rather than a plan field.

#### Scenario: The entries of a kept member are unchanged by a cut

- **WHEN** one instance keeps every member and a second cuts a member no kept member's binding named
- **THEN** every entry the second instance produces SHALL carry the key the first instance's
  corresponding entry carries
- **AND** the plan SHALL carry no entry for the cut member

#### Scenario: A cut member's generated value is not recorded

- **WHEN** a cut member declares a generator
- **THEN** the plan SHALL carry no value entry for it
- **AND** no entry SHALL name it in `dependsOn`

#### Scenario: The plan does not say what was cut

- **WHEN** two deployments produce the same entries, one by cutting a member and one by naming a
  module that never published it
- **THEN** the two plans SHALL be equal
- **AND** no field SHALL distinguish them

#### Scenario: A consumer whose read moved to a wired provider

- **WHEN** an instance cuts the member a slot was bound to and wires the slot to another instance's
  capability
- **THEN** the consuming entry's key SHALL differ from the uncut instance's corresponding entry
- **AND** the difference SHALL be the resolved read, which the key input already carries
- **AND** no other entry of that instance SHALL move
