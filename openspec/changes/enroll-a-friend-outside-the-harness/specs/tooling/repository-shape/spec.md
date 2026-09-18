<!--
A delta against `tooling/repository-shape`, whose current text is
`openspec/specs/tooling/repository-shape/spec.md`. One requirement is modified - `Every top-level
entry has a stated purpose`, copied whole from `:37-62` and extended - and nothing is added.

What it deliberately does not decide. That the two modules are published outputs, and under which
kind of name, is `tooling/consumer-surface`, the sibling delta of this same change; what either
module contains is `operator/enrollment-command` and `operator/machine-provisioning`. Nothing here
touches the path-resolution requirement, the one shell, the help text, the row tables or the
specification classification, which the other requirements of this capability own - in particular
the classification rule stays as it is, and this change's own delta specs are registered under it
like every other change's. Two changes of this set add a top-level directory and delta this one
requirement, which `openspec/changes/INTEGRATION.md:138-143` records: `classOf` is one table
gaining two rows, and whichever lands second restates the requirement over the amended base
rather than over the text both were written against.

The conditions. The classes are a hand-maintained table, `classOf` in
`tests/unit/layers.nix:56-86`, and an entry belonging to none of them is reported by name
(`:99-101`); a directory whose files are to be held to the path scan is registered a second time,
in `scannedDirectories` (`:296-307`). Neither carries a class for a module this repository
publishes for a consumer to compose, because no such directory exists: the module that places a
coordination server is inside an end-to-end folder
(`tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix`) that no deployment outside it may
name (`tests/unit/layers.nix:210-222`, `:224-235`), and the provisioning of a machine is a test
machine (`tests/e2e/guest.nix:319-392`). A deliverable with its own flake wiring is registered in
the flake's imports, the way `cli/flake-module.nix` is (`flake.nix:43-48`).
-->

## MODIFIED Requirements

### Requirement: Every top-level entry has a stated purpose

Each top-level entry of the repository SHALL belong to one of the classes the repository states:
the library, a realiser, the deployment build, the operator's command, a module this repository
publishes for a consumer to compose, the tests, the fixtures the tests read, the performance
harness, the documentation of the library, the specification records, the formatter's own
configuration, or the flake. An entry belonging to none of them SHALL fail a check naming it. A
file SHALL NOT be kept in this repository solely because another file cites it; the citing file
SHALL state the fact instead.

A published module SHALL live in a top-level directory of its own rather than inside the tests,
because a file of an end-to-end folder may be named by nothing outside that folder and a module a
consumer composes has to be nameable. Its files SHALL be held to the same path scan the library's
are: a path a published module names SHALL resolve in this repository, so a consumer following one
arrives at a file.

A command the root advertises SHALL be a command a reader can run. Where running it needs something
this repository cannot supply - a private dependency, a device, or a credential - the root SHALL
name that beside the command rather than in a document further down the reading order, so a reader
learns it before the run rather than from the failure.

#### Scenario: A top-level entry belongs to no stated class

- **WHEN** a top-level file or directory is added that is none of the stated classes
- **THEN** the check SHALL fail naming the entry
- **AND** SHALL name the classes that exist, so the entry is either classified or removed

#### Scenario: A command the root advertises needs something this repository cannot provide

- **WHEN** the root advertises a command whose run resolves a dependency this repository does not
  publish
- **THEN** the root SHALL name that dependency where it names the command
- **AND** SHALL say that a reader without it cannot run the command

#### Scenario: The directory of published modules is a class of its own

- **WHEN** the top-level entries are classified
- **THEN** the directory holding the modules this repository publishes SHALL belong to the class
  stated for them
- **AND** its files SHALL be inside the path scan the library's files are inside
