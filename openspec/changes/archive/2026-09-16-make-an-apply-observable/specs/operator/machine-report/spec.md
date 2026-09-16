<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It lives in
`cli/report.py`, beside the command whose other subcommands `operator/apply-command` owns in
`apply-deployments-with-an-operator-command`: that capability owns that the command can ask a
machine what it holds, and this one owns what the answer has to distinguish. It reads against
`realiser/flakelet-artifact` in `emit-flakelet-service-artifacts`, which owns what the endpoint
records and reports, and against `realiser/portable-service-image` in
`emit-systemd-portable-service-images`, which owns what attaching an image leaves on a machine.
Whether the identity a machine stores can be compared with the identity a build published is "The
identity a build publishes for an entry is the identity the machine stores" in
`report-every-refusal-as-a-row`, not this capability.
-->

## Purpose

Defines what asking a machine about a deployment answers, so that an operator whose run broke can
tell what each machine holds. It owns the four answers a report has to keep apart - an entry the
endpoint does not register, a machine carrying no endpoint, a machine that cannot be reached, and an
entry the endpoint recorded a failure for - and the rule that one machine's silence costs one line.

## ADDED Requirements

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
