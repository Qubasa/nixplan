## Purpose

Defines how the planner resolves a collect slot: which services become members of a collected set, which are excluded and why, the order the set is delivered in, and the order in which `impl` is applied when one collector's answer is another collector's input.

## ADDED Requirements

### Requirement: Collected set membership comes from placement

A collect slot names no provider. The planner SHALL resolve its membership from the placement set after placement is decided, as every service placed on the machine the collecting member landed on, and SHALL NOT accept membership written by a deployment.

#### Scenario: Membership differs per machine

- **WHEN** a collector is placed on two machines and an answering service is placed on only one of them
- **THEN** the collected set on the first machine contains that service and the set on the second does not
- **AND** both sets are resolved from placement, not from any field a deployment wrote

#### Scenario: A deployment tries to enumerate members

- **WHEN** a deployment writes a wire entry or a member list aimed at a collect slot
- **THEN** the planner SHALL emit an error row naming the field
- **AND** SHALL NOT resolve the slot from it

#### Scenario: Answers with no collector placed

- **WHEN** services on a machine answer a question and no collector for that question is placed there
- **THEN** the answers SHALL be treated as unread capabilities and SHALL NOT refuse the plan
- **AND** the planner SHALL emit a warning row naming the machine and the count of unread answers

### Requirement: A collector is excluded from its own set and from any set it transitively pulls

The planner SHALL exclude a collector from the set it asks for. The planner SHALL additionally exclude an entry from a collected set when that entry transitively requires a unit contributed by the collector asking for that set. Exclusion SHALL remove the entry's answer before any ordering or stratification is computed.

#### Scenario: Reflexive exclusion

- **WHEN** a collector's own service could answer the question it asks
- **THEN** the collector SHALL NOT appear in its own collected set
- **AND** the planner SHALL emit a warning row stating that nothing describes that collector's own contribution to its own question

#### Scenario: Transitive exclusion prevents a unit cycle

- **WHEN** collector A's unit requires a unit contributed by collector B, and A also answers a question B asks whose answers cause B's unit to stop the answerer's unit
- **THEN** the planner SHALL exclude A from B's collected set
- **AND** SHALL NOT emit the stop edge from B's unit to A's unit
- **AND** SHALL emit a warning row naming both entries and stating that A's paths are read without being held still

#### Scenario: Exclusion is not a refusal

- **WHEN** transitive exclusion removes an answer whose every declaration is individually valid
- **THEN** the plan SHALL be produced
- **AND** the planner SHALL NOT emit an error row, because no authored declaration is at fault

### Requirement: A collect slot may require its set ordered

A collect slot SHALL support an `order` field. When `order` requests wire ordering, the planner SHALL deliver the collected set as a sequence consistent with the slot graph projected onto the machine's members, dependents before their dependencies. The order SHALL be deterministic across plans that place the same members.

#### Scenario: Dependents arrive first

- **WHEN** member X is wired to member Y and both are members of an ordered collected set
- **THEN** X SHALL precede Y in the delivered sequence

#### Scenario: Unrelated members get a stable tie-break

- **WHEN** two members of an ordered set have no path between them in the projected slot graph
- **THEN** the planner SHALL place them in a deterministic order
- **AND** two plans over the same placement SHALL produce byte-identical output for any artifact derived from that order

#### Scenario: A cycle in the projection refuses the plan

- **WHEN** the slot graph projected onto an ordered set contains a cycle
- **THEN** the planner SHALL emit an error row naming every member on the cycle
- **AND** the row SHALL NOT attribute fault to a single module file, wire entry or deployment field

#### Scenario: Order is not requested

- **WHEN** a collect slot does not request an order
- **THEN** the planner MAY deliver the set unordered
- **AND** a cycle in the projected slot graph SHALL NOT refuse that slot

### Requirement: impl is applied to collectors in stratified order

The planner SHALL build a per-machine answer graph whose edges run from an answering entry to the collector whose question it answered, and SHALL apply `impl` in stratified order over that graph rather than in a single pass over all collectors. Entries that collect nothing SHALL be applied first.

#### Scenario: A chain of three strata

- **WHEN** services answer a group owner, and the group owner answers a backup collector
- **THEN** the services' `impl` SHALL be applied before the group owner's
- **AND** the group owner's `impl` SHALL be applied before the backup collector's
- **AND** all three SHALL be applied after placement and allocation are decided

#### Scenario: A cycle in the answer graph refuses the plan

- **WHEN** the answer graph for a machine contains a cycle after exclusions are applied
- **THEN** the planner SHALL emit an error row naming the entries and the questions forming the cycle
- **AND** SHALL NOT apply `impl` for any entry on that cycle

#### Scenario: Stratification is deterministic

- **WHEN** two plans are produced over the same placement
- **THEN** each entry SHALL be assigned the same stratum in both

### Requirement: An empty answer carries no answer-graph edge

An answer declared as empty SHALL produce no exports, SHALL contribute no edge to the answer graph, and SHALL count as answered for the purposes of the unanswered check. The planner SHALL NOT treat two collectors exchanging empty answers as a cycle.

#### Scenario: Two collectors exchange empty answers

- **WHEN** two collectors on one machine each answer the other's question as empty
- **THEN** both entries SHALL be assigned a stratum and both `impl` functions SHALL be applied
- **AND** neither entry SHALL appear in the other's dependency set or key

#### Scenario: An empty answer is distinguished from silence

- **WHEN** one service answers a question as empty and another never declares an answer to it
- **THEN** the first SHALL appear in the answered set and SHALL NOT appear in the collected set
- **AND** the second SHALL be reported by the unanswered check at the severity the question's consequence and the deployment's policy determine

### Requirement: Answer-graph edges are per export, not per module

The planner SHALL determine set dependence per export. An export of a collector that does not read the collected set SHALL NOT contribute an answer-graph edge, even though it is produced by the same `impl` as exports that do.

#### Scenario: A collector answers another question from static values

- **WHEN** a collector contributes an answer whose every export is derived only from its own settings, package and unit references
- **THEN** that answer SHALL NOT create an edge from the collector to the entry asking that question
- **AND** the plan SHALL NOT be refused as a cycle on account of that answer

#### Scenario: A collector answers using its own collected set

- **WHEN** a collector contributes an answer any export of which reads its collected set
- **THEN** that answer SHALL create an edge, placing the collector in a later stratum than the entry asking that question

### Requirement: A staged answer emits unit edges the collector did not write

When an answer carries a reference to a unit rather than a value, the planner SHALL emit a requirement edge and an ordering edge from the reading collector's unit to the referenced unit, and SHALL mark the referenced unit as demand-started so that it is released when the last requiring unit finishes. A module SHALL NOT be able to name another module's unit.

#### Scenario: Two collectors share one referenced unit

- **WHEN** two collectors on one machine read the same staged answer
- **THEN** the planner SHALL emit one requirement edge per collector to the same unit
- **AND** the referenced unit SHALL run once for a run in which both collectors participate

#### Scenario: Ordering alone is insufficient

- **WHEN** an answer carries a unit reference
- **THEN** the planner SHALL emit a requirement edge and not only an ordering edge

#### Scenario: Release after the last reader

- **WHEN** every collector requiring a demand-started unit has finished
- **THEN** that unit SHALL be released
- **AND** the release SHALL NOT be decided by any field the answering module wrote

#### Scenario: No answers carry unit references

- **WHEN** every answer in a collected set carries values rather than unit references
- **THEN** the planner SHALL emit no requirement or ordering edges for that slot

### Requirement: A staged path must not lie inside any subject's declared paths

The planner SHALL refuse a plan in which the path published by a staged answer is contained in the declared paths of any member of the same collected set, including the staged answer's own.

#### Scenario: Staged path inside its own subject

- **WHEN** a staged answer publishes a path contained in the paths that answer declares
- **THEN** the planner SHALL emit an error row naming the answer and both paths

#### Scenario: Staged path inside a sibling's paths

- **WHEN** a staged answer publishes a path contained in another member's declared paths and that member's answer is not staged
- **THEN** the planner SHALL emit an error row naming both members
- **AND** the row SHALL state that the sibling's copy would include the staged output

### Requirement: A consistency group is delivered as one subject

When several services must be held still together, the planner SHALL support a group owner that collects a participation question from those services and contributes a single answer to the outer question on their behalf. Members SHALL NOT also answer the outer question directly. The planner SHALL check that the set of members whose direct answer a deployment silenced equals the set the group owner claimed.

#### Scenario: The group answers once

- **WHEN** two wired services participate in a group and a backup collector asks the outer question
- **THEN** the backup collector's set SHALL contain the group owner's single answer
- **AND** SHALL NOT contain either member's paths a second time

#### Scenario: A member is claimed but not silenced

- **WHEN** a group owner claims a member and the deployment has not silenced that member's direct answer to the outer question
- **THEN** the planner SHALL emit an error row naming the member and both questions
- **AND** the row SHALL state that the member's paths would be read twice, once unquiesced

#### Scenario: A member is silenced but not claimed

- **WHEN** a deployment silences a member's direct answer and no group owner claims that member
- **THEN** the planner SHALL emit an error row naming the member
- **AND** the row SHALL state that the member's paths are read by nobody

#### Scenario: Participation is stated without a group owner placed

- **WHEN** services answer the participation question and no group owner is placed on their machine
- **THEN** the planner SHALL emit a warning row and SHALL NOT refuse the plan
- **AND** the members' direct answers to the outer question SHALL remain in effect
