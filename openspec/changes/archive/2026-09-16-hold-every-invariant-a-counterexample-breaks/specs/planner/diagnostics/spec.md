<!--
A delta against `planner/diagnostics`, whose base text lives in the unarchived changes
`implement-minimal-typed-edge`, `emit-systemd-portable-service-images`,
`report-every-refusal-as-a-row`, `deliver-a-secret-without-exposing-it`,
`open-a-delivered-value-to-its-reader`, `normalise-folds-and-report-refused-reads`,
`hold-declaration-shape-and-fold-set-reads`, `hold-every-stated-guarantee`,
`refuse-a-placement-onto-an-unaddressed-machine`, `refuse-a-value-a-unit-file-cannot-carry`,
`refuse-two-entries-claiming-one-host-resource`, `reserve-what-a-machine-already-holds`,
`type-a-port-claim-and-its-collision`, `cut-a-member-and-wire-its-place` and
`keep-a-declaration-from-ending-an-evaluation`. `openspec/specs/` is empty in this repository, so
the base text is read from those changes.

The added requirements read against `No evaluation path raises`, which `implement-minimal-typed-edge`
states and `report-every-refusal-as-a-row` last modified, and against `A record the reading indexes
into is checked to be a record first` in `keep-a-declaration-from-ending-an-evaluation`, which states
the rule for the record family a module writes. The first requirement below widens that rule from a
record the reading indexes to every value a declaration wrote, and the second narrows the claim
`No evaluation path raises` makes, whose own second scenario already admits a class the interpreter
does not let a caller catch: what changes is that the class is enumerated rather than left open.
`A diagnostic record has a fixed shape` and `Severity decides the apply and not the evaluation`
(`implement-minimal-typed-edge`) are the requirements the fourth and fifth read against, unchanged.
`One row is one line, whatever it names` (`report-every-refusal-as-a-row`) is restated whole under
`## MODIFIED Requirements`.

Evidence. Each declaration of the wrong kind named below ends the evaluation today and is held by a
probe in `tests/counterexamples/probes.nix`, because a nix-unit expression cannot hold an
uncatchable raise: `lib/module.nix:1431` builds `impl-missing` for a non-function `impl` and `:1457`
records the value anyway, so `lib/resolve.nix:1445` applies it; `lib/resolve.nix:1452-1457` catches
an implementation's raise and `:1461` re-forces the application outside that guard as the first
operand of its disjunction, with `:1564` forcing it a third time for the provider's exports;
`lib/resolve.nix:717` reads `root.services or { }` and `:718` calls `attrNames` on it;
`lib/plan.nix:410` concatenates a recipe's fragments; `lib/plan.nix:939-1004` serialises a settings
knob into the entry's key, where a knob holding a function answers `cannot convert a function to
JSON` with an empty table and `applicable = true`; `lib/default.nix:102-124` hands `machines`,
`instances`, `interfaces` and `storeDir` to the resolver unread; `lib/resolve.nix:1411` reads
`varsState`'s `present` with an `or` that covers an absence and not a kind; and
`lib/resolve.nix:1692` indexes an export carrying `util.isVarsFile`'s marker without the rest of
that record's fields. Verified on nix 2.34.8: `builtins.tryEval (({a}: a) { a = 1; b = 2; })`
propagates, so a module whose implementation names its arguments without `...` and a module
selecting an absent attribute of its own expression are outside any claim the library can keep.
`tests/counterexamples/probes.nix`'s `anUnwiredSlotStillLeavesATableToPrint` is the third
requirement's condition: the row fires, and forcing `applicable` forces the entry's own record, so
the table that explains the mistake is lost with the plan. The five row-construction rules are
`tests/unit/counterexamples.nix:352`, `:376`, `:404`, `:429` and `:486`: `lib/diagnostics.nix`
applies `util.oneLine` to the message, the evidence and the resolution and not to the subject,
`oneLine` replaces `\n` where `util.carriesLineBreak` reads `[\n\r]`, `isPlanKey` is a character
allowlist narrower than `util.carriesKeySeparator`'s denylist, `mkTable` repairs an out-of-grammar
subject to its last path component before it dedups, and `severities` is stated and read by nobody.
-->

## ADDED Requirements

### Requirement: Every value a declaration wrote is read for its kind

Every value a declaration wrote SHALL be read for its kind before the reading indexes into it,
coerces it, applies it or hashes it, and a value of another kind SHALL be one error row naming the
declaration and the site rather than the end of the evaluation. The rule SHALL cover the whole
surface a deployment, a root and a module write, not the record family a reading indexes into:

- a composing root's member container, which every reading below it indexes;
- a fragment of the recipe a rendered configuration file is assembled from, which the planner
  concatenates into bytes;
- a settings knob, whose resolved value reaches an entry's key as serialised text, so a knob of
  another kind ends the evaluation at the key rather than at the declaration it was written in;
- an implementation, which SHALL be recorded as none where it is not a function, so that the row a
  member with no implementation already earns is the whole answer and nothing applies the value;
- an implementation whose raise the planner's recovery already caught, which SHALL be forced once:
  no later reading of the same entry SHALL force it again outside the recovery that caught it,
  whatever order the readings are written in, and the row the recovery produced SHALL reach the
  table;
- an export carrying the marker of a generated file reference and not the rest of that record's
  fields;
- every value the planner's own entry point is handed - the machine registry, the instance table,
  the interface attribution and the store directory - and the answer a caller gives about which
  generated values exist.

A check SHALL be a check and not a recovery: the recovery channel reports that something raised and
catches neither an index into a value of the wrong kind nor a coercion of one, so a reading that
indexes first and recovers afterwards SHALL NOT be taken to satisfy this requirement.

A malformed value SHALL contribute nothing and SHALL NOT be defaulted into existence, and the
evaluation SHALL answer for the rest of the deployment: deeply forcing the plan, every entry's key
and the table SHALL succeed for every one of these declarations, and a table that is empty while a
key raises SHALL NOT be a result a caller can be handed.

#### Scenario: A root returns services of another kind

- **WHEN** a composing root returns its member container as a value of some other kind
- **THEN** the planner SHALL emit one error row naming that root
- **AND** deeply forcing the plan and the table SHALL succeed
- **AND** every other instance of the deployment SHALL still be planned

#### Scenario: A settings knob holds a function

- **WHEN** a deployment sets a knob of a placed member to a value no key can be derived from
- **THEN** the planner SHALL emit one error row naming the instance, the member and the knob
- **AND** the value SHALL NOT reach the entry's key
- **AND** forcing every key of the plan SHALL succeed and the deployment SHALL be reported as
  inapplicable

#### Scenario: An implementation that is not a function is recorded as none

- **WHEN** a module declares an implementation that is not a function
- **THEN** the planner SHALL record no implementation for that member and SHALL emit the row a
  member with none already earns
- **AND** nothing SHALL apply the declared value
- **AND** deeply forcing the result SHALL succeed

#### Scenario: A guarded implementation is forced once

- **WHEN** a module's implementation raises a catchable error and a later reading of the same entry
  asks that entry for its exports
- **THEN** the table SHALL carry the row the recovery produced
- **AND** no reading SHALL force the implementation outside that recovery
- **AND** deeply forcing the result SHALL succeed

#### Scenario: The planner is handed an argument of another kind

- **WHEN** the machine registry, the instance table, the interface attribution, the store directory
  or the answer about which generated values exist is a value of another kind
- **THEN** each SHALL be one error row naming the argument
- **AND** the planner SHALL still return both a plan and a table

### Requirement: The class the interpreter does not let a caller catch is named rather than claimed

Totality SHALL be claimed for every value a declaration wrote and SHALL NOT be claimed wider than
that. Exactly two conditions SHALL be stated as outside it, each because the interpreter offers a
caller no way to catch it:

- a module's own function signature refusing the argument record the planner hands it, the planner
  having no way to widen a signature it did not write and no way to catch the refusal;
- a module selecting an attribute of its own expression that is absent, which is neither a raise nor
  a failed assertion.

Each SHALL be documented as a failure that propagates, naming the kind of declaration that causes it
and the edit that removes it, rather than covered by a claim the library cannot keep. A module's
implementation SHALL accordingly carry a stated contract of accepting the arguments it does not name,
so that the argument record may gain a field without a module that ignores it ending an evaluation,
and that contract SHALL be part of what a module author is told rather than a convention a reader
discovers from a failure.

#### Scenario: An implementation accepts the arguments it does not name

- **WHEN** a module's implementation names some of the arguments it is handed and accepts the rest
- **THEN** the planner SHALL apply it whatever else the argument record carries
- **AND** a field added to that record later SHALL leave the module planning as it did

#### Scenario: A closed signature is named rather than contained

- **WHEN** a module's implementation names its arguments closed, or selects an absent attribute of
  its own expression
- **THEN** the failure MAY propagate
- **AND** the library's stated totality SHALL name that condition as outside it, with the contract a
  module is held to, rather than claiming to contain it

### Requirement: The table and the verdict survive an entry whose record raises

The diagnostics table and the applicability verdict SHALL be answerable for every input, including
an input one of whose plan records cannot be forced. Neither SHALL be computed by forcing a plan
record: the verdict SHALL be a function of the rows alone, and a row SHALL be reachable without the
entry it is about being forced. A deployment carrying a condition outside the stated totality SHALL
therefore still render the table that explains it, and the failure SHALL be confined to the plan
record holding the value it is about, so that a reader is told which declaration to edit rather than
handed a plan and a table that both end.

#### Scenario: A table is printable where one plan record raises

- **WHEN** one entry's plan record cannot be forced because a module read a value the planner cannot
  make safe
- **THEN** the table and the verdict SHALL still be answerable and SHALL render
- **AND** the table SHALL carry the row naming the declaration that caused it
- **AND** every other entry's record SHALL still be readable

#### Scenario: An unwired slot read by its own module leaves a table to print

- **WHEN** a module reads a slot nobody wired, so forcing that entry's own record ends in a failure
  the planner cannot catch
- **THEN** the table SHALL carry the row about the unwired slot
- **AND** the verdict SHALL report the deployment as inapplicable
- **AND** both SHALL be answerable without that entry's record being forced

### Requirement: A row's subject is the identity the plan already uses

A row's subject SHALL be a plan key the planner built, a path relative to the deployment root, or an
issue identifier, and the rule that accepts one SHALL be stated over those three rather than over the
characters they happen to contain. It SHALL NOT be an allowlist of characters narrower than the
grammar the names entering a key are held to: that grammar refuses the separators a key's own
structure uses and admits every other character, so a name the key grammar admits, the key the
planner built from it and a row subjected to that key are all legal, and a subject rule refusing the
key would turn a table carrying warnings and no error into a refusal to apply. A subject the rule
does refuse SHALL be reported as such, and the reporting SHALL NOT itself be an error that decides
applicability for a deployment whose own rows are warnings.

No repair of a subject SHALL turn two rows about two declarations into one row. Where a subject is
repaired, the repair SHALL NOT be what deduplication compares: two facts SHALL remain two rows even
where their repaired subjects agree, and a reader SHALL be told about the second declaration.

#### Scenario: A name the key grammar admits is not refused by the subject rule

- **WHEN** a deployment names an instance with a character the key grammar admits and earns one
  warning row and no error
- **THEN** the subject rule SHALL accept the plan key the planner built from that name
- **AND** the table SHALL carry that warning row and no row about the subject
- **AND** the deployment SHALL be reported as applicable

#### Scenario: Two module files sharing a basename keep two rows

- **WHEN** two members declared in two files whose names agree in their last component each earn the
  same kind of row
- **THEN** the table SHALL carry one row per member
- **AND** each row SHALL name the file its member was declared in
- **AND** neither row SHALL be dropped as a duplicate of the other

### Requirement: A row's severity is a closed domain

A row SHALL carry one of exactly the two severities the capability states, and the domain SHALL be
closed where a row is built rather than where a row is read. A value outside it SHALL be reported as
such, naming the producer and the value it carried, and SHALL NOT travel in the table as a severity
of its own.

A reading SHALL NOT be the thing that decides what an off-domain severity means: the fact that a row
carries a severity nobody declared SHALL NOT be inferable only by a reader comparing the value
against a spelling it knows, and such a row SHALL neither decide applicability by accident nor be
counted as a warning because it is not the error spelling. An off-domain severity SHALL NOT be a way
for a producer to put text a reader trusts into the table either: the row SHALL still render as one
line per field.

#### Scenario: A row severity is held to the stated domain

- **WHEN** a row is built with a severity outside the two the capability states
- **THEN** the planner SHALL report that value as such, naming the producer
- **AND** the row SHALL NOT be counted as a warning on the grounds that it is not the error spelling
- **AND** the rendered table SHALL carry one line per field of that row

## MODIFIED Requirements

### Requirement: One row is one line, whatever it names

The library SHALL export the constructor that builds a row, so that every producer of a row builds
it the same way, and SHALL NOT require a producer outside the library to write the six fields by
hand. Every field of a row a reader is shown - its subject as well as its message, its evidence and
its resolution - SHALL render as one line, whatever a deployment, a module or an interface
interpolated into it, so a rendered table has one line per field of one row and a reader of the
rendered table cannot be shown a row that was never produced.

A line break SHALL mean every character the library counts as one, the carriage return as well as
the newline, and one definition SHALL serve both the scan that asks whether a value carries a line
break and the repair that removes one. A refusal a module states through the one channel it has SHALL
therefore be unable to rewrite the subject, the severity or the message a reader is shown, whatever
text it carries.

#### Scenario: A row is built outside the library

- **WHEN** a layer above the library produces a row
- **THEN** the row SHALL be built by the library's own constructor
- **AND** it SHALL carry the same six fields, in the same shape, as a row the library produced

#### Scenario: A member name carries a line break

- **WHEN** a row names a deployment value that carries a line break
- **THEN** the rendered table SHALL still show one line for that row's message
- **AND** the row SHALL still name the value

#### Scenario: A subject carrying a line break renders one line per row

- **WHEN** a deployment names an instance with a name carrying a line break and the row about it is
  subjected to that instance's plan key
- **THEN** the rendered table SHALL carry one block per row and one line per field of it
- **AND** the row SHALL still name the declaration

#### Scenario: A fold refusal cannot carry a carriage return

- **WHEN** an interface's fold refuses a value with text carrying a carriage return
- **THEN** the row the planner builds from that refusal SHALL carry no line break in any field
- **AND** the rendered table SHALL show no line the planner did not produce
