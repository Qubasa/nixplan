## MODIFIED Requirements

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
