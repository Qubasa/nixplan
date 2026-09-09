<!--
A delta against `delivery/real-cluster`, which lives in the unarchived `prove-plan-on-real-machines`
change and is already modified by `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots`, `deliver-secrets-across-machines` and
`generate-values-with-nixos-secrets`. Nothing existing changes.

*No test double is involved* is deliberately left alone, even though this change is about the same
subject: it is being modified by the unstarted sibling change, and its own requirements are about
what a participant must not be. Until now the artifacts a run delivered were built by code written
for that run - one `artifacts.nix` per folder - and the delivery steps were assembled by the harness
(`copy_argv`, `deliver`, `activate`, `rollback` in `tests/e2e/delivery.py`). Neither is a stub, so
neither was refused by that requirement as written. What was missing is stated here as its own
requirement: a run has to take the operator's steps, or a defect between plan and running service has
no test to fail. `operator/apply-command` in this change owns what those steps are.
-->

## ADDED Requirements

### Requirement: A run applies its deployment the way an operator does

The artifacts a run delivers SHALL be built by the same code an operator's build runs, and the steps
that put them on a machine SHALL be the operator's own command. The harness SHALL contribute no
realisation of a plan and no delivery step of its own: what it MAY contribute is what only a test
needs - the machines, the credential a throwaway guest is reached with, the bytes a value source
stands in for, and the reading of the plan its assertions make.

#### Scenario: The artifacts were built by the operator's command

- **WHEN** a folder's deployment is put on its machines
- **THEN** each artifact delivered SHALL be the one the operator's build produced for that plan key,
  taken from the manifest that build wrote
- **AND** the copy, the value write and the activation SHALL each be a step of the operator's command
- **AND** the folder SHALL hold no code that realises a plan or delivers an artifact
