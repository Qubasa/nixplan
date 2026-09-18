## Why

`CLAUDE.md` is the index of this repository's invariants, and it is the only text about the tree
that the tree does not read as a subject. `tests/unit/layers.nix` reads it twice and both readings
are haystacks: `recordFiles` (`tests/unit/layers.nix:790-802`) makes it one corpus among nine that
`stated` (`:808`) searches for a sentence a counterexample's comment pinned, and `scannedFiles`
(`:308-312`) is every file under `lib image flakelet operator cli secrets perf tests fixtures docs`
plus the root's `*.nix`, so the root's `*.md` are in no scanned set and
`testAFileNamesAPathThatIsNotThere` (`:1071`) never opens them. An index that is never a subject
drifts, and it has: five of its statements disagree with the tree, a sixth names a document that
does not exist, a seventh names a capability the repository never adopted, and an eighth attributes
an identifier to a file that has no such name.

The requirement the drift breaks already exists.
`openspec/specs/tooling/repository-shape/spec.md:12-35` says a path named by this repository's code,
tests, fixtures **or documentation** resolves, in prose and in a comment alike, and
`:106-121` already crosses a document against the tree by identifier: the rows a document tabulates
are the rows the library can produce, and an identifier on one side and not the other fails a suite
naming the side it is missing from. Neither reaches the index. This change makes the index a subject
of both principles and states the boundary that keeps the withdrawn figure cross-walk withdrawn.

## What Changes

- **The root documents join the path scan, under the repository-rooted reading only.** The root's
  `*.md` - derived from the tree rather than listed, so a new root document joins by existing - are
  read by `rootedPathsOf` (`tests/unit/layers.nix:184-190`) and not by `namedPathsOf` (`:171-182`).
  A document at the root names a path as the repository sees it; a `./` or `../` fragment in it is a
  quotation of another file's own expression, whose base directory is the file that holds it and not
  the document. That reading is what makes `CLAUDE.md:552`'s `../lib` - the path
  `operator/default.nix` passes the library by - and `README.md:73`'s `./deployment` - a line of a
  consumer's own flake - the non-claims they are, rather than two exemptions.
- **A two-segment token that names a capability of the planning record resolves as a capability.**
  `operator` is both a top-level directory and the area of four capabilities, so
  `repoTokens` (`:126`) reads `operator/apply-command` (`CLAUDE.md:714`) as a path and finds nothing
  at it. The token names something the repository holds -
  `openspec/specs/operator/apply-command/spec.md`
  - and the check resolves it there. `operator/machine-identity` (`CLAUDE.md:711`) names neither a
  path nor a capability: `openspec/specs/operator/machine-identity/` does not exist, the delta file
  was deleted, and this is the live violation the extended scan catches today.
- **What the extended scan does not catch is stated rather than assumed.** `pathTokens` (`:115`)
  requires a token beginning `./` or `../` and `repoTokens` requires a first segment that is a
  top-level entry, so a bare filename is no path token at all. `CLAUDE.md:387`'s `design.md` is
  therefore invisible after the root documents join the scan, and so is the same reference in the
  already-scanned `tests/unit/platform.nix:355`. A bare-filename reading is not specifiable: 58 of
  the 66 filename-shaped backticked tokens of the index - `default.nix`, `args.nix`, `read.nix`,
  `manager.rs` among them - name a file of a directory their sentence names and resolve at no root.
  Both references are corrected to the path of the record that holds the measurement,
  `openspec/changes/archive/2026-09-16-emit-systemd-portable-service-images/design.md:116-131`, which
  the rooted reading then holds.
- **A quoted assignment is crossed against the tree.** A backticked fragment of a document that
  parses as `<name> = <value>` and carries no elision is a quotation of a line of this repository,
  and the bytes are searched for in the files the path scan reads, minus the documents themselves.
  The index carries 14 such fragments; 13 are in the tree verbatim and one is not,
  `additionalSpace = "2048M"` at `CLAUDE.md:871`, against `tests/e2e/guest.nix:434`'s
  `additionalSpace = "6144M"`. Across `README.md` and `docs/**` the same reading finds one more
  fragment and no violation: `docs/authoring.md:124`'s `fold = korora.fold "<name>" (set: …)`, which
  the elision gate excuses because it is an illustration and not a quotation.
- **An identifier a document attributes to a file is crossed against that file.** The attributions
  are the four idioms the index itself writes - `` `<identifier>` in `<file>` ``,
  `` `<identifier>` of `<file>` ``, `` `<file>`'s `<identifier>` `` and
  `` `<file>` has a `<identifier>` `` - read only where the file operand names a file or directory of
  this repository, which is what keeps `docs/operator.md:1066`'s
  `` `ConnectTimeout` in `NIX_SSHOPTS` `` out of the reading. Thirty attributions are readable across
  the root documents and `docs/**`; twenty-nine hold and one does not. `CLAUDE.md:460` says
  `image/default.nix` has a `quoted` of its own for the messages, and that file has no such
  identifier: it binds `escapedWord` (`image/default.nix:197`) over `planner.util`'s `shellQuote`
  (`lib/util.nix:193`). Correcting that sentence belongs to
  `hold-the-attach-script-to-its-own-discipline`, which owns the Realisers bullets; it is the live
  violation this check catches today, and this change's last task verifies it rather than racing it.
  The crossing reads the named file's **code**, comment lines dropped as
  `tests/unit/diagnostics.nix` already drops them, and matches an identifier token rather than a
  substring: `image/default.nix` says "quoted" twice in prose (`:23`, `:194`) and writes
  `double-quoted` nowhere as an identifier, and a substring reading would have found the claim true.
  The residual is stated: an identifier the index attributes to nothing is not crossed, which is
  exactly finding 2. `CLAUDE.md:817` names `extraPythonPaths` and `pythonRoot`, neither of which
  exists anywhere in the tree, and it names no file to attribute them to, so nothing could have
  crossed them. `treefmt.nix:55-57` writes a `mypy.ini` whose `mypy_path` is the `cli` store path,
  and its own comment (`treefmt.nix:50-54`) argues the opposite trade to the one the index states: a
  store path is what is wanted, because `PYTHONPATH` makes mypy read the directory as an installed
  distribution and then demand a `py.typed` marker. The correction states the true identifier in a
  checked idiom, which is what makes the claim crossable at all, and the demonstration that the
  check fails on the condition it names is the old claim written in that idiom. The residual is
  the price of having no false positives: twelve backticked identifiers of the index appear nowhere
  in the tree, and ten of them legitimately - `StopIteration` and `perInstance` are foreign,
  `c6fcb62` is a commit, and `documentFigures`, `treeFigures`, `testASuiteGainsATest`,
  `holds_attached`, `recordPath`, `markerPath` and `greetingPath` are things the index's own
  sentences say are gone.
- **The boundary: a quotation is crossed, a figure is not.** A quoted statement carries its own
  referent, so the check is `readFile` and a substring; a figure names a measurement, so a check for
  it has to re-implement the measurement, and then the document holds a second copy of an expression
  nobody runs. That is what `testASuiteGainsATest`, `documentFigures` and `treeFigures` were, and why
  `CLAUDE.md:746-748` records the requirement as withdrawn rather than excused. The discriminator is
  syntactic and not semantic: a backticked fragment that parses as an assignment is a quotation, and
  a number in prose is a figure. `additionalSpace = "2048M"` reads like a size and is not a figure -
  the quoted text is a line of `tests/e2e/guest.nix` - while the same fact at `CLAUDE.md:958`, "6 GiB
  of spare filesystem", is a figure and stays a reader's. One fact of the index, crossed where it is
  quoted and uncrossed where it is counted, is the boundary doing its work.
- **A change's status word is crossed against the record it restates.** `tests/unit/coverage.nix`
  already derives landing from the anchored `- [x]` marker of a change's own `tasks.md`
  (`changeHasLanded`, `:398-404`), and `staleExcuses` (`:406-416`) spends it. The index restates the
  same fact by hand and contradicts itself while doing so: `CLAUDE.md:53-54` calls
  `run-an-entry-without-root` "the open change" and `CLAUDE.md:716-719` lists it among the five that
  have landed, and its `tasks.md` has 27 boxes, all ticked. The crossing reads only the two words the
  record can derive, `open` and `landed`, near a change's own name and not across a sentence end;
  `parked`, `struck` and `narrowed` are judgements no `tasks.md` holds and are not crossed, which is
  the figure boundary again, and `CLAUDE.md:703`'s "Eight changes are open." is a figure whose
  neighbouring name is one token away and is not a claim about it, which is what the sentence-end
  gate is for. Eight claims are readable in the index today, seven of which agree with the record,
  and the eighth is the contradiction above.
- **One home for the marker reading.** The anchored `- [x]` reading moves to `tests/unit/support.nix`
  as a function of the text, and both `tests/unit/coverage.nix` and the new check call it, so a
  document-side reading and an excuse-side reading cannot disagree about what a ticked box is. The
  same reading answers both questions the two suites ask: whether a box is ticked at all, which is
  what an excuse expires on, and whether one is not, which is what `landed` claims.
- **Seven drift sites are corrected**, each with its line named: the size at `CLAUDE.md:871`, the
  mypy identifiers at `:817`, the status word at `:53-54`, the capability name at `:711`, the count
  of built deployments at `:894` against
  `tests/e2e/portable-image/test_portable_image.py:17-24` - four builds, `changed`, `retired` and
  `probed` beside the first - the rotted pointer at `:858` from `lib/compose.nix:30-31`, which is the
  `]` and `in` closing `serviceKeys`, to `:42`, where
  `settings = settingsOf { inherit name defaults fixed; }` is handed no instance so that the claim
  itself holds, and the bare `design.md` at `:387` together with its twin in the already-scanned
  `tests/unit/platform.nix:355`. Two of the audit's five findings are caught by no new check and are
  corrected by hand, which is this change's boundary showing its cost: "twice" is a count in prose,
  and a `path:line` pointer states no content, so nothing but a reader can say whether the line still
  carries the claim and a crossing for it would be a check that cannot fail on the condition it names
  (`openspec/specs/tooling/test-layers/spec.md:264-273`). Two further bare-filename pointers of the
  same class, `design.md D8` in `tests/e2e/portable-image/test_portable_image.py:26-27` and
  `tests/e2e/wired-pair/test_wired_pair.py:11-12`, are corrected to
  `openspec/changes/archive/2026-09-16-prove-plan-on-real-machines/design.md:149-153`.
- **No new suite and no new top-level path.** Four nix-unit checks join `tests/unit/layers.nix`,
  which is where the document-shape checks already live, so `suites` in `tests/default.nix` and
  `classOf` in `tests/unit/layers.nix` are untouched. The one registration this change owes is its
  own delta spec in `excused` in `tests/unit/coverage.nix`, moving to `accountable` in the edit that
  ticks the boxes. `openspec/**` stays exempt from the path scan (`testARecordIsReadAsHistory`,
  `tests/unit/layers.nix:1093-1104`): the status crossing reads a `tasks.md` as the record of its own
  change and not as a file whose paths must resolve, and the new document list holds the root's
  `*.md` and nothing under `openspec/`.
- The checks are text scans in a pure evaluation - `readFile`, `split`, `match`, `replaceStrings` -
  and write nothing. The quotation corpus is the path scan's own file set and deliberately not
  `statedIn` (`tests/unit/layers.nix:781-788`), which excludes `tests/` and strips `#`: a corpus
  without `tests/` cannot see `tests/e2e/guest.nix`, and a corpus with its comment markers replaced
  by spaces would let a fragment match across a comment boundary.

## Capabilities

### New Capabilities

None. The index is a document of this repository and the rules that hold a document are
`tooling/repository-shape`'s.

### Modified Capabilities

- `tooling/repository-shape`: the resolution rule names the index among the documents it holds, and
  states which reading a path in a root document gets and that a capability name is not a path; a
  code statement a document quotes is crossed against the file it is attributed to, with the
  quotation-versus-figure boundary stated; and a change's status word is read off the record that
  derives it rather than restated.
