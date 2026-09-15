## Why

`tests/unit/counterexamples.nix`, `tests/counterexamples/probes.nix` and `cli/counterexample_test.py`
hold 49 counterexamples. Each one asserts a sentence this tree already states about itself, and 48 of
them are red: the claim is false today. They were found by reading the recorded invariants against the
code rather than by fuzzing, so every one is an ordinary declaration a reader could write this
afternoon. Three of the breaks are silent and load-bearing - a rotated secret that no reader reopens,
a unit file two entries both publish, a plaintext secret in the plan - and the rest turn a row a
reader is owed into either an evaluation that ends or a table nobody prints.

**Evaluation is not total.** `lib/default.nix:5-8` states "Every check returns a row instead of
raising". `lib/module.nix:1431` builds `impl-missing` for a declaration whose `impl` is not a function
and `:1457` records that value anyway (`impl = given.impl or null`), so `lib/resolve.nix:1445` calls
it: `attempt to call something which is not a function but a set`. The guard beside it is defeated by
operand order: `implShape` at `lib/resolve.nix:1452-1457` catches the raise, and `:1461` then tests
`impl == null` **first**, re-forcing the application outside the guard that had just caught it, so
`module-raised` is produced and thrown away. `:1564` re-forces it a third time for the provider's
exports. Eleven more declarations of the wrong kind reach an index or a coercion the same way: a
recipe fragment, a root's `services`, a settings knob holding a function, `mkPlan`'s own four
arguments, `varsState`, an export shaped like a file reference, and the realisation statement's
`realiser`, `profile` and `mode`. Two conditions are not guardable at all: `builtins.tryEval
(({a}: a) { a = 1; b = 2; })` propagates, verified on nix 2.34.8, so a module writing `impl = {
settings }: …` without `...` ends `mkPlan` and a module reading `results.<slot>` for a slot nobody
wired does the same.

**A key names two things.** `image/read.nix:208,243` derive a unit file name as
`<instance>-<service>-<unit>.service`; `operator/read.nix:438-455` compares only `<instance>-<service>`
per artifact, which cannot collide inside one machine. Instance `a`, member `b` with unit `c-main` and
member `b-c` with unit `main` therefore both publish `a-b-c-main.service` on one machine, under both
realisers, with no row. `lib/plan.nix:1253` merges machine records, value entries and service entries
with `//`, so an instance called `machine` with a member named after a real machine silently replaces
that machine's record and every `dependsOn` edge onto it dangles. The name denylist admits the empty
string, and an entry named with it vanishes from `manifest.json` and from the secrets projection with
no row anywhere.

**A no-op edit re-keys.** `lib/plan.nix:120-122` prunes the three ownership fields from a value's key
by whether the declaration **wrote** them, not by whether they differ from the default they resolved
to. Writing `owner = "root"; group = "root"; mode = "0400"` - the defaults - re-keys a value whose
record is byte-identical, which the provenance driver reads as a disagreement and which regenerates a
secret. `:464` does the same for a configuration file's ownership, where the consequence is a new
image digest and a stop, detach and attach of a running unit for an edit that changes no byte.

**Secrecy and readability have holes at three of their four sites.** No check compares a secret
export's secrecy against the secrecy of the generated file backing it, so a file that omitted
`secrecy` reaches an interface that calls the value secret and its bytes travel in the plan, in a
unit's environment and in a content hash, with `applicable = true`. `util.admits` is asked about a
consumer's declared reads and about a configuration file, and never about the entry's **own** value:
a unit that cannot open the secret its own generator produced is a row under one realiser's
confinement profile and silence everywhere else. `undeployedRows` (`lib/plan.nix:530-571`) scans an
entry's mention sites for its own generators' paths with the predicate `!file.deploy`, so a value that
is deployed but delivered elsewhere - reached through a public export carrying the file's `path` - is
bound on a machine that does not hold it, which is the `226/NAMESPACE` failure the `deploy = false`
row exists to prevent.

**A realiser is handed values it cannot carry.** `lib/module.nix:1328` copies a configuration file's
`source` verbatim (`util.pickAttrs dispositions file`), held to neither kind nor store, so
`/etc/ssl/private/host.key` is bound into a unit as that entry's configuration. A configuration file's
host path passes a grammar that admits `:`, which separates systemd's bind list, and `%`, which
systemd expands as a specifier. A unit's attribute name and an `env` key are outside the line-break
scan the values go through, and `image/read.nix` renders `Environment="<k>=<v>"` escaping the key with
nothing. `image/read.nix:556-587` takes the version digest over name, units, closure, `storeDir`,
service manager, host paths and platform, and not over the confinement profile, so `trusted` and
`strict` are one digest, one image name, `nothing changed` on every apply and `current` in the report.

**The command drops a rotation and accepts a path outside the build.** `cli/apply.py:207-210` reads a
resolved read's providers from `slot["values"]`, the single-valued shape only, while
`cli/order.py:315-320` reads both: a `reach = "all"` read therefore orders the apply and never
restarts its consumer, so after a rotation every set-valued reader keeps the old bytes open.
`cli/order.py:313-314` returns no providers for a read that is not a record, before the `delivered`
gate that refuses the other unrecognised shapes, so such a consumer is activated before its provider
with no refusal. `cli/manifest.py:388-393` resolves a stated artifact path with `(root / stated)` and
no containment check, so `/etc` or a path above the build is copied to the machine and activated.

## What Changes

- **Totality is held for every value a declaration wrote, and the class the interpreter does not let a
  caller catch is named rather than claimed.** Twelve readings check the kind of what they were handed
  before they index or coerce it, the `impl` guard stops re-forcing its own subject, and a
  non-function `impl` is recorded as none. The two formals conditions and a missing attribute of a
  module's own expression stay uncatchable - Nix exposes no ellipsis and no way to catch either - so
  the property is stated as "every value a declaration wrote", and `diagnostics` and `applicable`
  become total even where one entry's own record raises, so the table that explains the mistake is
  always printable.
- **A plan key, an artifact name and a unit file name each name one thing.** A key claimed twice is an
  error row and an inapplicable deployment rather than a silent `//`; the name grammar refuses the
  empty string and any name carrying a line break or a control character; and the shared realiser
  reading refuses two entries of one machine whose derived unit file names collide, naming both
  entries and the file.
- **A field enters a key only where its value differs from the default.** Stating a default is a
  no-op, for a generated file's ownership and for a configuration file's, and a plan written before
  those fields existed still keys as it did. **BREAKING** for a deployment that states a default
  today: those values re-key once and are regenerated once.
- **The secrecy lattice and the readability predicate are asked at every site that holds the facts.** A
  secret export backed by a public file is an error and publishes nothing; an entry's own units are
  held to `util.admits` against their own value; and the mention scan asks whether the machine
  receives the value rather than whether the value is deployed.
- **A realiser is handed nothing it cannot carry.** A configuration file's `source` is a store path or
  the file has no bytes; a host path carries neither `:` nor `%`; a unit name and an `env` name are
  held to the same rule their values are, with an `env` key held to the POSIX environment name
  grammar; flakelet's unit rule stops letting `.` match a newline; and the image's version digest
  carries the confinement profile. **BREAKING**: every image re-keys once, which is one stop, detach
  and attach per entry.
- **An interface's identity stays nominal and the structural check moves to the wire.** korora's
  `struct` exposes only a name, a verifier and an override (`types.nix:485-489`), so a fingerprint
  cannot see two different field sets under one claimed `id`. Each delivered read is verified against
  the **consuming** interface's own export type instead, which catches the diamond whatever the two
  interfaces are called. **BREAKING** for a deployment whose provider publishes a value its consumer's
  own declaration refuses: that deployment becomes inapplicable, which is the point.
- **The command rotates every reader it ordered, refuses every read shape it cannot read, and copies
  nothing from outside the build.** Plus five smaller refusals it owes an operator: an endpoint answer
  that is not a status, absence claimed by anything but the endpoint, an image compared by anything
  but its own identity, a failure named by the machine rather than by an ssh option, and every
  undeclared file inside a value's directory.
- **Attribution decides nothing.** Identity and conflict rows are reached from the modules that
  imported an interface, never from the `interfaces` argument, so listing an interface cannot flip
  `applicable`.
- **Six diagnostics rules are held to their own text**: `oneLine` covers the subject and strips `\r`
  and `\t`; the subject grammar accepts every name the key grammar admits; two facts about two files
  sharing a basename stay two rows; a severity outside the stated domain is an error and says so; and
  a fold's refusal travels as a marker rather than as an in-band `refused` key a successful fold can
  carry.

## Capabilities

### New Capabilities

<!-- none: every rule below belongs to a capability this repository already carries -->

### Modified Capabilities

- `planner/diagnostics`: totality is required of every value a declaration wrote, the uncatchable
  class is named, the table is printable whatever one entry's record does, and five row-construction
  rules are held to their own text.
- `planner/plan-artifact`: a plan key names one record, a name entering a key is keyable, and a field
  enters a key only where it differs from its default.
- `planner/typed-edge`: a delivered read is verified against the consuming interface's own type, and
  attribution decides no row and no applicability.
- `planner/interface-identity`: a claimed identity is nominal and name-deep, and says so.
- `planner/interface-fold`: a fold's refusal is a marker the fold's own successful result cannot
  imitate.
- `planner/secret-delivery`: a secret export is backed by a secret file, an entry's own value is
  readable by its own units, and a value's path is named only on a machine that receives it.
- `planner/unit-vocabulary`: a configuration file's source is a store object, its host path is a word
  a unit can bind, and a unit name and an environment name are held to the rule their values are.
- `realiser/portable-service-image`: the version digest carries the confinement profile, and an
  environment name is escaped the way its value is.
- `realiser/flakelet-artifact`: the restated unit rule refuses a newline the way flakelet does.
- `realiser/secrets-configuration`: every word the rendered step escapes is a word the reading checked
  first, ownership included.
- `operator/deployment-build`: two entries of one machine may not share a derived unit file name, and
  every field the reading indexes is read for its kind.
- `operator/apply-command`: a set-valued read rotates its consumer, an unrecognised read shape is a
  refusal, an artifact path is inside the build, and a value source is measured to its leaves.
- `operator/machine-report`: absence is the endpoint's own answer and an image is compared by its own
  identity.
- `tooling/test-layers`: the tree holds three kinds of test, and an invariant is held by a
  counterexample that asserts the claim rather than the behaviour.

## Impact

- `lib/module.nix`: `impl` recorded only where it is a function; a recipe fragment, a settings knob
  and a configuration file's `source` read for kind; the unit and environment name rules; the host
  path grammar.
- `lib/resolve.nix`: the `impl` guard's operand order at `:1461` and `:1564`; the export reference
  check; `varsState` read for kind.
- `lib/compose.nix`: a root's `services` read for kind before it is indexed.
- `lib/plan.nix`: `withoutUnstated` becomes a default comparison; the `//` merge at `:1253` gains its
  collision row; `undeployedRows` widens from the entry's own undeployed values to every value the
  machine does not receive; the nested host path row; the readability question about the entry's own
  value.
- `lib/diagnostics.nix`: `oneLine` over the subject and over `\r` and `\t`; the subject grammar; the
  dedup order against the basename repair; the severity domain; the fold refusal marker.
- `lib/interface.nix`: identity rows reached from the importing modules; the nominal depth stated.
- `image/read.nix`: the profile in `versionFor`; the environment key rendered as its value is.
- `flakelet/read.nix`: the anchored unit rule.
- `secrets/read.nix`: ownership words checked before the step escapes them.
- `operator/read.nix`: the unit file name index per machine; the statement and plan fields read for
  kind.
- `cli/apply.py`, `cli/order.py`, `cli/manifest.py`, `cli/report.py`, `cli/remote.py`, `cli/values.py`:
  the eight refusals and the rotation.
- `tests/unit/counterexamples.nix`, `tests/counterexamples/probes.nix`,
  `cli/counterexample_test.py`: 47 tests turn green; the two asserting the withdrawn totality claim are
  rewritten to assert the narrowed one.
- `tests/unit/coverage.nix`: this change's spec files move from `excused` to `accountable`, and
  `cli/counterexample_test.py` joins the counted test files the way `perf/check_test.py` does.
- `docs/diagnostics.md`, `docs/tooling.md`, `README.md`, `CLAUDE.md`: the new identifiers, the suite
  figures, and the narrowed totality sentence.
- `fixtures/minimal-typed-edge/plan/*`: unchanged. The fixture states no ownership default - its one
  `configData` mode is `0600`, which is not the default and is in the key either way - and every
  other rule here turns a silence into a row or an evaluation into a table, neither of which the
  fixture holds today.
- `perf/budgets.json`: re-measured for the widened mention scan and the added verify pass.
