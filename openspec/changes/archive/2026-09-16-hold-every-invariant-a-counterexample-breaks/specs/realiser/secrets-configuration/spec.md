<!--
A delta against `realiser/secrets-configuration`, whose base text lives in the unarchived
`generate-values-with-nixos-secrets` change and is restated or extended by
`report-a-secrets-refusal-as-a-row` and `keep-a-secret-out-of-a-process-table`.
`openspec/specs/` is empty in this repository, so the base text is read from those changes.

Both requirements below are ADDED. The first reads against `The conditions only this reading knows
are its own rows` and `The deploy script is rendered from the plan`, both last restated by
`report-a-secrets-refusal-as-a-row`: the second already says that an address or a path the rendered
step cannot carry as one shell word is a row of the reading, and this requirement says the same of
every other word that step carries. Evidence: `secrets/backend.nix:59-66` carries the address, the
parent directory, the path, the mode and the ownership through the word rule, while
`secrets/read.nix:490-520` and `:521-537` row about the path and the address only, `:460-462` asking
of a file's `owner`, `group` and `mode` nothing but presence. An owner the `userName` atom admits
and the rendered word rule refuses is therefore a raise out of a builder with no table above it,
which is the layering `report-a-secrets-refusal-as-a-row` exists to hold. Counterexample:
`tests/unit/counterexamples.nix:1040`.

The second reads against `A plan is readable as a generator configuration` and `The name projection
holds or the reading refuses`, both last restated by the same change: the first states "one store
entry for each generated value the plan carries", and the second states four refusals over the
projection. Evidence: `secrets/read.nix:368` selects the plan's generated values by matching the key
text, so a value whose instance or member name is empty matches no key rule and is in no store
entry, in no collision, in no row and in no delivery the external tool performs, while the plan
carries it and a unit opens its file. Counterexample: `tests/unit/counterexamples.nix:226`. The name
grammar that refuses the empty name belongs to `planner/plan-artifact` in this same change, and
holds one stratum above this reading; the requirement here is what this reading owes for a plan it
is handed, whatever a stratum above did or did not refuse.
-->

## ADDED Requirements

### Requirement: Every value the rendered step carries as a word is checked by the reading first

This reading has two halves: the half that answers a diagnostics table raises nothing, and the half
that renders the delivery step refuses with the sentence a row of that table states. Every value the
rendered step carries as a single shell word - the address it dials, the path it writes, that path's
parent directory, the mode it sets and the ownership it sets - SHALL be checked by the half that
answers the table, so that the refusal a builder makes is the second time an operator hears the
fact and never the first.

A refusal the rendering half makes SHALL always have a row above it. A word only the rendering half
examines SHALL NOT exist: such a word turns a declaration an operator can correct into a build that
stops with no table, naming a rendered fragment rather than the value, the field and the machine.

Each row SHALL name both sides of the fact it reports - the value entry, the field the word came
from, the offending text and what a rendered word admits - and SHALL be an error, because the
rendered step is the one artifact of a generation that carries these words and it cannot be rendered
without them.

The words the two halves hold SHALL be crossed against each other rather than listed twice, so that
a word a future field adds to the rendered step is checked by existing rather than by somebody
remembering this rule.

#### Scenario: An ownership the render refuses is a row first

- **WHEN** a plan carries a delivered generated file whose stated owner or group the rendered step
  cannot carry as one shell word
- **THEN** the reading SHALL report an error row naming the value, the field and the offending text
- **AND** the reading asked for its rows SHALL NOT raise
- **AND** a caller that renders the step instead SHALL be refused with the sentence that row states

#### Scenario: Every value the rendered step escapes is crossed against the reading

- **WHEN** the words the rendered step carries are crossed against the values the table-answering
  half checks
- **THEN** every word the step carries SHALL be one the table-answering half checks
- **AND** a word checked by the rendering half alone SHALL fail that crossing naming the field
- **AND** a check of the table-answering half that no rendered word corresponds to SHALL fail it too

#### Scenario: An ownership the reading admits renders

- **WHEN** a delivered file states an owner and a group the rendered word rule admits
- **THEN** the reading SHALL report no row on their account
- **AND** the rendered step SHALL carry both as single words
- **AND** the step SHALL set that ownership on the file it writes

### Requirement: Every generated value the plan carries is projected or refused by name

This reading SHALL classify a plan record by what that record holds and never by the text of the key
it sits at: a record carrying a delivery set, a file set and a generator to run is a generated
value, and a record carrying a placement or nothing of either is not. An instance may legitimately
be called after a machine and a member after the prefix a generated value's key carries, so a
classification made by matching key text answers wrongly for a plan the planner calls applicable.

Every generated value the plan carries SHALL therefore be either projected onto a name the external
contract admits or refused by a row naming it. A value that is in no store entry, in no collision
comparison, in no row and in no delivery the external tool performs SHALL NOT be possible: the plan
holds bytes a unit opens at a path, and a value the reading cannot see is a unit left to open a file
nothing writes, with no sentence anywhere naming the declaration.

Where a key's components cannot be recovered - because a component is empty, or carries the
separator the projection uses, or carries a character the contract does not admit - the refusal
SHALL name the value by its plan key, which the plan always carries, rather than by the projection
that failed.

#### Scenario: The secrets reading sees every generated value the plan carries

- **WHEN** a plan carries a generated value whose instance or member name is empty
- **THEN** the reading SHALL either project that value onto a name the contract admits or report a
  row naming it by its plan key
- **AND** the count of values the reading sees plus the values it refuses SHALL be the count of
  generated values the plan carries
- **AND** no value of the plan SHALL reach the external tool's delivery without having been seen

#### Scenario: A value entry is recognised by the delivery it records

- **WHEN** a plan carries a generated value whose key text resembles no generated value's key
- **THEN** the reading SHALL recognise it from the fields its record holds
- **AND** it SHALL contribute one store entry, or one row naming what the record cannot answer

#### Scenario: A service entry whose key names a generator contributes no store entry

- **WHEN** a plan carries a placed service entry whose member name resembles a generated value's key
- **THEN** the reading SHALL contribute no store entry for it
- **AND** SHALL report no row about it
- **AND** SHALL render no delivery step naming it
