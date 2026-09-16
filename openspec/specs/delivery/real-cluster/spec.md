# delivery/real-cluster Specification

## Purpose
Defines what it means to deliver a built artifact to a machine that is not the machine that built
it, and which of a plan's claims a cluster of real machines is able to falsify: the addresses it
computed, the ports it allocated, and the wires it resolved at evaluation time. Every requirement
here is observed on running machines with no stub, no double and no injected store.

## Requirements

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
hypervisor. No part of the observation SHALL be produced by a stub, a fake or a recording. A
machine's *state* MAY be restored from a cut of a machine that booted, and a machine so restored
SHALL be a running kernel executing on from that state; every fact a test asserts SHALL be produced
by that machine during the run that asserts it.

The bytes of a generated value SHALL be produced by a real generator and held by a real store
backend, and the test SHALL NOT write them. A folder MAY state a value the test supplies only where
that value stands for something outside the deployment - a key an operator already holds - and SHALL
NOT do so for a value the deployment declares a generator for.

#### Scenario: Every participant is the real one

- **WHEN** the check runs
- **THEN** each machine SHALL be a kernel of its own, either booted this run or restored from a cut
  of one, reached over its own SSH server
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

#### Scenario: The delivered bytes were generated, not written

- **WHEN** a folder asserts that a machine authenticated with a delivered value
- **THEN** those bytes SHALL have been produced by the generator the deployment declares
- **AND** they SHALL have been held by a store backend between generation and delivery
- **AND** no literal of them SHALL appear anywhere in the folder

### Requirement: A portable-service image attaches on the machine the plan placed it on

An image realised from a placed plan entry SHALL be deliverable to that entry's machine and
attachable there by the script the artifact itself carries, with no step reconstructed by the
harness. Attaching SHALL use the machine's own portable-service manager and its own service
manager. An image whose target does not match the machine SHALL be refused by that script, on that
machine, before anything is attached.

#### Scenario: The image is attached by the script the artifact carries

- **WHEN** a delivered image artifact is attached on its machine
- **THEN** the command that attaches it SHALL be the script the realiser wrote into the artifact
- **AND** the harness SHALL NOT issue an attach command of its own construction

#### Scenario: The attached unit becomes active

- **WHEN** the artifact's attach script has completed on the machine
- **THEN** every unit the attachment names SHALL be active on that machine
- **AND** the image the portable-service manager reports as attached SHALL be the one the plan's
  entry names

#### Scenario: The confinement profile is enforced by the machine

- **WHEN** an entry stated to run under a restricted profile is attached
- **THEN** the profile the portable-service manager reports for it SHALL be the stated one
- **AND** a read the profile denies SHALL fail on the machine rather than in a description of it

#### Scenario: An image built for another architecture is refused

- **WHEN** an image whose target system is not the machine's is attached on that machine
- **THEN** the attach SHALL be refused naming both the built target and the machine's own
- **AND** no unit SHALL have been started

### Requirement: Detaching leaves the machine as it was found

Detaching an attached entry SHALL remove exactly what attaching created: the units and the staging
directory. A file attaching was shown rather than created — a generated file on the host, a store
path named as a reference — SHALL survive detaching untouched.

#### Scenario: Detaching removes the units and the staging directory

- **WHEN** a detached entry's machine is inspected
- **THEN** none of the attachment's units SHALL be known to the service manager
- **AND** the staging directory attaching created SHALL be absent

#### Scenario: A host file the image was shown survives detaching

- **WHEN** an entry that reads a host file is attached and then detached
- **THEN** that host file SHALL still be present with its contents unchanged
- **AND** the store paths the attachment named as references SHALL still be valid on the machine

### Requirement: A scheduled entry is deployed without being run

Delivering and activating an entry whose unit is scheduled SHALL install its trigger and SHALL NOT
run the unit. The schedule SHALL be what starts it, and a deployment SHALL be observable as a
trigger that is armed and a service that has not run.

#### Scenario: A scheduled unit is not fired by deploying it

- **WHEN** a scheduled entry has been delivered and activated on its machine
- **THEN** the service SHALL show no completed run
- **AND** the machine SHALL report it as never having been started

#### Scenario: The timer the schedule declares is enabled

- **WHEN** the same machine's timers are listed
- **THEN** the entry's timer SHALL be active with a next elapse in the future
- **AND** the unit it names SHALL be the entry's own service

### Requirement: A rollback names the generation it came from

The endpoint's record of a rollback SHALL state that the change was a rollback and which generation
it returned from, so a machine's history distinguishes a rollback from a redelivery of older
content.

#### Scenario: The endpoint reports what the rollback came from

- **WHEN** an entry with two generations is rolled back and the endpoint is asked for its status
- **THEN** the record SHALL identify the change as a rollback
- **AND** SHALL name the generation it returned from

### Requirement: A delivery of a generated value goes to the set the plan named

A delivery of a generated value SHALL take the plan and the value's own entry, and SHALL address
exactly the machines that entry's delivery set names, at the addresses the plan records for them. It
SHALL write each declared file at the path the entry records, and SHALL do so outside the store,
because a store object is readable by every process on the machine.

A machine the set does not name SHALL receive nothing, whether or not it runs a service of either
instance. A value the entry records as received by nobody SHALL be delivered to no machine at all.

#### Scenario: A secret reaches the machines the plan names

- **WHEN** the value behind a secret export read by a consumer on another machine is delivered
- **THEN** both the owner's machine and the consumer's machine SHALL hold the file at the path the
  plan records
- **AND** the bytes SHALL be identical on both
- **AND** the file SHALL be readable only by the user the units run as

#### Scenario: A machine outside the delivery set holds nothing

- **WHEN** a third machine of the same cluster runs a service of neither instance
- **THEN** it SHALL hold no file of either value
- **AND** it SHALL hold no directory of the owning instance's generated values

#### Scenario: A value nobody receives is on no machine

- **WHEN** the deployment declares a generator no machine receives
- **THEN** no machine of the cluster SHALL hold any file of it after every delivery the plan calls
  for

### Requirement: A delivered secret is the credential the service uses

The proof that a secret was delivered SHALL be the service using it, not the file existing: a
consumer on another machine SHALL authenticate to the provider with the delivered value over the
network, and the same request without it SHALL be refused by the provider. Both SHALL be observed
against the real units the plan describes.

#### Scenario: A consumer authenticates with the delivered secret

- **WHEN** the consumer's unit runs after the value has been delivered to its machine
- **THEN** its request to the provider on the other machine SHALL be accepted
- **AND** the unit SHALL read the value from the path the plan recorded rather than from any value
  in the artifact

#### Scenario: The provider refuses a request without it

- **WHEN** the same request is made to the provider without the delivered value
- **THEN** the provider SHALL refuse it
- **AND** the refusal SHALL come from the provider's own unit rather than from the harness

### Requirement: The bytes travel beside the artifacts, never inside them

Neither the plan nor any artifact built from it SHALL contain the bytes of a delivered value. A
value declared public MAY travel inside the plan, and a machine SHALL then be able to use it without
holding any file of it.

#### Scenario: No artifact carries the delivered bytes

- **WHEN** the plan and every artifact of the deployment are searched for the delivered bytes
- **THEN** they SHALL be found in none of them

#### Scenario: A public generated value travels in the plan

- **WHEN** a public file of a generator no machine receives is published as an export and read by a
  consumer
- **THEN** the consumer's unit SHALL be handed its value by the artifact
- **AND** no machine SHALL hold a file of that generator

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

### Requirement: A run broken between two machines is finished by a second run

Where a run of the operator's command is broken between two machines of a cluster, the machines it
reached SHALL hold what it put there and the machines it did not reach SHALL hold what they held
before. The report of the broken run SHALL name the step that broke and the machine that refused it,
and SHALL name as taken exactly the steps that were taken.

A second run of the same command over the same built deployment and the same value source, once the
machine can be reached again, SHALL leave every machine of the cluster running the deployment: the
entries the first run applied SHALL be undisturbed by the second, and the entries it did not apply
SHALL be applied. No step of the recovery SHALL be an undo of the first run.

#### Scenario: A run broken between two machines names the step that broke

- **WHEN** the route to the second machine of a cluster is cut and the deployment is applied
- **THEN** the run SHALL exit non-zero
- **AND** its last step line SHALL name the step against the machine that could not be reached
- **AND** every entry of the machine it did reach SHALL be running there

#### Scenario: A second run finishes what the broken run left

- **WHEN** the route is restored and the same deployment is applied again from the same build and
  the same value source
- **THEN** the run SHALL complete
- **AND** the entry on the machine the broken run never reached SHALL be running
- **AND** the entry the broken run applied SHALL still be running the generation it applied

#### Scenario: A machine the broken run never reached holds what it held before

- **WHEN** a run is broken before it reaches one machine of a cluster
- **THEN** that machine SHALL hold no artifact and no generated file of the entries the run did not
  reach it with
- **AND** what it held before the run SHALL be unchanged

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

### Requirement: A stateful service's setup is declared rather than scripted

The folder's cluster SHALL obtain its data directory, its authentication file and its one-time
bootstrap from declarations the plan carries, and its setup step SHALL create none of the three. The
data directory SHALL be a directory the service manager creates for the unit, at the mode the server
requires and owned by the account the unit declares, so that the step neither makes a directory nor
chooses its mode. The authentication file SHALL be a configuration file of the deployment, at a path
the module derives from its own entry's identity rather than one the deployment states, and the
server SHALL be told where it is by the configuration file the module already declares. The
bootstrap SHALL be a unit of its own whose start is conditional on the absence of the file that
proves the cluster exists, and the step that applies roles and databases SHALL run on every apply.

One declared file SHALL decide how a role's password is hashed: the private server the setup step
starts to apply roles SHALL read the same configuration file the published server reads, so no flag
of the initialisation states a second answer.

#### Scenario: The init step creates no directory of its own

- **WHEN** the folder's deployment is applied to a machine that has never run it
- **THEN** the data directory SHALL exist before the step runs, created by the service manager from
  the declaration
- **AND** the step's own script SHALL contain no directory creation

#### Scenario: The data directory arrives at the mode the server requires

- **WHEN** the cluster's units are active on a machine
- **THEN** the data directory SHALL be at the mode the declaration states and owned by the account
  the unit declares
- **AND** the server SHALL have started against it without refusing its permissions

#### Scenario: The authentication file arrives as a declared file

- **WHEN** the same machine is asked what it holds at the path the module derived
- **THEN** the authentication file SHALL be there with the bytes the plan holds
- **AND** the running server SHALL name that path as the file it read
- **AND** the path SHALL appear in the plan rather than in any declaration of the deployment

#### Scenario: The bootstrap runs once and is skipped after

- **WHEN** the deployment is applied twice to one machine
- **THEN** the bootstrap unit SHALL report having done its work on the first apply and having been
  skipped on the second
- **AND** the step that applies roles and databases SHALL have run both times

#### Scenario: One file decides how a password is hashed

- **WHEN** a role's password is applied by the setup step and the role then authenticates over the
  network
- **THEN** the hashing method SHALL be the one the declared configuration file states
- **AND** no flag of the initialisation SHALL state a method of its own

### Requirement: A second apply converges the roles and databases the deployment names

Applying the folder's deployment SHALL leave the cluster holding what the deployment names, and not
merely what it named the first time it was applied. A database that exists and whose declared owner
has changed SHALL be owned by the declared owner after the apply, and a role that owned it and is
no longer named SHALL no longer be able to log in. A role SHALL NOT be dropped: what the deployment
states is who may log in, not which of a machine's objects to delete.

Every value the step interpolates into SQL SHALL be escaped at the site it is interpolated, as an
identifier or as a literal according to which it is, so that a name carrying a quote is one name and
never a statement.

#### Scenario: A changed database owner takes effect on a second apply

- **WHEN** a deployment whose declared owner of an existing database differs from the one applied
  before is applied to that machine
- **THEN** the database SHALL be owned by the newly declared role
- **AND** the data written under the previous owner SHALL still be readable through it

#### Scenario: A role the deployment no longer names cannot log in

- **WHEN** the same apply has finished
- **THEN** the role the deployment no longer names SHALL be refused a login with its own credential
- **AND** the role SHALL still exist, so nothing it owned was deleted with it

#### Scenario: An identifier carrying a quote is not SQL

- **WHEN** a consumer whose declared label carries a quote writes its record
- **THEN** the record SHALL hold that label verbatim
- **AND** the step SHALL report no SQL error, so the quote was escaped rather than parsed
