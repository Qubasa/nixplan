<!--
A delta against `delivery/real-cluster`, whose base text lives in the unarchived changes
`prove-plan-on-real-machines`, `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots`, `deliver-secrets-across-machines`,
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`generate-values-with-nixos-secrets`, `deliver-a-secret-without-exposing-it` and
`run-a-shared-database-on-real-machines`. `openspec/specs/` is empty in this repository, so the base
text is read from those changes.

Every requirement below is ADDED. `run-a-shared-database-on-real-machines` states what one provider
instance shared by two consumers has to demonstrate, and none of that changes: the shared cluster,
its two databases, its two consumers and the delivery-set claims stay exactly as they are. This delta
adds the other half of the design goal - a second instance of the same module, on the same machine,
serving one application - and the rule that a deployment states no host path.
-->

## ADDED Requirements

### Requirement: Two instances of one module run on one machine

The end-to-end layer SHALL apply a deployment that places two instances of one service module on one
machine, one of them shared by consumers on two machines and one of them owned by a single
application. Both SHALL be running at once on that machine, and each SHALL be serving its own state.

No host resource SHALL be shared between them: the two instances SHALL hold two data directories, two
configuration files, two listening ports and two local sockets, and each of those SHALL be derived by
the module from the identity of the entry it belongs to rather than stated by the deployment.

#### Scenario: Two instances of one module run on one machine

- **WHEN** the deployment is applied
- **THEN** the machine SHALL report two running server processes of that module
- **AND** each SHALL name its own data directory, its own configuration file and its own port
- **AND** no two of those paths, ports or sockets SHALL be equal

#### Scenario: Every path a unit uses comes from the plan

- **WHEN** the paths the units use are read out of the plan the command built
- **THEN** each SHALL contain the instance and the member of the entry that uses it
- **AND** the deployment's own declarations SHALL state none of them

### Requirement: An application reaches the instance it wired and no other

Each application SHALL read and write through the capability it wired, against the server that
published it, and SHALL be unable to reach the other instance's state with what it was given.

The evidence SHALL be the servers' own answers read from the machines, not a claim in the plan: the
identity each server reports SHALL differ between the two instances, each application's row SHALL be
present in the instance it wired and absent from the other, and a credential published by one
instance SHALL be refused by the other.

#### Scenario: Each application reaches the database it wired

- **WHEN** each application has written its row
- **THEN** the row SHALL be readable in the instance that application wired
- **AND** the identity the server reports SHALL be that instance's own
- **AND** the two instances SHALL report two different identities

#### Scenario: Neither cluster carries the other's databases

- **WHEN** each server is asked which databases it holds
- **THEN** the shared instance SHALL hold the databases the deployment declared for it and not the
  private one's
- **AND** the private instance SHALL hold its own and neither of the shared instance's

#### Scenario: A credential of the shared cluster is refused by the private one

- **WHEN** a credential the shared instance published is presented to the private instance
- **THEN** the private instance SHALL refuse it
- **AND** the refusal SHALL be that server's own answer, read from the machine

#### Scenario: The private cluster's credential is on its own machine only

- **WHEN** the value backing the private instance's capability is delivered
- **THEN** it SHALL exist on the machine that runs the private instance and its application
- **AND** SHALL be absent from the machine that runs neither
- **AND** its delivery record SHALL name that machine and no other
