<!--
A delta against `openspec/specs/operator/apply-command/spec.md`, which owns the steps a run takes,
the refusals it makes before it dials and what it does on a machine. The base text is there and
this file restates only the blocks that change.

One ADDED requirement, `The run connects to the machine the deployment named`, and two MODIFIED,
each copied whole with one amendment.

`What the command does on a machine` is MODIFIED in its third paragraph alone. Its last sentence
reads "An option the caller stated for the connection SHALL win over the command's own value for
the same option", which is right for the three bounds on silence and is the hole for the two
options that decide which machine the run is talking to. The amendment names the exception and
says why it is a refusal rather than an override.

`The command refuses before it dials` is MODIFIED in its first sentence alone: a refusal is now
made from the connection options the invocation was given as well as from the plan, the deployment
record and the value source, and that sentence is what makes a dry run comparable to a real one
line by line.

Nothing else moves. `One command applies a whole deployment`, `The bytes of a generated value come
from outside the plan`, `A restriction bounds the machines a run contacts`, `The value source is
measured where the deployment declares files`, `The command refuses a deployment record it cannot
read` and `A build reports the table the deployment holds` are unchanged and not restated.

`retire-an-entry-a-build-no-longer-names` deltas this same capability with ADDED requirements only
and cites the two blocks below as preconditions; its retirement step goes through the channel this
requirement owns and states no rule of its own about the options.

The conditions. `cli/remote.py:39-48` is the bound on silence and `:262-273` is where it is
appended to the caller's `NIX_SSHOPTS`, "appended so the caller's own value wins". `:276-296` is
the one option string and the one environment a whole run uses, and `:316-323` and `:299-313` put
that string into every `ssh` and hand the same variable to every `nix copy`. `cli/apply.py:254` and
`cli/report.py:116,250` are the three callers, and none of them prints the string.
`tests/e2e/delivery.py:332-347` sends `StrictHostKeyChecking=no` and
`UserKnownHostsFile=/dev/null` through that variable for a throwaway guest, and `:350-359` is the
environment the operator's own command is handed inside a cluster. `cli/manifest.py:219-238` reads
a placed entry's address off the deployment record and `:241-257` reads a value machine's address
off the plan's own machine record, which are the two places an identity has to arrive through.
`cli/apply.py:182-207` is the channel a dry run replaces, and it replaces the channel and nothing
else.

`planner/machine-platform` owns the field and its grammar, so this capability states nothing about
what an identity looks like; a line the planner refused is recorded nowhere, so this command is
never handed one.
-->

## ADDED Requirements

### Requirement: The run connects to the machine the deployment named

Where the deployment states the identity a machine's host presents, every step the run takes
against that machine SHALL be made over a connection verified against that identity, and the run
SHALL fail the step rather than continue where the machine presents another. The verification SHALL
be a function of the deployment alone: the run SHALL derive it from the identity the deployment
stated and SHALL NOT take it from a file the invoking account happens to hold or from an identity a
machine offered during the run.

This SHALL hold for every kind of step, whichever program performs it: writing the bytes of a
generated value, copying an artifact, activating an entry, asking a machine what it holds, and
returning an entry to its previous generation. One machine SHALL be reached through one set of
connection options for the whole run, so that no step of it is weaker than another.

An option the invocation's environment carries that would remove that verification SHALL be a
refusal naming the machine and the option, made before the first machine is contacted, and SHALL
NOT be silently overridden. The command SHALL NOT be able to override it: the options the command
adds are appended to the caller's own so that the caller wins, which is what the bound on silence
requires, and appending cannot undo an option that has already been given. Refusing is therefore
the only answer that is both honest and effective. The refusal SHALL be per machine: an invocation
carrying such an option SHALL be refused where the run would dial a machine that states an
identity, and SHALL NOT be refused where no machine of the run states one.

The refusal SHALL be about the two option names that decide host verification, whichever spelling
the invocation's option set states them in. It SHALL NOT be about a connection configuration file
the invocation names: the command SHALL NOT read such a file, and SHALL NOT refuse a run for
naming one. That boundary is stated rather than left implicit, because a configuration file can
set either of the two settings and a reader must not take the refusal for a guarantee it is not.
Three reasons it is the right boundary. A command-line option beats a configuration file in the
protocol's own precedence, so the command's own verification options win over anything such a file
says, and the only channel that can precede them is the option set the invocation hands the
command. Reading the file to find out what it sets would make the command a parser of another
program's configuration language, including its conditional blocks and its includes, and a run
would then refuse or proceed on the command's reading of a file rather than on the protocol's.
And the option that names a file is load-bearing in the other direction: the one value this
repository's own harness states for it disables user configuration entirely, which is the safe
direction, and an operator's file is where their own jump host, login and key legitimately live.

A machine for which the deployment states no identity SHALL be contacted exactly as it is contacted
today, with the options the caller stated and the command's bounds appended, so that every
deployment that applies before this requirement still applies after it.

The run SHALL report, before its first step and once per machine it will contact, the machine, the
address it will dial and which of the two postures that machine is contacted under: the identity
pinned, named so that an operator can compare it with what the machine itself publishes, or that
the deployment states none and the caller's own options decide. An operator reading their own
output SHALL be able to tell a verified run from an unverified one without knowing what their
environment held.

The report and every refusal above SHALL be made from the plan, the deployment record, the value
source and the connection options, all of which are read before the first dial. A run asked what it
would do SHALL print the same report and make the same refusals as the run that acts, so the two
remain comparable line by line.

#### Scenario: A machine that states a host key is dialled pinned to it

- **WHEN** a run applies an entry on a machine whose record states the identity its host presents
- **THEN** every step against that machine SHALL be made over a connection verified against that
  identity
- **AND** the verification SHALL be derived from the deployment rather than from a file the invoking
  account holds

#### Scenario: Every step against one machine uses one option set

- **WHEN** a run writes a value, copies an artifact and activates an entry on one machine that
  states an identity
- **THEN** all three steps SHALL be made under one set of connection options
- **AND** the step that reaches the machine through another program SHALL be verified the same way
  as the steps that reach it directly

#### Scenario: An inherited option that would disable the pinning is refused

- **WHEN** the invocation's environment carries a connection option that would remove host
  verification, and the run would dial a machine whose record states an identity
- **THEN** the command SHALL refuse naming that machine and that option
- **AND** no machine SHALL have been dialled, including the machines that state no identity
- **AND** the option SHALL NOT have been overridden silently

#### Scenario: An inherited option reaches a run whose machines state no identity

- **WHEN** the invocation's environment carries the same option and no machine the run would dial
  states an identity
- **THEN** the command SHALL make no refusal about it
- **AND** the run SHALL proceed with the options the caller stated

#### Scenario: A machine that states no host key is dialled as before

- **WHEN** a run applies an entry on a machine whose record states no identity
- **THEN** the steps against it SHALL be made with the options the caller stated and the command's
  own bounds appended
- **AND** the run SHALL succeed wherever it succeeded before the deployment could state an identity

#### Scenario: The run reports what it connected with before its first step

- **WHEN** a run contacts machines of which one states an identity and one does not
- **THEN** the report SHALL carry one line per machine, before the first step line
- **AND** the line for the machine that states an identity SHALL name it
- **AND** the line for the machine that states none SHALL say that the caller's own options decide

#### Scenario: A dry run reports the connection its real run would make

- **WHEN** an applicable deployment is applied in the mode that asks rather than acts
- **THEN** the connection lines SHALL be the lines the same run without that mode prints
- **AND** a refusal about an inherited option SHALL be made identically in both modes
- **AND** no machine SHALL have been dialled

#### Scenario: A pinned run reaches a machine that presents the stated key

- **WHEN** a run applies a deployment stating, for a machine, the identity that machine's host
  actually presents
- **THEN** every step of the run against it SHALL succeed
- **AND** the run SHALL have verified the machine against the stated identity rather than against
  anything the invoking account held beforehand

#### Scenario: A machine presenting another key ends the step

- **WHEN** a run applies a deployment stating, for a machine, an identity other than the one that
  machine's host presents
- **THEN** the first step against that machine SHALL fail
- **AND** the failure SHALL name the machine and what the connection said
- **AND** no byte of any value SHALL have been written there

## MODIFIED Requirements

### Requirement: The command refuses before it dials

Every refusal the command can make from the plan, the deployment record, the value source and the
connection options the invocation was given SHALL happen before the first machine is contacted,
and SHALL name the entry, the field and the value at fault. A
deployment the planner reports as inapplicable SHALL NOT be applied, and an entry the caller names
that the plan does not carry SHALL be refused naming the entries that exist.

An apply SHALL be askable for what it would do without doing it. Asked that way, the command SHALL
make every refusal above, SHALL print the steps it would take in the order it would take them, and
SHALL contact no machine. The steps it prints SHALL be the steps a real run prints, so the two are
comparable line by line. It SHALL be a mode of applying rather than a separate subcommand, and SHALL
honour the same restriction, value source and connection options a real run is given.

Asking what a run would do SHALL NOT report what a machine currently holds. That is a question for
the machine, and answering it is a dial.

#### Scenario: A deployment the planner refuses is not applied

- **WHEN** the command is asked to apply a deployment whose diagnostics carry an error
- **THEN** it SHALL refuse with the rendered diagnostics table
- **AND** no machine SHALL have been dialled

#### Scenario: An entry named on the command line is not in the plan

- **WHEN** the caller restricts the command to an entry the plan does not carry
- **THEN** it SHALL refuse naming the entry given and the entries the plan carries
- **AND** no machine SHALL have been dialled

#### Scenario: A run is asked what it would do

- **WHEN** an applicable deployment is applied in the mode that asks rather than acts
- **THEN** the command SHALL print the value writes, the copies and the activations it would
  perform, in the order it would perform them
- **AND** those lines SHALL be the lines the same run without that mode prints
- **AND** no machine SHALL have been dialled

#### Scenario: A dry run of a deployment the planner refuses

- **WHEN** the mode that asks rather than acts is given a deployment, a restriction or a value
  source the command would refuse
- **THEN** it SHALL refuse exactly as a real run refuses, with the same message
- **AND** SHALL print no step

### Requirement: What the command does on a machine

On a machine the command SHALL use what is already there: the machine's own service manager, the
endpoint's own binary for an artifact the endpoint activates, and the artifact's own attach script
for a portable-service image. It SHALL report what each machine reported. It SHALL be able to ask a
machine what it holds and to return one entry to its previous generation.

A step that the machine refuses SHALL be reported as the command's own refusal, naming the entry,
the machine and what the machine printed, and SHALL NOT reach the operator as an unhandled failure
of the program the command ran.

Reaching a machine SHALL bound silence and SHALL NOT bound work: the command SHALL ask no question
of a terminal nobody is watching, SHALL give up on a machine that does not answer a connection, and
SHALL place no limit on how long a step that keeps making progress may take. An option the caller
stated for the connection SHALL win over the command's own value for the same option, except for an
option deciding whether the machine's identity is verified: the deployment owns that, and an option
the caller stated for it SHALL be a refusal rather than a value the command overrides, because the
command's own options are appended so that the caller wins and an appended option cannot undo one
already given.

#### Scenario: An image entry is attached by the command

- **WHEN** the command applies an entry realised as a portable-service image
- **THEN** the attachment SHALL be performed by the script the artifact carries
- **AND** every unit the attachment names SHALL be running on the machine afterwards

#### Scenario: The command rolls one entry back

- **WHEN** the command is asked to roll one entry back after a second generation was applied
- **THEN** the machine SHALL run the previous generation again
- **AND** the command SHALL report the generation it came from

#### Scenario: The command reports what a machine holds

- **WHEN** the command is asked for the status of an applied deployment
- **THEN** it SHALL report, per entry, what the machine's own endpoint reports for it
- **AND** an entry the machine does not hold SHALL be reported as absent rather than as an error

#### Scenario: A step that fails names the machine and what it said

- **WHEN** a machine refuses a step of a run
- **THEN** the command SHALL report a failure naming the entry, the machine and the machine's output
- **AND** the run SHALL exit non-zero
- **AND** no traceback of the program the command ran SHALL reach the operator

#### Scenario: An unreachable machine is refused without a prompt

- **WHEN** a step is taken against an address that answers nothing
- **THEN** the connection SHALL be given up on rather than waited on indefinitely
- **AND** the command SHALL ask nothing of a terminal
- **AND** a connection option the caller stated SHALL be the one used
