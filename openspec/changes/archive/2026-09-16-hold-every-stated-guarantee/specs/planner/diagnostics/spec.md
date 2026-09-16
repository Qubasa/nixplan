<!--
A delta against `planner/diagnostics`, which lives in the unarchived `implement-minimal-typed-edge`
change, was restated by `deliver-secrets-across-machines` and last by `report-every-refusal-as-a-row`.
It reads against that lineage's `No evaluation path raises`. The conditions below are the confirmed
raising sites: the deployment half of a declaration is read bare at `lib/resolve.nix:214-219`, `:274`,
`:383`, `:188`, `:203`, `:908-911` and `:916`; an export's atom type at `lib/resolve.nix:798-803`;
the refusal channel's coercion at `lib/resolve.nix:1012-1018`; and the fold row scope at
`lib/interface.nix:377-386`, which reaches only an interface the deployment attributed, while
`CLAUDE.md` says attribution is never a registry.
-->

## Purpose

Defines every malformed declaration as a row rather than an end to the evaluation, on both halves of
a deployment, and defines the channel a refusal travels through as one that cannot itself raise.

## ADDED Requirements

### Requirement: A deployment's own declarations are read the way a module's are

The half of a declaration the deployment writes - an instance, a wire, a placement, a machine, an
exposure - SHALL be read with the same tolerance as the half a module writes. A value of the wrong
type, or an absent key the reading needs, SHALL be a row naming the declaration and the field, and
the rest of the deployment SHALL still be read.

No malformed value a deployment can write SHALL end the evaluation, whether or not any module is
well formed.

#### Scenario: An instance names no module

- **WHEN** an instance is declared with no module
- **THEN** the planner SHALL produce a row naming that instance
- **AND** SHALL still plan every other instance

#### Scenario: A declaration carries the wrong type

- **WHEN** a wire, an exposure, a placement, a machine's tags or a machine's system is declared as
  something other than the shape the reading needs
- **THEN** each SHALL be a row naming the declaration and the field
- **AND** the planner SHALL still produce its table and its plan

### Requirement: An export's atom is checked where the export is used

An export SHALL be checked for the atom that types it wherever the planner uses that atom, not only
where the export is absent or unpublished. An export declaring no atom, or an atom that is not one,
SHALL be a row naming the interface and the export.

The check SHALL be reachable on the path a published export takes, so that the row can fire for a
capability a deployment actually reads.

#### Scenario: A published export declares no atom

- **WHEN** an interface declares an export with no atom and a capability publishes it
- **THEN** the planner SHALL produce a row naming the interface and the export
- **AND** the evaluation SHALL NOT end

#### Scenario: An export's atom is not an atom

- **WHEN** an export's atom is a value of some other kind
- **THEN** the planner SHALL produce a row naming the interface and the export

### Requirement: A refusal cannot break the table it travels to

The channel a module's refusal travels through SHALL accept only a refusal the planner can render,
and SHALL report anything else as a row. A refusal that is not text, or that is empty, SHALL be a row
naming the interface and what it refused, and SHALL NOT end the evaluation or produce a row with no
message.

#### Scenario: A refusal is not text

- **WHEN** a fold refuses a value with something other than text
- **THEN** the planner SHALL produce a row naming the interface and the slot
- **AND** the evaluation SHALL NOT end

#### Scenario: A refusal carries no reason

- **WHEN** a fold refuses a value with nothing
- **THEN** the row SHALL name the interface and the slot
- **AND** SHALL NOT be rendered with an empty message

### Requirement: A row about an interface does not depend on attribution

Attribution SHALL NOT decide whether an interface is checked. Every row an interface can earn - about
its declared identity, about its fold, about its exports - SHALL be reachable for an interface a
deployment did not list, because an interface absent from that list is still an interface.

#### Scenario: An unattributed interface declares a malformed identity

- **WHEN** two modules import an interface whose declared identity is malformed
- **AND** the deployment lists that interface nowhere
- **THEN** the planner SHALL produce the same row it would produce for a listed one

#### Scenario: An unattributed interface declares a fold that is not a function

- **WHEN** an interface a deployment did not list declares a fold that is not a function
- **THEN** the planner SHALL produce a row naming the file that declared it
