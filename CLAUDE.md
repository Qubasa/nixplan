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

- `lib/` never raises. Every check returns a diagnostics row, and evaluation stays total: one
  malformed declaration becomes a row and the rest is still read.
- `throw`, `abort`, `assert`, `.check ` and `korora.check` MUST NOT appear in `lib/*.nix`.
  `tests/unit/diagnostics.nix` scans the source text for them. It drops lines whose first
  non-space character is `#`, so prose may name a raising call, but a trailing comment on a line
  of code counts as code and fails the scan.
- korora's `verify` is the only entry point the library uses. `check` raises.
- `builtins.tryEval` catches a `throw` and a failed `assert`. It catches neither an abort, nor a
  missing attribute, nor a function called without an argument its pattern requires, and all three
  are documented as propagating. A missing attribute inside `lib/` is a bug that fails the suite
  loudly.
- A guard is not a check. Because a type error and a missing attribute are uncatchable, every value
  a declaration wrote is read for its kind before the reading indexes into it: `declaredRecord` in
  `lib/module.nix` answers `{ value, rows }` with `{ }` as the fallback and one
  `declaration-malformed` row naming the site, and the declaration itself, a port claim, a slot, a
  capability, a generator, a generated file's record and a pin all pass through it. A reading that
  indexed first and recovered afterwards would look total and would not be. The module's own
  expression is the other half: `compose.service` applies it under the same `diag.guard` the
  implementation gets, so a declaration that raises is `module-raised` plus the `impl-missing` its
  empty fallback earns, and never a third identifier. A unit and a configuration file are the
  implementation's half and keep `implementation-malformed`, which is the row the container and
  each entry inside it already earn.
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
- `tests/unit/diagnostics.nix` walks two file lists and they are not one list. `totalFiles` is
  `lib/**` plus `operator/read.nix`, and it is what the purity scan reads: those are the files that
  never raise. `producingFiles` adds `secrets/read.nix`, because a realiser's reading writes row
  identifiers the table owes a reader while still raising. Merging the two makes the purity scan
  report a realiser's own `throw` as a defect, which is how the lists first came apart.
- A host resource two entries of one machine both claim is a row, and the three claims are read off
  what the plan already records: a `configData` host path, a `claims.ports.<name>` record, and a
  unit directory an extension application records under `runtimeDirectory`, `stateDirectory` or
  `cacheDirectory` - the last read by name the way `supplementaryGroups` is, which names no
  realiser. `entry-host-path-claimed-twice` and `entry-port-claimed-twice` are errors, because two
  writers of one file and two listeners on one port are contradictions where neither declaration
  can be honoured. `entry-unit-directory-shared` is a warning, because the destructive case is
  `runtimeDirectory`, which the service manager deletes when its unit restarts, while a shared
  `stateDirectory` is a handoff two entries of one instance may intend: the row names it and the
  build still happens. A claim carries the field it was recorded under, so a state directory and a
  runtime directory of one name are two claims. The index is built in `entries`, which is the only
  site holding every placed entry, from claims each `placedEntry` returns off its pre-pruned
  records, and it is two `groupBy` passes over one flat list - machine, then resource - rather than
  a comparison of each entry against the others.
- A port claim has three typed fields and the reading normalises it before anything compares it:
  `fixed` is a `port` atom, `proto` is a `protocol` over `domains.protocol`, and `address` is a
  `bindAddress`. An unstated protocol is every protocol of the domain and an unstated address is
  every address of the machine, because the question the index answers is whether two listeners
  could contend and "the author did not say" answers yes. The wildcard therefore has no spelling:
  `0.0.0.0` and `::` are refused, two spellings of one reading being what `toJSON` gave the number
  before it was typed. A refused protocol or address widens the claim, since the number is still
  good and dropping the claim would make a refusal check less than no refusal; a refused number
  drops the claim, there being nothing left to record. Neither field reaches `alloc`, which stays
  `mapAttrs (_: claim: claim.fixed)`, so neither is in `keyInput.alloc` and a claim that adopts an
  address keys as it did. An address a deployment varies still re-keys, through
  `keyInput.settings`. Overlap is not equality, so the ports group is bucketed by spelling and its
  buckets compared pairwise inside one `(machine, number)` group rather than by one grouping key,
  and one claim may earn more than one row.
- A machine may state the host resources its own image already holds, `reserves.ports.<name>` as
  `{ proto, address, number }`, which is an entry's claim's three typed fields with `fixed` spelled
  `number`, and `reserves.paths` as host paths, and that
  statement is a claimant of the same index keyed `machine:<name>`. Both nested records are
  key-checked, so a misspelling is `declaration-unknown-key` rather than a reservation that
  silently checks nothing. It takes part in the one
  ordering the row already follows, so the machine is the subject exactly when its key sorts first
  and a named claimant either way, and it earns `entry-host-path-claimed-twice` and
  `entry-port-claimed-twice` rather than identifiers of its own: a reader would otherwise have to
  ask which of two families a three-way collision belongs to. Only a machine of `usedMachines`
  contributes claims, so a row's subject is always a record the plan carries.
  `entry-unit-directory-shared` has no reservation half, a unit directory claim being
  `<field>/<name>` in the service manager's namespace rather than a host path the registry can
  state. An absent statement checks nothing, and the planner never reads the machine: a discovered
  reservation is `lib/excluded.nix`'s `lifecycle` construct.
- `implArgs` hands an implementation `member` beside `instance` and `machine`, so a module can name
  a resource after its own entry rather than after itself: the pair is what every plan key of that
  member is built from, and a member name that would make the pair ambiguous is refused before any
  key exists. A composed `entryKey` was rejected there, since a key carries the two separators a
  name may not, and nothing about the key input moves.
- `unit-value-newline` is about every string a unit record carries at any depth - a plain field, an
  element of a list, a name or a value of an attribute set, and every field of every extension
  application - and the scan walks the record rather than a list of fields, so a field added to the
  vocabulary or
  declared by an extension author is covered by existing. A name is in scope because
  `image/read.nix` renders a unit's `env` key into the file as `Environment="<k>=<v>"` and escapes
  the key with nothing, so a line break in a name is the same free directive line a value would be.
  One identifier covers every field because
  two would ask a reader to learn which field belongs to which and would report one mistake twice
  for a value written into two of them; the row names the field path instead. Every field whose
  atom is a grammar refuses a line break as `unit-field-type-mismatch` and is never in the record,
  so one fact still earns one row. `image/read.nix` scans the same record and refuses, because a
  caller reaching it directly gets no table.
- The row records the offending value and keeps reading, and the entry is still planned: the row,
  `applicable = false` and the realiser's own refusal are the three things that stop the bytes.
  Pruning the value would make one identifier behave two ways, so a future change that prunes has
  to prune a name and a value alike.
- Two scans of one record hold that rule and they must agree. `util.anyLineBreak` answers the
  yes-or-no question with no allocation and gates the `util.stringsDeep` walk that builds the field
  paths, because the walk allocates a record and an interpolated path per string at every depth for
  a row almost no unit earns: gating it removes about 8.7 thunks per entry on `fleet` and 13.3 on
  `mesh`, which is most of the cost of the change that introduced it. A gate that skipped a shape
  the walk reports switches the check off silently, which is why both read attribute names.
- A configuration file's host path is held to the grammar one word of a rendered shell step can
  carry, and that grammar's one home is `lib/util.nix` beside `keySeparators`: `secrets/read.nix`
  reads it rather than stating it, because a widened grammar admitting a character in one rendered
  script and refusing it in another is the defect the single home exists to prevent. The check is
  the library's, so every realiser and every plan reader inherits it. A refused path is left out of
  the record the way a name carrying a key separator is left out of every key: the path enters
  `keyInput` through `configData`, and a reader may be handed a plan whose table it never read.

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
- A machine a placement selects must declare an `address`, a `system` and a `serviceManager`, and a
  placement onto one that does not is dropped rather than planned. The rule is the same shape as
  the separator one and for the same reason: a module may render any of the three, a field the
  target does not carry is a missing attribute, and `builtins.tryEval` catches neither that nor a
  function called without a required argument, so a row cannot make the declaration safe and the
  declaration has to leave every later stratum. The selection is therefore read twice - what the
  selector matched, which `machine-target-incomplete`, `placementsOn`, `usedMachines` and
  `member-not-placed` are computed over, and what survived the drop, which is what `lib/plan.nix`
  plans - because a check computed over the survivors would remove its own subject and its own
  row. Completeness is read off the value the registry reading produced rather than off the
  presence of the key, so `address = 22` is as incomplete as no address and earns both rows. A
  machine no placement selects declares whatever it likes.
- The rows of the unplaced reading of a member are produced only where the selector matched
  nothing. A member whose every placement was dropped is still recorded as unplaced, but its
  implementation is not read in a context the deployment never wrote: the unplaced reading hands
  `impl` no `target` at all, so reading it there would turn the registry's mistake back into the
  uncatchable failure this rule exists to remove.
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
- The reservation a machine states is deliberately outside `machineRecords` and `targetOf`, and
  lives in a third projection of the same reading. `machineKey` hashes the record it is handed,
  every placed entry depends on that key through its own `dependsOn`, and so does
  every per-placement generated value, so recording it would ask for a
  redelivery of every entry on the machine and a regeneration of bytes that are still correct each
  time an operator corrected a line of it. The plan records it nowhere for the same reason, and
  nothing reads it: no realiser, no subcommand.
- An image's version digest is deliberately not the entry key. It is taken over what the artifact
  holds: a shown path enters it by its bytes where the artifact carries them and by its path where
  the host writes them, so a reading handed an assembly and one handed none answer the same digest,
  and a `ref`-bearing recipe's content moves the entry key without moving the image.
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
- A binding is a capability value off a sibling's handle and never a name, so no root can name an
  instance. What decides whether a reference is a binding or an address is one thing, whether its
  target is a kept member of the same instance, so no line of a module differs between the two.
  The record the resolver reads back carries the member it came from, which is read back to that
  member's attribute key the way a capability's own `member` is.
- The cut is read before placement, settings, generators and wires, so "a cut member produces
  nothing" is one filter over the member set rather than a check at every later stage. A member the
  deployment does not mention is kept, which is why `members` is a block of exceptions and not a
  member list: an instance naming no `members` keeps a composition it never had to enumerate.
- A member name and a slot name are one namespace, because `wire.<key>` addresses either. The
  collision is refused one stratum above the wire reading (`member-and-slot-name-collide`), so the
  reading below it can decide which of the two a key is from the member set alone.
- `consumers` is counted over wires, deployment-wide, and a binding is a wire the module wrote. A
  consumer placed on twelve machines is one consumer, and the row is per capability rather than per
  consumer, so two slots taking one `consumers = "one"` capability produce one sentence naming
  both. The declared cardinality is read by the member's own capability name and never by the name
  a wire addressed: a root's `provides` decides what a wire may address and not how many wires may
  take the capability, so one capability exposed under two names is one capability and the wires to
  both names are counted together.
- Two instances wiring each other is not a cycle: a capability's exports are a function of module
  and settings, never of a wire. Do not add cycle detection.
- A refused read leaves the slot absent from `results` - not `null`, not `{}`. `or [ ]` cannot be
  written, so it cannot silently succeed.
- A wire's far end is read for an interface before either comparison, because `provides` reaches the
  wire as the author's own record rather than as the validated reading, so the key the provider's own
  `capability-interface-missing` names may be absent there. The consumer's row is
  `wire-capability-untyped` and the provider's stands beside it: two entries have a problem, and the
  slot is left absent. A binding is a capability handle only if it carries one, so a hand-written
  record naming a member and a capability is `binding-malformed` and the slot is the deployment's to
  fill.
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
- A file record's `owner`, `group` and `mode` are one value's and never one machine's: the same
  three reach every machine of the delivery set, the way `present` does. They default to `root`,
  `root`, `0400`, and only the ones the declaration actually stated enter the value's key, so a
  plan written before the fields existed keys as it did. `lib/module.nix` records which were
  stated for exactly that reason; do not delete `stated` as unused.
- A configuration file's record carries the same three fields, and the same rule about the key:
  `owner` and `group` default to `root` and only what a declaration stated enters `keyInput`, so a
  plan written before the two fields existed keys as it did. `mode` is the one difference, being
  required rather than defaulted, so it is always in the key. `configDataRecord` records the
  ownership on both of its branches, the incomplete one included: a reader must not be able to
  mistake an unfinished render for a record that does not say who reads the file.
- Two layers write a value and neither states a mode of its own: `cli/remote.py` and the step
  `secrets/backend.nix` renders both read the record. Both create the file `0600` before its first
  byte, set the ownership and then the mode, and move it into place, so the bytes are never at the
  writing login's umask and never wider than the record; both set ownership and mode again on
  every apply, so a machine-side edit does not survive one. The value's directories are `0711`:
  a file the record opens to an account is unreachable behind a directory only root may traverse.
- The denial of a delivered file is about permission and not about secrecy. `denialsOf` in
  `image/read.nix` compares the record against the account the profile imposes and the groups the
  unit declares, so a group-readable secret is realisable under a confining profile and a
  root-only public file is not. `operator/read.nix` mirrors it as
  `operator-entry-access-denied`, and `lib/plan.nix` makes the same comparison one stratum
  earlier as `slot-reads-value-unreadable-by-user` for a consumer's declared reads. A unit's
  declared groups are whatever an extension application records under `supplementaryGroups`,
  under any backend, which is how `lib/` asks the question without naming a realiser.
- The readability comparison is one predicate, `util.admits`, asked at the three sites that hold the
  facts, and each site names its own row. `lib/plan.nix` asks it of a consumer's declared reads
  (`slot-reads-value-unreadable-by-user`) and of a configuration file the entry's own units are
  shown (`entry-config-file-unreadable-by-user`); `image/read.nix` asks it of the account a
  profile imposes (`imageReader.denials`, over a delivered file and a configuration file alike);
  `operator/read.nix` mirrors the third as `operator-entry-access-denied` by mapping the
  builder's own denial list rather than comparing again. A fourth site is a place to forget it.
- Its one home is `lib/util.nix`, beside `keySeparators` and the renderable-word grammar, and the
  one thing its callers differ on is an argument rather than a second copy. `rootAdmitted` is true
  for the planner, which reads a unit running unconfined as the account it declares, so a unit
  declaring no account and a unit declaring `root` both open anything and answer alike. It is false
  for the image reader, because a confining profile imposes the account and never imposes root, so
  an undeclared account there matches no file's owner and only the world bit admits it. Two copies
  is what the tree had, and they disagreed:
  the planner's refused a unit spelling its account `root`, which `entry-config-file-unreadable-by-user`
  made deployment-fatal. The group clause asks about the unit's declared groups and not about its
  account, under either answer, so a unit naming a group and no account is admitted by that group.
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
  argument, and a unit list is escaped word by word rather than joined. The grammar above and the
  escape fail independently: a grammar is a rule a future field can be added without, and the
  escape is what holds for a value no rule has reached yet. `lib.escapeShellArg` leaves a
  safe-looking word bare, which is why `image/default.nix` has a `quoted` of its own for the
  messages.
- Independence stops at a value the receiving shell re-parses, and the `deploy.remote` step
  `secrets/backend.nix` renders is where that line falls. Its local half escapes every word, so the
  address, which reaches `ssh` as an operand and is never re-parsed, is carried by the escape alone.
  Its remote half is one `ssh` command whose text names `'$4'` through `'$7'` inside single quotes,
  so the parent directory, the path, the mode and the ownership are re-parsed on the machine and
  are held by `util.wordRule` and nothing else: fourteen sites across those four positions. Those
  four are grammar-dependent by construction, and widening `wordRule` to admit a quote breaks them
  however well the local side escapes. A second escape cannot fix it, because the escape would have
  to survive a round trip the step has no way to perform.
- Each realiser states its own name rule and its own unit rule as the sentence its refusal prints,
  and `operator/read.nix` asks the stated realiser for the two rather than testing which realiser
  it is, so a third publishing them is asked by existing. The image realiser's rule is the
  intersection of three constraints it is already inside - nix's store name set, which every
  derivation it builds spends, systemd's unit name grammar, and one shell word - and it is not the
  library's, because which realiser realises an entry is a statement beside the deployment and the
  union of two realisers' grammars refuses a name the stated one accepts.
- Every profile except `trusted` carries `DynamicUser=yes` and `PrivateUsers=yes`.
- A field missing from `systemdDirectives` in `image/read.nix` fails the build on purpose. An
  extension exists to add a field, so dropping one would make the extension a comment. The same
  rule holds for `unitDirectives`, which maps every vocabulary field: a vocabulary that grew and a
  realiser that did not is the realiser's defect, so the build refuses rather than dropping the
  field, and the row a deployment gets for an extension field the table has no rendering for is
  `operator-entry-extension-field-unrendered`, read off the stated realiser's own table.
- A unit's restart domain is four values - `no`, `on-failure`, `on-abnormal`, `always` - stated
  once as `restartPolicies` in `lib/atoms.nix`, which both the atom's predicate and the
  `unit-field-type-mismatch` row read. The other three systemd carries need a `Type=` or a
  `WatchdogSec=` this vocabulary does not have. A policy contradicting the unit's own shape is a
  row and the field is not recorded, so no renderer is handed two statements about when the unit
  runs.
- flakelet decides `[Install]`, no plan field does. A long-running unit is wanted by
  `multi-user.target`; a scheduled unit's timer is wanted by `timers.target` and its service is
  wanted by nothing. An `[Install]` on that service runs the job once at deploy time and again on
  its schedule.
- The flakelet realiser refuses a shown host path by two questions, **when its bytes exist** and
  **what record it states**, and by neither the kind of file nor its secrecy. It runs no step on
  the machine, so a recipe carrying a `ref` is a file it cannot carry at all, and a configuration
  file whose declaration states anything but a store object's own record is a file only a realiser
  that installs can show. A delivered generated file is asked neither question: its bytes arrive
  before activation and its record is installed by whoever delivers them. A `source` file and a
  recipe of nothing but literals are store objects, carried in the artifact beside `meta.json`
  and `units/`, and shown from there when the record agrees.
- The unit vocabulary carries the three directory kinds a service manager creates for a unit, a
  mode per kind, and two condition polarities over one path. The domain is the planner's because
  each is a fact about the entry rather than about a renderer: a mode is per kind because that is
  the grain a service manager applies one at, a name is relative to the root its kind implies so
  the kind decides where the directory lives, and a condition is one directive with the polarity
  in the value, which is systemd's own spelling. A directory is a claim against the machine
  whether it was declared through the vocabulary or through a backend extension application, so
  `directoriesOf` reads both and `entry-unit-directory-shared` fires either way; one kind declared
  at both sites on one unit is `unit-directory-declared-twice` and neither statement is recorded.
- Both realisers are handed the same `assemble` argument by the reading, so a configuration file
  whose bytes the plan holds is one store object written once. Under `image` those bytes are then
  in the image, so editing them moves the entry's version digest - which is what makes a second
  apply replace it - and what the attach step installs is a `ref`-bearing recipe or a file whose
  stated record a store object cannot carry.
- `flakelet/read.nix` restates two rules from flakelet's own `manager.rs`: `validate_name` and
  `validate_units`. `LOCKED_URL_PREFIX` in `tests/e2e/delivery.py` must match the prefix written
  there.
- The secrets reading has two halves, the way `operator/read.nix` and `operator/default.nix` do,
  and one description per condition: `rows` and `generation` answer a table and raise nothing,
  `store`, `configuration` and `deliveriesOf` refuse with the sentence that row states, and
  `operator.mkGeneration` writes `diagnostics.json` and `diagnostics.txt` into the generation farm
  and refuses through `planner.render` of the whole table. Three of its conditions are reachable
  from a plan the planner calls applicable: a value recording no `program`, a file name outside the
  contract's grammar, and an address the rendered step cannot carry as one shell word. A recipient
  machine with no address is no longer one of them, the planner refusing that registry before a
  plan exists, and it stays an error here because the rendered step is the one build artifact that
  carries an address.
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
- The temporary that step fetches into is one for the whole run, and it is removed by a `trap`
  installed before the first fetch. A trailing `rm` is not the fix: `set -eu` exits the step where
  a send is refused, which is the case that matters, and no trailing command runs on a signal
  either. Each fetch truncates the one file rather than making another, so `mktemp`'s `0600` is
  what every fetch writes into and the plaintext of at most one file exists at a time.
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
  with its machine and no `path` at all, it contributes no artifact, and only a statement naming
  it is a row. The absence is an omitted key rather than a `null` or an empty string, because a
  record stating either is one every subcommand refuses.
- A build of an inapplicable deployment still produces its tree. `plan.json`, `diagnostics.json`
  and `diagnostics.txt` are always there, no artifact of any entry is, the tree carries no marker
  of its own, and `passthru.entries.<key>` of such a deployment is the raise that carries
  `planner.render` of the table.
- The deployment build produces no row about a missing address. `machine-target-incomplete` holds
  that fact one stratum up, so a row here would restate a decision about a plan the planner cannot
  emit; the deployment record still carries `address` as an explicit absence, because a record is
  an interface a hand-written plan arrives through, and refusing to dial stays with the command,
  under "The command refuses before it dials".
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
  so the walk contradicts an edge rather than refusing. The order is the strong components of the
  read graph, computed once and walked in the dependency order between them with ties broken by
  each component's lowest plan key: a component of one entry is an entry with an order, a component
  of more is a cycle whose entries are applied in plan key order, and the edges contradicted are
  exactly that component's own edges pointing backwards in it. An entry that merely reads into a
  cycle therefore keeps its order, ordering costs the graph rather than its square, and eligibility
  is answered by construction rather than by a reachability search per candidate. Refusing a cycle
  would refuse a deployment the library accepts; silence would make a one-off startup failure
  unexplainable.
- The walk of the condensation cannot run out of components, a condensation being acyclic, and it
  refuses in that position anyway: an unorderable state is an `ApplyError` naming the entries and
  the reads between them, because the `next(...)` that stood there ended a run in `StopIteration`,
  which `cli/planner.py` does not handle. A future edge source is what makes the position reachable.
- Three lines report what the order could not honour, all before the first dial: `cycle of <keys>`
  names the component the order was broken at, one `ordered against the read of` line per
  contradicted edge names the read a consumer may fail on once at startup, and `not applying
  <provider>, which <consumer> reads` names a read whose provider a `--only` selection excludes.
  The last one is an announcement and no edge: an entry the run does not apply cannot be applied
  first, so the selection is applied as given.
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
- A report also says whether a machine holds what the build published, and the two realisers answer
  that with two different facts. An image names its identity: the record's `key` is the artifact's
  version digest, an image's file name carries it and `portablectl list` prints it, so that half is
  identity equality and the line says `current` or `holds <x>, built <y>`. A flakelet endpoint
  stores the digest in the generation it keeps and reports it nowhere: `flakelet status --json`
  prints `ServiceStatus`, whose only artifact-shaped field is the unit files of the active
  generation, and that half therefore compares those paths against the artifact's own and says
  `runs this build's units`, never `current`. The record's `key` is read by the command and a record
  publishing none for a placed entry is refused; do not delete it as unused.
  `delivery.endpoint_refusal` records what the locked endpoint answers and fails the moment that
  field set moves, and skips where the source cannot be resolved, because an unreadable signal is
  not evidence the answer moved.
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
- The bytes of a write travel on the step's input stream and enter no argv on either host: the
  script is a function of the record, `Subprocess` hands the payload to `subprocess.run(input=…)`,
  and the machine's own command line is the element of the local vector carrying that script. The
  channel is therefore bytes in and text out, decoded once with `errors="replace"`, because a
  secret is arbitrary bytes and a machine's answer may be too. The harness's recorder records the
  argv and drops the payload on purpose: a recorded copy of the bytes would move the leak into a
  test file, and the property asserted is that two payloads of one length produce equal vectors
  rather than that one known needle is absent.
- A value lives under `/run` (`lib/resolve.nix`), so a reboot loses every one of them while the
  endpoint brings the entries back. That is what the report's `value <key> missing on <machine>`
  lines are for: one question per machine, about presence only, one line per value however many of
  its files are gone, and a zero exit because a machine that answered is not a machine that failed.
  Never ask a machine what a value it holds contains.
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

## No host path in a deployment

- A deployment declares intent and never plumbing. A host path a unit needs is derived by the
  module that needs it, out of the `instance` and `member` of its own entry, or reaches that
  module through an export and a wire. `README.md` states the rule beside the design goal it
  serves, and `layers.testTheRootDocumentStatesHowAPathReachesAUnit` reads four of its phrases
  back off the document with its line breaks flattened, so deleting the sentence fails a check
  naming the document and rewrapping the paragraph does not.
- Two checks hold it, both in `tests/unit/layers.nix` and both reported by
  `testADeploymentStatesAHostPath`, so a folder that fails is told which of them it failed. The
  scan reads every `.nix` file under `tests/e2e/*/deployment/` and
  `tests/e2e/*/template/deployment/`, splits each line on the quote and refuses a fragment
  beginning with `/` whose first segment is one of `etc var run srv opt tmp usr home root nix`
  and which carries no `${`. Splitting on the quote is what catches a quoted attribute name,
  which is how `configData."/etc/..."` is written. The intersection refuses a path a folder's
  `test_*.py` and its own deployment both carry: a test asserting a path reads it off the plan
  it built, so the assertion is about where the deployment put it rather than about two files
  agreeing.
- A derived default is impossible, which is why the `recordPath`, `markerPath` and
  `greetingPath` knobs were deleted rather than defaulted. A default is written in the composing
  root, which is handed no instance (`lib/compose.nix:30-31`), so the path is built inside `impl`
  where `instance` and `member` are.
- Two exemptions. A path only a test knows is the test's own claim and stays:
  `portable-image`'s `/run/planner-assembly` fake root and `newcomer`'s `/opt/vendor/greeter`.
  And `fixtures/` and the unit suites' own deployments are outside the rule, because they
  exercise the library's reading, are placed once by construction and have their paths compared
  against goldens, so deriving one there would move a golden without claiming anything about a
  machine.
- The suite is nix-unit inside a pure evaluation, so the scan is a text scan and never
  `ast-grep`. It reads string fragments rather than whole lines, or a comment naming `/etc`
  fails it.

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
- `secret-delivery`'s later phases are the value half of a second apply and run in file order: the
  report of a machine holding everything, one file removed and put back, a rotation, the same
  rotation with the reader stopped by hand, and a reboot of that machine. Each is the previous one's
  machine, so nothing is restored between them and the rotation's new token is what the phases below
  it read. The reboot is last because `/run` is what it empties: after it the restart step finds a
  failed unit and leaves it alone, which is why that test starts the unit itself rather than waiting
  for one.
- `systemctl is-active` exits 3 for an inactive unit, so that assertion uses `ssh` rather than
  `ssh_succeed`.
- The reboot is issued in the guest, not by QMP reset, because the claim is about the service
  manager bringing the machine down.
- In `portable-image`, `elsewhere` is aarch64 and never booted: it exists so an image can be built
  for a machine this host is not. The attaching entry is stated `strict` because enforcement is
  the claim under test.
- `portablectl` is asserted in `tests/e2e/portable-image/` and nowhere else. `test_harness.py`
  hands the command a recorder, so a test there could state what the tool prints - and a verdict
  measured against an invented answer is the one thing this layer exists to avoid. The folder
  therefore owns every image comparison and builds the same deployment twice: `changed` carries
  another identity through another unit script, nothing attaches it, and a report read against it
  is what names two identities. One phase stops the units and leaves the image attached, because
  the tool prints `attached` there rather than `running` and only `detached` reads as absence;
  nothing restores them, since the detach below does not care and the file order is the order.
- The fallback in `cli/report.py` for a listing the command cannot read has no test. No real
  `portablectl` prints one, and the command can only be driven from inside a cluster, so there is
  nowhere to inject an answer without inventing it. A rewrite of `remote.attachment_of` is
  therefore unguarded against that branch.
- `tests/e2e/runner.py` puts the roots the app names **before** any inherited `PYTHONPATH`.
  `devshells.nix` puts this checkout on that variable on purpose, and appending the run's own roots
  let a checkout shadow the store copies the app had just built: a run then reported on modules it
  did not build, which reads as a failure of the code under test. `import_path` is the one place
  that order is decided, and `test_a_run_reads_the_built_layer_rather_than_a_shell_s_checkout`
  holds it.
- `portable-image`'s assembly tests run the artifact's own attach script on the machine, under a
  `PORTABLE_PLANNER_ROOT` of the run's own and with `portablectl` and `systemctl` answered by a
  `PATH` that refuses: the script then stops where the assembly ends, which leaves the machine's
  real attachment untouched and is the only window in which a half-written file exists. Running the
  script on this host instead would observe a recipe nothing on a machine ever ran.
- One case is one ssh command, and everything it observes is echoed as `key=value` lines. The
  guest's sshd is per-connection socket activated, so a burst of short logins is answered by the
  socket's own trigger limit: the machine stops accepting connections part way through a test and
  the failure reads as a dead VM. A value spanning lines is a parse the reader cannot make, which
  is why a file's bytes are compared on the machine and reported as one word.
- `shared-postgres`'s server reads two `configData` files of literals, which the flakelet realiser
  assembles at build time and carries in the artifact: the configuration file, and the
  authentication file it names through `hba_file`. Both state the record a store object carries,
  the second one explicitly, because a realiser that binds store objects refuses any other. The
  data directory is a declared `stateDirectory` with its own mode, not `configData`: a realiser
  writes bytes and not a directory a server initialises, and the service manager is what makes one.
- Its setup is three units, not one script with three guards. `bootstrap` carries
  `startIfPathAbsent` of the file `initdb` writes, so whether the cluster is initialised is the
  service manager's answer; `init` is ordered after it and converges every role and database on
  every apply; `server` follows both. `init` reaches whichever server already holds the cluster and
  starts a private one on a socket of its own when none does, and both read the declared
  configuration file, so one file decides how a password is hashed and `initdb` states no
  `--auth-*` flag of its own.
- Its DDL converges rather than creates. A database is created where none exists and its owner is
  then stated, the role that held it is granted to the new owner so the objects inside it are
  reachable, and a role the deployment no longer names is left every object it owns and loses only
  its login. Every interpolation is escaped at its site, as an identifier or as a literal, by the
  shell's own substitution: no external program and no argument list ever sees a password, and
  `near-app`'s label carries a quote so that the escaping is asserted rather than assumed.
- No unit of it is root. The password is delivered `postgres:postgres 0440`, the cluster's units
  run as `postgres` so the service that uses the credential is the service that reads it, and each
  consumer runs as `nobody` declaring `supplementaryGroups = [ "postgres" ]` and writing its record
  under a `runtimeDirectory` the service manager creates for that account. The init script therefore
  drops privilege nowhere and calls no `runuser`: it already has the account it needs.
- Its port is a default rather than `fixed`, because `lib/module.nix` allocates nothing and two
  listeners on one machine need two stated numbers: the leaf defaults to 5432 and `own-app` states
  5433 for its own database member. An export built from a knob requires the knob be resolved,
  which a default is, not that it be fixed.
- Every host path of the folder is derived by a module from `${instance}-${member}`, the pair an
  entry's plan key is built from minus the machine, and no declaration of the deployment states
  one: the data and socket directory is the state directory `postgresql/<name>` under the root that
  kind implies, the configuration and authentication files are `/etc/<name>/postgresql.conf` and
  `/etc/<name>/pg_hba.conf`, and a consumer's record is `record` inside a runtime directory called
  `<name>`. The separator is `-` because a key's own separators are refused in the names that enter
  it. `test_shared_postgres.py` reads each of them off the plan, so a broken derivation is a red
  test rather than a stale constant that still matches.
- `alpha` runs four entries and `beta` one: the shared cluster, the consumer that shares its
  machine, the private cluster and the application that owns it are all on `alpha`, placed there by
  its `private` tag, and `beta` keeps the remote consumer so a working consumer outside one delivery
  set is still there. `own-app:vars/password-private` is therefore delivered to `alpha` alone.
- Its three app instances are three shapes of one module, which composes a consumer and a database
  of its own and binds the one to the other. `near-app` and `far-app` cut the database and wire the
  slot the binding left open; `own-app` keeps it and wires nothing. That rewrite moved no plan key
  and no entry record of the three that existed before it, which is the claim the corpus's
  instance-as-group sketch makes and the reason the folder is where it is proven.
- Each app instance owns its own runtime directory, derived from its own identity. The service
  manager deletes a runtime directory when its unit restarts, so two instances sharing one name on
  a machine lose each other's records, which is how `own-app` first failed.
- Its server declares `restart = "on-failure"` with a `restartSec`, so the folder asserts recovery
  from a killed main process beside the deliberate restart: one case is the service manager's and
  the other is the operator's, and neither dials the machine to apply anything.
- The `postgres` account is the guest image's, because nothing in a plan creates an account: a
  module's unit names a user and no realiser provisions one. Every property of the shared image is
  part of every snapshot cut's key, so that one line made the next run of every folder cold;
  `rookery snapshot gc --all` is the reclaim. `tests/unit/layers.nix` crosses every account a
  folder's unit names against the image's own declaration and its assertion.
- The disk that folder's data directories need is its stage's, through `delivery.cluster_stage`'s
  `disk_gib`, and never the shared image's `additionalSpace`: growing the image re-keys every other
  folder's cut, and growing one stage re-keys only its own. Two clusters on one machine is what
  moved that figure last, and it moved this folder's cut and nobody else's.
- `tests/unit/layers.nix` recognises a folder that writes state by a module of it naming a path
  under a home the guest image declares for an account, or declaring a `stateDirectory`, because
  nothing in a plan creates an account and no settings knob names a directory any more. A folder
  that writes state and is not recognised makes the space check pass vacuously, which is what
  `testAFolderWritingStateIsRecognisedByWhatItDeclares` is for; `dataDir` in any of a folder's own
  text is what `byADeletedKnob` refuses, so a binding may not be named after the knob that went.
- That folder builds its deployment twice, `default` and `changed`, differing in one database's
  declared owner. The second build is the second apply's, which is the only way a convergence
  claim can be made at all: a first apply of anything creates what it names.
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
- Edit `tests/e2e/guest.nix` and then run `rookery snapshot gc --all` before anything else. Observed
  after the `postgres` account was added: folders resumed a cut whose frozen RAM names a system
  generation the new image's disk does not carry, so `/run/current-system/sw/bin` is a directory of
  dangling symlinks and every remote command answers `mkdir: command not found` while `$PATH` reads
  correctly. It looks like a broken write script and is a stale cut; the cold run after a `gc` is
  the check.

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
- A fold's refusal is an in-band sentinel: `lib/resolve.nix` reads a returned attrset carrying a
  `refused` attribute as a refusal, so a fold whose own successful result carries that name cannot
  succeed. A tagged pair costs one line per fold.
- The purity scan in `tests/unit/diagnostics.nix` is substring matching over comment-stripped text,
  so `.check ` matches inside a string literal and `assert ` misses a call spelled with no space.
  `ast-grep` is installed and parses.
