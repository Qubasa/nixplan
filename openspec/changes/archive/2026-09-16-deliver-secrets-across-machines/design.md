# Design

## D1 — Why the delivery set cannot be derived from the value

A routable secret may legitimately go anywhere, so no property of the value narrows the set of
machines that may hold it. Three candidate sources, and why each fails:

| Source | Why not |
| --- | --- |
| the atom (`locality`) | excluded (`lib/excluded.nix:18-21`), and `routable` would admit every machine anyway |
| `impl` interpolation | `impl` is applied per placement inside `mkPlacement` (`lib/resolve.nix:541`), which runs *after* wiring; deriving the set from it is a cycle |
| the wire | a wire says which capability, not which export; a consumer wiring a capability of ten exports would receive all ten secrets |

What is left is the declared read: `uses.<slot>.reads` is read in `readSlot`
(`lib/module.nix:183`) before any placement exists, and it already names exports one by one. So the
set is the owner's placements plus the machines of the entries whose `reads` name an export the
generator backs. The cost is a list an author maintains by hand, and the corpus records it as such.

The index that makes this cheap already exists: `readerIndex` (`lib/plan.nix:29-67`) maps
`"<providerEntryKey>|<capability>|<export>"` to the entry keys that read it. It is built once for
the whole deployment. Delivery needs one more thing from the provider side — which generator file, if
any, is behind an export — so `exportRecord` (`lib/resolve.nix:736-762`) keeps the provenance it
currently discards when it collapses a vars file to `value.path`.

## D2 — A generated value is an entry, not a field

Today a generated file appears only inside the entries that mention it (`varsRecord`,
`lib/plan.nix:89-100`). That cannot hold a delivery: a machine in the set may run no service that
reads the value, and a `per = "instance"` value has no single unit entry to live in at all.

So the value becomes a plan entry, keyed as the corpus keys it:

```
pg:vars/app            per = "instance"    one value for the instance
fleet:vars/hostKey@alpha  per = "placement"    one value per machine
```

Both forms split at the last `@`, which is the rule `parseKey` in `image/read.nix` and
`machine_of` in `tests/e2e/delivery.py:56-68` already apply. `vars/` in the service position is what
tells a reader an entry is a value rather than a service, and it cannot collide with a member name:
a member name is an attribute name in a root's `services`, and `/` is not in one.

**Ownership.** A generator is declared by a member's module, and the entry key names only the
instance. Two members of one instance declaring one generator name would be one address for two
values, so it is a row (`vars-generator-name-collision`) rather than a silent merge or a
member-qualified key. Keying by member instead was rejected: `per = "instance"` means *the
instance's* value, and a key naming the member would make the shared case read as one value per
member.

**Key inputs.** `per`, `deploy`, the file records, the sibling entries and keys it reads, and — for
`per = "placement"` — `machine:<m>@<hash>` in `dependsOn`, which is how a machine fact reaches a key
everywhere else in this library (`lib/plan.nix:402`). Not in the key: the delivery set. A machine
joining the set because a new consumer read the value does not change the value, and re-keying it
would force a regeneration of bytes that are still correct. The set is recorded, and the consumer
entry that caused it re-keys itself because its own `reads` moved.

## D3 — `varsState` is keyed by the value, not by the machine

`varsState.<machine>.<gen>.<file>` (`lib/resolve.nix:507`) has no answer for a value that exists
once for an instance placed on three machines: three records, free to disagree, about one value. The
new shape is the entry key the plan emits:

```nix
varsState."pg:vars/app".password             = { present = true; };
varsState."fleet:vars/hostKey@alpha"."key"   = { present = true; content = "…"; };
```

This is a clean cutover — every caller moves (`tests/unit/{plan,units,image,flakelet}.nix`,
`tests/unit/worked.nix`, `perf/{fleet,mesh}.nix`, `docs/README.md`, `docs/authoring.md`). The
alternative, keeping the machine keying and reducing over placements for the shared case, needs a
merge rule for two disagreeing records, and there is no correct one.

## D4 — The path gains the instance, and keeps `/run/vars`

`path = "/run/vars/${gen}/${fname}"` (`lib/resolve.nix:524`) is not unique on a machine: two
instances of one module placed together name one file. Delivery makes it reachable from a second
direction — a machine can receive a value it does not own — so the path becomes
`/run/vars/<instance>/<gen>/<file>`.

The prefix stays `/run/vars` rather than becoming the corpus's `/run/secrets`, because one generator
declares public and secret files together (the corpus's `signing` declares `cert.pem` and
`key.pem`) and splitting them across two prefixes by secrecy would put one object's halves in two
places. `image/read.nix` stages the path as a host path regardless of prefix, so nothing in the
image realiser depends on the literal.

## D5 — What the consumer receives

A secret export's value is a `secretRef`, and `atoms.secretRef` verifies `{ path, secrecy }`
(`lib/atoms.nix:14-16`). `exportRecord` currently collapses it to `value.path` for the plan, and
`results` hands the consumer that string (`lib/resolve.nix:751`, `442`). For a producer reading its
own value that is invisible, because a producer reads `vars.<gen>.<file>.path` directly.

For a consumer it matters: with a bare string, `env.DB_PASSWORD = results.db.password` silently
exports a *path* under the name of a password. So the consumer receives the record, and a module
writes `results.db.password.path`. Interpolating the record raises, which is the loud failure. The
plan keeps `value = <path>` on the export record, unchanged: the plan records the reference that is
delivered, and `plane = "reference"` beside it already says which it is.

## D6 — `deploy` is refused at the sites that would open the file

`deploy = false` means one value exists and no machine receives bytes. Two sites would then open a
path that resolves to nothing:

- the owning module's own unit or configuration file naming `vars.<gen>.<file>.path`. Detected the
  way an undeclared closure mention is detected: `mentionSites` (`lib/plan.nix:291-333`) already
  walks every unit, environment, extension and configuration file of an entry, so the same walk
  finds the path of an undeployed file.
- a consumer's declared read of a secret export backed by it. Detected at the edge, where the
  provenance of D1 is already in hand.

A public file of a `deploy = false` generator is not refused: its value is in the plan, and a value
in the plan needs no file on a machine. That is the binary-caches `ca-pub` case and the one thing
`deploy = false` is *for*.

## D7 — The arity rule replaces a platform rule

`vars.<gen>.reads` names siblings. The corpus records that this used to be a platform rule
forbidding a shared generator from depending on a machine-specific one, and that it is now an arity
mismatch: five placements hold five host keys, the CA is one value, and the read has no single
answer. So the check is `per`-against-`per` and needs no special case:

| reader | sibling | verdict |
| --- | --- | --- |
| `placement` | `instance` | accepted; each placement's entry depends on the one shared entry |
| `placement` | `placement` | accepted; the entry on a machine depends on the sibling on that machine |
| `instance` | `instance` | accepted |
| `instance` | `placement` | refused, naming both cardinalities |

The planner records the dependency and runs nothing: which order an operator's generators run in is
`dependsOn`, which is the same field a service entry uses.

## D8 — The flakelet refusal splits along a line already in the data

`flakelet/read.nix:127-137` refuses every `image.hostPaths` entry. The two kinds it refuses are
already distinguishable in that list (`image/read.nix:226-240`):

| kind | `from` | who creates the bytes |
| --- | --- | --- |
| `configuration-file` | `stagedPath name path` | an assemble step this realiser does not have |
| `generated-file` | `g.path`, i.e. itself | the delivery, before activation |

So the refusal becomes `filter (p: p.from != p.path)`. This is not a weakening: before this change
nothing put bytes at a generated file's path on a flakelet machine, so the refusal was correct; the
delivery agent is the step that makes it wrong. The planner still refuses an entry whose value no
machine receives (D6), so the realiser needs no second check for it.

## D9 — The machine layer: three machines, and what proves it

The claim is not that a file exists. It is that a service on another machine authenticates with the
value. So the folder is:

```
alpha  issuer:api@alpha    serves 200 only when the request bearer equals the delivered token
beta   probe:client@beta   reads /run/vars/issuer/session/token, gets 200, and 401 without it
gamma  idle:job@gamma      one unit, no slot: the bystander that must hold nothing
```

`issuer` declares two generators: `session` (`per = "instance"`, one secret file, delivered) and
`ca` (`deploy = false`, one public file whose value the consumer reads out of the plan). That pairs
the positive and negative halves of `deploy` in one deployment, and gives the folder a public value
that travels while its file exists nowhere.

Three machines rather than two, because the negative claim is machine-scoped: a bystander on a
machine in the set proves nothing. The cost is one more slot in one more snapshot cut
(`docs/cluster.md:121-177`), about 2 GiB and one cold boot.

The provider binds `0.0.0.0` and the plan is held to the exported URL built from `target.address`,
which is the rule `tests/e2e/wired-pair/` already follows: a unit starts before the DHCP lease
exists.

**Ordering.** Deliver values, then deliver and activate artifacts. The consumer's unit is a one-shot
whose success *is* the assertion, so an activation before delivery would fail it — which is the
right way round: the operator's sequence is stated in the test, and the planner records the
dependency (`dependsOn`) that a later orchestrator would enforce.

## D10 — What the agent is, and what it is not

`tests/e2e/delivery.py` gains the value half of a delivery beside the store half:

- `vars_entries(plan)` — the vars entries, as `(key, per, deploy, delivery, files)`.
- `deliver_value(namespace, plan, key, bytes_by_file, *, ssh_key)` — writes each file at the path
  the entry records, mode `0400`, on every machine in that entry's delivery set, refusing a set
  member the plan gives no address for.

It writes with `install -m 0400 -D` over ssh rather than `nix copy`, because a store object is
world-readable and the whole point is that the bytes are not in the store. Ownership beyond
root-owned `0400` is out of scope (see the proposal): it needs a machine `class` the registry does
not carry.

The generation itself is the operator's: the folder's `conftest` mints the token with
`secrets.token_hex` once per session and hands the same bytes to the agent, which is what a
`per = "instance"` value is. The planner is told `present = true` for that value through
`varsState`, keyed by the entry as in D3.

## Risks

- **The perf budgets move.** The vars entries are new plan entries, so cost per plan entry — the
  budgeted quantity (`CLAUDE.md`, "A budget is cost per plan entry") — changes on both synthetic
  fixtures, which declare one generator per machine. The gate is run and the budgets are
  regenerated as part of the change rather than adjusted by hand.
- **The golden plan grows.** `fixtures/minimal-typed-edge/` declares `hostKey` on a member placed on
  three machines, so the golden gains three vars entries and every generated path gains an instance
  segment. Regenerated with the documented command, never hand-edited.
- **`testAConsumerAsksForThePrivateHalf` flips.** It currently asserts the refusal this change
  deletes. Its scenario heading names a situation rather than an outcome, so the heading stays and
  the body is rewritten; the cross-walk (`tests/unit/coverage.nix`) keeps holding it.
