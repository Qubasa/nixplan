<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `realiser/flakelet-artifact` in `emit-flakelet-service-artifacts` and
`realiser/portable-service-image` in `emit-systemd-portable-service-images`, which own what one entry
of one plan is realised into, and against `planner/plan-artifact`, which owns what a plan holds. This
capability owns the step above both: one deployment, every placed entry, and the addressable set a
consumer receives.
-->

## Purpose

Defines what building a whole deployment produces, so that no deployment needs code written for it.
One reading decides which entries are built, which realiser builds each, and what the result is
addressed by; one manifest states the answer for a consumer that evaluates no Nix; and a deployment
the planner called inapplicable is refused rather than partially realised.

## ADDED Requirements

### Requirement: One reading builds every deployment

Building a deployment SHALL be a function of the deployment alone: the arguments the planner takes,
plus a statement of how each entry is realised. It SHALL NOT require code written for a particular
deployment, and two deployments SHALL be built by the same function.

The result SHALL hold the plan, a manifest, and one artifact per placed entry, and SHALL hold nothing
that is not derived from those. An entry the plan did not place SHALL contribute no artifact.

#### Scenario: Two deployments are built by one function

- **WHEN** two unrelated deployments are built
- **THEN** the same function SHALL build both
- **AND** each result SHALL hold the plan, the manifest and one artifact per placed entry of that
  deployment
- **AND** neither SHALL require a declaration written beside it

#### Scenario: An artifact is addressed by its plan key

- **WHEN** a consumer holds a plan key and wants the artifact built for it
- **THEN** the manifest SHALL name the artifact for that key
- **AND** the consumer SHALL NOT have to reconstruct the name from the key

#### Scenario: Two entries project onto one artifact name

- **WHEN** two plan keys project onto one artifact name
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name both keys and the name they collided on

### Requirement: The realiser of an entry is stated, never inferred

The realiser an entry is built with SHALL be a stated fact of the deployment, because no plan field
records it and the same entry may legitimately be realised either way. A realisation statement SHALL
be addressable per entry and SHALL carry a default for the entries it does not name.

Where a realiser requires a fact the plan does not carry, that fact SHALL be part of the statement,
and its absence SHALL be a refusal naming the entry and the fact — never a default chosen by the
builder.

#### Scenario: An entry states no realiser

- **WHEN** the deployment's realisation statement does not name an entry
- **THEN** that entry SHALL be built by the default realiser
- **AND** the manifest SHALL record which realiser built it

#### Scenario: An image entry states its confinement profile

- **WHEN** an entry is stated to be realised as a portable-service image
- **THEN** the profile the attachment runs under SHALL come from the statement
- **AND** an image entry whose statement carries no profile SHALL be refused naming the entry and the
  profile

#### Scenario: A realiser name nothing implements

- **WHEN** an entry is stated to use a realiser that does not exist
- **THEN** the build SHALL be refused
- **AND** the refusal SHALL name the entry, the name given, and the realisers that exist

### Requirement: An inapplicable deployment is not built

A deployment whose diagnostics carry an error SHALL NOT be built. The refusal SHALL be the rendered
diagnostics table, so the reason is the planner's own words, and it SHALL happen before any entry is
realised. A table carrying no error SHALL build, whatever else it carries.

#### Scenario: A deployment whose diagnostics carry an error

- **WHEN** a build is asked for a deployment the planner reports as inapplicable
- **THEN** it SHALL be refused
- **AND** the refusal SHALL carry the rendered diagnostics table
- **AND** no artifact of any entry SHALL be produced

#### Scenario: A deployment whose diagnostics carry only warnings

- **WHEN** a build is asked for a deployment whose table holds warnings and no error
- **THEN** every placed entry SHALL be built
- **AND** the table SHALL still be part of the result

### Requirement: The manifest is the whole interface to a build

A consumer of a deployment build SHALL be able to apply it by reading the plan and the manifest, with
no Nix evaluation. The manifest SHALL state, for each placed entry, the artifact built for it, the
realiser that built it, the machine it is placed on, the address recorded for that machine, and the
units it declares; and for each generated value, its files, their paths and the machines its delivery
set names.

The manifest SHALL be a function of the plan and the realisation statement alone, so that reading one
deployment twice yields one answer.

#### Scenario: The manifest names every entry the plan placed

- **WHEN** the manifest of a built deployment is read
- **THEN** every placed entry of the plan SHALL appear in it exactly once
- **AND** each SHALL carry its artifact, its realiser, its machine, that machine's address and its
  unit names
- **AND** an entry the plan placed on a machine the registry gives no address for SHALL be refused
  naming both

#### Scenario: The manifest names every value a machine receives

- **WHEN** the deployment declares generated values
- **THEN** the manifest SHALL name every value entry the plan carries, with its files and their paths
- **AND** each SHALL carry the delivery set the plan derived, including when that set is empty
- **AND** the manifest SHALL carry no bytes of any value

#### Scenario: The same deployment is read twice

- **WHEN** one deployment is read twice with no edit between
- **THEN** the two manifests SHALL be equal
- **AND** the two readings SHALL name the same artifact for each key
