<!--
A delta against `tooling/repository-shape`, whose requirements live in the unarchived
`clean-up-transplant-residue` change. That capability states what may exist in this repository and
that a path it names resolves. This delta reads it as a newcomer does: the root and the one shell
are the first two things a stranger opens and enters, and a program's help text is the only document
some readers have.

*Every top-level entry has a stated purpose* is restated to hold the root to naming what a command
it advertises needs and this repository cannot supply. *A path this repository names resolves* is
unchanged and is not restated. Three requirements are added: what the one shell is, what a program's
help text has to reach on its own, and what a document may say about a command it advertises.
-->

## MODIFIED Requirements

### Requirement: Every top-level entry has a stated purpose

Each top-level entry of the repository SHALL belong to one of the classes the repository states:
the library, a realiser, the deployment build, the operator's command, the tests, the fixtures the
tests read, the performance harness, the documentation of the library, the specification records,
the formatter's own configuration, or the flake. An entry belonging to none of them SHALL fail a
check naming it. A file SHALL NOT be kept in this repository solely because another file cites it;
the citing file SHALL state the fact instead.

The root SHALL state what the repository is, how the tree is laid out and which commands check it,
so that the first file a reader opens is not a document about one of the parts.

A command the root advertises SHALL be a command a reader can run. Where running it needs something
this repository cannot supply - a private dependency, a device, or a credential - the root SHALL
name that beside the command rather than in a document further down the reading order, so a reader
learns it before the run rather than from the failure.

#### Scenario: A top-level entry belongs to no stated class

- **WHEN** a top-level file or directory is added that is none of the stated classes
- **THEN** the check SHALL fail naming the entry
- **AND** SHALL name the classes that exist, so the entry is either classified or removed

#### Scenario: The root does not say what the repository is

- **WHEN** the repository root is read
- **THEN** it SHALL hold a document naming the library, the layout and the commands that check it
- **AND** that document SHALL name where the library's own reading order continues

#### Scenario: A command the root advertises needs something this repository cannot provide

- **WHEN** the root advertises a command whose run resolves a dependency this repository does not
  publish
- **THEN** the root SHALL name that dependency where it names the command
- **AND** SHALL say that a reader without it cannot run the command

## ADDED Requirements

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

### Requirement: A document does not advertise a command it reports as failing

A command a document shows SHALL succeed on a clean checkout of this repository, or the document
SHALL state exactly the condition under which it does not and which files are involved. A document
SHALL NOT show a command and separately describe it as failing without naming the cause, because a
reader who runs it cannot then tell their own edit from a known state.

#### Scenario: A document advertises a command it also says fails

- **WHEN** a document shows a command and elsewhere reports that the same command fails
- **THEN** the check SHALL fail naming the document and both places
- **AND** the report SHALL either be removed because the command succeeds, or name the files and
  the condition
