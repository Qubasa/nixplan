<!--
A delta against `tooling/test-layers`, whose base text lives in the unarchived changes
`strip-planner-tests-to-unit-and-e2e`, `add-scenario-test-harness`,
`resume-e2e-machines-from-snapshots`, `run-a-shared-database-on-real-machines`,
`report-a-secrets-refusal-as-a-row`, `hold-every-stated-guarantee` and
`give-every-instance-its-own-database`. `openspec/specs/` is empty in this repository, so the base
text is read from those changes.

Both requirements below are ADDED. Nothing about what a folder holds, how it is discovered or what
its stage declares changes; these two say what a folder's deployment may not state and what its test
may not restate.
-->

## ADDED Requirements

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
