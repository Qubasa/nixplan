<!--
A delta against `tooling/repository-shape`, whose current text is
`openspec/specs/tooling/repository-shape/spec.md`. One block is MODIFIED and two are ADDED.

`A path this repository names resolves` is modified rather than restated beside a second rule,
because its own sentence already holds a path a document names and the gap is in its enumeration of
who is held: `tests/unit/layers.nix:56-85` gives `CLAUDE.md` a class of its own, "the invariants an
author has to keep", which is neither the library, the tests, the fixtures nor the documentation of
the library, and the scan's own file set (`:295-312`) stops at the root's `*.nix`. The two readings
the block gains are decisions the current text does not take: which base a path in a root document
resolves against, and what a token that names a capability rather than a directory is.

`The rows a document tabulates are the rows the tree produces` (`:106-121`) is the precedent for the
first ADDED block and is not restated: it crosses a document's identifiers against what the library
can produce, one set against one set, and what is added here is the same principle where the
document names a file rather than a table.

The conditions, all read off the tree as it is today.

`scannedFiles` (`tests/unit/layers.nix:308-312`) is every file under the ten directories of
`scannedDirectories` (`:295-306`) plus the root's `*.nix`, and `repoNamedPaths` (`:316`) applies both
readings, `namedPathsOf` (`:171-182`) resolving a `./` or `../` token against the containing file's
own directory and `rootedPathsOf` (`:184-190`) resolving a token whose first segment is a top-level
entry against the repository root. `pathTokens` (`:115`) admits only a token beginning `./` or `../`
and `repoTokens` (`:126`) only one whose first segment is a top-level entry, so a bare filename is no
path token at all: `CLAUDE.md:387`'s `design.md` is invisible, and so is the same reference in the
already-scanned `tests/unit/platform.nix:355`. A bare-filename reading is not available - 58 of the
index's 66 filename-shaped backticked tokens name a file of a directory their sentence names and
resolve at no root - which is why the resolution rule is stated over a path and the dangling
reference is corrected rather than newly checked.

The index is read today only as a corpus: `recordFiles` (`:790-802`) makes it one of the texts
`stated` (`:808`) searches for a sentence a counterexample's comment pinned. It is never a subject.

Five of its statements disagree with the tree. `CLAUDE.md:871` quotes
`additionalSpace = "2048M"` where `tests/e2e/guest.nix:434` states `"6144M"`, which the index's own
figure at `:958` already contradicts. `CLAUDE.md:817` names `extraPythonPaths` and `pythonRoot`,
neither of which exists anywhere in the tree, where `treefmt.nix:55-57` writes a `mypy.ini` whose
`mypy_path` is the `cli` store path for the reason its own comment (`treefmt.nix:50-54`) gives.
`CLAUDE.md:53-54` calls `run-an-entry-without-root` the open change and `:716-719` lists it among
the five that have landed, its `tasks.md` carrying 27 ticked boxes. `CLAUDE.md:894` says
`portable-image` builds the same deployment twice where
`tests/e2e/portable-image/test_portable_image.py:1,17` says four. `CLAUDE.md:858` anchors the
derived-default argument at `lib/compose.nix:30-31`, which is the `]` and `in` closing `serviceKeys`,
where the evidence is `:42`'s `settings = settingsOf { inherit name defaults fixed; }`. A sixth,
`CLAUDE.md:460`, says `image/default.nix` has a `quoted` of its own where that file binds
`escapedWord` (`image/default.nix:197`) over `lib/util.nix:193`'s `shellQuote`; correcting it belongs
to `hold-the-attach-script-to-its-own-discipline`, which owns those bullets.

The status fact already exists: `changeHasLanded` (`tests/unit/coverage.nix:398-404`) reads the
anchored `- [x]` marker of a change's own `tasks.md` and `staleExcuses` (`:406-416`) spends it. The
marker is read anchored at the start of a line on purpose, because four of the production changes
name `- [x]` in prose.

What is deliberately not crossed is recorded at `CLAUDE.md:746-748`: a count a document states was
crossed by `testASuiteGainsATest`, `documentFigures` and `treeFigures`, and that requirement is
withdrawn rather than excused. The boundary below keeps it withdrawn.
-->

## MODIFIED Requirements

### Requirement: A path this repository names resolves

A path named by this repository's code, tests, fixtures, documentation or its index of invariants
SHALL resolve to a file or directory of this repository. This SHALL hold for a path literal an
evaluator reads and for a path written in prose or in a comment, because a reader follows both. A
reference that does not resolve SHALL fail a check that names the file it is in and the token that
failed, rather than being found by a reader. No document of this repository SHALL be exempt from this
by living where the check does not read: the set of files the check reads SHALL be derived from the
tree rather than listed, so that a document added beside the ones that exist is read by existing.

A path SHALL NOT reach outside the repository. Naming a file of another repository is permitted
only as a citation that states the fact it is citing, so that the sentence remains readable where
the cited file is not available.

A path a document at the repository root names SHALL be read as the repository sees it, rooted at
the repository. A fragment that states its own base - one beginning with `./` or `../` - SHALL NOT
be read as a path of that document: such a fragment is a quotation of an expression that lives in
another file, whose base is the file that holds it, and resolving it against the document's own
directory would refuse a correct quotation and admit an incorrect one.

A token that names a capability of the planning record SHALL resolve as that capability, whatever
directory its first segment shares a name with. A token naming neither a path of this repository nor
a capability the record holds SHALL fail the check, and the failure SHALL name the token, so that a
capability the repository never adopted is not read as a directory that was never there.

#### Scenario: A file names a path that is not there

- **WHEN** a file of the library, the tests, the fixtures, the documentation or the index names a
  path
- **THEN** that path SHALL resolve inside this repository
- **AND** a path that does not SHALL fail the check, naming the file, the line and the token

#### Scenario: A record is read as history

- **WHEN** a specification, proposal or task record under `openspec/` names a path
- **THEN** the resolution rule SHALL NOT apply to it
- **AND** the check SHALL state that a record describes the repository as it was when it was
  written, so a reader knows why the exemption exists

#### Scenario: The index of invariants names a path that is not there

- **WHEN** the index of invariants, or any other document at the repository root, names a path of
  this repository that does not resolve
- **THEN** the check SHALL fail naming that document, the line and the token
- **AND** the set of documents it read SHALL have been derived from the root rather than listed

#### Scenario: A document quotes a path relative to another file

- **WHEN** a document at the repository root quotes a fragment beginning `./` or `../`
- **THEN** the check SHALL NOT resolve it against the document's own directory
- **AND** SHALL report no failure for it

#### Scenario: A capability name is not a directory that is missing

- **WHEN** a document names a capability of the planning record whose first segment is also a
  top-level directory
- **THEN** the check SHALL resolve it as a capability and report no failure
- **AND** a name matching neither a path nor a capability SHALL fail the check naming the token

## ADDED Requirements

### Requirement: A code statement a document quotes is a claim about the file it names

A statement of this repository's own code that a document quotes SHALL be a statement the named file
makes. Two shapes of quotation SHALL be crossed and no others.

A quoted assignment - a fragment of a document that reads as a name, `=` and a value - SHALL appear
verbatim in a file of this repository. The corpus searched SHALL be the files the path scan reads,
excluding the documents themselves, so that one document quoting another's quotation satisfies
nothing. A fragment carrying a placeholder or an elision SHALL NOT be crossed: such a fragment is an
illustration of a shape and not a quotation of bytes, and crossing it would refuse a document for
teaching.

An identifier a document attributes to a named file SHALL appear in that file. The attribution SHALL
be read from the idioms the documents themselves use, stated once so that adding one is adding a
row, and SHALL be read only where the attributed-to operand names a file or directory of this
repository, so that an identifier stated beside an environment variable or a foreign program is not
read as a claim about a file. The named file's own code SHALL be what is read, its comment lines
dropped, and the identifier SHALL be matched as a whole identifier: a file that mentions the word in
prose does not define it, and a substring reading would report a claim as true because a longer
identifier or an English sentence contains the letters.

An identifier a document attributes to no file SHALL NOT be crossed. This residual SHALL be stated
rather than closed by searching the whole tree for every identifier a document quotes: a document
legitimately names a foreign identifier, a commit and a construct its own sentence says was deleted,
so a check over every quoted identifier would report a document for being accurate. Making an
unattributed claim crossable is the document's own work, by attributing it.

A failure SHALL name the document, the line, the fragment or identifier, and - for an attribution -
the file it was attributed to.

#### Scenario: A quoted assignment the tree no longer holds

- **WHEN** a document quotes an assignment whose text appears in no file of this repository
- **THEN** a suite SHALL fail naming the document, the line and the fragment
- **AND** correcting the fragment to the statement the tree makes SHALL remove the failure

#### Scenario: An illustration is not a quoted statement

- **WHEN** a document writes an assignment-shaped fragment carrying a placeholder or an elision
- **THEN** the suite SHALL NOT cross it against the tree
- **AND** SHALL report no failure for it

#### Scenario: An identifier attributed to a file that does not hold it

- **WHEN** a document attributes an identifier to a file of this repository, in one of the stated
  idioms, and that file's code does not name it
- **THEN** a suite SHALL fail naming the document, the line, the identifier and the file
- **AND** attributing it to the file that does name it SHALL remove the failure

#### Scenario: An identifier the named file only mentions in prose

- **WHEN** the identifier a document attributes to a file appears in that file only inside a comment,
  or only as part of a longer identifier
- **THEN** the suite SHALL still fail
- **AND** the failure SHALL name the same identifier and file

#### Scenario: An identifier a document attributes to no file

- **WHEN** a document quotes an identifier and names no file of this repository beside it
- **THEN** the suite SHALL NOT cross that identifier against anything
- **AND** SHALL report no failure for it

#### Scenario: A figure a reader maintains is not crossed

- **WHEN** a document states a count, a size or any other number in prose
- **THEN** no suite SHALL cross that number against a measurement of the tree
- **AND** a suite SHALL fail for a number only where the document quotes it as part of a statement
  the tree makes

### Requirement: A change's status is read off the record that derives it

Where a document of this repository states whether a planning change is open or has landed, that
word SHALL agree with the fact the planning record derives, and a disagreement SHALL fail a suite
naming the change, the word the document states and the fact the record derives.

The fact SHALL be derived from the change's own task record, by the same reading of the ticked
marker that decides whether an excuse for that change's specification still stands, and that reading
SHALL have one home: a document-side answer and an excuse-side answer about one change SHALL NOT be
derivable from two readings that can disagree. The marker SHALL be read anchored at the start of a
line, so that a task record naming the marker in prose is not read as a change that has started
landing.

Only a word the record can derive SHALL be crossed. A word that states a decision the task record
does not hold - that a change is parked, struck or narrowed - SHALL NOT be crossed, for the reason a
figure is not crossed: the record holds no answer to compare it against, and a check for it would be
a second place the decision is written.

A word SHALL be read as a claim about a change only where it stands beside that change's own name
and within the same sentence, so that a word belonging to a neighbouring sentence is not read as a
claim about the name that follows it.

#### Scenario: A change the document calls open has landed

- **WHEN** a document calls a change open and every task of that change's record is ticked
- **THEN** a suite SHALL fail naming the change, the word and the record
- **AND** stating the word the record derives SHALL remove the failure

#### Scenario: A change the document calls landed has work left

- **WHEN** a document calls a change landed and a task of that change's record is not ticked
- **THEN** a suite SHALL fail naming the change, the word and the record

#### Scenario: A status word the record cannot derive

- **WHEN** a document says a change is parked, struck or narrowed
- **THEN** no suite SHALL cross that word against the change's task record
- **AND** the change SHALL earn no failure for it

#### Scenario: A task record names the marker in prose

- **WHEN** a change's task record writes the ticked marker inside a sentence rather than at the start
  of a line
- **THEN** the derived fact SHALL be that no task of that change has been ticked
- **AND** both the document-side and the excuse-side answers SHALL be that same fact
