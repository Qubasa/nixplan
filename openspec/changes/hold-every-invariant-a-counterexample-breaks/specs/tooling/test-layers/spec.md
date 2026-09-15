<!--
A delta against `tooling/test-layers`, whose base text lives in the unarchived changes
`strip-planner-tests-to-unit-and-e2e`, `apply-deployments-with-an-operator-command`,
`resume-e2e-machines-from-snapshots`, `run-a-shared-database-on-real-machines`,
`report-a-secrets-refusal-as-a-row`, `hold-every-stated-guarantee`,
`give-every-instance-its-own-database`, `open-the-repository-to-a-consumer` and
`state-no-host-path-in-a-deployment`. `openspec/specs/` is empty in this repository, so the base
text is read from those changes.

The first requirement is MODIFIED and reads against `A planner test belongs to one of two layers`
in `strip-planner-tests-to-unit-and-e2e`, which this change restates in full, under a title its own
text makes true: the tree now holds three directories rather than two
(`tests/unit/layers.nix:883-899`). Its three scenarios are kept with their titles, so the tests they
name keep answering for them, and one is added. The reason for the third kind is mechanical and
verified: `builtins.tryEval (({a}: a) { a = 1; b = 2; })` propagates on nix 2.34.8, and a nix-unit
`expr` that raises that way ends the run that would have reported it instead of failing one
assertion, so the 17 attributes of `tests/counterexamples/probes.nix` are evaluated one process each
by `checks.planner-counterexamples-eval`, whose loop reads `builtins.attrNames probes`
(`flake-module.nix:327`) rather than a list of names. The 8 counterexamples about the operator's
command are `cli/counterexample_test.py`, run by `checks.planner-counterexamples-cli`
(`flake-module.nix:346-355`), because the command is run and not evaluated.

The second requirement is ADDED and reads against `A specification scenario names its test` in the
same base change, whose derivation of a test name from a scenario heading is what makes a
counterexample answerable at all, and whose cross-walk counts the evaluating suites, the machine
folders and `perf/check_test.py` (`tests/unit/coverage.nix:339-345`) but no test of the command.
48 of the 49 counterexamples this change lands are red on the tree as committed, each quoting the
sentence it breaks, and two of them assert a claim this change narrows rather than holds, which is
why withdrawal has to leave a test behind.
-->

## MODIFIED Requirements

### Requirement: A planner test belongs to one of three kinds

The tests of this package SHALL form exactly three kinds, and the kind SHALL be readable from the
directory a test is in. Which kind a claim is asserted in SHALL follow from how that claim fails,
never from an author's preference.

One kind SHALL assert the library and the realisers by evaluation alone, with no machine and no
built output, reporting every assertion of one run.

One kind SHALL assert a claim whose counterexample ends the evaluation rather than failing an
assertion - a call of something that is not a function, a missing attribute, a coercion of a
function - because such a failure takes the run that would have reported it instead of being
reported by it. A claim of that shape SHALL be one named attribute asserting one condition,
evaluated in a process of its own, one process per attribute, so that a claim that ends its own
evaluation costs the report of no other claim. The attribute SHALL answer that the condition is
fixed, that answer SHALL be what decides whether the claim holds, and an attribute that answers so
SHALL be kept as the regression pin rather than removed.

One kind SHALL assert behaviour on running machines.

A claim about a program that is run rather than evaluated - the operator's command - SHALL be
asserted in that program's own language, beside the program, and SHALL be run by a check of its own.
Such a test SHALL assert nothing that evaluation alone can answer.

Each kind SHALL be registered where its layer is registered, and adding a member of a kind SHALL be
one registration and no other edit. No kind SHALL be gated by a hand-written list of its members: an
attribute asserting a claim that ends an evaluation SHALL be discovered by existing, so that adding
one is adding the attribute and the check evaluates it without being edited.

There SHALL be no fourth kind, and no place for a test whose participants are neither values, nor a
process the check starts, nor machines. The harness that boots the machines MAY carry tests of its
own code beside itself; such a test SHALL assert nothing about the planner.

#### Scenario: The test tree is read

- **WHEN** the package's test directory is listed
- **THEN** it SHALL name exactly the three kinds and nothing else
- **AND** a reader SHALL be able to say which kind a claim is in from that name alone
- **AND** the kind that asserts a claim ending its own evaluation SHALL be named separately from the
  kind that reports many assertions of one run

#### Scenario: A unit test needs no machine

- **WHEN** the evaluating layer is read
- **THEN** every file in it SHALL be a Nix file
- **AND** no file in it SHALL name a built output, a store path it realises, or a program it runs

#### Scenario: An end-to-end test needs a machine

- **WHEN** the machine layer is read
- **THEN** every test in it SHALL be a directory holding one test file
- **AND** the layer's root SHALL hold only the harness those tests share

#### Scenario: A probe is discovered rather than listed by hand

- **WHEN** an attribute asserting a claim that ends an evaluation is added
- **THEN** the check that evaluates those attributes SHALL evaluate the new one without being edited
- **AND** each attribute SHALL be evaluated in a process of its own, so one that ends its evaluation
  SHALL leave every other one reported
- **AND** the check SHALL report, per attribute, whether the claim holds

## ADDED Requirements

### Requirement: An invariant is held by a test asserting the claim rather than the behaviour

A test of an invariant this repository records SHALL assert the claim the repository states, and not
the behaviour the code exhibits. It SHALL carry the sentence it pins, so that a failure reads as the
claim that is false rather than as two values that differ, and so that a reader can find where the
claim is stated without reading the code the test exercises.

A test of that kind SHALL be red for as long as the claim is false, and being red SHALL be
information rather than a defect of the test. It SHALL NOT be relaxed to what the code does today,
SHALL NOT be marked as expected to fail, and SHALL NOT be withheld from the suite until the claim is
made true: an unasserted claim is a claim nobody notices losing.

A claim made true SHALL leave its test in place as the regression pin, under the title it already
carries, so that the test which found the defect is the test that keeps it out.

A claim withdrawn or narrowed SHALL leave its test rewritten to the narrowed claim and quoting the
narrowed sentence, rather than deleted. The narrowing SHALL be recorded where the claim is stated, so
that the sentence a test quotes is a sentence the repository still states, and a quote of a sentence
nobody states any more SHALL fail rather than pass unread.

Every test of a recorded invariant SHALL be counted as a test by the specification cross-walk,
whatever language it is written in, the tests of the operator's command included. A scenario whose
derived name names one SHALL be answered by it exactly as a scenario naming an evaluating test or a
machine test is answered, and the rule that one name SHALL NOT exist in two layers SHALL hold across
every counted kind.

#### Scenario: A counterexample quotes the claim it pins

- **WHEN** a test asserts an invariant the repository records
- **THEN** it SHALL carry the sentence that invariant is stated in
- **AND** that sentence SHALL be one the repository still states, so a withdrawn claim fails until
  its test quotes the narrowed one
- **AND** a test asserting today's behaviour instead SHALL NOT be counted as holding the invariant

#### Scenario: The command's own tests are counted

- **WHEN** the specification cross-walk collects the tests that answer for scenarios
- **THEN** the tests written in the operator's command's own language SHALL be among them
- **AND** a scenario whose derived name names one SHALL be reported as observed
- **AND** a derived name carried by two kinds at once SHALL still fail the check naming both
