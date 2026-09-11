<!--
A delta against `operator/deployment-build`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `report-every-refusal-as-a-row`,
`make-an-apply-observable` and `hold-every-stated-guarantee`. `openspec/specs/` is empty in this
repository, so the base text is read from those changes.

Every requirement below is ADDED. `report-every-refusal-as-a-row` states that a realiser raises only
for a condition a row already reported, and that the reading which owns a fact is the layer that
reports it. This delta closes the one hole that statement still has: the extension field a builder
cannot render, whose account records no row id at all (`image/read.nix:108-111`) while
`lib/interface.nix:421-432` lets a module declare one and the planner calls the deployment
applicable.
-->

## ADDED Requirements

### Requirement: An extension field the stated realiser cannot render is an error row

The reading that turns a plan and a realisation statement into a deployment SHALL report, as an
error row, every extension field an entry records that the realiser stated for it has no rendering
for. The row SHALL name the entry, the unit, the extension, the field and the backend, and its
resolution SHALL name both ways out: write a field the realiser renders, or state a realiser that
renders this one.

No entry SHALL reach a realiser's own refusal for this condition without the row having been
produced first. The rule the row is read against SHALL be the realiser's own table rather than a
list restated here, so that a directive added to a realiser is a field the row stops naming without
an edit in this layer.

A deployment carrying such a row SHALL be inapplicable and SHALL build its plan and both halves of
its table and no artifact, the way every other error row of this reading behaves.

#### Scenario: A field no builder renders

- **WHEN** an entry's unit records an extension field the realiser stated for it has no rendering for
- **THEN** the reading SHALL produce an error row naming the entry, the unit, the extension, the
  field and the backend
- **AND** the deployment SHALL be inapplicable
- **AND** the build SHALL produce the plan and both halves of the table and no artifact

#### Scenario: The same field under a realiser that renders it

- **WHEN** the realisation statement names a realiser whose table carries that field
- **THEN** the reading SHALL produce no row for it
- **AND** the entry's artifact SHALL be built

#### Scenario: A field added to a realiser's table stops being reported

- **WHEN** a realiser's directive table gains a field an entry records
- **THEN** the reading SHALL stop reporting that field without this layer restating the table
- **AND** no row SHALL name a field the realiser can render
