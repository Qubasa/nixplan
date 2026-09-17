<!--
A delta against `operator/deployment-build`, whose current text is
`openspec/specs/operator/deployment-build/spec.md`. One requirement is added; nothing is modified.

`A statement is checked against the entry it is about` is the shape this follows: the reading
holds the statement and the entry, obtains what a realiser accepts from the realiser itself, and
reports the crossing as a row the realiser's own refusal repeats. `operator/read.nix:180-190` and
`:313-323` are the sites where the reading already asks the stated realiser for its rules rather
than testing which realiser it is, and the published `scopes` sits beside them.

The published table lands in the same per-realiser table `retire-an-entry-a-build-no-longer-names`
introduces in `manifest.json` (`realisers`), read by contract rather than restated: the retire
change's holdings question includes a realiser on a machine only where that realiser's published
scopes admit the machine's scope, and its argv carries `--user` exactly where the scope is `user`.
A command that restated a realiser's scopes would carry a rule whose one home is the realiser, and
the two would drift the way the copied `plan:` prefix did.

The row identifier is `operator-entry-scope-unsupported`, in the row-name inventory the batch
fixes. The realisers' own statements are their capabilities' deltas: the image realiser publishes
both scopes, flakelet publishes the system scope alone.
-->

## ADDED Requirements

### Requirement: A realiser publishes the scopes it can realise

Each realiser SHALL publish the scopes it can realise beside the name and unit rules the reading
already asks it for, and the deployment record SHALL carry the published scopes in its
per-realiser table, so a reader of the record alone knows which scope a realiser's steps may be
addressed to and which argv a scoped step carries. The reading SHALL obtain the scopes from the
realiser itself and SHALL NOT restate them, so a realiser that publishes them is asked by existing
and the row and the realiser's own refusal cannot drift apart.

The reading SHALL cross the stated realiser's published scopes against the scope of the entry's
machine. An entry whose machine's scope the stated realiser's scopes exclude SHALL be an
`operator-entry-scope-unsupported` error row naming the entry, the machine's scope and the scopes
the realiser publishes, and the realiser's own refusal for the same entry SHALL carry that row's
identifier, in the idiom every realiser refusal already follows.

#### Scenario: The record publishes each realiser's scopes

- **WHEN** a deployment is read
- **THEN** the record SHALL carry, for every realiser the reading is handed, the scopes that
  realiser publishes
- **AND** the published scopes SHALL be the realiser's own statement rather than a restatement by
  the reading

#### Scenario: An entry whose stated realiser excludes its machine's scope is refused

- **WHEN** an entry placed on a machine whose scope is `user` is stated to use a realiser whose
  published scopes name `system` alone
- **THEN** the build SHALL be refused with an `operator-entry-scope-unsupported` error row
- **AND** the row SHALL name the entry, the machine's scope and the scopes the realiser publishes

#### Scenario: The realiser's own refusal carries the row's identifier

- **WHEN** a caller reaches the excluded realiser directly with the entry of the previous scenario
- **THEN** the realiser SHALL refuse
- **AND** the sentence it prints SHALL carry `operator-entry-scope-unsupported` and state the
  condition the row states
