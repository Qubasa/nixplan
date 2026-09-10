<!--
A delta against `tooling/repository-shape`, which lives in the unarchived
`open-the-repository-to-a-consumer` change. `tests/unit/layers.nix` already enforces path tokens, the
shown code blocks and the README literal list; what rots silently is everything else. Twenty-two
false claims were found at `9ce69dc`, among them `docs/README.md:186,196` on the shape of `varsState`
and on what it can change, contradicted by `lib/resolve.nix:562-563`; `docs/diagnostics.md` missing
`vars-program-malformed` and misstating one trigger; `docs/plan.md:269-273` contradicting itself on
whether a plan carries bytes; and `docs/tooling.md`'s counts stale by twenty-nine tests. The
mechanical cross-checks below are the ones whose subjects the tree can enumerate: row identifiers,
recorded counts and the registration lists.
-->

## Purpose

Defines the repository's documents as claims the tree can be held to, so that a statement about a row,
a field or a count fails a suite when it stops being true rather than misleading a reader.

## ADDED Requirements

### Requirement: The rows a document tabulates are the rows the tree produces

The set of row identifiers a document tabulates SHALL equal the set the library can produce. An
identifier in the tree and not the table, or in the table and not the tree, SHALL fail a suite naming
the identifier and the side it is missing from.

#### Scenario: The library gains a row

- **WHEN** the library can produce a row identifier no document tabulates
- **THEN** a suite SHALL fail naming that identifier
- **AND** the failure SHALL name the document the identifier belongs in

#### Scenario: A document tabulates a row the tree cannot produce

- **WHEN** a document tabulates an identifier the library no longer produces
- **THEN** a suite SHALL fail naming that identifier

### Requirement: A count a document records is the count the tree has

A number a document states about the tree - a count of suites, of tests, of accountable
specifications, of rows - SHALL be derived from the tree rather than written by hand, or SHALL be
checked against it. A recorded count that no longer matches SHALL fail a suite naming the document
and both numbers.

#### Scenario: A suite gains a test

- **WHEN** the number of tests a document records stops matching the tree
- **THEN** a suite SHALL fail naming the document and both numbers

### Requirement: A specification is classified exactly once

Every specification the planning record holds SHALL be classified exactly once: accounted for, or
excused with a reason that is true. A specification classified twice, and an excuse whose reason no
longer holds, SHALL each fail a suite naming the specification.

#### Scenario: A specification is both accounted for and excused

- **WHEN** one specification appears in both classifications
- **THEN** a suite SHALL fail naming that specification

#### Scenario: An excuse outlives the state it describes

- **WHEN** a specification is excused on the ground that its change is unimplemented
- **AND** that change is implemented
- **THEN** a suite SHALL fail naming that specification
