# operator/machine-report Specification

## Purpose
Defines what asking a machine about a deployment answers, so that an operator whose run broke can
tell what each machine holds. It owns the four answers a report has to keep apart - an entry the
endpoint does not register, a machine carrying no endpoint, a machine that cannot be reached, and an
entry the endpoint recorded a failure for - and the rule that one machine's silence costs one line.

## Requirements

### Requirement: A report answers per entry with what the machine recorded

A report SHALL answer one line per entry asked about, and the answer SHALL be what that entry's own
machine recorded rather than a reading of what the deployment intended. For an entry the endpoint
activates, the line SHALL carry the generation the machine holds, the identity the endpoint stores
for the artifact, and the error the endpoint recorded for it where it holds one. For an entry
realised as a portable-service image, the line SHALL carry the attachment state the machine's own
tool printed, and only the word that tool uses for a detached image SHALL be read as absence.

#### Scenario: The identity a machine holds is in its report line

- **WHEN** a report is asked about an entry a machine holds
- **THEN** the line SHALL name the generation the endpoint reports
- **AND** SHALL name the identity the endpoint stores for the artifact
- **AND** SHALL be derived from the endpoint's own answer rather than from the deployment record

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

### Requirement: Absence, a missing endpoint and silence are three answers

An entry a machine's endpoint answers about and does not register SHALL be reported as absent, and
absence SHALL be reported only on an endpoint's own answer. A machine whose endpoint cannot be run
SHALL be reported as carrying no endpoint, with what the machine printed, and a machine that does
not answer at all SHALL be reported as unreachable; neither SHALL be reported as absent. An entry
whose machine declares no address SHALL be reported as one the command will not dial, naming the
machine, rather than dialled and reported unreachable.

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

### Requirement: One machine's silence does not hide another's answer

A report covering more than one machine SHALL report every machine it was asked about. A machine
that cannot be reached SHALL cost its own line and SHALL NOT prevent the lines of the machines that
answered from reaching the operator. A report in which any machine could not be asked SHALL exit
non-zero, and a report in which every machine answered SHALL exit zero whatever the answers were.

#### Scenario: One unreachable machine does not hide the others

- **WHEN** a report covers two machines and one of them answers nothing
- **THEN** the entries of the machine that answered SHALL be reported with its answers
- **AND** the entries of the other SHALL be reported as unreachable

#### Scenario: A report that could not ask every machine exits non-zero

- **WHEN** at least one machine of a report could not be asked
- **THEN** the report SHALL exit non-zero
- **AND** a report whose machines all answered SHALL exit zero, including one whose every entry is
  absent

### Requirement: A delivered value the machine does not hold is reported

The report SHALL name, for each machine, every value the deployment delivers to it that the machine
does not hold. The line SHALL name the value and the machine, and SHALL NOT report anything about the
bytes of a value the machine does hold: whether a held value is the current one is a question the
report cannot answer without reading it, and reading a secret to report on it is not something this
command does.

A machine holding every value the deployment delivers to it SHALL produce no such line. The lines
SHALL be printed as they are known, beside the other facts each machine answers, and SHALL NOT change
the exit status: a missing value is a fact about a machine, and putting it back is an apply's work.

#### Scenario: A machine that lost its values

- **WHEN** a machine is reported on after a reboot that cleared the paths its values were written to
- **THEN** the report SHALL name each missing value and that machine
- **AND** the report SHALL exit zero

#### Scenario: A machine holding every value

- **WHEN** a machine holds every value the deployment delivers to it
- **THEN** the report SHALL name no missing value for that machine
- **AND** no line SHALL describe the bytes of a value

#### Scenario: A value delivered to one of two machines

- **WHEN** one machine of two holds its value and the other does not
- **THEN** the report SHALL name the missing value for the second machine only

### Requirement: A machine holding older configuration bytes is not reported as current

Where an entry's artifact shows the machine configuration bytes the realiser assembles, the report
SHALL NOT state that the machine is current on the strength of the artifact's identity alone: that
identity deliberately excludes those bytes, so an identity match is evidence about the image and not
about the file.

The report SHALL either compare what the machine holds at the declared path against what the build
would assemble, or SHALL state that the comparison covers the artifact and not the bytes shown beside
it. Whichever it does, the word the report prints for an entry whose configuration bytes are out of
date SHALL NOT be the same word it prints for an entry that matches in every respect.

#### Scenario: An entry whose configuration bytes are out of date

- **WHEN** a machine holds the current artifact of an entry and older bytes at a path that entry is
  shown
- **THEN** the report SHALL NOT print the word it prints for a fully current entry
- **AND** the line SHALL let an operator tell that the artifact matches and something beside it does
  not

#### Scenario: An entry that matches in every respect

- **WHEN** a machine holds the current artifact and the current bytes
- **THEN** the report SHALL print the word for a current entry

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

Staleness SHALL remain a line and never an exit status: a report whose machines all answered SHALL
exit zero however stale their answers are, because changing what a machine holds is the applying
command's work.

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

### Requirement: An image is compared by the identity of the entry's own image

For an entry realised as an image, the currency verdict SHALL be identity equality between the
identity the build published for that entry and the identity of that entry's own image on the
machine. The identity compared SHALL be selected out of what the machine reports by the entry it
belongs to, so that anything else the machine holds - a leftover attachment of an earlier build of
the same entry among them - decides no verdict.

Where the two identities differ, the line SHALL name both, so an operator can tell which build a
machine is running from the build the report was run against. Where they agree, the line SHALL say so
in the words reserved for identity equality, which SHALL NOT be lent to the other half of the
question: an endpoint that publishes no identity for what it activated is compared by the files of
the artifact it activated, and that line SHALL say only that the machine runs this build's units.

A report that compared anything else for an image SHALL NOT be taken to satisfy this requirement: an
attachment state, a name, or whichever of several images a machine lists first are each a fact that
can be true while the machine holds another build, so a verdict resting on one of them can call a
machine current when it is not.

#### Scenario: An image report names the identity of the entry's own image

- **WHEN** a machine holds and runs the image this build published for an entry, and also lists an
  attached image of an earlier build
- **THEN** the line SHALL state that the machine holds this build's identity
- **AND** SHALL NOT carry the identity of the earlier build
- **AND** the report SHALL exit zero

#### Scenario: A leftover attachment of another build does not decide the verdict

- **WHEN** a machine lists an image of another build for an entry and no image of this build
- **THEN** the line SHALL name the identity the machine holds and the identity the build published
- **AND** SHALL NOT read as current and SHALL NOT read as an entry the machine does not hold
- **AND** the report SHALL exit zero
