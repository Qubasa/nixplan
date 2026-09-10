## ADDED Requirements

### Requirement: A fold may carry a name

The planner SHALL provide a constructor that builds a fold from a name and a function, and an
interface SHALL be able to declare either such a named fold or a bare function. A named fold SHALL
behave in every respect as the bare function it carries: it is applied to the same set, under the same
guard, with the same result, and every row about a fold SHALL read the same for both spellings.

A fold's name SHALL be a non-empty string carrying no whitespace. A named fold whose name is not one
SHALL produce an error row against the interface's declaring file, and the fold SHALL then not be
applied: a set-valued read of that interface SHALL deliver the provider-keyed set unchanged.

A fold's name SHALL exist so that two interfaces built by two evaluations can be compared. Two folds
carrying one name SHALL NOT be required to be one function, and the planner SHALL NOT compare their
behaviour.

#### Scenario: A named fold folds

- **WHEN** a slot reads with set reach an interface declaring a named fold
- **THEN** the consuming implementation SHALL receive the fold's result as that slot's value
- **AND** the outcome SHALL be the one the same fold declared as a bare function produces

#### Scenario: A raising named fold

- **WHEN** an interface's named fold raises a catchable error for the set it is given
- **THEN** the planner SHALL emit the same row it emits for a bare fold that raises
- **AND** the slot SHALL be absent from the values the consuming implementation receives

#### Scenario: A fold name that is not a name

- **WHEN** an interface declares a fold whose name is empty or carries whitespace
- **THEN** the planner SHALL emit an error row whose subject is the interface's declaring file
- **AND** a set-valued read of that interface SHALL deliver the provider-keyed set unchanged

#### Scenario: A bare fold stays legal

- **WHEN** an interface declaring no `id` declares a fold as a bare function
- **THEN** the planner SHALL apply it
- **AND** SHALL NOT emit a row for the missing name
