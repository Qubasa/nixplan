## 1. Registration, before anything is edited

- [ ] 1.1 Register this change's two delta specs in `excused` in `tests/unit/coverage.nix:104-121`,
  one line per file, each reason naming this change in the shape `excuseNamesChange`
  (`tests/unit/coverage.nix:389-394`) matches - "an unimplemented change: no task of
  hold-the-attach-script-to-its-own-discipline has been done, ..." - for
  `changes/hold-the-attach-script-to-its-own-discipline/specs/realiser/portable-service-image/spec.md`
  and `changes/hold-the-attach-script-to-its-own-discipline/specs/tooling/nix-unit-suite/spec.md`.
  Verify with `nix build .#checks.x86_64-linux.planner-tests` after 1.3: an unclassified `spec.md`
  fails `testEverySpecificationIsClassified`.
- [ ] 1.2 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` (`tests/unit/coverage.nix:398-404`) reads this file for a single anchored `- [x]`
  line and `staleExcuses` (`:406-416`) fails the suite for an excuse whose change has landed, so
  ticking one box while the two paths are excused turns the suite red for a reason that reads like a
  missing test. Both paths move to `accountable` and every box is ticked in the one edit task 7.1
  makes.
- [ ] 1.3 `git add` every file of this change before evaluating anything - the flake does not see an
  untracked path and the coverage cross-walk then reports the spec it cannot read rather than the
  file that was not staged. That is `proposal.md`, `design.md`, `tasks.md` and the two spec files.
  Verify with `nix eval --json '.#debug.failures'` returning something other than a file-not-found
  error.
- [ ] 1.4 Record no perf baseline and touch no budget: no file under `lib/` is edited by any task
  below, `perf/eval.nix` measures plan evaluation and this change edits a realiser's renderer and one
  suite. If a later task turns out to need a `lib/` edit, stop and take the baseline first
  (`bash perf/measure.sh`), because the gate is two-sided with a 0.15 margin.

## 2. The scan machinery, in the suite that already reads a rendered script

- [ ] 2.1 Add the quote-parity predicate to `tests/unit/image.nix`, beside `insideDoubleQuotes` and
  `namedInsideQuotes` (`:88-100`): given a subject and a text, return the occurrences whose preceding
  single-quote count is even, which are the occurrences a shell would read. Inside a single-quoted
  region nothing is active whatever the bytes, so parity is the whole predicate, and a subject nested
  inside a longer quoted word answers safe, which is true (design D2). Verify by a case in the same
  suite over three hand-written texts: `a 'x' b` with subject `x` answers none, `a x b` answers one,
  and `a '/nix/store/h-x/y' b` with subject `y` answers none.
- [ ] 2.2 Add the subject derivation: `planner.util.stringsDeep` (`lib/util.nix:386`) over the
  attachment description and the configuration file records of the entry the script was rendered
  from, plus the artifact's own store paths (`raw`, the verity output and the sidecar names), each
  subject carrying the field path `stringsDeep` yields so a failure names one field. Do not write a
  list of values; the point of the derivation is that a field added to the attachment is a subject by
  existing. Verify that the derived subject set of the `staged` fixture (`tests/unit/image.nix:104-130`)
  contains the staged path, the shown host path, the mode, the ownership, the profile, the target's
  system and every unit file name, asserted as the sorted field paths rather than as a count.
- [ ] 2.3 Add the report shape the two deltas require: `{ derived, located, unquoted }` - how many
  subjects were derived, which of them the text names, and the failing occurrences with their field
  paths. A subject the script names nowhere belongs in neither `located` nor `unquoted`. Verify that
  the report over a text of the empty string answers `located = [ ]`, which is the shape task 3.3's
  expectation makes visible.

## 3. The escape rule made observable, and the renderer brought to it

- [ ] 3.1 Replace `lib.escapeShellArg` with `planner.util.shellQuote` at every site of
  `image/default.nix` that renders into the three scripts the artifact publishes: `:233-237`, `:246`,
  `:251`, `:346`, `:385`, `:415`, `:417`, `:424`, `:487`, `:495`, `:510`, `:531`, `:548`, `:550` and
  `:556`. Leave `:106`, `:112-113`, `:185-186` alone - those render into the image build's own
  derivation script, which no evaluation of this repository can read as a string (design D3) and
  which the delta names as out of scope. `shellQuote` is `replaceStrings`-based
  (`lib/util.nix:193`), which keeps string context, so a store path it quotes still roots the
  script's closure; do not reach for `util.shortHash`, which discards it on purpose.
- [ ] 3.2 Escape the sites that reach no escape at all: `attachRef` (`image/default.nix:426`),
  `heldImage` (`:428`) and the four `install -m 0444` sources of the user-scope placement
  (`:447-450`). These are the live violation of
  `openspec/specs/realiser/portable-service-image/spec.md:714-728` that task 3.3's check catches
  today, spent at `:496`, `:509`, `:510` and `:530`. Verify by eye that each of the four spends is now
  a quoted word and by task 3.3 that the scan reports `unquoted = [ ]`.
- [ ] 3.3 Add `testEveryValueTheArtifactRecordsIsOneQuotedWordInEveryScriptItPublishes` to
  `tests/unit/image.nix`, over `attach`, `detach` and `check` of the `staged` fixture and of
  `userStaged`, asserting the whole report of 2.3: the derived field paths, the located ones and
  `unquoted = [ ]`. **The mutation it catches**: reverting one site of 3.1 or 3.2 to a bare
  interpolation, which the check reports as that field path with an even quote count - and which it
  reports today, before 3.1 and 3.2, at the four sites of 3.2. Run it against the unedited renderer
  first and keep the failing output in the commit message: a check whose first run is green over a
  renderer that violates the rule is a check that cannot fail
  (`openspec/specs/tooling/test-layers/spec.md:264-273`).
- [ ] 3.4 Add `testAStorePathTheBuildNamesIsOneQuotedWord`, asserting that the image the artifact
  carries, the verity data beside it and the artifact's own directory each appear as one quoted word
  at every site of the three scripts that names them, in both scopes. **The mutation**: the
  unescaped `"${raw}/${attachment.image}"` of `:426` and `:428`, which is what stands today. This is
  the store-path half stated separately from 3.3 because a store path is a value no grammar of this
  repository reaches, which is the case the requirement is written for.
- [ ] 3.5 Strengthen the body of `testEveryPathAGeneratedScriptNamesIsEscaped`
  (`tests/unit/image.nix:2405-2421`) to the parity predicate, keeping its heading and therefore its
  name: `namedInsideQuotes` asks only whether an occurrence sits inside a double-quoted string, so a
  bare occurrence outside every quote - which is what `:426` renders - passes it. **The mutation**:
  the same one, at a site the old body could not see.
- [ ] 3.6 Re-express the eight assertions that pin a spelling this change quotes:
  `tests/unit/image.nix:1707`, `:1710`, `:2485`, `:2798` with `:2824-2825`, `:2877-2878`, `:2884` and
  `:2888`. Each keeps the behaviour it asserts - which path the machine's answer is compared against,
  which path is attached, which mode is applied, which path the pool copy is moved onto - stated
  against the quoted word. `:1707` had recorded the unescaped form as its expectation, which is the
  evidence for design D6 and is worth a line in the commit message. Do not delete them and do not
  weaken them to an infix of the path alone: the path they name is the claim.

## 4. The candidate discipline, over the three dispositions

- [ ] 4.1 Add the three fixtures task 4.2 needs to `tests/unit/image.nix`, beside `staged` and
  `userStaged`: a recipe carrying a reference at a restrictive mode (the existing `staged` already
  is), a recipe of literals stating an ownership no store object carries, and a declared `source`
  store path stating such a record. The third takes the branch at `image/default.nix:249-252` and has
  no assembly file at all, so the install at `:263` is the only create in its path (design D4).
  Verify that all three answer `install = true` from the reading (`image/read.nix:493`) and therefore
  reach the assemble step.
- [ ] 4.2 Add `testACandidateIsCreatedAdmittingItsOwnerAlone`, over the three fixtures and both
  scopes: every create in the file's path names a mode admitting the owner alone, and no create names
  the record's own mode. Read the creates off the script's lines rather than asserting one infix -
  `hasInfix "install -m 0600 "` is satisfied by the recipe's own create at `image/default.nix:255`
  whatever `:263` says, which is why the property is unheld today. **The mutation**: widening `:263`
  to `install -m 0644`, which passes every existing check at both layers, `_probe` searching for
  `*.assembling` and never for the `.installing` candidate
  (`tests/e2e/portable-image/test_portable_image.py:1195-1197`).
- [ ] 4.3 Add `testAFileWhoseBytesAreAStorePathIsInstalledThroughTheSameCandidate`, over the third
  fixture: the store path is installed into the `.installing` path at the owner-only mode, that path
  carries the record, and the store path is never installed onto the staged path. **The mutation**:
  rendering `install -m 0444 ${candidate} ${staged}` for the source branch, which no check in either
  layer reads today - `testAFileStatingAnOwnershipIsInstalledOnTheHost` and its neighbours
  (`tests/unit/image.nix:2236-2291`) read `hostPaths` and `configFiles` and no script text.
- [ ] 4.4 Add `testTheRecordIsAppliedBeforeTheMoveAndNeverAfterIt`, over the three fixtures in system
  scope, where the record is two steps: every `chown` and every `chmod` over a file the script wrote
  names the `.installing` path, the `mv` onto the staged path is the last step over that file, and the
  one record step naming the staged path is the one under the equal-bytes branch
  (`image/default.nix:260-261`), which writes nothing. **The mutation**: moving the `chown` after the
  `mv`, which today changes only a count (`tests/unit/image.nix:2814` expects `2`) and is invisible
  to the machine layer, whose record is `root:root` under a `root` login
  (`tests/e2e/portable-image/deployment/modules/report/watch.nix:46-64`,
  `test_portable_image.py:75`).

## 5. The staging chain

- [ ] 5.1 Add `testEveryDirectoryOfTheStagingChainIsNamedWhereItIsCreated` to
  `tests/unit/image.nix`, with a fixture whose staged file sits several directories below the entry's
  own, and assert that the words of the one `install -d -m 0711` statement cover the chain derived
  from `image.staging` and each record's `staged` parents. Derive the expectation from the record,
  which is the renderer's input, and compare it against the rendered statement, which is its output
  (design D3): do not re-derive it from `stagingDirectories`. **The mutation**: dropping
  `<staging>/files` or `builtins.dirOf image.staging` from `stagingDirectories`
  (`image/default.nix:295-314`), which passes `testTheStagingDirectoryIsTraversableAndNotListable`
  (`tests/unit/image.nix:2470-2495`), that check reading only the entry's own directory and the leaf,
  and passes the machine layer, which stats the same two (`test_portable_image.py:1305-1320`).
- [ ] 5.2 Add `test_every_directory_above_a_staged_file_carries_the_traversable_mode` to
  `tests/e2e/portable-image/test_portable_image.py`, **last in file order** among the assembly cases,
  extending the fake root `_probe` already assembles under (`:1142-1205`): derive the chain from the
  attachment's `staging` and the staged path's parents, and report `stat -c %a` of each and an
  unprivileged `ls` of each in the one ssh command the folder's phases are written as. Every
  component the script created answers `711` and refuses the listing. **The mutation**: the same one
  as 5.1, which on a machine answers `755` for the unnamed component - measured against GNU coreutils
  9.11, `install -d -m 0711 a/b/c` creates `a` and `a/b` at `0755` under masks `000`, `022`, `027`
  and `077`, so the exposure needs no permissive login. Run with `nix run .#planner-e2e
  portable-image`.

## 6. The create scan

- [ ] 6.1 Add `testACreateThatNamesNoMode` to `tests/unit/image.nix`: over the lines of `attach`,
  `detach` and `check` of both scopes, classify every step that brings a path into existence and
  assert that each names the mode it creates at. The verbs this renderer spells are `install` and
  `install -d`; the scan also refuses a creating redirection, `touch`, `mkdir` and a `cp` or `mv`
  onto a path that did not exist, so a renderer that changes means fails rather than passes
  (design D5). **The mutation**: replacing `install -m 0600 /dev/null ${partial}`
  (`image/default.nix:255`) with `: > ${partial}` and a `chmod`, which leaves the recipe file at the
  attaching login's mask for the length of the concatenation.
- [ ] 6.2 Add `testATemporaryWhoseContractIsOwnerOnly`, naming `mktemp` in `check`
  (`image/default.nix:562-563`) as the one create admitted without a mode of its own, with its reason
  - its contract is a file readable by its owner alone - and asserting that it is the only such step
  in the three scripts. **The mutation**: a second create claiming the same exception, which the
  check reports because the exception is a named set of one rather than a class.

## 7. Verification and closing

- [ ] 7.1 In **one** edit, now that every heading of the two deltas has its test: delete this change's
  two `excused` entries from `tests/unit/coverage.nix`, add the same two paths to `accountable`, and
  tick every checkbox of this file. The three steps are one edit because the excuse is stale the
  moment a box is ticked (`changeHasLanded`, `tests/unit/coverage.nix:380-385`) and `accountable` is
  unsatisfiable until the tests exist. Verify with `nix build .#checks.x86_64-linux.planner-tests`:
  no unclassified spec, no stale excuse, and the heading cross-walk satisfied in both directions. Each
  heading is implementable in exactly one layer and
  `test_every_directory_above_a_staged_file_carries_the_traversable_mode` is the only pytest name of
  the set, a name present in both layers being a failure rather than a bonus
  (`tests/unit/coverage.nix:1-3`).
- [ ] 7.2 The registration points this change touches are exactly `accountable`/`excused` in
  `tests/unit/coverage.nix` and nothing else: no new suite file, so `suites` in `tests/default.nix` is
  untouched and the new cases are cases of `tests/unit/image.nix`, registered at
  `tests/default.nix:96-103`; no new top-level file or directory, so `classOf` and
  `scannedDirectories` in `tests/unit/layers.nix` are untouched; no new python directory, so
  `programs.mypy.directories` in `treefmt.nix` and `src` in `ruff.toml` are untouched; no new
  directory kind and no new excluded construct, so `lib/module.nix`'s `directoryKinds` and
  `lib/excluded.nix` are untouched; no new end-to-end folder, that layer being discovered from
  `tests/e2e/*/deployment/default.nix`; and no `README.md` literal moves.
- [ ] 7.3 Run `nix eval --json '.#debug.failures'` and require `[]`, then
  `nix build .#checks.x86_64-linux.planner-tests`, `nix build
  .#checks.x86_64-linux.planner-counterexamples-eval` and `nix build .#checks.x86_64-linux.treefmt`.
  Do not `nix flake check` the whole flake. `fixtures/**` is untouched: no golden plan and no
  rendered table changes, because no plan field and no row moves.
- [ ] 7.4 Add this change's invariants to `CLAUDE.md`, under **Realisers**, beside the attach
  script's existing bullets: that the three scripts the artifact publishes always quote an
  interpolated value and spend `shellQuote` (`lib/util.nix`) rather than `lib.escapeShellArg`,
  because an escape that inspects the value leaves an ordinary one bare and no scan can then tell a
  correct escape from a forgotten one; that a store path the build names is such a value and was
  unescaped at four sites; that the candidate install's own mode is the whole guarantee for a file
  whose bytes are a store path, there being no assembly step in that path; and that a component the
  create command makes for itself is made `0755` whatever the login's mask, which is the measured
  reason the whole staging chain is named. Correct the two stale sentences of that section in the same
  edit: the umask reason above, and the attribution of a `quoted` to `image/default.nix`, which spends
  `shellQuote` from `lib/util.nix` through a local `escapedWord`. Leave every other paragraph of the
  index to `hold-the-index-to-the-tree`, which owns its drift and cites the attribution as a
  violation its own check catches. Verify with `nix build .#checks.x86_64-linux.treefmt`, which lints
  `CLAUDE.md`.
- [ ] 7.5 Write no new document. The image realiser has no document of its own, which is why its
  rules are in the index in full, and `docs/tooling.md` records figures a reader maintains rather
  than counts a check crosses. If a sentence of `docs/diagnostics.md` or `docs/operator.md` turns out
  to name the escaping, make it name the property rather than the spelling; no row identifier and no
  refusal moves here, so the tables of both documents are unchanged.
