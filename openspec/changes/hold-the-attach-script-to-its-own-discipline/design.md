## Context

See `proposal.md` for why, and the two delta specs for what. What shapes the approach:

- The three scripts a machine runs for an image entry are strings this evaluation holds:
  `image/default.nix:471`, `:525` and `:542` render one each, and `tests/unit/image.nix:47-75` imports
  that file over a package set whose `writeShellScript` returns its own text (`:61`). That is why
  `tests/default.nix:4-7` hands that suite the real `nixpkgsLib` rather than a restatement of it -
  "a suite handing it a restatement would measure the escaping against its own copy rather than
  against the one the build spends".
- The derivation script of the image build is the third argument of `runCommand`, and the suite's
  fake returns `fakeDrv name text // attrs` (`tests/unit/image.nix:62-64`), so that text is reachable
  from no evaluation this repository runs.
- The evaluating layer is nix-unit inside a pure evaluation, so a check over a script is a text scan -
  `readFile`, `split`, `match` - never `ast-grep`, and nothing in it writes to the working tree.
- `lib/util.nix:190-193` states an escape that always quotes and records the reason: a bare
  safe-looking word is what `lib.escapeShellArg` leaves behind. `image/default.nix:197` spends it for
  a value inside a message and `:397` for the unit list; every other site of that file spends
  `lib.escapeShellArg`, and `:426`, `:428` and `:447-450` spend nothing.
- The configuration file records the scripts are rendered from carry `staged`, `assembling` and
  `installing` (`image/read.nix:506-508`), `install` says whether this realiser puts the bytes at the
  path at all (`:493`), and `disposition` says where they come from (`:476`, `:521-524`).
- The machine layer already runs the artifact's own script with `portablectl` and `systemctl`
  answered by a refusing `PATH` under a root of the run's own
  (`tests/e2e/portable-image/test_portable_image.py:1084-1205`), which is the only window in which a
  half-written file exists.
- `lib/` is not touched by any of this: the escape it publishes exists, the renderer is a realiser's,
  and no plan field, key or record moves.

## Goals / Non-Goals

**Goals:**

- Each of the four properties is held by a check whose subject is derived rather than chosen, so a
  site the renderer gains is covered by existing.
- Each check fails today or on a named one-line mutation of the renderer, and the mutation is written
  into the task that adds the check.
- The properties are stated over the rendered text and the machine's own answer, never over a
  spelling: a renderer rewritten with the same properties passes unchanged.

**Non-Goals:**

- No plan field, no record field, no key, no version digest and no row. What a value may contain is
  the library's and is already stated; this change is about what the renderer does with it.
- No rule over the image build's derivation script (see D3), and no rule over the other realisers'
  rendered steps: `secrets/backend.nix`'s `deploy.remote` step is held by `util.wordRule` and by a
  different argument, and extending a scan there is that capability's to state.
- No second home for the escape. `lib/util.nix:193` is it, and this change deletes a competing use
  rather than adding one.
- No machine-layer addition beyond one case: the machine answers about modes, and three of the four
  properties are facts about the text.

## Decisions

### D1 - The escape rule is stated as "one quoted word, always", because the value decides nothing

`lib.escapeShellArg` quotes a value that needs it and returns a value matching
`[[:alnum:],._+:@%/-]+` unchanged. For `x86_64-linux`, `systemd`, `strict`, `0400`, `root:root`,
`/run/vars/watch/upstream/secret` and `watch-file-report.service` - which is nearly every value these
scripts name - the escape is the identity. So the rendered bytes of a correctly escaped
interpolation and of a forgotten one are identical, and `image/default.nix:426`'s unescaped
`${raw}/${attachment.image}` is indistinguishable in the text from `:510`'s escaped
`${lib.escapeShellArg image.profile}`. A check over the text cannot separate them; a check over the
values cannot either, because the values are ordinary.

The requirement is therefore restated in the one form that is observable: every occurrence of a value
the records carry sits inside a single-quoted word. Any escape that quotes unconditionally satisfies
it, so it constrains no spelling, and the library already publishes one. The consequence is that the
three machine-run scripts stop spending `lib.escapeShellArg` and spend `planner.util.shellQuote`,
which is a deletion of a second escape rather than the addition of one.

Alternatives considered:

- **A scan over `image/default.nix`'s own source for an interpolation that reaches no escape.** This
  is the purity scan's shape (`tests/unit/diagnostics.nix`), and its recorded limits are why it does
  not fit: substring matching over comment-stripped text, which already misses `korora.check` bound
  as a value and matches `.check ` inside a string literal (`CLAUDE.md`, Known bugs). Here it would
  have to decide which `${…}` of a 612-line file is inside a rendered script, which is a syntactic
  fact a text scan does not have, and `ast-grep` is not available to a pure evaluation.
- **Planting a hostile value at every site.** This is what `hostile`
  (`tests/unit/image.nix:134-139`) does for one field through a hand-written plan, and it does not
  reach the values that are actually unescaped: a store path is the build's own and an image file
  name is derived from the entry's identity, so neither can be made to carry a metacharacter. Kept as
  the fixture for the values a plan does carry, dropped as the mechanism.
- **Leaving the rule as it stands and checking only the four unescaped sites.** That is a check over
  a spelling: it passes the moment the sites are fixed and says nothing about the fifth.

### D2 - The scan's predicate is quote parity, and its subjects come from the records

An occurrence of a subject in the script is safe when the number of single quotes in the text before
it is odd: inside a single-quoted region nothing is read by a shell, whatever the bytes. That
predicate is computable by a scan (`split` the text on the subject, count quotes in each piece,
accumulate), needs no notion of a shell word, and gives the right answer for a subject nested inside
a longer quoted word - a staged path inside a quoted `.installing` path has an odd prefix count and
is safe, which is true. A value whose own bytes carry a single quote is rendered escaped, so its
bytes do not appear contiguously; the scan looks for the escaped rendering as well and counts it
quoted by construction.

The subjects are the strings the records carry: `util.stringsDeep` (`lib/util.nix:386`) over the
attachment description and the configuration file records, plus the artifact's own store paths, which
the builder holds as `raw`, `verity` and the sidecar names. Deriving them is what makes the scan
cover a site the renderer gains: a field added to the attachment is a subject by existing. The scan
reports three things - the subjects it derived, the ones it located in the text, and the occurrences
that failed the predicate - and the check's expectation names all three, so a fixture that stopped
reaching the script fails instead of scanning an empty set. This is the rule the
`tooling/nix-unit-suite` delta states.

### D3 - The evaluating layer holds three properties, the machine layer holds the fourth's mode

The texts are strings a pure evaluation holds (Context), so a scan there costs one evaluation per
entry shape. That is what buys the coverage the machine layer cannot afford: `tests/e2e/portable-image/`
is one VM and four builds of one declaration (`test_portable_image.py:17-24`), whose assembly cases
read one entry whose two staged files are reference recipes at `mode = "0444"`
with no stated ownership, applied as `root`
(`tests/e2e/portable-image/deployment/modules/report/watch.nix:46-64`,
`test_portable_image.py:75`), and each further shape is a phase of a session-scoped, order-dependent
file. The dispositions, the scopes, the restrictive records and the planted values this change needs
are one `let` each in `tests/unit/image.nix`.

The one property that is not in the text is what the create command does with a component nobody
named. Measured against GNU coreutils 9.11, `install -d -m 0711 a/b/c` creates `a` and `a/b` at
`0755` under masks `000`, `022`, `027` and `077`: the mode argument reaches the last component only,
and the parents are neither at the mask nor at the stated mode. The recorded reason
(`image/default.nix:291-294` and the index) says such a component lands at the attaching login's
umask; the conclusion is right and the mechanism is worse than recorded, and either way it is a fact
about a program rather than about the script, so the machine layer is where the modes of the chain
are read. Its case extends the fake root `_probe` already assembles under
(`test_portable_image.py:1142-1205`), which starts from `rm -rf {root}`, so every component in that
root was created by this script and not by an earlier attach.

The render half of the same property is in the evaluating layer, and its expectation is the chain
derived from `image.staging` and each record's `staged` parent directories - inputs of the renderer -
compared against the words of the statement the script carries, which is the output. That is not a
guard comparing state against a record derived from that state
(`openspec/specs/tooling/test-layers/spec.md:287-291`): the record is what the renderer was handed.

### D4 - The candidate checks are over dispositions, not over a file

`image/read.nix:493` makes three shapes reach the install path, and they take two different branches
of `image/default.nix:230-278`:

1. a recipe carrying a reference, whose bytes are concatenated into `<staged>.assembling` (`:255`,
   `:202-217`);
2. a recipe of literals stating a record no store object carries, which takes the same branch,
   because `file.source` is the declared source alone (`image/read.nix:487`) and a build-time
   assembly is not one;
3. a declared `source` store path stating such a record, which takes the branch at `:249-252` and has
   no assembly file at all.

The third is the one no check reads, and it is the one where `install -m 0600 ${candidate}
${installing}` (`:263`) is the only create in the file's path. The checks are therefore parameterised
over the three shapes and over both scopes, and assert per shape: every create in that file's path
names a mode admitting the owner alone; no create names the record's mode; every ownership and mode
step over a file the script wrote names the `.installing` path; the move onto the staged path is the
last step; and the record step naming the staged path is the one under the equal-bytes branch
(`:260-261`), which is the branch that writes nothing.

### D5 - Every create the scripts spell is enumerated, and the one exception is named

The fourth property - no create at the environment's mask - is a scan over the lines of the three
scripts for the steps that bring a path into existence: `install` with or without `-d`, a redirection
that creates, `touch`, `mkdir`, `cp` and `mv` onto a path that did not exist. Every one of them must
carry the mode it creates at, which for this renderer means `install -m` and `install -d -m`, and the
single exception is `mktemp` in `check` (`image/default.nix:562-563`), whose own contract is a file
readable by its owner alone. The exception is named in the check with that reason, so admitting a
second one is a visible decision rather than a silent widening.

The scan is over verbs rather than over a parse, which is the limit the tree already accepts for a
source scan. It is stated in the delta as a property about creates rather than a list of commands, so
a renderer that creates a path by another means is a check to extend rather than a rule to reword.

### D6 - The pinned spellings are re-expressed, not re-pinned

Eight assertions name script text this change quotes: `tests/unit/image.nix:1707` and `:1710` (the
comparison against this build and the attach argument), `:2485` (`chmod 0400 `), `:2798` with
`:2824-2825` (the user-scope installing path), `:2877-2878` and `:2884` (the pool copy and the
comparison against it) and `:2888` (the system attach naming its store path). Each asserts a real
behaviour - which path is compared, which is attached, which mode is applied - and each keeps it,
stated against the quoted word. `:1707` is the one that pins a violation of a requirement the
capability already carries, and it is the evidence that a per-value check is worse than none there:
the suite had recorded the unescaped form as expected.

### D7 - Nothing this change does moves an identity or a budget

The version digest is taken over the statements the artifact was built from
(`openspec/specs/realiser/portable-service-image/spec.md:767-784`), and a renderer is not one of
them, so no entry's digest moves, no report changes its verdict and no apply detaches anything. The
artifact's own store path moves, because its scripts are inputs of it, so the next apply copies each
artifact once and the attach script then reports that nothing changed - which is the same
consequence any edit to a realiser has.

No file under `lib/` is edited, so the nine gated counters are not in question and no budget is
recorded (`perf/budgets.json`'s `note` is for a declared fact the planner has to read, which this is
not).

## Risks / Trade-offs

- **A scan that quantifies over the records is a scan whose failure output is long.** → It reports
  the field path of each failing subject beside the occurrence, which is what
  `util.stringsDeep` yields, so one failure names one field rather than the set.
- **Always-quoting renders `[ "$actualSystem" = 'x86_64-linux' ]` where a reader used to see the bare
  word.** → Accepted: the messages of that file already read that way, and the alternative is a rule
  no check can hold.
- **The create scan is over verbs, so a future create spelled another way passes it.** → It is stated
  as a property of every create, and the verb list is the check's, so extending it is a task rather
  than a spec change; the delta says so.
- **The machine-layer case stats directories under a fake root, not under `/`.** → That is the root
  the folder's assembly phase already uses, and the reason is recorded: a real attach on a real root
  would have the chain created by an earlier phase, so the modes read would be the earlier attach's.
- **A subject the record carries and the script legitimately does not name reads as "not found".** →
  That is the reported third number, not a failure, and the check's expectation names it, so a
  subject that stops being named is visible.

## Migration Plan

None on any machine: no digest moves, so no entry is detached, and the first apply after the change
copies the new artifacts and reports nothing changed. In the repository the order is the one
`tasks.md` states: the checks land red against today's renderer, the renderer is corrected in the
same change, and the two delta specs move from `excused` to `accountable` in the single edit that
ticks the boxes.
