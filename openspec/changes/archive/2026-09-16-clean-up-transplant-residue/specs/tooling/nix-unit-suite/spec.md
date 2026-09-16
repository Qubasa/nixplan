<!--
A delta on `tooling/nix-unit-suite`, whose cross-walk requirement is currently defined in the
unarchived `strip-planner-tests-to-unit-and-e2e` change. Only that requirement changes, and only by
one sentence: the two lists the cross-walk carries are themselves checked against the
specifications, so an entry that has outlived its specification is a failure. The rest of the
capability - the one-command run, the totality property and the golden comparison - is unaffected
and is not restated here.
-->

## MODIFIED Requirements

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
