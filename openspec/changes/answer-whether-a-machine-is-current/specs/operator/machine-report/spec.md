<!--
A delta against `operator/machine-report`, which lives in the unarchived `make-an-apply-observable`
change. `openspec/specs/` is empty in this repository, so the base text is read from there.

`A report answers per entry with what the machine recorded` is MODIFIED: its own header comment
delegates "whether the identity a machine stores can be compared with the identity a build published"
to `report-every-refusal-as-a-row`, which states that the identity is published and comparable and
does not state that anything compares it. The block below is that requirement copied whole, with the
comparison added.

`Absence, a missing endpoint and silence are three answers` and `One machine's silence does not hide
another's answer` are unchanged and not restated. The second is why the exit status is stated
negatively in the ADDED requirement: a stale entry is not a machine that could not be asked.

The conditions: `operator/read.nix:210` computes the identity and `:492` publishes it as an entry's
`key`; `cli/manifest.py:347-366` does not read it; `cli/report.py:216-233` renders the endpoint's
generation and locked url and compares nothing; `cli/report.py:219` reads an image's attachment
as a word rather than as an identity, though `image/read.nix:512` puts the identity in the image's
own file name.

Two comparisons rather than one, because only one endpoint names what it holds. An image's file
name carries the published identity, so that half is identity equality. A flakelet endpoint stores
the identity in the generation it keeps and reports it nowhere: what `flakelet status --json`
prints is `ServiceStatus` (`flakelet-core/src/manager.rs:86-108` at the locked revision), and the
only fact of it that moves with the artifact is the unit files of the active generation. That is
what the weaker comparison compares, and the requirement makes the line say so rather than let a
narrower answer wear the word `current`.
-->

## ADDED Requirements

### Requirement: A report says whether a machine holds what the build published

For every entry a machine answers about, the report SHALL state whether what the machine holds for
that entry is what the build being reported against published for it. Where a machine names the
identity the build published and the two agree, the line SHALL say so. Where they differ the line
SHALL carry both identities, so that an operator can tell a machine running an older build from a
machine running this one.

Where a machine's own answer names the identity the build published for an entry, that identity
SHALL be the one compared, and it SHALL be read from the deployment record rather than recomputed
from the plan, the artifact or the entry's content, so that a report cannot disagree with the build
it was run against.

Where a machine's answer names no such identity, the report SHALL compare the strongest fact that
answer does carry against the same fact of the artifact the build produced, and the line SHALL say
which comparison it made. A line resting on the weaker comparison SHALL NOT be written in the words
the identity comparison uses: it answers the narrower question of whether the machine runs what this
build produced, and a reader must be able to tell the two apart. Where an answer carries no
comparable fact at all the line SHALL say the machine reported nothing to compare, and SHALL NOT
read as current.

An entry an endpoint holds under an identity the build does not publish SHALL be reported as an
identity from another build rather than as absent or as current: three answers, not two.

A record that publishes no identity for a placed entry SHALL be refused as a record the command
cannot read, naming the entry and the field, the way a record of an unsupported version is refused.

Whether a machine is current SHALL NOT change the report's exit status. A report whose machines all
answered SHALL exit zero whatever the answers were, because a stale entry is a fact about the machine
rather than a question the report could not ask, and changing it is the applying command's work.

#### Scenario: A machine holding this build is reported as current

- **WHEN** a report is asked about an entry whose machine holds the identity this build published
- **THEN** the line SHALL state that the machine holds this build's identity
- **AND** the report SHALL exit zero

#### Scenario: A machine holding an older build is reported with both identities

- **WHEN** a report is asked about an entry whose machine holds an identity this build does not
  publish for it
- **THEN** the line SHALL carry the identity the machine holds and the identity the build published
- **AND** SHALL NOT read as an entry the machine does not hold
- **AND** the report SHALL exit zero

#### Scenario: A fleet part way through an apply reports both answers

- **WHEN** a report covers two machines, one applied from this build and one from an earlier one
- **THEN** the first machine's entries SHALL be reported as holding what this build produced
- **AND** the second machine's entries SHALL be reported as not holding it
- **AND** the report SHALL exit zero

#### Scenario: A record publishing no identity is refused

- **WHEN** a deployment record carries a placed entry with no published identity
- **THEN** the command SHALL refuse naming the entry and the field
- **AND** SHALL NOT report that entry with no verdict

#### Scenario: An endpoint that reports no identity is compared by what it does report

- **WHEN** a report is asked about an entry whose endpoint reports no identity for the artifact it
  activated
- **THEN** the line SHALL state whether the machine runs the artifact this build produced
- **AND** SHALL NOT state that the machine holds this build's identity
- **AND** the report SHALL exit zero

#### Scenario: An endpoint that reports nothing to compare is not reported as current

- **WHEN** an endpoint's answer for an entry carries neither the published identity nor the files
  of the artifact it activated
- **THEN** the line SHALL say the machine reported nothing to compare
- **AND** SHALL NOT read as current and SHALL NOT read as another build's identity

### Requirement: An image is compared by the artifact the machine holds

An image entry's identity is carried by the artifact a machine has attached, so a report about an
image SHALL read which image is attached and SHALL compare that against the identity the build
published. A machine holding an attached image from an earlier build SHALL be reported as holding
that build's identity, and SHALL NOT be reported as current merely because something is attached.

The attachment state and the identity are two facts and SHALL both be reported: an image may be
attached and stale, and a report that collapsed them would answer neither question.

#### Scenario: An attached image from an earlier build is not reported as current

- **WHEN** a machine has an image of an earlier build attached for an entry
- **THEN** the line SHALL name the identity the machine holds and the identity the build published
- **AND** SHALL also state that an image is attached

#### Scenario: An attached image of this build is reported as current

- **WHEN** a machine has the image this build published attached for an entry
- **THEN** the line SHALL state that the machine holds this build's identity
- **AND** SHALL state the attachment state the machine's own tool printed

## MODIFIED Requirements

### Requirement: A report answers per entry with what the machine recorded

A report SHALL answer one line per entry asked about, and the answer SHALL be what that entry's own
machine recorded rather than a reading of what the deployment intended. For an entry the endpoint
activates, the line SHALL carry the generation the machine holds, the identity the endpoint stores
for the artifact, and the error the endpoint recorded for it where it holds one. For an entry
realised as a portable-service image, the line SHALL carry the attachment state the machine's own
tool printed, and only the word that tool uses for a detached image SHALL be read as absence.

Each line SHALL additionally carry the verdict of comparing what the machine holds against what the
build published, by whichever of the two comparisons in "A report says whether a machine holds what
the build published" that machine's answer supports. What the machine holds remains the machine's
own answer; the verdict is the comparison of that answer with the build, and neither SHALL be
presented as the other.

#### Scenario: The identity a machine holds is in its report line

- **WHEN** a report is asked about an entry a machine holds
- **THEN** the line SHALL name the generation the endpoint reports
- **AND** SHALL name the identity the endpoint stores for the artifact
- **AND** SHALL be derived from the endpoint's own answer rather than from the deployment record
- **AND** SHALL carry the verdict of comparing what it reports with what the build published

#### Scenario: An entry the endpoint recorded a failure for is not reported as healthy

- **WHEN** the endpoint reports an entry whose last activation it recorded as failed
- **THEN** the line SHALL carry that error
- **AND** SHALL NOT read as an entry running the generation it names

#### Scenario: An image reports the attachment word the machine printed

- **WHEN** a report is asked about an image entry the command applied, whose units the attachment
  started
- **THEN** the line SHALL carry the state the machine's own tool printed for that image
- **AND** SHALL NOT report the entry as absent because that word is not the plainest one the tool
  has
