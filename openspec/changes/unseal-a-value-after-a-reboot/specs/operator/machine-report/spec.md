<!--
A delta against `openspec/specs/operator/machine-report/spec.md`.

`A delivered value the machine does not hold is reported` (`openspec/specs/operator/machine-report/
spec.md:95-122`) is MODIFIED. The requirement itself is untouched; its first scenario is not
producible any more the way it is written. It says "a machine is reported on after a reboot that
cleared the paths its values were written to", and after this change a machine that seals restores
those paths by itself, so a reboot is no longer a way to produce a missing value there. The block
below is that requirement copied whole with that scenario's condition restated as what actually
produces the line - a machine whose value paths are cleared and which holds no copy it can open -
and with the sentence about what the report asks widened to the one question per machine it now
asks. The two other scenarios are unchanged and are carried because a MODIFIED block is the whole
requirement.

The new requirement is ADDED. It does not touch `Absence, a missing endpoint and silence are three
answers` (`:41`) or `One machine's silence does not hide another's answer` (`:75`): a seal that does
not open is an answer a machine gave, so it is a line and not a machine that could not be asked,
which is why the exit status is stated negatively below.

`answer-whether-a-machine-is-current` modifies `A report answers per entry with what the machine
recorded` and adds two requirements about comparing a machine against a build. Nothing here touches
any of the three.

The conditions:

- `cli/report.py:126-135` asks one question per machine and reads `<path> present|absent` off it
  (`cli/remote.py:400-417`), one question rather than one per file because the guest's sshd is
  per-connection socket activated. `cli/report.py:169-180` reads nothing about the bytes of a file
  that is there.
- `cli/report.py:137-167` is the per-machine value index, built from the delivery sets of the
  selection, and it skips a machine that declares no address.
- `tests/e2e/secret-delivery/test_secret_delivery.py:680-711` is the test that asserts the reboot
  case today, and it is the last phase because `/run` is what a reboot empties.
- Whether a machine's values are sealed is the deployment record's answer
  (`operator/read.nix`, the machines table this change adds), and the trial that decides whether a
  sealed copy opens is the machine's own unsealer, which is on the machine only after an apply.
-->

## MODIFIED Requirements

### Requirement: A delivered value the machine does not hold is reported

The report SHALL name, for each machine, every value the deployment delivers to it that the machine
does not hold. The line SHALL name the value and the machine, and SHALL NOT report anything about the
bytes of a value the machine does hold: whether a held value is the current one is a question the
report cannot answer without reading it, and reading a secret to report on it is not something this
command does.

A machine holding every value the deployment delivers to it SHALL produce no such line. The lines
SHALL be printed as they are known, beside the other facts each machine answers, and SHALL NOT change
the exit status: a missing value is a fact about a machine, and putting it back is an apply's work.

What a machine is asked about its values SHALL stay one question per machine however many values and
copies of them it holds, because a machine's own service manager may answer a burst of short logins
by refusing the next connection, and a report that cost a login per file would fail as a machine that
died.

#### Scenario: A machine that lost its values

- **WHEN** a machine is reported on after the paths its values were written to were cleared and it
  holds no copy of them it can open
- **THEN** the report SHALL name each missing value and that machine
- **AND** the report SHALL exit zero

#### Scenario: A machine holding every value

- **WHEN** a machine holds every value the deployment delivers to it
- **THEN** the report SHALL name no missing value for that machine
- **AND** no line SHALL describe the bytes of a value

#### Scenario: A value delivered to one of two machines

- **WHEN** one machine of two holds its value and the other does not
- **THEN** the report SHALL name the missing value for the second machine only

## ADDED Requirements

### Requirement: A machine that cannot recover its own values is reported as such

For a machine the deployment record says holds sealed values, the report SHALL name every value of
it whose sealed copy the machine cannot open, and every value of it that has no sealed copy at all.
Both lines are about one thing an operator cannot see any other way: that machine will not have that
value after its next reboot.

The verdict SHALL be the machine's own answer, obtained by asking the machine's own unsealer whether
the copy opens, and never by reading the copy back or by comparing an identity the report holds: the
identity a copy was sealed to is recoverable from the copy, and the tool that would answer from it is
the same tool the trial runs. Nothing about the bytes of a value, sealed or plain, SHALL be printed
or transferred.

A machine the record says seals and which holds no unsealer SHALL be reported as one whose sealed
copies were not checked, naming the machine, rather than as one holding copies that open or copies
that do not.

Neither line SHALL change the exit status. A machine that answered is not a machine that could not be
asked, and a machine that will not recover by itself is still a machine an apply can put right.

#### Scenario: A machine holding a sealed copy it cannot open

- **WHEN** a machine's sealed copy of one value is replaced by one it cannot open and the report is
  run
- **THEN** the report SHALL name that value and that machine as a copy that does not open
- **AND** the report SHALL exit zero, and SHALL print no line about any other value of that machine

#### Scenario: A machine that seals and holds no sealed copy

- **WHEN** a machine the record says seals holds a value's plaintext and no sealed copy of it
- **THEN** the report SHALL name that value and that machine as one with no sealed copy
- **AND** the report SHALL exit zero

#### Scenario: A machine that holds no unsealer is not reported either way

- **WHEN** a machine the record says seals has never been applied to, so it holds no unsealer
- **THEN** the report SHALL say its sealed copies were not checked, naming the machine
- **AND** SHALL NOT report its copies as opening or as failing to open
