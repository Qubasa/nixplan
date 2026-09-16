<!--
A delta against `tooling/nix-unit-suite`, whose base text lives in the unarchived
`implement-minimal-typed-edge` change; its cross-walk requirement was restated by
`strip-planner-tests-to-unit-and-e2e` and then by `clean-up-transplant-residue`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

The requirement below is ADDED and reads against `Total evaluation is checked as a property`, which
is unchanged: the suite still forces one deployment carrying every authoring mistake and still fails
where a library source file uses a raising entry point. What is added is why that pair is not
sufficient. The source half of it is substring matching for five call spellings over comment-stripped
lines, which `CLAUDE.md` records under Known bugs, and the three conditions this change turns into
rows are an index into a value of the wrong kind rather than a call: a scan cannot name them without
refusing the library's own legitimate indexes. The property therefore has to be evaluated, one
malformed declaration at a time.
-->

## ADDED Requirements

### Requirement: A malformed declaration is planned rather than scanned for

The suite SHALL plan a malformed declaration of each shape a declaration has and SHALL assert the row
the planner produces for it, so that a reading which indexes into a declaration before it checks its
shape fails the suite rather than ending it.

Each probe's assertion SHALL be over the row's identifier and subject. A probe that asserted only that
the evaluation completed SHALL NOT be taken as coverage of that shape, because a reading that dropped
the declaration silently would pass it.

The suite SHALL NOT rely on the source scan for this property. The scan matches call spellings as
substrings, and the conditions here are an index into a value the reading was handed, so a scan that
could see them would also have to refuse every index the library makes into a value it built itself.

A probe SHALL assert that the rest of the deployment was still planned, so that a reading which
recovers by abandoning the deployment is distinguishable from one which recovers by reporting the
declaration.

#### Scenario: A probe plans every malformed shape at once

- **WHEN** one deployment carries a malformed record of every shape a declaration has, a module whose
  declaration raises, a wire to an untyped capability and a hand-written binding, beside one instance
  that is well formed
- **THEN** deeply forcing the plan and the table SHALL succeed
- **AND** the table SHALL carry one row per mistake
- **AND** the well-formed instance SHALL still be planned in full

#### Scenario: A probe names the declaration it planned

- **WHEN** a probe plans one malformed declaration
- **THEN** its expectation SHALL be the row's identifier and its subject
- **AND** a reading that produced no row for that shape SHALL fail the probe naming the identifier it
  expected
