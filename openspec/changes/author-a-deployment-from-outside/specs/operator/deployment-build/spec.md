<!--
A delta against `operator/deployment-build`, whose current text is
`openspec/specs/operator/deployment-build/spec.md`. One requirement is added and one is modified.

What this delta deliberately does not decide. It does not touch `The manifest is the whole interface
to a build`: the manifest is what a run applies, and an answer about the rows is not an answer about
the artifacts, so nothing about that requirement changes. It does not touch `The record a build
publishes is one every command can read`: `answer-a-machine-question-as-a-record` modifies that
block to restore `evidence` and `resolution` in the decode, and this change consumes whatever a row
carries rather than decoding one of its own - `openspec/changes/INTEGRATION.md` records that seam
and this set's order. It states nothing about what a deployment view renders:
`show-a-deployment-in-a-browser` owns that and consumes the same published answer.

The conditions. The rows and the rendered text are values already: `mkPlan` answers `diagnostics`
beside `plan` and `applicable` (`lib/default.nix:221-225`), the deployment build carries those rows
plus its own and publishes them (`operator/default.nix:341-347`), and the rendered text is a
function of the table alone (`lib/diagnostics.nix:173-182`, `docs/diagnostics.md:78-93`) which
`operator/default.nix:328` already evaluates for the `diagnostics.txt` of the farm. What is missing
is a route to them that realises nothing: `cli/planner.py:100-106` is `plan build apply status
rollback`, `build` resolves its target through `manifest.resolve`, which runs `nix build` for
anything that is not already a built directory (`cli/manifest.py:248-255`, the directory branch at
`:231-233`), and then reports what the result holds (`cli/planner.py:41-47`).

Which attribute an answer is read off is decided by the reading rather than by taste:
`operator/default.nix:71-75` and `:299-303` map every entry artifact and every machine artifact of
an inapplicable deployment onto `throw reading.refusal`, so a caller who evaluates the record as a
whole is handed the refusal in place of the table it is about - and an inapplicable deployment is
exactly the one an author is iterating on. `_build`'s exit status is the precedent for the status an
answer carries (`cli/planner.py:47`), `_plan` is the only subcommand that prints JSON today
(`cli/planner.py:35-38`), and `cli/planner.py:112-132` is the target description and epilogue every
subcommand states its target from.
-->

## ADDED Requirements

### Requirement: An author reads the rows without realising the deployment

The rows of a deployment and their rendered table SHALL be readable from an evaluation of the
deployment, without realising any artifact of it. Both SHALL be published as named attributes of the
deployment, and the rendered text SHALL be the one the build writes beside the rows rather than a
second rendering: rendering is the planner's, so one table has one text however it is reached.

An answer SHALL be read off those attributes by name. A caller SHALL NOT be required to evaluate the
deployment's record as a whole to reach them, and evaluating it as a whole SHALL remain the refusal
it is for an inapplicable deployment, because the per-entry and per-machine attributes of such a
deployment are that refusal.

The command SHALL carry a subcommand that prints the rendered table for a target and exits non-zero
where a row of it carries an error, which is the status a build of the same deployment reports. It
SHALL print the rows themselves, in the order the table put them, when asked for them as data, so
that a program reads one answer and a person reads the other and neither is a re-rendering of the
other. A target that is already a built deployment SHALL be answered from the files that build
wrote, with no evaluation at all; a target that names an attribute SHALL be answered by evaluating
it once. A target that answers neither the rows nor the rendered table SHALL be the command's own
refusal, naming the target and the two attributes it looked for, never a traceback and never an
empty table.

#### Scenario: The rows and the rendered table are read from an evaluation

- **WHEN** a deployment's rows and rendered table are read from its published attributes
- **THEN** both SHALL be answered
- **AND** no artifact of the deployment SHALL have been realised
- **AND** the rows SHALL be the rows the build writes and the text SHALL be the text the build
  writes

#### Scenario: The command answers a target it did not build

- **WHEN** the subcommand is given a target that is a directory a build of the deployment produced
- **THEN** it SHALL print the rendered table that build wrote
- **AND** it SHALL run no evaluation and no build

#### Scenario: An error among the rows is the exit status

- **WHEN** the subcommand is run against a deployment whose table carries an error, and then against
  one whose table carries warnings alone
- **THEN** the first SHALL exit non-zero and the second SHALL exit zero
- **AND** each SHALL print its table either way

#### Scenario: A target that answers no table is refused by the command

- **WHEN** the subcommand is given a target that answers neither the rows nor the rendered table
- **THEN** it SHALL refuse naming the target and the attributes it looked for
- **AND** it SHALL print no table and SHALL NOT report an empty one

#### Scenario: The rows a program reads are the rows the table ordered

- **WHEN** the subcommand is asked for the rows as data, twice, for one unedited deployment
- **THEN** both answers SHALL be equal
- **AND** the order SHALL be the order the table put the rows in
- **AND** each row SHALL carry every field the table's rows carry

## MODIFIED Requirements

### Requirement: An inapplicable deployment is not built

No entry of a deployment whose diagnostics carry an error SHALL be realised. The build SHALL still
produce the plan and both halves of the diagnostics, because a table nobody can read is of no use to
the deployment it describes, and the machine-readable half SHALL be reachable for exactly the
deployments it exists to describe. A caller asking for the artifact of an entry of such a deployment
SHALL be refused with the rendered table, so the reason is the planner's own words.

Both halves SHALL be reachable from an evaluation of such a deployment as well as from a build of
it, because the deployment an author is iterating on is the one the planner refused, and a table
that costs a build is a table an author reads last. Reaching them SHALL be by the attributes that
carry them; asking for the deployment's record as a whole SHALL be answered with the refusal, since
every entry artifact and every machine artifact of an inapplicable deployment is that refusal.

Applicability SHALL be read from the rows and never from the shape of the result: the result SHALL
carry no marker of its own about being refused, because a second statement of a fact the table
carries is a statement that can disagree with it. A table carrying no error SHALL build every entry
the reading realises, whatever else the table carries.

#### Scenario: A deployment whose diagnostics carry an error

- **WHEN** a build is asked for a deployment the planner reports as inapplicable
- **THEN** no artifact of any entry SHALL be produced
- **AND** a caller asking for one SHALL be refused with the rendered diagnostics table

#### Scenario: A deployment whose diagnostics carry only warnings

- **WHEN** a build is asked for a deployment whose table holds warnings and no error
- **THEN** every entry the reading realises SHALL be built
- **AND** the table SHALL still be part of the result

#### Scenario: Both halves of the table are reachable for a refused deployment

- **WHEN** a deployment the planner reports as inapplicable is built
- **THEN** the result SHALL hold the plan, the rows and the rendered table
- **AND** it SHALL hold no artifact of any entry
- **AND** nothing in the result SHALL state its applicability other than the rows themselves

#### Scenario: The table of an inapplicable deployment is read without building it

- **WHEN** the rows and the rendered table of a deployment the planner refused are read from its
  published attributes
- **THEN** both SHALL be answered
- **AND** nothing of the deployment SHALL have been realised
- **AND** the rows SHALL carry the error the planner reported

#### Scenario: A caller asking for the whole record is answered with the refusal

- **WHEN** a caller evaluates the record of an inapplicable deployment as a whole rather than the
  attributes that carry the table
- **THEN** the answer SHALL be the refusal carrying the rendered table
- **AND** the two attributes SHALL still answer when asked for by name
