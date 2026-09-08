<!--
A delta on `delivery/real-cluster`, which is defined in the unarchived
`prove-plan-on-real-machines` change. That capability's subject is delivering a built artifact to a
machine that is not the machine that built it; it currently states this for the flakelet realiser
only. The requirements below add the portable-service-image realiser as a second delivery shape and
the two observations the deleted NixOS VM test was the only evidence for.
-->

## ADDED Requirements

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
