<!--
A delta against `realiser/portable-service-image`, whose current text is
`openspec/specs/realiser/portable-service-image/spec.md`. Three blocks are MODIFIED and one is
ADDED. Each MODIFIED block carries the whole requirement, and every scenario heading the current
text carries is kept: each already names a test
(`testEveryPathAGeneratedScriptNamesIsEscaped`, `testAUnitListIsEscapedWordByWord`,
`testTheStagingDirectoryIsTraversableAndNotListable`,
`test_a_staged_file_is_readable_through_a_directory_nobody_may_list`,
`test_a_staged_file_renders_a_secret`, `test_the_assembly_of_a_file_fails_part_way`,
`test_the_mode_does_not_depend_on_the_attaching_environment`), and a heading is a test name by
construction (`tests/unit/coverage.nix:52-53`).

The conditions this was written against.

The three scripts the artifact publishes are rendered as strings by `image/default.nix:471`, `:525`
and `:542`, and the record each is rendered from is the reading's: the attachment description
(`image/read.nix`'s `attachment`, spent at `image/default.nix:190`) and the configuration file
records (`image/read.nix:475-510`), which is where `staged`, `assembling` and `installing` come from
(`:506-508`) and where `install` decides who puts the bytes at the path (`:493`).

The assembly. `image/default.nix:230-278` creates the recipe's own file at `0600` (`:255`), appends
the literals and the references into it (`:202-217`), installs the candidate at `0600` onto the
`.installing` path (`:263`), owns and chmods that path (`:243-246`), moves it onto the staged path
(`:265`) and deletes the recipe file (`:276`). A file whose bytes are a declared `source` store path
takes the branch at `:249-252` and has no recipe file at all, so `:263` is the only create in its
path. Where the bytes already match, the record is applied to the staged path itself (`:260-261`),
which is why this delta states that branch rather than forbidding a record at the destination
outright.

The staging tree. `stagingDirectories` (`:295-314`) is the parent of the image's own directory, that
directory, and every component under it down to each staged file's parent, created by the one
statement at `:486-488`.

The escape. `lib/util.nix:190-193` states an escape that always quotes, and records why: a bare
safe-looking word is what `lib.escapeShellArg` leaves behind. `image/default.nix:197` spends it for a
value inside a message, where the double-quoted string is closed around the word because a `$(…)`
inside double quotes is a substitution whatever quoting sits within them. Everywhere else that file
spends `lib.escapeShellArg`, which renders an ordinary value bare, and `:426`, `:428` and `:447-450`
interpolate a store path with no escape at all - a difference nothing in the rendered text
distinguishes, which is the argument this delta's escape block is written on.

`A configuration file is shown at the record it states` is a precondition of the blocks below and is
left alone: it decides which files the script installs at all, and its sentence that an installed
file keeps the attach step's guarantees is the sentence the first block below makes checkable.
`The artifact's script makes the machine match the artifact, or refuses` is unchanged for the same
reason - it names the assembly's guarantees as a step of the script's order, and the order is not
what changes here. `The version digest an artifact publishes covers every statement its bytes depend
on` is untouched: a digest is taken over the statements the artifact was built from, and the
renderer is not one of them, so nothing here moves a digest or re-attaches an entry.
-->

## MODIFIED Requirements

### Requirement: A staged file carries its declared mode before it carries bytes

A file the realiser assembles or installs on the host SHALL carry the ownership and the mode its
record states from the moment a file exists at its path, so that no window exists in which it is
readable by anyone the declaration did not admit. The mode SHALL NOT depend on the environment the
attach runs in.

This SHALL hold for every file the script puts at a host path, whatever the source of its bytes. The
file the bytes are written into SHALL be a file other than the one the unit is shown; it SHALL be
created admitting its owner alone, whatever record it will carry and whatever mode its declaration
states; and it SHALL carry the declared ownership and the declared mode before it is moved onto the
path the unit is shown. A file whose bytes are a store path SHALL be installed through that same
candidate file, and the mode that install names SHALL be the whole of this guarantee for that
disposition, there being no other create in its path.

The record SHALL be applied where the bytes are and never to the destination after a write: a step
that created the destination and set its record afterwards leaves it at the file-creation mask of the
login running the script for the length of the write, and leaves a half-written file at that mask if
the run stops in between. The move is what makes the window empty rather than narrow. Where the bytes
the machine already holds equal the bytes this build would write, the script SHALL create no file and
SHALL apply the record to the file already at the path, because an unchanged file at a widened record
is still wrong.

A failure part way through assembling a file SHALL NOT leave that file readable more widely than its
declaration states. A file whose assembly did not complete SHALL either carry its declared mode or
not exist.

#### Scenario: A staged file renders a secret

- **WHEN** a configuration file declares a mode and renders a reference to a generated secret
- **THEN** the file on the host SHALL carry that mode from the moment it exists
- **AND** at no point SHALL it be readable by a user the mode excludes

#### Scenario: The assembly of a file fails part way

- **WHEN** the assembly of a declared file stops after some bytes are written
- **THEN** what remains on the host SHALL NOT be readable more widely than the declared mode
- **AND** the next attach SHALL be able to assemble the file again

#### Scenario: The mode does not depend on the attaching environment

- **WHEN** the attach runs with a permissive file-creation mask
- **THEN** the staged file's mode SHALL be the declared one
- **AND** SHALL NOT be widened by the environment

#### Scenario: A candidate is created admitting its owner alone

- **WHEN** the script is rendered for an entry declaring a file at a mode wider than its owner and
  for an entry declaring one narrower
- **THEN** each create of the file the bytes are written into SHALL name a mode admitting the owner
  alone
- **AND** no create in that file's path SHALL name the mode the record states

#### Scenario: A file whose bytes are a store path is installed through the same candidate

- **WHEN** the script is rendered for an entry whose configuration file names a store path as its
  source and states a record that store path cannot carry
- **THEN** the bytes SHALL be installed into a file other than the one the unit is shown, admitting
  its owner alone
- **AND** that file SHALL carry the record before it is moved onto the path
- **AND** the store path SHALL NOT be installed onto the path the unit is shown

#### Scenario: The record is applied before the move and never after it

- **WHEN** the script is rendered for an entry whose configuration file states an ownership and a mode
- **THEN** every step that sets an ownership or a mode over a file the script wrote SHALL name the
  file the bytes were written into
- **AND** the move onto the path the unit is shown SHALL be the last step over that file
- **AND** the step that applies the record to the path itself SHALL be the one taken where the bytes
  did not change

### Requirement: A value a generated script interpolates is escaped, grammar or no grammar

Every value this realiser interpolates into a script the artifact publishes SHALL appear in that
script only inside a single-quoted word, whether or not a grammar elsewhere already constrains that
value, and whether or not the value happens to carry a character a shell reads. This SHALL hold for a
value in a message as well as for a value in an argument: a message is not a place to rely on a
grammar, and a value inside a quoted message SHALL have that quoting closed around it, a substitution
inside double quotes being a substitution whatever quoting sits within them.

The obligation is stated as a property of the rendered text because that is the only form of it a
check can fail on. An escape that quotes according to the value leaves a value no shell would read
specially bare, so for an ordinary value the bytes a correct escape produces and the bytes a
forgotten escape produces are the same bytes, and no scan over the script can tell an interpolation
this realiser escaped from one it did not. A rule whose violation reads exactly like its observance
is a rule nothing holds, which is why an escape that quotes unconditionally is what this requirement
asks for and why any such escape satisfies it.

A value no grammar of this repository reaches SHALL be quoted for the same reason as one that is
grammar-held: a grammar and an escape fail independently, and the escape is what holds when a new
field reaches a script before its rule does. A store path this build names is such a value - it is
neither the deployment's nor the plan's - and SHALL be one quoted word at every site that names it,
including a comparison, a command argument and a message.

A list of derived names a script hands to a command SHALL be escaped word by word rather than joined
into one string, so that a name carrying a shell metacharacter is a word the command refuses rather
than a pattern the shell expands.

This requirement is a property of the rendered script and SHALL NOT be satisfied by a row: a plan the
library refused is a plan this realiser is never handed, and a caller reaching the realiser directly
is exactly the caller the escape protects.

#### Scenario: Every path a generated script names is escaped

- **WHEN** an entry's scripts are rendered for an entry whose configuration file paths are ordinary
- **THEN** every occurrence of a path in those scripts SHALL be inside a single-quoted word
- **AND** no occurrence SHALL be a bare interpolation, inside a quoted string or outside one

#### Scenario: A unit list is escaped word by word

- **WHEN** the attach script stops, starts or detaches the units of an entry
- **THEN** each unit file name SHALL appear as its own escaped word
- **AND** the list SHALL NOT be rendered as one unquoted string

#### Scenario: Every value the artifact records is one quoted word in every script it publishes

- **WHEN** the values the artifact's own records carry are read off those records and looked for in
  each script the artifact publishes
- **THEN** every occurrence of every such value SHALL sit inside a single-quoted word
- **AND** the set of values looked for SHALL be derived from the records rather than listed, so that a
  value the records gain is looked for by existing
- **AND** a value the records carry that no script names SHALL be reported as not found rather than
  counted as observed

#### Scenario: A store path the build names is one quoted word

- **WHEN** the scripts name the image the artifact carries, the verity data beside it and the
  directories the artifact was built into
- **THEN** each SHALL appear as one quoted word at every site that names it
- **AND** a comparison, an attach argument and a detach argument SHALL each carry it quoted

### Requirement: The staging directory is traversable and not listable

A directory this realiser's attach script creates to hold what the host shows an image SHALL be
created traversable by any account and listable by none, which is the mode the two writers of a
delivered value already create their directories at. A unit reads a staged file by its full path, so
traversal is the only access any account needs, and the file's own declared mode still decides its
bytes.

Every directory between the directory the machine owns and the parent of each file the script stages
SHALL be named in the statement that creates them, and that statement SHALL name the mode. A
component left for the create command to make for itself is made at a mode the artifact did not
state: for the create command this realiser spends, such a component is listable by any account
whatever the file-creation mask of the login running the script, so the exposure is not conditional
on a permissive environment and cannot be read off the script's own mode arguments.

The directory SHALL be created at that mode before it holds a file, and no later step SHALL widen it.
A listable directory would publish the configuration file names of every entry on the machine to any
account, and a listable directory above it would publish the entry names themselves, neither being a
fact about the deployment that any declaration asked to be published.

#### Scenario: The staging directory is traversable and not listable

- **WHEN** the attach script creates the directory it stages configuration files in
- **THEN** the directory SHALL be traversable by any account and listable by none
- **AND** each staged file SHALL still carry its own declared mode

#### Scenario: A staged file is readable through a directory nobody may list

- **WHEN** a unit reads a staged configuration file whose declared mode admits its account
- **THEN** the read SHALL succeed
- **AND** listing the staging directory as that account SHALL be refused

#### Scenario: Every directory of the staging chain is named where it is created

- **WHEN** the script is rendered for an entry whose staged file sits several directories below the
  entry's own
- **THEN** the statement that creates them SHALL name every directory from the machine's own down to
  that file's parent
- **AND** the set of directories it names SHALL be derived from the staged paths rather than listed
- **AND** no directory of that chain SHALL be left for the create command to make for itself

#### Scenario: Every directory above a staged file carries the traversable mode

- **WHEN** the script assembles a file on a machine under a root that held none of the chain before
- **THEN** every directory the script created from that root's own down to the file's parent SHALL be
  traversable by any account and listable by none
- **AND** the file SHALL still carry the mode its record states

## ADDED Requirements

### Requirement: Every create a published script makes names the mode it creates at

No step of a script the artifact publishes SHALL leave the mode of a path it creates to the
environment. Every step that creates a file or a directory SHALL name the mode it is created at, so
that the record the declaration states and the modes the realiser chooses are the only inputs to what
a run leaves on the machine, and a script run under a permissive file-creation mask leaves what a
script run under a restrictive one leaves.

A create whose own contract is to admit the owner alone and nobody else SHALL be admitted as the one
exception, and SHALL be named where it is spent, so that a reader and a check can tell a deliberate
exception from an omission. A create that names no mode and is not that exception SHALL be a defect
of this realiser rather than a step whose outcome the attaching login decides.

This SHALL hold for a directory as well as for a file, and for every script the artifact publishes
rather than the one that assembles: a path a report or a detach creates is on the machine at whatever
mode it was created at, however short its life.

#### Scenario: A create that names no mode

- **WHEN** the scripts the artifact publishes are read for the steps that create a path
- **THEN** every such step SHALL name the mode the path is created at
- **AND** a step that creates a path and sets its mode afterwards SHALL be reported as a create that
  names no mode

#### Scenario: A temporary whose contract is owner only

- **WHEN** a script creates a temporary file through a create whose contract admits the owner alone
- **THEN** that create SHALL be the only one admitted without a mode of its own
- **AND** the temporary SHALL be readable by no account the declaration did not admit
