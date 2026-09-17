<!--
A new capability. Enrollment adds no registry key, no plan field and no library rule: the whole
delta is a row convention, a generated value's handling discipline, and two refusals owned by the
coordination server that the end-to-end folder observes. The registry keys themselves stay owned
by `planner/machine-platform`; the report's exit rules stay owned by `operator/machine-report`.
This spec states only what enrollment adds on top of both, so it MODIFIES neither.
-->

## ADDED Requirements

### Requirement: An enrolled machine is an ordinary machine

Enrollment SHALL add no machine registry key and no plan field. A friend machine SHALL be declared
with the keys the registry already reads: its `address` SHALL be its mesh name, so that every URL
export built from `target.address` carries the name and whatever answers the name is the mesh's
business. After admission, every command SHALL treat the machine as any other machine of its
scope: the same preflight, the same value writes, the same copy, activation and report, with no
enrollment-aware branch anywhere in the walk.

#### Scenario: A machine is declared by its mesh name

- **WHEN** the registry declares a machine whose `address` is a mesh name and whose scope is
  `user`, and a placement selects it
- **THEN** the planner SHALL emit no row about the address
- **AND** the placed entry's `target.address` SHALL carry the mesh name

#### Scenario: A user-scope entry is applied over the mesh

- **WHEN** an admitted friend machine is declared by its mesh name and an apply runs
- **THEN** the run SHALL dial the mesh name, ask the user-scope preflight first, and activate the
  entry under the account's own manager
- **AND** the report SHALL read the machine's holdings over the same name

### Requirement: The join credential is a generated secret

The credential that admits a machine to the mesh SHALL be a generated value of the deployment: a
generator on the entry that runs the coordination server SHALL mint it single-use and expiring,
its file record SHALL state `secrecy = "secret"`, and it SHALL be delivered to no machine. The
operator SHALL read it out of the value source and hand it to the friend outside the tree. Its
bytes SHALL appear in no plan field and in no argv of any run, the discipline every secret value
already has.

#### Scenario: The credential's bytes are not in the plan

- **WHEN** the deployment declaring the credential generator is planned
- **THEN** the plan SHALL record the value's path and its delivery facts
- **AND** no plan field SHALL carry the credential's bytes

#### Scenario: No argv of a run carries the credential

- **WHEN** an apply runs against the deployment declaring the credential generator
- **THEN** no recorded argv of the run SHALL contain the credential's bytes

### Requirement: A spent credential admits nobody

The credential SHALL be minted single-use and with an expiry, so that the coordination server owns
both refusals: a second join with a spent key SHALL be refused by the server, and a key past its
expiry SHALL admit nobody. Neither refusal SHALL be this tree's to make - the tree SHALL only mint
credentials the server will refuse twice.

#### Scenario: A second join with a spent key is refused

- **WHEN** a machine joins the mesh with the credential and a second machine presents the same
  credential
- **THEN** the coordination server SHALL refuse the second join
- **AND** the server's node list SHALL name the first machine alone

#### Scenario: A key past its expiry admits nobody

- **WHEN** a machine presents the credential after its stated expiry
- **THEN** the coordination server SHALL refuse the join

### Requirement: Membership ends at the server and the report says so

The tree SHALL automate nothing about admission or expulsion: the operator's check after a join is
the coordination server's node list, and expiring a node there is how membership ends. A machine
the server expired SHALL read as unreachable in the report - an answer about reachability, never
about retirement - and a machine that never joined SHALL receive nothing from a run.

#### Scenario: An expired node reads as unreachable

- **WHEN** the operator expires an enrolled machine's node on the coordination server and a report
  runs
- **THEN** the report SHALL name the machine as one it could not ask
- **AND** the report SHALL exit non-zero

#### Scenario: A machine that never joined receives nothing

- **WHEN** a declared friend machine has not joined the mesh and an apply runs
- **THEN** the run SHALL refuse at that machine's first step, naming the machine and what the dial
  answered
- **AND** nothing SHALL have been written to any machine after the refusal
