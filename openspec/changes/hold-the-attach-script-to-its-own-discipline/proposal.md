## Why

`image/default.nix` renders the three scripts a machine runs for an image entry - `attach`, `detach`
and `check` (`image/default.nix:471`, `:525`, `:542`) - and the load-bearing rules of that file are
about a window in which a rendered secret is readable by an account the declaration did not admit.
The index carries those rules in full, because the image realiser is the one realiser with no
document of its own, and the whole of its Realisers section names exactly one check, which belongs to
the other realiser (`CLAUDE.md`, the `flakelet/read.nix` bullet naming `tests/e2e/delivery.py`).

The index naming no check is not the same as the tree holding none, and this change begins by saying
what is held, because three of the four properties below are observed and the fourth is broken today.

**The staged-file discipline** - a candidate created closed, owned and chmodded, then moved onto the
path (`image/default.nix:230-278`) - is observed at both layers, unevenly. The evaluating layer reads
the user-scope render of one entry with one `0400` reference recipe and asserts `install -m 0600 `
somewhere in the text, `chmod 0400 <installing>` and `mv <installing> <staged>`
(`tests/unit/image.nix:2823-2825`); the system-scope render is asserted only as `chmod 0400 ` with no
target (`:2485`) and as a count of `chown` (`:2814`, expecting 2 at `:2839`).
`testAnInterruptedInstallLeavesNoFileAtAWiderRecord` (`:2324-2357`) asserts that the three paths are
distinct and under the staging directory, which is a property of the record
(`image/read.nix:506-508`) and reads no script. The machine layer runs the artifact's own script under
a `PORTABLE_PLANNER_ROOT` of the run's own with `portablectl` and `systemctl` answered by a refusing
`PATH` (`tests/e2e/portable-image/test_portable_image.py:1084-1139`) and observes the mode of the
staged path and of every `*.assembling` file under that root, under masks `000` and `077`
(`:1195-1197`, `:1208-1281`). That is for one entry, `watch:file@alpha`, whose two staged files are
both reference recipes stating `mode = "0444"` and no ownership
(`tests/e2e/portable-image/deployment/modules/report/watch.nix:46-64`), applied as `root`
(`test_portable_image.py:75`).

Three parts of it are therefore held by nothing. The mode the *candidate* is created at
(`image/default.nix:263`) is asserted nowhere: `hasInfix "install -m 0600 "` is already satisfied by
the recipe's own create at `:255`, and `_probe` searches for `*.assembling` and never for the
`.installing` candidate, so widening `:263` to `0644` passes both layers. The ownership's target is
asserted nowhere: the only assertion is a count, and the machine layer stats no owner and could not
see one, its record being `root:root` under a `root` login. And the whole discipline is unasserted for
a declared `source` file stating a record the store cannot carry (`image/read.nix:493`), whose script
has no assembly step at all (`image/default.nix:249-252`), so that `:263` is the only create in its
path; `testAFileStatingAnOwnershipIsInstalledOnTheHost` and its two neighbours
(`tests/unit/image.nix:2236-2291`) read `hostPaths` and `configFiles` and no script text.

**The staging-tree discipline** - one `install -d -m 0711` with every component named
(`image/default.nix:291-314`, `:486-488`) - is observed at its two ends and not along it. The
evaluating layer asserts exactly one `install -d ` line, at that mode, naming the entry's own staging
directory and `<staging>/files/etc` (`tests/unit/image.nix:2470-2495`); the machine layer stats
`<root><staging>` and the staged file's own parent at `711` and refuses `nobody` a listing of either
(`test_portable_image.py:1283-1323`). Neither reads the components between them, so dropping
`<staging>/files` or the parent of the staging directory from `stagingDirectories` passes every
existing check. The index and `image/default.nix:291-294` give the reason as the component landing at
the attaching login's umask; measured against GNU coreutils 9.11, `install -d -m 0711 a/b/c` creates
`a` and `a/b` at `0755` under masks `000`, `022`, `027` and `077`, so a component left for `install`
to create is world-listable whatever the login's mask. The recorded conclusion holds and the recorded
mechanism is weaker than the truth.

**The escape discipline** is stated in the spec as a rule over every value
(`openspec/specs/realiser/portable-service-image/spec.md:714-728`) and observed one value at a time:
every occurrence of one staged path outside double quotes (`tests/unit/image.nix:2405-2421`), one
hand-planted `target.system` no grammar reached, twice, both as `'…'` (`:2423-2444`, the fixture at
`:134-139`), and the unit list word by word (`:2446-2468`). Each is satisfied by whatever the renderer
does to every other value, and the machine layer asserts nothing about escaping at all. Under that
regime the rule is broken in the tree: `attachRef` and `heldImage` interpolate
`"${raw}/${attachment.image}"` with no escape of any kind (`image/default.nix:426`, `:428`), spent at
`:496`, `:509`, `:510` and `:530`, and the user-scope placement names `${verity}/…` and `${raw}/…`
bare as `install` sources (`:447-450`). `tests/unit/image.nix:1707` pins one of those spellings as its
expectation.

That last one is not a missing check but an unobservable rule. `lib.escapeShellArg` quotes according
to the value and leaves a word matching `[[:alnum:],._+:@%/-]+` bare, which is why the library states
an escape that always quotes (`lib/util.nix:190-193`). For an ordinary value, therefore, the bytes a
correct escape leaves and the bytes a forgotten escape leaves are the same bytes, and no scan over
the rendered text can tell them apart: `[ "$actualSystem" = x86_64-linux ]` (`image/default.nix:329`)
and `portablectl attach --profile=strict /nix/store/…` (`:510`, `:426`) read alike whether the escape
is there or not. A rule whose violation is indistinguishable from its observance is a rule no check
can hold, which is why this one has been stated since the capability was written and is violated at
six sites.

Two sentences the index carries about this file do not hold as written, and the corrections are part
of this change rather than of the one that owns the index's drift. The staging bullet gives the reason
for naming every component as the component landing at the attaching login's umask; the measurement
above says `0755` whatever the mask. And the escaping bullet attributes a `quoted` of its own to
`image/default.nix`; what that file has is `planner.util.shellQuote` (`lib/util.nix:193`) spent
through a local `escapedWord` (`image/default.nix:197`), which is an attribution
`hold-the-index-to-the-tree` names as a violation its own check catches. No count of invariants is
claimed here: the index's rules for this realiser are prose bullets and this proposal names the ones
it changes rather than a figure it cannot read off the tree.

## What Changes

- **The rule the escape discipline states becomes observable**: every value the artifact's own records
  carry SHALL appear in each published script only inside a single-quoted word. This is a property of
  the rendered text, satisfied by any escape that quotes unconditionally, and it is stated in that
  form because it is the form a scan can fail on. `lib.escapeShellArg` is consequently not what the
  three machine-run scripts spend: they spend the library's own always-quoting escape
  (`lib/util.nix:193`), which the messages of that file already spend through `escapedWord`
  (`image/default.nix:197`). The four store-path sites above are escaped in the same edit, because a
  check that cannot fail is not kept and this one fails today
  (`openspec/specs/tooling/test-layers/spec.md:264-273`).
- **The staged-file discipline is stated for every file the script installs and for the file it
  installs from**: the candidate is created admitting its owner alone whatever record it will carry,
  the record is applied to the candidate and never after the move, and a file whose bytes are a store
  path goes through the same candidate, that install being the only create in its path.
- **The staging-tree discipline is stated over the chain and not over its ends**: every directory
  between the machine's own and each staged file's parent is named in the one statement that creates
  them, with the measured reason above rather than the recorded one.
- **One new rule covers a create the renderer has not written yet**: no create in a published script
  depends on the environment's file-creation mask. Every create names the mode it creates at, and the
  one exception - a temporary whose own contract is owner-only (`image/default.nix:562-563`) - is
  named rather than left to a reader.
- **Every new check is in the evaluating layer, bar one.** The three scripts are strings this
  evaluation holds: `pkgs.writeShellScript` is answered by its own text in the suite's fake package
  set (`tests/unit/image.nix:47-75`, the fake at `:61`), which is why `tests/default.nix:4-7` hands
  that suite the real `nixpkgsLib` - "the one suite that reads a rendered script". A scan there costs
  one evaluation per entry shape, so the dispositions, the scopes and the hostile values the machine
  layer cannot afford are reachable. The one machine-layer addition is the mode of every component of
  the staging chain, because `install`'s treatment of a component it creates is a fact only a machine
  answers.
- **No new suite file and no new top-level path**: the checks are cases of `tests/unit/image.nix`,
  already registered in `tests/default.nix:96-103`, and one case of
  `tests/e2e/portable-image/test_portable_image.py`, an existing folder. The registration this change
  does carry is its two delta specs in `excused` in `tests/unit/coverage.nix:104-121`.
- **Existing assertions that pin a bare spelling are rewritten, not re-pinned**:
  `tests/unit/image.nix:1707`, `:1710`, `:2485`, `:2798`, `:2824-2825`, `:2877-2878`, `:2884` and
  `:2888` name script text that this change quotes. Each keeps the behaviour it asserts - which path
  is compared, which is attached, which mode is applied - and states it against the quoted word.
- **Not in scope**: the derivation script of the image build (`image/default.nix:105-113`, `:179-188`)
  keeps `lib.escapeShellArg`. It is the third argument of `runCommand`, which the suite's fake does not
  return (`tests/unit/image.nix:62-64`), so its text is reachable from no evaluation this repository
  runs and a rule over it would be a rule with no check. The plan, the reading and every record are
  untouched: no field is added, no key moves, and the artifact's version digest is the reading's
  (`openspec/specs/realiser/portable-service-image/spec.md:767-784`), so this change detaches and
  re-attaches nothing.

## Capabilities

### New Capabilities

None. Every property is already a property of a capability that exists; two of the four are already
written down in it and unobserved.

### Modified Capabilities

- `realiser/portable-service-image`: three requirements about the attach script are extended from one
  file, one directory and one value to every file the script installs, every directory of the chain
  and every value the records carry, and one requirement is added about a create whose mode the
  artifact did not state.
- `tooling/nix-unit-suite`: a check over a rendered script derives the values it looks for from the
  record the script was rendered from and reports what it found, so that a site the renderer gains is
  covered by existing and a fixture that stopped reaching the script fails rather than passing over
  nothing.
