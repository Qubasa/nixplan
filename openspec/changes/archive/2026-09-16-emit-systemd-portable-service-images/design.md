## Context

See proposal.md — Why. Four constraints shape every decision below.

**The planner realises nothing, by contract and by test.** `lib/default.nix:1-3` and `lib/plan.nix:5-6` state it; `tests/suites/perf.nix:45-53,111-126` asserts zero derivations, every store path a string, and at least one store path recorded. `mkPlan`'s argument set (`lib/default.nix:83-89`) and return set (`:118-122`) are closed, and an `impl` receives exactly six arguments (`lib/resolve.nix:383-389`). The image goes on the far side of the plan.

**A store path is not an evaluation.** The property Disnix establishes, and the one this change keeps, is that nothing downstream of the plan runs an evaluator. A literal store path in the plan does not violate it: copying bytes out of the store needs neither the evaluator nor the daemon, and the plan already carries store paths in `closure` and in every `command`. Bytes in the plan are a different question, and D5 answers it differently from bytes in the store.

**A secret's bytes are unreachable from a module today, and must stay so.** `mkPlacement` hands a generated file to `impl` as `{ __varsFile, present, secrecy, path, content }` where `content = if present && secrecy != "secret" then … else null` (`lib/resolve.nix:365-381`). A module holding a secret holds a path and nothing else, the `secretRef` atom verifies exactly that and deliberately carries no `content` (`lib/atoms.nix:20-24`), and an export declared secret is recorded with `plane = "reference"` (`lib/resolve.nix:492`). So no secret byte can reach `contentHash` today. D5 keeps that true by construction rather than by luck.

**The term is already resolved against systemd.** `notes/clan-portable-services-design.md:2341-2346` (§16.7) names the unit format a **modular service** and records that this resolves the collision with `portablectl`; `:2280-2282` states the host runner consumes rendered units through a `lib.services.configure` binding and never parses systemd units; `:3604` keeps NixOS, macOS launchd and rootless user systemd in charter. A change that makes systemd portable services *the* unit format contradicts all three, which is what D2 and D3 are shaped around.

**Prior art.** `nixpkgs` ships `pkgs.portableService` (`pkgs/build-support/portable-service/default.nix`): it writes `/etc/os-release` with `PORTABLE_ID` and `PORTABLE_PRETTY_NAME` (`:52-60,76`), copies unit derivations into `/etc/systemd/system/` (`:79`), asserts every unit name is prefixed with the image's `pname` (`:90-92`), copies the closure into the image's store (`:99-105`), and emits a squashfs whose `.raw` suffix the portable-service specification mandates (`:108-115`). The gap is upstream of that builder: nothing in today's plan can fill its `units` argument.

## Goals / Non-Goals

**Goals:**

- Make every fact a unit file needs a typed fact of the plan, portable fields and backend-specific fields alike.
- Keep the four invalidation classes distinct (`notes/clan-portable-services-design.md:2304-2309`): an image is closure-class, and a configuration or secret change stays reload-class.
- Make the target — architecture and service manager — a fact the plan carries, in a shape a builder can spend.
- Replace inference with declaration wherever inference cannot be complete: implementation keys, closure roots, unit extensions.

**Non-Goals:**

- The systemd portable service is not promoted to the unit format. It is one binding beside launchd and beside a rootless runner; §16.7 stands and gains an amendment saying so.
- No construct the exclusion table refuses comes back. `lifecycle`, `locality`, `per`/`deploy`, `placement.pick`, member cuts, externals, the collect family and the runtime plane stay excluded (`lib/excluded.nix:19-88`), and `excluded.constructs` gains no key — `testEveryExclusionTableRowIsCovered` (`tests/suites/exclusions.nix:465-505`) hard-asserts that table's size against `fixtures/minimal-typed-edge/README.md`.
- No orchestration. Attaching, generation diffing and rollback belong to the host agent and the orchestrator (`notes/clan-portable-services-design.md:749-755,791-792`). This change produces an image and a reviewable attachment description; it runs neither.
- No extension images, no confext, no sysext — D6 rejects them for this change.
- **Per-microarchitecture instantiation is not built here.** The plan records the facts that make it possible; D8 records why spending them collides with an adopted decision and leaves the collision open rather than pretending it does not exist.

## Decisions

### D1 — The image is a plan *consumer*, and the plan is the only input

The builder is a separate package outside `lib/`, taking a plan and one entry key. It re-evaluates nothing: not the module, not the root, not the deployment. A `mkImage` inside the library was rejected twice over — it would put a derivation inside a value the suite asserts derivation-free, and it would let the image depend on facts the plan does not record, which is exactly the two-readings disagreement `unify-declaration-and-implementation-readings` is removing elsewhere.

Everything else follows: whatever the builder needs has to be *in* the plan, which is why six of the nine decisions below are planner-side.

### D2 — The portable vocabulary is typed, and it is the corpus's vocabulary

`command`, `env`, `after`, `requires`, `user`, `oneShot`, `remainAfterExit`, `schedule`, `timeout`, `stopCommand`, `reloadCommand`. Every one is already written by the design corpus into a committed plan fixture or a module source (`examples/firewall/plan/backup.json:84-93,144-160`, `examples/quiesce-group/plan/participants.json:180-205`, `examples/firewall/modules/postgres/service.nix:89-104`, `examples/firewall/modules/backup/service.nix:88-125`, `examples/firewall/modules/nftables/firewall.nix:197-204`). The code records only `command` (`lib/plan.nix:327`), so the corpus is ahead of the library and this closes the distance rather than opening a front.

Typing is not new machinery. An interface's export atoms are already `{ type, secrecy }` with an unknown key refused and a failing value producing `export-type-mismatch` (`lib/interface.nix:95-141`); the unit vocabulary is the same construction applied to a fixed field set, so `atomRows`' checking is shared rather than duplicated. The atoms the vocabulary needs beyond korora's primitives join `url` and `secretRef` in `lib/atoms.nix`: a unit reference, a duration, a schedule and a user name. A unit reference stays producible only by the module that declared the unit it names — the rule `examples/firewall/interfaces/default.nix:167-171` gives for `korora.unit` — so no module can order itself against a stranger's unit.

Deferred, not rejected: the restart-policy family. A restart policy is a statement about failure over time, the corpus has never needed one, and readiness (`notificationProtocol`, `notes/clan-portable-services-design.md:2215`) is the only liveness concept the design admits. It is additive later; adding it now would be inventing. A backend that has one can carry it as an extension in the meantime, which is exactly what D3 is for.

### D3 — A backend extension is a typed value, not an escape hatch

The temptation is a raw `serviceConfig` passthrough. It is the one thing §16.6's *"compat surface kept minimal on purpose"* (`notes/clan-portable-services-design.md:2338-2340`) forbids, it makes the plan unrenderable by any non-systemd binding, and it makes every future systemd option an unversioned part of this repo's contract. So the extension is typed to the same standard as the portable half:

```nix
# extensions/systemd.nix — a value, imported by whoever uses it
systemdService = planner.unitExtension {
  backend = "systemd";
  name = "systemd-service";
  fields = {
    protectSystem      = { type = korora.enum [ "no" "yes" "full" "strict" ]; };
    ambientCapabilities = { type = korora.listOf korora.string; };
    stateDirectory     = { type = korora.string; };
  };
};
```

An extension is identified by the value a module imported, never by a name resolved at composition time, and `name` is a label for diagnostic output — the same rule `interface` follows (`lib/interface.nix:1-6,36-44`), for the same reason: an extension nobody upstreamed is an extension. `backend` is the one field that is not merely a label, because it is what a mismatch is checked against.

Applying one:

```nix
impl = { target, ... }: {
  units.web = {
    command = "${myapp}/bin/serve";
    env.PORT = "8080";
  }
  // lib.optionalAttrs (target.serviceManager == "systemd") {
    extends = [ { extension = systemdService; values.protectSystem = "strict"; } ];
  };
};
```

`values`' keyset must be a **subset** of the extension's fields, not equal to it: a hardening extension exists to set two of thirty knobs. That differs deliberately from a capability's exports, where the keyset must equal the interface's (`docs/authoring.md:163-166`) — an export set is a contract a consumer reads against, an extension application is a partial override. An unknown key is a row, a mistyped value is a row, and an extension whose `backend` is not the target's `serviceManager` is `unit-extension-backend-mismatch` — so forgetting the conditional is caught rather than silently ignored.

The plan records extensions grouped by backend, so a launchd renderer meeting a systemd extension refuses knowingly instead of dropping fields, and a reviewer reading the plan sees which parts of a unit are portable and which are not.

Rejected: making the backend a property of the deployment rather than the machine. Two machines in one deployment can run different service managers, which is the whole reason `lib.services.configure` exists.

### D4 — The target reaches a module as a seventh implementation argument

`implArgs` is `{ machine, vars, instance, settings, alloc, results }` (`lib/resolve.nix:383-389`). It gains `target = { system = <the reduced platform record>; serviceManager = <name>; }`, drawn from the machine the placement selected. Rejected alternatives: deriving the backend inside the module from `machine` (a name, not a fact — it would put a machine-name-to-backend table in module source, which §28.1's "module source names types and never a deployment object" forbids), and a separate `impl` per backend (it duplicates the portable half, which is the thing worth writing once).

A member that is placed nowhere has no target. Its unplaced entry already carries no machine, no closure and nothing it depends on (`lib/plan.nix:379-419`); consistently, `target` is absent there and a module that dereferences it hits a missing attribute, which is the same trade the library already makes for a refused read (`docs/authoring.md:168-185`).

### D5 — The plan names bytes; it does not carry them, and it never digests what it cannot see

This replaces the earlier "put public content in the plan" answer, which was wrong for two reasons the review surfaced: it puts authored bytes in an artifact whose job is to name things, and it makes a file's identity a digest over assembled content, which is a digest over material the plan does not hold as soon as any of that material is a reference.

A configuration file records `mode`, the units it reloads, and exactly one of:

- **`source`** — a store path holding the rendered file. The realiser copies it out with no evaluator and no daemon. This is the preferred form and the one an author with a `writeText` in their own lexical closure (§16.2's `importApply` discipline, `notes/clan-portable-services-design.md:2230-2246`) gets for free.
- **`render`** — an ordered list whose items are `{ text = "<public literal>" }` or `{ ref = "<path>" }`. The machine concatenates it. This is the form eval-derived content needs, because content computed from a set-valued read exists at evaluation and in no store path: `configData."/srv/borg/.ssh/authorized_keys"` built from `results.clients` (`docs/authoring.md:120-123`) has no derivation to name.

Hashing follows from the disposition rather than being layered on it. A `source` file's identity is its store path — the store already hashed it, and rehashing would be the planner claiming to know bytes it has not read. A `render` list of nothing but `text` items carries `contentHash` over its own bytes, which are public literals the plan already holds. A `render` list containing **any** `ref` carries a structure hash over its fragments and its reference paths, and **no digest over assembled bytes**. Answering the review question directly: no, hashes of secrets are not needed, and none is produced — not today, because a module cannot obtain secret bytes (`lib/resolve.nix:380`), and not after this change, because the record has no field a secret-derived digest could occupy.

What is lost is that a secret rotation no longer moves anything in the plan. That is correct rather than regrettable: it is what `inPlan = "reference"` already means (`lib/plan.nix:123`, `docs/plan.md:143`) — *"the plan is unchanged until the bytes are regenerated"* — and detecting rotation is the agent's job, not the plan's.

`reload` stops being every unit of the entry (`lib/plan.nix:270`) and becomes what the module named. All-units was defensible while a unit was one field; it is not once the plan drives real reload wiring, because it would reload a database on a firewall change.

### D6 — Secrets and configuration reach the units through the host, never through the image

An image carrying configuration content is invalidated by every configuration edit, collapsing §16.4's reload class into the rebuild class (`notes/clan-portable-services-design.md:2304-2309`) — the forty-rebuilds failure recorded at `:1459-1470`. So the image carries units and closure; the host holds configuration files and generated files, and the attachment shows them at the paths the plan already fixes (`/run/vars/<generator>/<file>`, `lib/resolve.nix:377`).

Rejected: a confext or sysext per generation. It is a second image to build, sign, ship and collect, for the content that changes most often, and it buys nothing a bind mount does not when both sides are on one machine. It would also need its own identity, version matching and attach ordering.

This is what makes reproducibility cheap: with no configuration and no secret inside, an image is a function of the units and the declared closure, and both are key inputs.

### D7 — A machine declares `system` and `serviceManager`; the plan records a reduced elaboration

`machineRegistryKeys` is `[ "address" "tags" ]` (`lib/resolve.nix:44-47`) and `platforms` is read, type-checked and used by nothing (`lib/module.nix:341,365-373` — a repo-wide grep finds it in no plan and no resolution path). Both gaps close together.

Tags were rejected as the carrier: a tag is an operator's label with no schema, and `tagged` (`lib/resolve.nix:73`) would place on the wrong architecture when one is misspelled. Per-placement declaration was rejected because the same machine would then be described twice.

The plan records `lib.systems.elaborate`'s output **reduced by allow-list**, and specifically not upstream's own `_withoutFunctions`. Two measurements decide it, both taken against the pinned nixpkgs:

1. **`_withoutFunctions` is not function-free.** It is `removeAttrs final ignoredNames` over a hand-maintained deny-list of four names — `canExecute`, `emulator`, `emulatorAvailable`, `staticEmulatorAvailable` (`nixpkgs:lib/systems/default.nix:57-65,128`) — so it strips only *top-level* functions. Measured on `elaborate "aarch64-linux"`, two functions survive at `parsed.abi.assertions[0].assertion` and `parsed.abi.assertions[1].assertion`, and `builtins.toJSON` of the result raises. A plan is required to serialise (`docs/plan.md:6-9`), so `_withoutFunctions` cannot be a plan value as it stands.
2. **It is 115 attributes wide** (against 120 for the raw record). Putting it in an entry means `androidSdkVersion`, `darwinSdkVersion`, `avx512Support` and a hundred others enter `keyInput` (`lib/plan.nix:334-347`), so an upstream edit to any of them re-keys every entry in the fleet. An allow-list makes a new upstream field a decision instead of a silent re-key.

What upstream's mechanism *is* for is `systems.equals` (`nixpkgs:lib/systems/default.nix:47`), which needs value comparison rather than serialisation; a surviving nested function compares equal there by object identity, which is why the wrinkle is invisible upstream and fatal here. So the projection is the JSON-safe subset a builder actually spends: `system`, `config`, `libc`, `useLLVM`, `linuxArch`, `parsed.cpu`, `parsed.kernel`, `parsed.abi` minus its `assertions`, and the codegen group `gcc` — `abi`, `arch`, `cmodel`, `cpu`, `float`, `float-abi`, `fpu`, `long-double-format`, `mode`, `strict-align`, `thumb`, `tune`, the fields cc-wrapper and gcc's own build read (`nixpkgs:pkgs/build-support/cc-wrapper/default.nix:315-367`, `nixpkgs:pkgs/development/compilers/gcc/common/platform-flags.nix:8-45`) — whenever the elaboration carries any of them.

The `is*` predicates are **excluded**, and that is the second half of the same argument as `_withoutFunctions`' width. All seventy-five are `mapAttrs (n: v: v final.parsed) inspect.predicates` (`nixpkgs:lib/systems/default.nix:442`): each is a pure function of `parsed`, which the record already carries, so recording them would put seventy-five derived booleans in every entry, in every `keyInput`, and in every plan diff, without a consumer learning anything it could not compute. The projection is what a cross build spends and nothing derivable from it; a consumer wanting the whole family elaborates the record's own `system` string. What replaces the deleted "the predicate list is exactly the pinned elaboration's" guard is a live cross-check in the other direction: every `gcc` field the pinned platform set sets on any exposed double must be named by `gccNames`, so an upstream codegen field is a decision here rather than a silent omission from every record.

`functionNames` is nonetheless useful as a **cross-check rather than as the filter**: upstream keeps it exactly in sync with the elaborated record's top-level function attributes, guarded by `test_equals_functionNames_in_sync` (`nixpkgs:lib/tests/systems.nix:301-313`). Asserting that the projection's own field set contains nothing named there, and that it serialises, catches a bad allow-list edit on this side without adopting upstream's deny-list as the mechanism.

This makes `lib.systems` a dependency of the library, which until now imports korora only. It is pure Nix producing no derivation, and it is memoised per distinct `system` string, so the cost scales with architectures in the fleet rather than machines. `platforms` becomes a containment check per placement, and the row is a refusal that still emits the entry so an operator sees what they asked for.

Adding keys to `machineRegistryKeys` widens `machineRecords` (`:88-91`), therefore `machineKey` (`lib/plan.nix:31`), therefore every `dependsOn` hash. Intended: a machine that changed architecture must re-key what runs on it.

### D8 — Reproducibility outranks tuning: the plan carries the microarchitecture and nothing spends it

Recording the codegen group makes "build every module optimised for its target" *expressible*. A stated project priority makes it unwanted by default: every service pins its own inputs so that a nixpkgs move cannot change what a service runs, and the bytes a service runs are the bytes its author validated.

That priority is already the adopted design rather than a new requirement. §16.2 (`notes/clan-portable-services-design.md:2230-2263`) removes `pkgs` as a module argument entirely — a module's binaries bind by lexical closure through `importApply`, pinned by the author's repo — and `notes/unaddressed.md:583-587` states the consequence in one line: *"every module ships its own pin and nothing depends on the consumer's nixpkgs."* A store path in a `command` is therefore chosen before any machine is known, and that is the property, not a limitation to work around.

Per-target optimisation requires instantiating an author's package set against a `hostPlatform` the author did not choose. Under the priority above, each route fails for a different reason:

1. **A module exposes a package parameter.** Survives, opt-in and visible: the substitution is one named knob at one call site, and a deployment that does not use it keeps the author's bytes exactly. Its own cost is §24.2's (`:3253-3266`): the override swaps the top-level derivation while the transitive closure stays on the author's pin, so it tunes the top and nothing below it. Default off.
2. **Re-instantiate the author's closure per target.** Rejected. Not merely because it abandons §16.2's co-versioning, but because there is nowhere to do it: the realiser has no evaluator (*"Never evaluates Nix"*, `:791-792`), and doing it at evaluation time means the author's `importApply` argument set becomes a function of the target — `pkgs`-as-argument returning under another name, with §24.2's *"author-side co-versioning and a fleet-wide injection point cannot coexist"* as the verdict.
3. **A fleet-wide microarchitecture baseline.** Rejected as a default, and this reverses an earlier recommendation in this document's own review. A baseline still instantiates every author's pin against an overridden `hostPlatform`, so the bytes differ from the ones the author validated — and, decisively, they differ from every published narinfo, so nothing substitutes. The fleet rebuilds every authoring repo's closure locally, which multiplies the build surface a nixpkgs move can break: the exact failure the priority exists to prevent, paid for a single-digit-percent gain outside codecs, crypto and numeric kernels.

So this change carries the facts and spends none of them. What the facts buy immediately is verification rather than tuning: `lib.systems.architectures.inferiors` gives the containment relation (measured: `inferiors.znver5` lists `x86-64-v3`, `x86-64-v2`, `x86-64` among fifteen), so *if* a baseline is ever adopted, "every machine supports it" becomes a containment check with a diagnostic row instead of an unverifiable assumption that surfaces as an illegal instruction on the one old machine in the rack.

### D9 — The closure is declared; the string scan is demoted to a verifier

`closure = util.uniqueStrings (util.storePathsDeep units ++ util.storePathsDeep merged.env)` (`lib/plan.nix:328`), where `units` is the already-reduced `{ command }` set and the recogniser is `split "(/nix/store/[0-9a-z]{32}-[0-9a-zA-Z?=_.+-]+)"` (`lib/util.nix:79`). Three defects, and widening the scan fixes only the first:

1. **Incomplete.** A store path named only by a configuration file, an export value or a vars path is absent. Harmless while the closure was documentation; a broken image once it is the population list.
2. **Unsound.** The hash class `[0-9a-z]{32}` admits `e`, `o`, `t` and `u`, which Nix's base-32 alphabet (`0123456789abcdfghijklmnpqrsvwxyz`) does not contain, so 32 characters of a package *name* can be recognised as a hash.
3. **Not a guarantee in principle.** A path assembled at runtime, one that arrives through a `configData` `ref`, or one a module holds in a shape the scan does not walk, is invisible to any scanner. Inference cannot be complete, so it must not be the source of truth.

So the module declares its closure roots, and the scan becomes the contradiction check: a store path mentioned anywhere in the entry and absent from the declared roots is `closure-path-undeclared`; a declared root mentioned nowhere is a warning, because a root that nothing names is either dead weight or a runtime-assembled path worth writing down. The declaration is what the image is populated from; the scan is what stops the declaration from drifting.

The store directory stops being hardcoded: `mkPlan` takes `storeDir ? builtins.storeDir`. `builtins.storeDir` is pure, needs no impure evaluation, and is the actual configured store rather than an assumption — and making it an argument is what lets one deployment plan for a machine whose store lives elsewhere. Both the recogniser and the realiser read it, so an image built for a machine with a relocated store populates the right directory.

Rejected: a typed `storePath` atom as the *only* way to name a package. It would be the honest form, and it would rewrite every command in every module and every fixture in the corpus. Declaration-plus-verification gets the same guarantee for the closure without touching how a command is written.

### D10 — The unit name prefix is the entry, and the collision is checked

`pkgs.portableService` asserts every unit name starts with the image's `pname` (`nixpkgs:pkgs/build-support/portable-service/default.nix:90-92`), and the design's only unit-namespacing mechanism is §16.1's `<parent>-<child>` sub-service naming, which `examples/instance-as-group/README.md:487-490` records as **unchecked**: *"One module deployed four times collides with itself on any host that takes two of its clients, and the `<instance>-<service>` prefix is the only thing between them. Nothing in the folder checks it."*

The prefix is the entry's instance and service, which is exactly what makes an entry key unique on a machine (`lib/plan.nix:82-87`), so the collision cannot occur by construction — and the builder asserts it rather than trusting it.

### D11 — The profile is stated, and a denied access is a build failure

Choosing a confinement profile on the author's behalf is the failure the notes record for `Conflicts=`/`After=` (`examples/firewall/README.md:465`): a plausible pair of directives that stops the service and never starts it again. So the profile is named, the attachment description records it beside the units and the host paths shown, and an entry needing an access the named profile denies fails the build naming both — never a silent widening.

Dynamic users stay out. The one place the notes make real systemd directives load-bearing is the probe executor (`User=` plus `DynamicUser=` plus `JoinsNamespaceOf=`, `notes/clan-portable-services-design.md:2806-2808`), probes are excluded (`lib/excluded.nix:72-75`), and a dynamic identity has no answer for the uid-inside-versus-outside problem the corpus already records as unsolved (`examples/instance-as-group/README.md:726-729`). `user` in the portable vocabulary is a name; a backend with more can extend it under D3.

### D12 — §16.7 gains an amendment rather than being contradicted

One paragraph in §16.7 recording that a systemd portable-service **image** is a binding of the unit vocabulary — the systemd sibling of the launchd `lib.services.configure` path (`notes/clan-portable-services-design.md:2280-2282`) — and that `planner/unit-vocabulary` plus its typed extensions is what bindings render from. Without it this change reads as a reversal; with it, the collision note keeps its meaning and gains a second binding.

### D13 — The pin is a recorded fact, not a resolution the planner performs; `mana` is the resolver

Per-service pinning is only a guarantee if a reader can see which pin a service is on. Today nothing in the plan says: `closure` is a list of store paths, so a path moving tells you *something* changed and never *which pin* moved, and the mechanism that binds those paths — an author's `importApply` scope — is by design *"unreachable from outside"* (`notes/clan-portable-services-design.md:3259`). An image whose bytes must be stable is built from exactly that closure, so provenance belongs beside the closure declaration rather than in a separate capability.

**Earlier drafts of this decision built a dependency manager, and one already exists.** `~/Projects/mana` is a pure-Nix locker and injector whose surface is item-for-item what the previous draft was inventing: `dependencies.<name>.url` is the pin registry, `shares = [ "nixpkgs" ]` propagates one version to the whole transitive tree (`README.md:136-162`), `pins = [ "nixpkgs" ]` protects a library's own version from a consumer's `shares` (`:164-184`), narHash deduplication is `dedup :: { narHash -> lockKey }` (`nix/lib.nix:194-196`), the precedence order is `resolveNode`'s documented two-pass — *"a parent declaring `shares` needs its own locked version before recursing"* (`:157-167`) — and the injection step is `f (intersectAttrs (functionArgs f) scope)` (`nix/importer.nix:182`), which is §16.2's lexical-closure authoring model implemented generically rather than per-repo. A second resolver in the repository root would be a resolver that can *disagree* with that one, and the disagreement would surface as an image whose bytes don't match its recorded pin.

So the resolution algebra is deleted from this change. The planner declares no registry, holds no default, resolves no precedence and knows no `shares`. What it does is what only it can do:

1. **Record.** A placed entry carries `pin = { key, locked }` — the lock key the resolver assigned and the locked record it resolved to. Mana's key is a path through the dependency graph (`""`, `/nixpkgs`, `/treefmt-nix/nixpkgs`, `nix/lib.nix:49`) and its locked record is `{ type, owner, repo, rev, narHash }` (`lock.json:15-21`), so both are literal strings and a plan stays JSON-safe and derivation-free.
2. **Refuse what is not pinned.** A locked record with no `rev` or no `narHash` is an error row naming the module and the missing field. Mana's lock always carries both, so this guards hand-written and hand-edited data rather than the resolver — cheap, and it is the one property the whole priority rests on.
3. **Key on it.** The effective pin is a `keyInput`, so a re-pin re-keys exactly the entries whose bytes moved.
4. **Not verify.** The planner reads no lockfile and instantiates nothing, so it cannot confirm that the store paths in a `command` came from the pin the entry names. `SHALL record`, never `SHALL verify`.

**And sharing stops needing a vocabulary.** The previous draft recorded `source ∈ module | default | instance` so a reader could tell a fleet pin from an author's pin. With a real resolver the lock key already says it: two entries sharing a nixpkgs record the *same* key, because that is what dedup means, and two on different nixpkgs record different keys. Key equality is the answer, so there is no provenance label to invent, no displacement warning to emit, and no one-row-versus-N-rows question to get wrong — `shares` is one visible line in one `mana.nix`, which is where an override belongs.

One consequence to name: a module should not hand-write its own pin, because a hand-written pin drifts from the lock silently and the planner cannot catch it (point 4). The correct source is the resolver, and mana was three lines from providing it. As landed (task 8.5), the shape is one line smaller than the draft above assumed: the node's `pin` is built where its source is, above the `fetchTree` call, and `source = fetchTree pin.locked` then reads that same record — so `locked` cannot drift from the bytes that were fetched, and the entrypoint invocation only has to widen its scope with it. A module's pin therefore arrives the way its packages do.

What none of this attempts: injecting a fleet-wide library version *underneath* an author's pin while leaving that pin in place. §24.2 rates that structurally impossible (`:3253-3266`) — the top-level override does not reach the transitive closure — and mana agrees by construction, since `shares` re-locks the subtree rather than swapping a top derivation. The honest alternatives §24.2 names are a CI closure scan wired into the bytes-available gate, the shared-pin policy, and the fork-and-repin runbook. The scan is outside this change; recording the pin is what makes it able to name a stale repo at all. The pin-freshness item §16.2 promised is still untracked (`:3261`: *"no bead exists; it is untracked"*) and belongs with that work.

### D14 — Order of work

Types and the extension constructor first, because the vocabulary depends on them; then the vocabulary and per-unit `env`; then the implementation allow-list, which is only enforceable once there is a vocabulary to enforce; then the configuration-file dispositions; then `system`, `serviceManager` and the platform record, which `target` depends on; then the declared closure and the store-path grammar; then one fixture regeneration and one budget re-pin for all of it; then the builder; then the corpus amendment. One regeneration at the end, not eight: every entry re-keys.

## Risks / Trade-offs

- **Every entry in the golden fixture re-keys** (vocabulary, per-unit env, extensions, platform record and declared closure are all key inputs) → regenerated once with `python3 tests/regenerate.py` (`docs/plan.md:194-198`), and `tests/python/test_golden.py` compares field by field so a wrong regeneration reports paths rather than passing.
- **Declared closure roots are a new authoring obligation** → the verifier makes forgetting one a row rather than a broken image, and the row names the path and the string that mentions it, so the fix is mechanical.
- **`lib.systems` becomes a library dependency** → pure, derivation-free, memoised per architecture, and reduced by allow-list so upstream churn cannot silently enter a key. It is also already in the pinned nixpkgs the flake carries, so nothing new is fetched.
- **The typed extension surface is a maintenance surface**: every systemd field somebody wants must be declared with a type → deliberate. It is the price of refusing a passthrough, and an extension lives in whichever repo needs it rather than in this library, exactly as an interface does.
- **The implementation allow-list is breaking for any module writing outside the vocabulary** → breaking on purpose, and loudly: an unrecognised key was already being discarded, so the change converts a silent wrong plan into a row. The vocabulary is a superset of what every module in this repo writes today (`command`, `env`).
- **`system` and `serviceManager` become mandatory on a machine** → a registry omitting either gets a row naming the machine and the file, and the plan is still emitted, so a deployment mid-migration is diagnosable rather than unevaluable.
- **The perf budgets move** (`perf/budgets.json`): a typed vocabulary, extension checking, platform elaboration and a whole-entry scan all cost allocations → measured and re-pinned in both directions with fresh provenance, the precedent being `unify-declaration-and-implementation-readings`' D4. A budget is not waived to make a change pass.
- **A `render` list moves assembly to the machine**, so a file's final bytes exist nowhere at plan time → intended by D5, and the structure hash still moves when the recipe changes. The cost is that a plan diff cannot show the assembled file, only its recipe.
- **systemd's portable-service interface could change** → the builder is one file wrapping `pkgs.portableService`, which is where nixpkgs already absorbs that churn, and the plan-side vocabulary is deliberately not systemd-shaped, so a `portablectl` change cannot reach it.
- **`mana` becomes the resolver this change assumes** → the alternative is a second resolver inside the repository root, which is strictly worse (two answers to "which nixpkgs", one of them wrong). The coupling is deliberately thin: the planner consumes `{ key, locked }` as literal strings and never reads `lock.json`, so a different resolver satisfies the same requirement by producing the same two fields. Real exposure is that mana is pre-1.0 and its fetcher is `fetchTree` (`~/Projects/mana/README.md:61`, experimental), and that task 8.5 is a change in a repository outside this one — so it is ordered first, and the planner-side row for a locked record missing `rev` or `narHash` is what catches a resolver regression at plan time rather than at build time.

## Migration Plan

1. Land task 8.5 in `mana` first, then the planner side behind no flag, in D14's order. It landed in the other order, which cost nothing: the planner records the pin it is handed and reads no lockfile, so neither half needs the other to evaluate. The mana side is a commit in `~/Projects/mana`, not in this repository — it is uncommitted there and has to be committed and pushed separately from this change.
2. Regenerate `fixtures/minimal-typed-edge/plan/backup.json` once and re-pin `perf/budgets.json` to the measurement.
3. Update `docs/` — authoring surface, plan artifact, diagnostics row list, and the exported-symbol table for `unitExtension` and `storeDir`.
4. Add the builder as a separate package with its own check, building the worked example's entries into images.
5. Amend `notes/clan-portable-services-design.md` §16.7.

There is no rollback step for the planner side: a plan is a build artifact, and reverting the commits reverts it. The builder is additive and can be removed without touching the library.

## Open Questions

- Which confinement profile the worked example's entries attach under. D11 requires it be stated rather than inferred; the answer per entry changes no spec, no decision and no task.
- Whether a `schedule` renders as a timer unit inside the image or as a host-side timer starting an attached service. Both satisfy the vocabulary; the image-internal form is assumed in the spec's scheduled-unit scenario and the builder can revisit it without a planner change.
- Which of D8's three routes to per-microarchitecture instantiation to take. Deferrable by construction: this change records the facts and builds nothing that spends them, so the answer changes no spec here.
