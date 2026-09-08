<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It replaces
`tooling/scenario-suite` in the unarchived `add-scenario-test-harness` change, whose requirements
this change removes, and it reads against `tooling/nix-unit-suite` in `implement-minimal-typed-edge`,
which owns the unit layer's own contract, and against `delivery/real-cluster` in
`prove-plan-on-real-machines`, which owns what a real machine is asked.
-->

## Purpose

Defines where a claim about the planner is asserted and how a reader finds it: that there are two
layers and no third, that an end-to-end test's fixture is a directory belonging to that test rather
than a corpus a separate suite reads, that a specification scenario names its test by construction
instead of through a committed table, and that a behaviour observed on a real machine is not also
asserted against a stand-in.

## ADDED Requirements

### Requirement: A planner test belongs to one of two layers

The tests of this package SHALL form exactly two layers, and the layer SHALL be readable from the
directory a test is in. One layer SHALL assert the library and the realisers by evaluation alone,
with no machine and no built output. The other SHALL assert behaviour on running machines. There
SHALL be no third layer, and no place for a test whose participants are neither values nor
machines. The harness that boots the machines MAY carry tests of its own code beside itself; such a
test SHALL assert nothing about the planner.

#### Scenario: The test tree is read

- **WHEN** the package's test directory is listed
- **THEN** it SHALL name exactly the two layers and nothing else
- **AND** a reader SHALL be able to say which layer a claim is in from that name alone

#### Scenario: A unit test needs no machine

- **WHEN** the evaluating layer is read
- **THEN** every file in it SHALL be a Nix file
- **AND** no file in it SHALL name a built output, a store path it realises, or a program it runs

#### Scenario: An end-to-end test needs a machine

- **WHEN** the machine layer is read
- **THEN** every test in it SHALL be a directory holding one test file
- **AND** the layer's root SHALL hold only the harness those tests share

### Requirement: An end-to-end test carries its own fixture

An end-to-end test's configuration under test SHALL live in that test's own directory: the
interfaces it declares, the modules it composes, its machine registry, its instance declaration and
the realisation of them. A test SHALL NOT read a file belonging to another end-to-end test. A
fixture every end-to-end test needs SHALL live at the layer's root as part of the harness, and
SHALL be the only thing a test reaches upwards for.

#### Scenario: A reader opens an end-to-end directory

- **WHEN** a reader opens an end-to-end test's instance declaration
- **THEN** every module and interface it names SHALL resolve to a file in that same directory
- **AND** the machine registry it is placed against SHALL be in that same directory

#### Scenario: An end-to-end test reads a file of another end-to-end test

- **WHEN** a test names a path inside a sibling end-to-end directory
- **THEN** the check SHALL fail
- **AND** SHALL name both directories

#### Scenario: A fixture is needed by every end-to-end test

- **WHEN** a fixture is required by more than one end-to-end test
- **THEN** it SHALL live at the layer's root rather than be copied into each directory
- **AND** what it guarantees SHALL be stated where it is defined, so a removal fails a build rather
  than a boot

#### Scenario: An end-to-end test is deleted

- **WHEN** an end-to-end test's directory is removed
- **THEN** nothing outside the harness and the specification cross-walk SHALL still refer to it
- **AND** no fixture SHALL be left behind that nothing reads

### Requirement: A specification scenario names its test

The correspondence between a specification scenario and the test that observes it SHALL be a
function of the scenario's heading, not a committed table of pairs. The same heading SHALL yield the
same test name in every layer, spelled in each layer's own convention. Where a heading names no test
of that name, the cross-walk SHALL carry either the name of the test that observes the same
behaviour under a different heading, or the reason the scenario is unobserved, and nothing else.

#### Scenario: A scenario heading is reworded

- **WHEN** a scenario's heading text changes and its test is not renamed with it
- **THEN** the coverage check SHALL fail
- **AND** SHALL show both the name the heading now requires and the name that exists

#### Scenario: A scenario is observed under another heading

- **WHEN** two capabilities describe one behaviour in different words
- **THEN** the cross-walk SHALL name the single test that observes it
- **AND** the check SHALL NOT require a second test to exist

### Requirement: A behaviour is asserted in one layer only

A behaviour SHALL be asserted in one layer. A test name that exists in both layers SHALL fail the
coverage check, naming the behaviour and both files, rather than being left to an author's
judgement.

#### Scenario: One behaviour is asserted in both layers

- **WHEN** a test name derived from one heading exists in both layers
- **THEN** the coverage check SHALL fail
- **AND** SHALL name the heading and the two files that carry it

### Requirement: No observation about the planner is produced by a double

No test of this package SHALL assert the planner's behaviour against a stand-in for a program a
machine would run. Where an observation needs a service manager, a portable-service manager, a
store-copy tool or a network, it SHALL use the machine's own, and therefore SHALL be in the machine
layer.

#### Scenario: A test writes a stand-in for a system binary

- **WHEN** a test creates an executable standing in for a program the realiser's output invokes
- **THEN** the check SHALL fail
- **AND** SHALL name the test and the program it stood in for

### Requirement: Each layer runs from one command

The evaluating layer SHALL be a check of the flake and SHALL run wherever the flake evaluates. The
machine layer SHALL be one command that runs every end-to-end test, SHALL accept the name of one
end-to-end test to run alone, and SHALL NOT appear among the flake's checks, because a build
sandbox cannot boot a machine. That command SHALL refuse before starting any machine when the host
cannot provide what a machine needs, naming what is missing.

#### Scenario: A developer runs every end-to-end test

- **WHEN** the documented machine-layer command is run with no arguments
- **THEN** every end-to-end test SHALL execute
- **AND** the exit status SHALL reflect whether any failed

#### Scenario: A developer runs one end-to-end test

- **WHEN** the command is given the name of one end-to-end test
- **THEN** only that test SHALL execute
- **AND** an unknown name SHALL be refused naming the tests that exist

#### Scenario: The host cannot provide what a machine needs

- **WHEN** the command is run on a host missing a device, a kernel module or a permission a
  machine needs
- **THEN** it SHALL refuse naming each missing thing and why a machine needs it
- **AND** no machine SHALL have been started

#### Scenario: No end-to-end test appears among the checks

- **WHEN** the flake's checks are evaluated
- **THEN** no check SHALL require a machine to boot
- **AND** the machine layer SHALL be reachable as a command instead
