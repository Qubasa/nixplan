## 1. Registration and order, before anything is edited

- [ ] 1.1 `git add` every file of this change before evaluating anything: `proposal.md`, `design.md`,
  `tasks.md` and `specs/tooling/repository-shape/spec.md`. The flake does not see an untracked path,
  and the coverage cross-walk then reports the spec it cannot read rather than the file that was not
  staged. Verify with `nix eval --json '.#debug.failures'` returning something other than a
  file-not-found error.
- [ ] 1.2 Register this change's one delta spec in `excused` in `tests/unit/coverage.nix`, as
  `changes/hold-the-index-to-the-tree/specs/tooling/repository-shape/spec.md`, with the reason in the
  shape `excuseNamesChange` (`tests/unit/coverage.nix:389-394`) matches: "an unimplemented change: no
  task of hold-the-index-to-the-tree has been done, so nothing in this package claims to satisfy it
  yet". Verify with `nix build .#checks.x86_64-linux.planner-tests`: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [ ] 1.3 **Leave every checkbox of this file unticked for as long as that excuse stands.**
  `changeHasLanded` (`tests/unit/coverage.nix:398-404`) reads this file for one anchored `- [x]` line
  and `staleExcuses` (`:406-416`) fails the suite for an excuse whose change has landed, so ticking
  one box early turns the suite red for a reason that reads like a missing test. The excuse and the
  boxes move in the one edit of task 9.1. Verify by ticking nothing until then, and by
  `nix build .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [ ] 1.4 Record the perf baseline before anything else: `bash perf/measure.sh`, nine counters into
  this change's working notes. Nothing this change edits is evaluated by `perf/eval.nix` - the whole
  of it is `tests/unit/`, `tests/unit/support.nix` and two documents - so every counter is expected
  to be unmoved, and the baseline is what turns "expected" into evidence. The gate is two-sided with
  a 0.15 margin, so a counter that moves is a task here and never a re-recorded budget.

## 2. One reading of the ticked marker, in one home

- [ ] 2.1 Move the anchored marker reading into `tests/unit/support.nix` as a function of a text,
  answering both questions about one task record: whether any line is ticked, and whether any line is
  unticked. It takes no root - the caller reads the file - so `support.nix`'s own argument set
  (`tests/unit/support.nix:1-7`) does not change. Anchor the match at the start of a line, the way
  `tests/unit/coverage.nix:402` does, because four of the production changes name `- [x]` in prose.
  Verify with 2.2.
- [ ] 2.2 Rewrite `changeHasLanded` (`tests/unit/coverage.nix:398-404`) to call it, keeping its own
  name and its own meaning - at least one ticked line, which is what an excuse expires on - and
  leaving `staleExcuses` untouched. Verify with `nix build .#checks.x86_64-linux.planner-tests`:
  `testAnExcuseOutlivesTheStateItDescribes` (`tests/unit/coverage.nix:531-536`) asserts both an empty
  tree-side list and the synthetic half, `changeHasLanded "answer-whether-a-machine-is-current"` being
  true, so a reading that lost its anchor or its meaning fails there.

## 3. The root documents join the path scan

- [ ] 3.1 In `tests/unit/layers.nix`, add the document list beside `scannedFiles` (`:308-312`),
  derived and not written out: `filesIn repoRoot` filtered to `*.md`, which is `CLAUDE.md`,
  `README.md` and `LICENSE.md` today and a new root document tomorrow by existing. Feed it to
  `repoNamedPaths` (`:316`) through `rootedPathsOf` (`:184-190`) **only**, never `namedPathsOf`
  (`:171-182`): a document at the root names a path as the repository sees it, and a `./` or `../`
  fragment in it is a quotation of another file's expression - `CLAUDE.md:552`'s `../lib` is what
  `operator/default.nix` is handed, and `README.md:73`'s `./deployment` is a line of a consumer's own
  flake. Verify with 3.3.
- [ ] 3.2 In the same file, resolve a rooted token that names a capability of the planning record as
  that capability: a token is resolved where `openspec/specs/<token>/spec.md` exists or where a delta
  `openspec/changes/*/specs/<token>/spec.md` does. `operator` is the only top-level entry that is
  also a capability area, because `firstSegment` (`:117-122`) has to be a top-level entry, so this is
  two `pathExists` calls on the candidates `repoTokens` (`:126`) already produced. Do not add an
  exemption list: a list is what the next capability of that area is left out of. Verify with 3.3.
- [ ] 3.3 Add to `tests/unit/layers.nix` the three new nix-unit tests of the MODIFIED requirement,
  which is the only layer they land in because each is a decision of a pure evaluation over text:
  `testTheIndexOfInvariantsNamesAPathThatIsNotThere`,
  `testADocumentQuotesAPathRelativeToAnotherFile` and
  `testACapabilityNameIsNotADirectoryThatIsMissing`. Write the reading so a scenario can hand it a
  synthetic document text and the tree-side assertion is the same function over the real files; the
  first test asserts both, the real documents naming no unresolved path and a synthetic document
  naming `lib/nothing-here` producing a row that carries the document, the line and the token.
  **What this catches today: `CLAUDE.md:711`'s `operator/machine-identity`**, which names neither a
  path nor a capability - `openspec/specs/operator/machine-identity/` does not exist - while
  `CLAUDE.md:714`'s `operator/apply-command` resolves as a capability and earns nothing. Of the
  audit's five findings this check catches none: the sixth, the bare `design.md` at `CLAUDE.md:387`,
  is no path token at all, which task 6.6 states rather than works around. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [ ] 3.4 Extend `testARecordIsReadAsHistory` (`tests/unit/layers.nix:1093-1104`) to assert the new
  document list holds nothing under `openspec/` either, so the exemption is asserted over the whole
  scanned set rather than over the two lists that existed when it was written. The status crossing of
  task group 5 reads a `tasks.md` as the record of its own change and not as a file whose paths must
  resolve, and this is where that stays true. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.

## 4. A code statement a document quotes

- [ ] 4.1 In `tests/unit/layers.nix`, add the quoted-assignment reading: over every `*.md` of the
  root and of `docs/`, a backticked fragment of one line that reads as a name, `=` and a value, and
  that carries no placeholder or elision, must appear verbatim in the quotation corpus. The corpus is
  the files the path scan reads minus the documents themselves, walked once per fragment with
  `replaceStrings` the way `stated` (`:808`) walks its own. Do **not** reuse `statedTexts`
  (`:804`) or `statedIn` (`:781-788`): that corpus excludes `tests/`, so it cannot see
  `tests/e2e/guest.nix` at all, and it replaces `#` with a space, which would let a fragment match
  across a comment boundary. **What this catches today: finding 1**, `CLAUDE.md:871`'s
  `additionalSpace = "2048M"` against `tests/e2e/guest.nix:434`'s `additionalSpace = "6144M"`. The
  elision gate is what excuses `docs/authoring.md:124`'s `fold = korora.fold "<name>" (set: …)`, the
  one other fragment the reading finds across all twelve documents. Verify with 4.3.
- [ ] 4.2 In the same file, add the attributed-identifier reading: four idioms held in one stated
  table so adding one is adding a row - `` `<identifier>` in `<file>` ``,
  `` `<identifier>` of `<file>` ``, `` `<file>`'s `<identifier>` `` and
  `` `<file>` has a `<identifier>` `` - read only where the file operand names a file or directory of
  this repository, which keeps `docs/operator.md:1066`'s `` `ConnectTimeout` in `NIX_SSHOPTS` `` out.
  Read the named file's **code**, dropping lines whose first non-space character is `#` as
  `tests/unit/diagnostics.nix` already does, and match a whole identifier, bounded by characters
  outside `[A-Za-z0-9_'-]`. Both properties are load-bearing and were measured as failures of the
  naive reading: `image/default.nix` says "quoted" in two comments (`:23`, `:194`), so a whole-text
  reading reports the false claim as true, and `double-quoted` contains the same letters.
  **What this catches today: `CLAUDE.md:460`**, "`image/default.nix` has a `quoted` of its own for
  the messages", where that file binds `escapedWord` (`image/default.nix:197`) over
  `lib/util.nix:193`'s `shellQuote` - 30 attributions across the twelve documents, 29 of which hold.
  **Finding 2 is what this check is for and not what it catches**: `CLAUDE.md:817` names
  `extraPythonPaths` and `pythonRoot`, which exist nowhere in the tree, and attributes them to no
  file, so nothing crossed them. Demonstrate the failure by writing that claim in a checked idiom -
  `` `extraPythonPaths` in `treefmt.nix` `` - observing the suite name the identifier and the file,
  and reverting to the corrected sentence task 6.2 writes. Verify with 4.3.
- [ ] 4.3 Add to `tests/unit/layers.nix` the six nix-unit tests of the first ADDED requirement, which
  is the only layer they land in because each is a text reading inside a pure evaluation:
  `testAQuotedAssignmentTheTreeNoLongerHolds`, `testAnIllustrationIsNotAQuotedStatement`,
  `testAnIdentifierAttributedToAFileThatDoesNotHoldIt`,
  `testAnIdentifierTheNamedFileOnlyMentionsInProse`, `testAnIdentifierADocumentAttributesToNoFile`
  and `testAFigureAReaderMaintainsIsNotCrossed`. Each asserts the real documents produce no row and a
  synthetic document produces the row the scenario names, which is what makes the negative cases -
  the illustration, the unattributed identifier, the figure - assertions rather than restatements of
  an empty list. `testAnIdentifierTheNamedFileOnlyMentionsInProse` hands the reading a document
  attributing an identifier to a file that names it in a comment only, and asserts the row is still
  produced. Verify with `nix build .#checks.x86_64-linux.planner-tests`.

## 5. A change's status word

- [ ] 5.1 In `tests/unit/layers.nix`, add the status crossing: for each directory under
  `openspec/changes/` other than `archive/`, derive the word from the change's own `tasks.md` through
  the reading of task 2.1 - `landed` where at least one line is ticked and none is unticked, `open`
  otherwise, a change with no `tasks.md` deriving `open` - and compare it with the word the documents
  state. A word is read as a claim about a change where it stands within a bounded token distance of
  that change's name, backticked or inside its `openspec/changes/<name>` path, with no sentence end
  between them. Cross `open` and `landed` and nothing else: `parked`, `struck` and `narrowed` are
  decisions no `tasks.md` holds, and `CLAUDE.md:703`'s "Eight changes are open." is a figure whose
  neighbouring change name is one token away and which says nothing about it, which is what the
  sentence-end gate is for. Verify with 5.2.
- [ ] 5.2 Add to `tests/unit/layers.nix` the four nix-unit tests of the second ADDED requirement,
  which is the only layer they land in because the record and the document are both read by
  evaluation: `testAChangeTheDocumentCallsOpenHasLanded`,
  `testAChangeTheDocumentCallsLandedHasWorkLeft`, `testAStatusWordTheRecordCannotDerive` and
  `testATaskRecordNamesTheMarkerInProse`. The first two hand the reading a synthetic document and a
  synthetic task record, so each fails on the condition it names without waiting for the tree to
  drift; `testATaskRecordNamesTheMarkerInProse` asserts a record writing the marker mid-sentence
  derives "no task ticked" and that the document-side and excuse-side answers are that same fact.
  **What this catches today: finding 3**, `CLAUDE.md:53-54` calling `run-an-entry-without-root` "the
  open change" against a `tasks.md` of 27 ticked boxes and none unticked, while `CLAUDE.md:716-719`
  calls it landed - eight readable claims in the index, seven of which agree with the record. Verify
  with `nix build .#checks.x86_64-linux.planner-tests`.

## 6. The index is corrected

- [ ] 6.1 `CLAUDE.md:871`: `` `additionalSpace = "2048M"` is room for the two delivered artifacts and
  their closures `` becomes `` `additionalSpace = "6144M"` is room for the two delivered artifacts and
  their closures and for the nixpkgs checkout and build inputs a machine of `tests/e2e/newcomer/`
  fetches for itself ``, which is what `tests/e2e/guest.nix:430-434` states and what the index's own
  figure at `:958` already said. Caught by 4.1. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`.
- [ ] 6.2 `CLAUDE.md:816-819`: delete `extraPythonPaths` and `pythonRoot`, which name nothing in the
  tree, and state the mechanism `treefmt.nix` actually spends - `mypy_path` in `treefmt.nix`, written
  into a `mypy.ini` (`treefmt.nix:55-57`) and holding the `cli` store path, because `PYTHONPATH`
  makes mypy read an importable directory as an installed distribution and then demand a `py.typed`
  marker, and because a relative path would be read from the run's directory rather than from the
  configuration (`treefmt.nix:50-54`). Write it in one of the four checked idioms, which is what
  makes the claim crossable at all. Caught by 4.2 only once it is attributed, per 4.2's
  demonstration. Verify with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 6.3 `CLAUDE.md:53-54`: "The open change `run-an-entry-without-root` lands the substrate"
  becomes a sentence whose status word is the one the record derives - `run-an-entry-without-root`
  has landed, all 27 boxes ticked - so it reads "`run-an-entry-without-root`, landed, is the
  substrate; a later change, named there as a non-goal, owns the exported bundle for a machine no run
  can dial." Caught by 5.1. Verify with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 6.4 `CLAUDE.md:893-896`: "builds the same deployment twice" becomes "builds the same deployment
  four times", and the sentence names what the other two are for, because
  `tests/e2e/portable-image/test_portable_image.py:17-24` states four - `changed`, attached by
  nothing, `retired`, the deployment without `beacon`, and `probed`, whose probe refuses. **No new
  check catches this**: "twice" is a count in prose, which is precisely the figure the boundary of
  this change leaves to a reader, and crossing it would need a check that counts a folder's builds.
  Verify by reading the two texts against each other.
- [ ] 6.5 `CLAUDE.md:856-858`: the derived-default argument's anchor moves from `lib/compose.nix:30-31`
  - which is the `]` and `in` closing `serviceKeys` (`lib/compose.nix:25-31`) - to `lib/compose.nix:42`,
  where `settings = settingsOf { inherit name defaults fixed; }` is handed a name, the declared
  defaults and the fixed settings and no instance, so the claim itself holds and only the pointer had
  rotted. **No new check catches this**: a `path:line` pointer states no content, so nothing but a
  reader can say whether the line still carries the claim, and a crossing for it would be a check
  that cannot fail on the condition it names
  (`openspec/specs/tooling/test-layers/spec.md:264-273`). Verify by reading `lib/compose.nix:42`.
- [ ] 6.6 `CLAUDE.md:387` and `tests/unit/platform.nix:354-356`: the bare `design.md` D7 becomes
  `openspec/changes/archive/2026-09-16-emit-systemd-portable-service-images/design.md:116-131`, which
  is where the `_withoutFunctions` measurement is written - two functions surviving at
  `parsed.abi.assertions[0].assertion` and `[1].assertion`, and the record being 115 attributes wide.
  Both sites, because the index's pointer and the guard's own comment are the same claim and a
  corrected one beside an uncorrected one is the drift this change is about. **No new check catches
  either**: a bare filename is no path token, and 58 of the 66 filename-shaped backticked tokens of
  the index name a file of a directory their sentence names, so a bare-filename reading would be
  almost entirely false positives. The corrected pointers are repository-rooted and the existing scan
  then holds them. Verify with `nix build .#checks.x86_64-linux.planner-tests`, which reads
  `tests/unit/platform.nix` under the path scan already.
- [ ] 6.7 `CLAUDE.md:710-711`: `operator/machine-identity` becomes `machine-identity`, the sentence
  already saying "its ... capability", because the area prefix makes it a path-shaped token naming a
  capability the repository never adopted - `openspec/specs/` holds no such directory
  (`openspec/changes/name-the-machine-a-run-dials/proposal.md:104-112`). Caught by 3.3. Verify with
  `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 6.8 The same bare-filename class in two end-to-end docstrings, corrected for the reason 6.6
  gives: `tests/e2e/portable-image/test_portable_image.py:26-27` and
  `tests/e2e/wired-pair/test_wired_pair.py:11-12` both point at `design.md D8` for the claim that a
  build needs no address and a machine's address resolves only inside the cluster's net namespace.
  The referent is
  `openspec/changes/archive/2026-09-16-prove-plan-on-real-machines/design.md:149-153`. Coordinate the
  first with `hold-the-attach-script-to-its-own-discipline` before editing it; that change owns the
  `portable-image` folder's claims. Verify with `nix build .#checks.x86_64-linux.planner-tests`.
- [ ] 6.9 Verify `CLAUDE.md:460` is green under 4.2 rather than racing it:
  `hold-the-attach-script-to-its-own-discipline` owns the Realisers bullets and words the replacement
  as the attribution this check holds - `shellQuote` in `lib/util.nix:193`, spent through
  `escapedWord` in `image/default.nix:197`. If that change has not landed when this one is ready,
  correct the one line here, because a check that lands red is indistinguishable from a broken suite.
  Verify with `nix build .#checks.x86_64-linux.planner-tests`.

## 7. The index records what this change decided

- [ ] 7.1 Add this change's invariants to `CLAUDE.md`. Under "Tooling" or beside the path-scan rules:
  that the root's `*.md` are read by the path scan under the repository-rooted reading only and the
  list of them is derived from the root, so a `./` or `../` fragment in one of them is a quotation
  rather than a claim; that a rooted token naming a capability of the planning record resolves as
  that capability, `operator` being the only top-level entry that is also a capability area; that a
  quoted assignment of a document must appear verbatim in the tree and an identifier a document
  attributes to a named file must be in that file's code, with the comment-stripping and
  whole-identifier readings named as load-bearing; that the boundary is syntactic - a quoted
  statement is crossed, a figure stays a reader's, which is why "twice" at `:894` and the
  spare-filesystem figure at `:958` are corrected by hand; and that a change's `open` or `landed` is
  read off its own `tasks.md` through the one marker reading in `tests/unit/support.nix`, while
  `parked`, `struck` and `narrowed` are not crossed. Verify with `nix build
  .#checks.x86_64-linux.treefmt`, which lints `CLAUDE.md`.
- [ ] 7.2 In the same edit, name the registration points this change touches and the ones it does
  not: `excused` and then `accountable` in `tests/unit/coverage.nix` (1.2 and 9.1), and nothing else -
  no new suite, so `suites` in `tests/default.nix` is untouched; no new top-level entry, so `classOf`
  and `scannedDirectories` in `tests/unit/layers.nix` are untouched; no python directory, so
  `programs.mypy.directories` in `treefmt.nix` and `src` in `ruff.toml` are untouched; no directory
  kind and no excluded construct. Update the "Eight changes are open." figure at `CLAUDE.md:703` and
  name this change in the Registration points section, noting in this change's own notes that the
  figure is corrected by hand because no check crosses it - which is the cost the boundary chose.
  Coordinate with `account-for-every-counterexample` and
  `hold-the-attach-script-to-its-own-discipline` before editing that paragraph: all three are named
  in it and the edit is one paragraph. Verify with `nix build .#checks.x86_64-linux.treefmt`.

## 8. Gates

- [ ] 8.1 `nix eval --json '.#debug.failures'` returns `[]`.
- [ ] 8.2 `nix build .#checks.x86_64-linux.planner-tests`, with every new test green and
  `testAFileNamesAPathThatIsNotThere`, `testARecordIsReadAsHistory`,
  `testACounterexampleQuotesTheClaimItPins` and `testAnExcuseOutlivesTheStateItDescribes` still
  green: the first two are the requirement this change modifies, the third reads the corpus this
  change deliberately did not reuse, and the fourth is the reading task 2.1 moved.
- [ ] 8.3 `nix build .#checks.x86_64-linux.treefmt`, which lints both documents this change edits.
- [ ] 8.4 `nix build .#checks.x86_64-linux.planner-perf`, against the baseline of 1.4. Nothing this
  change edits is evaluated by `perf/eval.nix`, so every counter is expected unmoved; a counter that
  moved is a task here and never a re-recorded budget.
- [ ] 8.5 `fixtures/minimal-typed-edge/plan/*.json` is **not** regenerated: no declaration of any
  fixture changes and nothing of this change is inside `mkPlan`. Verify by `nix eval --json
  .#debug.worked.plan | jq -S .` comparing equal to the committed file.

## 9. Close

- [ ] 9.1 In **one** edit, now that every scenario of task groups 3, 4 and 5 has its test: delete
  this change's `excused` entry from `tests/unit/coverage.nix`, add
  `changes/hold-the-index-to-the-tree/specs/tooling/repository-shape/spec.md` to `accountable`, and
  tick every checkbox of this file. One edit because the excuse is stale the moment a box is ticked
  (`changeHasLanded`, `tests/unit/coverage.nix:398-404`) and `accountable` is unsatisfiable until the
  tests exist, so any other order puts the suite red in between. Verify with `nix build
  .#checks.x86_64-linux.planner-tests`: no unclassified spec
  (`testEverySpecificationIsClassified`), no stale excuse
  (`testAnExcuseOutlivesTheStateItDescribes`), every heading of the delta with a test
  (`testAScenarioGainsNoTest`) and none of them named in both layers
  (`testOneBehaviourIsAssertedInBothLayers`) - 15 scenarios, 13 of them new tests and 2 restated
  headings whose tests already exist, all 15 under nix-unit and none under pytest.
