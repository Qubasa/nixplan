## Purpose

Defines the second test layer of the planner: a whole-fleet test is a committed configuration directory plus assertions written against the serialised plan, so the deployment under test reads like a deployment an operator would write rather than a call to a test helper. It fixes the layer boundary against the existing per-row suite and states which tests cannot live here.

## ADDED Requirements

### Requirement: A scenario is a committed configuration directory

A scenario SHALL be a directory of configuration files in the same shape a real deployment uses: the interfaces it declares, the modules it composes, a machine registry, and an instance declaration. The harness SHALL evaluate those files as committed. A scenario SHALL NOT be produced by a helper that assembles instances, machines or modules from arguments, and the harness SHALL NOT inject any key that the documented authoring surface does not carry.

#### Scenario: A reader inspects what is under test

- **WHEN** a reader opens a scenario's instance declaration
- **THEN** it SHALL be a complete declaration of instances, their settings, their placement and their wires
- **AND** every module and interface it names SHALL resolve to a file in that same directory

#### Scenario: A scenario needs a construct the subset excludes

- **WHEN** a scenario cannot be written without a construct the planner refuses
- **THEN** that SHALL be recorded as a finding about the subset
- **AND** the harness SHALL NOT gain a key that exists only for tests

#### Scenario: A directory is added

- **WHEN** a new scenario directory is committed
- **THEN** the harness SHALL discover it without being told its name

### Requirement: The asserting half reads a serialised artifact

The evaluating half and the asserting half SHALL communicate through a serialised artifact carrying each scenario's plan, its diagnostics table and its applicability. The asserting half SHALL NOT evaluate configuration itself, SHALL NOT require an evaluator at run time, and SHALL run with no network access and no access to a build daemon.

#### Scenario: The suite runs as a check

- **WHEN** the project's checks are evaluated
- **THEN** the scenario suite SHALL appear among them
- **AND** SHALL execute with no network access and without invoking an evaluator

#### Scenario: A developer iterates on a scenario

- **WHEN** a developer asks for a scenario's result directly, without building a check
- **THEN** the artifact SHALL be produced from the same configuration as the check consumes
- **AND** the two SHALL be equal for an unchanged working tree

#### Scenario: The artifact is inspected by hand

- **WHEN** the artifact is read outside any test
- **THEN** it SHALL be a self-describing document that round-trips through serialisation
- **AND** SHALL carry no value that only an evaluator can interpret

### Requirement: A failure names the field that differs

A failing assertion SHALL identify the scenario, the plan entry or diagnostic row concerned, and the field whose value differed, and SHALL show the expected and actual values for that field. It SHALL NOT report only that two documents differ, and SHALL NOT print a whole plan or a whole diagnostics table in order to show one difference.

#### Scenario: One field of one entry drifts

- **WHEN** a produced entry differs from its expectation in a single field
- **THEN** the failure SHALL name the scenario, the entry and the field
- **AND** SHALL show both values for that field alone

#### Scenario: A row is missing

- **WHEN** a scenario expects a diagnostic row that the planner did not produce
- **THEN** the failure SHALL name the expected row's identifier and subject
- **AND** SHALL list the identifiers of the rows that were produced

### Requirement: Comparison and regeneration share one traversal

The comparison of a produced plan against a committed fixture and the regeneration of that fixture SHALL be implemented once and used by both. Regeneration SHALL remain a separate action from running the suite: a failing comparison SHALL leave every fixture on disk unchanged.

#### Scenario: A fixture is regenerated

- **WHEN** the documented regeneration command is run
- **THEN** the fixture on disk SHALL be replaced by the produced plan
- **AND** running the suite immediately afterwards SHALL pass

#### Scenario: A comparison fails

- **WHEN** a golden comparison fails
- **THEN** no fixture on disk SHALL be modified
- **AND** the failure SHALL name the differing paths

#### Scenario: The traversal changes

- **WHEN** the rule for which fields participate in a comparison changes
- **THEN** the change SHALL take effect in both the comparison and the regeneration
- **AND** SHALL be expressed in one place

### Requirement: Each test belongs to exactly one layer

The project SHALL document which layer a test belongs to, and the rule SHALL be decidable from the test's subject: a test about a single malformed declaration and the text of the row it produces belongs to the per-row suite, and a test about a whole fleet or about the shape of the plan artifact belongs to the scenario suite. A behaviour SHALL NOT be asserted in both layers.

#### Scenario: An author adds a test

- **WHEN** an author has a new behaviour to assert
- **THEN** the documented rule SHALL determine which layer receives it
- **AND** the rule SHALL be stated where the commands to run the suites are documented

#### Scenario: A behaviour is already covered

- **WHEN** a proposed test asserts a behaviour the other layer already asserts
- **THEN** it SHALL not be added
- **AND** the existing test SHALL be extended or moved instead

### Requirement: The specification cross-walk may name a scenario test

The mapping from specification scenarios to tests SHALL accept a test in either layer. A mapping entry naming a scenario-suite test SHALL fail the coverage check when no test of that name exists, in the same way as an entry naming a test of the per-row suite.

#### Scenario: A heading maps to a scenario test

- **WHEN** a specification scenario is mapped to a test of the scenario suite
- **THEN** the coverage check SHALL treat the heading as covered
- **AND** SHALL verify that the named test exists

#### Scenario: A mapped scenario test is renamed

- **WHEN** a mapped scenario-suite test is renamed or deleted
- **THEN** the coverage check SHALL fail
- **AND** SHALL name the mapping entry that no longer resolves

### Requirement: A scenario whose result cannot be serialised is refused loudly

A refused read leaves the consuming module without the slot, so a module that dereferences it raises an error the planner cannot catch. The harness SHALL NOT emit a partial artifact for such a scenario: it SHALL fail, SHALL name the scenario, and SHALL state that the scenario belongs to the per-row suite. One unserialisable scenario SHALL NOT prevent the remaining scenarios from being asserted.

#### Scenario: A scenario dereferences a refused read

- **WHEN** serialising a scenario raises because a module read a slot that did not deliver
- **THEN** the harness SHALL fail naming that scenario
- **AND** SHALL state that such a case is asserted in the per-row suite

#### Scenario: Another scenario is unaffected

- **WHEN** one scenario cannot be serialised
- **THEN** every other scenario SHALL still be asserted
- **AND** its result SHALL NOT depend on the failing one

### Requirement: A scenario no test names is a failure

Every discovered scenario SHALL be asserted by at least one test. A scenario directory that no test names SHALL fail the suite, naming the directory, so that fixtures cannot accumulate unread.

#### Scenario: A scenario loses its last test

- **WHEN** the only test naming a scenario is deleted
- **THEN** the suite SHALL fail
- **AND** SHALL name the scenario directory that nothing asserts
