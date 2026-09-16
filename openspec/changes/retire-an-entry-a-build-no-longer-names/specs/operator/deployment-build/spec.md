<!--
A delta against `operator/deployment-build`, whose current text is
`openspec/specs/operator/deployment-build/spec.md`. One ADDED requirement; nothing is modified.

`The manifest is the whole interface to a build` is the precondition: a consumer applies a build by
reading the plan and `manifest.json` with no Nix evaluation. That is exactly why the fact added here
has to be published rather than restated in the command - the command cannot evaluate a realiser to
ask it anything. `A statement is checked against the entry it is about` is the shape this follows:
the reading holds both halves and asks the stated realiser for the rules only it knows.

The conditions. `operator/read.nix:608-627` publishes per placed entry the realiser, the machine,
the address, the units, the identity and the artifact path, and publishes nothing about how a
machine names what a realiser put there. `operator/read.nix:180-190` and `operator/read.nix:313-323`
are the pattern this follows: the reading asks the stated realiser for its own rules
(`endpoint.pathRule`, `endpoint.recordRule`, `acceptsHostPath`) rather than testing which realiser
it is, and `flakelet/read.nix:81-86` and `image/read.nix:520-526` are where each publishes them.

The fact itself already exists in each realiser and is spent nowhere a consumer can read it.
`flakelet/read.nix:194` writes `flake_url = "plan:${image.key}"`, which is the prefix and the plan
key the endpoint answers with; `tests/e2e/delivery.py:36` keeps a second copy of that prefix equal
to it by comment, which is the defect a published fact removes. `image/read.nix:919` composes
`<name>_<version>.raw` out of `image/read.nix:208`'s name and `lib/util.nix:495-496`'s sixteen hex
digits, which is what a machine's own listing prints for an image this realiser built.

Why this is a requirement of the build rather than of the command: a machine's endpoint answers for
everything it holds, including services no deployment of this planner put there, so the command has
to be able to tell them apart, and which answers are a realiser's is a fact only that realiser
holds. A command that restated it would carry a rule whose one home is a realiser, and a widened
rule in one place and not the other retires something nobody asked to retire.
-->

## ADDED Requirements

### Requirement: The record publishes what a machine names a realiser's holdings by

For every realiser the reading is handed, the deployment record SHALL publish what a machine's own
answer names the things that realiser put there by, sufficient for a reader of the record alone to
decide whether something a machine holds came from a deployment this planner applied, and to read
out of it whatever identity the answer carries.

The published fact SHALL be read off the realiser itself, beside the name and unit rules the reading
already asks it for, and SHALL NOT be restated by the reading or by any reader of the record: a
realiser that publishes it is asked by existing, so a third realiser needs no edit to the reading
and no edit to the command. Every realiser the reading is handed SHALL publish it, and the suite
that crosses the realisers against the reading SHALL fail for one that does not.

It SHALL be published for every realiser the reading knows and not only for the ones this
deployment's entries state. A machine may hold an entry of a realiser this build no longer states -
the entry that was dropped may have been the last one of its realiser - and a record that published
only the stated realisers would make exactly that holding unfindable.

It SHALL carry no identity of any entry: it says how a name or an identity is recognised, never
which ones exist. Publishing it SHALL move no entry's identity and no artifact, because it is a
property of the realiser rather than of anything the entry records.

#### Scenario: The record publishes what a machine names a flakelet holding by

- **WHEN** a deployment whose entries state the endpoint realiser is read
- **THEN** the record SHALL publish, for that realiser, what a machine's answer names its holdings
  by
- **AND** that published value SHALL be the one the realiser writes into the artifact it builds

#### Scenario: A record publishes the fact for a realiser its entries do not state

- **WHEN** a deployment whose every entry states one realiser is read
- **THEN** the record SHALL publish the fact for that realiser
- **AND** SHALL publish it for every other realiser the reading was handed

#### Scenario: Every realiser the reading is handed publishes the fact

- **WHEN** the realisers the reading is handed are crossed against the fact the reading publishes
  for each
- **THEN** every one of them SHALL publish it
- **AND** a realiser publishing none SHALL fail that crossing rather than reach a deployment
