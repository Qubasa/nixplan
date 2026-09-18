<!--
A delta against `operator/machine-report`, whose current text is
`openspec/specs/operator/machine-report/spec.md`. One requirement is added and three are modified.

What this delta deliberately does not decide. It adds no question of a machine: the three questions
a report asks - one per entry, one per machine's values, one for what a machine holds
(`cli/report.py:139-168`) - keep their scripts, their argv and their folding. It changes no exit
status: `planner status` exits non-zero for the machines it could not ask and for nothing else
(`cli/planner.py:69-82`). It rewords no sentence: every line stays byte-identical, which is the
compatibility contract stated below. And it does not touch
`A delivered value the machine does not hold is reported`, whose sentence
`unseal-a-value-after-a-reboot` owns as `openspec/changes/INTEGRATION.md` records, nor
`A machine holding older configuration bytes is not reported as current` and
`An image is compared by the identity of the entry's own image`, both of which stay true unedited
because the words they hold the report to are the rendering's and the record names the identity
pair and the disagreeing paths they rest on.

The neighbouring seams. `show-a-deployment-in-a-browser` consumes the record this delta defines and
defines no machine question of its own; `author-a-deployment-from-outside` consumes the restored
diagnostics fields of the `operator/deployment-build` delta beside this one;
`openspec/changes/INTEGRATION.md` is the one place the order of the set and the rest of its seams
are written out.

The conditions. `Report` carries `lines: tuple[str, ...]` and `unasked` and nothing else
(`cli/report.py:81-86`), and every verdict is f-stringed at the site that computed it - the entry
line at `:144`, the value line at `:157-158`, the seal lines at `:159-160`, the holding line at
`:167`. The verdicts are structured before they are rendered: `_answered` tells five conditions
apart by an exit status (`:364-375`, against the sentinels at `:77-78` and `remote.UNREACHABLE` and
`remote.MISSING` at `cli/remote.py:59-60`), `_read_status` reads a generation, a locked url, a unit
comparison and a last error out of the endpoint's own JSON (`:422-436`, `:471-486`), and
`_read_attachment` reads an attachment state, projects the identity of the entry's own image out of
the listing, compares it against `entry.digest` and names the configuration paths that disagree
(`:489-521`, `:524-526`, `:529-548`). Two of those facts already exist as records inside `remote` -
`Attachment` (`cli/remote.py:851-858`) and `Holding` (`cli/remote.py:920-941`) - and both are
turned back into prose before a caller sees them, `Holding` by a `sentence` method the record
carries itself (`cli/remote.py:938-940`), called from the report (`cli/report.py:167`) and from the
apply (`cli/apply.py:205-215`). The consumer is an in-process importer, not a shell: the pure half
of the command is published as `packages.planner-src` (`cli/flake-module.nix:45`) and exported as
`PLANNER_CLI_SRC` (`flake-module.nix:201-207`), the end-to-end runner puts it on `PYTHONPATH`
(`tests/e2e/runner.py:26-29`, `:355`), and the harness and a folder's own tests already import the
modules (`tests/e2e/test_harness.py:34-44`, `tests/e2e/wired-pair/test_wired_pair.py:87-88`) and
assert against the prose (`tests/e2e/test_harness.py:2338-2341`,
`tests/e2e/portable-image/test_portable_image.py:878-881`).
-->

## ADDED Requirements

### Requirement: A machine question is answered as a record and its line is a rendering

Each question a report asks SHALL be answered as a record carrying the fields the verdict is made
of, and the library function that asks SHALL return those records to its caller. One record SHALL
be produced per question asked: one per entry asked about, one per value delivered to a machine,
and one per holding the build names no entry for.

The record of an entry SHALL carry the plan key, the machine and the realiser; how the machine was
reached, as one value of the closed set the report already tells apart; what the machine printed
where an answer carries that; whether the endpoint answered and registered nothing; the identity
the machine holds and the identity the build published for that entry; the comparison the
endpoint's own answer permits where it publishes no identity; the state the machine's own tool
printed; each configuration path whose bytes disagree with what the build would assemble, with the
word the machine's own check gave it; and the error the endpoint recorded for the entry where it
holds one. The record of a value SHALL carry the value key, the machine, whether the machine holds
every declared path of it, and the machine's own verdict on its sealed copy. The record of a
holding SHALL carry the realiser it is attributed to, the identity the machine answered, the name
the endpoint's own removal verb resolves, the state the answer carries and the machine it was asked
of.

No field SHALL be in a record that no reading computes: the field set SHALL be derived from what
the readings already produce, and a verdict the report does not make SHALL NOT be invented as a
field. A field that is meaningless for the way a machine was reached SHALL be absent rather than
empty, so that a consumer cannot read a missing answer as a fact.

Every line a report prints SHALL be the rendering of exactly one such record, produced by one
function, and no reading SHALL compose a line of its own. The lines SHALL be byte-identical to the
lines the command printed before this change, so that what an operator reads does not move and the
lines the operator's document states stay true. A record SHALL NOT be reachable only by a
serialisation of the command's output: the function SHALL return it, because what consumes it is a
program importing the command's own pure half.

A record that carries a machine's identity beside the build's SHALL NOT change any exit status. A
report whose machines all answered SHALL exit zero however stale the records are, for the reason a
stale line already does not: changing what a machine holds is the applying command's work.

#### Scenario: A record carries the fields the verdict is made of

- **WHEN** a report is asked about an entry whose machine answers with a generation, the identity
  it holds and an error it recorded
- **THEN** the record for that entry SHALL carry the plan key, the machine, the realiser, the
  identity the machine holds, the identity the build published and that error as fields
- **AND** no consumer SHALL have to read them out of a sentence

#### Scenario: A record names no field a reading does not compute

- **WHEN** the record of an entry whose machine could not be reached is read
- **THEN** every field the reading did not compute for it SHALL be absent rather than carrying an
  empty value
- **AND** the record SHALL carry no verdict the report does not make

#### Scenario: An operator's sentences do not move

- **WHEN** a report is run against a machine holding this build, a machine holding another build, a
  machine answering nothing and a machine holding a value the build delivers and a sealed copy that
  does not open
- **THEN** every line printed SHALL be byte-identical to the line the command printed for that
  answer before the record existed
- **AND** each line SHALL be the rendering of exactly one record

#### Scenario: A holding escapes as a record and the caller renders it

- **WHEN** a report and an applying run both name the same holding a machine answered
- **THEN** each SHALL receive the holding as a record rather than as a sentence
- **AND** both lines SHALL be produced by the one rendering function
- **AND** the line the applying run prints SHALL differ from the report's only in what it appends
  about what it did

#### Scenario: A stale record changes no exit status

- **WHEN** every machine of a report answers and one of them holds an identity the build did not
  publish
- **THEN** the record SHALL carry both identities
- **AND** the report SHALL exit zero

## MODIFIED Requirements

### Requirement: A report answers per entry with what the machine recorded

A report SHALL answer one record and one line per entry asked about, and the answer SHALL be what
that entry's own machine recorded rather than a reading of what the deployment intended. For an
entry the endpoint activates, the record SHALL carry the generation the machine holds, the identity
the endpoint stores for the artifact, and the error the endpoint recorded for it where it holds
one. For an entry realised as a portable-service image, the record SHALL carry the attachment state
the machine's own tool printed, and only the word that tool uses for a detached image SHALL be read
as absence.

The line SHALL be the rendering of that record and SHALL carry every one of those facts it carried
before this change, in the same bytes. A fact the record does not carry SHALL NOT appear in the
line: the line is derived from the record, so the record is where a fact an operator reads is
added.

#### Scenario: The identity a machine holds is in its report line

- **WHEN** a report is asked about an entry a machine holds
- **THEN** the line SHALL name the generation the endpoint reports
- **AND** SHALL name the identity the endpoint stores for the artifact
- **AND** SHALL be derived from the endpoint's own answer rather than from the deployment record
- **AND** the record it is rendered from SHALL carry both as fields

#### Scenario: An entry the endpoint recorded a failure for is not reported as healthy

- **WHEN** the endpoint reports an entry whose last activation it recorded as failed
- **THEN** the line SHALL carry that error
- **AND** SHALL NOT read as an entry running the generation it names
- **AND** the record SHALL carry that error as its own field

#### Scenario: An image reports the attachment word the machine printed

- **WHEN** a report is asked about an image entry the command applied, whose units the attachment
  started
- **THEN** the line SHALL carry the state the machine's own tool printed for that image
- **AND** SHALL NOT report the entry as absent because that word is not the plainest one the tool
  has

#### Scenario: The line is a rendering of the record it came from

- **WHEN** the same answer is rendered twice, once for the operator and once for a program reading
  the record
- **THEN** the line SHALL be produced from the record and not beside it
- **AND** no reading of the machine's answer SHALL compose a line of its own

### Requirement: Absence, a missing endpoint and silence are three answers

An entry a machine's endpoint answers about and does not register SHALL be reported as absent, and
absence SHALL be reported only on an endpoint's own answer. A machine whose endpoint cannot be run
SHALL be reported as carrying no endpoint, with what the machine printed, and a machine that does
not answer at all SHALL be reported as unreachable; neither SHALL be reported as absent. An entry
whose machine declares no address SHALL be reported as one the command will not dial, naming the
machine, rather than dialled and reported unreachable.

Each of those answers SHALL be one value of a single field of the entry's record, and the four
SHALL be distinguishable by reading that field. A consumer SHALL NOT have to match a word of the
rendered line to tell them apart: the line is prose an operator reads and every wording in it would
otherwise become a compatibility surface.

#### Scenario: An entry the endpoint does not register is reported as absent

- **WHEN** a machine's endpoint answers about an entry it has never been given
- **THEN** the line SHALL report the entry as absent
- **AND** the report SHALL treat the machine as having answered

#### Scenario: A machine with no endpoint is not reported as absent

- **WHEN** the endpoint a report asks for cannot be run on a machine
- **THEN** the line SHALL say the machine carries no endpoint
- **AND** SHALL carry what the machine printed about it
- **AND** SHALL NOT be the answer the report gives for an entry a machine does not hold

#### Scenario: A machine that cannot be reached is reported as unreachable

- **WHEN** a machine of the deployment does not answer a connection
- **THEN** each of its entries SHALL be reported as unreachable, naming the machine
- **AND** the report SHALL claim nothing about what that machine holds

#### Scenario: An entry whose machine records no address is not dialled

- **WHEN** a report covers an entry placed on a machine whose registry record declares no address
- **THEN** the line SHALL name the entry and the machine as one the command will not dial
- **AND** no connection SHALL be attempted for it

#### Scenario: The four answers are four values of one field

- **WHEN** one report covers an entry the endpoint does not register, an entry on a machine whose
  endpoint cannot be run, an entry on a machine that answers nothing and an entry on a machine
  declaring no address
- **THEN** the four records SHALL differ in the value of one field
- **AND** a consumer SHALL tell them apart without reading any rendered line

### Requirement: Only an endpoint's own answer produces the absence line

The absence line SHALL be produced by one fact and nothing else: an endpoint that answered and
registered no entry. No other answer SHALL be read as absence, because absence is what an operator
reads as a deployment that never reached the machine, and the whole point of the report is that each
of the ways a machine can fail to say what it holds costs its own line.

An answer the command cannot read as the endpoint's own status SHALL be its own condition, kept apart
from the four the report already distinguishes - an entry the endpoint does not register, a machine
carrying no endpoint, a machine that answers nothing, and an entry whose machine declares no address.
It SHALL be the command's own refusal naming the entry and what the machine said, SHALL NOT be read
as absence, and SHALL NOT escape as an unhandled error of the process that read it. A report that
could not ask a machine SHALL exit non-zero, and an answer the command cannot read is a machine that
was not asked.

The one fact absence rests on SHALL be a field of the record and not a spelling of the line, so that
a consumer reads absence rather than recognising a word, and the refusal SHALL stay a refusal rather
than becoming a value of that field: a machine whose answer cannot be read is a machine that was not
asked, and no record SHALL claim anything about what it holds.

Staleness SHALL remain a line and never an exit status: a report whose machines all answered SHALL
exit zero however stale their answers are, because changing what a machine holds is the applying
command's work. A record carrying the identity a machine holds beside the identity the build
published SHALL NOT change that: staleness becomes readable as data and stays absent from every
exit status the command has.

#### Scenario: Absence is an endpoint's own answer and nothing else

- **WHEN** a machine's endpoint answers something other than a registration of no entry - a value of
  another kind, or a value carrying no registered entry at all
- **THEN** the report SHALL NOT report that entry as absent
- **AND** the answer SHALL be reported as the condition it is, naming the entry and what the machine
  said
- **AND** an endpoint that answered and registered no entry SHALL still be the absence line

#### Scenario: An endpoint answer that is not a status is the command's own refusal

- **WHEN** an endpoint answers a value the command cannot read as its own status, whether that value
  is of another kind or of a shape the command cannot read an entry out of
- **THEN** the command SHALL refuse naming the entry and what the machine said
- **AND** the refusal SHALL be the command's own rather than an unhandled error
- **AND** the report SHALL exit non-zero rather than claiming anything about what the machine holds

#### Scenario: A staleness a record carries changes no exit status

- **WHEN** a report covers a machine that answered and holds an identity the build did not publish,
  a value the machine does not hold, and a holding the build names no entry for
- **THEN** each SHALL be a field of the record that names it
- **AND** the report SHALL exit zero
