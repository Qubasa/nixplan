<!--
A delta against `realiser/flakelet-artifact`, which lives in the unarchived
`emit-flakelet-service-artifacts` change. `A host file this realiser has no step for is refused` was
last restated by `deliver-secrets-across-machines`, and this delta restates that version again. Two
requirements change and both change in the same way: the refusal keeps its wording and stops being
the first thing a user hears, because the layer above now reports it as a row.

The subjects are the three raises of `flakelet/read.nix:131-139` and the two rules of
`flakelet/read.nix:36-48`, restated from flakelet's own `manager.rs`. The rows that precede them are
`A statement is checked against the entry it is about` in `operator/deployment-build` in this same
change, which obtains those rules from this realiser rather than restating them. The scenario
headings of both requirements are kept: each names a situation, and it is the outcome that moves.
-->

## Purpose

Defines what one plan entry is realised into for a store-backed endpoint, and what this realiser
refuses. A refusal here is the answer a caller reaching this realiser directly receives, and the
same condition reaches a caller of the deployment build as a row.

## MODIFIED Requirements

### Requirement: A name the endpoint cannot accept is refused before bytes exist

The names an artifact derives - the service name and every unit file name - SHALL satisfy the
endpoint's own naming rules, and the builder SHALL refuse an entry whose derived names do not,
naming the entry, the offending name and the rule it breaks. A refusal SHALL be a raise, as every
refusal on this side is, and it SHALL happen before any file is produced.

This realiser SHALL be the author of both rules, and SHALL publish each as a predicate a caller can
ask before building, so that the deployment build reports the same condition as a row without
restating the rule. A raise here SHALL therefore be reachable only by a caller that did not ask, and
the sentence a raise prints SHALL be the sentence the row states.

#### Scenario: An unusable instance name

- **WHEN** an entry's instance or service name contains a character the endpoint's service names may
  not carry
- **THEN** the build SHALL fail naming the entry, the derived name and the rule
- **AND** a caller that reads the deployment build instead SHALL have received a row naming the same
  three

#### Scenario: A unit name outside the service's namespace

- **WHEN** an entry would render a unit file whose name does not begin with the derived service name
- **THEN** the build SHALL fail naming the entry and that unit

#### Scenario: A well-formed entry is not refused

- **WHEN** an entry's instance, service and unit names are all made of characters the endpoint
  accepts
- **THEN** the build SHALL succeed

### Requirement: A host file this realiser has no step for is refused

The artifact SHALL be everything the machine needs, and this realiser SHALL run nothing on the
machine before the endpoint links and starts the units. An entry whose unit is shown a host file the
realiser would have to produce - a configuration file assembled from the plan, whose bytes come out
of the store and land at a path nothing else creates - SHALL therefore be refused, naming the entry,
the path and the step that does not exist, rather than rendered into a unit that names a path
nothing on the machine creates.

The condition SHALL be reported as a row by the deployment build before this realiser is called,
because which realiser an entry uses is a fact the statement holds and this file cannot see. A
deployment stating this realiser for such an entry SHALL therefore be refused with a row naming the
entry, the path and the realiser, and the raise here SHALL remain as the answer to a direct caller.

A generated file read by reference SHALL NOT be refused. Its host path is its own source rather than
a staging destination, and its bytes reach the machine by delivery of the value the plan names,
before the entry is activated. The realiser SHALL therefore build the entry and SHALL add no step:
the delivery is the operator's, and an entry whose value no machine receives is already refused by
the planner.

#### Scenario: An entry shown a configuration file

- **WHEN** an entry records configuration data its unit reads
- **THEN** the build SHALL fail naming the entry and that file's path

#### Scenario: An entry shown a generated file

- **WHEN** an entry's unit reads a generated file by reference
- **THEN** the artifact SHALL be built
- **AND** it SHALL carry no bytes of that file and no step that would create it

#### Scenario: An entry shown no host file is built

- **WHEN** an entry records no configuration data and reads no generated file
- **THEN** the artifact SHALL be built
