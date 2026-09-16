## ADDED Requirements

### Requirement: A row originates in the library or in a guarded interface fold

Every diagnostics row SHALL be produced by the planner. A module SHALL have exactly one channel
through which it can refuse something another module supplied: the fold of an interface it declares,
applied under the planner's guard. For such a refusal the module SHALL supply text only, and the
planner SHALL supply the row's identifier, its subject and its severity.

A module SHALL NOT declare the severity of a row. An implementation SHALL NOT carry a field through
which it returns rows: a key an implementation is not defined to return SHALL be reported as an
unknown implementation key, and the report SHALL name the fold as the place a refusal belongs.

#### Scenario: A module declares a severity

- **WHEN** a module's declaration carries a severity
- **THEN** the planner SHALL read and discard it, and SHALL emit a warning row saying so
- **AND** every other row the planner produced for that module SHALL keep the severity the planner
  gave it

#### Scenario: An implementation returns a refusals field

- **WHEN** an implementation returns a field intended to carry refusals
- **THEN** the planner SHALL emit an error row naming that key as one an implementation does not
  return
- **AND** the row SHALL name the interface fold as where a refusal of another module's value belongs

#### Scenario: A fold refuses a provider

- **WHEN** an interface's fold refuses a provider's value and states why
- **THEN** the row SHALL carry the planner's identifier, the consuming entry as its subject and the
  planner's severity
- **AND** the row SHALL carry the fold author's own message

#### Scenario: One bad provider read by two consumers

- **WHEN** two consuming entries read a set containing the same refused provider
- **THEN** the planner SHALL emit one row per consuming entry, each naming its own subject
- **AND** neither row SHALL be dropped as a duplicate of the other

#### Scenario: A module raises outside a fold

- **WHEN** a module's own expression raises a catchable error anywhere other than a fold
- **THEN** the planner SHALL emit the row it already emits for a raising module, naming what was
  being forced
- **AND** the module's own text SHALL NOT become the row's message
