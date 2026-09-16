<!--
A delta against `tooling/test-layers`, whose base text lives in the unarchived changes
`strip-planner-tests-to-unit-and-e2e`, `apply-deployments-with-an-operator-command`,
`open-the-repository-to-a-consumer`, `hold-every-stated-guarantee` and
`report-a-secrets-refusal-as-a-row`. `openspec/specs/` is empty in this repository, so the base text
is read from those changes.

Every requirement below is ADDED. The folder shape requirement those changes state - one
`deployment/` and one `test_*.py`, no builder, discovery from `deployment/default.nix` - is unchanged
and is what this folder is held to; what this delta adds is the account a shared guest image owes
when one folder's needs reach it.
-->

## ADDED Requirements

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
