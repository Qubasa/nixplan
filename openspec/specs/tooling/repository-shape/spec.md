# tooling/repository-shape Specification

## Purpose
Defines what may exist in this repository and which references its files may make, so that a
reader who follows a path a comment, a fixture or a document names arrives at a file instead of at
a folder that belongs to some other repository. It also fixes which top-level entries the
repository has and what each is for, so an unowned file is a failure rather than a thing nobody
remembers adding.

## Requirements

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
the library, a realiser, the deployment build, the operator's command, the tests, the fixtures the
tests read, the performance harness, the documentation of the library, the specification records,
the formatter's own configuration, or the flake. An entry belonging to none of them SHALL fail a
check naming it. A file SHALL NOT be kept in this repository solely because another file cites it;
the citing file SHALL state the fact instead.

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

### Requirement: The one shell is a shell of this checkout

The development shell SHALL carry the commands the repository's own documentation tells a reader to
run, including the operator's command, so that a reader following a document types the command's own
name.

The shell SHALL derive the tree it configures from the flake it was built from, never from the
directory the caller happened to be in. Entering it from an unrelated repository SHALL NOT configure
that repository's directories. Where the shell needs a working tree rather than a store copy and no
working tree of this repository is present, it SHALL refuse and say so, rather than continuing with
an answer derived from a foreign tree or from an empty one.

#### Scenario: The shell carries the command its documentation is about

- **WHEN** the development shell is entered
- **THEN** the operator's command SHALL be runnable by its own name
- **AND** every command the repository's documentation instructs a reader to run inside the shell
  SHALL be present

#### Scenario: The shell is entered from outside this checkout

- **WHEN** the shell is entered from a directory belonging to another repository, or from no
  repository at all
- **THEN** it SHALL NOT configure any directory of that other repository
- **AND** where a working tree of this repository is required and absent, it SHALL refuse naming
  what it needed

### Requirement: A program's help text reaches an applied deployment

A program this repository publishes SHALL be usable from its own help text. The help SHALL state
what each positional argument may be, what an option's value looks like where the shape is not
obvious from its name, every constraint the parser enforces, and where the fuller document is. A
constraint the program refuses on SHALL be a constraint the help states.

#### Scenario: The help text is read as the only document

- **WHEN** a reader with no access to this repository reads the operator's command's help
- **THEN** they SHALL be able to name a target the command accepts and restrict a run to one entry
- **AND** every constraint the parser enforces SHALL be stated in the help of the subcommand that
  enforces it
- **AND** the help SHALL name the document that describes the command in full

### Requirement: The rows a document tabulates are the rows the tree produces

The set of row identifiers a document tabulates SHALL equal the set the library can produce. An
identifier in the tree and not the table, or in the table and not the tree, SHALL fail a suite naming
the identifier and the side it is missing from.

#### Scenario: The library gains a row

- **WHEN** the library can produce a row identifier no document tabulates
- **THEN** a suite SHALL fail naming that identifier
- **AND** the failure SHALL name the document the identifier belongs in

#### Scenario: A document tabulates a row the tree cannot produce

- **WHEN** a document tabulates an identifier the library no longer produces
- **THEN** a suite SHALL fail naming that identifier

### Requirement: A specification is classified exactly once

Every specification the planning record holds SHALL be classified exactly once: accounted for, or
excused with a reason that is true. A specification classified twice, and an excuse whose reason no
longer holds, SHALL each fail a suite naming the specification.

#### Scenario: A specification is both accounted for and excused

- **WHEN** one specification appears in both classifications
- **THEN** a suite SHALL fail naming that specification

#### Scenario: An excuse outlives the state it describes

- **WHEN** a specification is excused on the ground that its change is unimplemented
- **AND** that change is implemented
- **THEN** a suite SHALL fail naming that specification

### Requirement: The root document states how a host path reaches a unit

`README.md` SHALL state that a deployment declares intent and never plumbing: a host path a unit
needs SHALL be derived by the module that needs it, from the identity of its own entry, or SHALL
reach the module through an export and a wire. The document SHALL state the two consequences a
reader can check - that no deployment declaration carries a host path, and that a test asserting one
reads it out of the plan - and SHALL state them beside the design goal they serve, that a service can
be instantiated more than once.

The rule SHALL be asserted rather than remembered: a literal from the document SHALL be read by the
suite that checks the tree's shape, so that deleting the rule from the document fails a check naming
the document.

#### Scenario: The root document states how a path reaches a unit

- **WHEN** the repository shape suite reads `README.md`
- **THEN** it SHALL find the rule about deriving a host path from the entry's identity
- **AND** the check SHALL fail if that text is removed
