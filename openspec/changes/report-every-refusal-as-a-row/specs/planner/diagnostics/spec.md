<!--
A delta against `planner/diagnostics`, which lives in the unarchived `implement-minimal-typed-edge`
change and was last restated by `deliver-secrets-across-machines`. This delta reads against that
restatement of `No evaluation path raises`, and against `operator/deployment-build` in
`apply-deployments-with-an-operator-command`, which owns the reading this rule hands the second kind
of fact to. The refusals the rule constrains are the `fail` of `image/read.nix:83` and the `fail` of
`flakelet/read.nix:29`; the constructor it exports is `lib/diagnostics.nix:33-50`, reachable today
only through `lib/default.nix:70-73`, which exports `render` and `mkTable` and not the constructor.
-->

## Purpose

Defines evaluation as total, and defines where a refusal is reported when the layer that needs the
fact is not the layer that holds it. A caller sees a row before it sees a raise, and one row is one
line however it was built.

## ADDED Requirements

### Requirement: One row is one line, whatever it names

The library SHALL export the constructor that builds a row, so that every producer of a row builds
it the same way, and SHALL NOT require a producer outside the library to write the six fields by
hand. A row's message, evidence and resolution SHALL each render as one line, whatever a deployment
interpolated into them, so a rendered table has one line per row and a reader of the rendered table
cannot be shown a row that was never produced.

#### Scenario: A row is built outside the library

- **WHEN** a layer above the library produces a row
- **THEN** the row SHALL be built by the library's own constructor
- **AND** it SHALL carry the same six fields, in the same shape, as a row the library produced

#### Scenario: A member name carries a line break

- **WHEN** a row names a deployment value that carries a line break
- **THEN** the rendered table SHALL still show one line for that row's message
- **AND** the row SHALL still name the value

## MODIFIED Requirements

### Requirement: No evaluation path raises

Forcing the whole result, including every plan entry, every export value and every diagnostic
record, SHALL NOT raise. The library SHALL NOT call any Nix builtin whose failure mode is to raise
in place of returning a value, and SHALL use the type library's verification entry point rather
than its assertion entry point.

A layer above the library MAY raise, and SHALL raise only for a condition an error row already
reported. A refusal about a fact the plan carries SHALL be an error row from the planner. A refusal
about a fact the realisation statement carries SHALL be an error row from the deployment build. A
realiser SHALL refuse only conditions one of those two reported, and its refusal SHALL remain as the
answer a caller reaching the realiser directly receives. A deployment the planner reports as
applicable, realised under a statement the deployment build accepted, SHALL therefore be realised
rather than refused.

#### Scenario: Every authoring mistake at once

- **WHEN** a deployment carries an unwired slot, a secret published as a value, a keyset violation,
  an arity violation and an interface mismatch simultaneously
- **THEN** deeply forcing the result SHALL succeed
- **AND** the diagnostics table SHALL contain one row per mistake

#### Scenario: A realiser refuses a condition no row reports

- **WHEN** a realiser gains a refusal that neither the planner nor the deployment build reports as
  an error row
- **THEN** the test suite SHALL fail
- **AND** the failure SHALL name the refusal and the layer that owes the row

#### Scenario: An applicable deployment is realised without a raise

- **WHEN** every placed entry of a deployment the planner reports as applicable is realised under a
  statement the deployment build accepted
- **THEN** each entry SHALL be read into an artifact
- **AND** no realiser SHALL raise

#### Scenario: A unit value no unit file has a line for

- **WHEN** a unit's environment carries a value containing a line break
- **THEN** the planner SHALL report an error row naming the entry, the unit and the variable
- **AND** the deployment SHALL be reported as inapplicable

#### Scenario: A declared closure root is not a store path

- **WHEN** an implementation declares a closure root that is not a path under the store directory
  the plan records
- **THEN** the planner SHALL report an error row naming the entry and the root
- **AND** the row SHALL name the store directory the plan was read against

#### Scenario: A declared closure root arrives by delivery

- **WHEN** an implementation declares a closure root that the plan also records as a delivered
  reference
- **THEN** the planner SHALL report an error row naming the entry and the root
- **AND** the row SHALL say that the bytes reach the units from the machine rather than from a
  closure
