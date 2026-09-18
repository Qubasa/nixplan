<!--
A delta against `operator/deployment-build`, whose current text is
`openspec/specs/operator/deployment-build/spec.md`. One requirement is modified; nothing is added.

What this delta deliberately does not decide. It changes nothing the build writes: the reading
already publishes six fields per diagnostics row and `operator/default.nix:319-329` already writes
them into `diagnostics.json` beside the rendered `diagnostics.txt`. It adds no row, no realiser
fact and no manifest table, and it takes no decision about the machine answers the
`operator/machine-report` delta beside it owns. The record version the build states is not moved:
no field of the manifest changes, only what the command's own decode keeps of a file the build
already writes whole.

The neighbouring seams. `author-a-deployment-from-outside` consumes the two restored fields, which
is what lets a rows-without-a-build command tell an author what was observed and which declaration
to edit; `show-a-deployment-in-a-browser` consumes the same decode.
`openspec/changes/INTEGRATION.md` is the one place the order of the set and the rest of its seams
are written out.

The conditions. `lib/diagnostics.nix:45-63` requires six fields of every row a producer builds -
`id`, `subject`, `severity`, `message`, `evidence`, `resolution` - and the comment above it states
why: a row with no resolution is a row nobody can act on. `cli/manifest.py:664-679` decodes four of
them into the four-field `Diagnostic` (`cli/manifest.py:123-131`), dropping `evidence` and
`resolution`, and that decode is the only reader of `diagnostics.json` the command has: every
consumer of a build's rows goes through it, `Deployment.rendered` included, which composes lines out
of the decoded rows where the build wrote no table (`cli/manifest.py:206-210`). So the one path
designed for a program rather than for a reader is the one that loses the two fields an author most
needs, while the rendered table beside it keeps them.
-->

## MODIFIED Requirements

### Requirement: The record a build publishes is one every command can read

An entry's record in the manifest SHALL be readable by every command that reads the manifest,
whatever the entry declares. Where an entry legitimately has no artifact - a placed entry that
declares no unit is one the planner accepts - the record SHALL say so in a shape the reading side
accepts, and SHALL NOT be a value the reading side refuses.

A record of one entry SHALL NOT make a command refuse the whole deployment: a command that needs an
artifact only for some entries SHALL refuse only when it needs the one that is absent.

A diagnostics row the build publishes SHALL be read by the command with every field the producer
built it with: its identifier, its subject, its severity, its message, the evidence it records and
the resolution it names. A command SHALL NOT keep a subset: the row is the one shape in the build
designed for a program to read, the evidence says what was observed and the resolution names the
declaration to edit, and a program handed neither can say less about a refusal than the rendered
table beside it does.

The six fields SHALL be restored in the one decode of the published rows that every reader of them
already goes through, and SHALL NOT be reached by a second reader of the same file. Two decodes of
one file diverge - a field one defaults and the other requires, a row shape one refuses and the
other accepts - and the reader every command already uses would stay the lossy one, so a consumer
reaching for the evidence would have to know which of two readers to import.

#### Scenario: An entry declares no unit

- **WHEN** a deployment places an entry that publishes an export and runs nothing
- **THEN** the build SHALL publish a record for that entry
- **AND** every command that reads the manifest SHALL read it without refusing
- **AND** a command that does not need an artifact for that entry SHALL proceed

#### Scenario: A command needs the artifact an entry does not have

- **WHEN** a command needs an artifact for an entry whose record names none
- **THEN** the refusal SHALL name that entry
- **AND** SHALL NOT be a refusal of the entries whose records the command can read

#### Scenario: A diagnostics row reaches a program with its evidence and its resolution

- **WHEN** a command reads a build whose deployment the planner refused, whose rows each carry an
  evidence and a resolution
- **THEN** every row the command holds SHALL carry all six fields the producer built it with
- **AND** a program reading the rows SHALL be able to name the declaration to edit without reading
  the rendered table

#### Scenario: One decode carries the fields for every reader

- **WHEN** two consumers of a build read its diagnostics rows
- **THEN** both SHALL read them through the one decode of the published rows
- **AND** no second reader of that file SHALL exist to carry the two fields the first one dropped
