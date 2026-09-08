<!--
A delta on `tooling/nix-unit-suite`, which is defined in the unarchived
`implement-minimal-typed-edge` change. Only the cross-walk requirement changes: the mapping stops
being a committed table of heading-to-test pairs and becomes a function of the heading, with the
exceptions a function cannot produce written out. The rest of that capability - the one-command
run, the totality property and the golden comparison - is unaffected and is not restated here.
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
