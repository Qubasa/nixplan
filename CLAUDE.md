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

## Deployment scope

User-scope deployments are the project's explicit goal. The end state: an operator manages
infrastructure with client roles and can hand a third party a self-installing package that spawns
user services without root - a mesh node and the operator's own application, authenticating
against the operator's IdP and reaching the operator's services over the mesh. The open change
`run-an-entry-without-root` lands the substrate; a later change, named there as a non-goal, owns
the exported bundle for a machine no run can dial.

- A deployment is made as an account, never as a mode. Root is the account every check admits, so
  there is one model and no second code path, and nothing may branch on "root or not" where it can
  ask "can this account do it".
- `scope` is a machine registry key with two values, `system` unstated. Stating the default
  re-keys nothing; `user` enters the hashed machine record and the target, because rendered
  units, attach argv and profiles all differ under it. The domain has one home,
  `atoms.domains.scope`, and deliberately no korora typedef of its own: no module and no
  interface declares a scope, the one reading that crosses a stated value against the domain is
  the registry's, and a second top-level key in `lib/atoms.nix` costs a gated counter - the
  reason is under Perf harness. The boundary a privileged port claim is read against is
  `atoms.portRange.privilegedBelow`, in the record that already states the port domain.
- The registry's scope reading is one memoised table, `machineScopes` in `lib/resolve.nix`,
  answering `refused`, `usable` and `value` per machine, because `placeable`, the row, the machine
  record and the target all ask it. Both optional fields of a machine record - the
  microarchitecture and the scope - ride one update for the same reason a plan counts its copies.
- A declared fact a user scope cannot honor is an error row, never a silent drop or a collapsed
  default: a unit's account, its supplementary groups, a fixed port below 1024, a delivered
  file's stated ownership. Confinement that needs no privilege - seccomp filters, the
  namespace-based sandboxing - is not in that set and is not degraded.
- The fixed roots do not move with scope: `/run/vars`, the sealed root and the image staging root
  are the same paths on every machine, so no uid enters a plan and a scope flip re-keys entries
  and not values. Provisioning makes the roots account-writable on a user-scope machine. Root at
  provision time, never at deploy time, and the apply's preflight verifies rather than assumes.
- A realiser publishes the scopes it can realise beside its name and unit rules, and the reading
  crosses the stated realiser against the machine: a mismatch is `operator-entry-scope-unsupported`.
  flakelet is system-only - its core writes `/run/systemd/system` and `/var/lib/flakelet`
  (`systemd.rs:13` at the locked revision) - until upstream grows a user mode.
- The portable image is the user-scope realiser. systemd 260 added the per-user portabled and the
  pinned nixpkgs resolves systemd 261.1. A user attach needs `systemd-mountfsd` and
  `systemd-nsresourced`, unprivileged user namespaces, and a **signed dm-verity** image: an
  unsigned image outside the system trusted directories escalates to an interactive polkit
  action, which a non-interactive run reads as a hard failure. The verity public key is installed
  at provision time and the signing key is `mkDeployment`'s `signing` argument,
  `{ privateKey, certificate }`, one key per operator and never per entry, spent only by the image
  build: no plan field, no reading field, no record field and no artifact carries it, so rotating
  it re-keys nothing.
- The signature is a **sidecar** set beside the squashfs and not a signed GPT image: upstream's own
  user-scope portable test signs `<name>.verity`, `<name>.roothash` and `<name>.roothash.p7s` with
  the `.raw` dropped from the image's name, which is the naming rule `systemd.exec(5)` states, and
  `veritysetup format` plus `openssl smime -sign` is the whole step. A `systemd-repart` DDI was
  built first and deleted: it needs a systemd architecture-name table the tree has no other use
  for.
- A user-scope image places its unit files under the user unit directory - user-mode extraction
  reads only that path and a system-unit image yields `Couldn't find any matching unit files`,
  observed - and states `PORTABLE_SCOPE=` in its os-release, which gates attachment: the same
  image offered to the system manager is refused with `portable scope 'user' incompatible with
  portabled runtime scope 'system'`, also observed. Upstream's user profiles drop
  `DynamicUser=yes` and `ProtectHome=yes` and keep `PrivateUsers=yes`; `trusted` is identical, and
  the reading's denial table is per scope, derived from the statements the scope keeps rather than
  written out twice.
- Persistent user attach copies an out-of-tree image to `~/.config/portables`, which the user
  image search path never scans (systemd 261). The attach flow places the image and its three
  sidecars into `${XDG_STATE_HOME:-$HOME/.local/state}/portables` at `0700` and attaches by name
  rather than relying on that move.
- An attach does not deliver: `portablectl attach --now` cannot start a user unit the manager has
  not reloaded yet, so the script attaches and then `systemctl --user start`s the entry's units by
  name.
- The seal recipient is an age key the registry declares (`sealRecipient`), never the machine's
  ssh host key: an account cannot read `/etc/ssh` host keys, sshd refuses looser modes, and age
  supports no agent. The identity file is minted at provision time and its public line pasted
  into the registry; nothing in this repository holds or moves the private half.
- The published provisioning module carries the one-time root work a machine needs before a run can
  write to it as the account it deploys as, and it is the declaration `preflight` in
  `cli/remote.py` verifies per run - the same six facts, which is also the limit on which machines
  can receive a user-scope entry. It asserts two things a plan cannot state: the service manager is
  built `withPortabled`, and the package set's systemd resolved a `vmlinux.h` or the machine
  vouches for the interface itself, because nsresourced compiled without BPF refuses the userns
  API. `tests/e2e/guest.nix` imports it rather than holding a second copy, which is why editing it
  re-keys every folder's snapshot cut.

## Enrollment and the mesh

How a machine becomes a member is `openspec/changes/enroll-a-friend-machine`, **landed** behind the
four production changes: no registry key, no plan field and no library rule, so that half of it is
a row convention, a credential's handling discipline and the proof in
`tests/e2e/friend-enrollment/`. `enroll-a-friend-outside-the-harness` took it out of the harness
and is **landed** too: the acts are three verbs of the command, which entry coordinates is a
statement beside the deployment, and the server and the provisioning are modules under
`published/` a consumer composes rather than a folder's own text. The decentralized alternative was
designed, red-teamed and parked: it is in `openspec/changes/PARKED.md` with the trigger that
revives it.

- Enrollment is centralized on purpose: a coordination server the operator runs is the membership
  authority. The registry declares, the server admits and expels, and the sync is one-way,
  registry to server - the server's database is never a source the planner reads.
- Runtime facts never enter evaluation: a machine's current endpoint, presence and last-seen are
  the mesh's facts, `mkPlan` sees none of them, and the only gate from the mesh back into
  evaluation is an operator-reviewed registry edit.
- An export binds to a name, never an address: a friend machine's registry `address` is its mesh
  name, so a URL built from `target.address` carries the name and whatever answers it is the
  mesh's business.
- The join credential is a generated secret value like any other: minted by the hub entry's
  generator, single-use and expiring, delivered to no machine, handed over outside the tree, and
  its bytes enter no plan field and no argv.
- A run reaches a mesh name from wherever the command runs, so the operator's own machine is a
  member too: a run dials `ssh <user>@<address>` and `nix copy --to ssh://<user>@<address>` and no
  layer below that resolves a name for it. The end-to-end run cannot be root, so its node is a
  `tailscaled --tun=userspace-networking` one started inside the cluster's own user and network
  namespace, and the name is resolved by an ssh `ProxyCommand` through that node - measured, and
  the reason it cannot be a hostname the machine's resolver answers: a userspace node installs no
  OS resolver, so `tailscale ping <name>` and `tailscale debug resolve` fail while
  `tailscale nc <name> <port>` resolves it inside the dialing path. `delivery.mesh_membership`
  owns the node and `delivery.namespace_prefix` the namespace it is started in.
- The coordination server is an entry the plan places, never guest-image wiring: the image carries
  the client daemon and the server's tool and nothing else, because a daemon holding a tun device
  and a node key is nothing a plan creates and the operator's mint, node list and expiry are acts
  against the server rather than units of it.
- The server's own tool reads a copy of the configuration under a name ending `.yaml`. The store
  object the unit is shown is named by its hash with no suffix, and the server decides a
  configuration's format from the extension: `error loading config file <store path>` is what an
  operator invocation pointed at the object itself answers. The host path the entry states exists
  inside that unit's namespace alone, which is why a copy and not that path.
- `headscale preauthkeys create` takes a numeric user id, not a name, so the id the server's own
  database assigned is read back with `headscale users list --output json` and handed to the
  minting program. A credential appears in the server's own listings masked to its first twelve
  characters, which is why a listing may be read back verbatim.
- An expiry is a fact about the dialing node's map of the mesh and not about the server's database:
  the server answers immediately and the route goes when the node is handed a map without that
  peer, so the folder waits by asking its own node and never by sleeping. A report run in between
  reads the route that is about to go and answers `current`.
- The published coordination module renders the configuration once and is shown twice: the declared
  `configData` file the realiser binds, and a store object named `planner-coordination.yaml` that
  the operator's verbs read out of the entry's own closure, because the server decides a format
  from the extension and a store object is named by a digest with no suffix. No step installs a
  copy at a host path, and `coordinate` is what names the two objects to the command.
- Every cluster choice the module takes is a settings knob defaulting to what it can defend outside
  a cluster - a loopback listener, clients verified, no embedded relay, an expiry that is not
  forever - and `clientUrl`, `policy` and `domain` are arguments it refuses to default, because a
  deployment that states none of them has no working mesh and should not be told that it has one.
  `tests/e2e/friend-enrollment/` states the cluster's own answers as settings, which is what makes
  it a consumer of the module rather than a second copy of it.

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
- A string a derivation *writes* carries no context; a path a copy has to *follow* keeps it. Every
  layer spends the same discard, and it is four sites in three layers rather than one rule in one
  place, because each is a different use of one row's or one record's text: `dedup` in
  `lib/diagnostics.nix` keys a row by its own identifier, subject and message, and an attribute
  name may carry no context, so a message naming a store path - a closure root nothing mentions is
  one - ended the evaluation inside the table that exists to report it;
  `operator/default.nix` discards where the farm writes `diagnostics.txt` and `diagnostics.json`,
  because `writeText` refuses a string with context; and `flakelet/default.nix` discards the base
  name it builds a `closure/` link's name from, while the link's target keeps its own. A fifth site
  is a place to forget it. `plan.json` and `manifest.json` keep their context, which is what roots
  the paths a copy puts on a machine, and the discard in `lib/` is at that one key and nowhere
  else: inside `util.oneLine` it runs three to four times per row and cost 45 gated figures against
  the key's 33. `probes.nix`'s `aRowNamingAStorePathIsStillARow` is the pin.
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
- The four rows a user scope earns are produced where the crossing they are about is held: the
  three entry-side ones in `mkPlacement`, beside `unit-extension-backend-mismatch`, because two of
  them read the units an implementation produced for that placement, and
  `value-ownership-in-user-scope` in `lib/plan.nix`, whose subject is the value entry. Each is a
  refusal and not a filter: the entry stays in the plan.
- "States an ownership" is read off the file record against the default it resolves to unstated,
  which is the comparison the value's key already makes. Stating `root` therefore states nothing,
  in the row as in the key.
- The accounting cross-walk reads comment-stripped source lines with no notion of a nix string, so
  the moment a builder *borrows* a reading's `fail`, every rendered shell `fail "…"` line in that
  builder reads as an unaccounted refusal - `image/default.nix` renders six. A realiser's refusal
  therefore lives in its `read.nix`, which is where the sentence belongs anyway.
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
- A probe and its bound are unit fields, so they are in the entry's key like every other unit
  field: a changed probe is a new generation and a new image, observed on a machine as two image
  digests for one entry. Neither is defaulted, because a bound nobody stated would be a service
  manager's own default standing in the record.
- A machine's own answer about what it holds is keyed by nothing this tree writes: a flakelet
  holding is recognised by the published `plan:` prefix and what follows it is the plan key, and an
  image holding is recognised by splitting the name `portablectl` printed at the published
  separator into a name and a digest of the published length over the published alphabet, with no
  plan key derived from it at all. That is why the fact is published as data - a separator, an
  alphabet, a length, a prefix - and never as a pattern: a nix pattern and a python pattern are two
  dialects and one published pattern would be one rule with two readings.
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
- The seal recipient a machine states is a fourth projection of the registry reading, beside the
  reservation and for the same reason, so declaring or rotating one re-keys nothing - which is what
  `testARotatedIdentityReKeysNothing` asserts by planning one deployment twice. Unlike the
  reservation the plan does record it: the `machine:<name>` record carries it as an explicit
  absence, present and null where none is declared, because an absent field means the plan does not
  know and a reader has to be able to tell that apart from "declared none".
- A value's sealed path is derived from its runtime path by `util.sealedPathOf` and is a field of no
  file record, which is what keeps it out of `fileKeyInput`: a sealed path in the record would
  re-key every generated value the first time a root moved. The realisers and the command derive
  it; nothing in `lib/` spends it per entry.
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
- `mkDeployment` publishes the rendered table beside the rows, bound once in `operator/default.nix`
  and spent twice, so the farm's `diagnostics.txt` and `passthru.rendered` are one text in one
  rendering. Rendering is the planner's; a second renderer would be a second format to keep equal
  to the byte-compared fixture.
- `lib/vocabulary.nix` publishes the authoring vocabulary as data, projected from the tables
  `lib/atoms.nix`, `lib/module.nix` and `lib/resolve.nix` already hold and restating none of them,
  so a key added to a table is described by existing. It is published because the library is what
  enforces it and because `lib/default.nix` publishes neither `module` nor `resolve`; `moduleKeys`
  and the four registry key lists are the two additive exports that made the projection possible,
  both evaluated once per library import and outside `mkPlan`. A type is published by its name and,
  where it is an enumeration, by its members; a predicate is published in no form, because a
  validator is a function - the limit `identityOf` and the platform record's absent `is*`
  predicates already record - and `atoms.domains` is read for its list-valued members alone. Every
  leaf is a string, a list of strings or a record of those, which is why the port range is text.
  The row identifiers are deliberately not projected: their home is the production sites and
  `docs/diagnostics.md`, and the rows one deployment earned are `planner diagnose`'s answer.

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
- The image root carries `/etc` whatever the entry is shown, because it carries `/etc/os-release`,
  `/etc/resolv.conf` and `/etc/machine-id`: a system-scope image got the directory for free from
  its unit directory `/etc/systemd/system`, and a user-scope one, whose units go to
  `/usr/lib/systemd/user`, failed the build at `touch $out/etc/resolv.conf`.
- An image an account attaches is reached by its path by a child that owns none of the account's
  directories, so every component of the pool path is created traversable. portabled extracts the
  metadata in a child that joined the user namespace nsresourced delegated, in which the
  account's own uid is unmapped, and `extract_now` asks whether the image path is the root
  directory (`chaseat_prefix_root` -> `path_is_root_at`), which opens the path itself
  `O_PATH|O_DIRECTORY`: a world-traversable path answers `ENOTDIR` and is read as `not root`, and
  one that is not answers `EACCES`, which `portable.c` returns unlogged and the manager reports
  as `AttachImage failed: Access denied`. The attach script therefore names `$HOME/.local`,
  `$HOME/.local/state` and the pool - or `$XDG_STATE_HOME` and the pool where that is stated - in
  one `install -d -m 0711`, which is the staging tree's mode and for the staging tree's reason,
  and the home above them is the machine's, verified by the preflight.
- A realiser shows a host path only for a generated file whose entry records `deploy` true. An
  undeployed value is on no machine, so binding its path mounts nothing and the unit fails at
  `226/NAMESPACE` naming neither the value nor the declaration. That is why every file record in
  the plan carries `deploy`: the owner of a `deploy = false` generator runs units of its own, and
  its entry holds the value's path either way so that a site opening it is still a row.
- A realiser shows a host path for every deployed generated file the entry's own declaration
  generates **and** for every one a declared read of it names: an entry that generated none of a
  value is shown it because it reads it, which is what lets one value serve a fleet without a
  second generator. The union is one list, one record per path, and the host paths, the denial
  table, the reference paths and the attachment description all read that one - a value reached
  twice, by two reads or by a generator and a read, being one record and one bind. The join is by
  the path the read record already carries, never by ownership carried beside it: `reads` is in the
  entry's key input, so a peer's `owner`, `group` or `mode` recorded there would re-key every
  consumer the moment the value's own record moved, and who may open the file stays the value
  entry's answer looked up by that path. A shown value path the plan's value records account for no
  delivered bytes at is `operator-entry-value-unaccounted`, refusing the entry, the slot and the
  path rather than mounting nothing or omitting the path without a word.
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
- A probe is one derived `<service name>-health.service` per entry, derived in `unitFilesOf`
  because that is the one derivation the image's name rule, flakelet's `acceptsUnit` and the
  per-machine unit-file index all read, so all three see it by existing. One per entry and not one
  per unit, because that name is the only file flakelet's activation starts; a second probe on a
  second unit is `unit-probe-declared-twice` rather than a file nobody starts. It carries no
  `[Install]`, which is why it is rendered by the shared reading and by neither realiser's wrapper,
  and both realisers therefore produce one text. It inherits the probed unit's account and declares
  no directory of any kind: a service manager deletes a unit's runtime directory when that unit
  stops, so a oneshot that exited would take the probed unit's directory with it.
- What a failing probe means is the realiser's and not the plan's. flakelet deletes the new
  generation, switches back and exits non-zero, so the previous generation is what runs. The image
  realiser has no generation to return to: the probe is in the attachment's unit list, the attach
  script starts it, and a failure is a failed apply step naming the entry and what the machine
  printed while the image stays attached running what it holds. Nothing rolls back there, and that
  is stated rather than dressed up.
- Each realiser publishes, beside its name rule, its unit rule and its `scopes`, one `holdings`
  record saying what a machine's own answer names its holdings by, and it publishes for every
  realiser the reading is handed rather than only the ones an entry states: an entry the build
  dropped may have been the last one of its realiser, and a table of the stated ones would make
  exactly that holding unfindable.
- Both realisers are handed the same `assemble` argument, so a configuration file whose bytes the
  plan holds is one store object written once.
- An artifact references every root its entry declares, under both realisers: the image carries
  them in its own closure and the flakelet farm carries one `closure/<name>` link each, deduped
  through `util.uniqueStrings`. Without it the farm referenced `meta.json`, the unit files and the
  assembled configuration files alone, so a declared root that no unit mentions never reached the
  machine and `operator/read.nix`'s own sentence about a verb running a program out of the entry's
  closure was false for that realiser - observed as a coordination server answering `error loading
  config file <store path>: no such file or directory` after a clean apply. A root a unit mentions
  arrived anyway, by mention, which is why only an operator's own object could catch it.
- `flakelet/read.nix` restates `validate_name` and `validate_units` from flakelet's own
  `manager.rs`, and binds the `plan:` prefix once so `meta.json`'s `flake_url` and the published
  `holdings.urlPrefix` are the one string. `tests/e2e/delivery.py` keeps no copy of it any more: it
  reads the published value off the deployment record, which is what deleted a second literal that
  was kept equal by comment.
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
- The unsealer is the one artifact keyed by a machine and not by an entry: `machines/<name>` in the
  same link farm as the entries, one per machine a **delivered value reaches** that declares a
  recipient - the delivery set and never the placement, which is why the fixture's `gamma` gets
  none. It is a function of the value file records, the machine's scope and the ordering list, and
  never of the recipient, so a rotation rebuilds nothing. It carries `bin/unseal`, `bin/check` and
  `planner-unseal.service`, with `age` in its closure, because a program that arrives off the
  machine's own `PATH` is a fact no plan records.
- `planner-unseal.service` orders and does not require: `Before=` every unit file the reading's
  ordering list names and no `Requires` of any reader, so a machine whose seals do not open still
  starts its readers and they still fail on the file that is not there. Its own name carries one
  hyphen where every name an entry can derive carries at least two, which is how a machine's unit
  cannot collide with an entry's.
- `bin/unseal` opens into a temporary created `0600` inside the plaintext's own parent chain, owns
  it, chmods it and **moves** it into place, for the reason the attach script does the same: the
  move is what makes the readable window empty rather than narrow. It leaves a plaintext that is
  already there untouched, names a copy it could not open and exits non-zero **after** restoring
  every other, and age's own stderr goes nowhere, so no byte of a sealed file reaches a log line.
- `operator.mkGeneration` is where the secrets reading is built. `operator/default.nix` takes
  `korora` for `plan.nix` alone, nixpkgs arriving as `pkgs.path` and the library as `../lib`, and
  that expression imports the deployment's `args.nix`, never its `default.nix`.

## The operator's command

Prose: `docs/operator.md`, under "The command", "Where the bytes of a generated value come from",
"The order `apply` walks", "When a run breaks" and "Reaching a machine".

- A machine question is answered as a record and never as a sentence: `report.status` returns one
  per question it asked - one per entry, one per value delivered to a machine, one per holding the
  build names no entry for - and `report.lines_of` is the one function every line comes out of, the
  applying run's holding line included, so `remote.Holding` carries no `sentence` of its own. A
  reading composes no line, a field the reading did not compute is absent rather than empty, and
  the field set is what the readings already produced rather than a verdict invented beside them:
  an image's two identities are carried and the word comparing them is the renderer's. The four
  answers a report keeps apart - absent, no endpoint, unreachable, not dialled - are four values of
  the one `reached` field rather than four spellings, absence still rests on the one fact that an
  endpoint answered and registered nothing, and an answer the command cannot read stays a refusal
  rather than becoming a sixth value. The operator's sentences are byte-identical, which is what
  the harness case rendering every record shape against the lines `docs/operator.md` states holds,
  beside the five folders asserting those strings on real machines. Staleness is a field and still
  never an exit status: `unasked` is the one thing `planner status` exits non-zero on.
- The command's one decode of `diagnostics.json` carries all six fields a producer builds a row
  with, `evidence` and `resolution` included: `cli/manifest.py`'s `_rows` is the only reader of
  that file, every consumer of a build's rows goes through it - the fallback `Deployment.rendered`
  composes where a build wrote no table included - and a second reader for the two fields would
  leave the one every command imports the lossy one.
- `apply` orders by every resolved read of `plan.<consumer>.reads.<slot>`, never by `dependsOn`.
  A single-valued read records `entry` and a `reach = "all"` read records `entries` keyed by
  provider, and both are edges. A delivered read recorded in neither shape is the command's own
  refusal naming the consumer and the slot, because an unrecognised shape that contributes zero
  edges is what let that stand. Values are written before any entry is activated, and an entry is
  copied before it is activated.
- A user-scope machine is asked one question before the run writes anything there, and the answer
  is read where it was asked: the plan holds no fact about what a machine currently permits, so a
  fact that does not hold is the command's own `ApplyError` naming the machine and every failed
  requirement with what the machine answered, and no diagnostics row. One question per machine,
  folded the way the values and holdings questions fold, because a guest's sshd is per-connection
  socket activated and a burst of short logins hits the socket's own trigger limit. It is the head
  of the on-machine line - before the retirement, the unsealer install, the value writes, the copy,
  the activation and the value-driven restarts, which `openspec/changes/INTEGRATION.md` writes out
  once - and under `--dry-run` it goes through the replaced channel and is recorded rather than
  asked. A system-scope machine is asked nothing new.
- Root at provision time, never at deploy time. The three fixed roots the preflight verifies are
  stated once in `cli/remote.py` - `/run/vars`, `/run/portable-planner` and the sealed root - and
  the sealed root is that file's own constant until `unseal-a-value-after-a-reboot` lands, which
  has to adopt it rather than state a second one.
- Two of the preflight's facts are the attach's alone and are asked only where an image entry is
  placed: the account's own portabled, and the account's home and every directory above it being
  traversable by a uid that owns none of them. The second is stated as traversal by another uid
  rather than as a mode, so 0711 and 0755 both answer `ok`, and it exists because its absence is
  otherwise unreadable: portabled answers `AttachImage failed: Access denied` and names no path.
  The key set the question asks is crossed against `tests/e2e/test_harness.py`, so a fact added
  here is added there.
- Every step that addresses an account's own manager states `XDG_RUNTIME_DIR` itself: a
  non-interactive login has no session, so nothing else sets it, and `systemctl --user` then
  answers about no manager at all. The `--user` a step spends is read off the machine's scope in
  the record and the published `scopes` of the realiser the step belongs to, never off the login.
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
- A machine's unsealer is copied and its unit installed before that machine's **first** value
  write, for exactly the machines the run writes a value to whose record says they seal. The unit
  goes to `/usr/local/lib/systemd/system` with a `<target>.wants` link beside it, one spelling on
  every machine rather than a path chosen by testing what the machine permits: `/etc/systemd/system`
  is a link into a read-only store on an image-managed machine and `systemctl enable` writes into
  that same directory, and `/run/systemd/system` is disqualified by the thing the change exists
  for, a reboot emptying it. Observed on the guest: `FragmentPath` answers that path and `WantedBy`
  answers `multi-user.target`. Idempotence compares the two links and never `systemctl is-enabled`,
  which answers `alias` there - a word about how the file arrived rather than about what starts the
  unit.
- A sealed copy is written on every apply and has no `changed`/`unchanged` answer of its own,
  because two sealings of one file differ; whether the bytes moved stays the plaintext step's
  answer. The sealed copy is written **first**, so an interrupted run never leaves a sealed copy
  older than the plaintext beside it. The recipient is a public word and may appear in an argv; the
  ciphertext travels on the step's input stream, so no byte of a value, sealed or plain, ever does.
- A value write compares on the machine and answers `changed` or `unchanged`, and neither the bytes
  nor a digest of them is ever printed or put in an argv. A value that moved restarts its readers
  last, after every activation: the readers are the entries whose resolved reads name that value on
  that machine, which is the same index `cli/order.py` builds its edges from, and the restart is
  `systemctl try-restart` of the entry's whole unit list. Coarse on purpose - the plan says which
  entry reads a value and never which of its units opens the file - and `try-restart` because
  whether a unit runs at all is the activation's answer and never this step's, so a unit an operator
  stopped stays stopped and a unit the activation just started is not restarted twice.
  A value that moved does not re-run a probe either, for the same reason and by the same mechanism:
  `try-restart` skips a oneshot that already completed, so a probe is a question about an
  activation and never about a value write.
- What a machine holds that the build names no entry for is a line every apply and every report
  prints, and removing it is opt-in. Every run asks one holdings question per machine of the
  selection before it writes anything anywhere, so a run that cannot read one answer has changed
  nothing; without `--retire` the line carries `; not retired`, which makes a plain apply the
  preview of one with the flag. The retirement itself is the endpoint's own verb - `flakelet
  remove` without `--purge`, `portablectl detach --now` over the name the listing printed - and it
  deletes no state and runs no script out of the retired entry's own artifact, which is not in this
  build and which nothing on the machine roots. It is taken after the preflight question and before
  the first value write, the first copy and the first activation, because the host resources an
  orphan holds - a port, a unit file name, a host path - are exactly what a renamed entry needs
  back before it can start. `--only` bounds which machines are asked and decides nothing about what
  counts as unnamed: a holding is unnamed when the deployment places no entry that owns it at all.
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
- `planner diagnose` is the one subcommand that realises nothing: it prints the rendered table and
  exits 1 where a row carries an error, which is the status `build` reports, and `--json` prints the
  rows instead, in the table's order and with every field a row carries. A target that is a built
  directory is answered from the two files the build wrote with no `nix` at all, and any other
  target by one `nix eval --apply` selecting the two published attributes by name, `diagnostics` and
  `rendered`. The record as a whole is never evaluated - every entry and machine attribute of an
  inapplicable deployment is `throw reading.refusal`, and an inapplicable deployment is the one an
  author is iterating on - and a target answering neither attribute is the command's own
  `ApplyError` naming the target and both attributes, never an empty table and never a row of the
  command's own. `cli/diagnose.py` owns that reading and decodes no row itself: the built-directory
  branch spends `manifest.read`, whose `_rows` stays the one decode.
- A membership act is a verb of the command - `invite`, `members`, `expel` - and never a shell
  string a test composes. Each is one step on the machine of the entry the deployment states as its
  coordination server, addressed by that machine's own scope, and a machine that does not hold the
  program this build names is refused naming the entry and the path rather than having one
  reconstructed. `--only` is deliberately not theirs: the selection bounds which machines a run
  asks, and a membership act is about one entry the deployment named.
- Which entry coordinates a mesh is stated beside the deployment as `coordinate`, an argument of
  `mkDeployment` beside `realise` defaulting to `{ }`, and inferred from
  nothing - not a module's identity, not a package in a closure, not the text of a plan key. An
  unstated statement is no statement: no row and no record key, and every verb refuses on that
  absence naming what to add. A statement naming no record of the kind the field is about is
  `operator-coordination-names-nothing`, and a program or configuration object outside the stated
  entry's own closure is `operator-coordination-object-unheld`.
- `invite` mints with the generated value's own declared program, run where the server answers
  under the contract the external backend already runs a generator under (`out` set, the files read
  back off the step's stream), so the deployment stays the one place a credential's expiry, file
  name and secrecy are declared and the command chooses none of the three. The bytes reach no
  argument vector and no line the verb prints; the expiry rides beside the key as a public file,
  because what a credential was minted under is a fact the operator is told. `members` prints the
  server's own answer verbatim, a reformatted listing being a second format to keep equal, and
  `expel` takes the node identifier out of that listing and refuses a registry machine name in its
  place.
- The view reads a build and mutates nothing: no route applies, retires, rolls back, builds or
  writes, every method but `GET` and `HEAD` is refused, and it binds the loopback interface, an
  instruction to listen elsewhere being refused naming the reason. The target is resolved once
  through `manifest.resolve` before the port is open, so the one branch that invokes nix runs in the
  foreground and no request is ever a build. The live half calls `report.status` with the command's
  own runner and renders the record it answers with - no question, no remote script, no verdict
  vocabulary and no parsing of another layer's sentences - and it asks only when a reader asks, the
  answer carrying when it was taken. A fact the report does not answer is a requirement against the
  report's own capability, never a question the view invents. The graph's column is the index of an
  entry's strong component in `order.walk`'s order, the row is plan key order within it, a value is
  a cell in the column before its readers, and a read recorded in neither recognised shape is named
  by consumer and slot rather than dropped.

## Registration points

Each of these lists is hand-maintained. An addition that skips one fails a check, or worse, is
silently unobserved.

- A new unit suite goes in `suites` in `tests/default.nix`. That attrset is the only registration
  point, and its key names feed the coverage cross-walk. `coverage` is passed its own name too;
  that is not a cycle.
- `tests/unit/published.nix` is the suite for the modules under `published/` and for their
  consumers inside this repository. It is handed `planner`, `support`, `nixpkgsLib`, `imageSource`
  and `repoSource` - no `publishedSource`, because `repoSource + "/published"` reaches it and a
  sixth source argument is a second edit in `flake-module.nix` for every suite that wants one. A
  unit suite instantiates no package set, so that one stands one in: every builder answers a store
  object named by the bytes it was handed, which is load-bearing rather than incidental - two
  objects rendered from one text are one path, and that is how the suite proves the bound
  `configData` file and the `planner-coordination.yaml` object are one rendering rather than two
  that agree today. The three roots the provisioning declaration makes account-writable are crossed
  against the layers that own them - `planner.util.varsRoot`, `planner.util.sealedRoot` and the
  parent of the image reader's staging path - and written out nowhere, so a path that changes
  changes in one place.
- A counterexample goes where its own failure allows: the suite, the probe file or the command's
  test file, under "Counterexamples on record". A probe is named by existing - `flake-module.nix`
  reads `builtins.attrNames` of `tests/counterexamples/probes.nix` - and a directory beside
  `tests/unit/` and `tests/e2e/` goes in `layers.testTheTestTreeIsRead`.
- A new top-level file or directory goes in `classOf` in `tests/unit/layers.nix`, and in
  `scannedDirectories` there if its files should be held to the path scan. `lemmalog.nix` is
  classed with the flake for that reason, and the index's own corpus lives under `docs/` so that
  carrying it adds no class.
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
- Thirteen changes are open. `answer-whether-a-machine-is-current` stays open because its tasks 1.1
  and 1.2 record themselves as not doable and superseded by `tests/e2e/test_harness.py`, so marking
  them done would falsify the record, and its 21 landed tasks are what the synthetic half of
  `testAnExcuseOutlivesTheStateItDescribes` reads: archiving it moves that probe.
  `declare-service-state` was **struck**: the vocabulary's own `directoryKinds` made its premise
  false and the readers it was for are outside this repository, so its unbuilt half is in
  `openspec/changes/PARKED.md` with the trigger that revives it.
  `deliver-a-secret-without-exposing-it` is narrowed: its
  `operator/machine-identity` capability, its sections 3 and 5 and its task 7.5 are superseded by
  `name-the-machine-a-run-dials`, and the delta file is deleted, because a capability that never
  landed cannot be the home of a rule the current `planner/machine-platform` spec refuses and the
  current `operator/apply-command` spec licenses. `name-the-machine-a-run-dials` is itself parked:
  user scope moved the seal recipient to an age key, so nothing consumes `hostKey` any more, and
  connection pinning is unowned until an operator decision revives or deletes the change. The five
  that make the tree operable have **landed**: `run-an-entry-without-root`,
  `retire-an-entry-a-build-no-longer-names`, `probe-a-service-before-it-counts-as-live`,
  `unseal-a-value-after-a-reboot` and `enroll-a-friend-machine`, each with every box ticked and all
  eighteen of their delta specs moved from `excused` to `accountable` in the one edit that ticks
  them. They stay on disk under `openspec/changes/` until they are archived; the parked change's
  three delta specs are still `excused`, and archiving a landed change moves its delta specs out of
  `accountable` and its content into the current spec. The designs `enroll-a-friend-machine`
  deliberately does not build are parked with their triggers in `openspec/changes/PARKED.md`.
  Five of the thirteen are the demo set, planned in parallel against one set of contracts the way
  the production four were, and `openspec/changes/INTEGRATION.md` carries a second section holding
  their order and their seams: `bind-a-value-an-entry-did-not-generate` first, because it is the
  set's only correctness defect and the demonstration's own shape is what trips it, then
  `answer-a-machine-question-as-a-record`, whose record and whose six-field diagnostics decode two
  of the remaining three consume, then `show-a-deployment-in-a-browser`,
  `author-a-deployment-from-outside` and `enroll-a-friend-outside-the-harness` in any order. Their
  fourteen delta specs are `excused` with the planning artifacts, and
  `bind-a-value-an-entry-did-not-generate` narrows `deliver-a-secret-without-exposing-it` once
  more by superseding its tasks 6.1 and 6.3. The three changes outside that set that carry no
  ticked box - `account-for-every-counterexample`,
  `hold-the-attach-script-to-its-own-discipline` and `hold-the-index-to-the-tree` - touch no
  command, no vocabulary and no plan field, and are deferrable whole.
- A directory kind goes in `directoryKinds` in `lib/module.nix`, which is what `unitVocabulary`,
  the two rows about a directory, `directoriesOf` in `lib/plan.nix` and the claim index all read.
  `unitVocabulary` reads it by deriving the kind's own field and its mode field from it rather than
  spelling the six out, because a hand-written vocabulary let a fourth kind be registered and stay
  silently inert: the field was dropped before `typed`, so `unit-directory-declared-twice` and
  `unit-directory-mode-without-directory` could not fire for it and the unit declaring it earned
  `implementation-unknown-key` instead.
  Adding a third *declaration site* for one is parked rather than open, under "Declared state
  beyond a unit's own directories" in `openspec/changes/PARKED.md`: a path-keyed `state` would be
  a third place one directory is stated, `unit-directory-declared-twice` only refuses two, and
  whichever shape lands has to decide which site owns the fact rather than growing a rule per
  pair of sites.
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
- `view/` is the read-only view of a built deployment, and it is registered in four places: a row
  in `classOf` and an entry in `scannedDirectories` in `tests/unit/layers.nix`, a
  `programs.mypy.directories` root in `treefmt.nix`, and an entry in `src` in `ruff.toml`. Three of
  those four fail quietly rather than red, which is why
  `layers.testAClassifiedDirectoryOfModulesIsCheckedAsWellAsClassified` crosses the classified
  python-module directories - `cli`, `perf`, `view` - against the mypy roots and the linter's `src`
  read as text. Its own `flake-module.nix` is one `imports` line in `flake.nix`, and its pytest file
  is one entry in `besideFiles` in `tests/unit/coverage.nix` or the cross-walk cannot see a name it
  answers a scenario with.
- A served route's leading segment names no top-level entry, and a served document names its own
  assets by route and never by a path of this source: `repoTokens` counts a token as a path exactly
  when its first segment is a real top-level entry, so `/documents/...` and `/page.css` are routes
  and `docs/...` would be a path the scan demands resolve. `view/routes.py` is the one home of the
  route set and `layers.testAServedDocumentNamesARouteRatherThanAPath` reads it there.
- A module this repository publishes for a consumer to compose goes under `published/`, classed
  there in `classOf` and in `scannedDirectories`, with its outputs registered by
  `published/flake-module.nix` in the `imports` of `flake.nix`. The directory is not called
  `modules/` for a reason a rename would re-break: `testAFileNamesAPathThatIsNotThere` scans raw
  text including comments, so a top-level `modules/` turns every `modules/...` token already
  written in `docs/`, `tests/unit/diagnostics.nix` and eight folder deployments into a repository
  path that must resolve.
- Every end-to-end folder is offered one argument set and receives the arguments it names, because
  `buildsOf` applies `builtins.intersectAttrs (builtins.functionArgs …)` in `flake-module.nix`: a
  published module is handed to every folder without widening the closed pattern of a folder that
  composes none. `builtins.functionArgs` answers `{ }` for a lambda with no attribute pattern, so
  such a folder is handed the base set instead: `tests/e2e/newcomer/deployment/default.nix` is
  `args: …` on purpose, and narrowing it by the intersection hands it nothing.
- The scaffold is published as `flake.templates.default` naming `./tests/e2e/newcomer/template` and
  never as a copy of it: a second text kept equal by hand is what "the example a document shows is
  the example a test builds" exists to refuse. It is in `flake.nix` rather than in
  `flake-module.nix`, whose text may name no end-to-end folder
  (`layers.testAnEndToEndFolderIsAddedWithoutEditingTheFlake`). `layers.consumerCalls` exempts
  `template/flake.nix` from the builder scan for `mkPlan` alone: that flake is a consumer's, calling
  the published planner by name, and it may still not realise.
- The scaffold carries two entry points over one deployment text. `deployment/args.nix` states the
  declarations and takes every package a module interpolates as an argument, and
  `deployment/default.nix` builds those packages and composes it, stating no instance of its own.
  Its formals are `{ packages, ... }`: the ellipsis answers the library and the state a secrets
  generation hands every `args.nix`. The flake's rows-only output plans those args against
  store-shaped stand-ins, because `util.storePathsIn` recognises a store path by the store directory
  and 32 characters of Nix's base 32 - a bare name turns the closure family off and leaves a table
  that is clean for the wrong reason.

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
  4, 16, 64, and 256. The margin is one-sided: it is the headroom a measurement may have *below*
  its budget before the budget has to be lowered, and anything above the budget fails by any
  amount.
- The gate is a two-sided ratchet, so it is re-recorded and the rule is about when. A refactor that
  costs evaluation for no new fact pays for it at its own site and the budget does not move. A
  declared fact the planner has to read is the other case, and it re-records with three things on
  the record: the measurement that shows the cheapest implementation does not fit, the figure it
  cost, and the reading that accounts for it. `perf/budgets.json`'s `note` is where that is written,
  and one recording covers a whole set of landings rather than one per change: the 2026-09-18
  recording is four changes at once, because recording per change would have re-recorded the same
  counters four times and the fourth would have measured the first three rather than itself.
  `packages.planner-perf-results` is the measurement a recording is taken from; `check.py` compares
  and never writes.
- Two counters are sensitive in ways nothing else in the tree is. `nrOpUpdateValuesCopied` counts
  every value an `//` copies, so one new top-level key in the attrset on the right of
  `korora // { … }` in `lib/atoms.nix` costs one copy per plan and one extra `//` per machine
  costs one per machine: that is why the scope domain is a `domains` member rather than an atom of
  its own, why the privileged-port boundary rides `portRange`, and why a machine record's two
  optional fields are folded into one update. `envs.bytes` grows with the bindings of a `let` that
  is instantiated per placement, so a reading that is asked more than once is one memoised table
  rather than four functions.
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
- That attrset is the union of two, and the split is what a shell being entered pays: the two rows
  naming the guest force its own NixOS evaluation, measured at 8 of the 9 seconds an uncached
  `planner-e2e-env` spends, so they are rendered into `planner-e2e-guest-paths` and the rest into
  `planner-e2e-tool-paths`. `planner-e2e-env --without-guest` prints every row but those two, costs
  1.1 seconds uncached, and says on stderr which two it left unset; the app and the argument-free
  script still print every row. The eval cache misses on every edit, because the flake reference is
  a dirty git tree, so this is the cost of `direnv reload` rather than of a cold checkout.
- `docs/lemmalog/` is the invariant index as facts, and it is a corpus rather than a check: nothing
  fails when a fact goes stale. The corpus is the source and the store `planner-lemmalog` loads it
  into is derived, which is why `$LEMMALOG_MCP_PATH` names a path under `.direnv/` - the engine
  writes its own derived facts and its episodes back into that file. `lemmalog.nix` pins the engine,
  upstream publishing no flake, and the engine holds an object to eight words and sixty characters
  (`src/agent.rs`, `entity_token_problem`), so a claim stays in words and a path rides `governs`,
  `located`, `host_path` or `names`. A path too long for that is split into its parent and a
  `names` row rather than truncated: a truncated repository-rooted path is a token
  `testAFileNamesAPathThatIsNotThere` refuses.
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
- The view is python over the standard library, and its page carries no client-side dependency and
  no script, which is what keeps the toolchain at one formatter, one linter, one type checker and
  one test runner. Its layout is computed where it is served, so two showings of one build are
  byte-equal and a test can assert the picture. Its check is named for the tests,
  `planner-view-tests`, and never for the program: a name that names a program a reader runs must
  not also name a check, which `consumer.testACheckOverAPublishedProgramTakesANameOfItsOwn` holds
  over every `apps.` and `checks.` name the publishing modules carry. `planner-perf` stays one name
  because it is one subject reached two ways and neither half is a program.
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
  ending with a reboot because `/run` is what it empties. What that last phase asserts was
  **inverted** by `unseal-a-value-after-a-reboot`: it used to prove a value was lost and reported,
  and it now proves the machine holds every value again with no command run against it, which is
  the one claim that change exists for. Losing a value is produced by clearing **both** copies
  instead. `systemctl is-active` exits 3 for an inactive unit, so that assertion uses `ssh` rather
  than `ssh_succeed`, and the reboot is issued in the guest rather than by QMP reset.
- That folder's first phase provisions each machine the way an operator would - the identity file
  at `/var/lib/planner/age.key`, `0400` inside a `0700` directory - and it is a **phase** and never
  a snapshot preparation, because a preparation body does not run on a cache hit and the evidence
  would be a replay. Both halves of its age identity are committed, on the snakeoil login key's
  precedent: a throwaway that opens nothing but that folder's test tokens on an offline guest. Its
  `gamma` declares a recipient and receives no value, which is what proves the unsealer follows the
  delivery set and not the placement.
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
- `generated-secret` declares no `sealRecipient` on either machine, deliberately: its subject is
  the external generator's contract and sealing is `secret-delivery`'s. Its table therefore carries
  the two `machine-receives-a-value-unsealed` warnings whatever the backend holds, and the folder
  asserts them by identifier, subject and severity rather than asserting an empty table - which is
  how it went red unnoticed when `unseal-a-value-after-a-reboot` landed that warning. A folder
  asserting `diagnostics == []` is a folder that breaks the next time a warning is added anywhere
  above it.
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
- The user-scope stack is six guest properties, each of which the change needs and none of which a
  plan can state. `systemd-mountfsd` and `systemd-nsresourced` arrive through
  `systemd.additionalUpstreamSystemUnits` and are enabled one `overrideStrategy = "asDropin"`
  `wantedBy = [ "sockets.target" ]` each, because that option only copies a unit; the user
  portabled and its D-Bus activation ride `systemd.additionalUpstreamUserUnits`. systemd is rebuilt
  with `-Dvmlinux-h=provided` off the guest kernel's own BTF: the stock build logs `Not setting up
  BPF subsystem, as functionality has been disabled at compile time` and nsresourced then refuses
  the userns API. polkit is enabled with a rule admitting the account's
  `org.freedesktop.portable1.*` and `io.systemd.mount-file-system.*` actions, which is why
  upstream's own user-scope portable test skips itself unless `pkcheck` is at least 124. The
  account's home is `homeMode = "711"`, for the reason under Realisers: an extraction child holds a
  foreign uid and NixOS' `createHome` default of 0700 refuses it. The account is in
  `nix.settings.trusted-users`, because the run copies each artifact as that login and a remote
  daemon refuses an unsigned path from a login it does not trust. And the throwaway dm-verity pair
  is `tests/e2e/user-scope/verity.nix`, read by the guest for the public half it installs under
  `/etc/verity.d` and by that folder's deployment for the `signing` argument, one file because two
  copies of a pair can disagree.
- `tests/e2e/user-scope/` is where the scope's own refusals are exercised, deployed as an account
  like `tests/e2e/friend-enrollment/` below it: its registry states
  `scope = "user"`, the run is `planner apply --user deployer`, and every step of it - the
  preflight question, the value write, the `nix copy` and the activation - is that login's. Its
  entry declares no unit `user`, no groups, no port and no ownership on its one value, each being
  a planner refusal in that scope, and it reads the value back out of the runtime directory its
  own manager created. Its last phase reboots from inside the guest: lingering brings the manager
  back and the attachment survives, because the pool and the attached unit files are the account's
  own state, while `/run` and the value in it do not. The apply after that reboot writes the value
  again and starts nothing - starting is the attachment's own step and the value step is a
  `try-restart` - and the folder starts the unit the way an operator would.
- `tests/e2e/friend-enrollment/` is the second folder deployed as an account and the only one whose
  machine is reached by a name rather than a number: its `hub` runs the coordination server as a
  planned entry at `10.0.0.10` and its `friend` declares the mesh name as its `address`, so the
  lease that machine does hold appears nowhere in the deployment. Its `disk_gib` has to exceed the
  shared image's own virtual size - `qemu-img resize` refuses a shrink without `--shrink`, which is
  what a figure below it is - and every credential it mints is read into the test process on the
  standard output of one ssh and reaches exactly two argument vectors, both a presenter's own.
  A throwaway node the folder brings up on the hub to present a spent key is a second `tailscaled`
  with a state directory of its own, because the machine's own daemon already holds one membership,
  and it is backgrounded with `& pid=$!` in one command element: a `; ` after the `&` is a shell
  syntax error rather than a launch.

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
- deadnix, through `nix fmt`, deletes an unused formal of a function, including one belonging to a
  stand-in whose whole point is to accept the argument the real builder takes. A stub builder
  therefore takes `...`, or the next `nix fmt` turns it into `called with unexpected argument`.
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
- The four conditions that end an evaluation instead of earning a row are named in one place,
  `docs/authoring.md` under "What ends an evaluation", each with what the interpreter prints and
  the edit: an `abort`, a missing attribute, a function called without an argument its pattern
  requires, and a derivation handed to a module in place of `"${drv}"`. `docs/diagnostics.md` stays
  the short statement of the class and names that section, and `lib/vocabulary.nix` names the
  document and the heading and carries no sentence of either.
- `builtins.functionArgs` answers `{ }` for a lambda with no attribute pattern, so narrowing a
  folder's arguments by `intersectAttrs (functionArgs deployment)` hands nothing at all to a
  deployment written `args: …` - which `tests/e2e/newcomer/deployment/default.nix` is, on purpose,
  so the folder holds no second copy of the template's deployment. `buildsOf` in
  `flake-module.nix` hands such a folder the base argument set instead.
- The external generator's `generate.py` at the pinned revision writes PEP 758 unparenthesized
  `except A, B:`, so it parses under python 3.14 and under nothing older. The pinned nixpkgs'
  `python3` is 3.14, which is the only reason the composition runs at all.
- A deployment hands a module a store path as a string (`"${script}"`) and never the derivation.
  Every reading in `lib/` walks a unit record for line breaks and store paths, and a derivation
  attribute set reaches nixpkgs' own `stdenv` through its inputs, where that walk ends in
  `error: stack overflow; max-call-depth exceeded` pointing at
  `pkgs/stdenv/generic/default.nix` and naming nothing of this tree. Every folder's deployment
  already interpolates; the trap is that a derivation evaluates fine until the walk reaches it.
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
