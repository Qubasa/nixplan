<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`,
`deliver-secrets-across-machines`, `deliver-a-secret-without-exposing-it`,
`report-every-refusal-as-a-row`, `open-a-delivered-value-to-its-reader`,
`normalise-folds-and-report-refused-reads`, `hold-declaration-shape-and-fold-set-reads`,
`hold-every-stated-guarantee`, `cut-a-member-and-wire-its-place` and
`refuse-two-entries-claiming-one-host-resource`. `openspec/specs/` is empty in this repository, so
the base text is read from those changes.

The requirement below is ADDED and is the general rule this change is the second instance of. It
states nothing new about a row's shape, its ordering, its deduplication or the totality of
evaluation: what it names is the one case those cannot cover, where the value a declaration is
missing would be forced by a module through a path the interpreter does not let the planner catch.
`No evaluation path raises`, which `report-every-refusal-as-a-row` last modified, already admits
that such a failure may propagate; this requirement says what the planner owes the reader instead of
letting it.
-->

## ADDED Requirements

### Requirement: A declaration a row cannot make safe is left out of every later stratum

Where a declaration's absence would be read by a module's own expression through a path the planner
cannot catch - selecting an attribute that is not there, which is neither a raise nor a failed
assertion and which no guard recovers - the planner SHALL NOT rely on reporting it alone.
It SHALL report it as an error row and SHALL additionally leave the declaration out of everything a
later stratum derives, in the stratum the row is produced in and before any plan key exists, so that
no later evaluation can reach the uncatchable path.

A row SHALL still be produced in every such case, and it SHALL name the declaration to edit rather
than the module that would have read it: the module is correct and the declaration is not.

The rule SHALL apply to a machine a placement selected whose target is incomplete, as it already
applies to a name carrying a separator the plan key grammar splits on. The row SHALL be reported for
the declaration as the deployment wrote it, whether or not anything downstream of the drop survives,
so that a check which removes its own subject does not thereby remove its own row. Where such a drop
leaves a later check with nothing to complain about, that later check SHALL NOT produce a second row
about the same mistake.

#### Scenario: The row outlives the placements it dropped

- **WHEN** every placement a machine was selected by is dropped because its target is incomplete
- **THEN** the table SHALL still carry the error row naming that machine and the registry file
- **AND** the row SHALL state how many entries the deployment placed on it

#### Scenario: One row for one machine however many placements selected it

- **WHEN** three members of two instances are all placed on one machine that declares no address
- **THEN** the table SHALL carry exactly one row about that machine

#### Scenario: The row names the keys the machine did not declare

- **WHEN** a selected machine declares neither an address nor a service manager
- **THEN** the row SHALL name both keys and the registry file
- **AND** its resolution SHALL name the edit to make in that file

#### Scenario: A dropped placement produces no module row

- **WHEN** an implementation that reads its own machine's address is placed on a machine that
  declares none
- **THEN** the table SHALL carry the registry's row and no row about the module
- **AND** deeply forcing the plan and the table SHALL succeed
