<!--
A delta against `tooling/test-layers`, whose requirements live in the unarchived
`strip-planner-tests-to-unit-and-e2e` change and were last narrowed by
`apply-deployments-with-an-operator-command`. This delta reads against that narrowed text, which is
restated below in full.

Two things change. *An end-to-end test carries its own fixture* forbids a test to reach outside its
own folder, and the newcomer walk has to copy a directory of its folder onto a machine and build it
there. The requirement is restated so a directory a run copies is permitted and a path a folder
resolves outside itself is still not. Beside it, a new requirement puts the consumer's route in the
machine layer, because a route that is documented and never walked is a document rather than a
route.
-->

## MODIFIED Requirements

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

## ADDED Requirements

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

