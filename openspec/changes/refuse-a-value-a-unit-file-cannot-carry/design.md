## Context

See `proposal.md` - Why. Five shapes of the tree decide where each of the three rules lands.

- **A record holds only typed values.** `readUnit` computes `typed` from each field's korora
  `verify` and records `typed` minus `withheld` (`lib/module.nix:692-718`), so a value that failed
  its atom is never in the record a renderer reads. `builtins.match` is anchored, so the nine fields
  whose atoms are grammars - `unitRef`, `duration`, `schedule`, `restartPolicy`, `userName`
  (`lib/atoms.nix:42,46-48,50,65,90-92`) - already refuse a line break as `unit-field-type-mismatch`.
  What is left is `atoms.string` and `attrsOf atoms.string` (`lib/module.nix:59,60,68,69`) and an
  extension field, whose type is whatever its author declared.
- **`renderUnit` is the one renderer and reads the record.** `image/read.nix:661-718` renders from
  `u.record` and `u.directives`, and `flakelet/read.nix:176-179` delegates to it, so a value in the
  record is a value in a unit file under both realisers, and a rule over the record covers both.
- **`lib/` names no realiser.** It reads one extension field by name - `supplementaryGroups`
  (`CLAUDE.md`, Interfaces, composition, reads) - because that key is the one a realiser's directive
  table and the rule both read. Anything stronger is a realiser's name inside the front end.
- **A refusal carries the row that reports it.** `image/read.nix:120-160` pairs every refusal with a
  row identifier or with a recorded reason why no deployment reaches it, and
  `tests/unit/diagnostics.nix` crosses that data against the rows the producing layers build. A new
  refusal therefore needs a row, or a reason.
- **A realiser's own rules are asked of it, not restated.** `operator/read.nix:167-176` asks
  `flakeletReader.acceptsName` and `flakeletReader.nameRule`, and the row it builds
  (`operator/read.nix:326-330`) says "the rule is the realiser's own, asked of it rather than
  restated". `docs/diagnostics.md:60-62` lists the rules each realiser is asked for.

## Goals / Non-Goals

**Goals:**

- A value that would put a line the module did not declare into a unit file is an error row, for
  every field a unit file carries.
- A host path a rendered script interpolates is held to a grammar once, in the layer both realisers
  and the plan reader read, and that grammar has one home in the repository.
- A name this tree derives and hands to a shell is refused by a rule the realiser states, with the
  entry named, before the build system that happens to receive it refuses it for its own reasons.
- Every interpolation into a generated script is escaped, so the grammar is defence and not the
  defence.
- No golden, no fixture and no entry key moves.

**Non-Goals:**

- No raw directive passthrough. See the decision below.
- No new vocabulary field, no new plan field, no new declaration. All three rules read what a module
  already writes.
- No grammar on a `configData` path beyond what a rendered word admits. Whether the path must be
  absolute is an open question below, not a decision taken quietly here.
- No change to what an image's version digest covers (`image/read.nix:447-486`), and therefore no
  forced redelivery. The consequence is recorded under Risks.
- No change to `flakelet/read.nix`'s name rule. It already holds; what changes is that the image
  realiser holds one too and that the reading stops asking by realiser name.

## Decisions

### The newline rule walks the record's strings, and its identifier covers every field

The scan is over every string the recorded unit carries at any depth: a plain field, an element of a
list field, a value of an attribute-set field, and every field of every extension application under
`extends`. That is one walk with the shape `mentions` already has for store paths
(`image/read.nix:545`, `storePathsDeep`), and it needs no list of fields to keep current.

The identifier `unit-env-value-newline` is replaced by `unit-value-newline` rather than joined by a
second identifier. Two identifiers for one class of defect asks a reader to learn which field
belongs to which, and it makes a value that appears in a command and in an environment variable two
rows for one mistake. The message changes with it: the old text says "an environment assignment has
no second line to put the rest on" (`lib/module.nix:834-836`), which is the sentence a reader who
wrote a newline into `command` must not be handed. The row names the field path.

Alternatives rejected:

- **Keep `unit-env-value-newline` and add `unit-command-value-newline` and
  `unit-extension-value-newline`.** Rejected: three identifiers for one rule, and a fourth the day a
  field is added, which is the defect this change exists to remove.
- **Keep `unit-env-value-newline` as the identifier and widen its meaning.** Rejected: the name
  states a field the rule no longer is about, and `docs/diagnostics.md:176` would then describe
  something the identifier denies. The repository's contract is a clean cutover, not a dual
  spelling.

### The scan iterates neither keyset: it iterates the record

Of the two candidate keysets, the realiser's `unitDirectives` (`image/read.nix:101-116`) is the set
of fields actually rendered, and the planner's `unitVocabulary` (`lib/module.nix:58-72`) is the set
of fields a record may carry. They are held equal by construction already: `readUnit` refuses a
recorded field its directive table does not name (`image/read.nix:564,577-578`), with an account
saying that a vocabulary that grew and a realiser that did not is the realiser's own defect
(`image/read.nix:142-145`).

So the library's scan iterates the record, which is bounded by `unitKeys` (`lib/module.nix:74`) and
therefore by the vocabulary, and it names no realiser. Walking `unitDirectives` in `lib/` would put
a realiser's table in the front end; walking `unitVocabulary` field by field would miss the
extension values, which are not vocabulary fields and which `spell` joins with spaces
(`image/read.nix:204-215`). The record is the thing both realisers render from, so the record is
what the rule is about.

The realiser keeps a refusal of its own and scans the same record, because a caller reaching
`image/read.nix` directly gets no table. That refusal is the one place the realiser's own table is
the right keyset, and it already has it.

### The path grammar is a library check and the newline rule stays where it is

The two rules land in two layers, and the reason is the same test applied twice: which layer holds
the fact.

A line break in a unit value is a fact about a file **a realiser renders**, and the check reads the
realiser's own record of what it will render. It is in `lib/` as a row and in `image/read.nix` as a
refusal, which is what it already is, and the library half asks the question without naming a
realiser because the record is the plan's.

A host path a configuration file is written to is a fact **the plan carries and three consumers
read**: `image/default.nix` renders it into an attach script, `flakelet/read.nix` decides whether it
can be shown at all, and `operator/read.nix` indexes it. A grammar stated in one realiser would be a
grammar the other two do not have, and a plan reader outside this repository would have none. So the
grammar is checked in `lib/module.nix`'s `readConfigFile` (`lib/module.nix:872-985`), beside the
four `config-file-*` rows a file already earns.

The grammar itself moves to `lib/util.nix`, beside `keySeparators` (`lib/util.nix:69-82`), which is
where the other grammar a key or a script spends already lives, and `secrets/read.nix:53-70` reads it
instead of stating it. That reading already takes `planner` (`secrets/read.nix:13`) and already reads
`planner.util`, so nothing new is passed and `secrets-rendered-word-refused` keeps its identifier and
its sentence.

Alternative rejected: **state the grammar in each rendered step.** That is the defect in miniature -
one rule, two homes, and a widening that reaches one of them. `docs/diagnostics.md:60-62` records the
opposite habit: one rule has one home, and the row and the raise say the same thing.

### A refused path is not recorded

The sibling `config-file-*` rows leave the file in the record with the failing field nulled
(`lib/module.nix:971-985`), because the failing value is a field inside the file. Here the failing
value is the file's key, and there is no null to hold it: recording it means the plan carries a path
the library has just said no rendered step can carry.

The precedent is `name-carries-key-separator`, whose comment states the rule: a name held to the
grammar the key it enters can carry is checked in the reading of each, and "the thing named is then
left out of everything a key is derived from" (`lib/resolve.nix:189-192`). A configuration file's
path enters `keyInput` through `configData` (`lib/plan.nix:799-800`), so a refused path that stayed
in the record would key an entry by a path nothing may render.

Alternative rejected: **record it and rely on the error blocking the apply.** Rejected because a plan
reader may be handed a plan whose table it did not read - that is the whole reason
`image/read.nix:1-12` states its refusals as answers to a direct caller - and because the escape of
the next decision is then the only thing between a `$(…)` in an attribute name and a root shell.
Dropping the file costs an inapplicable deployment a moved entry key, which is a plan nobody can
apply.

### The image realiser states its name rule, and the reading asks the stated realiser

`image/read.nix` gains `acceptsName`, `nameRule`, `acceptsUnit` and `unitRule` in its exported set
(`image/read.nix:409-424`), written as the sentence its refusal prints, the way
`flakelet/read.nix:52-64` writes them. The rule is: a derived service name and unit file base begin
with an ASCII alphanumeric and carry only ASCII alphanumerics, `_`, `-` and `.`. That is the
intersection of three constraints this realiser is already inside - nix's store-name set, which
`image/default.nix:45-47` spends; systemd's unit-name grammar; and one shell word - and it admits
every name in this repository.

`operator/read.nix:167-176` stops testing `realiser == "flakelet"` and asks the stated realiser for
its two rules, so a third realiser publishing them is asked by existing. The row stays
`operator-entry-name-refused`: its text already reads "the endpoint of the stated realiser refuses
the service name or a unit file name the entry derives" (`docs/diagnostics.md:265`), and its message
is built from `refused.what` and `refused.rule` (`operator/read.nix:326-330`), which is a sentence
the realiser supplies.

Alternatives rejected:

- **A planner row on the derived name.** Rejected: `lib/` would then state a realiser's grammar, and
  the union of two realisers' grammars refuses a name the stated realiser accepts. Which realiser
  realises an entry is a statement beside the deployment and no plan field records it.
- **Rely on nix refusing the store name.** Rejected: nix admits `?` and `=`, which are a shell glob
  and a directive separator; and the abort names neither the entry nor the declaration, which is the
  one property every refusal in this tree is required to have.
- **A second identifier for the image realiser's name refusal.** Rejected: the condition is the same
  condition, and the row's own text is already about the stated realiser rather than about flakelet.

### A generated script escapes what it interpolates, grammar or no grammar

The six messages of `image/default.nix` (`:154`, `:196`, `:209`, `:263`, `:315`, `:389-394`) escape
the path they name, and the three `systemctl` lines (`:332`, `:344-345`, `:360`) escape the unit list
word by word rather than joining it with `concatStringsSep " "`. This is kept even though the library
now refuses a path outside the grammar, because the two protections fail independently: a grammar is
a rule a future field can be added without, and an escape is a property of the rendering that holds
for a value no rule has reached yet. The scripts already escape every argument on the same lines
(`image/default.nix:186-188,196,206-208,330`); the messages are the residue of an assumption nobody
wrote down.

Alternative rejected: **escape nothing now that the grammar exists.** That is the reasoning that
produced this change's three defects: a rule applied at one of the sites it must hold at.

### The staging directory is created `0711`, at the third writer

`image/default.nix:191` and `:324` become `install -d -m 0711`. The rule and its reason are already
written twice - `cli/remote.py:313-319` and `secrets/backend.nix:95`, and `CLAUDE.md` under
Interfaces, composition, reads - and a staged configuration file is the same kind of thing as a
delivered value file: bytes at a declared mode, reached by a unit at a full path.

Nothing lists the directory. The attach script names every staged file by its escaped full path, the
check script the same (`image/default.nix:379-397`), the detach script removes the tree as root
(`image/default.nix:362`), and a unit reaches the file through `BindReadOnlyPaths=<from>:<path>`
(`image/read.nix:681-683`), which needs traverse and not list. What `0755` publishes is the set of
configuration file names of every entry on the machine, to any account, which no declaration asked
to be published.

Alternative rejected: **record why a staged configuration directory is listable where a value
directory is not.** There is no reason that survives being written down. The two directories hold the
same kind of bytes for the same kind of reader, and the asymmetry is an oversight rather than a
decision.

### No raw directive escape hatch

No `extraConfig`, no passthrough string, no second spelling of a vocabulary field. A raw string is
invisible to every check that reads a structured field, and there are four: `unit-field-type-mismatch`
(`lib/module.nix:791-802`), the restart contradictions (`lib/module.nix:848-864`), the closure scan
(`image/read.nix:545-547`, which reads store paths out of the record and refuses an undeclared root
at `:572`), and `denialsOf` (`image/read.nix:375-407`, which reads the recorded `user` and the
recorded groups). An escape hatch is therefore the newline hole with a blessing: it re-earns exactly
the defect this change closes, and it does so for a value a reader would have no reason to suspect.
The vocabulary is also portable by design - a realiser maps it to its service manager's spelling
(`CLAUDE.md`, Realisers, on the restart domain) - and a raw directive makes every plan a systemd
plan.

## Open questions

- **Whether a `configData` path must be absolute.** The grammar of a renderable word admits a
  relative path, and `stagedPath` concatenates `"${stagingOf name}/files${path}"`
  (`image/read.nix:224`), so a relative path produces a joined path with no separator between the
  staging root and the file. Every path in the repository is absolute. This change does not decide
  it, because an absoluteness rule is about where a file lands rather than about what a script can
  carry, and the two rules earn two rows.
- **Whether the path row should bound a path's length.** systemd's unit name limit and `PATH_MAX`
  both exist; neither is a fact this rule needs and no deployment in the tree approaches either.
  Recorded rather than guessed at.

## Risks / Trade-offs

- **The identifier rename reaches anything that reads identifiers.** → `docs/diagnostics.md:176`,
  `image/read.nix:155` and two unit suites (`tests/unit/plan.nix:1307-1319`,
  `tests/unit/image.nix:660-669`) are the whole set, and the tasks move them rather than adding a
  row beside the old one. No golden carries the identifier: no fixture declares a newline.
- **The scan is a new walk of every unit record, in `lib/`.** → Linear in the record's strings, once
  per unit, which is the shape `mentions` already has per unit in the realiser. `perf/mesh.nix`
  keeps one unit per peer with a reference list crossed against the entry's own unit names
  (`CLAUDE.md`, Perf harness), so its unit records are the largest in the tree and are what the gate
  measures. `nix build .#checks.x86_64-linux.planner-perf` is a task of its own.
- **The fix to the attach script does not reach a machine that already holds the entry.** → An
  image's version digest is over the plan facts the artifact holds and not over the script's bytes
  (`image/read.nix:447-486`), so a machine holding an older build keeps its `0755` staging directory
  and its unescaped messages until something the digest covers moves. Folding the script into the
  digest was rejected: it would redeliver every entry of every deployment on any edit to a realiser,
  which is the opposite of what the digest is for. The report's own line for such a machine is
  `current`, which is true about the image and says nothing about the script, and that is a known
  limit of the digest rather than a defect of this change.
- **A deployment that builds today may stop building.** → Only one that writes a line break into a
  unit value, a character outside the grammar into a configuration file path, or a name outside the
  realiser's rule. Each of the three is a deployment whose current failure mode is a broken unit
  file, a root-run command substitution, or a nix-level abort that names nothing.
- **A module author loses a way to write a directive the vocabulary lacks.** → It was never a way;
  it was an accident that bypassed four checks including the confinement lattice. The vocabulary
  grows by a field and a directive, which `hold-a-long-running-daemon` demonstrates costs two lines
  and a type.
- **`0711` could break a reader nobody enumerated.** → The enumeration is above and is closed: three
  scripts, all by full path, and one bind mount. A machine-level scenario of this change's realiser
  delta asserts a staged file is still readable through the narrowed directory.
