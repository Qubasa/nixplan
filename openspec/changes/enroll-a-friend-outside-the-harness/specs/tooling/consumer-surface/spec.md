<!--
A delta against `tooling/consumer-surface`, whose current text is
`openspec/specs/tooling/consumer-surface/spec.md`. One requirement is modified - `The flake
publishes every layer a consumer builds with`, copied whole from `:12-37` and extended - and
nothing is added.

What it deliberately does not decide. What either published module contains is
`operator/enrollment-command` and `operator/machine-provisioning`, the two capabilities this change
adds; this delta decides only that they are outputs and under which kind of name. Which top-level
directory holds them, and the class that directory belongs to, is `tooling/repository-shape`, the
sibling delta of this same change. Nothing here touches the platform elaboration, the published
names of the command, or the example a document shows, which the other requirements of this
capability own. Three changes of this set delta this requirement and each states only the name it
publishes, which `openspec/changes/INTEGRATION.md:145-147` records: whichever lands second and
third restates the requirement over the amended base rather than over the text it was written
against, the rule the production set already states for `planner/machine-platform`.

The conditions. The two things a consumer outside this repository cannot reach today are exactly
the two this change publishes. A module that places a coordination server exists only inside an
end-to-end folder (`tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix`), which no
deployment outside that folder may name: `tests/unit/layers.nix:210-222` refuses a path token
resolving outside its own folder and `:224-235` refuses a folder naming a sibling at all. The
provisioning a machine needs exists only as a test machine, `tests/e2e/guest.nix:319-392`, while
the command that verifies those facts creates none of them (`cli/remote.py:670-729`). The
precedent for publishing rather than pointing at a path is `flake.operator`
(`flake-module.nix:65-70`), whose own comment states that a path inside this flake's source is not
an interface, and the precedent for handing a module to a consumer as an argument is how every
folder receives the deployment build (`flake-module.nix:155-173`) and how the test machine receives
the flakelet module (`:189-194`).
-->

## MODIFIED Requirements

### Requirement: The flake publishes every layer a consumer builds with

Planning a deployment and building one SHALL both be reachable as outputs of this flake. A consumer
SHALL NOT have to name a path inside this repository's source to reach either, and a deployment
SHALL NOT have to live inside this checkout to be built. The output that builds a deployment SHALL
take the consumer's own package set, so it is one name for every system rather than one name per
system.

A consumer SHALL NOT be asked for an input this repository pins. Every argument a documented call
takes SHALL be a value the consumer already has - their package set and their deployment - or an
output of this flake.

A module this repository publishes for a consumer to compose SHALL be an output too, under a name
whose namespace says which kind of module it is: a module a deployment composes into an instance is
published beside the library it is composed by, and a module a machine's own configuration imports
is published under the name that kind of module is published under everywhere. A consumer SHALL NOT
reach either by naming a path inside this repository's source, and SHALL NOT reach either by
copying a file out of the tests, which no consumer may name at all.

A module this repository publishes SHALL be composable by a consumer who pins nothing this
repository pins: every argument it requires SHALL be a value the consumer already has, or an output
of this flake, and a fact the module refuses to default SHALL be an argument of the module rather
than a value it chooses.

#### Scenario: A consumer reads the build off an output

- **WHEN** a flake that consumes this repository asks for the library and for the deployment build
  by output name
- **THEN** both SHALL resolve
- **AND** the deployment build SHALL name the function a consumer calls
- **AND** neither SHALL require a path inside this repository's source

#### Scenario: A consumer is asked for an input only this flake pins

- **WHEN** a consumer's flake declares the inputs a documented call needs
- **THEN** those inputs SHALL be their own package set and this repository
- **AND** no further input this repository pins SHALL have to be declared or resolved by the
  consumer

#### Scenario: A published module is reached by an output name

- **WHEN** a consumer asks this flake for the module that places a coordination server and for the
  module that provisions a machine
- **THEN** both SHALL resolve as outputs
- **AND** each SHALL be under a name whose namespace says whether a deployment composes it or a
  machine's configuration imports it
- **AND** neither SHALL require a path inside this repository's source

#### Scenario: A published module is composed by a consumer who pins nothing of this flake

- **WHEN** a consumer composes a published module in their own deployment or machine configuration
- **THEN** every argument it requires SHALL be a value they already have or an output of this flake
- **AND** a required argument they do not state SHALL fail their own evaluation naming it
