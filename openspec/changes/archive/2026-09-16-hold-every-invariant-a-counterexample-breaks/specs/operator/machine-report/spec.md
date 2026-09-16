<!--
A delta against `operator/machine-report`, whose base text lives in the unarchived changes
`make-an-apply-observable`, `answer-whether-a-machine-is-current` and
`take-effect-on-a-second-apply`. `openspec/specs/` is empty in this repository, so the base text is
read from those changes.

Both requirements below are ADDED. The first reads against `Absence, a missing endpoint and silence
are three answers` in `make-an-apply-observable`, whose own sentence is that "absence SHALL be
reported only on an endpoint's own answer", and against `One machine's silence does not hide
another's answer`, which owns the exit status. The second reads against `An image is compared by the
artifact the machine holds` and `A report says whether a machine holds what the build published` in
`answer-whether-a-machine-is-current`, which state that an image's half of the currency question is
identity equality and that the other half compares the unit files of the active generation and says
only that a machine runs this build's units. Neither base requirement is edited: what is added is
which answers may produce the absence line at all, and that an image's comparison is against the
entry's own image and not against whatever the machine's listing prints first.

The conditions, both verified as tests in `cli/counterexample_test.py`. `cli/report.py:317-324`
reads the endpoint's answer as JSON and returns `absent` for every falsy value, so `null`, `0`,
`false` and `{}` are reported as a deployment that was never applied, and a truthy answer of another
shape - a status record rather than a list of registered entries, a number - is indexed at `[0]` and
escapes as a `KeyError` or a `TypeError` rather than as the command's own refusal
(`test_absence_is_an_endpoints_own_answer_and_nothing_else`,
`test_an_endpoint_answer_that_is_not_a_status_is_the_commands_own_refusal`). `cli/report.py:368-376`
reads the attachment the machine's own tool prints without selecting the entry's own image out of
the listing, so a leftover attachment of an earlier build decides the verdict and the line carries
that build's identity for an entry whose own image the machine holds and runs
(`test_an_image_report_names_the_identity_of_the_entrys_own_image`).
-->

## ADDED Requirements

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
