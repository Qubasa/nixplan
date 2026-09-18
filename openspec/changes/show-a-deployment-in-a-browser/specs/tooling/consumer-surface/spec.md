<!--
A delta against `tooling/consumer-surface`, whose current text is
`openspec/specs/tooling/consumer-surface/spec.md`. Two requirements are modified and each is copied
whole before it is edited, because a partial block loses the rest of the requirement at archive.

What it deliberately does not decide: what the view shows and what it asks. That is
`operator/deployment-view` in this same change. This delta decides only that the view is reached by
output name and that the names it occupies mean one thing each. The classification of the directory
it lives in and the resolution of the paths its files name are `tooling/repository-shape`, also in
this change; every cross-change seam of this set is written out once in
`openspec/changes/INTEGRATION.md`.

The conditions. The view is a deliverable with its own flake wiring, which is imported from
`flake.nix:43-48` the way the command's is (`cli/flake-module.nix:1-10`), and the command is the
precedent for both halves of the naming: one name in every namespace that answers for a program
(`cli/flake-module.nix:44-51`) and a second name for the same source root published so the tests can
import the pure half with no wrapper (`:20`, `:45`). The check is the case the current requirement
does not cover. Today the tree carries one name in both `packages` and `checks`, `planner-perf`: the
package is the measurement harness and the check runs it (`flake-module.nix:358-367`, `:390-396`),
which is one subject reached two ways and no program. A server and the pytest layer over it are two
subjects, and a reader who types `nix run` and one who types `nix build .#checks...` cannot see
which answered, which is the confusion the requirement already names. The view adds no input this
repository pins: it is the standard library, and the interpreter the tests run under carries pytest
and nothing else (`pytest-env.nix:6`).
-->

## MODIFIED Requirements

### Requirement: The flake publishes every layer a consumer builds with

Planning a deployment and building one SHALL both be reachable as outputs of this flake. A consumer
SHALL NOT have to name a path inside this repository's source to reach either, and a deployment
SHALL NOT have to live inside this checkout to be built. The output that builds a deployment SHALL
take the consumer's own package set, so it is one name for every system rather than one name per
system.

A program this repository publishes for reading a built deployment SHALL be an output too, reachable
by name in the namespaces that answer for a program, and SHALL take a built deployment the way the
operator's command takes one: a directory a build wrote, or a reference that builds one. Its source
root SHALL be published under a name of its own where a test has to import its pure half, so that a
rename cannot leave the published program and the tests naming two different things.

A consumer SHALL NOT be asked for an input this repository pins. Every argument a documented call
takes SHALL be a value the consumer already has - their package set and their deployment - or an
output of this flake. A published program SHALL NOT add an input of its own to the set this
repository pins.

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

#### Scenario: A consumer reads the view off an output

- **WHEN** a consumer asks this flake for the program that shows a built deployment, by output name
- **THEN** it SHALL resolve in the namespaces that answer for a program
- **AND** its source root SHALL resolve under a name of its own
- **AND** neither SHALL require a path inside this repository's source, and neither SHALL add an
  input to the set this repository pins

### Requirement: A published name means one thing

A name this flake publishes SHALL mean one thing across every output namespace. A value that exists
for the repository's own development SHALL NOT occupy a name a runnable output uses, because the
commands that reach the two namespaces differ and a reader cannot see which one answered. Where a
name is advertised by the root document, the command the root shows SHALL reach the thing the root
describes.

A name that names a program a reader runs SHALL NOT also name a check. A check is a value of this
repository's own development and a program is the thing a reader runs, so the two SHALL take two
names, and a check over a published program SHALL be named for what it checks rather than for the
program itself. A name shared by a package and the check that runs that same package SHALL remain
one name, because it is one subject reached two ways and neither half is a program.

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

#### Scenario: A check over a published program takes a name of its own

- **WHEN** this flake publishes a program a reader runs and a check over that program
- **THEN** the check's name SHALL differ from the program's
- **AND** no name SHALL answer one command with that program and another with its check
