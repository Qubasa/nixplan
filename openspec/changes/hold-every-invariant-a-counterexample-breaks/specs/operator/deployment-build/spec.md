<!--
A delta against `operator/deployment-build`, whose base text lives in the unarchived changes
`apply-deployments-with-an-operator-command`, `report-every-refusal-as-a-row`,
`make-an-apply-observable`, `hold-a-long-running-daemon`,
`refuse-a-placement-onto-an-unaddressed-machine` and `hold-every-stated-guarantee`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED. The first reads against `One reading builds every deployment`,
whose scenario `Two entries project onto one artifact name` is the collision the reading already
refuses; that requirement is unchanged, and restating it here would put a second edited copy of it
beside the one `report-every-refusal-as-a-row` holds. The second reads against `The reading is total
over a plan the planner pruned` in `hold-every-stated-guarantee`, which states that a field the plan
may omit is a row rather than a raise, and against `A statement that names nothing is a refusal` in
`report-every-refusal-as-a-row`, which states that a statement of the wrong shape is a row. Neither
is edited: what is added is that the rule covers a value of the wrong kind as well as a value that
is absent, and that the derived unit file namespace is owned here.

The conditions, all verified. `operator/read.nix:438-455` compares the projection
`<instance>-<service>@<machine>` maps onto per artifact, which carries the machine and therefore
cannot collide inside one machine, while `image/read.nix:208,243` and the flakelet reading derive a
unit file name as `<instance>-<service>-<unit>.service`, which drops both the machine and the unit
into one hyphenated string: instance `a` with member `b` declaring unit `c-main` and member `b-c`
declaring unit `main`, both placed on one machine, publish `a-b-c-main.service` twice with no row
(`tests/unit/counterexamples.nix`, `testTwoEntriesOfOneMachineDoNotShareAUnitFileName`). Both
realisers spend the same derived names, so the check belongs to the shared reading, beside the
projection and the artifact-name refusal, rather than to the planner, which derives no unit file
name and is handed no statement of which realiser renders an entry.

The realisation statement is read for no kind, so `default.realiser = 3` and `default.profile = 3`
end the reading where `operator-entry-realiser-unknown` and the profile row are owed, and a
configuration file the planner refused for its missing `mode` is recorded with `mode = null`
(`lib/module.nix:1315`), which the denial reading interpolates (`operator/read.nix:313` reaching
`image/read.nix:329`) as `cannot coerce null to a string`. The three are held by
`aRealiserStatementOfAnotherKindIsARow`, `aProfileStatementOfAnotherKindIsARow` and
`aConfigurationFileWithNoModeIsARowInTheOperatorReading` in `tests/counterexamples/probes.nix`, each
evaluated in its own process because an uncatchable raise takes the run that would report it.
-->

## ADDED Requirements

### Requirement: Two entries of one machine do not share a derived unit file name

Every unit file name a realiser derives for the entries of one machine SHALL name one entry. Where
two entries placed on one machine derive one unit file name, the reading SHALL produce one error row
naming both entries and the name they collided on, and the deployment SHALL be inapplicable: two
entries publishing one unit file name means the second replaces the first on the machine, so one
entry runs the other's unit and neither declaration is honoured.

The comparison SHALL be made over the names the realisers actually spend. A name that carries a fact
the derived name drops SHALL NOT stand in for it: an artifact name carries the machine and so cannot
collide inside one machine, while a derived unit file name joins the instance, the member and the
unit name into one string, so two members whose names and unit names differ can spell one file name.

The check SHALL belong to the reading that derives those names and already refuses two entries whose
artifact names collide, not to the planner: the planner derives no unit file name and is handed no
statement of which realiser renders an entry. One check SHALL therefore cover every realiser,
because every realiser spends the same derived names, and a realiser SHALL NOT be the first to speak
about a collision the reading can see.

#### Scenario: Two entries of one machine do not share a unit file name

- **WHEN** two members of one instance are placed on one machine, and one member's name together
  with its unit name spells the other member's name together with its unit name
- **THEN** the reading SHALL produce one error row naming both entries and the unit file name
- **AND** the deployment SHALL be inapplicable, so no artifact of it is realised
- **AND** the row SHALL be produced whichever of the two entries the reading reads first

#### Scenario: A unit file name collision is reported under either realiser

- **WHEN** one such pair of entries is stated for the realiser that emits an image, and then for the
  realiser that emits a service artifact
- **THEN** both readings SHALL produce the row, naming the same two entries and the same name
- **AND** a deployment whose derived unit file names are all distinct SHALL be refused by neither
- **AND** neither realiser's own refusal SHALL be what an operator meets first

### Requirement: Every field the reading indexes is read for its kind

Every value the reading indexes or coerces SHALL be read for its kind before it is indexed or
coerced, whether the value comes from the realisation statement beside the deployment or from a
record of the plan. A value of another kind SHALL be one error row naming the statement or the record
it was found in and the field inside it, and SHALL contribute nothing to the build.

A reading that answers a diagnostics table SHALL NOT end the evaluation instead. An evaluation error
in place of a table names neither the statement nor the field, and it takes the one thing that
explains the mistake with it, so a caller holding a statement of the wrong kind SHALL still be handed
a table naming what to edit.

A stated fact of another kind SHALL be reported the way a stated fact outside the values a realiser
implements is reported, naming the entry and what the statement held, and SHALL NOT be taken as a
fact the builder chose on the deployment's behalf. A field of a plan record the reading needs SHALL
be read for its kind as well, including where the planner already refused that record and recorded it
incompletely: such a deployment is inapplicable, so the table is the only thing left to produce.

#### Scenario: A realisation statement names a realiser of another kind

- **WHEN** a realisation statement states a realiser as a number rather than as a name
- **THEN** the reading SHALL produce one error row naming the statement and the field
- **AND** no entry SHALL be realised under a realiser chosen on the statement's behalf
- **AND** the reading SHALL still answer a table

#### Scenario: A statement carries a profile of another kind

- **WHEN** a statement for an entry realised as an image carries a confinement profile that is a
  value of another kind
- **THEN** the reading SHALL produce one error row naming the entry and the field
- **AND** the row SHALL be the one a profile outside the values the realiser implements earns
- **AND** the value SHALL index nothing the realiser holds about a profile

#### Scenario: A configuration file record carries no mode

- **WHEN** a plan carries a configuration file record that states no mode, which is what the planner
  records for a file it already refused
- **THEN** the reading SHALL produce one error row naming the entry and the field
- **AND** the reading SHALL still answer the table the deployment's other rows are in
- **AND** the absence SHALL NOT be coerced into a rendered decision about that file
