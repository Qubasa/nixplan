<!--
A delta against `operator/deployment-build`, which lives in the unarchived
`apply-deployments-with-an-operator-command` change and is implemented by `operator/`. That change
owns what building a whole deployment produces and what the record it publishes states.
`report-every-refusal-as-a-row` also modifies this capability, and lands first: it restates "An
inapplicable deployment is not built" (the tree holds the plan and the rows even when no entry is
realised) and this same requirement, for the artifact identity an entry publishes and for a machine
that declares no address. This delta restates the requirement on top of that text and adds two facts
to it.

The two facts - `operator/read.nix:231-233` already writes both - become part of what the record
promises, so that a reader may be held to them. Refusing on either is the reader's, and it is stated
in `operator/apply-command` under "The command refuses a deployment record it cannot read".
-->

## Purpose

Defines what building a whole deployment produces, so that no deployment needs code written for it.
One reading decides which entries are built, which realiser builds each, and what the result is
addressed by; one record states the answer for a consumer that evaluates no Nix; and a deployment
the planner called inapplicable is refused rather than partially realised.

## MODIFIED Requirements

### Requirement: The manifest is the whole interface to a build

A consumer of a deployment build SHALL be able to apply it by reading the plan and `manifest.json`,
with no Nix evaluation. `manifest.json` SHALL state, for each placed entry, the artifact built for
it, the realiser that built it, the machine it is placed on, that machine's address as the registry
declared it or as an absence, the units it declares, and the artifact identity the endpoint records;
and for each generated value, its files, their paths and the machines its delivery set names.

`manifest.json` SHALL also state the version of its own shape and the store directory its artifact
paths live in, so that a reader can tell a record it implements from one it does not, and a record
built against another store from one it can copy from. The version SHALL change when a reader that
implements the previous one would misread the new one.

`manifest.json` SHALL be a function of the plan and the realisation statement alone, so that reading
one deployment twice yields one answer.

#### Scenario: The manifest names every entry the plan placed

- **WHEN** the `manifest.json` of a built deployment is read
- **THEN** every placed entry of the plan SHALL appear in it exactly once
- **AND** each SHALL carry its artifact, its realiser, its machine, that machine's address as the
  registry declared it or as an absence, its unit names, and the artifact identity the endpoint
  records
- **AND** an entry whose machine declares no address SHALL be recorded with that absence and
  reported by a warning row, neither left out nor refused

#### Scenario: The manifest names every value a machine receives

- **WHEN** the deployment declares generated values
- **THEN** `manifest.json` SHALL name every value entry the plan carries, with its files and their
  paths
- **AND** each SHALL carry the delivery set the plan derived, including when that set is empty
- **AND** `manifest.json` SHALL carry no bytes of any value

#### Scenario: The same deployment is read twice

- **WHEN** one deployment is read twice with no edit between
- **THEN** the two records SHALL be equal
- **AND** the two readings SHALL name the same artifact for each key

#### Scenario: A build states the shape of its record and the store it used

- **WHEN** a deployment is built
- **THEN** the record it publishes SHALL state the version of its own shape
- **AND** SHALL state the store directory the artifact paths in it live in
- **AND** both SHALL be readable without reading any entry of the record
