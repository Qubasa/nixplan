## Purpose

Defines the test contract for the planner library: how the suite runs, what it has to cover, and the two properties that are checked by construction rather than case by case. A library whose whole subject is refusing things has to demonstrate each refusal, so coverage here is an obligation rather than a target.

## ADDED Requirements

### Requirement: The suite runs from the flake with one command

The test suite SHALL be runnable with a single command against a clean checkout, SHALL require no network access beyond resolving the pinned inputs, and SHALL exit non-zero when any test fails. Failure output SHALL name the failing test and show the expected and actual values.

#### Scenario: A developer runs the suite

- **WHEN** the documented command is run on a clean checkout
- **THEN** every test SHALL execute
- **AND** the exit status SHALL reflect whether any failed

#### Scenario: A test fails

- **WHEN** one test's actual value differs from its expected value
- **THEN** the output SHALL name that test
- **AND** SHALL show both values

#### Scenario: The suite is part of the checks

- **WHEN** the flake's checks are evaluated
- **THEN** the suite SHALL appear among them
- **AND** SHALL be runnable without naming it separately

### Requirement: Every spec scenario maps to a named test

Each scenario in this change's planner specifications SHALL correspond to a test whose name identifies it. A scenario the suite deliberately does not exercise SHALL be listed with the reason it is not exercised. The mapping SHALL live in the repository rather than in a change proposal, so it survives archiving.

#### Scenario: A scenario gains no test

- **WHEN** a specification scenario has neither a test nor an entry in the list of deliberate omissions
- **THEN** the coverage check SHALL fail
- **AND** SHALL name the scenario

#### Scenario: A scenario is deliberately not tested

- **WHEN** a scenario is listed as not exercised with a reason
- **THEN** the coverage check SHALL pass
- **AND** the reason SHALL appear in the check's output

### Requirement: Total evaluation is checked as a property

The suite SHALL contain a test that deeply forces the result of evaluating a deployment carrying every authoring mistake the specifications describe, and asserts that the evaluation completes. It SHALL NOT satisfy this by catching failures per case.

#### Scenario: A new check raises

- **WHEN** a newly added check raises instead of returning a record
- **THEN** the property test SHALL fail
- **AND** the failure SHALL be attributable to that check

#### Scenario: The assertion entry point is used

- **WHEN** a library source file uses the type library's raising entry point
- **THEN** a test SHALL fail naming the file
- **AND** the check SHALL be over the source text rather than over one evaluation path

### Requirement: Golden comparisons print a usable difference

A test comparing a produced artifact against a committed fixture SHALL, on failure, report which keys and fields differ rather than printing both artifacts in full. A fixture SHALL be regenerable by a documented command, and regenerating SHALL be a separate action from running the suite.

#### Scenario: A golden fixture drifts

- **WHEN** the produced plan differs from its fixture in one field of one entry
- **THEN** the failure SHALL name that entry and that field
- **AND** SHALL NOT print the whole plan

#### Scenario: A fixture is regenerated

- **WHEN** the documented regeneration command is run
- **THEN** the fixture on disk SHALL be replaced by the produced artifact
- **AND** running the suite immediately afterwards SHALL pass

#### Scenario: Regeneration is not automatic

- **WHEN** the suite is run and a golden comparison fails
- **THEN** the fixture on disk SHALL be unchanged
