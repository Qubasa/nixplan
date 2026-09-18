<!--
A delta against `tooling/consumer-surface`, whose current text is
`openspec/specs/tooling/consumer-surface/spec.md`. One requirement is modified and three are added.

What this delta deliberately does not decide. It does not touch `The flake publishes every layer a
consumer builds with`: `show-a-deployment-in-a-browser` and `enroll-a-friend-outside-the-harness`
both modify that requirement, so the two outputs this change publishes - the scaffold under a name
and the vocabulary as a file - are stated as requirements of their own rather than as a third edit
to one block that three changes would then have to merge. `openspec/changes/INTEGRATION.md` records
that seam and this set's order. It does not define the six-field row a program reads:
`answer-a-machine-question-as-a-record` owns the decode that restores `evidence` and `resolution`,
and this change consumes whatever a row carries. It does not move `tests/e2e/newcomer/template/`,
and it does not touch what that folder is: `openspec/specs/tooling/test-layers/spec.md:209-229`
makes it the newcomer's route and licenses other changes to add scenarios to it, which is all this
change does there.

The conditions. The scaffold is reachable only as a path under `tests/`: `flake-module.nix:50-79`
publishes `lib`, `mkLib`, `operator` and `debug` and nothing else, `flake.nix:31-53` adds no further
output, and `README.md:48-50` and `:82-84` tell a reader to read `tests/e2e/newcomer/template/`.
That text is already held to two documents byte for byte (`tests/unit/layers.nix:389-407`, the
failure list at `:433-442`, the file list at `:1084-1090`) and to the scan that refuses a host path
in a deployment (`:715`), which is why a name and not a copy is what is missing. The one entry point
that text carries takes `pkgs` (`tests/e2e/newcomer/template/deployment/default.nix:1-5`) and its
flake hands it `nixpkgs.legacyPackages.${system}` (`tests/e2e/newcomer/template/flake.nix:18`), so
every question about the declarations is asked through a package set; `operator/default.nix:351-362`
records why an `args.nix` exists for exactly that reason, and
`tests/e2e/generated-secret/deployment/args.nix:6-10` is the one in the tree.
`tests/unit/worked.nix:6-9` is the precedent for store-path placeholders as a default with the real
package set as an argument, and `lib/util.nix:282-296` is why a placeholder has to be store-shaped.

The vocabulary is prose in `docs/authoring.md` - `:137-146`, `:252-260`, `:324-333`, `:383-408`,
`:561-568`, `:809-816` and `:894-902` - against data in `lib/atoms.nix:79-201`,
`lib/module.nix:26-35`, `:63-67`, `:84-103`, `:130-144` and `lib/resolve.nix:37-61`. The two already
disagree: `docs/authoring.md:809-818` names six registry keys and says a machine declares those six
and nothing else, while `lib/resolve.nix:52-61` admits eight. A predicate cannot be published: an
atom's validator is a function (`lib/module.nix:944`) and only its name is a value (`:1149`), which
is the limit `CLAUDE.md` records for `identityOf` and for the platform record's absent `is*`
predicates, and `lib/atoms.nix:111` puts one predicate inside the domain table itself. And three
failures end an evaluation rather than earning a row (`docs/diagnostics.md:372-386`), whose cost is
stated at `docs/authoring.md:659-662`: `applicable` forces every row of every entry, so one
unguarded read leaves nothing rendered for any entry at all.
-->

## MODIFIED Requirements

### Requirement: The example a document shows is the example a test builds

An example a document shows as a working deployment SHALL be a deployment this repository builds.
The document's text and the fixture built SHALL be one text rather than two copies kept in step by
hand, so an example that stops building fails a check that names the document. A document SHALL NOT
show as complete an example that plans without a diagnostics row and then cannot be realised.

That one text SHALL also be what this flake hands a reader who asks it for a scaffold. The scaffold
SHALL be reachable by a name this flake publishes rather than by a path inside its source, and that
name SHALL resolve to the directory the documents show and an end-to-end folder proves on a machine.
A published copy of that directory SHALL NOT exist: a second copy is the pair of texts kept in step
by hand that this requirement exists to refuse, so what is published is a name for the one
directory.

The scaffold SHALL carry two entry points over one deployment text: one that takes the consumer's
own package set and builds the deployment, and one that takes no package set and states the
deployment's arguments alone. Both SHALL be part of the text a document shows, and the deployment
SHALL be stated once, with the building entry point composing the other rather than restating it.

#### Scenario: The example a document shows is the example a folder holds

- **WHEN** a document shows the smallest deployment that works
- **THEN** its text SHALL equal the deployment an end-to-end folder holds
- **AND** a difference SHALL fail a check naming the document and the folder

#### Scenario: The documented smallest example is built

- **WHEN** the deployment that document shows is built
- **THEN** the build SHALL produce an artifact for the entry the deployment places
- **AND** a refusal SHALL NOT come from a realiser for a fact the plan reported no row about

#### Scenario: A reader is handed the scaffold by name

- **WHEN** a reader asks this flake for its scaffold by the published name, in a directory of their
  own
- **THEN** every file written SHALL be byte-equal to the committed directory the documents show
- **AND** the reader SHALL have named no path inside this repository's source

#### Scenario: The scaffold carries two entry points over one deployment

- **WHEN** the scaffold's two entry points are read
- **THEN** the one that takes no package set SHALL state the deployment's arguments
- **AND** the one that takes a package set SHALL compose it rather than state them again
- **AND** both SHALL appear in the text a document shows

## ADDED Requirements

### Requirement: The authoring vocabulary is published as data

What a deployment may declare SHALL be published as data beside the library that enforces it, as one
value a consumer can read and as one file a program can read without evaluating anything of its own.
It SHALL name every key a declaration may carry - the registry keys, the instance keys, the leaf
declaration keys, the fields an implementation is handed, the unit record's fields, a configuration
file's keys and the kinds of directory a unit may declare - and for each the name of the type its
value is held to.

It SHALL be projected from the tables the library already reads and SHALL NOT restate any of them.
The projection SHALL read each table rather than a list of names written beside it, so that a field
added to a table is described by existing rather than by a second edit, and a table that grows
without the projection growing SHALL fail a check rather than go unnoticed.

A type SHALL be published by its name and by the values it admits where those are an enumeration. A
predicate SHALL NOT be published in any form: a type's validator is a function, so it can be named
and not serialised, which is the same limit that makes a claimed identity compare type names and
that keeps the derived platform predicates out of the platform record. A table of value domains
SHALL be published as its enumerated members alone, because such a table may legitimately carry a
predicate, and serialising one ends the evaluation that would have reported it.

The published vocabulary SHALL state that it describes and does not validate. It SHALL NOT carry the
catalogue of row identifiers: that catalogue's home is the sites that produce the rows and the
document a check already crosses them against, and the rows a particular deployment earned are what
the answer to a deployment is.

#### Scenario: The published vocabulary names every key a declaration may carry

- **WHEN** the published vocabulary is read and its key sets are crossed against the library's own
  tables
- **THEN** every key each table carries SHALL appear in the vocabulary exactly once
- **AND** the vocabulary SHALL name no key no table carries
- **AND** a key added to a table and absent from the vocabulary SHALL fail that comparison

#### Scenario: A type is published by its name and not by its predicate

- **WHEN** the entry for a field whose type is a predicate over strings is read
- **THEN** it SHALL carry the type's name
- **AND** it SHALL carry no predicate, no function and no expression of the rule
- **AND** every value the published vocabulary carries SHALL be a string, a list of strings, or a
  record of those

#### Scenario: A domain that is a predicate is not published as a domain

- **WHEN** the library's table of value domains carries an enumeration and a predicate
- **THEN** the published vocabulary SHALL carry the enumeration with its members
- **AND** SHALL carry no entry for the predicate

#### Scenario: An author reads the vocabulary as one file

- **WHEN** a reader asks this flake for the vocabulary as a file
- **THEN** the file SHALL be machine-readable and SHALL decode
- **AND** its content SHALL equal the value the library publishes
- **AND** reading it SHALL require no deployment and no package set of the reader's own

### Requirement: A deployment's declarations are readable without a package set

The rows a deployment's own declarations earn SHALL be readable without instantiating a package set,
because the packages a deployment interpolates are an argument to it and the declarations are not.
An entry point that states a deployment's arguments and takes no package set SHALL therefore be part
of the published scaffold, and the rows it answers SHALL be the planner's, produced by the same
reading a build's rows come from.

Where a package is stood in for, the stand-in SHALL be a store path rather than a bare name: the
reading that recognises a store path recognises it by the store directory and the shape of a hash,
so a stand-in that is not one silently answers nothing about the family of rows that reads declared
closure roots, and an answer that is clean because nothing was recognised is worse than no answer.

The rows such a reading cannot decide SHALL be named where the scaffold is documented rather than
implied: a row about the store path a package resolves to is a row about whatever was handed in, and
the build over the consumer's own package set SHALL remain the authority for it. Both readings SHALL
answer for one deployment text, so a difference between them is the packages and never the
declarations.

#### Scenario: The rows of a deployment are read with no package set instantiated

- **WHEN** the scaffold's rows are asked for through the entry point that takes no package set
- **THEN** the answer SHALL be the planner's rows for that deployment
- **AND** the evaluation SHALL force no package set
- **AND** it SHALL cost a fraction of the evaluation that answers through the consumer's package
  set, measured by the counters an evaluation reports about itself

#### Scenario: A placeholder package is a store path

- **WHEN** the entry point that takes no package set is handed a stand-in for a package
- **THEN** the stand-in SHALL be a path under the store directory the plan is read against
- **AND** a stand-in that is not one SHALL be a defect of the scaffold rather than a clean table

#### Scenario: The two answers agree where both can decide

- **WHEN** one declaration is edited so that the planner refuses it, and the rows are read once
  through each entry point
- **THEN** both SHALL report the same row identifier and the same subject
- **AND** the scaffold as shipped SHALL be answered by both with no error row at all

### Requirement: A failure the library cannot catch is named where an author meets it

Evaluation is total for every condition the interpreter lets the library catch, and three conditions
it does not - an abort, a missing attribute, and a function called without an argument its pattern
requires - SHALL be named in one place an author is handed, each with what ends the evaluation, what
the interpreter prints, and the edit that resolves it. Naming them is the whole remedy available:
none of the three can be answered by a row, and what makes them expensive is that forcing the table
forces every entry, so one of them leaves no table at all rather than one missing row.

A condition that could be answered by a row SHALL NOT be documented in place of the row. Where such
a condition is known and the row is not this change's to add, the record SHALL name the condition,
the reading that could recognise it and the owner, so that a documented sentence is never mistaken
for the decision that a row is impossible.

The published vocabulary SHALL name that place rather than carry a copy of it, so the sentences have
one home and the data has another.

#### Scenario: Every failure that ends an evaluation is named in one place

- **WHEN** the section that documents the failures the library cannot catch is read
- **THEN** it SHALL name every such failure the tree knows of
- **AND** each SHALL carry what the interpreter prints and the edit that resolves it
- **AND** a failure known to the tree and absent from that section SHALL fail a check

#### Scenario: The published vocabulary names the section rather than copying it

- **WHEN** the published vocabulary is read for what it says about a failure that ends an evaluation
- **THEN** it SHALL name the document and the section
- **AND** it SHALL carry no sentence that document carries
