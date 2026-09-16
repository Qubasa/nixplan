<!--
A delta against `operator/apply-command`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`open-the-repository-to-a-consumer`, `hold-every-stated-guarantee`,
`order-a-cycle-by-its-strong-components`, `deliver-a-secret-without-exposing-it`,
`open-a-delivered-value-to-its-reader` and `take-effect-on-a-second-apply`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED and nothing is restated.
`deliver-a-secret-without-exposing-it` already requires that the bytes "reach a machine as the input
of the remote command that writes them" and appear in "the argument vector of no process on either
host"; that wording is correct and stays that change's. What is missing beside it is a property an
implementation can be observed against, which is what these two requirements are: what a process
table shows of a step, and what the channel change is not allowed to cost.

The condition: `cli/remote.py:306` base64-encodes the bytes, `:322` embeds the result as a literal of
the script string, `:264` makes that script the last element of the ssh argv, and `:84-90` runs the
argv through `subprocess.run` with no shell. `cli/apply.py:344-352` is the caller.

Every scenario here is machine-free and belongs to `tests/e2e/test_harness.py`, which
`checks.planner-delivery` runs: a step's argument vector is decided before anything is dialled, and
the write script runs the same under `bash -c` on this host as it does under a login shell on a
machine. A `/proc` sample taken while a real write is in flight is not the observation, because a
write lasts milliseconds and a sampling test that passed by missing the window would be worse than
no test; the argument vector the channel is handed is exactly what `execve` publishes to a process
table, so that vector is what is read.
-->

## ADDED Requirements

### Requirement: A step's argument vector is a function of the plan alone

Every step the command takes against a machine SHALL be addressed by an argument vector derivable
from the plan, the deployment record and the invocation's own options, and by nothing that was read
out of the value source. No element of that vector SHALL hold a byte of a generated value, an
encoding of one, or a digest of one. This SHALL hold for the process the command starts on the
operator's host and for the process a machine starts to run the step, which are one vector: the
machine's command line is the element of the local vector that carries the script.

The bytes of a value SHALL travel as the input stream of the step that writes them. Two runs that
deliver different bytes of one length to one path SHALL therefore run identical argument vectors,
and a run's argument vectors SHALL be knowable from the deployment without knowing any of its
secrets.

The payload SHALL be part of what a run's channel carries and SHALL NOT be part of what the run
records: no step line, no refusal, no log and no observer of the channel SHALL be handed the bytes
to keep. A run asked what it would do SHALL substitute its channel and nothing else, so the payload
reaches a channel that takes no step, and the lines the two runs print SHALL stay comparable one for
one.

#### Scenario: A process table observed during a value write

- **WHEN** an apply that writes a generated value is observed by reading the argument vectors it
  hands its channel, which is what a process table shows of each step
- **THEN** no element of any of them SHALL hold a byte of the value, a base64 or other encoding of
  it, or a digest of it
- **AND** the same SHALL hold for the machine's own command line, which is the element of that
  vector carrying the script

#### Scenario: Two values of one length run one argument vector

- **WHEN** one deployment is applied twice with two different values of one length for one file
- **THEN** the argument vectors of the two runs SHALL be identical
- **AND** the step lines of the two runs SHALL be identical

#### Scenario: A value write carries its bytes on the step's input stream

- **WHEN** a value write is taken with a payload that is not valid text
- **THEN** the file SHALL hold exactly the bytes handed over, unchanged
- **AND** the step SHALL still answer with the one word it reports
- **AND** an answer a machine gives that is not valid text SHALL be reported rather than ending the
  run

#### Scenario: A dry run hands no payload to the channel it substitutes

- **WHEN** a deployment carrying a delivered value is applied with the run asked what it would do
- **THEN** no step SHALL be taken and nothing SHALL be dialled
- **AND** the lines printed SHALL be the lines a real run prints, one for one

### Requirement: Moving the bytes onto the input stream costs the write none of its guarantees

A write whose bytes arrive on its input stream SHALL make every guarantee the write already made:
the temporary is created at `0600` before its first byte and never at the login's umask, the
recorded ownership is set before the recorded mode, the move into place is atomic and under a trap,
the ownership and the mode are set again after it on every apply, the parent directories are
traversable and not listable, and the step reports whether the bytes moved and never what they
moved to.

A write that fails after its bytes have arrived SHALL leave nothing of them behind: no temporary, no
fragment, and no file at a mode or an ownership the record does not state. The machine SHALL hold
either the file it held before or none, the run SHALL stop at that step, and the recovery SHALL be a
second apply rather than a repair.

#### Scenario: A write that fails after its bytes have arrived

- **WHEN** the bytes of a value have reached the machine and the step then fails at setting the
  recorded ownership
- **THEN** nothing holding those bytes SHALL be left on the machine
- **AND** the machine SHALL still hold the file it held before the step
- **AND** the run SHALL report the value, the file, the machine and what the machine said, and SHALL
  take no step after it

#### Scenario: A repeated write finishes what a failed one did not

- **WHEN** the same write is taken again after one that failed part way
- **THEN** it SHALL write the file and report that the bytes moved
- **AND** the file SHALL carry the recorded ownership and mode
