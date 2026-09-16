<!--
A delta against `tooling/test-layers`, which lives in the unarchived
`strip-planner-tests-to-unit-and-e2e` change. Only *An end-to-end test carries its own fixture*
changes.

As written, a folder's fixture includes "the realisation of them", and each of the three folders
therefore holds an `artifacts.nix` that applies the declaration to real packages, plans it, realises
each entry and collects the result. Three of those five steps are identical in all three files, and
the identical part is now a layer of the repository (`operator/`), asserted in the evaluating layer.
What is left for a folder is what only that folder knows: its packages and how its entries are
realised. The requirement is narrowed to that, and gains the two shape claims the narrowing makes
checkable.
-->

## MODIFIED Requirements

### Requirement: An end-to-end test carries its own fixture

An end-to-end test's configuration under test SHALL live in that test's own directory: the interfaces
it declares, the modules it composes, its machine registry, its instance declaration, the packages its
modules run and the statement of how its entries are realised. A test SHALL NOT read a file belonging
to another end-to-end test.

A folder SHALL NOT hold the realisation itself. Planning a deployment, realising its entries and
collecting the result SHALL be the repository's own code, shared by every folder and by every reader
outside this repository, and SHALL reach a folder as an argument rather than as a path the folder
resolves. A fixture every end-to-end test needs SHALL live at the layer's root as part of the harness,
and SHALL be the only thing a test reaches upwards for.

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
