## ADDED Requirements

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
