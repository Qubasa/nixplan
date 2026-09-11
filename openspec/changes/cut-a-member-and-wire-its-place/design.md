## Context

See proposal.md - Why. Three shapes decide the approach:

- **A member handle is built eagerly and holds everything about that member.**
  `lib/compose.nix:24-71`: `service settingsOf name args` resolves the member's settings, applies the
  module once against them, and returns `{ name, module, defaults, fixed, settings, declaration,
  slotSet, unknownKeys, provides }`. `provides` is the declaration's capabilities decorated with
  `member` and `capability`. Adding a `wire` key to `serviceKeys` puts the root's bindings on the same
  record.
- **A wire resolves per member, from one instance-level namespace.** `lib/resolve.nix:810` reads
  `resolved.instances.<i>.wire`, and the slot name is the key, so one `wire.<slot>` reaches every
  member of the instance that declares that slot name - which is how the corpus's
  `inherit mesh oidc` hands two slots to two consumers with two wires rather than four.
- **The member-scoped shape is already detected.** `lib/resolve.nix:1436-1444` has `isMemberCut` and
  refuses it with the exclusion row, and the refusal is skipped by the `wire-unknown-instance` guard
  at `:1450-1458`. The reading knows the shape; it declines to mean anything by it.

The one thing that does not exist at all is an intra-instance edge. Today a module that composes a
consumer and its private provider cannot connect them: the deployment must write a wire, which means
the deployment learns that the private provider exists.

## Goals / Non-Goals

**Goals:**

- Let a module publish one composition with its internal edges written as Nix bindings, and let a
  deployment take less of it.
- Make the binding-versus-address rule mechanical: what decides it is whether the target is a kept
  member, and nothing else, so no line of the module differs between the two cases.
- Add nothing to the plan. A cut is an absence of entries; the plan must not gain a field saying
  what was cut, or the cut stops being an authoring decision.
- Keep every key of every entry that remains.

**Non-Goals:**

- No per-placement member settings. A member's asking half is evaluated once and its `provides` is
  one value; a divergence between two machines is still a second instance, which is what the corpus
  records at `deployment/instances.nix:84-88`.
- No implicit resolution across an instance boundary. A cut opens a slot and the deployment fills it
  by name; nothing searches for a capability that would fit.
- No `collects`/`contributes`. A slot whose far end is every service on a machine stays excluded.
- No cycle detection. A capability's exports are a function of module and settings and never of a
  wire, which is what keeps a binding acyclic, and it is what makes two instances wiring each other
  legal already.

## Decisions

### A binding is a value, not a name

`wire.<slot>` inside a member takes the capability *value* off a sibling's handle -
`db.provides.db`, not `"db"` or a path. A mistyped attribute is then a Nix error in the module's own
file, which is the same trade `provides.repo = server.provides.repo` already makes in
`fixtures/minimal-typed-edge/modules/borg-repo/default.nix:21`.

A capability record already carries `member` and `capability` (`lib/compose.nix:63-70`), so the
resolver can tell which member a binding points at without the root saying so, which is exactly what
the cut rule needs.

Alternatives considered:

- **`wire.<slot> = { member = "db"; provides = "db"; }`.** Rejected: it is a name resolved at
  composition time, so a typo is a row at best and a silent miss at worst, and it duplicates the
  namespace the handles already are.
- **Wire members implicitly by interface.** Rejected: it is the search this design does not have,
  and two members providing one interface would make the edge depend on declaration order.

### A cut is read before anything else about the member

`members.<name>.enable = false` is read in the instance reading, before placement, settings
namespaces, generators and unit references. A cut member is then absent from the member set every
later stage folds over, so "produces no entry" and "owns no value" are consequences of one filter
rather than four checks. The rows for naming a cut member are produced by comparing the deployment's
own keysets - `placement.every`, `settings` - against the kept set, which is where `namespaceRows`
(`lib/compose.nix:148-165`) already compares one keyset against the member list.

### A binding to a cut member becomes an unfilled slot, not an error

The handle of a cut member still exists in the root's `let` - the root is Nix and the binding is
evaluated - so the resolver cannot simply not see it. What it does instead is check the `member` field
of the capability a binding names against the kept set: a binding naming a cut member is discarded,
and the slot is then unwired unless the deployment wrote `wire.<member>.<slot>`.

Discarding rather than refusing is the whole point: a module that binds `server.db` to its private
database is correct in both deployments, and the deployment that cut the database is the party that
says what fills the slot.

### A member-scoped wire outranks nothing; a binding to a kept member outranks the deployment

Three cases, and each has one answer:

1. The binding's target is kept and the deployment writes no wire → the binding resolves the slot.
2. The binding's target is cut and the deployment writes `wire.<member>.<slot>` → that address
   resolves the slot.
3. The binding's target is kept and the deployment writes a wire anyway → an error row naming the
   slot, the bound member and the deployment file, and the binding resolves the slot.

Case 3 is a row rather than a precedence rule because the two statements disagree about what the
composition is, and picking a winner silently would make one of the two files a lie. The instance's
own `wire.<slot>` continues to mean what it means for a slot no binding fills.

### `consumers` is counted over wires, once per capability

The check is a fold over every instance's resolved wires, grouped by the capability they name: a
capability declaring `consumers = "one"` with more than one wire naming it earns one row listing the
consumers. Counting wires and not placements is what makes a consumer placed on twelve machines one
consumer, which is the reading the corpus states at
`notes/examples/instance-as-group/modules/postgresql/databases.nix:26-30` - "the second consumer of
one database is refused".

The row is subjected to the providing capability rather than to one of the consumers, so `dedup` keeps
one and neither consumer is named as the offender.

### Removing an exclusion row is three edits and they move together

`lib/excluded.nix` drops `enable` and `memberWire` and the `member cuts` row;
`tests/unit/exclusions.nix` drops the two cases and its row count moves;
`fixtures/minimal-typed-edge/README.md`'s table drops the row. The suite compares the count against
the README, so the three cannot be edited apart - which is why the diagnostics delta states the
table's contents as a requirement rather than leaving it to the implementation.

## Risks / Trade-offs

- **The binding construct is a new authoring surface, and every root in the tree could use it.** →
  It is optional and additive: a root that writes no `wire` is unchanged, and the fixture keeps its
  current shape so the golden plan does not move.
- **Case 3 is a row where a user may expect an override.** → An operator who wants to replace a
  bound provider cuts the member; that is one line and it says what it means. A silent override
  would make a module's internal edges deployment-dependent, which is the property the cut rule
  exists to keep.
- **A cut member's handle is still evaluated**, so a module whose cut member raises on its own
  settings still raises. → That is already true of every member (`lib/compose.nix:42-50` guards the
  second reading for this reason), and the cut does not make it worse.
- **`consumers = "one"` is a provider-side policy a deployment cannot override.** → That is what it
  is for. A provider that can serve two consumers should not declare it, and the row names the
  capability so the fix is visible.
- **The corpus's `pg-shared` also wants `locality`, `state`, a firewall contribution and a port
  range.** → None is in this change. What this change delivers is the half the corpus calls "the
  whole rule in two files"; the rest stays excluded with its triggers recorded.
- **A deployment that cuts a member and mistypes the member's name gets no cut.** → The row for
  naming a member the module does not publish already exists for `settings`; the cut reading uses the
  same comparison, so a mistyped cut is a row rather than a silent no-op.
