<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `realiser/flakelet-artifact` in the unarchived `emit-flakelet-service-artifacts` change,
which defines the artifact this capability delivers, and against `planner/typed-edge` in
`implement-minimal-typed-edge`, which defines the wire this capability observes as traffic.
-->

## Purpose

Defines what it means to deliver a built artifact to a machine that is not the machine that built
it, and which of a plan's claims a cluster of real machines is able to falsify: the addresses it
computed, the ports it allocated, and the wires it resolved at evaluation time. Every requirement
here is observed on running machines with no stub, no double and no injected store.

## ADDED Requirements

### Requirement: A delivery moves one entry's closure to the machine the plan placed it on

A delivery SHALL take a plan, one placed entry, and nothing else, and SHALL address the machine at
the address the plan records for it. After a delivery the receiving machine SHALL hold the
artifact and every store path its units name. The delivery SHALL move the artifact's closure and
no other closure.

#### Scenario: The machine holds what the artifact names

- **WHEN** an entry placed on a machine has been delivered to it
- **THEN** the artifact's own path SHALL be present on that machine
- **AND** every store path the entry's units name SHALL be present on that machine
- **AND** each of those paths SHALL be a valid store path on that machine, not loose files

#### Scenario: The plan names the address

- **WHEN** a delivery is asked for an entry placed on a machine
- **THEN** the address it connects to SHALL be the address the plan records for that machine

#### Scenario: An entry is not delivered to a machine it was not placed on

- **WHEN** a delivery is asked for an entry and a machine the plan did not place it on
- **THEN** the delivery SHALL be refused naming the entry, the machine asked for and the machines
  the plan placed it on
- **AND** no bytes SHALL have been sent

### Requirement: The receiving machine evaluates nothing and fetches nothing

A machine SHALL be able to run a delivered entry without evaluating the plan, without a copy of the
deployment, and without reaching any store but its own. The machine's ability to run the entry
SHALL come only from what the delivery moved.

#### Scenario: The unit runs from the delivered directory

- **WHEN** a delivered entry is activated on the machine
- **THEN** the entry's long-running unit SHALL become active
- **AND** the endpoint SHALL report the entry as running under the plan's key for it

#### Scenario: No evaluation happens on the machine

- **WHEN** an entry is activated on the machine
- **THEN** the machine's record of the activation SHALL show a prebuilt artifact being used
- **AND** SHALL show no evaluation and no build

#### Scenario: No store but the machine's own is reachable

- **WHEN** the whole run takes place
- **THEN** the machines SHALL have no route to any host outside the cluster
- **AND** every store path a unit names SHALL therefore have arrived by delivery and by nothing else

### Requirement: A wire the planner resolved is traffic between two machines

A plan that wires a consuming service on one machine to a providing service on another SHALL be
observable as a request that succeeds between those two machines, at the address the plan computed,
on the port the planner allocated. Both ends SHALL learn the address from the planner: the producer
from the machine it was planned for, the consumer from the wire it read, and neither from anything
it discovers at runtime or is told by the harness.

#### Scenario: The consumer reaches the producer

- **WHEN** both entries of a wired pair have been delivered to their two machines and activated
- **THEN** the consumer's unit SHALL succeed against the producer
- **AND** its success SHALL be observable on the consuming machine

#### Scenario: The address used is the address the plan recorded

- **WHEN** the consumer's delivered unit text is read
- **THEN** the address it names SHALL equal the address the producer's export carries in the plan
- **AND** that address SHALL equal the address the producing machine actually holds

#### Scenario: Neither end was told the address by the harness

- **WHEN** the deployment that produced both entries is read
- **THEN** the address SHALL appear once, in the machine registry
- **AND** the harness SHALL pass no address into the plan

#### Scenario: The allocated port is the listening port

- **WHEN** the producer is running on its machine
- **THEN** a socket SHALL be listening on the port the planner allocated for it
- **AND** no socket SHALL be listening on that port on the consuming machine

#### Scenario: Cutting the wire's far end is visible

- **WHEN** the producing entry is stopped on its machine
- **THEN** the consumer's request SHALL fail
- **AND** the failure SHALL name the address the plan computed

### Requirement: A redelivery decides by identity, and a machine can go back

A second delivery of an entry whose artifact is unchanged SHALL leave the running service alone. A
delivery of a changed entry SHALL become a new generation, and the machine SHALL be able to return
to the previous one.

#### Scenario: An unchanged entry is a no-op

- **WHEN** an entry already running is delivered and activated again unchanged
- **THEN** the endpoint SHALL report the same generation as before
- **AND** the running process SHALL not have been replaced

#### Scenario: A changed entry is a new generation

- **WHEN** an entry whose unit differs is delivered and activated
- **THEN** the endpoint SHALL report a later generation
- **AND** the change SHALL be observable in the service's own behaviour

#### Scenario: Rollback returns the previous generation

- **WHEN** the machine is asked to roll back an entry with two generations
- **THEN** the endpoint SHALL report the previous generation as active
- **AND** the service's observable behaviour SHALL be the previous one

### Requirement: What the machine keeps across a reboot and a reconcile

A delivered entry SHALL survive a reboot of its machine without a second delivery and without
evaluation. A machine whose host configuration declares no services SHALL NOT remove an entry that
was delivered and activated by hand.

#### Scenario: A reboot brings the entries back

- **WHEN** both machines are rebooted after their entries were activated
- **THEN** each entry's units SHALL be active again
- **AND** the wire between them SHALL be traffic again

#### Scenario: A reconcile leaves a hand-activated entry alone

- **WHEN** the machine's own reconcile pass runs, and its host configuration declares no services
- **THEN** the delivered entry SHALL still be registered and running

### Requirement: No test double is involved

The run SHALL use real processes end to end: the endpoint's own binary, each machine's own service
manager and SSH server, a real store-to-store copy over the network, and real machines under a real
hypervisor. No part of the observation SHALL be produced by a stub, a fake or a recording.

#### Scenario: Every participant is the real one

- **WHEN** the check runs
- **THEN** each machine SHALL be a booted kernel of its own, reached over its own SSH server
- **AND** the endpoint on each machine SHALL be its packaged binary
- **AND** the delivery SHALL be performed by the same store-copy tool an operator would use

#### Scenario: The machines are not told the answer

- **WHEN** a machine boots
- **THEN** its image SHALL contain no artifact of the plan and none of the store objects an entry
  it will be given contributes: the artifact directory, its unit files, and the payload the unit
  names
- **AND** a store object both the image's own closure and an entry name SHALL be shared rather than
  delivered, so a base image holding the tool an entry runs is not a leak of the plan
- **AND** it SHALL declare no services of its own
