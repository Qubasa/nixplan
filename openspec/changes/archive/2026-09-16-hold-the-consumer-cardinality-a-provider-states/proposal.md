## Why

`consumers = "one"` is the only check in the edge layer that expresses an exclusive resource on the
*provider's* side. Every other rule of a wire is about the consumer: `reach` counts the provider's
placements against what the slot can hold, the interface comparison is made at the slot, and an
absent read is reported against the reading entry. A single-writer database role, a lease and a
single-listener socket have nothing else to say so. It is silently unenforced whenever the instance
root re-exposes the capability under a name other than the member's own attribute key.

Reproduced with one deployment, two consumers and one capability declaring `consumers = "one"`:
with the root writing `provides.repo = server.provides.repo;` the table carries
`capability-consumers-exceeded` and `applicable` is false. Change that one word to
`provides.endpoint = server.provides.repo;`, wire both consumers to `endpoint`, and the identical
deployment plans clean with an empty diagnostics table.

The cause is two adjacent expressions keyed on two different names. `capName`
(`lib/resolve.nix:1555`) is the wire's own `provides` field, which is a key of the root's `exposed`
set (`lib/resolve.nix:791`, built from `rootProvides` at `lib/resolve.nix:646-648`). The exports are
read by the member's own capability name, `capability.capability`
(`lib/resolve.nix:1608`), which is what `lib/compose.nix:68-75` records on every capability a member
publishes. The cardinality is read by the first of the two:

    providerDeclared =
      if providerMember == null then null else providerMember.declaration.provides.${capName} or null;

`lib/resolve.nix:1581-1582`. A renamed exposure makes that attribute miss, the `or null` swallows
it, and `consumers = if providerDeclared == null then "many" else providerDeclared.consumers`
(`lib/resolve.nix:1853`) reads the provider's statement as `many`. The deployment-wide count itself
is correct: `lib/resolve.nix:1951` groups on
`"${edge.providerInstance}:${edge.providerMember}.${edge.capability}"`, the member's own name, so the
wires are counted against the right capability and compared against a cardinality nobody declared.
For a binding the two names coincide - `capName = binding.capability`
(`lib/resolve.nix:1555`) is already the member's own - so the bound path is correct today.

It is invisible in this repository because every in-tree root re-exposes name for name:
`fixtures/minimal-typed-edge/modules/borg-repo/default.nix:21` writes `provides.repo =
server.provides.repo`, and `tests/e2e/shared-postgres/deployment/modules/postgresql/default.nix:28`
derives its keyset with `mapAttrs (db: _: cluster.provides.${db})`, which is name for name by
construction. No test exercises a renamed exposure, and nothing else in the reading depends on the
two names agreeing.

## What Changes

- **A capability's declared consumer cardinality is read by the member's own capability name.** It
  is a property of the capability the member declared, so the reading asks the member's own
  declaration for it rather than asking it for the name a root chose to publish.
- **A root re-exposing a capability under another name no longer widens its cardinality.** What a
  root's `provides` decides is which name a wire may address. How many wires may take the capability
  is the member's statement, and the two are separate facts: one capability exposed as one name, as
  another, or under two names at once admits the same number of consumers, and a wire naming any of
  those names counts against that one capability.
- **The count is unchanged.** Deployment-wide, over wires rather than placements or reads, a binding
  counted as a wire, a consumer placed on twelve machines counted once, one row per capability
  subjected to the providing member. Nothing about the grouping, the severity or the row's text
  moves.
- **No new row identifier and no new declaration.** `capability-consumers-exceeded` already exists
  and already says what it has to say; the change is which capability's declaration it is compared
  against. `capability-consumers-malformed` still reports a value outside the domain, and a
  capability declaring nothing is still taken by any number.

## Capabilities

### New Capabilities

<!-- none: the rule exists and is read by the wrong name -->

### Modified Capabilities

- `planner/typed-edge`: the consumer-cardinality requirement restated, so that the declared
  cardinality is read by the member's own capability name, a renamed or aliased exposure neither
  widens nor narrows it, and a binding still counts as a wire.

## Impact

- `lib/resolve.nix`: one expression, `lib/resolve.nix:1581-1582`, reading
  `providerMember.declaration.provides.${capability.capability}` instead of `…${capName}`.
  `providerDeclared` has one consumer (`lib/resolve.nix:1853`) and nothing else in the file reads it.
  The member's read declaration is where the cardinality is defaulted and domain-checked
  (`lib/module.nix:275-313`, `lib/module.nix:1016-1018`), so the row a malformed value earns is
  still produced at the declaration and the count still sees `many`.
- `tests/unit/resolution.nix`: the `taking` helper (`tests/unit/resolution.nix:283-317`) gains the
  ability to expose a capability under a chosen name, which `support.root`
  (`tests/unit/support.nix:59-71`) already accepts and only `soleRoot`
  (`tests/unit/support.nix:73-93`) collapses to name for name. Four tests beside the four cardinality
  tests that exist (`tests/unit/resolution.nix:2266-2421`), all four of which keep their present
  deployments and stay green.
- No plan field moves. `readsRecord` records `reach`, `reads`, `delivered` and the wire as the
  deployment wrote it (`lib/plan.nix:236-241`); the cardinality is nowhere in the plan, so the only
  observable difference for a renamed deployment is the row and `applicable`. `reads.<slot>.wire.provides`
  keeps recording the name the deployment named (`lib/resolve.nix:1838-1845`), which is the other
  half of the same distinction.
- No golden moves. Nothing under `fixtures/` declares `consumers` at all, and every in-tree root
  re-exposes name for name, so `fixtures/minimal-typed-edge/plan/backup.json` and
  `.../diagnostics.txt` stay byte-equal.
- `docs/diagnostics.md:203`, `docs/authoring.md:820-827` and `CLAUDE.md:240-243`: the rule gains the
  sentence about which name the cardinality is read by. `docs/tooling.md:87`: the `resolution` suite's
  recorded figure, which `coverage` crosses against the suite.
- Nothing under `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. A realiser is
  handed the same plan; a deployment whose provider said it serves one consumer and whose root
  renamed the capability now carries the error row it always owed.
