# tooling/test-layers Specification

## Purpose
Defines where a claim about the planner is asserted and how a reader finds it: that there are two
layers and no third, that an end-to-end test's fixture is a directory belonging to that test rather
than a corpus a separate suite reads, that a specification scenario names its test by construction
instead of through a committed table, and that a behaviour observed on a real machine is not also
asserted against a stand-in.

## Requirements

### Requirement: A planner test belongs to one of three kinds

The tests of this package SHALL form exactly three kinds, and the kind SHALL be readable from the
directory a test is in. Which kind a claim is asserted in SHALL follow from how that claim fails,
never from an author's preference.

One kind SHALL assert the library and the realisers by evaluation alone, with no machine and no
built output, reporting every assertion of one run.

One kind SHALL assert a claim whose counterexample ends the evaluation rather than failing an
assertion - a call of something that is not a function, a missing attribute, a coercion of a
function - because such a failure takes the run that would have reported it instead of being
reported by it. A claim of that shape SHALL be one named attribute asserting one condition,
evaluated in a process of its own, one process per attribute, so that a claim that ends its own
evaluation costs the report of no other claim. The attribute SHALL answer that the condition is
fixed, that answer SHALL be what decides whether the claim holds, and an attribute that answers so
SHALL be kept as the regression pin rather than removed.

One kind SHALL assert behaviour on running machines.

A claim about a program that is run rather than evaluated - the operator's command - SHALL be
asserted in that program's own language, beside the program, and SHALL be run by a check of its own.
Such a test SHALL assert nothing that evaluation alone can answer.

Each kind SHALL be registered where its layer is registered, and adding a member of a kind SHALL be
one registration and no other edit. No kind SHALL be gated by a hand-written list of its members: an
attribute asserting a claim that ends an evaluation SHALL be discovered by existing, so that adding
one is adding the attribute and the check evaluates it without being edited.

There SHALL be no fourth kind, and no place for a test whose participants are neither values, nor a
process the check starts, nor machines. The harness that boots the machines MAY carry tests of its
own code beside itself; such a test SHALL assert nothing about the planner.

#### Scenario: The test tree is read

- **WHEN** the package's test directory is listed
- **THEN** it SHALL name exactly the three kinds and nothing else
- **AND** a reader SHALL be able to say which kind a claim is in from that name alone
- **AND** the kind that asserts a claim ending its own evaluation SHALL be named separately from the
  kind that reports many assertions of one run

#### Scenario: A unit test needs no machine

- **WHEN** the evaluating layer is read
- **THEN** every file in it SHALL be a Nix file
- **AND** no file in it SHALL name a built output, a store path it realises, or a program it runs

#### Scenario: An end-to-end test needs a machine

- **WHEN** the machine layer is read
- **THEN** every test in it SHALL be a directory holding one test file
- **AND** the layer's root SHALL hold only the harness those tests share

#### Scenario: A probe is discovered rather than listed by hand

- **WHEN** an attribute asserting a claim that ends an evaluation is added
- **THEN** the check that evaluates those attributes SHALL evaluate the new one without being edited
- **AND** each attribute SHALL be evaluated in a process of its own, so one that ends its evaluation
  SHALL leave every other one reported
- **AND** the check SHALL report, per attribute, whether the claim holds

### Requirement: An end-to-end test carries its own fixture

An end-to-end test's configuration under test SHALL live in that test's own directory: the
interfaces it declares, the modules it composes, its machine registry, its instance declaration, the
packages its modules run and the statement of how its entries are realised. A test SHALL NOT read a
file belonging to another end-to-end test.

A folder SHALL NOT hold the realisation itself. Planning a deployment, realising its entries and
collecting the result SHALL be the repository's own code, shared by every folder and by every reader
outside this repository, and SHALL reach a folder as an argument rather than as a path the folder
resolves. A fixture every end-to-end test needs SHALL live at the layer's root as part of the
harness, and SHALL be the only thing a test reaches upwards for.

A test MAY build its folder's declaration from a directory it creates while it runs, which is how a
consumer outside this repository is observed. What that directory holds SHALL come from the folder
and from committed documentation, never from a path the folder resolves, and the directory SHALL NOT
survive the run.

Adding or removing an end-to-end test SHALL require no edit outside its own directory: the folders
SHALL be discovered, and no list of their names SHALL exist.

#### Scenario: A reader opens an end-to-end directory

- **WHEN** a reader opens an end-to-end test's instance declaration
- **THEN** every module and interface it names SHALL resolve to a file in that same directory
- **AND** the machine registry it is placed against SHALL be in that same directory

#### Scenario: An end-to-end test reads a file of another end-to-end test

- **WHEN** a test names a path inside a sibling end-to-end directory
- **THEN** the check SHALL fail
- **AND** SHALL name both directories

#### Scenario: A fixture is needed by every end-to-end test

- **WHEN** a fixture is required by more than one end-to-end test
- **THEN** it SHALL live at the layer's root rather than be copied into each directory
- **AND** what it guarantees SHALL be stated where it is defined, so a removal fails a build rather
  than a boot

#### Scenario: An end-to-end test is deleted

- **WHEN** an end-to-end test's directory is removed
- **THEN** nothing outside the harness and the specification cross-walk SHALL still refer to it
- **AND** no fixture SHALL be left behind that nothing reads

#### Scenario: An end-to-end folder holds a builder of its own

- **WHEN** a folder holds code that plans a deployment, realises an entry or collects artifacts
- **THEN** the check SHALL fail
- **AND** SHALL name the folder and the file

#### Scenario: An end-to-end folder is added without editing the flake

- **WHEN** the flake is read
- **THEN** it SHALL name no end-to-end folder
- **AND** every folder holding a deployment SHALL be reachable as a package of the flake without one

### Requirement: A specification scenario names its test

The correspondence between a specification scenario and the test that observes it SHALL be a
function of the scenario's heading, not a committed table of pairs. The same heading SHALL yield the
same test name in every layer, spelled in each layer's own convention. Where a heading names no test
of that name, the cross-walk SHALL carry either the name of the test that observes the same
behaviour under a different heading, or the reason the scenario is unobserved, and nothing else.

#### Scenario: A scenario heading is reworded

- **WHEN** a scenario's heading text changes and its test is not renamed with it
- **THEN** the coverage check SHALL fail
- **AND** SHALL show both the name the heading now requires and the name that exists

#### Scenario: A scenario is observed under another heading

- **WHEN** two capabilities describe one behaviour in different words
- **THEN** the cross-walk SHALL name the single test that observes it
- **AND** the check SHALL NOT require a second test to exist

### Requirement: A behaviour is asserted in one layer only

A behaviour SHALL be asserted in one layer. A test name that exists in both layers SHALL fail the
coverage check, naming the behaviour and both files, rather than being left to an author's
judgement.

#### Scenario: One behaviour is asserted in both layers

- **WHEN** a test name derived from one heading exists in both layers
- **THEN** the coverage check SHALL fail
- **AND** SHALL name the heading and the two files that carry it

### Requirement: No observation about the planner is produced by a double

No test of this package SHALL assert the planner's behaviour against a stand-in for a program a
machine would run. Where an observation needs a service manager, a portable-service manager, a
store-copy tool or a network, it SHALL use the machine's own, and therefore SHALL be in the machine
layer.

#### Scenario: A test writes a stand-in for a system binary

- **WHEN** a test creates an executable standing in for a program the realiser's output invokes
- **THEN** the check SHALL fail
- **AND** SHALL name the test and the program it stood in for

### Requirement: Each layer runs from one command

The evaluating layer SHALL be a check of the flake and SHALL run wherever the flake evaluates. The
machine layer SHALL be one command that runs every end-to-end test, SHALL accept the name of one
end-to-end test to run alone, and SHALL NOT appear among the flake's checks, because a build
sandbox cannot boot a machine. That command SHALL refuse before starting any machine when the host
cannot provide what a machine needs, naming what is missing.

#### Scenario: A developer runs every end-to-end test

- **WHEN** the documented machine-layer command is run with no arguments
- **THEN** every end-to-end test SHALL execute
- **AND** the exit status SHALL reflect whether any failed

#### Scenario: A developer runs one end-to-end test

- **WHEN** the command is given the name of one end-to-end test
- **THEN** only that test SHALL execute
- **AND** an unknown name SHALL be refused naming the tests that exist

#### Scenario: The host cannot provide what a machine needs

- **WHEN** the command is run on a host missing a device, a kernel module or a permission a
  machine needs
- **THEN** it SHALL refuse naming each missing thing and why a machine needs it
- **AND** no machine SHALL have been started

#### Scenario: No end-to-end test appears among the checks

- **WHEN** the flake's checks are evaluated
- **THEN** no check SHALL require a machine to boot
- **AND** the machine layer SHALL be reachable as a command instead

### Requirement: The machine layer walks a newcomer's route

One end-to-end folder SHALL observe the route a reader outside this repository takes, and SHALL
observe it on a machine: a deployment built through a flake of the reader's own that consumes this
repository as an input, applied by the operator's command to the machines that flake names, ending
in a running unit on each of them.

The reader's flake SHALL be a committed template directory whose text is the text committed
documentation shows, and whose input SHALL name the published repository and nothing else. The run
SHALL resolve that input to the tree under test by locking the template rather than by editing it,
and the lock SHALL be where the resolution is observable.

Every step of the route SHALL be a command run on a machine that is not this host and belongs to no
plan: the lock, the build, the apply and the report. This host SHALL contribute the source of the
tree under test, the credential the machines authorize, and nothing else. The folder's cluster SHALL
therefore have egress, and the folder SHALL skip itself rather than pass when it has none.

A folder observed this way SHALL hold one deployment of its own, and that deployment SHALL be the
one the template holds.

Other changes MAY add scenarios to this folder. None SHALL redefine what the folder is.

#### Scenario: The template names the published flake

- **WHEN** the machine has locked the template it was given
- **THEN** the lock SHALL record the published flake as the input asked for
- **AND** SHALL record the tree under test as what that input resolved to
- **AND** SHALL record the package set as an input the machine obtained for itself

#### Scenario: The machine builds the deployment it was handed

- **WHEN** a machine holding the template and the source of the tree under test builds the
  deployment
- **THEN** the build SHALL report one entry per machine the template places the service on
- **AND** each entry SHALL name the address the registry declares for its machine
- **AND** two entries of one instance SHALL be two artifacts
- **AND** the build SHALL be in the store of the machine that built it

#### Scenario: One apply reaches both machines

- **WHEN** the machine that built the deployment applies it
- **THEN** the command SHALL report the copy and the activation for every entry
- **AND** the unit each entry declares SHALL be running on the machine that entry names
- **AND** what each unit wrote SHALL name the machine it was planned for

#### Scenario: The machine that built it runs none of it

- **WHEN** the apply has finished
- **THEN** the machine that built and applied the deployment SHALL run no unit of it

#### Scenario: The workstation asks both machines what they hold

- **WHEN** the machine that applied the deployment reports its status
- **THEN** every entry SHALL be reported as the generation its own machine holds

### Requirement: A check that cannot fail is not kept

Every check SHALL be capable of failing on the condition it names. A check whose assertion holds for
every input, that compares a value to itself, that restates the expression under test as its own
expectation, or whose subject the fixture makes unreachable SHALL be either rewritten to assert the
behaviour it claims or removed.

Where the property a check claims cannot be observed by the assertion it makes, the check SHALL be
replaced by one that observes it, and SHALL NOT be kept as a weaker assertion under the original
name.

#### Scenario: An assertion holds for every input

- **WHEN** a check's assertion is true whatever the code under test does
- **THEN** it SHALL NOT remain in the suite
- **AND** the property it claimed SHALL be asserted by a check that fails when the property is lost

#### Scenario: A claimed property needs another observation

- **WHEN** the property a check names cannot be distinguished by the comparison it makes
- **THEN** the suite SHALL observe that property by a means that can distinguish it
- **AND** the check SHALL fail when the property is lost

#### Scenario: A guard compares a record with the values that wrote it

- **WHEN** a run compares stored state against a record derived from that same state in the same run
- **THEN** the comparison SHALL NOT be counted as a guard
- **AND** the guard SHALL be made against state the run did not itself just write

### Requirement: A gate that measured nothing refuses rather than passes

A gate over recorded figures SHALL refuse a run in which a figure it gates was not measured. A
missing measurement SHALL be a failure naming what was not measured, and SHALL NOT be reported as a
comparison that found nothing wrong.

The count of comparisons a gate made SHALL be reported, so that a run comparing fewer figures than
the gate covers is visible.

#### Scenario: A measurement is absent

- **WHEN** a gated figure has no measurement in the run
- **THEN** the gate SHALL fail naming the figure and what was not measured
- **AND** SHALL NOT report the run as having no failures

#### Scenario: Every gated figure was measured

- **WHEN** every figure the gate covers was measured
- **THEN** the gate SHALL report the number of comparisons it made
- **AND** the number SHALL equal the figures it covers

### Requirement: Every refusal of every realiser is accounted for

The suite SHALL account for every refusal every realiser can make, and SHALL fail naming any refusal
that is not accounted for. An account of a refusal SHALL be either the identifier of the row that
reports the same condition, or a recorded statement of why no deployment can reach it.

The set of realisers the accounting covers SHALL be derived from the realiser sources the suite is
handed rather than written out, so that a realiser is covered by existing. A realiser whose refusals
are in no account SHALL fail the suite rather than pass unexamined.

An accounted row identifier SHALL be one a producing layer actually produces. An identifier named by
an account and produced by nobody SHALL fail the suite.

#### Scenario: A realiser is added without editing the accounting

- **WHEN** a realiser source the suite is handed holds a refusal
- **THEN** that refusal SHALL be accounted for or the suite SHALL fail naming it
- **AND** no hand-written list of realiser files SHALL decide whether it is examined

#### Scenario: A refusal with no row above it fails the suite

- **WHEN** a realiser refusal names a condition no producing layer reports as a row
- **AND** the account does not record why no deployment reaches it
- **THEN** the suite SHALL fail naming the refusal and the realiser

#### Scenario: An accounted row nobody produces fails the suite

- **WHEN** an account names a row identifier that no producing layer produces
- **THEN** the suite SHALL fail naming that identifier

### Requirement: A refusal is paired with its row by identity, not by its wording

The pairing between a refusal and the row that reports the same condition SHALL be made on data the
refusal itself carries, not on the text of its message. Rewording a refusal or a row SHALL NOT change
which row a refusal is accounted by, and SHALL NOT fail the accounting.

A refusal carrying no account SHALL fail the suite in the same way as an unaccounted one, so that the
data cannot be omitted where a message fragment would previously have matched by accident.

#### Scenario: A refusal is reworded

- **WHEN** the message of a realiser refusal is rewritten without changing the condition it refuses
- **THEN** the accounting SHALL still pair it with the same row
- **AND** the suite SHALL pass without any test being edited

#### Scenario: A refusal carries no account

- **WHEN** a realiser refusal carries neither a row identifier nor a statement that no deployment
  reaches it
- **THEN** the suite SHALL fail naming the refusal

### Requirement: A fact one folder needs from the shared guest image carries its own account

The guest image every end-to-end machine boots SHALL carry an assertion for each fact a folder needs
from it, stating which folder needs it and why the plan cannot supply it. An account naming no folder
SHALL NOT be added, and a fact no assertion names SHALL NOT be relied on by a folder.

Where such a fact is a machine-level account a service runs as, the account SHALL be declared in the
image, because no plan creates an account: a module's unit may name a user
(`lib/module.nix:58-70`) and nothing in any realiser provisions one. The assertion SHALL say so, so
that the absence is read as the boundary between a deployment and a machine rather than as an
omission.

The assertion SHALL also record what the addition costs: every property of the shared image is part
of every snapshot cut's key, so adding one makes the next run of every folder cold.

#### Scenario: The image declares the account a folder's service runs as

- **WHEN** a folder deploys a service whose unit names a system user
- **THEN** the guest image SHALL declare that account
- **AND** an assertion SHALL name the folder that needs it and state that no plan creates an account
- **AND** the assertion SHALL state that the addition re-keys every snapshot cut

#### Scenario: An image fact no folder needs is not added

- **WHEN** the guest image is read
- **THEN** every assertion SHALL name the folder or folders whose claims depend on it
- **AND** no configuration SHALL be present for a folder the tree does not hold

### Requirement: A folder needing more than one machine's worth of state declares it

A folder whose service holds state on disk SHALL declare the space that state needs through the
stage it obtains machines from, rather than relying on the space another folder's artifacts left
over. The declared figure SHALL be stated beside the folder's own needs, so that a later folder
raising it is a visible edit rather than a silent dependency.

#### Scenario: A stateful folder declares its own space

- **WHEN** a folder deploys a service that writes state on the machine
- **THEN** its stage SHALL declare the additional space that state and the folder's artifacts need
- **AND** the declaration SHALL be readable beside the folder rather than inferred from another's

### Requirement: A folder that writes state is recognised by what its modules declare

The check that a stateful folder declares its own disk space SHALL recognise such a folder from a
fact its modules still carry once every host path is derived rather than stated. A folder that writes
state on a machine and is not recognised SHALL fail the check rather than pass it vacuously, so that
deleting a settings knob cannot silently remove a folder from the set the check covers.

The space SHALL be declared on the folder's own stage and nowhere else. Nothing about the shared guest
image SHALL carry it, because every property of that image is part of every folder's snapshot cut key.

#### Scenario: A folder writing state is recognised by what it declares

- **WHEN** the folder whose modules derive their state directories is checked
- **THEN** it SHALL be counted as a folder that writes state
- **AND** the check SHALL require its stage to declare disk space

#### Scenario: A stateful folder declares its space on its own stage

- **WHEN** every folder that writes state is read
- **THEN** each SHALL declare its space where its stage is declared
- **AND** the shared guest image SHALL declare no per-folder space

### Requirement: One folder proves both halves of the instancing goal

The machine layer SHALL hold one folder in which one service module is instantiated twice in one
deployment: once shared between consumers on two machines and once owned by a single application,
with both instances placed on one machine. The two instances SHALL be backed by one module file, so
that what the folder proves is instantiation rather than two modules that happen to resemble each
other.

#### Scenario: One module file backs both instances

- **WHEN** the folder's modules are read
- **THEN** the module the application composes its own database from SHALL be the same file the
  shared instance is built from
- **AND** the folder SHALL hold no second copy of it

### Requirement: No deployment of the machine layer states a host path

No `.nix` file under a machine-layer folder's deployment SHALL carry a host path written out in full.
A host path SHALL be recognised as a string literal beginning with `/` whose first segment is one of
the machine's own roots, and it SHALL be held to be written out in full when the literal contains no
interpolation. A path built by interpolating the identity of the entry that uses it SHALL be
permitted, and a path that is not a host path - a URL path, a path relative to the folder - SHALL be
outside the rule.

The check SHALL name the file, the line and the path, so that a failure says what to derive rather
than that something is wrong. It SHALL cover the template deployment a consumer is shown as well as
the folders' own, because that template is what a reader outside the repository copies first.

The rule SHALL NOT extend to the unit suites' own fixtures or to `fixtures/`: those deployments exist
to exercise the library's reading, are placed once by construction, and their paths are compared
against goldens, so a derived path there would move a golden without making a claim about a machine.

#### Scenario: A deployment states a host path

- **WHEN** a `.nix` file under a folder's deployment carries a string literal naming a host path with
  no interpolation in it
- **THEN** the check SHALL fail naming the file, the line and the path

#### Scenario: A URL path is not a host path

- **WHEN** a deployment carries a literal such as a URL path whose first segment is not one of the
  machine's roots
- **THEN** the check SHALL pass

#### Scenario: A derived path is permitted

- **WHEN** a module builds a host path by interpolating the instance and the member of its own entry
- **THEN** the check SHALL pass
- **AND** two entries of one machine SHALL therefore hold two different paths

### Requirement: A test reads a path off the plan rather than restating it

No folder's test SHALL carry a host path that the folder's own deployment also carries. A path a test
has to assert SHALL be read out of the plan the test built, so that the assertion is about what the
deployment put where the machine will look, and so that a module whose derivation changes makes the
test red rather than leaving a constant that no longer describes anything.

A path only the test knows - a fake root it invents, a path it expects a machine to refuse - SHALL be
permitted, that path being the test's own claim rather than a restatement of the deployment's.

#### Scenario: A test restates a path its deployment carries

- **WHEN** a folder's test and its deployment both carry one host path
- **THEN** the check SHALL fail naming the folder, the path and both files

#### Scenario: A test carries a path of its own

- **WHEN** a test carries a host path its deployment does not carry
- **THEN** the check SHALL pass

### Requirement: An invariant is held by a test asserting the claim rather than the behaviour

A test of an invariant this repository records SHALL assert the claim the repository states, and not
the behaviour the code exhibits. It SHALL carry the sentence it pins, so that a failure reads as the
claim that is false rather than as two values that differ, and so that a reader can find where the
claim is stated without reading the code the test exercises.

A test of that kind SHALL be red for as long as the claim is false, and being red SHALL be
information rather than a defect of the test. It SHALL NOT be relaxed to what the code does today,
SHALL NOT be marked as expected to fail, and SHALL NOT be withheld from the suite until the claim is
made true: an unasserted claim is a claim nobody notices losing.

A claim made true SHALL leave its test in place as the regression pin, under the title it already
carries, so that the test which found the defect is the test that keeps it out.

A claim withdrawn or narrowed SHALL leave its test rewritten to the narrowed claim and quoting the
narrowed sentence, rather than deleted. The narrowing SHALL be recorded where the claim is stated, so
that the sentence a test quotes is a sentence the repository still states, and a quote of a sentence
nobody states any more SHALL fail rather than pass unread.

Every test of a recorded invariant SHALL be counted as a test by the specification cross-walk,
whatever language it is written in, the tests of the operator's command included. A scenario whose
derived name names one SHALL be answered by it exactly as a scenario naming an evaluating test or a
machine test is answered, and the rule that one name SHALL NOT exist in two layers SHALL hold across
every counted kind.

#### Scenario: A counterexample quotes the claim it pins

- **WHEN** a test asserts an invariant the repository records
- **THEN** it SHALL carry the sentence that invariant is stated in
- **AND** that sentence SHALL be one the repository still states, so a withdrawn claim fails until
  its test quotes the narrowed one
- **AND** a test asserting today's behaviour instead SHALL NOT be counted as holding the invariant

#### Scenario: The command's own tests are counted

- **WHEN** the specification cross-walk collects the tests that answer for scenarios
- **THEN** the tests written in the operator's command's own language SHALL be among them
- **AND** a scenario whose derived name names one SHALL be reported as observed
- **AND** a derived name carried by two kinds at once SHALL still fail the check naming both
