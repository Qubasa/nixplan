<!--
A delta against `operator/machine-report`, whose base text lives in the unarchived changes
`make-an-apply-observable` and `answer-whether-a-machine-is-current`. `openspec/specs/` is empty in
this repository, so the base text is read from those changes.

Every requirement below is ADDED. What the report asks each machine, that absence is an endpoint's
own answer, that a machine that could not be asked exits non-zero, and that staleness is a line and
never an exit status are unchanged.

The conditions: a delivered value lives under `/run` (`lib/resolve.nix:949`), which no machine keeps
across a reboot, and no line of the report mentions a value at all; and an image entry's identity
excludes its configuration bytes (`image/read.nix:302-318`), so a machine holding older bytes is
reported `current`.
-->

## ADDED Requirements

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
