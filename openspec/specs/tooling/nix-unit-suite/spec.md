# tooling/nix-unit-suite Specification

## Purpose
Defines the test contract for the planner library: how the suite runs, what it has to cover, and the two properties that are checked by construction rather than case by case. A library whose whole subject is refusing things has to demonstrate each refusal, so coverage here is an obligation rather than a target.

## Requirements

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

Each scenario in this project's planner specifications SHALL correspond to a test whose name
identifies it. The correspondence SHALL be derived from the scenario's heading rather than recorded
as a pair: a heading SHALL yield one test name, spelled in the convention of the layer the test is
in. A scenario the project deliberately does not exercise SHALL be listed with the reason it is not
exercised. A scenario observed by a test named after a different heading SHALL be listed with that
test's name. Nothing else SHALL be listed, and a scenario that is neither derived, aliased nor
excused SHALL fail the coverage check. The derivation and both lists SHALL live in the repository
rather than in a change proposal, so they survive archiving.

Every list the cross-walk carries SHALL be checked in both directions. A specification the project
answers for that no longer exists SHALL fail, and so SHALL an entry excusing, aliasing or omitting
something that no longer exists, naming the entry and what it referred to. A list SHALL NOT be
allowed to accumulate entries for files and headings that are gone, because such an entry reads as
a decision the project has taken about something it no longer has.

#### Scenario: A scenario gains no test

- **WHEN** a specification scenario has neither a test of its derived name, an entry naming the
  test that observes it, nor an entry in the list of deliberate omissions
- **THEN** the coverage check SHALL fail
- **AND** SHALL name the scenario

#### Scenario: A scenario is deliberately not tested

- **WHEN** a scenario is listed as not exercised with a reason
- **THEN** the coverage check SHALL pass
- **AND** the reason SHALL appear in the check's output

#### Scenario: A test name is derived from a heading

- **WHEN** a scenario heading is turned into a test name
- **THEN** the result SHALL be a function of that heading's words alone
- **AND** the same heading SHALL yield the same name every time it appears, in whichever capability
  it appears

#### Scenario: An excuse outlives its specification

- **WHEN** the cross-walk excuses a specification that is no longer in the repository
- **THEN** the coverage check SHALL fail
- **AND** SHALL name the entry and the path it referred to

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

### Requirement: A malformed declaration is planned rather than scanned for

The suite SHALL plan a malformed declaration of each shape a declaration has and SHALL assert the row
the planner produces for it, so that a reading which indexes into a declaration before it checks its
shape fails the suite rather than ending it.

Each probe's assertion SHALL be over the row's identifier and subject. A probe that asserted only that
the evaluation completed SHALL NOT be taken as coverage of that shape, because a reading that dropped
the declaration silently would pass it.

The suite SHALL NOT rely on the source scan for this property. The scan matches call spellings as
substrings, and the conditions here are an index into a value the reading was handed, so a scan that
could see them would also have to refuse every index the library makes into a value it built itself.

A probe SHALL assert that the rest of the deployment was still planned, so that a reading which
recovers by abandoning the deployment is distinguishable from one which recovers by reporting the
declaration.

#### Scenario: A probe plans every malformed shape at once

- **WHEN** one deployment carries a malformed record of every shape a declaration has, a module whose
  declaration raises, a wire to an untyped capability and a hand-written binding, beside one instance
  that is well formed
- **THEN** deeply forcing the plan and the table SHALL succeed
- **AND** the table SHALL carry one row per mistake
- **AND** the well-formed instance SHALL still be planned in full

#### Scenario: A probe names the declaration it planned

- **WHEN** a probe plans one malformed declaration
- **THEN** its expectation SHALL be the row's identifier and its subject
- **AND** a reading that produced no row for that shape SHALL fail the probe naming the identifier it
  expected
