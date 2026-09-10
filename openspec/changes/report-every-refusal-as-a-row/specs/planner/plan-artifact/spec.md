<!--
A delta against `planner/plan-artifact`, which lives in the unarchived
`implement-minimal-typed-edge` change and has been extended by `emit-systemd-portable-service-images`,
`prove-plan-on-real-machines`, `declare-service-state`, `deliver-secrets-across-machines` and
`generate-values-with-nixos-secrets`. This delta adds one requirement about the entry record and
restates none. It reads against the pruning at `lib/plan.nix:22`, which removes every empty list and
empty attribute set from an entry, and against `required` at `image/read.nix:118-123`, which reads an
absent field as a fact the plan does not know. The two placed entries of the example at
`docs/README.md:52-125` are the two ordinary shapes that disagreement makes unbuildable, and the rule
stated here is the one `CLAUDE.md` already states for `delivery` and `deliveryDerivedFrom`.
-->

## Purpose

Defines what a placed entry records about the two facts a realisation cannot infer: the store paths
the entry declares and the units it runs. A field the plan omits and a field the plan records as
empty are two different answers, and a realisation is entitled to tell them apart.

## ADDED Requirements

### Requirement: A placed entry records what a realisation reads

A placed entry SHALL record the closure it declares and the units it declares, whether or not either
holds anything. An empty closure SHALL mean the entry depends on no store path, and an empty unit
set SHALL mean the entry runs nothing; an absent field SHALL mean the plan does not know, which is a
condition a realisation may refuse. A reader SHALL NOT have to write a fallback for either field,
and SHALL NOT be able to mistake either field for an absence.

The plan MAY continue to omit a field whose emptiness carries no such claim. An entry that is placed
nowhere SHALL record neither, because it declares no units for any machine and has no closure to
declare.

#### Scenario: A unit names no store path

- **WHEN** a placed entry's only unit runs a command outside the store and names no store path
- **THEN** the entry SHALL record a closure holding no root
- **AND** reading that entry as an artifact SHALL produce one, with no refusal about a field the
  entry does not record

#### Scenario: A placed service runs no unit

- **WHEN** a service is placed on a machine, publishes an export and declares no unit
- **THEN** the entry SHALL record a unit set holding no unit
- **AND** the diagnostics table SHALL carry no row about it

#### Scenario: An entry that is placed nowhere records no unit

- **WHEN** a member's placement selects no machine
- **THEN** the entry the plan carries for it SHALL record neither a closure nor a unit set
- **AND** it SHALL still record its own key, its placement and its settings
