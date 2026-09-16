This file holds project invariants, if you encounter a project invariant that has not been written down yet,
please add it to this file. Also if you encounter bugs, you can add them here such that next time we won't make that mistake again.
Keep it concise and human readable please.

Commit `c6fcb62` deleted every comment in the tree. The load-bearing ones are back at their own
constructs, shortened. This file is the index of the same invariants, so a rule can be found
without reading the code first. One line per invariant: a section whose argument is written out
elsewhere names that document and states the rule only, and what no document carries is here in
full, which is the design lineage, the registration points, the image realiser, the known bugs and
the counterexamples.

## Design lineage

Names for what the layers already are, so a reader can look up prior art rather than invent
vocabulary, and so a known hazard is not re-derived.

- The tree is a compiler. `lib/` is a front end with error recovery, the plan is an input-addressed
  intermediate representation, `image/`, `flakelet/` and `secrets/` are back ends, and `cli/` is
  the loader. A row carries the fields a rustc diagnostic carries: identifier, subject, message,
  note, help.
- `lib/resolve.nix` is a stratified reference attribute grammar: synthesized attributes (exports,
  rows), inherited ones (settings, target), reference attributes (a wire naming another instance's
  node) and a lazy knot at `resolved`. The hazard of that shape is an attribute cycle, and the fix
  is already under Keys and identity: a key is structural, so it is computed in an earlier stratum
  than the units. A future field that has to see a downstream unit set reopens it.
- `lib/diagnostics.nix` is an accumulating validation applicative, and `diag.guard` is the
  try-catch a host puts around a plugin's own expression.
- `provides`, `uses`, `exposes` and `wire` are capability routing. Fuchsia's component framework
  routes the same verbs and validates the same routes before running anything; its aggregate
  capability is this library's fold, and its weak route is the mutual wire.
- The domain model is clan-core's inventory: `instances.<n>.roles.<role>.{machines,tags}.settings`,
  `perInstance` and `perMachine`, `constraints.roles.<role>.{min,max}Machines`, `exports`, and
  `clan.core.vars.generators` with `share` and `deploy`. A slot's `reach` is their constraint and a
  generator's `per` is their `share`. What this library adds is a type on the wire, a total table
  and a plan that is data.
- An interface's claimed identity is a nominal brand over a structural fingerprint, which is what
  Cap'n Proto's type ids and WIT's package identifiers are for, and the failure it fixes is the
  diamond dependency. The fingerprint compares korora type names, so two libraries declaring `url`
  over different predicates claim one identity. Nominal by name is the trade rather than an
  oversight: a predicate cannot be hashed.
- `secrecy` with `plane`, a generator's `deploy` and the image profiles are a two-point
  information-flow lattice over a capability denial table. One rule is checked at three sites:
  `export-secret-not-a-reference`, `vars-not-deployed-opened` and `imageReader.denials`. A fourth
  site is a place to forget it.
- An entry key is input-addressed hashing, which is what a derivation already is. Written by hand
  because `mkPlan` realises nothing.

## No solver, no Datalog, no Prolog

Recorded so the question is answered once.

- Nothing here searches. Placement filters by tag, `alloc.ports` records fixed claims only, and a
  wire is stated and then checked. Adding `placement.pick` or a dynamic port introduces the first
  search in the tree.
- Should one arrive, copy PubGrub's incompatibility tracking rather than a SAT or CP solver. A
  solver answers that the constraints cannot be met; the product here is a sentence naming the
  declaration to edit, and a minimal unsatisfiable core names no resolution.
- Datalog would replace six `groupBy` calls - tags, platform elaborations and placements in
  `lib/resolve.nix`, the two reader indexes in `lib/plan.nix`, unit extensions by backend in
  `lib/module.nix` - and leave the 92 row constructors, the reading in `lib/module.nix` and every
  message. Four reasons it cannot be `lib/`: an engine is a process, and `mkPlan` runs inside a
  pure evaluation a consumer's own flake performs; a relation holds ground terms, while `impl`, a
  korora predicate and a fold are functions, which is why `identityOf` had to project one out to
  compare it at all; bottom-up evaluation has no per-node recovery, which `diag.guard` is; and the
  only recursion in the tree is a generator reading a sibling, the walk in `cli/order.py` being an
  iterative Tarjan over a graph a fleet makes deeper than the interpreter's stack.
  Provenance in Datalog is a proof tree over relation names, not a resolution.
- Prolog adds unification and backtracking, which is the search this design removed, and trades a
  deterministic ordered table for first-solution semantics.
- The part worth borrowing is notation: the delivery set reads as two rules, and a spec may write
  them as rules.

## Purity and totality

Prose: `docs/diagnostics.md`, under "Which layer reports a refusal" and "What is not caught".

- `lib/` never raises: every check returns a row and evaluation stays total.
- `throw`, `abort`, `assert`, `.check ` and `korora.check` MUST NOT appear in `lib/*.nix`.
  `tests/unit/diagnostics.nix` scans the source text, dropping lines whose first non-space
  character is `#`, so a trailing comment on a line of code counts as code and fails the scan.
- korora's `verify` is the only entry point the library uses. `check` raises.
- `builtins.tryEval` catches a `throw` and a failed `assert`, and none of an abort, a missing
  attribute, or a function called without an argument its pattern requires.
- A guard is not a check: every value a declaration wrote is read for its kind before the reading
  indexes into it, `declaredRecord` answering `{ value, rows }` with `{ }` and one
  `declaration-malformed` row. The module's own expression runs under the same `diag.guard`, so a
  declaration that raises is `module-raised` plus `impl-missing` and never a third identifier.
- An `impl` whose argument pattern is closed is `implementation-formals-closed` and is not applied;
  an unwired slot leaves it unapplied too, so the entry is planned and records `units = { }`.
- `mkPlan` realises nothing. A generator's `program` is recorded and never run, read or resolved,
  anything but exactly one store path being `vars-program-malformed`, and it is no closure root and
  no mention site.
- `storeDir` is an argument. Never write `/nix/store` into `lib/`.
- `util.shortHash` discards string context to keep a store reference out of a key string;
  `util.uniqueStrings` keeps it, because that context is what lets a consumer copy the bytes.
- `image/` and `flakelet/` do the opposite and raise: a fact the entry does not record is a refusal
  naming the entry and the field, never a default.
- A refusal belongs to the layer holding the fact - `mkPlan`, `operator/read.nix` for the
  realisation statement, `secrets/read.nix` for the external contract - and
  `tests/unit/diagnostics.nix` crosses each realiser's refusals against the rows above them, off
  the realiser sources it is handed, pairing accounts rather than message fragments.
- `operator/read.nix` is on `lib/`'s side and `operator/default.nix` is on the realisers'. The
  reading is total and every refusal it makes is a row; the derivations over it raise, and a table
  carrying warnings and no error builds.

## Diagnostics

Prose: `docs/diagnostics.md`, which also tables every row a layer of this tree can produce.

- A row is a value a caller returns beside its result. No accumulator, no ambient list.
- `row`, `error` and `warning` are exported from the library, and a producer outside it builds a
  row with them rather than writing the six fields. They are what applies `util.oneLine`, so one
  row is one line whatever a deployment interpolated into it, and a rendered table cannot show a
  row nobody produced.
- Table order is identifier, then subject, then message (`lib/diagnostics.nix`), and
  `fixtures/minimal-typed-edge/plan/diagnostics.txt` is exactly what `nix eval --raw
  .#debug.rendered` prints for the worked deployment, compared byte for byte.
- A subject is a plan key, a path relative to the deployment root, or an issue identifier. An
  absolute path is refused; a message and a resolution keep theirs, naming the file to edit.
- The same fact produced twice is one row. `dedup` keeps the first.
- A refusal is recognised by the marker attribute that constructor writes and by nothing else, so
  a fold's own successful result may carry an attribute named `refused` and is delivered. `impl`
  gains no `refusals` key, and a module may not tag a row's severity.
- `tests/unit/diagnostics.nix` walks two file lists and they are not one list: `totalFiles` is
  `lib/**` plus `operator/read.nix`, which the purity scan reads, and `producingFiles` adds
  `secrets/read.nix`, whose reading writes row identifiers while still raising.
- The host-resource index is two `groupBy` passes over one flat list built in `entries`, each
  claim carrying the field it was recorded under, and a machine's `reserves` is a claimant of it
  keyed `machine:<name>`, earning the entries' own identifiers rather than any of its own.
- A port claim is normalised before anything compares it, so the wildcard has no spelling and
  `0.0.0.0` and `::` are refused; a refused `proto` or `address` widens the claim, a refused
  number drops it, neither reaches `alloc`, and one claim may earn more than one row.
- `implArgs` hands an implementation `member` beside `instance` and `machine`. A composed
  `entryKey` was rejected there.
- `unit-value-newline` is about every string a unit record carries at any depth - a plain field, an
  element of a list, a name or a value of an attribute set, and every field of every extension
  application - and the scan walks the record rather than a list of fields. A name is in scope
  because `image/read.nix` renders a unit's `env` key into the file as `Environment="<k>=<v>"` and
  escapes the key with nothing. One identifier covers every field and the row names the field path.
- `util.anyLineBreak` gates the `util.stringsDeep` walk that builds those paths, and both read
  attribute names or the gate switches the check off silently.
- The row records the offending value and keeps reading: the row, `applicable = false` and the
  realiser's own refusal are the three things that stop the bytes.
- A configuration file's host path is held to the grammar one word of a rendered shell step can
  carry, whose one home is `lib/util.nix` beside `keySeparators`. The check is the library's, so
  every realiser and every plan reader inherits it, and a refused path is left out of the record.
- A unit's environment name is held to `envNameRule` in that same file, an assignment being
  rendered with no escape of the name.

## Keys and identity

Prose: `docs/plan.md`, under "Entry keys" and "Keys and re-keying", and `docs/operator.md`, under
"The artifact name a plan key projects onto".

- An entry key is structural: placement decides it, never units.
- A plan key is `<instance>:<service>@<machine>` and a keyed form appends `@<hash>`. Split at the
  last `@`.
- `@`, `:` and `/` in a machine, instance, member or generator name are
  `name-carries-key-separator`, left out of every key, checked before any key exists, and it is a
  denylist of the three rather than an allowlist.
- A placement onto a machine declaring no `address`, `system` or `serviceManager` is dropped
  rather than planned, so the selection is read twice, what matched and what survived, or a check
  over the survivors would remove its own subject. Completeness is read off the value, so
  `address = 22` is as incomplete as none, and the unplaced reading hands `impl` no `target`.
- A member's identity is its attribute key in the root and nothing else, so `name` inside the
  member is `member-name-disagrees`.
- The delivery set is deliberately not in a generated value's key, and a `program` enters it only
  where one was declared.
- A field enters a key only where its value differs from the default it would resolve to unstated,
  which `withoutDefaults ownershipDefaults` in `lib/plan.nix` holds for both file records. Stating
  a default is therefore no re-key, whichever record states it, and a configuration file's `mode`,
  which has no default to sit at, is always in the key.
- `varsState` is keyed by the value's entry, not by machine: one value has one answer about
  whether it exists however many machines receive it.
- The reservation a machine states is a third projection of the registry reading, outside
  `machineRecords` and `targetOf`, because `machineKey` hashes the record every placed entry and
  per-placement value depends on. The plan records it nowhere and nothing reads it.
- An image's version digest is deliberately not the entry key. It is taken over what the artifact
  holds: a shown path by its bytes where the artifact carries them and by its path where the host
  writes them, and the stated confinement profile is in it because it decides rendered directives.
- An artifact is addressed by the name its plan key projects onto: `:` and `@` become `-`, so
  `issuer:api@alpha` is `entries/issuer-api-alpha`. The projection is not injective, so two keys
  sharing one name is `operator-entry-name-collision` rather than a silent overwrite, and
  `manifest.json` records the mapping.
- The unit file names of one machine are one namespace, so two entries deriving one is
  `operator-entry-unit-file-collision`; that name drops the machine the artifact name carries.

## Interfaces, composition, reads

Prose: `docs/authoring.md` for interfaces, leaf modules, roots and the deployment, and
`docs/plan.md` for what a capability publishes and what a read records.

- The `interfaces` argument is attribution, never a registry, and every row an interface can earn
  is reached from the modules that imported it rather than from that argument. `fileOf` matches by
  value first and by claimed identity second, so the identity pass only turns a miss into a hit.
- A refused claim is an error row with `identityOf` null, which is equal to no claim.
- A member name and a slot name collide one stratum above the wire reading, so the reading below
  decides which of the two a key is from the member set alone.
- `planner.fold "<name>" (set: …)` is `typedef name verify` with the words changed: `foldApply` is
  what the planner applies and `foldName` is what an identity carries.
- A fold normalises and refuses; rendering bytes is the consumer's. A slot whose interface declares
  a fold that can refuse is read under `results ? <slot>`, and no other refused read is guarded: an
  unwired slot is `slot-unwired` before any implementation runs.
- A slot set derived from settings is a warning rather than a refusal, only the `uses` keyset is
  compared, and the baseline reading is `defaults // fixed` rather than `defaults` alone.
- `configDataRecord` records the ownership on both branches, the incomplete one included, so an
  unfinished render cannot read as a record that does not say who opens the file.
- The denial of a delivered file is about permission and not about secrecy, and a unit's declared
  groups are whatever an extension application records under `supplementaryGroups`, under any
  backend, which is how `lib/` asks the question without naming a realiser.
- The readability comparison is one predicate, `util.admits`, asked at the three sites that hold
  the facts, and each names its own row: `lib/plan.nix` for declared reads
  (`slot-reads-value-unreadable-by-user`) and for a configuration file the entry's units are shown
  (`entry-config-file-unreadable-by-user`), `image/read.nix` for the account a profile imposes
  (`imageReader.denials`), and `operator/read.nix` mirroring the third as
  `operator-entry-access-denied`. A fourth site is a place to forget it.
- Its one home is `lib/util.nix`, and `rootAdmitted` is the one thing its callers differ on: true
  for the planner, which reads an unconfined unit as the account it declares, false for the image
  reader, because a profile imposes an account and never imposes root. Two copies is what the tree
  had, and they disagreed. The group clause asks about declared groups under either answer.
- A placed entry carries `closure` and `units` where `pruned` drops every other empty field,
  because an absent field means the plan does not know, which `required` in `image/read.nix`
  refuses.
- A secret export must publish a generated file, never a bare value: `export-secret-not-a-reference`.
  A path in the plan is deliverable; bytes in the plan are a leak.

## Platform record

Prose: `docs/plan.md`, under "The platform record".

- The `is*` predicates are absent on purpose: each is a function of `parsed`, and recording them
  would put seventy-five derived booleans into every entry and every entry's key.
- `platform.gccNames` is written out by hand and must name every `gcc` field the pinned nixpkgs
  sets on any exposed platform. `tests/unit/platform.nix` crosses the list against every double.
- If the upstream guard in `tests/unit/platform.nix` goes red, upstream fixed `_withoutFunctions`.
  Rewrite the measurement in `design.md` D7. Do not delete the guard. Its evidence is the
  surviving function paths, not a failed `toJSON`: serialising a function aborts the suite.

## Realisers

Prose: `docs/flakelet.md` for the flakelet artifact, `docs/secrets.md` for the secrets reading and
the rendered deploy step, and `docs/operator.md` for the realisation statement and the build layer.
The image realiser has no document of its own, so its rules are here in full.

- An image carries an empty file at every host path it is shown. The image root is a read-only
  squashfs, so a missing mount point is not a missing file at run time but a unit that cannot start
  (`Failed to create parent directories …: Read-only file system`, then `226/NAMESPACE`).
- A realiser shows a host path only for a generated file whose entry records `deploy` true. An
  undeployed value is on no machine, so binding its path mounts nothing and the unit fails at
  `226/NAMESPACE` naming neither the value nor the declaration. That is why every file record in
  the plan carries `deploy`: the owner of a `deploy = false` generator runs units of its own, and
  its entry holds the value's path either way so that a site opening it is still a row.
- An image carries no generated bytes, and it binds a configuration file from the store only where
  the plan holds its bytes **and** the record it states is the store's own, `root:root` at `0444`:
  a bind shows the ownership and the mode of what it binds. Anything else the script installs on
  the host, which is also every `ref`-bearing recipe, whose bytes arrive from the host at attach
  time. An edit to a bound literal file therefore moves the image's version digest and an edit to
  an installed one does not.
- The attach script installs every file it puts at a host path through three paths under the
  entry's own staging directory: a recipe is concatenated into `<staged>.assembling`, the
  candidate is created `0600` at `<staged>.installing`, owned and then chmodded to the record, and
  moved onto `<staged>`. Creating the destination and chmod-ing afterwards left it at the
  attaching login's umask for the length of the write, which is a window in which a rendered
  secret is readable by anyone the declaration did not admit, and left a half-written file at that
  mode if the script stopped in between. The move is what makes the window empty rather than
  narrow. Nothing in the recipe may depend on the environment's `umask`.
- `$root` in the attach script is `PORTABLE_PLANNER_ROOT`. It prefixes host state and never a
  store path.
- The attach script owns the machine's state for its entry, and the command takes no decision about
  it: every apply runs it, and it compares what the machine holds against what this build is before
  it changes anything. Which image the entry currently runs from is read from `systemctl show -P
  RootImage` of its own first unit - two builds of one entry render the same unit file names, so a
  listing cannot say which of them a name belongs to - and an image that is neither empty nor this
  one is stopped and detached before this one is attached. The script prints one line per step it
  took and `nothing changed` when it took none, and those lines are what the command reports under
  the activation. The `holds_attached` skip the command used to make is deleted: it asked about the
  *new* image's path, so a changed build read as `detached` and the two collided.
- A configuration file is assembled into its temporary and installed only where it differs from the
  file the machine already holds, and each file the script rewrote reloads exactly the units the
  plan's `reload` list names: `ExecReload` where the unit declared one, a restart where it did not,
  and nothing at all for a unit that is not running. The artifact's `bin/check` is the same
  comparison with no writes, which is what `status` asks to tell an entry whose image matches and
  whose shown bytes do not.
- The attach script creates its whole staging tree in one `install -d -m 0711`, for the reason the
  value directories are `0711`: a unit reaches a staged file by its full path through
  `BindReadOnlyPaths`, so traversal is the only access any account needs, and a listable directory
  publishes the configuration file names of every entry on the machine. Every component is named
  rather than left to `install -d` to create along the way, because a component `install` creates
  for itself is created at the attaching login's umask and not at the mode.
- Every value a generated script interpolates is escaped as one word, in a message as well as in an
  argument, and a unit list is escaped word by word rather than joined. The grammar and the escape
  fail independently: a grammar is a rule a future field can be added without, and the escape is
  what holds for a value no rule has reached yet. `lib.escapeShellArg` leaves a safe-looking word
  bare, which is why `image/default.nix` has a `quoted` of its own for the messages.
- Independence stops at a value the receiving shell re-parses, and the `deploy.remote` step
  `secrets/backend.nix` renders is where that line falls: its remote half names `'$4'` through
  `'$7'` inside single quotes, so the parent directory, the path, the mode and the ownership are
  re-parsed on the machine and are held by `util.wordRule` and nothing else, fourteen sites across
  those four positions, which widening `wordRule` to admit a quote breaks however well the local
  side escapes.
- Each realiser states its own name rule and its own unit rule as the sentence its refusal prints,
  and `operator/read.nix` asks the stated realiser for the two rather than testing which realiser
  it is. The image realiser's rule is the intersection of three constraints it is already inside -
  nix's store name set, systemd's unit name grammar, and one shell word - and it is not the
  library's, because the union of two realisers' grammars refuses a name the stated one accepts.
- Every profile except `trusted` carries `DynamicUser=yes` and `PrivateUsers=yes`.
- A field missing from `systemdDirectives` or `unitDirectives` in `image/read.nix` fails the build
  on purpose, an extension existing to add a field, and the row for an extension field with no
  rendering is `operator-entry-extension-field-unrendered`, read off the stated realiser's table.
- A unit's restart domain is four values, stated once as `restartPolicies` in `lib/atoms.nix`,
  which both the atom's predicate and the `unit-field-type-mismatch` row read.
- A directory is a claim against the machine whether declared through the vocabulary or through a
  backend extension, so `directoriesOf` reads both and `unit-directory-declared-twice` records
  neither statement.
- flakelet decides `[Install]`, no plan field does: an `[Install]` on the service of a scheduled
  unit would run the job once at deploy time and again on its schedule.
- Both realisers are handed the same `assemble` argument, so a configuration file whose bytes the
  plan holds is one store object written once.
- `flakelet/read.nix` restates `validate_name` and `validate_units` from flakelet's own
  `manager.rs`, and `LOCKED_URL_PREFIX` in `tests/e2e/delivery.py` must match the prefix there.
- The secrets reading has two halves and one description per condition: `rows` and `generation`
  answer a table and raise nothing, `store`, `configuration` and `deliveriesOf` refuse with the
  sentence that row states. A file record's ownership is a fifth escaped word `rows` asks nothing
  about, which is `counterexamples.testAnOwnershipTheRenderRefusesIsARowFirst`, and a recipient
  machine with no address is not reachable from an applicable plan, the planner refusing that
  registry first.
- The path has one owner, this library: the contract carries none, so the `deploy.remote` step is
  the only thing that ever states one, and the temporary it fetches into is one for the whole run
  removed by a `trap` installed before the first fetch, `set -eu` exiting where a send is refused.
- Which realiser realises an entry is stated beside the deployment, never inferred: no plan field
  records it and the same entry can legitimately be both. The statement is read by plan key, then
  by the `<instance>:<service>` prefix, then `default`, every field down those same three steps.
  An `image` entry with no `profile` is `operator-image-profile-missing`, never a profile the
  builder chose.
- The reading classifies a plan record by what it records and never by the text of its key: a
  record carrying `delivery` is a generated value, one carrying `placement` is a service entry,
  one carrying neither is a machine record, and one matching none of the three is
  `operator-plan-record-unclassified`.
- A placed entry that declares no unit is realised into nothing: no `path` at all and no artifact,
  the absence being an omitted key rather than a `null`, and only a statement naming it is a row.
- A build of an inapplicable deployment still produces its tree, carries no marker of its own, and
  refuses `passthru.entries.<key>` with `planner.render` of the table.
- The per-entry identity `manifest.json` publishes is the artifact's own version digest, which the
  endpoint stores as `settings_hash`; the plan entry key stays in `plan.json`.
- `operator.mkGeneration` is where the secrets reading is built. `operator/default.nix` takes
  `korora` for `plan.nix` alone, nixpkgs arriving as `pkgs.path` and the library as `../lib`, and
  that expression imports the deployment's `args.nix`, never its `default.nix`.

## The operator's command

Prose: `docs/operator.md`, under "The command", "Where the bytes of a generated value come from",
"The order `apply` walks", "When a run breaks" and "Reaching a machine".

- `apply` orders by every resolved read of `plan.<consumer>.reads.<slot>`, never by `dependsOn`.
  A single-valued read records `entry` and a `reach = "all"` read records `entries` keyed by
  provider, and both are edges. A delivered read recorded in neither shape is the command's own
  refusal naming the consumer and the slot, because an unrecognised shape that contributes zero
  edges is what let that stand. Values are written before any entry is activated, and an entry is
  copied before it is activated.
- The walk refuses in a position a condensation cannot reach: an unorderable state is an
  `ApplyError` naming the entries and the reads, because the `next(...)` that stood there ended a
  run in `StopIteration`, which `cli/planner.py` does not handle.
- A step's line is printed before the step is attempted, so the last one names the step that was
  running. A machine's refusal is the command's own error naming the entry, the machine and what
  the machine printed, never a traceback and never the argv. Nothing after the failed step is
  attempted, and the recovery is a second apply.
- Absence is an endpoint's own answer and nothing else's. A machine with no endpoint, one that
  answers nothing and an entry whose machine declares no address are three other lines, a report
  that could not ask a machine exits non-zero, and only `detached` is a detached image.
- An image names its identity: the record's `key` is the artifact's version digest, an image's file
  name carries it and `portablectl list` prints it, so that half is identity equality and the line
  says `current` or `holds <x>, built <y>`. A flakelet endpoint reports the digest nowhere, so that
  half compares the active generation's unit files. A record publishing no `key` for a placed entry
  is refused; do not delete it as unused. `delivery.endpoint_refusal` records what the locked
  endpoint answers and fails the moment that field set moves.
- Staleness is a line and never an exit status. A report whose machines all answered exits zero
  however stale they are: a stale entry is an answer, and changing it is `apply`'s work.
- A value write compares on the machine and answers `changed` or `unchanged`, and neither the bytes
  nor a digest of them is ever printed or put in an argv. A value that moved restarts its readers
  last, after every activation: the readers are the entries whose resolved reads name that value on
  that machine, which is the same index `cli/order.py` builds its edges from, and the restart is
  `systemctl try-restart` of the entry's whole unit list. Coarse on purpose - the plan says which
  entry reads a value and never which of its units opens the file - and `try-restart` because
  whether a unit runs at all is the activation's answer and never this step's, so a unit an operator
  stopped stays stopped and a unit the activation just started is not restarted twice.
- The harness's recorder keeps the argv and drops the payload: the property asserted is that two
  payloads of one length produce equal vectors.
- The value source is measured under the directories of the value entries the deployment delivers.
  A file under none of them is a claim about no value, and every undeclared file inside one is
  named rather than the first of them.
- A deployment record is refused by its `version` and by its `storeDir` before any entry is read,
  and one carrying no `entries` table is refused rather than read as a deployment that places
  nothing.
- `manifest.json` addresses an artifact inside the build, and the build is a farm of symlinks, so
  `cli/manifest.py` resolves each artifact path to its store path. The path an activation names on
  the machine has to be the path the copy put there.
- `flake.lib`, `flake.mkLib` and `flake.operator` are the whole consumer interface, and the three
  realisers are published as nothing on purpose: `realise` of `mkDeployment` is where a consumer
  states which one reads an entry, and a path inside this flake's source is not an interface.
- `flake.debug` is the development attrset and `planner` is the command in every namespace that
  answers for it: `apps.planner`, `packages.planner` and `packages.planner-src`, with `apps.default`
  the same wrapper.
- `flake.nix` writes its `systems` out rather than taking `nix-systems/default`, which names
  `x86_64-darwin`: the pinned nixpkgs removed that platform with a `throw`, so `nix flake show`
  died in a release note before it reached an output of this flake.
- `tests/e2e/newcomer/template/` writes no path of this repository: every path in it is a host path
  a unit reads at run time or an interpolation of an argument the flake handed it, and
  `testAFileNamesAPathThatIsNotThere` reads that text as this tree's, comments included.
- The one shell takes its root from `git rev-parse --show-toplevel`, and `planner-e2e-env` refuses
  to run outside a checkout of this repository: entered from a foreign tree it would export the
  paths of a checkout the reader is not editing.

## Registration points

Each of these lists is hand-maintained. An addition that skips one fails a check, or worse, is
silently unobserved.

- A new unit suite goes in `suites` in `tests/default.nix`. That attrset is the only registration
  point, and its key names feed the coverage cross-walk. `coverage` is passed its own name too;
  that is not a cycle.
- A counterexample goes where its own failure allows: the suite, the probe file or the command's
  test file, under "Counterexamples on record". A probe is named by existing - `flake-module.nix`
  reads `builtins.attrNames` of `tests/counterexamples/probes.nix` - and a directory beside
  `tests/unit/` and `tests/e2e/` goes in `layers.testTheTestTreeIsRead`.
- A new top-level file or directory goes in `classOf` in `tests/unit/layers.nix`, and in
  `scannedDirectories` there if its files should be held to the path scan.
- A deliverable with its own flake wiring goes in the `imports` of `flake.nix`, the way
  `cli/flake-module.nix` and `devshells.nix` do. An end-to-end folder is the opposite case: it is
  discovered from `tests/e2e/*/deployment/default.nix`, and `flake-module.nix` naming one fails
  `testAnEndToEndFolderIsAddedWithoutEditingTheFlake`.
- A new directory of python modules goes in `programs.mypy.directories` in `treefmt.nix` and in
  `src` in `ruff.toml`.
- A new `spec.md` goes in `accountable` or `excused` in `tests/unit/coverage.nix`, by its path
  under `openspec/`: `specs/<capability>/spec.md` for a current capability, one per capability, and
  `changes/<open-change>/specs/<capability>/spec.md` for a change still open. The suite is handed
  `openspecRoot = ./openspec` rather than the changes directory, and it deliberately does not read
  `changes/archive/`, an archived delta being a record whose content is in the current spec.
  An excuse names the change it rests on and expires the moment that change starts landing, so a
  tasks file states `- [x]` at the start of a line and may name the marker in prose: the reading
  anchors it, and every one of the four production changes documents the trap in prose and would
  have read as landed under an unanchored match.
- Seven changes are open. `answer-whether-a-machine-is-current` stays open because its tasks 1.1
  and 1.2 record themselves as not doable and superseded by `tests/e2e/test_harness.py`, so marking
  them done would falsify the record, and its 21 landed tasks are what the synthetic half of
  `testAnExcuseOutlivesTheStateItDescribes` reads: archiving it moves that probe.
  `declare-service-state` is untouched. `deliver-a-secret-without-exposing-it` is narrowed: its
  `operator/machine-identity` capability, its sections 3 and 5 and its task 7.5 are superseded by
  `name-the-machine-a-run-dials`, and the delta file is deleted, because a capability that never
  landed cannot be the home of a rule the current `planner/machine-platform` spec refuses and the
  current `operator/apply-command` spec licenses. The four that make the tree operable with
  flakelet as the stated realiser are `retire-an-entry-a-build-no-longer-names`,
  `name-the-machine-a-run-dials`, `unseal-a-value-after-a-reboot` and
  `probe-a-service-before-it-counts-as-live`; none has a box ticked, so all fourteen of their delta
  specs are `excused`.
- A directory kind goes in `directoryKinds` in `lib/module.nix`, which is what `unitVocabulary`,
  the two rows about a directory, `directoriesOf` in `lib/plan.nix` and the claim index all read.
  `unitVocabulary` reads it by deriving the kind's own field and its mode field from it rather than
  spelling the six out, because a hand-written vocabulary let a fourth kind be registered and stay
  silently inert: the field was dropped before `typed`, so `unit-directory-declared-twice` and
  `unit-directory-mode-without-directory` could not fire for it and the unit declaring it earned
  `implementation-unknown-key` instead.
  Adding a third *declaration site* for one is the open question
  `openspec/changes/declare-service-state` carries: its path-keyed `implKeys.state` would be a
  third place one directory is stated, and `unit-directory-declared-twice` only refuses two.
  Whichever of the three lands has to decide which site owns the fact, rather than growing a rule
  per pair of sites.
- A new excluded construct goes in `lib/excluded.nix`, the single home of that table - `rows` plus
  `constructs.<key> = { row, trigger }` - and gets a refusal test in `tests/unit/exclusions.nix`,
  whose one scanner reads the table rather than a count written out beside it.
- `README.md` is asserted for two things and no longer for a list of directory names: the example
  it shows is byte-equal to the folder's own, and its no-host-path paragraph still states how a
  path reaches a unit (`testTheRootDocumentStatesHowAPathReachesAUnit`).
- A `#### Scenario:` heading names its test by construction: `test_<snake_case>` under pytest,
  `test<CamelCase>` under nix-unit. A name present in both layers is a failure, not a bonus.
- `openspec/**` is exempt from the path scan: a record describes the repository as it was.
- A count a document records is no longer crossed against the tree: `testASuiteGainsATest`,
  `documentFigures` and `treeFigures` are gone and the requirement is withdrawn rather than
  excused, so a figure in `docs/tooling.md` is a figure a reader maintains.

## Fixtures and goldens

Prose: `docs/tooling.md`, under "Regenerate the golden fixture", and `docs/plan.md`, under "The
committed fixture".

- `fixtures/**` is excluded from the formatter: the suites evaluate it as committed and compare the
  golden plan with `==`, so a formatter would be editing a test's subject.
- Regenerate the golden with `nix eval --json .#debug.worked.plan | jq -S .`. Nothing in the
  evaluating layer can write to the working tree.
- `gamma` deliberately has not run its generator: `set-entry-absent`, the incomplete render and the
  absence marker are what that one absence exercises.
- `vault` carries no `backed-up` tag, or a self-tagged server would put its own key into the set it
  authorizes.
- `borg-repo`'s port 22 is `fixed` rather than a default, because the `url` export is built from
  it, and it is the only `fixed` against `defaults` coverage in the fixture. `borgRepository`
  declares two exports so that provider keyset equality has something to be equal about.
- Package defaults in `tests/unit/worked.nix` are literal store-path strings, and the `packages`
  argument exists so the image check can hand the same deployment real ones.
- A fixture carrying `...` or a hash that is not sixteen hex digits has stopped being evidence.

## Perf harness

Prose: `docs/tooling.md`, under "The performance gate".

- `perf/eval.nix` stays a plain Nix file. Making it a flake attribute folds flake evaluation into
  every gated counter and invalidates all nine recorded budgets at once.
- Fake store hashes are exactly 32 characters of Nix's base 32 (no `e`, `o`, `t`, `u`). Anything
  else stops `util.storePathsIn` recognising the path, and the closure check then exercises
  nothing while the suite stays green.
- `perf/mesh.nix` keeps one unit per peer, each ordered `after` the hub: that reference list
  crossed against the entry's own unit names is the quadratic path the fixture measures. Mesh also
  spells placements as explicit machine lists, where `perf/fleet.nix` uses tags.
- `perf/measure.sh` applies arguments with `--apply` because `nix eval --file` will not auto-call
  a function from `--argstr`.
- A budget is cost per plan entry, with a margin of 0.15 and a growth bound of 1.25 across sizes
  4, 16, 64, and 256.
- `tests/unit/perf.nix` plans size 64 rather than 256, and compares plans rather than deployments,
  because a deployment carries module functions and two functions are never equal in Nix.

## Tooling

Prose: `docs/tooling.md`, under "The other checks", and `docs/cluster.md`, under "Running pytest by
hand".

- The vale wrapper in `treefmt.nix` turns any printed alert into exit 1, because vale itself exits
  0 for warning-level rules. Every `*.md` outside the excludes is linted, this file included.
- mypy runs once per directory of top-level modules. Both `tests/e2e` roots carry `cli` on
  `extraPythonPaths`, and `pythonRoot` turns it into a path relative to the run's directory rather
  than writing that path out, which `layers.testAFileNamesAPathThatIsNotThere` refuses; a store
  path is also wrong, mypy then demanding a `py.typed` marker.
- `ruff.toml` carries the rules because this repository owns no python package, and
  `target-version` is a floor below the devshell's interpreter rather than a record of it.
- `devshells.nix` names no built artifact: a store reference in its hook would make entering the
  checkout build the 3.7 GiB guest image, so the machine layer's variables arrive from
  `eval "$(planner-e2e-env)"`. That file and the `planner-e2e` app are rendered from one attrset,
  `e2eArtifactPaths` in `flake-module.nix`, so a variable added to one is added to both, and the
  shell puts the checkout's `tests/e2e` and `cli` on `PYTHONPATH`.
- `pytest.ini` keeps `-rs`, the skip reason being the only thing that tells an artifact-backed
  suite skipping itself apart from a run with nothing to say, and names `workdirs/` in
  `norecursedirs`, or `pytest .` collects two files called `test_harness.py`.
- `resolve_rookery` builds with `--refresh`, or a branch reference resolves through nix's tarball
  TTL and a run uses whatever rookery was fetched last, which is reported as
  `PYTHON VERSION MISMATCH`: check the resolved revision before changing `pytest-env.nix`.
- `tests/e2e/runner.py` puts `$PLANNER_E2E` and `$PLANNER_CLI_SRC` on the child's `PYTHONPATH` and
  `tests/e2e/conftest.py` edits `sys.path` for neither, because pytest loads no conftest above the
  directory of the ini file it found, so a `sys.path` edit there reaches nothing when one folder is
  named.
- vulture and harper are deliberately not run. Vulture's only finding is `cmd` in the `Runner`
  protocol of `cli/remote.py`, an interface parameter name, and harper flags `realiser`,
  `flakelet` and `keyset`.
- Build the individual check. Never `nix flake check` the whole flake.

## No host path in a deployment

Prose: `README.md`, beside the design goal the rule serves.

- A deployment declares intent and never plumbing: a host path a unit needs is derived by the
  module that needs it, out of the `instance` and `member` of its own entry, or reaches that module
  through an export and a wire. `layers.testTheRootDocumentStatesHowAPathReachesAUnit` reads four
  of the document's phrases back off it with the line breaks flattened.
- Two checks hold it, both reported by `testADeploymentStatesAHostPath`. The scan reads every
  `.nix` file under `tests/e2e/*/deployment/` and `tests/e2e/*/template/deployment/`, splits each
  line on the quote and refuses a fragment beginning with `/` whose first segment is one of
  `etc var run srv opt tmp usr home root nix` and which carries no `${`. Splitting on the quote
  catches a quoted attribute name, which is how `configData."/etc/..."` is written, and the
  intersection refuses a path a folder's `test_*.py` and its own deployment both carry.
- A derived default is impossible, which is why the `recordPath`, `markerPath` and `greetingPath`
  knobs were deleted rather than defaulted: a default is written in the composing root, handed no
  instance (`lib/compose.nix:30-31`), so the path is built inside `impl`.
- Two exemptions. A path only a test knows stays: `portable-image`'s `/run/planner-assembly` fake
  root and `newcomer`'s `/opt/vendor/greeter`. And `fixtures/` and the unit suites' own deployments
  are outside the rule, their paths being compared against goldens.
- The suite is nix-unit inside a pure evaluation, so the scan is a text scan and never `ast-grep`.
  It reads string fragments rather than whole lines, or a comment naming `/etc` fails it.

## End-to-end layer

Prose: `docs/cluster.md`, which describes the host, the folders, the guest image, where the
machines come from and a manual `pytest` run. What follows is what that document does not carry,
`shared-postgres` being the folder it has least of.

- `additionalSpace = "2048M"` is room for the two delivered artifacts and their closures, and
  machine addresses are rookery's static MAC-keyed dnsmasq leases, `10.0.0.(10 + i)`.
- A served unit binds `0.0.0.0` because it starts before the DHCP lease exists; the plan is held to
  the exported URL, which does use `target.address`.
- `--retry` in the probe exists for cross-machine boot ordering, not for flakiness, and
  `schedule = "daily"` keeps the next elapse in the future for the whole run.
- The pytest phases are session-scoped and order-dependent, and the trailing `wait_until_succeeds`
  restores the wire for the phases after it.
- `secret-delivery`'s later phases are the value half of a second apply and run in file order,
  ending with a reboot because `/run` is what it empties: after it the restart step finds a failed
  unit and leaves it alone, which is why that test starts the unit itself. `systemctl is-active`
  exits 3 for an inactive unit, so that assertion uses `ssh` rather than `ssh_succeed`, and the
  reboot is issued in the guest rather than by QMP reset.
- `portable-image` owns every `portablectl` claim, states its attaching entry `strict` because
  enforcement is the claim under test, and builds the same deployment twice; nothing attaches
  `changed`, and one phase stops the units and leaves the image attached, the tool printing
  `attached` there rather than `running` and only `detached` reading as absence.
- Its assembly tests run the artifact's own attach script on the machine, under a
  `PORTABLE_PLANNER_ROOT` of the run's own and with `portablectl` and `systemctl` answered by a
  `PATH` that refuses, so the script stops where the assembly ends, which is the only window in
  which a half-written file exists.
- The fallback in `cli/report.py` for a listing the command cannot read has no test: no real
  `portablectl` prints one and the command runs only inside a cluster, so a rewrite of
  `remote.attachment_of` is unguarded against that branch.
- `tests/e2e/runner.py` puts the roots the app names **before** any inherited `PYTHONPATH`, or a
  checkout shadows the store copies the app had just built; `import_path` is the one place that
  order is decided and
  `test_a_run_reads_the_built_layer_rather_than_a_shell_s_checkout` holds it.
- One case is one ssh command, everything it observes echoed as `key=value` lines: the guest's sshd
  is per-connection socket activated, so a burst of short logins hits the socket's own trigger
  limit and the failure reads as a dead VM, and a value spanning lines is a parse the reader cannot
  make, which is why a file's bytes are compared on the machine.
- A unit of a service artifact runs with the PATH the artifact carries, so `newcomer`'s greeter
  takes `coreutils` as a runtime input. The machine's own PATH is not a fact the plan records.
- `shared-postgres`'s server reads two `configData` files of literals, the configuration file and
  the authentication file it names through `hba_file`, both stating the record a store object
  carries; the data directory is a declared `stateDirectory` with its own mode, not `configData`.
- Its setup is three units, not one script with three guards: `bootstrap` carries
  `startIfPathAbsent` of the file `initdb` writes, `init` is ordered after it and converges every
  role and database on every apply, and `server` follows both. `init` reaches whichever server
  already holds the cluster and starts a private one on a socket of its own when none does, and
  both read the declared configuration file, so `initdb` states no `--auth-*` flag of its own.
- Its DDL converges rather than creates: a database is created where none exists and its owner
  then stated, the role that held it is granted to the new owner, and a role the deployment no
  longer names keeps every object it owns and loses only its login. Every interpolation is escaped
  at its site by the shell's own substitution, so no argument list ever sees a password, and
  `near-app`'s label carries a quote so the escaping is asserted rather than assumed.
- No unit of it is root: the password is delivered `postgres:postgres 0440`, the cluster's units
  run as `postgres`, and each consumer runs as `nobody` declaring
  `supplementaryGroups = [ "postgres" ]` and writing its record under a `runtimeDirectory`, so the
  init script drops privilege nowhere. The account is the guest image's, and
  `tests/unit/layers.nix` crosses every account a folder's unit names against that declaration.
- Its port is a default rather than `fixed`, `lib/module.nix` allocating nothing and two listeners
  on one machine needing two stated numbers: the leaf defaults to 5432 and `own-app` states 5433.
- Every host path of the folder is derived by a module from `${instance}-${member}`, with `-`
  because a key's own separators are refused in the names that enter it, and
  `test_shared_postgres.py` reads each off the plan rather than repeating a constant.
- `alpha` runs four entries and `beta` one, so `own-app:vars/password-private` is delivered to
  `alpha` alone and `beta` keeps a working consumer outside one delivery set.
- Its three app instances are three shapes of one module composing a consumer and a database and
  binding the one to the other: `near-app` and `far-app` cut the database and wire the slot the
  binding left open, `own-app` keeps it and wires nothing. That rewrite moved no plan key and no
  entry record, which is why the folder is where the claim is proven.
- Each app instance owns its own runtime directory, derived from its own identity, the service
  manager deleting one when its unit restarts, so two instances sharing a name lose each other's
  records.
- Its server declares `restart = "on-failure"` with a `restartSec`, so the folder asserts recovery
  from a killed main process beside the deliberate restart, and it builds its deployment twice,
  `default` and `changed`, differing in one database's declared owner.
- The disk that folder's data directories need is its stage's, through `delivery.cluster_stage`'s
  `disk_gib`, and never the shared image's `additionalSpace`: growing the image re-keys every other
  folder's cut, and growing one stage re-keys only its own.
- `tests/unit/layers.nix` recognises a folder that writes state by a module of it naming a path
  under a home the guest image declares for an account, or declaring a `stateDirectory`, which is
  what `testAFolderWritingStateIsRecognisedByWhatItDeclares` is for; `dataDir` in a folder's own
  text is what `byADeletedKnob` refuses.
- Do not "fix" `newcomer`'s fidelity by pinning the template to another nixpkgs: a consumer follows
  the library's pin, and a second one would evaluate the deployment against packages the library
  never saw. The guest image carries `nix-command`, `flakes` and 6 GiB of spare filesystem for that
  machine, all three properties of the shared image, so changing one re-keys every cut.

## Machine layer snapshots

Prose: `docs/cluster.md`, under "Where the machines come from", for the cut, its key and its cache.

- A folder's stage is `@cluster_snapshot_fixture` through `delivery.cluster_stage`, and
  `@snapshot_fixture` is wrong here: a single-VM cut can only resume as slot 0, so two of them are
  both `10.0.0.10` with no route between them.
- A preparation body waits and yields, reading no environment variable and running no program,
  which is why the stage declares no `extra_env`, `extra_files` or `extra_tools`: rookery scrubs
  the environment and confines the body with Landlock.
- Never move a delivery, an activation or an attachment into a preparation: the body does not run
  on a cache hit, so the evidence would be a replay, and `test_a_cut_carries_no_delivery` asserts
  the other half.
- Wait to `multi-user.target`, not just `wait_for_ssh`: the vsock sshd answers before the login
  `PATH` exists, and a cut taken there resumes a half-booted guest.
- `tests/e2e/conftest.py`'s `state_root` is resolved by rookery **by name**; renaming it silently
  moves every run's state to rookery's own default root.
- Edit `tests/e2e/guest.nix` and then run `rookery snapshot gc --all` before anything else.
  Observed after the `postgres` account was added: folders resumed a cut whose frozen RAM names a
  system generation the new image's disk does not carry, so `/run/current-system/sw/bin` is a
  directory of dangling symlinks and every remote command answers `mkdir: command not found` while
  `$PATH` reads correctly. It looks like a broken write script and is a stale cut.

## Known bugs

- New files are invisible to the flake until `git add`, and the coverage cross-walk then reports
  the spec it cannot read rather than the file you forgot to stage.
- `-k wire` selects every `wired-pair` test: pytest matches the folder name too.
- Deleting a comment leaves the blank line that framed it, and `checks.treefmt` then fails on
  formatting rather than on prose. `nix fmt` after any comment removal.
- The comment strip cut five comments in half, leaving a mid-sentence fragment above the argument
  list of `lib/interface.nix`, `tests/unit/coverage.nix`, `tests/unit/worked.nix` and two fixture
  files. Removed. A blanket comment removal wants a check for a surviving `#` line.
- `mypy --strict` inside the `tests/e2e` treefmt root answers `INTERNAL ERROR` intermittently
  under mypy 2.1.0, in the build sandbox and with no file named. Rerun before believing a mypy
  failure; the same arguments in the devshell pass.
- `tests/unit/layers.nix` scans raw file text, comments included, and its
  `testAFileNamesAPathThatIsNotThere` catches stale path references that live in comments. A path
  written in a comment therefore has to resolve, and a foreign repository's file is named without
  a repository-rooted prefix.
- The external generator's `generate.py` at the pinned revision writes PEP 758 unparenthesized
  `except A, B:`, so it parses under python 3.14 and under nothing older. The pinned nixpkgs'
  `python3` is 3.14, which is the only reason the composition runs at all.
- An entry realised into nothing carries no artifact path: `operator/read.nix` omits `path` from its
  record and the command reads the field as optional. Both sides move together. A record stating
  `path` as `null` is read as an omission, not refused: JSON `null` decodes to `None` and
  `record.get("path")` cannot tell it from an absent key (`cli/manifest.py`). Only the empty string
  is refused. The behaviour is the useful one; the sentence that claimed otherwise was stale.
- The purity scan in `tests/unit/diagnostics.nix` is substring matching over comment-stripped text,
  so `.check ` matches inside a string literal and `assert ` misses a call spelled with no space.
  It also misses korora's `check` bound as a value rather than applied - `atoms.port.check` written
  `.check;`, `.check)` or at the end of a line - and it can only see a raising call at all, while
  every probe in `tests/counterexamples/` raises through a call of a non-function, a wrong-arity
  pattern, a missing attribute or a coercion. A `throw`-free file is not a total file.
  `ast-grep` is installed and parses.
- `util.shortHash` discards string context to keep store references out of a key string, not
  because `builtins.hashString` refuses one: under nix 2.34.8 it accepts a context-carrying string.
  The discard is still load-bearing; the reason recorded beside it was wrong.

## Counterexamples on record

Every invariant above that the tree does not hold has a test that asserts the claim rather than the
behaviour, so each is red until the claim is made true or withdrawn. Three homes, by what the
counterexample does:

- It can be evaluated: `tests/unit/counterexamples.nix`, a suite like any other, registered in
  `tests/default.nix` with its figure in `docs/tooling.md`.
- It ends the evaluation: `tests/counterexamples/probes.nix`, one attribute per break, each
  evaluated in its own process by `checks.planner-counterexamples-eval`. A nix-unit `expr` cannot
  hold an uncatchable raise - a call of a non-function, a missing attribute, `toJSON` of a function
  - because the raise takes the run that would report it. An attribute answering `"ok"` means the
  defect is fixed, and the probe stays as the regression pin. `tests/` therefore holds three kinds
  of test, which `layers.testTheTestTreeIsRead` states.
- It is about the operator's command: `cli/counterexample_test.py`, run by
  `checks.planner-counterexamples-cli`. Python, because the command is run rather than evaluated.

The families they cover: `lib/` raising where a row is owed (an `impl` that is not a function, one
with strict formals, one that raises inside the guard that caught it, a recipe fragment of another
kind, a settings knob holding a function, `mkPlan`'s own arguments, a `varsState` answer of another
kind); a key that names two things (two entries of one machine deriving one unit file name, a
service entry replacing a machine record, a value the secrets projection cannot see); a no-op
declaration edit that re-keys (a file record or a configuration file's ownership stated at its own
default); the diagnostics discipline (a subject carrying a line break, a name the key grammar
admits and the subject rule refuses, two rows collapsing into one, a severity outside the domain, a
fold refusal carrying a carriage return); secrecy and readability (a secret export backed by a
public file, a unit that cannot open its own value, a value path named outside its delivery set);
identity (two struct schemas under one claimed `id`, attribution deciding applicability); and the
realisers (a `configData` source outside the store, two shown paths that nest, a unit name or an
`env` name that forges a directive, a version digest that ignores the confinement profile).
