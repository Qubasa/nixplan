## Context

See `proposal.md` - Why. What shapes the approach is the machinery that already reads documents, and
the one crossing this repository deliberately deleted.

`tests/unit/layers.nix` holds every check about the shape of the tree and already reads every
document: `recordFiles` (`:790-802`) is `CLAUDE.md`, `README.md`, `docs/**.md` and the `.nix` and
`.py` files of six source directories, flattened with `#` replaced by a space (`:804`) and searched
by `stated` (`:808`) with `replaceStrings` so each text is walked once per needle. That corpus exists
for one purpose: `withdrawnClaims` (`:882-888`) fails on a sentence a counterexample's comment
pinned that no record states any more. The index is on the haystack side of it.

The path scan is separate and narrower. `scannedFiles` (`:308-312`) is every file under the ten
directories of `scannedDirectories` (`:295-306`) plus the root's `*.nix`; `repoNamedPaths` (`:316`)
runs both readings over it, `namedPathsOf` (`:171-182`) resolving a `./`-or-`../` token against the
containing file's directory and `rootedPathsOf` (`:184-190`) resolving a token whose first segment is
a top-level entry against the root; `unresolvedReferences` (`:318-322`) is what
`testAFileNamesAPathThatIsNotThere` (`:1071`) asserts empty.

`tests/unit/coverage.nix` owns the planning record. `changeHasLanded` (`:398-404`) reads
`openspec/changes/<name>/tasks.md` for a line matching `[[:space:]]*- [[]x[]].*`, anchored because
four production changes name the marker in prose, and `staleExcuses` (`:406-416`) fails for an
excuse whose change has started landing. `excuseNamesChange` (`:389-394`) is how an excuse names its
change.

Two facts bound every decision below. The suite is nix-unit inside a pure evaluation, so a check
over text is `readFile`, `split`, `match` and `replaceStrings`, never `ast-grep`, and nothing may
write to the working tree. And `CLAUDE.md:746-748` records that a count a document states is no
longer crossed: `testASuiteGainsATest`, `documentFigures` and `treeFigures` were deleted and the
requirement withdrawn rather than excused, so any new document-versus-tree crossing has to say why
it is not that.

## Goals / Non-Goals

**Goals:**

- The index is a subject of the same resolution rule its code is held to, by the check that already
  exists rather than by a second one.
- A statement of code a document quotes fails where the file it names does not make it.
- A change's status word is compared with the record, not with a second copy of the record.
- Every reading is a function of a text, so a scenario can hand it a synthetic document and the
  tree-side assertion is the same function applied to the real files.

**Non-Goals:**

- Reviving the figure cross-walk in any form. No count, size or duration a document states is
  measured against the tree.
- Crossing a `path:line` pointer. The pointer states no content, so nothing but a reader can say
  whether the line still carries the claim.
- Crossing every identifier a document quotes. The residual is stated in the spec and left.
- Any rule about the counterexample paragraph. `account-for-every-counterexample` owns that, and it
  owns `tooling/test-layers`.
- Rendering the index from the tree, or generating any part of a document.
- A new suite file, a new top-level entry, or a second corpus beside the ones that exist.

## Decisions

### D1 - The root documents join the existing scan, under the rooted reading only, derived from the root

`scannedFiles` keeps its meaning - the files whose paths are read under both readings - and a second
list beside it holds the documents read under the rooted reading alone. It is derived, `filesIn
repoRoot` filtered to `*.md`, so `CLAUDE.md`, `README.md` and `LICENSE.md` are read today and a
document added at the root is read by existing. Nothing is hand-maintained, so there is no
registration point to forget.

Why the rooted reading only: a document at the root is one file, and every path it names is a path
of the repository, but the fragments it quotes are not. `CLAUDE.md:552` quotes `../lib`, which is
what `operator/default.nix` passes the library by - correct in that file, and resolving to a
directory above the repository when read from the root. `README.md:73` shows `import ./deployment`
inside a consumer's own flake, which resolves in the reader's tree. Under `namedPathsOf` both are
failures and both would need an exemption; under `rootedPathsOf` neither is a claim the document
makes.

Measured over the three root documents under this reading: two rooted tokens do not resolve as
paths, `operator/machine-identity` (`CLAUDE.md:711`) and `operator/apply-command` (`:714`). D2
answers the second; the first is the live violation.

Alternatives rejected:

- **Add the root's `*.md` to `scannedFiles`.** They would get `namedPathsOf` too, and the change
  would ship with two exemptions for two correct sentences.
- **Scan every `*.md` of the tree under the rooted reading.** `docs/**` is already scanned under
  both readings and its relative paths are relative to `docs/`, correctly: `docs/cluster.md` names
  `../tests/e2e/runner.py` and means it. Widening the rooted reading there changes nothing and
  narrowing the relative one would lose a real check.
- **Read a bare filename as a path of the root.** 58 of the index's 66 filename-shaped backticked
  tokens - `default.nix`, `args.nix`, `read.nix`, `manager.rs` among them - name a file of a
  directory their own sentence names. The reading would be almost entirely false positives, and the
  one reference it would catch, `design.md` at `CLAUDE.md:387`, is corrected to a path instead.

### D2 - A two-segment token is resolved as a capability before it is reported

`operator` is a top-level directory and also the area of four capabilities, so `repoTokens` reads
`operator/apply-command` as a path. The token names something the repository holds -
`openspec/specs/operator/apply-command/spec.md` - and the check resolves it there: a token that
names a capability of the planning record, whether a current spec or the delta of an open change,
resolves. `planner/`, `realiser/`, `tooling/` and `delivery/` tokens never reached the scan at all,
because `firstSegment` (`:117-122`) has to be a top-level entry, so the collision is exactly the
`operator` area and the reading is two `pathExists` calls per candidate token.

`operator/machine-identity` (`CLAUDE.md:711`) resolves as neither:
`openspec/specs/operator/machine-identity/` does not exist and the delta file was deleted as
superseded
(`openspec/changes/name-the-machine-a-run-dials/proposal.md:104-112`). It stays a failure and is
corrected in the index by naming the capability without the area prefix, which is what the sentence
already means.

Alternatives rejected:

- **An exemption list of tokens.** A list is what the next capability of the `operator` area is left
  out of, and the exemption would hide exactly the case that is wrong today.
- **Forbid the index from naming a capability.** The Registration points section is where a reader
  learns which capability owns what; the fix belongs in the reading.

### D3 - Two quotation shapes, both syntactic, both stated as data

Each reading is a function from a document's text to rows, so the suite asserts the same function
twice: once over the real documents, once over a synthetic document a scenario writes.

**A quoted assignment.** A backticked fragment of one line that matches a name, `=` and a value, and
carries no placeholder or elision, must appear verbatim in the quotation corpus. Measured: the index
carries 14 such fragments and 13 appear verbatim; the fourteenth is `additionalSpace = "2048M"`
(`CLAUDE.md:871`) against `tests/e2e/guest.nix:434`. Across `README.md`, `LICENSE.md` and `docs/**`
one further fragment is found and excused by the elision gate,
`docs/authoring.md:124`'s `fold = korora.fold "<name>" (set: …)`, which is an illustration of a shape.

The corpus is the path scan's own file set minus the documents. It is deliberately not `statedIn`
(`:781-788`): that corpus excludes `tests/`, so it cannot see `tests/e2e/guest.nix` at all, and it
replaces `#` with a space, which would let a fragment match across a comment boundary. Excluding the
documents is what stops one document satisfying another document's quotation, and stops the index
satisfying itself.

Verbatim and not normalised, because the tree is formatted: `nixfmt` writes one space either side of
`=`, so the bytes the document quotes are the bytes the file holds. A fragment that wraps across
lines in the document is not crossed, and none does today.

**An attributed identifier.** Four idioms, stated once as a table so that adding one is adding a
row: `` `<identifier>` in `<file>` ``, `` `<identifier>` of `<file>` ``, `` `<file>`'s `<identifier>` ``
and `` `<file>` has a `<identifier>` ``. The file operand must name a file or directory of this
repository, which is what keeps `docs/operator.md:1066`'s `` `ConnectTimeout` in `NIX_SSHOPTS` `` out
of the reading. Measured across the root documents and `docs/**`: 30 attributions, 29 holding.

The one that does not is `CLAUDE.md:460`, "`image/default.nix` has a `quoted` of its own for the
messages": that file binds `escapedWord` (`image/default.nix:197`) over `lib/util.nix:193`'s
`shellQuote`. The sentence belongs to `hold-the-attach-script-to-its-own-discipline`, which owns the
Realisers bullets and corrects it there; this change's last task verifies the crossing is green and
corrects the line only if that change has not landed, because a check that lands red is
indistinguishable from a broken suite.

Two properties of the identifier reading are load-bearing and were measured as failures of the naive
version. The named file's **code** is read, comment lines dropped the way
`tests/unit/diagnostics.nix` drops them, because `image/default.nix` says "quoted" in two comments
(`:23`, `:194`) and a whole-text reading reports the false claim as true. And the identifier is
matched as a whole identifier, bounded by characters outside `[A-Za-z0-9_'-]`, because `double-quoted`
contains the letters of `quoted` and is a different name.

Alternatives rejected:

- **Attribution by proximity - the identifier and a path in one bullet, or in one sentence.**
  Measured: 131 crossings and 31 failures, almost all of them correct sentences.
  `CLAUDE.md:245` names `mkPlacement` and `lib/plan.nix` in one sentence and means two different
  files; `CLAUDE.md:746` names `testASuiteGainsATest` beside `docs/tooling.md` to say it is gone;
  `stdenv` sits beside `lib/`. A check with 31 exemptions is a check nobody can read.
- **Crossing every quoted identifier against the whole tree.** Measured: 12 of the index's 235
  distinct backticked identifiers appear nowhere, and 10 legitimately - `StopIteration` and
  `perInstance` are foreign, `c6fcb62` is a commit, and `documentFigures`, `treeFigures`,
  `testASuiteGainsATest`, `holds_attached`, `recordPath`, `markerPath` and `greetingPath` are
  constructs the index's own sentences say were deleted. Telling those apart needs the sentence's
  verb, which no scan reads.
- **A published regular expression per idiom.** The idioms are read by one reading over a stated
  table of prepositions and possessives; a pattern per idiom would be four rules with four spellings.

### D4 - The boundary: a quotation carries its referent, a figure names a measurement

This is the decision the withdrawn crossing forces, and it is syntactic rather than semantic.

A quoted code statement carries its own referent. `additionalSpace = "2048M"` is either a line of
this repository or it is not, and the check that answers is `readFile` plus a substring: no model of
the tree, no measurement, no second implementation of anything. A figure names a measurement -
"eight changes", "six guest properties", "nine counters" - so a check for it has to re-implement the
measurement, and then the document holds a copy of an expression nobody runs, kept equal by hand.
`documentFigures` and `treeFigures` were that, and `testASuiteGainsATest` was the same shape applied
to a test count.

The discriminator is what a fragment reads as, not what it is about. `additionalSpace = "2048M"`
reads like a size and is not a figure: it is an assignment, quoted from a named file, and the size is
incidental to how it is checked. The same fact at `CLAUDE.md:958` - "6 GiB of spare filesystem" - is
a figure, stays uncrossed, and stays a reader's to maintain. One fact of the index, crossed where it
is quoted and uncrossed where it is counted, is the boundary doing its work rather than being
asserted.

The cost is stated rather than hidden: after this change the index still carries figures that can
rot, `CLAUDE.md:703`'s "Eight changes are open." among them, and correcting one is a reader's edit.
That is the trade the withdrawal already chose.

### D5 - The status crossing reads only the two words the record derives

The vocabulary is `open` and `landed` and nothing else. `parked`, `struck` and `narrowed` are
decisions no `tasks.md` holds, so there is nothing to compare them against - which is D4 again: a
word the record cannot derive is a reader's, like a figure.

A word is a claim about a change where it stands within a bounded distance of that change's own name
- backticked, bare or inside its `openspec/changes/<name>` path - and no sentence end lies between
them. Measured over the index: eight claims, seven agreeing with the record, and one failing -
`CLAUDE.md:53-54`'s "The open change `run-an-entry-without-root`" against a `tasks.md` of 27 ticked
boxes and none unticked. The sentence-end gate is what it is for: `CLAUDE.md:703` reads "Eight
changes are open. `answer-whether-a-machine-is-current` stays open because…", where the figure's own
`open` is one token from a change name it says nothing about.

The derived word is `landed` where the record has at least one ticked box and none unticked, and
`open` otherwise, a change with no `tasks.md` deriving `open`. That is what makes the index's two
correct statements about `answer-whether-a-machine-is-current` (21 of 23 ticked, "stays open") and
the five landed changes both hold, and it is the reason the crossing needs the unticked lines as
well as the ticked ones: `changeHasLanded` answers "has started landing", which is what an excuse
expires on, and `landed` claims "has finished".

Alternatives rejected:

- **Forbid a status word in the index.** The brief of the Registration points section is to tell a
  reader what is in flight. A prohibition would move that to `openspec list` and delete a reader's
  index of it.
- **A stated table of statuses the check reads by construction.** It is a third copy of the fact -
  the record, the prose and the table - and the section's style is argued prose.
- **Cross every word of a stated vocabulary.** It fires on "a capability that never landed" and "its
  21 landed tasks", neither of which is a status claim, which is what the distance and sentence-end
  gates answer.

### D6 - One home for the ticked-marker reading

The anchored reading moves to `tests/unit/support.nix` as a function of a text, answering both
questions about one change: whether any line is ticked, and whether any is not.
`tests/unit/coverage.nix`'s `changeHasLanded` calls it and keeps its own name and its own meaning,
and the new check calls it for the second answer. `support.nix` takes no root and needs none - the
reading is a function of the text the caller read - so nothing about how either suite is wired
changes.

Two readings of one marker is how a document-side answer and an excuse-side answer come to disagree
about the same change, and the anchoring is exactly the part that is easy to write differently the
second time: an unanchored match reads the four production changes' own prose about `- [x]` as a
ticked box.

### D7 - The checks live in `tests/unit/layers.nix`

That file is where every check about the shape of the tree and the text of a document already lives,
it is already handed `repoSource`, and it already reads `CLAUDE.md`. No new suite file means `suites`
in `tests/default.nix` is untouched, no new top-level path means `classOf` is untouched, and the one
registration this change owes is its own delta spec in `excused` in `tests/unit/coverage.nix`.

The status crossing reads `openspec/changes/*/tasks.md`, which does not make `openspec/` part of the
path scan: `testARecordIsReadAsHistory` (`:1093-1104`) asserts that `scannedDirectories` and
`scannedFiles` hold nothing under `openspec/`, the new document list holds the root's `*.md` alone,
and a `tasks.md` is read here as the record of its own change rather than as a file whose paths must
resolve. A record still describes the repository as it was.

## Risks / Trade-offs

- **A quoted assignment could be satisfied by a coincidentally identical line in another file.** →
  The check answers "the tree still makes this statement", which is the drift it exists to catch; a
  statement attributed to a particular file is the identifier reading's job. Requiring a quotation to
  name its file would refuse every quotation the index makes: not one of the fourteen fragments
  names a file in its own sentence, and thirteen of them are correct - `restart = "on-failure"`,
  `homeMode = "711"` and `reach = "all"` among them.
- **The identifier reading is an idiom table, so a claim written in a fifth idiom is not crossed.** →
  Stated in the spec as the residual, with its measurement: an unattributed identifier is exactly how
  `extraPythonPaths` survived. The table makes attributing a claim the way to have it checked, and
  adding an idiom later is adding a row.
- **The identifier reading drops whole comment lines only, so an identifier named in a trailing
  comment of a code line counts as code.** → The same reading `tests/unit/diagnostics.nix` makes, and
  it errs towards passing, which for this check means a false claim could survive in a trailing
  comment. A reading that understood nix strings is what the purity scan already does not have.
- **A document may correctly quote a statement of a foreign repository that reads as an assignment.**
  → Then it fails, and the fix is the citation rule the resolution requirement already states: state
  the fact rather than quoting the foreign line. No such fragment exists in any document today.
- **The status crossing is prose-shaped and a rewording could put a claim outside its window.** → It
  degrades to not crossing, never to a false failure, and the window is measured against every claim
  the index makes today. A claim the check cannot see is the same residual as an unattributed
  identifier.
- **Four more text scans in `planner-tests`.** → All four read files the suite already reads, the
  quotation corpus is walked once per fragment with `replaceStrings` as `stated` already is, and none
  of it is inside `mkPlan`: the perf gate measures plan evaluation and this is a suite.
- **`CLAUDE.md:460` is corrected by a sibling change.** → Coordinated: that change owns the Realisers
  bullets and words the replacement as the attribution the new check holds. This change's last task
  verifies rather than races, and corrects it only if the sibling has not landed.

## Migration Plan

One cutover inside the test tree, nothing to deploy. The six corrections to `CLAUDE.md` and the one
to `tests/unit/platform.nix` land in the same change as the checks that would fail on them, so the
suite is green at every commit that is meant to be green. The ordering the tasks fix is the
registration one this repository already documents: the delta spec is `excused` while the boxes are
unticked, and the excuse and the boxes move in one edit.
