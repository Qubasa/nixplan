<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`,
`report-every-refusal-as-a-row`, `open-a-delivered-value-to-its-reader`,
`normalise-folds-and-report-refused-reads`, `hold-declaration-shape-and-fold-set-reads`,
`hold-every-stated-guarantee` and `refuse-two-entries-claiming-one-host-resource`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED, and both read against `No evaluation path raises`, which the
base states and `deliver-secrets-across-machines` and `report-every-refusal-as-a-row` restate.
That requirement is unchanged: what is added is the two mechanisms it needs to be true of a module's
half of a declaration, because the library's recovery channel catches a raise and does not catch an
index into a value of the wrong kind. `hold-every-stated-guarantee` states the same rule for the
half a deployment writes; this is the half a module writes, and its `A deployment's own declarations
are read the way a module's are` is the sentence these requirements make true in the direction it
already claims.
-->

## ADDED Requirements

### Requirement: A record the reading indexes into is checked to be a record first

A declaration of the wrong shape SHALL be a diagnostics row and SHALL NOT end the evaluation. Every
value a module or a root writes that the reading indexes into - the declaration itself, a port claim,
a slot, a capability, a generator, a generated file's record, a pin, a unit, a configuration file -
SHALL be checked to be a record before it is indexed, and a value of another kind SHALL be one error
row naming the module file and the site inside it.

The check SHALL be a check and not a recovery. The library's recovery channel reports that something
raised and cannot catch an index into a value of the wrong kind, so a reading that indexes first and
recovers afterwards SHALL NOT be taken to satisfy this requirement.

A malformed value SHALL contribute nothing to the plan: a port claim that is not a record claims no
port, a slot that is not a record declares no slot, a capability that is not a record publishes
nothing, and none of the three SHALL be defaulted into existence. A malformed value SHALL NOT be
dropped silently either, and SHALL NOT earn a row about some other condition that its absence would
have produced.

One identifier SHALL serve the whole family, because the condition is one, and the row SHALL name
which site it is about rather than leaving that to the identifier.

#### Scenario: A port claim is not a record

- **WHEN** a module declares a port claim as a number
- **THEN** the planner SHALL emit one error row naming the module file and that claim
- **AND** the entry SHALL claim no port
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A slot is not a record

- **WHEN** a module declares a slot of `uses` as something other than a record
- **THEN** the planner SHALL emit one error row naming the module file and that slot
- **AND** the member SHALL declare no such slot, so no wire for it is resolved
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A capability is not a record

- **WHEN** a module declares a capability of `provides` as something other than a record
- **THEN** the planner SHALL emit one error row naming the module file and that capability
- **AND** the capability SHALL publish nothing and be addressable by no wire
- **AND** every other entry of the deployment SHALL still be planned

#### Scenario: A module returns something other than a record

- **WHEN** a module's declaration is a value of some other kind entirely
- **THEN** the planner SHALL emit one error row naming the module file
- **AND** the row SHALL be the row an implementation returning a value of the wrong kind already
  earns for the other half of the same module
- **AND** every other entry of the deployment SHALL still be planned

### Requirement: A module's own expression is forced under the planner's recovery

A module's declaration SHALL be forced under the same recovery its implementation already gets. A
module that raises a catchable error while computing its declaration SHALL be one `module-raised` row
naming the member, and the rest of the deployment SHALL still be read.

The recovery SHALL record the declaration as the empty record, so the entry degrades through the
existing `impl-missing` row rather than through an identifier invented for this case. Two rows for
one mistake is the intended table: the first names what raised and the second names what the entry
consequently declares none of.

A failure the interpreter does not let a caller catch SHALL still propagate, and the library SHALL
keep documenting that class rather than claiming to contain it.

#### Scenario: A module raises while computing its declaration

- **WHEN** a module raises a catchable error while computing its declaration, before any
  implementation of it is applied
- **THEN** the planner SHALL emit the `module-raised` row naming the member and what was being forced
- **AND** the table SHALL also carry `impl-missing` for that member
- **AND** every other entry of the deployment SHALL still be planned
