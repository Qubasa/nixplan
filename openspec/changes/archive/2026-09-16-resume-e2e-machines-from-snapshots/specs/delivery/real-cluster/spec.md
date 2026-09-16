<!--
A delta against `delivery/real-cluster`, which lives in the unarchived
`prove-plan-on-real-machines` change (`openspec/specs/` is empty in this repository) and is already
modified by `strip-planner-tests-to-unit-and-e2e`. Only *No test double is involved* changes here:
the machines are now resumed from a cut of a prepared cluster rather than booted on every run, and
the requirement has to say which half of "real" that touches. The new capability
`tooling/machine-snapshots` in this change owns how the cut is made and what it may carry.
-->

## MODIFIED Requirements

### Requirement: No test double is involved

The run SHALL use real processes end to end: the endpoint's own binary, each machine's own service
manager and SSH server, a real store-to-store copy over the network, and real machines under a real
hypervisor. No part of the observation SHALL be produced by a stub, a fake or a recording. A
machine's *state* MAY be restored from a cut of a machine that booted, and a machine so restored
SHALL be a running kernel executing on from that state; every fact a test asserts SHALL be produced
by that machine during the run that asserts it.

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
