<!--
A delta against `openspec/specs/planner/secret-delivery/spec.md`, which owns the delivery set. The
base text is there and this file restates nothing from it.

One ADDED requirement. The row belongs here rather than in `planner/machine-platform` because the
condition is a fact about a delivery set and not about a registry: a machine stating no identity is
reported only where some value's bytes are on their way to it, and `planner/machine-platform` owns
the field, its grammar and the projection it is read in.

`A generated value is delivered to the machines that need it` (base `:46-78`) is the precondition
and is not restated: this requirement adds no machine to a set and removes none. `A value nobody
receives is stated, not implied` (base `:80-116`) is why an undeployed value earns nothing here -
its set is empty, so no machine is receiving bytes.

The conditions. `lib/plan.nix:1314-1320` is where a value entry's `delivery` is computed, and it is
the only site holding both the set and the value; `:1404-1419` is the `machine:<name>` record, built
over `usedMachines` (`:1402`), and every machine of any delivery set carries a placement - the set
is the owning member's surviving placements plus the machine of a placed reader - so `machine:<name>`
is a record the plan carries for every machine this row can name. `lib/resolve.nix:617-619` is the
projection the identity is read in.

The severity is a warning, and that is the whole decision. Every deployment in this repository and
every folder under `tests/e2e/` states no identity today, so an error would refuse all of them at
once, and a build that a warning stopped would be an error under the diagnostics discipline. The row
is a statement an operator acts on between one apply and the next, not a contradiction in the
declaration: the deployment is coherent, and what it does not say is which machine it trusts.
-->

## ADDED Requirements

### Requirement: A value delivered to a machine of unstated identity is reported

For every machine in the delivery set of a generated value, the planner SHALL report whether the
deployment stated the identity that machine's host presents. A machine that receives a value and
states no identity SHALL produce one warning row naming the machine and the values it receives.

The severity SHALL be a warning and SHALL NOT be an error. A deployment that states no identity for
any machine SHALL remain applicable and SHALL still be built, because stating an identity is a fact
a deployment may add after the bytes are already flowing, and because a row that stopped the build
would be an error in a warning's clothes.

The row SHALL be one row per machine, however many values that machine receives and however many
files each of those values declares, and its subject SHALL be a record the plan carries. It SHALL
name the values, so that an operator reading the table knows what would travel unauthenticated
rather than only that something would.

A machine whose stated identity the reading refused SHALL earn this row as well as the refusal: what
the plan carries for it is the same absence a machine that stated nothing carries, and a reader
comparing a build against a table must not find one condition reported once when two declarations
produced it.

A machine that states no identity and receives no value SHALL produce no row here, whatever entries
it runs: an artifact and an activation carry no secret of the deployment's, and the command's own
posture for such a machine is `operator/apply-command`'s.

#### Scenario: A machine in a delivery set states no host key

- **WHEN** a generated value's delivery set names a machine whose registry record states no identity
- **THEN** the planner SHALL emit one warning row naming that machine and the value
- **AND** the deployment SHALL still be applicable
- **AND** the value's delivery set SHALL be the set it was, unchanged by the row

#### Scenario: One machine receives two values

- **WHEN** two generated values of one deployment are both delivered to one machine that states no
  identity
- **THEN** the planner SHALL emit exactly one row about that machine
- **AND** the row SHALL name both values

#### Scenario: Every machine of a delivery set states a host key

- **WHEN** every machine in every delivery set of a deployment states the identity its host presents
- **THEN** the planner SHALL emit no row of this kind
- **AND** the table SHALL be the table that deployment produced before the field existed

#### Scenario: A machine that receives no value states no host key

- **WHEN** a machine runs placed entries, states no identity, and is in no value's delivery set
- **THEN** the planner SHALL emit no row of this kind about it

#### Scenario: A value nobody receives reports nobody

- **WHEN** a generator declares that no machine receives its bytes, and the machines its owner is
  placed on state no identity
- **THEN** the planner SHALL emit no row of this kind
