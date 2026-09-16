<!--
A delta against `delivery/real-cluster`, whose base text lives in the unarchived changes
`prove-plan-on-real-machines`, `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots`, `deliver-secrets-across-machines`,
`apply-deployments-with-an-operator-command`, `make-an-apply-observable`,
`generate-values-with-nixos-secrets` and `deliver-a-secret-without-exposing-it`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Every requirement below is ADDED. The existing requirements about what a delivery moves, which
machines answer and how a run is observed are unchanged: this delta adds one deployment shape to the
set the layer proves, and says what that shape has to demonstrate on a machine rather than in a plan.

`deliver-secrets-across-machines` states that a declared read of a secret export is what widens a
value's delivery set. This delta is the first place where the machine that is left out of one
delivery set is a working consumer of the same provider instance rather than a machine running
nothing.
-->

## ADDED Requirements

### Requirement: Two instances take one capability each from one provider instance

The end-to-end layer SHALL apply a deployment in which one instance publishes one capability per
entry of a settings-valued declaration, and two other instances each wire exactly one of those
capabilities. The provider SHALL be deployed once, and the two consumers SHALL receive two different
values of the same interface.

The consumers SHALL NOT be placed identically: one SHALL share the provider's machine and one SHALL
be on another machine, so that one deployment demonstrates both a local and a routable read of the
same provider.

The values each consumer receives SHALL be the values the plan recorded for the capability it wired,
and a consumer SHALL NOT be able to reach the other's capability with what it was given.

#### Scenario: Two instances take one database each

- **WHEN** a deployment places one database cluster instance declaring two databases, and two
  consumer instances each wiring one of them
- **THEN** the plan SHALL carry one entry for the cluster and one for each consumer
- **AND** each consumer's unit SHALL carry the data source of the database it wired
- **AND** neither consumer's unit SHALL carry the other's data source

#### Scenario: A consumer on another machine reads over the address the plan recorded

- **WHEN** the consumer that is not on the provider's machine is activated
- **THEN** it SHALL reach the provider at the address and port the plan recorded for that machine
- **AND** the value it read SHALL be the value the provider's entry published

#### Scenario: One process is behind both capabilities

- **WHEN** both consumers have read their databases
- **THEN** the machine SHALL report one long-running process serving both
- **AND** the entry SHALL have declared one long-running unit and one unit that applied and exited

#### Scenario: A credential of one capability is refused by the other

- **WHEN** the credential the provider published for one capability is presented to the other
- **THEN** the provider SHALL refuse it
- **AND** the refusal SHALL be the provider's own answer, read from the machine

### Requirement: A per-consumer credential reaches its consumer's machine and no other

Where a provider publishes one generated value per capability and each consumer declares a read of
its own, the value SHALL exist on the provider's machine and on the machine of the consumer that
read it, and SHALL NOT exist on the machine of a consumer that read a different capability of the
same provider.

The entry SHALL record, for each value, the machines it is delivered to and what derived that set,
and the machines SHALL agree with the record: a file the record does not deliver SHALL be absent from
that machine's filesystem, not merely unreferenced.

#### Scenario: A consumer's machine holds its own credential only

- **WHEN** two consumers of one provider instance each declare a read of a different secret export
- **THEN** each consumer's machine SHALL hold the value it read
- **AND** SHALL NOT hold the value the other consumer read
- **AND** the delivery record of each value SHALL name the provider's machine and one consumer's

#### Scenario: A working consumer is outside one delivery set

- **WHEN** a machine runs a consumer of one capability of a provider and not of another
- **THEN** the value backing the capability it does not read SHALL be absent from that machine
- **AND** the run SHALL still have activated that machine's own entry

### Requirement: A stateful entry survives the restart of its own service

An entry whose long-running unit holds state on the machine SHALL be restartable without the state
being rebuilt: restarting the long-running unit SHALL leave the data written before it readable
after it, and the unit that initialised the state SHALL NOT run a second time.

#### Scenario: Data written before a restart is readable after it

- **WHEN** a consumer has written data through its capability and the provider's long-running unit is
  restarted on the machine
- **THEN** the data SHALL be readable through the same capability afterwards
- **AND** the initialising unit SHALL report the same start timestamp it had before the restart
