## Why

`tooling/test-layers` already requires that a test of a recorded invariant carry the sentence it
pins (`openspec/specs/tooling/test-layers/spec.md:498-537`), and the check built for it holds the
wrong subject. `pinsOf` (`tests/unit/layers.nix:876-880`) collects, per **file**, the quoted
fragments of at least 24 characters found in that file's comment blocks, and `withdrawnClaims`
(`:882-888`) fails on a collected fragment the records no longer state. Nothing in it is asked
about a counterexample. The second half of the same test's assertion,
`quotingHomes` (`:890`, read by `testACounterexampleQuotesTheClaimItPins` at `:1306-1319`), asks
only that each of the three homes quotes *something*, so one pinned sentence in a file of seventeen
attributes satisfies it for all seventeen. A counterexample whose own comment quotes nothing, or
quotes a token, is unobserved: the requirement holds for the file and is unmet for the member.

Measured, by the three constructions each home already admits. The probe file's counterexamples are
the bindings below its own `in`, which `probeNames` (`tests/unit/layers.nix:896-905`) parses as
`  <name> = ` - **17**, `tests/counterexamples/probes.nix:94` through `:393`. The evaluable home's
are the suite's own attributes, `  test<Camel> =` - **24**, `tests/unit/counterexamples.nix`. The
command's are the `def test_<snake>(` definitions `definitionOf` (`tests/unit/layers.nix:939-944`)
and `defOf` (`tests/unit/coverage.nix:182-187`) both read - **14**, `cli/counterexample_test.py`.
**55** counterexamples. `pinsOf` collects 15, 27 and 19 fragments from those three files, 61 in
all: a figure above the number of counterexamples that still says nothing about any one of them,
which is the shape of the defect rather than an accident of this tree.

Crossing the two, with each comment block attributed to the definition it sits above (or, in the
command's file, the definition whose body holds it), **48 of 55 carry a pin and 7 do not**:
`anImplementationThatRaisesIsAGuardedRow` (`tests/counterexamples/probes.nix:106-111`), whose block
quotes `A guard is not a check`, 22 characters, two short of the floor;
`aRecipeFragmentHoldingANonStringIsARow` (`:136-141`), quoting `pass through`;
`aSettingsKnobHoldingAFunctionIsARow` (`:168-175`), whose first quote is `` `lib/` never raises ``
at 19 characters while the 101-character sentence beside it is the block's *second* quote, which
`pinnedIn` (`:865-870`) deliberately does not read; `anInstanceTableOfAnotherKindIsARow`
(`:234-237`), whose block quotes nothing and rests on the sibling probe's quote in prose;
`testAPlanKeyNamesOneRecord` (`tests/unit/counterexamples.nix:327-331`), quoting nothing;
`testARowSeverityIsHeldToTheStatedDomain` (`:473-477`), quoting `error`; and
`testAClaimedIdentityDoesNotCollapseTwoStructSchemas` (`:552-557`), quoting nothing.
`cli/counterexample_test.py` is at 14 of 14.

The 25-of-55 figure this change was opened against does not hold; 7 of 55 is what the tree has, and
the audit paragraph it came from was itself measuring `pinsOf` per file. The gap is smaller than
stated and its shape is worse: the four probe blocks and three suite blocks that fail are not
authors who forgot to argue their claim - each names its record in prose and three of them quote a
sentence that is genuinely stated and merely short. They are seven places where the check is silent,
and a check that is silent for seven is silent for the eighth nobody has written yet.

## What Changes

- The check becomes **per counterexample**. Every counterexample of every home is enumerated by the
  construction that home already admits - an attribute of the probe file, a test of the evaluable
  suite, a `def test_` of the command's own file - so a counterexample is counted by existing and
  not by being listed anywhere.
- A counterexample carrying no pinned sentence is a **failure naming the home and the
  counterexample**, which is the line `withdrawnClaims` already prints for a withdrawn pin and the
  line the per-file reading cannot print at all.
- A pinned sentence the records no longer state stays a failure, unchanged: `withdrawnClaims`
  (`tests/unit/layers.nix:882-888`) and the corpus `recordFiles` (`:790-802`) names keep their
  reading, and `stated` (`:808`) keeps being asked of every collected fragment.
- The **pin rule itself does not move**: the block's first quoted fragment, split at an elision, at
  least 24 characters (`sentenceLength`, `:874`). Lowering the floor to admit
  `` `lib/` never raises `` would admit a field name; reading a block's later quotes would admit the
  rendered directives and spellings `pinnedIn`'s comment says they are. The seven blocks are
  requoted against the record instead, each to a sentence the corpus states - verified for all seven
  before this proposal was written.
- The enumeration for the evaluable home is **crossed against the suite's own attribute names**,
  handed to `tests/unit/layers.nix` the way `unitSuites` is handed to `tests/unit/coverage.nix`
  (`tests/default.nix:121`, `:135`). A name the text scan locates and the suite does not have, or
  the suite has and the scan does not locate, is a failure of its own: the failure this change
  exists to remove is a counterexample no check can see, and a regex that quietly skips one is that
  failure wearing the new check's name.
- An enumeration that found **nothing** in a home fails rather than reporting zero unpinned
  counterexamples. A per-member check whose member set is empty is the per-file check again.
- `quotingHomes` (`tests/unit/layers.nix:890`) and the `quoting` field of
  `testACounterexampleQuotesTheClaimItPins` are **deleted**, not kept beside the new reading: a home
  that quotes nothing is impossible once every counterexample in it carries a pin, so the per-file
  assertion becomes a weaker restatement of the per-member one, and two assertions of one rule is
  how the two copies of `util.admits` disagreed.
- **The families paragraph of the index loses its enumeration** (`CLAUDE.md:1082-1094`). It keeps the
  three homes and what decides which home a counterexample is in (`:1065-1080`), which is an
  argument, and stops naming members, which is a list. The argument is in `design.md` D3; the short
  form is that the list cannot be held by a check even in principle - this repository withdrew
  document-to-tree count crossings rather than excusing them (`CLAUDE.md`, Registration points) -
  and it is already wrong in a way no reader can detect: it names 27 items, or 26 if the compound
  item naming a unit name and an `env` name is counted as one, out of 55; it names none of the 14
  counterexamples of the command's own file; and one member it does name,
  `testAnOwnershipTheRenderRefusesIsARowFirst`, is stated 569 lines earlier under Realisers
  (`CLAUDE.md:513`) and appears in the paragraph not at all.
- No new suite file, no new top-level path, no new python directory, no plan field and nothing inside
  `mkPlan`: the whole change is the reading in `tests/unit/layers.nix`, one argument to it in
  `tests/default.nix`, seven comment blocks, the delta below, and the index paragraph.

## Capabilities

### New Capabilities

None. The requirement exists; its check reads the wrong subject.

### Modified Capabilities

- `tooling/test-layers`: `An invariant is held by a test asserting the claim rather than the
  behaviour` gains the account - every counterexample of every home enumerated by construction, a
  counterexample with no pinned sentence a failure naming the home and the counterexample, the
  enumeration crossed against the suite's own names, an empty enumeration a failure, and the pin
  rule and the withdrawn-pin reading unchanged.

## Impact

- `tests/unit/layers.nix`: the per-counterexample reading, the four tests that assert it, and the
  deletion of `quotingHomes` and of the `quoting` field.
- `tests/default.nix`: one argument handing `layers` the counterexample suite's attribute names.
- `tests/counterexamples/probes.nix`, `tests/unit/counterexamples.nix`: seven comment blocks
  requoted. No attribute, no assertion and no expression changes.
- `tests/unit/coverage.nix`: this change's one delta spec, `excused` then `accountable`.
- `CLAUDE.md`: the families paragraph, and the sentence recording that the account is the check.
