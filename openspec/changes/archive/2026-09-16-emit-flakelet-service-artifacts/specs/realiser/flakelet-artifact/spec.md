<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `realiser/portable-service-image` in the unarchived `emit-systemd-portable-service-images`
change, which is the other realiser over the same plan.
-->

## Purpose

Defines the service artifact built from one placed plan entry for a host that runs a service out
of its own store rather than out of an image: what the artifact contains, who decides that a unit
is enabled, what identity it carries so an endpoint can tell whether anything changed, what it
refuses, and what a real service manager does with it. This is the first realiser in this
repository whose output is activated by something other than a test double.

## ADDED Requirements

### Requirement: An artifact is built from one plan entry, outside the planner

An artifact SHALL be built by a component outside `mkPlan`, and plan evaluation SHALL remain free
of derivations. The builder SHALL take one placed entry and the plan it belongs to, and SHALL
derive every fact it needs from them: the units to render, the timers a scheduled unit implies,
and the identity to stamp. The artifact SHALL contain the rendered unit files and a metadata
document and nothing else, so that activating it requires no evaluation, no network and no
knowledge of Nix on the machine.

#### Scenario: One entry becomes one artifact

- **WHEN** a placed entry with one long-running unit is built
- **THEN** the artifact SHALL contain that unit's file under a directory of units
- **AND** SHALL contain a metadata document
- **AND** SHALL contain no other file

#### Scenario: A scheduled unit brings its trigger

- **WHEN** a placed entry declares a unit with a schedule
- **THEN** the artifact SHALL contain both that unit's file and its timer file

#### Scenario: Nothing is evaluated to activate it

- **WHEN** an artifact is activated on a machine
- **THEN** the machine SHALL require no evaluator, no service-flake source and no network to do it

### Requirement: Enablement is the backend's decision, not the plan's

The plan SHALL say when a unit runs and the artifact SHALL say what that means for the endpoint
that starts it. A long-running unit SHALL be rendered so that the endpoint starts it on
activation and again after a reboot. A scheduled unit SHALL be rendered so that only its timer is
enabled: deploying a scheduled service SHALL NOT run it immediately.

#### Scenario: A long-running unit is started

- **WHEN** an artifact whose entry declares a long-running unit is activated
- **THEN** that unit SHALL be running

#### Scenario: A long-running unit returns after a reboot

- **WHEN** the machine reboots after an activation
- **THEN** that unit SHALL be running again without any activation being re-run by hand

#### Scenario: A scheduled unit is not fired by deploying it

- **WHEN** an artifact whose entry declares a scheduled unit is activated
- **THEN** its timer SHALL be enabled
- **AND** its service SHALL NOT have been started by the activation

### Requirement: The artifact carries the plan's identity

The artifact SHALL record the key of the entry it was built from and that entry's content-derived
version, in the fields the endpoint already reads. An endpoint comparing a newly delivered
artifact against what it is running SHALL therefore compare plan facts, and an artifact built
twice from one unchanged entry SHALL compare equal.

#### Scenario: An unchanged entry is a no-op

- **WHEN** an artifact is activated and then an artifact built from the same unchanged entry is offered
- **THEN** the endpoint SHALL report that there is nothing to do
- **AND** SHALL NOT restart the running units

#### Scenario: A changed unit field is a new generation

- **WHEN** a unit field changes and an artifact built from the changed entry is offered
- **THEN** the endpoint SHALL activate it as a new generation

#### Scenario: The running artifact names its entry

- **WHEN** an operator asks the endpoint what it is running
- **THEN** the answer SHALL contain the plan key of the entry the running artifact was built from

### Requirement: A name the endpoint cannot accept is refused before bytes exist

The names an artifact derives - the service name and every unit file name - SHALL satisfy the
endpoint's own naming rules, and the builder SHALL refuse an entry whose derived names do not,
naming the entry, the offending name and the rule it breaks. A refusal SHALL be a raise, as every
refusal on this side is, and it SHALL happen before any file is produced.

#### Scenario: An unusable instance name

- **WHEN** an entry's instance or service name contains a character the endpoint's service names may not carry
- **THEN** the build SHALL fail naming the entry, the derived name and the rule

#### Scenario: A unit name outside the service's namespace

- **WHEN** an entry would render a unit file whose name does not begin with the derived service name
- **THEN** the build SHALL fail naming the entry and that unit

#### Scenario: A well-formed entry is not refused

- **WHEN** an entry's instance, service and unit names are all made of characters the endpoint accepts
- **THEN** the build SHALL succeed

### Requirement: A host file this realiser has no step for is refused

The artifact SHALL be everything the machine needs, and this realiser SHALL run nothing on the
machine before the endpoint links and starts the units. An entry whose unit is shown a host file -
a configuration file assembled from the plan, or a generated file read by reference - SHALL
therefore be refused, naming the entry, the path and the step that does not exist, rather than
rendered into a unit that names a path nothing on the machine creates. The dependency is named,
the way `state.json`'s is.

#### Scenario: An entry shown a configuration file

- **WHEN** an entry records configuration data its unit reads
- **THEN** the build SHALL fail naming the entry and that file's path

#### Scenario: An entry shown a generated file

- **WHEN** an entry's unit reads a generated file by reference
- **THEN** the build SHALL fail naming the entry and that file's path

#### Scenario: An entry shown no host file is built

- **WHEN** an entry records no configuration data and reads no generated file
- **THEN** the artifact SHALL be built

### Requirement: An artifact is a function of its entry alone

Two builds of one entry SHALL produce byte-identical artifacts. A change to an entry SHALL change
that entry's artifact, and SHALL leave every other entry's artifact unchanged.

#### Scenario: A rebuild is identical

- **WHEN** one entry is built twice
- **THEN** the two artifacts SHALL be byte-identical

#### Scenario: An unrelated edit changes nothing

- **WHEN** a setting is changed on one service and a second service reads nothing from it
- **THEN** the second service's artifact SHALL be byte-identical to the one built before the edit

### Requirement: A real endpoint runs the artifact and can go back

The change SHALL be proved against a real service manager and a real endpoint rather than test
doubles: an artifact is activated, the service it describes is reachable, it survives a reboot,
and an endpoint holding two generations of one entry SHALL be able to return to the previous one.

#### Scenario: The service is reachable

- **WHEN** an artifact whose unit serves requests is activated on a real machine
- **THEN** a request to that service SHALL succeed

#### Scenario: Rollback returns the previous generation

- **WHEN** a second artifact of one entry has been activated and the endpoint is asked to roll back
- **THEN** the units of the previous generation SHALL be running
- **AND** the endpoint SHALL report the previous generation as active

#### Scenario: No test double is involved

- **WHEN** the end-to-end check runs
- **THEN** it SHALL use the endpoint's real binary and the machine's real service manager
