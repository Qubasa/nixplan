<!--
`openspec/specs/` is empty in this repository, so this new capability is written here. It reads
against `delivery/real-cluster` in `prove-plan-on-real-machines`, which owns what a real machine is
asked and whose *No test double is involved* requirement this change restates, and against
`tooling/test-layers` in `strip-planner-tests-to-unit-and-e2e`, which owns where a claim is
asserted.
-->

## Purpose

Defines how the machine layer obtains its machines: that a cluster is prepared once and afterwards
resumed from a cut of that preparation rather than booted again, what a resumed machine must be
indistinguishable in, that the credential the run uses belongs to the image rather than to the run,
and where the boundary lies between state a cut may carry and an observation a test must make for
itself.

## ADDED Requirements

### Requirement: The machine layer prepares a cluster once and resumes it afterwards

The machines an end-to-end test runs against SHALL be obtained from a preparation that is performed
once and cached, and resumed on every later run whose inputs are unchanged. The preparation SHALL
end only when every machine is usable: reachable over its control channel, its service manager
having reached its default target, and its network address configured. A run whose cached
preparation is absent, unusable or made from different inputs SHALL prepare the cluster again
rather than resume something else, and SHALL leave a cut behind for the next run.

#### Scenario: A prepared cluster is cached for the next run

- **WHEN** an end-to-end test's machines have been obtained
- **THEN** either they SHALL have been resumed from a cached preparation
- **AND OR** the preparation performed this run SHALL be cached under the key a later run resolves,
  so that the next run resumes it

#### Scenario: A resumed machine is usable at once

- **WHEN** the first test of a folder runs against machines that were resumed
- **THEN** every machine's service manager SHALL report its default target reached
- **AND** an ordinary command SHALL resolve on the login path without waiting for anything

#### Scenario: A resumed machine holds the address its slot was cut with

- **WHEN** the machines are read for the address each one holds
- **THEN** each machine's address SHALL be the address the plan records for it
- **AND** each machine SHALL answer to the name its slot in the cluster was cut with

### Requirement: The credential belongs to the image, not to the run

The machines SHALL authorize one credential that the image itself carries, and the run SHALL use
that credential rather than one it generated. That credential SHALL be a published test key with no
authority anywhere else, and SHALL be defined once so that the image and the run cannot come to
hold different keys. Password authentication SHALL remain refused. No machine SHALL mount a
directory of the host: a cut carries device state, so a host share cannot survive a resume, and a
credential handed in over one would bind every cut to the run that made it.

#### Scenario: The machines are reached with the key the image carries

- **WHEN** a machine is reached over the network and over its control channel
- **THEN** both SHALL be authorized by the key the image carries
- **AND** an attempt to authenticate with a password SHALL be refused

#### Scenario: No host directory is mounted in a machine

- **WHEN** a machine's mounted filesystems are read
- **THEN** none of them SHALL be a share of a host directory

### Requirement: A cut carries state, never an observation a test asserts

A cached preparation MAY carry the machines' state. It SHALL NOT carry any fact a test asserts
about an act the layer exists to observe: a delivery, an activation, a redelivery, a rollback or an
attachment SHALL be performed against the machines during the run that asserts it, and the evidence
a test reads SHALL be the report those machines and that act produced during that run.

#### Scenario: A cut carries no delivery

- **WHEN** the machines have just been obtained, whether booted this run or resumed
- **THEN** no machine SHALL report a registered entry
- **AND** no machine SHALL hold the artifact of an entry it is about to be given
