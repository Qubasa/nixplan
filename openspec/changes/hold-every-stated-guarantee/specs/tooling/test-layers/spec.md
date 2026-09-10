<!--
A delta against `tooling/test-layers`, which lives in the unarchived `strip-planner-tests-to-unit-and-e2e`
change and was last restated by `open-the-repository-to-a-consumer`. The conditions are checks that
are green without exercising anything: `tests/unit/vars.nix:872` asserts
`unsafeDiscardStringContext s == s`, true of every string because Nix equality ignores context;
`tests/unit/interfaces.nix:696` compares two applications of one pure function to identical arguments;
`tests/e2e/generated-secret/test_generated_secret.py:291-293` compares a provenance record against the
values it was just written from, so the guard `CLAUDE.md` calls the only defence against a stale
stored value cannot fire; `tests/unit/operator.nix:467-470` expects the implementation's own call on
the same entry; and `perf/check.py` prints `0 failures` having compared nine of eighty-one gated
figures when eight result files are absent.
-->

## Purpose

Defines the test layers as evidence: a suite that is green has exercised what it claims, a check that
cannot fail is not kept, and a gate that measured nothing says so instead of passing.

## ADDED Requirements

### Requirement: A check that cannot fail is not kept

Every check SHALL be capable of failing on the condition it names. A check whose assertion holds for
every input, that compares a value to itself, that restates the expression under test as its own
expectation, or whose subject the fixture makes unreachable SHALL be either rewritten to assert the
behaviour it claims or removed.

Where the property a check claims cannot be observed by the assertion it makes, the check SHALL be
replaced by one that observes it, and SHALL NOT be kept as a weaker assertion under the original
name.

#### Scenario: An assertion holds for every input

- **WHEN** a check's assertion is true whatever the code under test does
- **THEN** it SHALL NOT remain in the suite
- **AND** the property it claimed SHALL be asserted by a check that fails when the property is lost

#### Scenario: A claimed property needs another observation

- **WHEN** the property a check names cannot be distinguished by the comparison it makes
- **THEN** the suite SHALL observe that property by a means that can distinguish it
- **AND** the check SHALL fail when the property is lost

#### Scenario: A guard compares a record with the values that wrote it

- **WHEN** a run compares stored state against a record derived from that same state in the same run
- **THEN** the comparison SHALL NOT be counted as a guard
- **AND** the guard SHALL be made against state the run did not itself just write

### Requirement: A gate that measured nothing refuses rather than passes

A gate over recorded figures SHALL refuse a run in which a figure it gates was not measured. A
missing measurement SHALL be a failure naming what was not measured, and SHALL NOT be reported as a
comparison that found nothing wrong.

The count of comparisons a gate made SHALL be reported, so that a run comparing fewer figures than
the gate covers is visible.

#### Scenario: A measurement is absent

- **WHEN** a gated figure has no measurement in the run
- **THEN** the gate SHALL fail naming the figure and what was not measured
- **AND** SHALL NOT report the run as having no failures

#### Scenario: Every gated figure was measured

- **WHEN** every figure the gate covers was measured
- **THEN** the gate SHALL report the number of comparisons it made
- **AND** the number SHALL equal the figures it covers
