<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `operator/deployment-build` in `apply-deployments-with-an-operator-command`, which owns what
a deployment build produces and what `mkDeployment` takes, and against `tooling/repository-shape` in
`clean-up-transplant-residue`, which owns what the root document says. This capability owns one
thing those two do not: what this flake publishes to somebody who is not this repository, and
whether the ordinary commands find it.
-->

## Purpose

Defines the surface a consumer outside this repository builds against: which layers are outputs
rather than paths inside the source, what a published name means, whether the ordinary discovery
commands answer, whose nixpkgs elaborated the platform record every entry key folds in, and whether
an example a document shows is one a test builds. A reader who clones this repository, or who adds
it as an input, reaches a running service through this surface and through nothing else.

## ADDED Requirements

### Requirement: The flake publishes every layer a consumer builds with

Planning a deployment and building one SHALL both be reachable as outputs of this flake. A consumer
SHALL NOT have to name a path inside this repository's source to reach either, and a deployment
SHALL NOT have to live inside this checkout to be built. The output that builds a deployment SHALL
take the consumer's own package set, so it is one name for every system rather than one name per
system.

A consumer SHALL NOT be asked for an input this repository pins. Every argument a documented call
takes SHALL be a value the consumer already has - their package set and their deployment - or an
output of this flake.

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

### Requirement: A published name means one thing

A name this flake publishes SHALL mean one thing across every output namespace. A value that exists
for the repository's own development SHALL NOT occupy a name a runnable output uses, because the
commands that reach the two namespaces differ and a reader cannot see which one answered. Where a
name is advertised by the root document, the command the root shows SHALL reach the thing the root
describes.

#### Scenario: One published name answers two different things

- **WHEN** a name that names a runnable output is asked for by a command that reads another
  namespace
- **THEN** the answer SHALL be that runnable output
- **AND** no output of this flake SHALL answer one command with a program and another with an
  attribute set of development values

#### Scenario: The test results are reachable under a name of their own

- **WHEN** the suites, their failures and the worked plan are read from the flake
- **THEN** they SHALL be under a name that no application and no package uses
- **AND** every document that shows a command reading them SHALL show that name

### Requirement: The output surface answers the ordinary discovery commands

A reader who knows nothing about this repository SHALL be able to list what it publishes with the
command that lists a flake's outputs, and that listing SHALL complete for every system this flake
claims. A system this flake claims SHALL be one the pinned package set can evaluate. Running the
flake without naming an attribute SHALL run the operator's command, so the discovery route ends at
something a reader can type next.

#### Scenario: The flake names its outputs

- **WHEN** a reader lists this flake's outputs with the ordinary command
- **THEN** the listing SHALL complete for every system the flake claims
- **AND** it SHALL name the operator's command among the applications and among the packages
- **AND** running the flake with no attribute named SHALL run that command
- **AND** that command's own help SHALL name its subcommands

### Requirement: The platform elaboration a consumer receives is a stated choice

The library this flake publishes SHALL state which package set elaborated the platform records it
produces. A platform record is a field of every placed entry and every entry key is a digest over
the entry, so the elaboration decides identity, and a consumer whose own package set differs SHALL
be able to read which one decided theirs. The flake SHALL also publish a way to obtain the library
elaborated against the consumer's own platform definitions, so a consumer who wants one package set
deciding everything can have it.

#### Scenario: The library states whose nixpkgs elaborated its platforms

- **WHEN** the published library is read
- **THEN** it SHALL carry the identity of the package set whose platform definitions it was applied
  to
- **AND** that identity SHALL be the one this flake's own lock records

#### Scenario: A consumer elaborates a machine with its own nixpkgs

- **WHEN** the library is obtained with a consumer's own platform definitions
- **THEN** a machine record SHALL be elaborated by those definitions
- **AND** the plan SHALL be otherwise the plan the published library produces for the same
  deployment

### Requirement: The example a document shows is the example a test builds

An example a document shows as a working deployment SHALL be a deployment this repository builds.
The document's text and the fixture built SHALL be one text rather than two copies kept in step by
hand, so an example that stops building fails a check that names the document. A document SHALL NOT
show as complete an example that plans without a diagnostics row and then cannot be realised.

#### Scenario: The example a document shows is the example a folder holds

- **WHEN** a document shows the smallest deployment that works
- **THEN** its text SHALL equal the deployment an end-to-end folder holds
- **AND** a difference SHALL fail a check naming the document and the folder

#### Scenario: The documented smallest example is built

- **WHEN** the deployment that document shows is built
- **THEN** the build SHALL produce an artifact for the entry the deployment places
- **AND** a refusal SHALL NOT come from a realiser for a fact the plan reported no row about
