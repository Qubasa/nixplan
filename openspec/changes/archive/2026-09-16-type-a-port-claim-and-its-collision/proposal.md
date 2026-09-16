## Why

`entry-port-claimed-twice` is the one guarantee the library makes about a port, and it is skipped
for whole classes of input because the value it compares is never typed.

- **The number is unvalidated and compared as JSON.** `readClaims` checks that the key exists and
  nothing else: `util.optional (!(claim ? fixed))` is the only row and
  `ports = util.filterAttrs (_: claim: claim ? fixed) ports` is the only filter
  (`lib/module.nix:344-355`). The collision index keys a claim as
  `"${if isString proto then proto else "unstated"}/${builtins.toJSON fixed}"` (`lib/plan.nix:708`),
  and `builtins.toJSON "5432"` is `"\"5432\""` where `builtins.toJSON 5432` is `"5432"`, so
  `fixed = "5432"` and `fixed = 5432` on one machine are two claims that do not collide and two
  servers bind one port with no row. It is reachable rather than theoretical: a claim is written
  `fixed = settings.port` (`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:26-30`)
  and a settings knob carries no type at all - `values = defaults // applied // fixed`
  (`lib/compose.nix:108`) - so whatever a deployment writes at `settings.own.port`
  (`tests/e2e/shared-postgres/deployment/instances.nix:61`) is what the claim is. `lib/atoms.nix`
  types `unitRef`, `duration`, `schedule`, `restartPolicy`, `fileMode`, `userName` and `groupName`;
  the port claim is the one scalar in the vocabulary with no atom.
- **The protocol is optional and unvalidated.** `claimKeys = [ "proto" "count" "fixed" ]`
  (`lib/module.nix:115-119`), and `lib/plan.nix:708` is the only site in the tree that reads
  `proto`. So `"tcp"`, `"TCP"` and an omitted `proto` are three claims that do not collide on one
  number, and the omitted one keys as `unstated`, which collides with nothing - the opposite of the
  safe reading. `docs/diagnostics.md:244` states the rule as though the protocol were checked.
- **`count` is vocabulary nothing reads.** It is in `claimKeys` (`lib/module.nix:117`) and appears
  nowhere else in `lib/`: `alloc` is `mapAttrs (_: claim: claim.fixed)` (`lib/resolve.nix:941-943`),
  the index compares `<proto>/<fixed>` (`lib/plan.nix:701-709`), and the comment there says "`count`
  is recorded and not expanded" (`lib/plan.nix:699-700`) when it is not recorded either.
  `docs/authoring.md:142` publishes it, and twelve claim sites of this tree write it. `{ fixed = 8000;
  count = 4; }`, the obvious spelling for a worker pool, is protected on 8000 and unprotected on
  8001 to 8003.
- **A claim carries no bind address, and the row's own evidence asserts the address away.** The
  detection predicate is the machine, the protocol string and `toJSON fixed`, and the evidence reads
  "one machine carries one listener per protocol and port" (`lib/plan.nix:652`). Two entries binding
  one number on two genuinely different addresses are therefore an error that makes the deployment
  inapplicable, which is how a fleet runs two databases on one host. There is no namespacing escape:
  no profile carries `PrivateNetwork` (`image/read.nix:55-69`) and no directive table names it
  (`image/read.nix:76-94`), so every unit shares the host network namespace.

## What Changes

- **A port claim's number is a port.** An integer in 1 to 65535. A value that is not is
  `port-claim-not-a-port` and the claim is not recorded, the way a unit field failing its type is
  dropped rather than coerced (`unit-field-type-mismatch`). The index compares the number itself, so
  the `builtins.toJSON` in `lib/plan.nix:708` goes.
- **A port claim's protocol is one of a named domain, and an unstated protocol collides with every
  protocol in it.** `protocols` joins `restartPolicies` and `consumerCardinalities` in
  `lib/atoms.nix` as a named domain a row can quote. `proto` stays optional, because that is the
  reading that is safe by default and costs no declaration that exists; a protocol outside the
  domain is `port-claim-protocol-unknown` and the claim is then read as though it stated none.
- **A port claim may state the address it binds.** `address` joins the claim vocabulary. Its
  absence is the wildcard, so no declaration that exists moves. Two claims of one number on one
  machine collide when their protocols overlap and either binds the wildcard or both bind the same
  address, and do not collide when they bind two different addresses. The address is not recorded in
  `alloc` and does not enter the entry key.
- **`count` is removed from the vocabulary.** It records nothing, expands into nothing and protects
  nothing. Expanding it instead would change what `alloc` records, which is an input to every entry
  key (`lib/plan.nix:802`), and would re-key every entry that writes the word for a number the plan
  never carried. Removing it makes a module writing it earn `declaration-unknown-key`
  (`lib/module.nix:164-191`), which is one word deleted per site; every site in this tree is named
  below.
- **No allocation and no search.** The planner still chooses no port and no address. A claim is
  still a fact the deployment states, and `dynamicPort` stays the excluded construct it is
  (`lib/excluded.nix:32-35`).

## Capabilities

### New Capabilities

<!-- none: the claim vocabulary and the collision row both belong to capabilities that exist -->

### Modified Capabilities

- `planner/plan-artifact`: a port claim is a typed record of a number, a protocol and an address;
  what an entry records for it stays the number alone, so a claim that adopts the new field moves no
  key.
- `planner/diagnostics`: the three refusals a claim can earn, and the amendment to the port half of
  the host-resource collision rule - the protocol domain, the unstated protocol that collides with
  every protocol, and the address that makes two listeners on one number two listeners.

## Impact

- `lib/atoms.nix`: a `port` atom, a `protocol` atom over a named `protocols` domain published as
  `domains.protocol` beside `domains.restartPolicy` (`lib/atoms.nix:15-19,26-29,65-75`), and a
  `bindAddress` atom.
- `lib/module.nix`: `claimKeys` becomes `[ "proto" "fixed" "address" ]` (`:115-119`); `readClaims`
  (`:326-366`) gains the three rows and returns a normalised claim carrying `fixed`, `proto` and
  `address`, so the index reads a value the reading has already held to a domain rather than reading
  the module's own attrset back.
- `lib/plan.nix`: `portsOf` (`:701-709`) compares the normalised claim and drops the `toJSON`;
  `claimsOf` (`:714-726`) carries a port claim as a record rather than a string; `collisionRows`
  (`:733-757`) gains the overlap step for ports; the port resource's evidence and resolution
  (`:648-656`) are restated over the address.
- `lib/resolve.nix`: unchanged. `alloc.ports` stays `mapAttrs (_: claim: claim.fixed)`
  (`:941-943`), which is what keeps the entry key still.
- The modules that must lose one word, one `count` line each:
  `fixtures/minimal-typed-edge/modules/borg-repo/server.nix:16`, `perf/fleet.nix:90`,
  `perf/mesh.nix:102`, `tests/unit/composition.nix:54`, `tests/unit/composition.nix:217`,
  `tests/unit/plan.nix:276`, `tests/unit/plan.nix:927`, `tests/unit/postgres.nix:45`,
  `tests/e2e/generated-secret/deployment/modules/issuer/api.nix:15`,
  `tests/e2e/secret-delivery/deployment/modules/issuer/api.nix:13`,
  `tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:28` and
  `tests/e2e/wired-pair/deployment/modules/page/server.nix:13`. Twelve claim sites in ten files, one
  of them a fixture and two of them perf inputs.
- No golden moves. A claim's `count` is in no plan field, so deleting it changes no record, and every
  number claimed in the fixture and in `perf/` is already an integer. The task list verifies that
  rather than asserting it, with `nix eval --json .#debug.worked.plan | jq -S .` against
  `fixtures/minimal-typed-edge/plan/*` as committed.
- `tests/unit/{composition,plan}.nix` gain the scenarios. There is no `tests/unit/module.nix`, which
  an earlier draft of this list named: the module reading is exercised through `composition`, whose
  deployments are what a claim is written in. `tests/unit/coverage.nix` moves this change's two spec
  files from `excused` to `accountable`; `docs/tooling.md`'s per-suite figures move with the test
  counts.
- `docs/authoring.md:142` (the claim row of the vocabulary table), `docs/diagnostics.md:130` (the
  three new identifiers beside `port-claim-not-fixed`) and `docs/diagnostics.md:244` (the port row,
  which today states a rule the tree does not hold). `docs/plan.md:68,80` stay as written: `alloc`
  still records the fixed port and the key still hashes it.
- `CLAUDE.md`: the claim's three typed fields, why an unstated protocol is the wide reading and an
  unstated address is the wildcard, and why the address is in neither `alloc` nor the key.
- Nothing under `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. No realiser reads a
  claim: `alloc` reaches a unit only through the `impl` argument a module interpolates itself.
