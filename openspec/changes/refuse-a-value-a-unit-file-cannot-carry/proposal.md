## Why

Three rules of this tree are written down and applied at one of the sites they have to hold at. All
three are the same defect: a value a module writes reaches a generated file through a path nobody
checked, and the failure names neither the entry nor the declaration.

**A unit file is line-oriented, and one field of the vocabulary is held to it.**
`image/read.nix:598-599` states the rule - "A unit file is line-oriented, so a newline in a value is
a fact the file cannot carry. Spaces and quotes can be: they are escaped at render." -
and `image/read.nix:600-614` applies it to `units.<u>.env.<k>`, as does the row above it
(`lib/module.nix:769-775`, `lib/module.nix:829-838`). `renderUnit` interpolates every other recorded
string straight into the file: `image/read.nix:702` writes `ExecStart=${unit.command}`, `:704` and
`:705` the stop and reload commands, `:685-687` one line per extension field through `spell`
(`image/read.nix:204-215`), which joins a list of strings with spaces. Four of those values are
strings no grammar constrains: `command`, `stopCommand` and `reloadCommand` are `atoms.string`
(`lib/module.nix:59,68,69`), and an extension's field carries whatever type its author declared -
`tests/e2e/portable-image/deployment/default.nix` declares `supplementaryGroups` as
`listOf string`. A newline in one of them appends a line of the author's choosing to the
`[Service]` section: `User=root`, or `PrivateUsers=no`. `flakelet/read.nix:178` calls the same
`reader.renderUnit`, so both realisers carry it.

The consequence is not cosmetic. The confinement decision reads the *recorded* `user` and the
recorded `supplementaryGroups` (`image/read.nix:366-374` `admits`, `:375-407` `denialsOf`), so a
`User=` smuggled past the record is never compared against the profile, and
`operator-entry-access-denied` and the `strict`/`default`/`trusted` lattice become advisory for any
module author who can write `\n`. The same record is what `mentions` scans for undeclared store
paths (`image/read.nix:545-547`).

The other nine vocabulary fields are already safe, and for a reason worth recording rather than
rediscovering: `builtins.match` is anchored, so `atoms.unitRef`, `atoms.duration`, `atoms.schedule`,
`atoms.restartPolicy` and `atoms.userName` (`lib/atoms.nix:42,46-48,50,65,90-92`) each refuse a
newline as a type failure, and `recorded` is the typed fields minus the withheld ones
(`lib/module.nix:718`), so a failing value never reaches a record a renderer reads. The hole is
exactly "a string whose atom admits any string", which is what a rule over the record's strings
closes and a rule over an enumerated field list does not.

**A `configData` host path reaches a generated script unescaped.** `lib/module.nix:872-985` puts no
grammar on the attribute name, and `image/default.nix` interpolates `file.path` into six
double-quoted shell strings of the attach and check scripts: `:154`, `:196`, `:209`, `:263`, `:315`,
`:389-394`. The path *arguments* on those same lines are escaped - `lib.escapeShellArg file.staged`
at `:186-188`, `file.source` at `:196`, `file.mode` at `:206-208` - and only the messages are not.
A `$(…)` in a path is therefore a command substitution the machine runs as root at apply time, and a
`"` produces a syntactically invalid attach script whose failure names nothing. The identical
condition is checked for the other rendered step in this tree: `secrets/read.nix:53-70` states
`wordRule = "[a-zA-Z0-9_./:@%+=,~-]+"` with the reason, `:83` applies it, and
`secrets/read.nix:243-258` reports it as `secrets-rendered-word-refused`. `configData` is written
inside `impl`, so the condition is reachable by a module author and not only by a deployment author.

**A derived unit file name has no grammar under the image realiser.** A unit file is
`"${instance}-${service}-${unit}.service"` (`image/read.nix:182,217`), and the only grammar on the
three names it is built from is the key-separator denylist (`lib/util.nix:76-82`,
`lib/resolve.nix:195-212`), which admits a space, `?`, `=` and `;`. `image/default.nix:332`, `:344`,
`:345` and `:360` splice the whole list into `systemctl` as bare words, three lines after the same
script escapes a single unit name (`:330`). The exposure is bounded by nix, not by this tree: the
same string is a derivation name at `image/default.nix:45-47`, and nix refuses a store name outside
`[a-zA-Z0-9+._?=-]`, so `;`, `$` and a space abort the build. `?` passes nix and is a shell glob,
and the nix-level abort names neither the entry nor the declaration, which is the one thing every
realiser refusal in this tree is required to do. `flakelet/read.nix:54-58` already holds the derived
service name to `[A-Za-z0-9][A-Za-z0-9_-]*` and `:82-94` holds each unit file name to a rule of its
own; `operator/read.nix:167-176` asks flakelet for those rules and reports
`operator-entry-name-refused` (`operator/read.nix:326-330`) before any build. The image realiser is
asked nothing, because it states nothing.

One inconsistency belongs with them. The attach script creates its staging directory `0755`
(`image/default.nix:191`, `:324`) where both value writers are deliberately `0711` with the reason
written down (`cli/remote.py:313-319`, `secrets/backend.nix:95`, and `CLAUDE.md`: "The value's
directories are `0711`: a file the record opens to an account is unreachable behind a directory only
root may traverse"). It leaks the configuration file names of every entry on the machine, not their
bytes, and there is no third answer: either the rule holds at its third writer or it is not a rule.

## What Changes

- **The newline rule covers every string a unit record carries, at any depth.**
  `unit-env-value-newline` is replaced by `unit-value-newline` (error), which names the field path
  the value sits at - `command`, `env.<k>`, `extends.<backend>.<field>` - rather than assuming an
  environment variable. The scan walks the recorded unit rather than an enumerated field list, so a
  future `atoms.string` field and an extension field of any shape are covered by existing. The
  realiser's refusal above it (`image/read.nix:634-638`) is generalised the same way and keeps its
  account, whose `id` moves to the new identifier.
- **A `configData` host path is held to a grammar in the library.** `config-file-path-refused`
  (error) reports a path outside the grammar a rendered step can carry as one word, and the grammar
  is the one `secrets/read.nix:57` already states, moved to `lib/` so that one rule has one home.
  The refused file is not recorded, the way a name carrying a key separator is left out of every key
  it would have entered (`lib/resolve.nix:189-192`).
- **The image realiser states a name rule and is asked for it.** `image/read.nix` gains
  `acceptsName`, `nameRule`, `acceptsUnit` and `unitRule` beside the ones `flakelet/read.nix`
  publishes, refuses a name outside them with an account naming `operator-entry-name-refused`, and
  `operator/read.nix:167-176` stops branching on `realiser == "flakelet"` and asks the stated
  realiser instead. No new row identifier: the existing one already means "the endpoint of the
  stated realiser refuses a name this entry derives" (`docs/diagnostics.md:265`).
- **Every value a generated script interpolates is escaped, whether or not a grammar admits it.**
  The six messages of `image/default.nix` escape the path they name, and the three `systemctl` lines
  escape the unit list word by word. A message is not the place to rely on a grammar: the grammar
  and the escape fail independently, and the escape is what holds when a future field reaches a
  script before its rule does.
- **The staging directory is created `0711`.** `image/default.nix:191` and `:324` hold the rule its
  two sibling writers already hold. A unit reads a staged file by its full path through
  `BindReadOnlyPaths` (`image/read.nix:681-683`) and nothing lists that directory, so traversable
  and unlistable costs the realiser nothing.
- **No raw directive escape hatch.** No `extraConfig`, no passthrough string, no second spelling of
  a field the vocabulary carries.

## Capabilities

### New Capabilities

<!-- none: all three rules belong to capabilities that exist -->

### Modified Capabilities

- `planner/diagnostics`: a value a unit file cannot carry is a row for every field the file carries
  and not for one of them; a configuration file's host path is held to the grammar a rendered step
  can carry as one word, in the library, so every realiser and every plan reader inherits it.
- `realiser/portable-service-image`: a unit file name this realiser derives is held to a grammar it
  states itself, and a name outside it is a refusal carrying the row that reports it; a value a
  generated script interpolates is escaped whether or not a grammar constrains it; the staging
  directory is traversable and not listable.

## Impact

- `lib/module.nix`: the newline scan (`:769-775`) walks the record's strings rather than
  `record.env`, and its row (`:829-838`) becomes `unit-value-newline` naming a field path;
  `readConfigFile` (`:872-985`) gains the path grammar row and drops a refused file from its record.
- `lib/util.nix`: the one statement of the shell-word grammar, beside `keySeparators`
  (`lib/util.nix:69-82`), which is where the other grammar a key or a script spends already lives.
- `secrets/read.nix`: `wordRule` and `wordAdmits` (`:53-70`) read the library's statement instead of
  restating it. The reading already takes `planner` (`secrets/read.nix:13`), so nothing new is
  passed, and `secrets-rendered-word-refused` keeps its identifier and its sentence.
- `image/read.nix`: the generalised scan and refusal (`:598-614`, `:634-638`), the account's new id
  (`:155`), and `acceptsName`/`nameRule`/`acceptsUnit`/`unitRule` in the exported set (`:409-424`)
  with the refusal in `read`.
- `image/default.nix`: six escaped messages, three escaped `systemctl` word lists, two `0711`
  directory creations.
- `operator/read.nix`: `refusedNames` (`:167-176`) asks the stated realiser rather than testing for
  one by name, so a third realiser publishing the same two rules is accounted for by existing.
- `tests/unit/{plan,module,image,flakelet,operator,diagnostics}.nix`: the scenarios of both spec
  files. The existing `unit-env-value-newline` assertions (`tests/unit/plan.nix:1307-1319`,
  `tests/unit/image.nix:660-669`) move to the new identifier rather than being duplicated beside it.
- `docs/diagnostics.md`: `unit-value-newline` replaces `unit-env-value-newline` at `:176`,
  `config-file-path-refused` joins the `config-file-*` rows at `:180-183`, and the list of rules a
  reading asks each realiser for (`:60-62`) gains the image realiser's two.
- `tests/unit/coverage.nix`: this change's two spec files move from `excused` to `accountable`.
- `CLAUDE.md`: the newline rule is about every string a unit record carries; the path grammar has one
  home; a realiser states its own name rule and the reading asks for it; the staging directory is
  `0711` for the reason the value directories are.

**No golden and no fixture moves, and it is checked rather than assumed.** Every `configData` path
in the tree is inside the grammar: `/srv/borg/.ssh/authorized_keys`
(`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:40`), `/etc/fleet/peers`
(`perf/fleet.nix:107`), `/etc/mesh/peers` (`perf/mesh.nix:137`), the two derived from an entry's own
identity in `tests/e2e/portable-image/deployment/modules/report/watch.nix:38-40`, and the one
`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:109` derives. Every unit name
declared anywhere in `fixtures/`, `perf/` and `tests/e2e/*/deployment/` is
one ASCII word - `agent`, `attest`, `borgPush`, `borgRepo`, `fetch`, `hub`, `idle`, `init`, `mark`,
`mirror`, `report`, `rotate`, `say`, `serve`, `server`, `write` - as is every instance, member and
machine name they are prefixed by. No string in any unit record carries a newline. So
`fixtures/minimal-typed-edge/plan/*` stays byte-equal, including `diagnostics.txt`, and no entry key
moves. The three e2e folders that build images or artifacts are unaffected; the one behaviour change
a reader can observe on a machine is that `/run/portable-planner/<name>` is no longer listable by an
unprivileged account.
