<!--
A delta against `delivery/real-cluster`, which lives in the unarchived `prove-plan-on-real-machines`
change and is already modified by `strip-planner-tests-to-unit-and-e2e`,
`resume-e2e-machines-from-snapshots` and `deliver-secrets-across-machines`. Only *No test double is
involved* changes: until now the bytes of a delivered value were written by the test, which is the
one participant of a secret delivery that was not real. The new capability
`delivery/generated-values` in this change owns how those bytes are obtained.
-->

## MODIFIED Requirements

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
