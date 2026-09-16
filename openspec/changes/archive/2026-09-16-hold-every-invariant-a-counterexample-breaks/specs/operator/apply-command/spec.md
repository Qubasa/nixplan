<!--
A delta against `operator/apply-command`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`open-the-repository-to-a-consumer`, `deliver-a-secret-without-exposing-it`,
`keep-a-secret-out-of-a-process-table`, `open-a-delivered-value-to-its-reader`,
`hold-every-stated-guarantee`, `order-a-cycle-by-its-strong-components` and
`take-effect-on-a-second-apply`. `openspec/specs/` is empty in this repository, so the base text is
read from those changes.

Every requirement below is ADDED, and each names the base requirement it reads against. The
rotation reads against `A changed value restarts the entries that read it` in
`take-effect-on-a-second-apply`, whose own sentence is "the same source the activation order is
derived from", and against `One command applies a whole deployment` in `hold-every-stated-guarantee`,
which states that every shape a resolved read is recorded in contributes its edges. The refusal of
an unreadable read shape reads against that same requirement and against `An order the command
cannot compute is a refusal` in `order-a-cycle-by-its-strong-components`. The containment rule reads
against `The manifest is the whole interface to a build` and `The command refuses a deployment record
it cannot read` in `make-an-apply-observable`, and against `Every refusal a run can make without a
machine precedes the first machine` in `hold-every-stated-guarantee`. The value-source rule reads
against `The value source is measured where the deployment declares files` in
`make-an-apply-observable`, whose "Every file so found SHALL be named, not the first of them" is the
sentence deepened here. The naming rule reads against `A failure on a machine is reported without the
arguments that produced it` in `deliver-a-secret-without-exposing-it` and `A step's argument vector
is a function of the plan alone` in `keep-a-secret-out-of-a-process-table`. None of those
requirements is edited.

The conditions, all verified as tests in `cli/counterexample_test.py`. `cli/apply.py:207-210` reads a
resolved read's providers from `slot["values"]`, the single-valued shape only, while
`cli/order.py:315-320` reads both that shape and the `entries` shape a `reach = "all"` read is
recorded in (`lib/plan.nix:227`), so a set-valued reader is ordered against and never restarted after
a rotation (`test_a_set_valued_read_of_a_secret_rotates_its_consumer`). `cli/order.py:313-314`
returns no providers for a resolved read that is not a record, before the `delivered` gate that
refuses the other unrecognised shapes, so such a consumer is activated before its provider with no
refusal (`test_a_delivered_read_in_neither_shape_is_refused`). `cli/manifest.py:388-393` resolves a
stated artifact path as `(root / stated)` with no containment check, so `/etc` or a path above the
build is copied to a machine and activated (`test_an_artifact_path_that_leaves_the_build_is_refused`).
`cli/values.py` measures a value's directory one level deep, so a file below a subdirectory of it is
named by nothing (`test_every_undeclared_file_inside_a_values_directory_is_named`). And
`cli/remote.py`'s `destination` recovers the machine from the command vector rather than from the
record, so an option value carrying an `@` - `-o Ciphers=aes256-gcm@openssh.com` is an ordinary one -
can be reported as the machine (`test_a_refusal_names_the_machine_and_not_an_ssh_option`).
-->

## ADDED Requirements

### Requirement: A read that orders an apply is a read that rotates its consumer

The reads that order a run and the reads that decide which consumers a moved value restarts SHALL be
one relation over the reads the plan resolved. Every shape a resolved read is recorded in SHALL
contribute to both: a read naming one provider and a read naming every provider of a set SHALL each
order the consumer after its providers and SHALL each restart that consumer when the bytes of a value
it names move.

A read the run ordered against and did not rotate SHALL NOT be possible. A consumer ordered after a
provider it reads is a consumer that opens what that provider published, so a rotation the run does
not carry through to it leaves a process holding the previous bytes for as long as it lives, with
nothing in the run saying so - which is the one failure the restart step exists to remove and the one
an operator cannot see.

The reach of a read SHALL decide how many providers a consumer waits for and SHALL decide nothing
else. A run SHALL NOT answer one question from one shape of a resolved read and the other question
from another.

#### Scenario: A set valued read of a secret rotates its consumer

- **WHEN** a consumer declares a read with a reach of every entry that provides the capability, one
  provider's export is backed by a generated file, and that value's bytes move in the value source
- **THEN** the run SHALL restart that consumer's units on the machine it is placed on
- **AND** the restart SHALL be reported naming the entry, the machine and the value
- **AND** the same read SHALL have ordered that consumer after every provider of the set

#### Scenario: A reader of a set valued read is restarted after every activation

- **WHEN** a run both activates entries and rotates a value a set-valued read names
- **THEN** every restart the rotation causes SHALL follow every activation of the run
- **AND** a reading consumer whose units are not running SHALL NOT be started by that step
- **AND** a run in which no value's bytes moved SHALL take no such step

### Requirement: A resolved read the command cannot read is a refusal

A resolved read the command does not recognise SHALL be a refusal naming the consumer and the slot,
whatever kind of value it is. The refusal SHALL NOT be reserved for a read the command can look
inside: a read recorded as a bare provider name, as a number or as a list is as unreadable as a
record whose fields the command does not know, and the run cannot tell from any of them which
provider a consumer waits for.

Contributing no edge SHALL NOT be the answer to a shape the command does not recognise. A read that
silently contributes nothing reads as a consumer with no provider, so the consumer is activated
before the entry it reads and the run reports nothing about it, which is exactly the outcome the
refusal exists to prevent.

The refusal SHALL be the command's own, of the same kind as every other refusal it makes, and SHALL
be made before the first machine is dialled. A read the command does recognise and whose provider the
run is not applying SHALL remain an announcement rather than a refusal, so an unreadable record and a
restricted selection stay two different reports.

#### Scenario: A delivered read in neither shape is refused

- **WHEN** a plan records a consumer's resolved read in neither the shape that names one provider nor
  the shape that names every provider of a set
- **THEN** the command SHALL refuse naming the consumer and the slot
- **AND** the refusal SHALL be made before the first machine is dialled
- **AND** the consumer SHALL NOT have been ordered as an entry that reads nothing

#### Scenario: A resolved read that is not a record is refused

- **WHEN** a consumer's resolved read is recorded as a bare provider key rather than as a record
- **THEN** the command SHALL refuse naming the consumer and the slot
- **AND** the refusal SHALL be reported the way every other refusal of the command is
- **AND** the read SHALL NOT be read as zero edges and passed over

### Requirement: An artifact the command copies is inside the build it read

Every artifact path a deployment record states SHALL resolve inside the build that record was read
from. A stated path that resolves above the build root, and one stated as an absolute location
outside it, SHALL each be a refusal naming the entry and the path stated, made before the first
machine is dialled.

Containment SHALL be decided by where the path resolves and not by what is there: a path outside the
build SHALL be refused whether or not anything exists at it, and whether it is spelled relative to
the build or absolute. The path a copy step puts on a machine is the path the activation names there,
so a path outside the build copies bytes the build did not produce onto a machine and activates them
under the name of an entry the operator asked for.

#### Scenario: An artifact path that leaves the build is refused

- **WHEN** a deployment record states an artifact path that resolves above the build it was read
  from, or an absolute path outside that build
- **THEN** the command SHALL refuse naming the entry and the path stated
- **AND** no machine SHALL have been dialled
- **AND** both spellings of such a path SHALL be refused alike

#### Scenario: An artifact path below the build is accepted

- **WHEN** a record states an artifact path that resolves inside the build
- **THEN** the command SHALL read it and SHALL NOT refuse the deployment
- **AND** the path the copy step names SHALL be the path the activation names on the machine

### Requirement: A value source is measured to the leaves of a value's own directory

The measurement of a value source SHALL reach every file under the directory of a value entry the
deployment delivers, at any depth, and every file it reaches that the value does not declare SHALL be
named. A file nested below a subdirectory of such a directory SHALL be measured the way one lying
beside the declared files is: the operator's fix is the list of what to remove, and a measurement that
stops at the first level leaves bytes inside a value's own directory that nothing in the deployment
claims and nothing in the run names.

A file SHALL be reached through a subdirectory whatever that subdirectory is, including one that is a
link to a directory elsewhere, and SHALL be named by its path below the value's own directory rather
than by where its bytes happen to live, so an operator is told which file to remove. A file under no
delivered value entry's directory SHALL remain a claim about no value and SHALL be left alone.

#### Scenario: Every undeclared file inside a value's directory is named

- **WHEN** a delivered value's own directory holds, below a subdirectory of it, a file the value does
  not declare
- **THEN** the command SHALL refuse, naming that file by its path below the value's directory
- **AND** no machine SHALL have been dialled
- **AND** the refusal SHALL name every such file it reached rather than the first of them

### Requirement: A refusal names the record the command read, never the vector it built

What a refusal names SHALL come from the record the command read. The entry, the machine and the
value a failed step belongs to SHALL be taken from the plan and the deployment record, and SHALL NOT
be recovered from the argument vector the command built to address that step.

A vector carries more than the destination: it carries the connection options the caller handed the
command, whose values may spell anything, and for a value write it carries the script that reads the
value's bytes. A refusal that reads its own vector back therefore reports whatever a word of it
happens to look like, which is how a caller's own transport option can be reported as the machine a
step failed against.

Where the command nevertheless has to answer which machine a vector addresses, it SHALL answer the
destination the command itself placed in that vector and no other word of it, whatever an option's
value spells.

#### Scenario: A refusal names the machine and not an ssh option

- **WHEN** a step fails against a machine and the caller's own connection options carry a value that
  spells a destination
- **THEN** the refusal SHALL name the machine the deployment record states for that entry
- **AND** SHALL name no other word of the vector the step was addressed by
- **AND** SHALL carry what the machine printed rather than the call that raised
