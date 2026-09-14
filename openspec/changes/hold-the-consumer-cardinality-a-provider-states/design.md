## Context

See `proposal.md` - Why. The shapes that decide the fix, each read rather than assumed:

- **Two names exist for one capability and both are legitimate.** A member's own capability name is
  its attribute key under `provides`, which `lib/compose.nix:68-75` records on the published record
  as `capability` beside `member`. A root's exposed name is a key of its own `provides`, which
  `lib/resolve.nix:646-648` turns into `rootProvides` and `lib/resolve.nix:791` filters by `exposes`.
  A wire names the second (`lib/resolve.nix:1550,1555`); the exports are read by the first
  (`lib/resolve.nix:1608`).
- **The cardinality lives on the member's read declaration.** `providerMember.declaration` is
  `module.read` of the member's own declaration (`lib/resolve.nix:814-819`), whose `provides` is a
  `mapAttrs` over the member's keys (`lib/module.nix:1016-1018`). `readCapability`
  (`lib/module.nix:275-313`) is where `consumers` is domain-checked against
  `atoms.domains.consumerCardinality`, where a value outside it is `capability-consumers-malformed`
  and not recorded, and where an omitted key becomes `"many"` (`lib/module.nix:286-293`).
- **The count already uses the member's own name.** `takenCapabilities` groups on
  `"${edge.providerInstance}:${edge.providerMember}.${edge.capability}"` (`lib/resolve.nix:1951`),
  and `edge.capability` is `capability.capability` (`lib/resolve.nix:1846`). So the wires are already
  gathered against the right capability; only the number they are compared against is read by the
  wrong name.
- **`providerDeclared` has exactly one consumer.** `lib/resolve.nix:1853` is the only read of it, and
  nothing else in the file mentions it. The fix has no second site.
- **A binding already agrees.** Where `isBound`, `capName = binding.capability`
  (`lib/resolve.nix:1555`) and `capability = binding` (`lib/resolve.nix:1562-1564`), so the two names
  are one string and the bound path is correct before and after.
- **The plan records neither number.** `readsRecord` carries `reach`, `reads`, `delivered` and the
  wire (`lib/plan.nix:236-241`), and no field of any entry says how many consumers a capability
  admits. A renamed deployment's plan is therefore identical before and after the fix; what moves is
  the diagnostics table and `applicable`.

## Goals / Non-Goals

**Goals:**

- A provider's statement about exclusivity holds however the composition publishes the capability.
- The fix is one expression at the site that already knows both names, with no new field, no new row
  identifier and no new declaration.
- The renamed path gains tests, because no deployment in the tree renames and the goldens therefore
  cannot hold the rule.

**Non-Goals:**

- No change to the count. The grouping, the wire-not-placement rule, the binding-counts-as-a-wire
  rule, the one-row-per-capability rule and the row's own text stay as they are.
- No restriction on composition. A root renaming a capability, and a root exposing one capability
  under two names, stay legal.
- No new cardinality. `one` and `many` remain the domain; an exact count, a per-machine cardinality
  and a per-instance one are each a separate decision and none is needed to hold the stated rule.
- No search and no allocation. Counting declared wires is a fold over data the reading already built.

## Decisions

**The cardinality is read by the member's own capability name.** `lib/resolve.nix:1581-1582` becomes
`providerMember.declaration.provides.${capability.capability} or null`. `capability` is already forced
one line above, since `providerMember` is `targetInstance.members.${capability.member}`
(`lib/resolve.nix:1575-1576`), so the selection adds an attribute lookup and no thunk of its own. The
`or null` stays: a capability absent from the member's read declaration is a shape the reading
reports elsewhere, and the fallback to `many` is what keeps this check from being a second voice
about a malformed declaration.

Alternative rejected: read it off the exposed record, `capability.consumers`. That record is
`declared // { member; capability; }` over `declaration.provides` of the *composing* module
(`lib/compose.nix:68-75`), where `declaration` is `module { settings = settings.values; }`
(`lib/compose.nix:31`) - the raw module output, which has not been through `readCapability`. Reading
it would bypass the domain check and the default: a capability declaring nothing would be an
attribute miss rather than `"many"`, and a value the declaration reading already refused as
`capability-consumers-malformed` would be enforced anyway, which is two answers to one question.

**The group key stays the provider's own capability.** Two exposed names for one member capability
therefore fold into one group and the wires to both are counted together. Alternative rejected:
grouping by the exposed name (`capName`). It would make a root able to widen a provider's cardinality
by writing one more line of `provides`, which is the same defect this change closes, spelled
deliberately.

**Renaming stays legal and earns no row.** A root publishes its own vocabulary, and the tree relies
on it: `tests/e2e/shared-postgres/deployment/modules/postgresql/default.nix:28` derives its exposed
keyset from a setting with `mapAttrs`, which only happens to be name for name. Alternative rejected:
a `capability-renamed-on-exposure` row, or a refusal of two names for one capability. Both restrict
composition in order to repair a reading, and a rename is not a mistake once the number is read from
the right side.

**The row's text is unchanged, and it names the provider's own capability name.** The subject is the
providing member (`lib/resolve.nix:1971`) and the message names `first.capability`
(`lib/resolve.nix:1973`), which is the name the declaration a reader has to edit is written under.

Open question, recorded rather than decided: whether the message should also name the exposed names
the wires used. It is a message-only change, it has no single answer where two names alias one
capability, and the resolution already names the declaration to edit and the wires to move, so the
text is left alone here. A reader who has to work back from a wire to the declaration currently does
it through the root's `provides`, which is one file.

**The evidence is in `tests/unit/resolution.nix`, through the helper that already exists.**
`support.root` takes `provides` as an attrset of `{ member, capability }` references
(`tests/unit/support.nix:59-71`), so an exposed name other than the member's own costs no new support
code; `soleRoot` (`tests/unit/support.nix:73-93`) is the name-for-name shortcut over it. The suite's
own `taking` helper (`tests/unit/resolution.nix:283-317`) gains the exposure mapping and keeps its
present signature for the four tests that call it, so the four cardinality tests that exist
(`tests/unit/resolution.nix:2266-2421`) are untouched and go on proving the name-for-name case.

Alternative rejected: a fixture that renames. `fixtures/**` is compared with `==` and is excluded
from the formatter (`CLAUDE.md`, Fixtures and goldens), so a fixture edit is a golden edit, and the
folder's job is one worked deployment rather than one deployment per rule.

**The check stays provider-side and alone.** `reach`, the interface comparison and the absent-read
rows are all about the consumer. This is the only rule in the edge layer by which a provider states
that its resource is exclusive, which is the reason the miss is worth a change of its own rather than
a line in a larger one: nothing else would have reported it.

## Risks / Trade-offs

- **A deployment that plans clean today starts failing.** → Only a deployment whose provider declared
  `consumers = "one"` and whose root exposed that capability under another name, with a second wire
  to it. That is a deployment where the provider said it cannot serve the second consumer and the
  planner agreed by accident. No deployment in this repository renames: the fixture and the two
  end-to-end roots that expose anything are name for name
  (`fixtures/minimal-typed-edge/modules/borg-repo/default.nix:21`,
  `tests/e2e/shared-postgres/deployment/modules/postgresql/default.nix:28`), and nothing under
  `fixtures/` declares `consumers` at all.
- **The rule now has two readings to keep in step: the group key and the declaration lookup.** → They
  are the same name after this change, which is the point, and a test of the aliased case
  (one capability, two exposed names, one wire each) fails the moment they part again.
- **Evaluation cost.** → One attribute selection per edge on a value already forced. The gate is `nix
  build .#checks.x86_64-linux.planner-perf`, where the budgets are cost per plan entry with a margin
  of 0.15, and `perf/mesh.nix` is the fixture with an edge per peer.
- **A root can still hide which capability a wire took, by name.** → It is one file per instance and
  the row names the provider's member and its capability, so the walk from the wire to the
  declaration is short. Adding the exposed name to the message is the open question above rather than
  a silent assumption.
