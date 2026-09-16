<!--
A delta against `tooling/test-layers`, which lives in the unarchived
`strip-planner-tests-to-unit-and-e2e` change and was last restated by
`open-the-repository-to-a-consumer` and `hold-every-stated-guarantee`. Both requirements below are
ADDED: the accounting they describe exists in code (`tests/unit/diagnostics.nix:57-207`) and in no
requirement, which is how the third realiser came to be outside it.

The conditions: `realiserFiles` (`tests/unit/diagnostics.nix:144-153`) names `image/read.nix` and
`flakelet/read.nix` and not `secrets/read.nix` or `secrets/backend.nix`, so thirteen refusals are
unaccounted; `accountingOf` (`:186`) matches a refusal to its row by `hasInfix` over a hand-written
message fragment, so a reworded message breaks the suite for a reason that is not the defect, and a
fragment that stops matching its own message is not detectable from either side.
-->

## ADDED Requirements

### Requirement: Every refusal of every realiser is accounted for

The suite SHALL account for every refusal every realiser can make, and SHALL fail naming any refusal
that is not accounted for. An account of a refusal SHALL be either the identifier of the row that
reports the same condition, or a recorded statement of why no deployment can reach it.

The set of realisers the accounting covers SHALL be derived from the realiser sources the suite is
handed rather than written out, so that a realiser is covered by existing. A realiser whose refusals
are in no account SHALL fail the suite rather than pass unexamined.

An accounted row identifier SHALL be one a producing layer actually produces. An identifier named by
an account and produced by nobody SHALL fail the suite.

#### Scenario: A realiser is added without editing the accounting

- **WHEN** a realiser source the suite is handed holds a refusal
- **THEN** that refusal SHALL be accounted for or the suite SHALL fail naming it
- **AND** no hand-written list of realiser files SHALL decide whether it is examined

#### Scenario: A refusal with no row above it fails the suite

- **WHEN** a realiser refusal names a condition no producing layer reports as a row
- **AND** the account does not record why no deployment reaches it
- **THEN** the suite SHALL fail naming the refusal and the realiser

#### Scenario: An accounted row nobody produces fails the suite

- **WHEN** an account names a row identifier that no producing layer produces
- **THEN** the suite SHALL fail naming that identifier

### Requirement: A refusal is paired with its row by identity, not by its wording

The pairing between a refusal and the row that reports the same condition SHALL be made on data the
refusal itself carries, not on the text of its message. Rewording a refusal or a row SHALL NOT change
which row a refusal is accounted by, and SHALL NOT fail the accounting.

A refusal carrying no account SHALL fail the suite in the same way as an unaccounted one, so that the
data cannot be omitted where a message fragment would previously have matched by accident.

#### Scenario: A refusal is reworded

- **WHEN** the message of a realiser refusal is rewritten without changing the condition it refuses
- **THEN** the accounting SHALL still pair it with the same row
- **AND** the suite SHALL pass without any test being edited

#### Scenario: A refusal carries no account

- **WHEN** a realiser refusal carries neither a row identifier nor a statement that no deployment
  reaches it
- **THEN** the suite SHALL fail naming the refusal
