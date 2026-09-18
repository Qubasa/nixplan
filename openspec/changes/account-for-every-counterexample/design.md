## Context

See `proposal.md` - Why for the defect and the measurement. What matters here: the pin reading is
five bindings in `tests/unit/layers.nix` - `commentBlocks` (`:819-845`), `quotedIn` (`:847-852`),
`pinnedIn` (`:865-870`), `sentenceLength` (`:874`) and `pinsOf` (`:876-880`) - and every one of them
takes a *file* and answers about that file. `counterexampleHomes` (`:770-774`) is the list of three
files, `withdrawnClaims` (`:882-888`) folds over it, and `quotingHomes` (`:890`) is the only thing
that reads a home's pin set for emptiness. The suite is nix-unit inside a pure evaluation, so every
reading here is a text scan over `readFile`, and nothing in it may write to the working tree.

One construction per home already exists and is used for something else: `probeNames` (`:896-905`)
parses the probe file's bindings below its own `in` for
`testAProbeIsDiscoveredRatherThanListedByHand`, and `definitionOf`/`definedIn` (`:939-947`) parse
`def test_<snake>(` out of `cli/counterexample_test.py` for `testTheCommandsOwnTestsAreCounted`.
The evaluable home has no construction in `layers.nix` at all: its authority is
`builtins.attrNames` of the suite, which `tests/default.nix:135` already computes for
`tests/unit/coverage.nix`.

## Goals / Non-Goals

Goals: the pin check reads one counterexample at a time; the member set of each home comes from the
home; a member with no pin is a line naming the member.

Non-goals: the pin rule (what a pin is), the withdrawn-pin reading, the corpus a pin is looked for
in, the three-homes taxonomy, and the document-crossing rules `hold-the-index-to-the-tree` owns.
Nothing about the attach script, `mkPlan` or any plan field is in reach: no counter of
`perf/budgets.json` is a function of a test suite's text, so this change records no baseline and
moves no budget.

## Decisions

**D1. The reading stays in `tests/unit/layers.nix`; no new suite.** Every input is already there -
the three homes, the comment-block walk, the corpus, the probe and command constructions - and the
two tests that would move to a new suite are the two this change edits. A new suite file would be a
registration in `suites` (`tests/default.nix:34-133`), a name in the coverage cross-walk and a
second place the pin rule is stated. Rejected: `tests/unit/counterexamples.nix` as the home of its
own account, because a suite asserting that its own members are pinned cannot see the other two
homes, and the probe file's members are not attributes of anything the suite can read.

**D2. A counterexample is located by pairing the home's member set with the comment block adjacent
to that member's definition.** The member set is authoritative and the block is positional: for
each name the home yields, the pin is taken from the comment block whose last line is the last
non-blank line above the definition, and - for the command's file, where the argument is inside the
body - from a block that opens after the definition and before the next one. A block owned by no
definition is a file-level or a `let`-level comment and is not a pin; there are one in
`tests/counterexamples/probes.nix` and five in `tests/unit/counterexamples.nix` today, and counting
them is how the per-file reading came to collect 61 pins for 55 counterexamples.

Two alternatives were measured rather than argued. Treating any block between two definitions as
belonging to the earlier one credits the block above a definition to its predecessor as well: that
reading answers 55 of 55 pinned, because `aRecipeFragmentHoldingANonStringIsARow` inherits the quote
belonging to `aRootReturningServicesOfAnotherKindIsARow` and six other pairs do the same, so it is
the per-file defect at member granularity. Requiring the block to be on the line immediately above,
with no blank line tolerated, makes the reading depend on a formatter: `nix fmt` is free to leave a
blank line where a comment was shortened, and `CLAUDE.md` records under Known bugs that a comment
removal has already left framing blank lines behind.

**D3. The enumeration is crossed against the suite's exported names, and `layers` is handed them.**
The import at `tests/default.nix:121`, today `{ inherit support repoSource; }`, gains one argument:
the attribute names of `suites.counterexamples`. That is `builtins.attrNames` of a suite that does
not depend on `layers`, so there is no self-reference of
the kind `tests/default.nix:123` has to disclaim for `coverage`. Handing `layers` the whole
`unitTestNames` table was rejected: it would name `layers` itself, which is a question about whether
`attrNames` forces a value that a reader should not have to answer, and `layers` needs one suite's
names.

The crossing is what makes the enumeration non-gameable. A regex over text can miss a binding -
an indentation the pattern does not admit, a name the character class does not cover - and a missed
counterexample is silence, which is the exact failure this change exists to remove. With the
crossing, a name the scan cannot locate is a line naming both sides. The probe file and the
command's file have no exported authority to cross against, which is why the non-vacuity rule is
stated for all three: an empty member set is a failure, not a clean home.

**D4. The pin rule does not move; the seven blocks are requoted.** Three of the seven quote a
sentence the records genuinely state and are merely short - `A guard is not a check` at 22
characters, `` `lib/` never raises `` at 19 - so lowering `sentenceLength` looks like the smaller
edit. It is not: the fragments it would newly admit include `error` at 5 and `pass through` at 12,
and there is no floor that admits 19 and refuses 12 for a reason a reader can state. Reading a
block's later quotes was the other candidate, and `pinnedIn`'s own comment already says what those
are - a word of a rendered directive, a spelling - so admitting them would let a counterexample pin
`Environment="<k>=<v>"` and pass. Each of the seven gains a first quote of a sentence the corpus
states; all seven candidate sentences were checked against the corpus `recordFiles` (`:790-802`)
names before this change was written, and `tasks.md` records which.

**D5. `quotingHomes` and the `quoting` field of `testACounterexampleQuotesTheClaimItPins` are
deleted.** Once every member of a home carries a pin, a home carrying none is unreachable, so the
per-file assertion is implied by the per-member one. Keeping both would put one rule in two readings
that can disagree, which is what the two copies of `util.admits` did before they were folded into
one predicate (`CLAUDE.md`, Interfaces, composition, reads).

**D6. The index's families paragraph (`CLAUDE.md:1082-1094`) loses its enumeration; the section
keeps its argument.** The paragraph is a prose list of the families the counterexamples cover. It
goes, and `:1065-1080` - the three homes and what decides which home a counterexample is in - stays,
gaining one sentence that the account is the check and where its failure is read.

The list cannot be held by a check even in principle. This repository withdrew document-to-tree
count crossings rather than excusing them: `testASuiteGainsATest`, `documentFigures` and
`treeFigures` are gone and the requirement was withdrawn (`CLAUDE.md`, Registration points), so a
figure in `docs/tooling.md` is a figure a reader maintains. An enumeration is a count with names
attached, so a check over this paragraph would reinstate exactly the class of check that was
withdrawn - a reversal of a recorded decision, not the filling of a gap.

And it is already wrong in a way no reader can detect. It names 27 items - 26 if the compound item
naming a unit name and an `env` name counts as one, and a prose enumeration having no countable
membership is itself half the argument - out of 55. It names none of the 14 counterexamples in
`cli/counterexample_test.py`, so a reader looking for the command's counterexamples in the section
about counterexamples finds the file named in a bullet and its members nowhere. And one member it
does name is not in it: `testAnOwnershipTheRenderRefusesIsARowFirst` is stated under Realisers
(`CLAUDE.md:513`), 569 lines earlier, as the counterexample a sentence about the secrets reading
rests on.

The rejected option is keeping the paragraph as prose with the check as the real account. It rots by
construction: adding a counterexample is an attribute and a comment, and the paragraph is a third
edit nothing fails on - it is 27 of 55 today for precisely that reason. Worse, a reader who finds a
counterexample absent from a list that reads as an enumeration reads the absence as a statement, and
`testAnOwnershipTheRenderRefusesIsARowFirst` shows the reading is already false. A list nothing
holds is more expensive than no list. Regenerating the list into the document was not an option to
begin with: nothing in the evaluating layer can write to the working tree (`CLAUDE.md`, Fixtures and
goldens), so a "derived" list here is hand-copied, which is the same rot with a claim of automation
on top.

What only prose can carry stays, because it is an argument and not a membership: why an uncatchable
raise cannot live in a nix-unit `expr`, why the command's counterexamples are python, and that an
attribute answering `"ok"` is kept as the regression pin.

**D7. Four new scenarios, four new tests, all nix-unit in `layers.nix`.** One test per scenario,
named by the construction (`tests/unit/coverage.nix:52-53`):
`testACounterexampleCarriesNoPinnedSentence`, `testACounterexampleTheEnumerationCannotLocate`,
`testAnEnumerationThatFoundNothingFails` and `testAPinShorterThanASentenceIsNotAPin`. Each was
checked against every test name this repository defines - 1098 across the unit suites,
`cli/`, `perf/` and `tests/e2e/` - and none of the four is taken in either layer. No pytest test is
added: the subject is a text scan of three files, which the evaluating layer answers, and the
command's file is read here as text exactly as `definedIn` already reads it.

## Risks / Trade-offs

- The block-to-member pairing is positional, so a comment written somewhere else entirely - two
  definitions up, or below the assertion - reads as no pin → the failure is the safe direction: it
  names a counterexample and asks for a quote beside it, which is where a reader of that
  counterexample looks. The seven live failures are the demonstration that the direction is the
  useful one.
- A fourth home would have to be added to `counterexampleHomes` by hand, and a home nobody
  registers is unaccounted → the same one-line registration the three homes already are, and the
  home list is asserted against the test tree by `testTheTestTreeIsRead`
  (`tests/unit/layers.nix:977-993`), which fails on a directory beside `tests/unit/` that is not in
  its expected set.
- Requoting seven comment blocks touches two files whose contents are the subject of other checks →
  no attribute, expression or assertion is edited, and the corpus check (`withdrawnClaims`) is what
  proves each new quote is a sentence the records state.
- `hold-the-index-to-the-tree` makes a backticked identifier that the index joins to a file
  crossable against that file → the rewritten section attributes no identifier to a file it is not
  in. `layers.testTheTestTreeIsRead` stays, and it resolves: `tests/unit/layers.nix:977`.

## Migration Plan

The check is written before any comment is requoted, so its first run is the demonstration: it
reports exactly the seven counterexamples `proposal.md` names, and no other. The seven blocks are
then requoted and the same run is green. The delta spec is `excused` in
`tests/unit/coverage.nix` from the first commit and moves to `accountable` in the one edit that
ticks this change's boxes, because `changeHasLanded` (`tests/unit/coverage.nix:398-404`) reads a
`- [x]` at the start of a line in `tasks.md` and `staleExcuses` (`:406-416`) fails on an excuse whose
change has started landing. There is no rollback step: every edit is a test, a comment or a
document, and reverting the commit restores the per-file reading.
