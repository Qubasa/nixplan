<!--
A delta against `tooling/repository-shape`, whose current text is
`openspec/specs/tooling/repository-shape/spec.md`. Two requirements are modified and each is copied
whole before it is edited, because a partial block loses the rest of the requirement at archive.

What it deliberately does not decide: what the view shows and what it asks, which is
`operator/deployment-view`, and which names the flake publishes it under, which is
`tooling/consumer-surface` - both in this same change. Every cross-change seam of this set is
written out once in `openspec/changes/INTEGRATION.md`.

The conditions. The view is a new top-level directory, and a top-level entry with no row in
`classOf` fails `testATopLevelEntryBelongsToNoStatedClass` (`tests/unit/layers.nix:54-56`,
`:98-100`), so the stated classes have to name it. The classification alone is not enough to make it
checked: the type checker runs one root per directory of top-level modules and a directory nobody
named is not checked at all (`treefmt.nix:74-102`), the linter's `src` decides how first-party
imports sort (`ruff.toml:4`), and only a directory in `scannedDirectories` has its files read by the
path scan (`tests/unit/layers.nix:295-312`). Three of those four fail quietly rather than red, which
is why the crossing between the classification and the roots is stated as a rule.

The second condition is the scan's own reading. A repository-rooted token counts as a path exactly
when its first segment is a real top-level entry (`tests/unit/layers.nix:124-126`), and the scan
reads raw file text including comments (`:314-316`). A view serves documents whose text carries the
routes it answers, which are tokens of the same shape, so the moment a directory of served documents
is scanned, a route spelled with a top-level entry's name in front reads as a path of this
repository that has to resolve.
-->

## MODIFIED Requirements

### Requirement: A path this repository names resolves

A path named by this repository's code, tests, fixtures or documentation SHALL resolve to a file or
directory of this repository. This SHALL hold for a path literal an evaluator reads and for a path
written in prose or in a comment, because a reader follows both. A reference that does not resolve
SHALL fail a check that names the file it is in and the token that failed, rather than being found
by a reader.

A path SHALL NOT reach outside the repository. Naming a file of another repository is permitted
only as a citation that states the fact it is citing, so that the sentence remains readable where
the cited file is not available.

A token a served document carries is a route the serving program answers and not a path of this
repository, and the two SHALL be told apart by construction rather than by an exemption: a route
SHALL NOT be spelled so that its leading segment names a top-level entry, because the scan reads a
token whose first segment is a top-level entry as a repository path and would then demand that a
route resolve to a file. A served document SHALL name its own assets by the routes that serve them
and SHALL NOT name a path inside this repository's source.

#### Scenario: A file names a path that is not there

- **WHEN** a file of the library, the tests, the fixtures or the documentation names a path
- **THEN** that path SHALL resolve inside this repository
- **AND** a path that does not SHALL fail the check, naming the file, the line and the token

#### Scenario: A record is read as history

- **WHEN** a specification, proposal or task record under `openspec/` names a path
- **THEN** the resolution rule SHALL NOT apply to it
- **AND** the check SHALL state that a record describes the repository as it was when it was
  written, so a reader knows why the exemption exists

#### Scenario: A served document names a route rather than a path

- **WHEN** a document this repository serves names the route or the asset it refers to
- **THEN** no leading segment of that token SHALL name a top-level entry of this repository
- **AND** the document SHALL name no path inside this repository's source

### Requirement: Every top-level entry has a stated purpose

Each top-level entry of the repository SHALL belong to one of the classes the repository states:
the library, a realiser, the deployment build, the operator's command, the read-only view of a
built deployment, the tests, the fixtures the tests read, the performance harness, the documentation
of the library, the specification records, the formatter's own configuration, or the flake. An entry
belonging to none of them SHALL fail a check naming it. A file SHALL NOT be kept in this repository
solely because another file cites it; the citing file SHALL state the fact instead.

A top-level directory of python modules SHALL also be named where the type checker reads its roots
and where the linter reads its source directories, and a top-level directory whose files are held to
the path scan SHALL be named where that scan reads its directories. Being classified SHALL NOT be
mistaken for being checked: a directory nobody named as a type-checking root is not type-checked at
all and fails nothing, so the crossing between the stated classes and those roots SHALL be a check
rather than a habit.

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

#### Scenario: A classified directory of modules is checked as well as classified

- **WHEN** a top-level directory of python modules is classified among the stated classes
- **THEN** it SHALL be named where the type checker reads its roots and where the linter reads its
  source directories
- **AND** a directory named in one and missing from the other SHALL fail a check naming the
  directory and the root it is missing from
