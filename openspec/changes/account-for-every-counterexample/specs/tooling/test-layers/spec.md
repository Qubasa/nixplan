<!--
A delta against `tooling/test-layers`, whose current text is
`openspec/specs/tooling/test-layers/spec.md`. One requirement is modified and nothing is added: the
requirement `An invariant is held by a test asserting the claim rather than the behaviour`
(`:498-537`) already states that a test of a recorded invariant carries the sentence it pins, so
what is missing is the subject of the check rather than a rule, and a second requirement beside it
would be one rule stated twice. Its two existing scenarios, `A counterexample quotes the claim it
pins` and `The command's own tests are counted`, are carried over unedited: they are answered today
by `testACounterexampleQuotesTheClaimItPins` and `testTheCommandsOwnTestsAreCounted`
(`tests/unit/layers.nix:1306`, `:1340`), and a reworded heading would rename a test for no change in
what it asserts (`openspec/specs/tooling/test-layers/spec.md:131-149`).

The conditions. `pinsOf` (`tests/unit/layers.nix:876-880`) collects, per file of
`counterexampleHomes` (`:770-774`), every fragment of at least 24 characters (`sentenceLength`,
`:874`) taken from the first quoted fragment of each comment block (`pinnedIn`, `:865-870`;
`commentBlocks`, `:819-845`), split at an elision. `withdrawnClaims` (`:882-888`) fails on a
collected fragment that `stated` (`:808`) cannot find in the corpus `recordFiles` (`:790-802`)
names, and `quotingHomes` (`:890`) answers only which of the three files quote anything at all.
Neither reading is asked about a counterexample, so the requirement is enforced for a file and
unenforced for its members.

Measured against the three homes, by the construction each already admits - `probeNames` (`:896-905`)
for the bindings below the probe file's own `in`, the suite's own attribute names for the evaluable
home, `definitionOf` (`:939-944`) for the command's file - there are 17, 24 and 14
counterexamples, 55 in all, of which 48 carry a pin and 7 do not:
`anImplementationThatRaisesIsAGuardedRow`, `aRecipeFragmentHoldingANonStringIsARow`,
`aSettingsKnobHoldingAFunctionIsARow` and `anInstanceTableOfAnotherKindIsARow` in
`tests/counterexamples/probes.nix`, and `testAPlanKeyNamesOneRecord`,
`testARowSeverityIsHeldToTheStatedDomain` and `testAClaimedIdentityDoesNotCollapseTwoStructSchemas`
in `tests/unit/counterexamples.nix`. Those seven are what the new scenarios are demonstrated to fail
on, and `proposal.md` records how each fails.

The pin rule is unchanged on purpose and is not restated as a requirement of its own: lowering the
24-character floor admits a field name, and reading a block's later quotes admits the rendered
directives and spellings `pinnedIn`'s own comment says they are. Enumeration by construction is the
idiom this capability already states for the probe file - `No kind SHALL be gated by a hand-written
list of its members` (`:36-39`) - and the requirement below states it for the pin check per
counterexample rather than per home.
-->

## MODIFIED Requirements

### Requirement: An invariant is held by a test asserting the claim rather than the behaviour

A test of an invariant this repository records SHALL assert the claim the repository states, and not
the behaviour the code exhibits. It SHALL carry the sentence it pins, so that a failure reads as the
claim that is false rather than as two values that differ, and so that a reader can find where the
claim is stated without reading the code the test exercises.

A test of that kind SHALL be red for as long as the claim is false, and being red SHALL be
information rather than a defect of the test. It SHALL NOT be relaxed to what the code does today,
SHALL NOT be marked as expected to fail, and SHALL NOT be withheld from the suite until the claim is
made true: an unasserted claim is a claim nobody notices losing.

A claim made true SHALL leave its test in place as the regression pin, under the title it already
carries, so that the test which found the defect is the test that keeps it out.

A claim withdrawn or narrowed SHALL leave its test rewritten to the narrowed claim and quoting the
narrowed sentence, rather than deleted. The narrowing SHALL be recorded where the claim is stated, so
that the sentence a test quotes is a sentence the repository still states, and a quote of a sentence
nobody states any more SHALL fail rather than pass unread.

Every test of a recorded invariant SHALL be counted as a test by the specification cross-walk,
whatever language it is written in, the tests of the operator's command included. A scenario whose
derived name names one SHALL be answered by it exactly as a scenario naming an evaluating test or a
machine test is answered, and the rule that one name SHALL NOT exist in two layers SHALL hold across
every counted kind.

The carrying of a sentence SHALL be held per test and never per file. Every test of a recorded
invariant, in every home such a test may live in, SHALL be enumerated by the check that holds this
requirement, and the enumeration SHALL use the construction that home already admits: an attribute
of the file whose members are evaluated one process each, a test of the evaluating suite, a test of
the operator's command's own test file. A test SHALL therefore be counted by existing, and no list
of these tests SHALL be maintained anywhere for the check to read. The account of which invariants
are held this way SHALL be that enumeration, and no document SHALL be required to enumerate them for
the account to be complete.

A test the enumeration names and no pinned sentence can be found for SHALL be a failure naming the
home and the test, so that the answer is the member that is unaccounted for and not the file it sits
in. A file in which some tests carry a sentence SHALL NOT thereby satisfy this requirement for the
tests in it that carry none.

A quoted fragment shorter than a sentence SHALL NOT count as the sentence a test carries: a pin is
what a reader can find the claim by, and an identifier, a field name or a severity is a token that
appears in every record. The length that separates the two, and the rule deciding which quotation of
a comment is read as the pin, SHALL have one home that every part of this check reads, so that
relaxing either is one edit in one place and is visible as such.

The enumeration SHALL be crossed against what the home itself holds wherever the home has an
authority to be crossed against - for the evaluating suite, the names of the tests it exports - and a
name held by one side and not the other SHALL be a failure naming both sides. An enumeration that
found no test in a home SHALL be a failure naming that home, and SHALL NOT be reported as a home in
which nothing is unaccounted for.

#### Scenario: A counterexample quotes the claim it pins

- **WHEN** a test asserts an invariant the repository records
- **THEN** it SHALL carry the sentence that invariant is stated in
- **AND** that sentence SHALL be one the repository still states, so a withdrawn claim fails until
  its test quotes the narrowed one
- **AND** a test asserting today's behaviour instead SHALL NOT be counted as holding the invariant

#### Scenario: The command's own tests are counted

- **WHEN** the specification cross-walk collects the tests that answer for scenarios
- **THEN** the tests written in the operator's command's own language SHALL be among them
- **AND** a scenario whose derived name names one SHALL be reported as observed
- **AND** a derived name carried by two kinds at once SHALL still fail the check naming both

#### Scenario: A counterexample carries no pinned sentence

- **WHEN** a test of a recorded invariant carries no quoted sentence of its own
- **THEN** the check SHALL fail naming the home and that test
- **AND** SHALL fail whether or not other tests of that home carry one
- **AND** a pinned sentence the records no longer state SHALL keep failing as it does today, naming
  the home and the sentence

#### Scenario: A counterexample the enumeration cannot locate

- **WHEN** a test the evaluating suite exports is not found by the enumeration, or the enumeration
  finds a name the suite does not export
- **THEN** the check SHALL fail naming the name and both sides
- **AND** the name SHALL NOT be silently left out of the tests held to the pin

#### Scenario: An enumeration that found nothing fails

- **WHEN** the enumeration finds no test in one of the homes
- **THEN** the check SHALL fail naming that home
- **AND** SHALL NOT report that home as carrying no unaccounted test

#### Scenario: A pin shorter than a sentence is not a pin

- **WHEN** a test's comment quotes only an identifier, a field name or a fragment shorter than the
  stated length
- **THEN** the check SHALL treat that test as carrying no pinned sentence and fail naming it
- **AND** a sentence of the stated length or longer that the records state SHALL satisfy the pin
- **AND** a fragment quoted after the one the rule reads as the pin SHALL NOT satisfy it
