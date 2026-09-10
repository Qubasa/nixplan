This file holds project invariants, if you encounter a project invariant that has not been written down yet,
please add it to this file. Also if you encounter bugs, you can add them here such that next time we won't make that mistake again.
Keep it concise and human readable please.

Commit `c6fcb62` deleted every comment in the tree. The load-bearing ones are back at their own
constructs, shortened. This file is the index of the same invariants, so a rule can be found
without reading the code first.

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
  `lib/module.nix` - and leave the 83 row constructors, the reading in `lib/module.nix` and every
  message. Four reasons it cannot be `lib/`: an engine is a process, and `mkPlan` runs inside a
  pure evaluation a consumer's own flake performs; a relation holds ground terms, while `impl`, a
  korora predicate and a fold are functions, which is why `identityOf` had to project one out to
  compare it at all; bottom-up evaluation has no per-node recovery, which `diag.guard` is; and the
  only recursion in the tree is a generator reading a sibling and the walk in `cli/order.py`.
  Provenance in Datalog is a proof tree over relation names, not a resolution.
- Prolog adds unification and backtracking, which is the search this design removed, and trades a
  deterministic ordered table for first-solution semantics.
- The part worth borrowing is notation: the delivery set reads as two rules, and a spec may write
  them as rules.

## Purity and totality

- `lib/` never raises. Every check returns a diagnostics row, and evaluation stays total: one
  malformed declaration becomes a row and the rest is still read.
- `throw`, `abort`, `assert`, `.check ` and `korora.check` MUST NOT appear in `lib/*.nix`.
  `tests/unit/diagnostics.nix` scans the source text for them. It drops lines whose first
  non-space character is `#`, so prose may name a raising call, but a trailing comment on a line
  of code counts as code and fails the scan.
- korora's `verify` is the only entry point the library uses. `check` raises.
- `builtins.tryEval` catches a `throw` and a failed `assert`. It catches neither an abort nor a
  missing attribute, and both are documented as propagating. A missing attribute inside `lib/` is
  a bug that fails the suite loudly.
- `mkPlan` realises nothing: no derivation, no filesystem read, no network, and every store path
  in a plan is a literal string.
- A generator's `program` is recorded and never run, never read and never resolved. `lib/` checks
  only that it is exactly one store path; anything else is `vars-program-malformed`, and omitting
  the key is no row at all. A deployment declares `drvPath`, because the external contract wants a
  derivation and a `drvPath` is a string a pure evaluation can produce.
- That program is no closure root and no mention site. A generator runs where the plan is read, so
  making it a root would send every deployment's generators to every machine that receives one of
  their outputs.
- `storeDir` is an argument. Never write `/nix/store` into `lib/`.
- `util.shortHash` discards string context on purpose: `hashString` refuses a context-carrying
  string, and a plan of a real deployment has to stay keyable. `util.uniqueStrings` keeps context,
  because a closure root's context is what lets a consumer copy the bytes.
- `image/` and `flakelet/` do the opposite and raise. A fact the entry does not record is a
  refusal naming the entry and the field, never a default.
- Three layers hold three kinds of fact, and a refusal belongs to the layer that holds one. A fact
  the plan carries is a row from `mkPlan`. A fact the realisation statement carries is a row from
  `operator/read.nix`, which is the only layer handed the statement. A fact the external
  generator's contract carries is a row from `secrets/read.nix`, which is the only layer handed
  that. A realiser raises only for a condition one of those already reported as an error row, so
  no path through a deployment build or a generation build reaches a raise before a row. A raise
  is what a caller reaching `image/read.nix`, `flakelet/read.nix` or `secrets/read.nix` directly
  receives, and every one of those refusals carries the identifier of the row that reports it, or
  a recorded reason why no deployment reaches it. `tests/unit/diagnostics.nix` crosses that data
  against the rows `lib/`, `operator/read.nix` and the secrets reading produce: a refusal with no
  row above it fails the suite, an account naming a row nobody produces fails it, and which files
  are examined is read off the realiser sources the suite is handed rather than written out, so a
  fourth realiser is accounted for by existing. The pairing is the account and never a fragment of
  a message, so rewording a refusal moves nothing. The reading asks each realiser for the rules
  only it knows rather than restating one, so the row and the raise print the same sentence.
- `operator/read.nix` is on `lib/`'s side and `operator/default.nix` is on the realisers'. The
  reading is total and every refusal it makes is a row, so a unit suite can assert the decision; the
  derivations over it raise, and the message of an inapplicable deployment is `planner.render` of
  the planner's own table. A table carrying warnings and no error builds, because a warning that
  stopped a build would be an error.

## Diagnostics

- A row is a value a caller returns beside its result. No accumulator, no ambient list.
- `row`, `error` and `warning` are exported from the library, and a producer outside it builds a
  row with them rather than writing the six fields. They are what applies `util.oneLine`, so one
  row is one line whatever a deployment interpolated into it, and a rendered table cannot show a
  row nobody produced.
- Table order is identifier, then subject, then message, so two evaluations of one input render
  the same bytes. `fixtures/minimal-typed-edge/plan/diagnostics.txt` is compared against that.
- A subject is a plan key, a path relative to the deployment root, or an issue identifier. An
  absolute path is refused, because a rendered table would differ between checkouts. A message and
  a resolution keep their absolute paths on purpose: they name the file to edit.
- The same fact produced twice is one row. `dedup` keeps the first.
- An interface fold is the only channel through which a module refuses a value another module
  produced. The fold returns `{ refused = "<why>"; }` and supplies the message; the planner
  supplies the identifier, the consuming entry as subject and the severity. `impl` gains no
  `refusals` key, and a module still may not tag a row's severity. `builtins.tryEval` reports that
  something raised and never what it said, which is why a refusal is a returned value and why
  `module-raised` carries the planner's text rather than the author's.

## Keys and identity

- An entry key is structural: placement decides it, never units. Two instances that wire each
  other would otherwise each need the other's units to know its own key.
- A plan key is `<instance>:<service>@<machine>`, and a keyed form appends `@<hash>`. Split at the
  last `@`.
- A name entering a key is held to the grammar the key can carry: `@`, `:` and `/` are what a key
  splits on, so a machine, an instance, a member or a generator carrying one is
  `name-carries-key-separator` and is left out of every key the plan builds. The check is in the
  reading of each, before any key exists, so no delivery set is ever derived from an ambiguous
  key. It is a denylist of the three separators rather than an allowlist, which would refuse names
  existing deployments legitimately use.
- A member's identity is its attribute key in the root, and nothing else. Placement, the settings
  namespace and every plan key read that key, so `name` inside the member is a second spelling
  nothing can address, and a member naming itself something else is `member-name-disagrees`.
- A generated value is an entry of its own: `<instance>:vars/<generator>` for `per = "instance"`,
  `<instance>:vars/<generator>@<machine>` for `per = "placement"`. A value delivered to a machine
  that runs none of the services reading it has no unit entry to live in.
- The delivery set is deliberately not in a value's key. A machine joining because a new consumer
  declared a read does not change the value, and re-keying it would ask for a regeneration of
  bytes that are still correct.
- A `program` enters its value's key only where one was declared, which leaves a plan written
  before the field existed keyed as it was. A value generated by another program is another value.
- `varsState` is keyed by the value's entry, not by machine: one value has one answer about
  whether it exists however many machines receive it.
- An image's version digest is deliberately not the entry key. A configuration file's content
  moves the key and never enters the image, so keying the image on it would rebuild equal bytes.
- An artifact is addressed by the name its plan key projects onto: `:` and `@` become `-`, so
  `issuer:api@alpha` is `entries/issuer-api-alpha`. The key itself is not a directory name because
  `@` and `:` are what the key grammar splits on, and a name the caller chooses is the local
  convention that cannot be generic. The projection is not injective, so two keys sharing one name
  is `operator-entry-name-collision` rather than a silent overwrite, and `manifest.json` records the
  mapping so nothing reconstructs a name from a key.

## Interfaces, composition, reads

- An interface is identified by the value an author imported **or** by an identity it claims with
  an `id`. `name` is a label for row text; two interfaces in two files may share one. The
  `interfaces` argument is attribution, never a registry: an interface absent from it is still an
  interface, and a claim registers nothing either.
- A claim is the `id`, each export's name, korora type name (`type.name`, which carries
  `attrsOf<string>` where `__name` says `attrsOf`) and resolved secrecy, and the fold's name. It
  carries no function at any depth, which is what lets it survive two evaluations of `lib/`: this
  library's atoms are `korora.typedef` applied to a fresh predicate, so two evaluations produce
  unequal atoms and unequal interfaces over them, while korora's own types survive because
  `import` is memoised by path.
- Both ends must claim before a claim is used. Where either claims nothing the rule is value
  equality, so adopting an `id` breaks no wire that resolves today, and taking one side's word
  would capture a far end that never agreed. Value equality is tried first, so an in-repository
  wire costs what it cost before.
- A refused claim - a malformed `id`, an unnamed fold beside an `id`, a fold name that is not a
  name - is an error row and the interface falls back to its value. `identityOf` is `null` there,
  and null is equal to no claim.
- Two interfaces claiming one `id` whose identities differ is `interface-id-conflict`, observable
  from the registry and at a wire and reported once: both sites build the row through
  `interface.conflictRow`, so `dedup` (id, subject, message) keeps one. Subjecting the wire's copy
  to the consuming entry instead would put two rows in the table for one conflict.
- Attribution follows the same rule: `fileOf` matches by value first and by claimed identity
  second, so the identity pass only ever turns a miss into a hit.
- A claimed identity is recorded at `provides.<capability>.interfaceId` and is absent where nothing
  was claimed. It is not in `keyInput`: a claim decides which edges exist, not what an entry was
  rendered from.
- A root keys each member's settings under that member's own name, including when it owns exactly
  one member, and forwards nothing.
- Two instances wiring each other is not a cycle: a capability's exports are a function of module
  and settings, never of a wire. Do not add cycle detection.
- A refused read leaves the slot absent from `results` - not `null`, not `{}`. `or [ ]` cannot be
  written, so it cannot silently succeed.
- An interface may own the fold of a set-valued read, and the planner applies it under `diag.guard`
  to the value the read already built. What the plan records is the entry-keyed set either way:
  only `results.<slot>` changes, so no plan field says whether a fold ran. A fold that raises
  leaves the slot absent rather than empty, a fold that is not a function is a row against the
  interface's declaring file, and a fold no set-valued read applies is a warning - where "applies"
  is the same rule a wire matches by, so an interface whose claim-equal twin is read with set reach
  is not reported as unread. A fold may be spelled `planner.fold "<name>" (set: …)`, which is
  `typedef name verify` with the words changed: `foldApply` is what the planner applies and
  `foldName` is what an identity carries. A bare function stays legal, an `id` requires a name, and
  two folds carrying one name are not required to be one function.
- The slot set a member asks for may be derived from its settings, and that is a warning row rather
  than a refusal: a removed slot is otherwise the one declaration difference nothing records, since
  nobody wires it and no `slot-unwired` row misses it. Only the `uses` keyset is compared. A
  `provides` keyset is blessed by `unify-declaration-and-implementation-readings`, and a value
  inside a slot, a claim, a generator or an export is ordinary. The baseline reading is `defaults //
  fixed`, the member's own values, never `defaults` alone: a knob a module declares `fixed` without
  defaulting it is missing under bare defaults, and a `uses` set reading it then aborts `mkPlan`
  instead of producing a row. The second reading is taken only where a knob's source is the
  deployment, because with no deployment knob the two readings are one value by construction.
- A unit reference (`after`, `requires`) is checked against the units the module declared itself.
- The delivery set of a generated value comes from the owner's placements plus the machine of
  every entry that declared a read of an export backed by one of its files. Nothing else enters
  it: not the value; not the interface; not what `impl` interpolates. A routable secret is bounded
  by nobody, so a declared read is the only thing that widens the set. An omitted read is the only
  thing that narrows it.
- Every value entry carries `delivery` and `deliveryDerivedFrom` whether or not either holds
  anything. A reader must not be able to mistake either field for an absence.
- A value entry carries `files` for the same reason and on the same terms: a generator declaring
  none records an empty set, not no field. `operator/read.nix` indexes it, and a pruned absence
  there is indistinguishable from a plan that never had the field.
- Every row an interface can earn is reached from the modules that imported it, never from the
  `interfaces` argument. Attribution decides what a row says and nothing about which rows exist,
  so an interface a deployment lists nowhere earns the same identity, fold and export rows a
  listed one does.
- A placed entry carries `closure` and `units` for the same reason: `pruned` in `lib/plan.nix`
  drops an empty list and an empty attrset from every other field, and those two are what a
  realisation reads. An empty closure means the entry depends on no store path and an empty unit
  set means it runs nothing, while an absent field means the plan does not know, which
  `required` in `image/read.nix` refuses. An entry that is placed nowhere records neither.
- A `deploy = false` generator's value still exists and its public files still travel in the plan.
  What is refused is opening one of its files on a machine. A unit or configuration file of the
  owner is `vars-not-deployed-opened`; a consumer's declared read is `slot-reads-undeployed-value`.
- A secret export must publish a generated file, never a bare value: `export-secret-not-a-reference`.
  A path in the plan is deliverable; bytes in the plan are a leak.
- A fold normalises and refuses; rendering bytes is the consumer's. One interface has one fold and
  any number of consumers, so a fold that returned a file would make a second output format a
  reason to declare a second interface, which is a policy construct answering a formatting
  question. A refusal reaches a reader only where no implementation forces the absent slot:
  `applicable` forces the whole table and a missing attribute is uncatchable, so one consumer
  reading `results.<slot>` unconditionally leaves the row produced and no table to print it in.
  That is why a slot whose interface declares a fold that can refuse is read under
  `results ? <slot>`, and why no other refused read is guarded: an unwired slot is `slot-unwired`
  before any implementation runs.

## Platform record

- The `is*` predicates are absent on purpose: each is a function of `parsed`, and recording them
  would put seventy-five derived booleans into every entry and every entry's key.
- `platform.gccNames` is written out by hand and must name every `gcc` field the pinned nixpkgs
  sets on any exposed platform. `tests/unit/platform.nix` crosses the list against every double.
- A declared microarchitecture replaces the whole `gcc` group rather than merging into it, because
  `elaborate` applies its arguments over `platforms.select`. That is what `crossSystem` does too.
- If the upstream guard in `tests/unit/platform.nix` goes red, upstream fixed `_withoutFunctions`.
  Rewrite the measurement in `design.md` D7. Do not delete the guard. Its evidence is the
  surviving function paths, not a failed `toJSON`: serialising a function aborts the suite.

## Realisers

- An image carries an empty file at every host path it is shown. The image root is a read-only
  squashfs, so a missing mount point is not a missing file at run time but a unit that cannot start
  (`Failed to create parent directories …: Read-only file system`, then `226/NAMESPACE`).
- A realiser shows a host path only for a generated file whose entry records `deploy` true. An
  undeployed value is on no machine, so binding its path mounts nothing and the unit fails at
  `226/NAMESPACE` naming neither the value nor the declaration. That is why every file record in
  the plan carries `deploy`: the owner of a `deploy = false` generator runs units of its own, and
  its entry holds the value's path either way so that a site opening it is still a row.
- An image carries no configuration bytes and no generated bytes. They arrive from the host at
  attach time, which keeps an image byte-identical across a configuration edit.
- The attach script assembles a configuration file into a temporary the `install -m` beside it
  created at the declared mode, and installs that at the same mode. Creating the file with `: >`
  and chmod-ing afterwards left it at the attaching login's umask for the length of the append,
  which is a window in which a rendered secret is readable by anyone the declaration did not
  admit, and left a half-written file at that mode if the script stopped in between. Nothing in
  the recipe may depend on the environment's `umask`.
- `$root` in the attach script is `PORTABLE_PLANNER_ROOT`. It prefixes host state and never a
  store path.
- Every profile except `trusted` carries `DynamicUser=yes` and `PrivateUsers=yes`.
- A field missing from `systemdDirectives` in `image/read.nix` fails the build on purpose. An
  extension exists to add a field, so dropping one would make the extension a comment.
- flakelet decides `[Install]`, no plan field does. A long-running unit is wanted by
  `multi-user.target`; a scheduled unit's timer is wanted by `timers.target` and its service is
  wanted by nothing. An `[Install]` on that service runs the job once at deploy time and again on
  its schedule.
- The flakelet realiser refuses an entry shown a host path it would have to assemble - a
  configuration file - because it has no assemble step. A delivered generated file is its own
  source (`from == path`) and arrives before activation, so it is not refused.
- `flakelet/read.nix` restates two rules from flakelet's own `manager.rs`: `validate_name` and
  `validate_units`. `LOCKED_URL_PREFIX` in `tests/e2e/delivery.py` must match the prefix written
  there.
- The secrets reading has two halves, the way `operator/read.nix` and `operator/default.nix` do,
  and one description per condition: `rows` and `generation` answer a table and raise nothing,
  `store`, `configuration` and `deliveriesOf` refuse with the sentence that row states, and
  `operator.mkGeneration` writes `diagnostics.json` and `diagnostics.txt` into the generation farm
  and refuses through `planner.render` of the whole table. Four of its conditions are reachable
  from a plan the planner calls applicable: a value recording no `program`, a file name outside the
  contract's grammar, a recipient machine with no address, and an address the rendered step cannot
  carry as one shell word. A missing address is an error there and a warning of a deployment build,
  because the rendered step is the one build artifact that carries an address.
- The secrets realiser projects a value's key onto `<instance>:<generator>`, and onto
  `<instance>:<generator>:<machine>` for a per-placement value. A colon is what the contract's
  `safe-name` admits and `/` and `@` are not, and a hash would make the tool's own listing and its
  prompts about deleting something unattributable. Four refusals, each naming both sides: two keys
  projecting onto one name, a component carrying the separator, a component outside the contract's
  grammar, and an entry recording no `program`.
- The path has one owner, this library. The contract carries none, a store entry's file record
  being the single boolean `deploy`, and the `deploy.remote` step `secrets/backend.nix` renders is
  therefore the only thing that ever states a path: the external side never has to agree about
  one. That step carries no bytes: every file is fetched from the store backend's own `get` at run
  time.
- Which realiser realises an entry is stated beside the deployment, never inferred: no plan field
  records it and the same entry can legitimately be both, which `portable-image` and `wired-pair`
  demonstrate between them. The statement is read by plan key, then by the `<instance>:<service>`
  prefix, then `default`, and `flakelet` is the default because it needs no further fact. An `image`
  entry with no `profile` is `operator-image-profile-missing`, never a profile the builder chose.
  Every field is resolved down those same three steps, so a `profile` inherits from `default` the
  way a `realiser` does and no reader has to know which fields inherit.
- The reading classifies a plan record by what it records and never by the text of its key: a
  record carrying `delivery` is a generated value, one carrying `placement` is a service entry,
  one carrying neither is a machine record, and one matching none of the three is
  `operator-plan-record-unclassified`. `machine` is a legal instance name and `vars/x` a legal
  member name, so a prefix match answers wrongly for a deployment the planner accepts. A key is
  read only for the instance, the service and the machine of a placed entry.
- A placed entry that declares no unit is realised into nothing: it is in the deployment record
  with its machine and a `null` artifact, it contributes no artifact, and only a statement naming
  it is a row.
- A build of an inapplicable deployment still produces its tree. `plan.json`, `diagnostics.json`
  and `diagnostics.txt` are always there, no artifact of any entry is, the tree carries no marker
  of its own, and `passthru.entries.<key>` of such a deployment is the raise that carries
  `planner.render` of the table.
- `operator-entry-machine-no-address` is a warning. An address is read by the step that dials a
  machine and by no step that builds one, so the record carries the absence and every artifact is
  built; refusing to dial belongs to the command, under "The command refuses before it dials".
- The per-entry identity `manifest.json` publishes is the artifact's own version digest, which is
  what the endpoint stores as `settings_hash`. The plan entry key stays in `plan.json`: an address
  edit moves it and no byte of any artifact, so publishing it would present every entry on that
  machine as a new generation of identical content.
- `operator.mkGeneration` is where the secrets reading is built, so a folder or a consumer reaches
  it through the one thing that already builds a deployment. It writes `secrets.json`, `names.json`
  and `plan.nix`, and `operator/default.nix` takes `korora` for that last file alone: a plan
  carrying a generated value's bytes cannot be a build artifact of a run that has generated
  nothing yet, so what is built is an expression that instantiates the same library again. nixpkgs
  arrives as `pkgs.path` and the library as `../lib`, which is why neither is an argument. The
  expression imports the deployment's `args.nix`, never its `default.nix`: that one takes `pkgs`,
  which no evaluation outside a build can hand it.

## The operator's command

- `operator/` is evaluated and `cli/` is run. They are one role and two kinds of thing, so they are
  two directories that import nothing of each other: merging them would put a python file under a
  directory the unit layer imports, and an interpreter in the closure of what
  `tests/unit/operator.nix` evaluates.
- The command is wired by `cli/flake-module.nix`, imported by `flake.nix` beside `./flake-module.nix`
  and `./devshells.nix`. The root module is where the suites, the perf harness and the machine layer
  are registered, and it reads `PLANNER_CLI` and `PLANNER_CLI_SRC` off that module's own attributes
  rather than constructing either, so a rename cannot leave the app and the environment disagreeing.
- `cli/` imports nothing under `lib/`, `operator/` or `tests/`. Its inputs are a built directory, a
  flake reference and a value source, and what a deployment is it learns from `manifest.json`.
- `apply` orders by every resolved read of `plan.<consumer>.reads.<slot>`, never by `dependsOn`: a
  consumer's `dependsOn` is `machine:<name>@<hash>`, which is key provenance rather than order.
  A single-valued read records `entry` and a `reach = "all"` read records `entries` keyed by
  provider, and both are edges: reading only `entry` silently dropped every set-valued read and
  left a consumer activated before its providers. A delivered read recorded in neither shape is
  the command's own refusal naming the consumer and the slot, because an unrecognised shape that
  contributes zero edges is what let that stand. Values are written before any entry is
  activated, and an entry is copied before it is activated.
- Two instances wiring each other is a legal deployment whose activation graph has no first element,
  so the walk contradicts an edge rather than refusing. Only an edge on a cycle is contradicted:
  with nothing ready it takes the lowest entry every unapplied provider of which is reachable from
  it, contradicts exactly the reads into that entry and prints each, and a provider left behind by
  a contradicted edge is applied at the first opportunity. An entry that merely reads into a cycle
  keeps its order. Refusing would refuse a deployment the library accepts; silence would make a
  one-off startup failure unexplainable.
- A step's line is printed before the step is attempted, so the last step line a run printed names
  the step that was running when it ended, and a failure line follows it. A machine's refusal is
  the command's own error naming the entry, the machine and what the machine printed, never a
  traceback and never the argv: a value write carries the bytes of a secret. The run attempts
  nothing after the step that broke, and the recovery is a second apply.
- `--dry-run` replaces the channel every remote step goes through, and nothing else. Every refusal
  the command makes is made from the plan, the deployment record and the value source, all of which
  are read before the first dial, so the two runs are comparable line by line and the mode is not a
  second copy of the walk. What a machine currently holds is not a question it answers; `status` is.
- Absence is an endpoint's own answer and nothing else's. A machine with no endpoint, a machine
  that answers nothing and an entry whose machine declares no address are three other lines, one
  each, printed as they are known; a report that could not ask a machine exits non-zero. Only
  `detached` is a detached image: `portablectl is-attached` prints four words for one a machine
  holds.
- The value source is measured under the directories of the value entries the deployment delivers.
  A file under none of them is a claim about no value, and every undeclared file inside one is
  named rather than the first of them.
- A deployment record is refused by its `version` and by its `storeDir`, before any entry of it is
  read, and a record carrying no `entries` table is refused rather than read as a deployment that
  places nothing. An entry's `address` may be absent, because a machine declaring none is a warning
  of the planner; the refusal is made where the machine would be dialled.
- The ssh options the command adds - `BatchMode`, `ConnectTimeout` and the server-alive pair - are
  appended to the caller's `NIX_SSHOPTS`, never prepended, because ssh takes the first value it is
  given for an option. They bound silence and never work: a first `nix copy` onto a fresh machine
  legitimately runs for minutes.
- The value source is a directory of bytes and nothing in this repository fills it. The required
  set is the declared files of every delivered value entry that records no `program`: bytes are
  needed only for a file that will be written, the plan carries the bytes of nothing, and a value
  whose entry names a generator is produced and delivered by the external tool. A source holding
  one of those files is refused naming the program, rather than being read as an undeclared file.
- `manifest.json` addresses an artifact inside the build, and the build is a farm of symlinks, so
  `cli/manifest.py` resolves each artifact path to its store path. The path an activation names on
  the machine has to be the path the copy put there.
- `flake.lib`, `flake.mkLib` and `flake.operator` are the whole consumer interface, and all three
  are system-independent because each takes the caller's own `pkgs`. A consumer that can only reach
  the planner can plan and cannot build, which is what `flake.operator` exists to prevent; a path
  inside this flake's source is not an interface and neither is anything under `tests/`. The three
  realisers are published as nothing on purpose: which realiser reads an entry is a statement
  beside the deployment, so `realise` of `mkDeployment` is where a consumer says it, and their
  source paths reach the suites as arguments rather than as outputs.
- `platformSource` is the identity of the package set whose `lib.systems` elaborated a machine's
  platform record. A record is a field of every placed entry and a key is a digest over the entry,
  so the elaboration decides identity, and `flake.lib` records `inputs.nixpkgs.rev` for the pin
  this flake carries. `flake.mkLib` is the way out of that pin for a consumer following another
  package set, and the library invents no name where a caller states none: two elaborations of one
  deployment are two plans, and nothing merges them.
- `flake.debug` is the development attrset - the worked plan, the suites and their failures - and
  `planner` is the command in every namespace that answers for it: `apps.planner`,
  `packages.planner` and `packages.planner-src`. One name answering both a debug value and the
  program an operator installs is what a reader trips on, and `docs/tooling.md` is written against
  the debug name.
- `flake.nix` writes its `systems` out rather than taking `nix-systems/default`, which names
  `x86_64-darwin`. The pinned nixpkgs removed that platform with a `throw`, so `nix flake show` died
  in a release note before it reached an output of this flake. Filtering the input's list instead
  would leave two sources of truth for a set this flake states in one line.
- `apps.default` and `apps.planner` are the same wrapper. `nix run .` is the first thing a reader
  types and the command is the only thing here worth running.
- The smallest example `docs/README.md` shows is the deployment `tests/e2e/newcomer/template/` holds,
  and `README.md` shows that template's `flake.nix`. Both comparisons are byte equality in
  `tests/unit/layers.nix`, so a documented example that stopped building fails a check naming the
  document and the folder. The template therefore writes no path of this repository: every path in
  it is either a host path a unit reads at run time or an interpolation of an argument the flake
  handed it. A path relative to a repository resolves from the reader's own tree there, and
  `testAFileNamesAPathThatIsNotThere` reads that text as this tree's, comments included.
- The one shell takes its root from `git rev-parse --show-toplevel`, and `planner-e2e-env` refuses
  to run outside a checkout of this repository. The shell is documentation about this tree: entered
  from a foreign one it would export the paths of a checkout the reader is not editing.

## Registration points

Each of these lists is hand-maintained. An addition that skips one fails a check, or worse, is
silently unobserved.

- A new unit suite goes in `suites` in `tests/default.nix`. That attrset is the only registration
  point, and its key names feed the coverage cross-walk. `coverage` is passed its own name too;
  that is not a cycle.
- A new top-level file or directory goes in `classOf` in `tests/unit/layers.nix`, and in
  `scannedDirectories` there if its files should be held to the path scan.
- A deliverable with its own flake wiring goes in the `imports` of `flake.nix`, the way
  `cli/flake-module.nix` and `devshells.nix` do. An end-to-end folder is the opposite case: it is
  discovered from `tests/e2e/*/deployment/default.nix`, and `flake-module.nix` naming one fails
  `testAnEndToEndFolderIsAddedWithoutEditingTheFlake`.
- A new directory of python modules goes in `programs.mypy.directories` in `treefmt.nix` and in
  `src` in `ruff.toml`.
- A new `spec.md` anywhere goes in `accountable` or `excused` in `tests/unit/coverage.nix`.
- A new excluded construct goes in `lib/excluded.nix`, gets a test in `tests/unit/exclusions.nix`,
  and moves the row count that suite compares against the fixture README's table.
- `README.md` must keep naming `docs/`, `docs/README.md`, `lib/`, `image/`, `flakelet/`,
  `secrets/`, `operator/`, `cli/`, `fixtures/`, `perf/`, `openspec/`, `tests/unit/`, `tests/e2e/`
  and the five documented commands. `tests/unit/layers.nix` asserts each literal.
- A `#### Scenario:` heading names its test by construction: `test_<snake_case>` under pytest,
  `test<CamelCase>` under nix-unit. A name present in both layers is a failure, not a bonus.
- `openspec/**` is exempt from the path scan: a record describes the repository as it was.

## Fixtures and goldens

- `fixtures/**` is excluded from the formatter. The suites evaluate it as committed and compare
  the golden plan with `==`, so a formatter would be editing a test's subject.
- Regenerate the golden with `nix eval --json .#debug.worked.plan | jq -S .`. Nothing in the
  evaluating layer can write to the working tree.
- `gamma` deliberately has not run its generator. That one absence is what the folder exercises:
  `set-entry-absent`, the incomplete render and the absence marker.
- `vault` carries no `backed-up` tag. A self-tagged server would put its own key into the set it
  authorizes, and the folder has no field to narrow a `reach = "all"` set.
- `borg-repo`'s port 22 is `fixed` rather than a default, because the `url` export is built from
  it. It is also the only `fixed` against `defaults` coverage in the fixture.
- `borgRepository` declares two exports so that provider keyset equality has something to be equal
  about. `quota` is not spare.
- Package defaults in `tests/unit/worked.nix` are literal store-path strings, because a fixture
  references a package and realises nothing. The `packages` argument exists so the image check can
  hand the same deployment real ones.
- A fixture carrying `...` or a hash that is not sixteen hex digits has stopped being evidence.

## Perf harness

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

- The vale wrapper in `treefmt.nix` turns any printed alert into exit 1, because vale itself exits
  0 for warning-level rules. Every `*.md` outside the excludes is linted, this file included.
- mypy runs once per directory of top-level modules, because that is what each import expects to
  be beside. `e2e-folders` is a label rather than a path, and its run happens from `tests/e2e` so
  that `import delivery` resolves the way it does under pytest; its module list is read from the
  directory, so a folder is checked by existing. Both `tests/e2e` roots carry `cli` on
  `extraPythonPaths` because `test_harness.py` and a folder's test import the command's modules,
  and `pythonRoot` turns it into a path relative to the run's directory rather than writing that
  path out: written out it would resolve from neither `treefmt.nix` nor the repository root, which
  `layers.testAFileNamesAPathThatIsNotThere` refuses. A store path is also wrong here - mypy then
  reads the modules as an installed distribution and demands a `py.typed` marker.
- `ruff.toml` carries the rules because this repository owns no python package. `src` names the
  three import roots. The one devshell carries the interpreter `pytest-env.nix` builds, and
  `tests/e2e/runner.py` refuses a run where it and rookery's own disagree. `target-version` is a
  floor below that interpreter, not a record of it: it bounds what `UP` may rewrite to.
- `devshells.nix` is one shell and it names no built artifact. A store reference in its hook
  would make entering the checkout build the 3.7 GiB guest image, so the machine layer's
  variables arrive from `eval "$(planner-e2e-env)"` instead, which resolves
  `packages.planner-e2e-env-paths` by name when it is called. That file and the `planner-e2e`
  app are rendered from one attrset, `e2eArtifactPaths` in `flake-module.nix`: a variable added
  to one is added to both.
- `pytest.ini` keeps `-rs`: an artifact-backed suite skips itself when its `PLANNER_*` variable
  names no built path, and the skip reason is the only thing that tells that apart from a run with
  nothing to say.
- `workdirs/` is gitignored and holds git worktrees of this same tree, so it is invisible to the
  flake and to treefmt but not to pytest: `pytest.ini` names it in `norecursedirs`, or `pytest .`
  collects two files called `test_harness.py` and refuses the second as an import mismatch.
- `resolve_rookery` builds with `--refresh`. A branch reference resolves through nix's tarball
  TTL, so without it a run uses whatever rookery was fetched last, and one from before a nixpkgs
  bump is a different python minor version. That is reported as `PYTHON VERSION MISMATCH`, which
  reads like a real pin disagreement and is not one: check the resolved revision before changing
  `pytest-env.nix`.
- `tests/e2e/runner.py` puts `$PLANNER_E2E` and `$PLANNER_CLI_SRC` on the child's `PYTHONPATH`;
  `tests/e2e/conftest.py` edits `sys.path` for neither. pytest loads no conftest above the
  directory of the ini file it found, so `nix run .#planner-e2e wired-pair` collects a path with no
  conftest below it and a `sys.path` edit there reaches nothing. The whole-layer run happened to
  work, which is why the gap surfaced only when one folder was named.
- `devshells.nix` puts the checkout's `tests/e2e` and `cli` on `PYTHONPATH`, because in the shell an
  edit is what a run should read; the app and the `planner-delivery` check name store paths.
- vulture and harper are deliberately not run. Vulture's only finding is `cmd` in the `Runner`
  protocol of `cli/remote.py`, which is an interface parameter name. Harper flags `realiser`,
  `flakelet` and `keyset`.
- Build the individual check. Never `nix flake check` the whole flake.

## End-to-end layer

- `tests/e2e/guest.nix` restates the invariants of rookery's `nix/base-image-configuration.nix`.
  rookery is resolved at run time rather than pinned as an input, so nothing checks the copy
  mechanically. Diff it when rookery moves.
- The guest image carries no plan artifact and no declared flakelet service, and its only
  credential is the image's own snakeoil key. Every entry arrives by delivery, otherwise the tests
  pass vacuously.
- TCP sshd is the delivery channel, and systemd's ssh generator derives the vsock control channel
  from it.
- A folder holds `deployment/` and one `test_*.py`, and no builder. `deployment/default.nix` takes
  `pkgs`, `planner` and `operator` as arguments and returns one deployment build per name, because
  `testAReaderOpensAnEndToEndDirectory` fails any path token that leaves the folder: the builder
  arrives as an argument rather than as an import. A build named `default` is
  `packages.planner-e2e-<folder>` and any other name is suffixed with its own.
- A folder's test builds its own deployment with `planner build`, in the pytest process, and
  applies it with `planner apply` through `Cluster.run`. The split is the one that already existed:
  a delivery has to run where the cluster's addresses resolve and a build must not, so no
  evaluation and no build happens inside the cluster's user namespace.
- `Cluster.run` replaces the environment rather than extending it, so `delivery.command_env` carries
  the caller's own plus the `NIX_SSHOPTS` a throwaway guest needs. Those options are the guest's and
  never an operator's, which is why the command extends what it is given instead of deciding it.
- `additionalSpace = "2048M"` is room for the two delivered artifacts and their closures.
- Machine addresses are rookery's static MAC-keyed dnsmasq leases, `10.0.0.(10 + i)`. They are not
  free-choice test values.
- A served unit binds `0.0.0.0` because it starts before the DHCP lease exists. The plan is held
  to the exported URL, which does use `target.address`.
- `--retry` in the probe exists for cross-machine boot ordering, not for flakiness.
- `schedule = "daily"` keeps the next elapse in the future for the whole run.
- Every cluster's dnsmasq has no upstream except `newcomer`'s, which is why the offline assertion
  holds where it is made.
- The pytest phases are session-scoped and order-dependent. The trailing `wait_until_succeeds`
  restores the wire for the phases after it.
- `systemctl is-active` exits 3 for an inactive unit, so that assertion uses `ssh` rather than
  `ssh_succeed`.
- The reboot is issued in the guest, not by QMP reset, because the claim is about the service
  manager bringing the machine down.
- In `portable-image`, `elsewhere` is aarch64 and never booted: it exists so an image can be built
  for a machine this host is not. The attaching entry is stated `strict` because enforcement is
  the claim under test.
- `newcomer` proves the outward surface, not a deployment, and it proves it on a machine. The host
  computes one thing: the store path `nix flake metadata --json` resolves the checkout to. A
  `path:` reference copies the ignored trees beside it and a `git+file:` one pins `HEAD`, which
  tests the last commit instead of the tree under test.
- That source path and the image's key are handed to the workstation with one `nix copy` inside the
  cluster's namespace, and every step after it is a command the workstation runs. Moving a build or
  an apply back onto the host removes the claim: that a machine with nothing but the template and
  the source can do it.
- `template/flake.nix` carries the published input url verbatim and is never edited. The
  workstation runs `nix flake lock --override-input nixplan path:<source>`, which writes the
  substitution into the lock without fetching the published ref, and the first test reads the lock
  rather than trusting it.
- `newcomer`'s cluster is the one that is not hermetic (`offline=False` on the stage, `pasta`
  uplink, an upstream for the resolver). Without egress the folder skips itself: a machine that
  cannot reach the substituter can only be observed failing to fetch.
- The workstation does not download nixpkgs. A NixOS system pins its own flake in the registry, so
  the image's closure already holds that source, and nix never fetches a locked input whose hash is
  valid in the store. What it does fetch is the command's interpreter and the build's inputs, about
  340 MB. Do not "fix" the fidelity by pinning the template to another nixpkgs: a consumer follows
  the library's pin, and a second one would evaluate the deployment against packages the library
  never saw.
- The guest image carries `nix-command`, `flakes` and 6 GiB of spare filesystem for that
  workstation. All three are properties of the shared image, so changing one re-keys every folder's
  cut, and the assertion in `tests/e2e/guest.nix` says why they are there.
- `newcomer`'s test names no symbol of the planner. `tests/unit/layers.nix` scans a folder's text
  for `mkPlan`, so the consumer surface is asserted by what the machines do rather than by a name
  check.
- The folder's own `deployment/default.nix` imports `../template/deployment` rather than holding a
  second copy: `tests/unit/layers.nix` requires a folder to hold one, and two would drift.
- A unit of a service artifact runs with the PATH the artifact carries, so `newcomer`'s greeter
  takes `coreutils` as a runtime input. The machine's own PATH is not a fact the plan records.
- The runner's state directory prefix stays short. The virtiofs socket path
  `<state>/rookery/rookery-<pid>-<id>/vm-<i>/virtiofs-<tag>.sock` hits the 108-byte `AF_UNIX`
  limit, and virtiofsd then exits during startup with no useful error.
- Provenance lives in `tests/e2e/generation.py` and in no plan field. Staleness is a fact about
  bytes on disk, which the library cannot observe, so a `varsState.<key>.from` field would be the
  planner restating its caller's claim. The driver writes each stored value's plan key beside the
  state it read and refuses a disagreement naming both identities; a stored value with no record
  is a disagreement, not a match.
- The external generator is pinned by revision `e6af758a5745ac4adef763deb0f1771cec58c461` and by
  the digest of its `secrets-config.schema.json`, both recorded in `tests/e2e/generation.py`,
  which is where the guard lives too. It fails naming `secrets/read.nix` when the resolved tool's
  schema differs, and does not fail when the tool cannot be resolved at all: an unreadable signal
  is not evidence the contract moved, and the run skips instead.
- `tests/e2e/generated-secret/deployment/backend.py` is that folder's own `age` store backend and
  not the PR's example one. The reason is mechanical: the configuration carries a build-time
  `.drv` path for every backend program, and the example backend lives in the NixOS module tree of
  a branch resolved at run time, so no derivation path of it exists when the configuration is
  written. The folder proves the composition, not the backend.
- That folder builds its plan twice, because a plan is a function of `varsState`. Its
  `deployment/args.nix` is the deployment on its own and takes `varsState`; `deployment/default.nix`
  calls it against a declared state, so the unit files and the generator configuration are a
  function of the declaration alone. The run evaluates the `plan.nix` of the `generation` build
  against the state the backend answered, and that second plan is what every assertion reads.
- Its third build is `age` itself. The run mints its identity with the same binary the store
  backend runs, and a build of the folder is the only place that binary is named.

## Machine layer snapshots

- Each `tests/e2e/<folder>/` obtains its machines from one `@cluster_snapshot_fixture` stage,
  declared through `delivery.cluster_stage`. `@snapshot_fixture` is wrong here: a single-VM cut
  can only resume as slot 0, so two of them are both `10.0.0.10` with no route between them.
- A cut is RAM plus device state, so a snapshotted guest mounts **no virtiofs share**. Adding one
  back fails an assertion in `tests/e2e/guest.nix` rather than silently costing every cache hit.
- The credential is therefore the image's, not the run's: nixpkgs' `snakeOilEd25519*` from
  `nixos/tests/ssh-keys.nix`. One place defines both halves (the guest authorizes the public one
  and exports the private one as `e2eGuest.sshPrivateKey`), so the image and the run cannot drift.
  A store file is 0444 and ssh refuses a private key that readable, so `delivery.ssh_key` copies
  it to 0600 under the run's state root.
- A preparation body waits and yields. It reads no environment variable and runs no program, which
  is why the stage declares no `extra_env`, `extra_files` or `extra_tools`: rookery scrubs the
  environment and confines the body with Landlock, and an undeclared read or exec is an error.
  Nothing about the artifacts is in the cut's key, so editing a deployment leaves the boot cached.
- Never move a delivery, an activation or an attachment into a preparation. The body does not run
  on a cache hit, so the evidence those tests read would be a replay instead of an observation.
  `test_a_cut_carries_no_delivery` asserts the other half: a freshly obtained machine holds none.
- Wait to `multi-user.target`, not just `wait_for_ssh`. The vsock sshd answers before the login
  `PATH` exists, and a cut taken there resumes a half-booted guest.
- `uefi = true` on the stage: the guest boots systemd-boot from a GPT ESP while the decorator's
  own default is BIOS. Secure Boot and the TPM stay off. All three are part of the key.
- `tests/e2e/conftest.py`'s `state_root` is resolved by rookery **by name**; renaming it silently
  moves every run's state to rookery's own default root.
- The cut's key folds in the python environment rookery runs under, so a rookery interpreter bump
  re-keys every cut: the next run is cold. That is the intended failure mode, never a stale pass.
- Two folders never share one cut. The shape is part of the key (`vms=2;0:alpha:root;1:beta:root`
  against `vms=1;0:alpha:root`), a resume seeds one overlay and one RAM file per slot, and each
  slot's address is frozen in its own saved RAM. Sharing would also need one preparation function
  for both folders, and a session-scoped fixture instantiates once, so the folders would share a
  live cluster, which the attach tests and `test_a_cut_carries_no_delivery` deny.
- The cache never evicts. A moved key input orphans the old entry at about 2 GiB per machine, so
  editing a preparation body repeatedly fills a disk quietly. `rookery snapshot gc --all` is the
  only reclaim, and `rookery snapshot list` is how the accretion is noticed.

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
  record and the command reads the field as optional. Both sides move together, and a record that
  states `path` as `null` rather than omitting it refuses the whole deployment for every subcommand,
  because the command's field reader demands a non-empty string. Observed as that refusal before
  `openspec/changes/hold-every-stated-guarantee` was applied to the tree.
- The walk in `cli/order.py` rescans the entries still to apply once per entry applied, so ordering
  costs the square of the fleet, and the cycle path rebuilds a reachability question per candidate.
  Its eligibility `next(...)` has no default, so a violated invariant ends a run in `StopIteration`
  rather than in a refusal, and `cli/planner.py` handles `ApplyError` only. Today's single edge
  sources cannot violate it. `openspec/changes/order-a-cycle-by-its-strong-components`.
- A fold's refusal is an in-band sentinel: `lib/resolve.nix` reads a returned attrset carrying a
  `refused` attribute as a refusal, so a fold whose own successful result carries that name cannot
  succeed. A tagged pair costs one line per fold.
- `planner apply --only` drops the edge of a provider the selection excludes and prints nothing,
  while a contradicted cycle edge prints a line. Both are reads the run does not honour.
  `openspec/changes/order-a-cycle-by-its-strong-components`.
- Every refusal in `secrets/read.nix` and `secrets/backend.nix` sits above no row and outside the
  accounting in `tests/unit/diagnostics.nix`, whose `realiserFiles` names two files. A generator
  declaring no `program`, a file name outside the external grammar and a recipient machine with no
  address each abort a generation build under an empty table.
  `openspec/changes/report-a-secrets-refusal-as-a-row`.
- The deployment record publishes a per-entry identity so a report can compare a machine against a
  build, and `cli/manifest.py` reads no such field, so `status` cannot tell a current machine from
  one holding an earlier build. `openspec/changes/answer-whether-a-machine-is-current`.
- The purity scan in `tests/unit/diagnostics.nix` is substring matching over comment-stripped text,
  so `.check ` matches inside a string literal and `assert ` misses a call spelled with no space.
  `ast-grep` is installed and parses.
