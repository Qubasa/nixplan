# operator/apply-command Specification

## Purpose
Defines the one command that puts a built deployment on the machines it names, so that the steps
between a plan and a running service are a program with a contract rather than a script each caller
writes. It owns the order the steps happen in, where the bytes of a generated value come from, what is
refused before a machine is dialled, and what the command does on a machine it reaches.

## Requirements

### Requirement: One command applies a whole deployment

Applying a deployment SHALL be one command over a built deployment. It SHALL derive the order of its
steps from the plan and SHALL NOT require the caller to state it: an artifact SHALL be on its
machine before it is activated there, every generated value a machine receives SHALL be written
before any unit that may read it is activated, and an entry that provides a capability SHALL be
activated before an entry that reads it.

The provider-before-consumer edges SHALL be taken from the reads the plan resolved, not from the key
provenance the plan records for other purposes. Every read the plan resolved SHALL contribute its
edges whatever its reach: a read of one entry and a read of a set of entries SHALL each be ordered
against, and a consumer of a set-valued read SHALL be activated after every entry in that set. No
shape a resolved read is recorded in SHALL leave a provider unordered.

Where the edges form a cycle - which two instances wiring each other legitimately do - the command
SHALL break it deterministically and SHALL report the edge it broke, rather than refusing a
deployment the planner accepted. An edge the command reports as contradicted SHALL lie on a cycle:
the provider of that edge SHALL be reachable from its consumer through the reads of the entries the
run has still to apply. An edge on no cycle SHALL be satisfied by the order the command walks.

Each step SHALL be announced before it is attempted, so that the last step line a run printed names
the step that was running when the run ended. This SHALL hold for every step the command takes
against a machine, whichever subcommand takes it.

#### Scenario: An entry is copied before it is activated

- **WHEN** the command applies one entry
- **THEN** the copy of its artifact to its machine SHALL precede the activation on that machine
- **AND** the address dialled SHALL be the one the plan records for that machine

#### Scenario: A provider is applied before its consumer

- **WHEN** one entry reads a capability another provides
- **THEN** the provider SHALL be activated before the consumer
- **AND** the order SHALL come from the plan rather than from the order the caller named the entries
  in

#### Scenario: An entry reading a set of providers follows all of them

- **WHEN** one entry reads a capability with a reach of every entry that provides it
- **THEN** every entry in that set SHALL be activated before the entry that reads it
- **AND** the edges SHALL be taken from the same resolved read whatever shape the plan records it in
- **AND** an entry the run does not apply SHALL contribute no edge

#### Scenario: Two entries each read the other's capability

- **WHEN** two entries each read a capability the other provides
- **THEN** the command SHALL apply both
- **AND** SHALL report which edge it ordered against
- **AND** SHALL NOT refuse the deployment

#### Scenario: A mutual pair is reported however each side reads the other

- **WHEN** two entries read each other and one of the two reads the other as a set of providers
- **THEN** the command SHALL report the edge it ordered against
- **AND** SHALL NOT present the pair as an order it satisfied

#### Scenario: An entry off the cycle keeps its order

- **WHEN** one entry reads a capability provided by one of two entries that read each other
- **THEN** the command SHALL activate the mutual pair before the entry that reads into it
- **AND** the only edge it reports as contradicted SHALL be one between the two entries of the pair
- **AND** the read the third entry declared SHALL be satisfied by the order walked

#### Scenario: A step is announced before it is attempted

- **WHEN** the command takes a step against a machine
- **THEN** the line naming that step SHALL be printed before the step is attempted
- **AND** a run that ends during a step SHALL have that step's line as the last step it named

#### Scenario: A step the machine refuses is named by the run that took it

- **WHEN** a step fails on the machine, on any subcommand that takes a step
- **THEN** the line naming that step SHALL already have been printed
- **AND** the failure SHALL name the machine and the step rather than the call that raised

### Requirement: The bytes of a generated value come from outside the plan

The command SHALL take the bytes of a generated value from a source the operator names, never from
the plan or an artifact. For each value entry it SHALL write each declared file to every machine the
entry's delivery set names, at the path the entry records, outside the store, readable only by the
user the units run as. A value whose delivery set is empty SHALL be written nowhere.

The source SHALL be checked against the plan before anything is dialled: a file the plan names that
the source does not hold, and a file the source holds that the plan does not name, SHALL both be
refusals naming the entry and the file.

#### Scenario: A value the plan names has no bytes in the source

- **WHEN** the command is given a value source missing a file the plan declares
- **THEN** it SHALL refuse naming the value entry and the file
- **AND** no machine SHALL have been dialled

#### Scenario: A value source carries bytes the plan does not name

- **WHEN** the value source holds a file no value entry of the plan declares
- **THEN** the command SHALL refuse naming the file
- **AND** SHALL NOT write it to any machine

#### Scenario: A secret is applied from the operator's value source

- **WHEN** a deployment whose consumer reads a secret export is applied with a value source holding
  that secret
- **THEN** the file SHALL be present on each machine of the delivery set and on no other machine
- **AND** the consuming unit SHALL authenticate to the provider with it
- **AND** the bytes SHALL appear in no artifact the command built

### Requirement: The command refuses before it dials

Every refusal the command can make from the plan and the deployment record alone SHALL happen before
the first machine is contacted, and SHALL name the entry, the field and the value at fault. A
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
stated for the connection SHALL win over the command's own value for the same option.

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

### Requirement: A restriction bounds the machines a run contacts

A restriction on which entries a run applies SHALL bound which machines the run contacts. The
machines contacted SHALL be the machines of the entries selected, plus the delivery machines of a
value entry the restriction names directly, and no others - a machine that receives a value only
because some unselected entry reads it SHALL NOT be dialled.

#### Scenario: A restricted run contacts only the machines of the entries it applies

- **WHEN** a run is restricted to one entry of a deployment placed on two machines, and a value the
  entry's machine receives is delivered to both
- **THEN** the run SHALL contact the entry's own machine
- **AND** SHALL open no connection to the other machine

#### Scenario: A restriction that names a value entry reaches its delivery set

- **WHEN** a run is restricted to a value entry rather than a placed entry
- **THEN** every machine of that value's delivery set SHALL receive its files
- **AND** no entry SHALL be activated

### Requirement: The value source is measured where the deployment declares files

A file of the value source is a claim about a value only where it lies under the directory of a
value entry the deployment delivers. The refusal of a file the plan does not name, which "The bytes
of a generated value come from outside the plan" states, SHALL be measured over those directories
and SHALL NOT be measured over the rest of the source. Every file so found SHALL be named, not the
first of them.

#### Scenario: A file outside every value's own directory is left alone

- **WHEN** the value source holds a file that lies under no delivered value entry's directory
- **THEN** the command SHALL apply the deployment
- **AND** SHALL write that file to no machine

#### Scenario: Two undeclared files are both named

- **WHEN** a delivered value's directory holds two files the value does not declare
- **THEN** the refusal SHALL name both
- **AND** no machine SHALL have been dialled

### Requirement: The command refuses a deployment record it cannot read

A deployment record states the version of its own shape and the store its artifact paths live in.
The command SHALL read both and SHALL refuse a record whose version it does not implement, naming
the version read and the version it implements, and a record whose store is not the store it runs
against, naming both. A record carrying no table of entries SHALL be refused as a record it cannot
read, never read as a deployment that places nothing.

A target naming a path under the store directory that does not exist SHALL be refused as a build
that was collected, naming the path, rather than reported as a reference that does not build.

An entry whose machine declares no address SHALL NOT make a record unreadable: the reading SHALL
carry that absence, and the refusal SHALL stay at the point where the machine would be dialled.

#### Scenario: A record states a version the command does not implement

- **WHEN** the command is given a deployment record whose stated version is not the one it
  implements
- **THEN** it SHALL refuse naming both versions
- **AND** no machine SHALL have been dialled

#### Scenario: A record names a store the command does not run against

- **WHEN** the record states a store directory other than the one the command runs against
- **THEN** it SHALL refuse naming both store directories
- **AND** no artifact SHALL be copied

#### Scenario: A record carries no table of entries

- **WHEN** the record holds no table of placed entries under the name the shape gives it
- **THEN** the command SHALL refuse naming the record and the table
- **AND** SHALL NOT report a run that applied nothing as successful

#### Scenario: A target that was collected is named as collected

- **WHEN** the target names a path under the store directory that is no longer there
- **THEN** the command SHALL refuse naming that path as a build that was collected
- **AND** the refusal SHALL tell the operator to build the reference again

#### Scenario: A record carrying an entry with no address is read

- **WHEN** the record places an entry on a machine whose registry record declares no address
- **THEN** reading the record SHALL succeed
- **AND** the refusal SHALL come when that entry's machine would be dialled, naming the entry and
  the machine

### Requirement: A build reports the table the deployment holds

Reporting what a built deployment holds SHALL include the diagnostics the build wrote, rendered as
the planner renders them, beside the entries and the values. A deployment whose rows are warnings
SHALL be reported with those warnings and SHALL be reported as successful; a deployment whose rows
carry an error SHALL be reported with the rendered table and SHALL exit non-zero. The rows are the
ones the tree already carries, because "An inapplicable deployment is not built" in
`report-every-refusal-as-a-row` requires a build to publish its plan and its rows whether or not any
entry was realised, and what the command prints is that refusal rather than a second one of its own.

#### Scenario: A build of a deployment carrying warnings prints them

- **WHEN** a built deployment whose diagnostics hold warnings and no error is reported
- **THEN** every warning row SHALL appear in the output beside the entries and the values
- **AND** the report SHALL exit zero

#### Scenario: A build of a deployment carrying an error prints the table and refuses

- **WHEN** a built deployment whose diagnostics hold an error row is reported
- **THEN** the rendered table SHALL be the output
- **AND** the report SHALL exit non-zero

### Requirement: A run that broke is finished by a second run

A run SHALL stop at the first step a machine refuses and SHALL attempt no step after it, so that a
broken run leaves one boundary rather than a set of them. A second run over the same built
deployment and the same value source SHALL be the recovery: a step whose effect is already on its
machine SHALL be taken again with no effect on that machine, and the command SHALL NOT re-run an
attachment for an image the machine already holds attached at that path.

#### Scenario: The run stops at the step that broke

- **WHEN** a machine refuses a step of a run that has further entries to apply
- **THEN** no step after the failed one SHALL be attempted
- **AND** the steps taken before it SHALL be the ones the log named

#### Scenario: An image the machine already holds attached is not attached twice

- **WHEN** a run applies an image entry the machine already holds attached at the path the record
  names
- **THEN** the artifact's attach script SHALL NOT be run again
- **AND** the entry SHALL be reported as already attached
- **AND** the run SHALL continue with the entries after it

### Requirement: Every refusal a run can make without a machine precedes the first machine

A refusal the command can make from the build and its own arguments alone SHALL be made before the
first machine is dialled, so that a deployment the command will not finish changes nothing. This
SHALL cover every artifact the run will need on any machine, not only the ones the first machine
needs: a record the command cannot read, an artifact the build does not name, and a file inside the
build that is malformed SHALL each be refused before the run mutates a machine.

A malformed file inside a built directory SHALL be a refusal naming the file, never an unhandled
error from the reader.

#### Scenario: An artifact the run needs later is missing

- **WHEN** a run will need an artifact for an entry on a machine after the first
- **AND** the build does not name that artifact
- **THEN** the command SHALL refuse before it dials the first machine
- **AND** no value SHALL have been written and no artifact copied

#### Scenario: A file inside the build is malformed

- **WHEN** a file the command reads from a built directory is not the shape the command needs
- **THEN** the command SHALL refuse naming that file
- **AND** the refusal SHALL be the command's own, not the reader's error

### Requirement: A cycle is broken at a component and reported as one

Where the reads the plan resolved form a cycle, the entry the command orders first among the
unorderable ones SHALL be a member of a strong component of the remaining read graph that no entry
outside it reads into. The edges the order contradicts SHALL be edges inside that component, and no
edge between two entries that are not on one cycle SHALL be contradicted.

The report SHALL name the cycle as a cycle: the entries of the component whose edge was contradicted
SHALL be named together, so that an operator can tell two entries that read each other from a
provider that an earlier decision left behind. Naming the contradicted edge alone SHALL NOT be the
whole report.

Entries within one component SHALL be ordered deterministically by plan key, and components SHALL be
walked in the dependency order between them, so that one deployment always walks one way.

#### Scenario: Two entries that read each other are named as one cycle

- **WHEN** two entries each read a capability the other provides
- **THEN** the report SHALL name both entries as a cycle the order was broken at
- **AND** SHALL name the edge or edges the order contradicted
- **AND** the deployment SHALL be applied

#### Scenario: An entry reading into a cycle is not contradicted

- **WHEN** one entry reads a capability provided by one of two entries that read each other
- **THEN** the contradicted edges SHALL all lie between the two entries that read each other
- **AND** the read the third entry declared SHALL be satisfied by the order walked
- **AND** the third entry SHALL NOT be named as part of the cycle

#### Scenario: Two separate cycles are two reports

- **WHEN** a deployment carries two disjoint pairs of entries that read each other
- **THEN** each pair SHALL be named as its own cycle
- **AND** no entry SHALL be named in a cycle it is not on

### Requirement: The order costs no more than the graph it is read from

Computing the order SHALL cost no more than the size of the read graph: the entries to apply plus the
resolved reads between them. The command SHALL NOT rescan the entries still to apply once per entry
applied, and SHALL NOT recompute a reachability question once per candidate entry.

A deployment an operator can build SHALL be a deployment the command can order without a
super-linear cost, so that ordering is never the reason a large fleet cannot be applied.

#### Scenario: A large deployment is ordered without a per-entry rescan

- **WHEN** the command orders a deployment of a thousand placed entries whose reads form a chain
- **THEN** the order SHALL be produced
- **AND** the cost of producing it SHALL grow no faster than the entries and the reads between them

#### Scenario: A large deployment carrying a cycle is ordered at the same cost

- **WHEN** the command orders a deployment of a thousand placed entries in which one pair reads each
  other
- **THEN** the order SHALL be produced with that pair's edge contradicted
- **AND** the cost SHALL be of the same order as for the same deployment without the cycle

### Requirement: An order the command cannot compute is a refusal

If the command reaches a state in which no entry can be ordered, it SHALL refuse naming the entries
it could not order and the reads between them. The refusal SHALL be the command's own, of the same
kind as every other refusal it makes, and SHALL NOT be an unhandled error or a traceback.

No state of the command SHALL depend for its correctness on an argument stated only in prose: where an
invariant decides which entry is ordered next, its violation SHALL be a refusal rather than an
unhandled error.

#### Scenario: No entry can be ordered

- **WHEN** the command reaches a state in which no entry of those remaining can be ordered
- **THEN** it SHALL refuse naming those entries and the reads between them
- **AND** the refusal SHALL be reported the way every other refusal of the command is
- **AND** no machine SHALL have been dialled after the refusal

### Requirement: A read the run will not satisfy is announced

A read whose provider the run is not applying SHALL be announced, naming the reading entry and the
provider it reads. The announcement SHALL be printed where the report of a contradicted edge is
printed, before the first machine is dialled.

Such a read SHALL remain no ordering constraint: an entry the run does not apply cannot be ordered,
so the run SHALL apply the selection it was given. What changes is that the run states which read it
is not honouring, so that a restricted apply and a broken cycle are equally visible.

#### Scenario: A restricted run activates a consumer without its provider

- **WHEN** a run is restricted to a selection that holds a consumer and not a provider it reads
- **THEN** the run SHALL announce that read, naming the consumer and the provider
- **AND** SHALL apply the consumer
- **AND** the announcement SHALL precede the first machine dialled

#### Scenario: A full run announces nothing about unapplied providers

- **WHEN** a run applies every placed entry of a deployment
- **THEN** no read SHALL be announced as unsatisfied
- **AND** the only reads reported SHALL be the edges a cycle made the order contradict

### Requirement: A value is written at the ownership and mode its record states

The step that writes a value on a machine SHALL set the owner, the group and the mode the value's
record states, and SHALL take all three from the record rather than from a literal of its own.

The file SHALL never exist at a mode or an ownership wider than the recorded one, not even for the
length of the write: the write SHALL create the file at the recorded mode before its first byte
lands, and SHALL NOT depend on the environment's umask for its answer. A write that is interrupted
SHALL leave either the previous file or no file, never a readable fragment at a wider mode.

Where the recorded owner or group does not exist on the machine, the step SHALL fail as the command's
own refusal naming the value, the machine and the account, rather than leaving the file owned by the
writing login.

#### Scenario: A value delivered to an account

- **WHEN** a value's record names an owner, a group and a mode
- **THEN** the machine SHALL hold the file with that owner, that group and that mode
- **AND** the step SHALL have set all three

#### Scenario: A value delivered with the defaults

- **WHEN** a value's record carries the default ownership and mode
- **THEN** the machine SHALL hold the file exactly as the command delivered it before this change

#### Scenario: An interrupted write

- **WHEN** the write of a value is interrupted after the file is created and before its bytes are
  complete
- **THEN** no file SHALL exist at a mode wider than the recorded one
- **AND** the machine SHALL hold either the previous file or none

#### Scenario: An account the machine does not have

- **WHEN** a value's record names an owner no account on the machine matches
- **THEN** the command SHALL refuse naming the value, the machine and the account
- **AND** the file SHALL NOT be left owned by the login the command used

### Requirement: A re-apply restores a value's ownership and mode

Every apply that delivers a value SHALL set its ownership and mode, whether or not the bytes moved.
A value edited on the machine - its mode widened, its owner changed - SHALL be returned to what the
record states by the next apply, so that what a machine holds is decided by the deployment and not by
whatever last touched the file.

The report SHALL name the write the way it names every other step, so an operator can see that the
value was written.

#### Scenario: A mode widened on the machine

- **WHEN** a value's mode is widened on a machine and the deployment is applied again with unchanged
  bytes
- **THEN** the file SHALL carry the recorded mode afterwards
- **AND** the step SHALL have been reported

#### Scenario: An owner changed on the machine

- **WHEN** a value's owner is changed on a machine and the deployment is applied again
- **THEN** the file SHALL carry the recorded owner afterwards

### Requirement: No entry is skipped for being already present

The command SHALL activate every entry of the selection it was given, and SHALL NOT skip one because
the machine already holds it. Whether an entry's activation is a change SHALL be the activation's own
answer, reported by the step, rather than a question the command decides before running it.

An activation SHALL therefore be idempotent: applying an unchanged deployment twice SHALL leave the
machine as it was after the first apply, and the second run's report SHALL say that nothing changed
rather than that nothing was attempted.

#### Scenario: An unchanged deployment applied twice

- **WHEN** a deployment is applied twice with nothing changed between the runs
- **THEN** both runs SHALL report an activation step for every entry
- **AND** the machine SHALL hold the same units, the same images and the same configuration bytes
  after the second run
- **AND** no unit's main process SHALL have been replaced by the second run

#### Scenario: An entry whose configuration bytes changed

- **WHEN** a deployment is applied, one entry's configuration file is edited, and the deployment is
  built and applied again
- **THEN** the machine SHALL hold the new bytes at the declared path
- **AND** the step SHALL report that the file changed

#### Scenario: An entry whose artifact identity changed

- **WHEN** a deployment is applied, an entry's artifact identity moves, and the deployment is applied
  again
- **THEN** the machine SHALL run the new artifact
- **AND** SHALL NOT hold the previous one
- **AND** the step SHALL report the replacement

### Requirement: A value write says whether the bytes moved

The step that writes a value SHALL report whether the bytes on the machine changed, and SHALL make
that comparison on the machine rather than from a record of what a previous run wrote: the command
holds no state between runs, and the only authority on what a machine holds is the machine.

The comparison SHALL NOT put the value's bytes anywhere a second process can read them, and SHALL NOT
print them: what is reported is that the file changed, never what it changed to.

#### Scenario: A value whose bytes are unchanged

- **WHEN** a value is written whose bytes on the machine are already those bytes
- **THEN** the step SHALL report that the value was unchanged
- **AND** the file's ownership and mode SHALL still be set

#### Scenario: A value whose bytes moved

- **WHEN** a value is written whose bytes on the machine differ
- **THEN** the step SHALL report that the value changed
- **AND** no report line SHALL contain the value's bytes

### Requirement: A changed value restarts the entries that read it

After every value has been written and before the run ends, the command SHALL restart the units of
every entry that declared a read of a value whose bytes moved, on the machine that entry is placed
on. A unit that is not running SHALL NOT be started by this step: the activation is what decides
whether a unit runs, and this step only replaces a process holding bytes that are no longer current.

The entries restarted SHALL be derived from the reads the plan resolved, the same source the
activation order is derived from. A value whose bytes did not move SHALL cause no restart, and a run
that wrote no value SHALL contain no such step.

Each restart SHALL be its own reported step naming the entry, the machine and the value that caused
it, so that an operator reading the log can tell a restart caused by a rotation from one caused by a
new artifact.

#### Scenario: A rotated secret restarts its reader

- **WHEN** a value's bytes are changed in the value source and the deployment is applied
- **THEN** the units of every entry that declared a read of that value SHALL be restarted
- **AND** each restart SHALL be reported naming the entry, the machine and the value
- **AND** the reading process SHALL be a new process afterwards

#### Scenario: A reader that is not running is not started

- **WHEN** a value's bytes change and one reading entry's unit is stopped on its machine
- **THEN** that unit SHALL NOT be started by the restart step
- **AND** the run SHALL still report the restart step for the entries whose units were running

#### Scenario: An unchanged value restarts nothing

- **WHEN** a deployment is applied twice with unchanged values
- **THEN** the second run SHALL contain no restart step
- **AND** no reading process SHALL have been replaced

#### Scenario: A value read by two entries on two machines

- **WHEN** a value delivered to two machines changes and an entry on each declared a read of it
- **THEN** both entries' units SHALL be restarted
- **AND** each restart SHALL name its own machine

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
