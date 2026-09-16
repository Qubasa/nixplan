<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `tooling/test-layers` in the unarchived `strip-planner-tests-to-unit-and-e2e` change, which
owns the same rule for the machine layer's directories: everything an end-to-end test names is
inside that test's own folder. This capability states the rule for the repository as a whole, which
is what a transplant out of a larger repository leaves broken.
-->

## Purpose

Defines what may exist in this repository and which references its files may make, so that a
reader who follows a path a comment, a fixture or a document names arrives at a file instead of at
a folder that belongs to some other repository. It also fixes which top-level entries the
repository has and what each is for, so an unowned file is a failure rather than a thing nobody
remembers adding.

## ADDED Requirements

### Requirement: A path this repository names resolves

A path named by this repository's code, tests, fixtures or documentation SHALL resolve to a file or
directory of this repository. This SHALL hold for a path literal an evaluator reads and for a path
written in prose or in a comment, because a reader follows both. A reference that does not resolve
SHALL fail a check that names the file it is in and the token that failed, rather than being found
by a reader.

A path SHALL NOT reach outside the repository. Naming a file of another repository is permitted
only as a citation that states the fact it is citing, so that the sentence remains readable where
the cited file is not available.

#### Scenario: A file names a path that is not there

- **WHEN** a file of the library, the tests, the fixtures or the documentation names a path
- **THEN** that path SHALL resolve inside this repository
- **AND** a path that does not SHALL fail the check, naming the file, the line and the token

#### Scenario: A record is read as history

- **WHEN** a specification, proposal or task record under `openspec/` names a path
- **THEN** the resolution rule SHALL NOT apply to it
- **AND** the check SHALL state that a record describes the repository as it was when it was
  written, so a reader knows why the exemption exists

### Requirement: Every top-level entry has a stated purpose

Each top-level entry of the repository SHALL belong to one of the classes the repository states:
the library, a realiser, the tests, the fixtures the tests read, the performance harness, the
documentation of the library, the specification records, the formatter's own configuration, or the
flake. An entry belonging to none of them SHALL fail a check naming it. A file SHALL NOT be kept in
this repository solely because another file cites it; the citing file SHALL state the fact instead.

The root SHALL state what the repository is, how the tree is laid out and which commands check it,
so that the first file a reader opens is not a document about one of the parts.

#### Scenario: A top-level entry belongs to no stated class

- **WHEN** a top-level file or directory is added that is none of the stated classes
- **THEN** the check SHALL fail naming the entry
- **AND** SHALL name the classes that exist, so the entry is either classified or removed

#### Scenario: The root does not say what the repository is

- **WHEN** the repository root is read
- **THEN** it SHALL hold a document naming the library, the layout and the commands that check it
- **AND** that document SHALL name where the library's own reading order continues
