<!--
A delta against `operator/machine-report`, whose current text is
`openspec/specs/operator/machine-report/spec.md`. Every block below is ADDED: the four answers the
report keeps apart - held, absent, no endpoint, unreachable - are unchanged and not restated, and
the fifth thing a report says is stated beside them rather than folded into one of them.

`Absence, a missing endpoint and silence are three answers` is a precondition of the blocks below
and is left alone: a holding the build does not name is not a fifth spelling of absence, because
absence is an answer about an entry the report asked about and a holding is a thing nobody asked
about. `One machine's silence does not hide another's answer` is why the exit status is stated
negatively here, and `A delivered value the machine does not hold` is the shape the new lines copy:
a fact about a machine that answered, printed as it is known, costing no exit status.

The conditions. `cli/report.py:94-135` asks one question per selected entry and one value question
per machine, and asks nothing about what else a machine holds. `cli/report.py:372-391` looks for an
image the machine listed only under the file name the build published for an entry it names, so an
entry deleted from the deployment matches nothing and reaches no line. `cli/remote.py:435-446`
asks the flakelet endpoint by name, so an entry no name is asked about is invisible to it, while
`cli/remote.py:449-470` and `cli/remote.py:482-512` already read the machine's whole image listing
and already keep the name and the state of every row of it.

What a machine's own answer carries about a holding differs by realiser, and the difference is not
cosmetic. `flakelet/read.nix:194` writes `flake_url = "plan:${image.key}"` into the artifact's
`meta.json`, and the endpoint reports it back as `locked_url` (`cli/report.py:275-277` prints it),
so a flakelet holding's answer carries the plan key of the entry it came from - which is why a
second copy of that literal is kept equal by comment in `tests/e2e/delivery.py:36`. An image carries
no such thing: `image/read.nix:919` composes the file name out of `image/read.nix:208`'s
`<instance>-<service>` and `lib/util.nix:495-496`'s sixteen hex digits, and that projection is not
injective, so a listed image names no plan key and the report may not invent one.

`lib/plan.nix:1404-1418` emits a `machine:<name>` record only for a machine some placement
selected, so a machine the build no longer names carries no address anywhere in the build. That is
why the last block states what the report does about such a machine: nothing, and it says so here
rather than leaving a reader to infer it from a missing line.
-->

## ADDED Requirements

### Requirement: A report names what a machine holds that the build does not name

A report SHALL name, per machine it asked, every holding that machine runs that the build being
reported against names no entry for. Each holding SHALL cost its own line, naming the machine and
the identity or the name the machine itself gave the holding, and the lines SHALL be printed as they
are known, beside the other facts that machine answers.

The identity a line carries SHALL be the machine's own answer. Where that answer carries the plan
key of the entry the holding came from, the line SHALL name that key. Where it carries only a name
the build's own naming is not recoverable from, the line SHALL name what the machine listed and
SHALL NOT present a plan key it derived from it: the name an artifact is addressed by is not
injective, so a key reconstructed from one would name an entry that may not be the entry the machine
is running.

A machine running nothing the build does not name SHALL produce no such line.

These lines SHALL NOT change the exit status. A report whose machines all answered SHALL exit zero
however many holdings it named, for the reason a stale entry and a missing value cost no exit status
either: a holding the build does not name is an answer a machine gave, not a machine that could not
be asked, and removing it is the applying command's work.

#### Scenario: A machine holds what no build names

- **WHEN** a deployment that placed two entries on one machine is applied, one entry is deleted from
  the deployment, and the machine is reported against the build that no longer names it
- **THEN** the report SHALL carry a line naming that machine and the entry it still runs
- **AND** the line SHALL carry the plan key the machine's own answer names it by
- **AND** the entry the build still names SHALL be reported as it was before

#### Scenario: A machine holding nothing unnamed is reported without such a line

- **WHEN** a machine holds exactly the entries the build names
- **THEN** the report SHALL name no holding for that machine
- **AND** the lines for its entries SHALL be unchanged

#### Scenario: An unnamed holding does not change the exit status

- **WHEN** a report names a holding the build does not name and every machine it asked answered
- **THEN** the report SHALL exit zero
- **AND** the line SHALL still be printed

#### Scenario: An image the machine holds for no entry of the build is named as the machine listed it

- **WHEN** a machine holds an attached image whose name belongs to no entry of the build being
  reported against
- **THEN** the report SHALL name that machine and the image name the machine listed
- **AND** SHALL NOT name a plan key for it

### Requirement: A holding is attributed before it is named

A machine's endpoint answers for everything it holds, and only some of it came from a deployment
this command applied. The report SHALL name a holding only where the deployment record publishes,
for the realiser that would have put it there, what a machine's own answer names that realiser's
holdings by, and only where the answer carries it. Anything else the machine holds SHALL be reported
as nothing: not as a holding, not as an entry, and not as an error.

Attribution SHALL reach this command and no further: it says the holding came from a deployment this
command applies, not that it came from the deployment being reported against. A machine two
deployments were applied to SHALL therefore have each deployment's entries named as holdings the
other does not name, and the report SHALL claim nothing more than that.

A holding of an entry the build does name, carrying an identity the build did not publish, SHALL
remain the answer the report already gives for a machine holding another build of a named entry, and
SHALL NOT also be named as a holding the build does not name: one fact earns one line.

#### Scenario: A service the machine's own configuration declares is not reported

- **WHEN** a machine's endpoint answers for an entry whose identity carries nothing the record
  publishes for that realiser
- **THEN** the report SHALL name no holding for it
- **AND** SHALL report the entries the build names as it otherwise would

#### Scenario: An earlier build's image of a named entry is not an unnamed holding

- **WHEN** a machine holds an image of an earlier build of an entry the build still names
- **THEN** the report SHALL name it as a machine holding another build's identity
- **AND** SHALL NOT also name it as a holding the build does not name

### Requirement: The selection bounds which machines are asked and not what counts as unnamed

Where a report is restricted to some of the deployment's entries, the restriction SHALL bound which
machines the report asks and SHALL NOT bound what counts as a holding the build does not name. A
holding SHALL be named only where the deployment places no entry that owns it at all; an entry the
deployment places and the restriction left out SHALL NOT be named as one, on any machine.

A machine no entry of the selection is placed on SHALL NOT be asked what it holds.

#### Scenario: An entry the selection excluded is not reported as unnamed

- **WHEN** a report is restricted to one of two entries a machine runs, and both are entries of the
  deployment
- **THEN** the report SHALL name no holding for that machine
- **AND** SHALL report the selected entry

#### Scenario: A machine the build no longer names is not asked

- **WHEN** a deployment is reported against after every entry of one of its machines was deleted
  from it
- **THEN** that machine SHALL NOT be contacted
- **AND** the report SHALL name no holding for it
- **AND** the report SHALL exit zero if every machine it did ask answered

### Requirement: What a machine holds is one question per machine

Whatever a machine holds, the report SHALL ask it in one question per machine rather than one per
holding: a machine's endpoint may be reached over a socket-activated login, and a burst of short
logins is answered by the socket's own trigger limit rather than by the endpoint.

An answer to that question the command cannot read as the endpoint's own SHALL be the command's own
refusal naming the machine and what it said, SHALL NOT be read as a machine holding nothing, and
SHALL make the report exit non-zero, because a machine whose answer cannot be read is a machine that
was not asked.

#### Scenario: The question of what a machine holds is asked once per machine

- **WHEN** a report covers three entries placed on one machine
- **THEN** the question of what that machine holds SHALL be asked once
- **AND** the answer SHALL be read for every holding it carries

#### Scenario: An answer about what a machine holds that the command cannot read is a refusal

- **WHEN** a machine answers the question of what it holds with something that is not its endpoint's
  own answer
- **THEN** the command SHALL refuse naming the machine and what it said
- **AND** SHALL NOT report that the machine holds nothing the build does not name
