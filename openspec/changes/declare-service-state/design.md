## Context

See proposal.md - Why. The constraints that shape the approach, all measured in this tree:

- The implementation surface is a closed allow-list: `implKeys = [ "units" "configData" "provides" "closure" ]`
  (`lib/module.nix:86-91`). A key it does not name is `implementation-unknown-key`,
  and a key an excluded construct owns is `declaration-excluded-key` with that construct's
  recorded trigger beside it (`lib/excluded.nix:19-59`).
- `configData` is already path-keyed with a per-file record of `{ mode, reload, computed }`
  (`docs/plan.md:66`), so a path-keyed map with a small record is the shape this
  library already reads and renders.
- `atoms.nix` already ships the typed values a portable declaration needs: `userName`, whose
  comment fixes the rule this design depends on - "the identity a name resolves to is the
  machine's answer and not the plan's" (`lib/atoms.nix:50-55`) - and `unitRef`,
  which "refuses a name the referring module did not declare itself" (`:25-28`).
- `keyInput` is assembled in one place (`lib/plan.nix:454-471`) and the key is
  `util.shortHash (builtins.toJSON keyInput)` (`:491`).
- An interface's atoms carry `type` and `secrecy` only (`lib/interface.nix:23-26`).
  `locality` is not implemented; it is the excluded construct whose trigger is "the first export
  in the target whose value is a unix socket path or a loopback port"
  (`lib/excluded.nix:20-23`).
- The planner emits rows and never raises; the image builder raises and reads nothing that is
  not a plan fact (`image/read.nix:1-13`). The two halves keep that split here.

## Goals / Non-Goals

**Goals:**

- One declaration site for mutable state, portable across the service managers in charter.
- The plan carries it, so P2 and P7 read state without an evaluator and without parsing units.
- The rendered unit's directive is derived from the declaration, so the two cannot disagree.
- Every malformed declaration is a row; the plan is still produced.

**Non-Goals (design-level, beyond the proposal's scope):**

- No new merge semantics. State is contributed by one member and read by the machine; it is not
  a machine-scope option with a merge class (§15.3/§19.4 territory).
- No snapshot format, no dump store, no transfer. This change names the hooks; running them is
  P2's charter (`notes/clan-portable-services-design.md:741-748`).
- No host-side folder creation. What creates a folder outside the service manager's own state
  location is endpoint work (`universe-463.4`), and this change refuses such a folder without an
  owner precisely so that work has a name to use.

## Decisions

**D1. State is a declared fact, not an export.**
The three readers that need it - P2, P7, the binding - are not peers on a wire, and a wire is
optional by construction while state is not. Declaring it under `implKeys` puts it in the plan
unconditionally.
*Alternative considered: a platform-shipped `state` interface with `provides.state`/`uses.state`
as the only site.* Rejected for this change on evidence rather than taste: a state folder is a
path on one machine, which is exactly the value `excluded.constructs.locality` names as its
trigger. Putting one on the export plane forces the bound, the provider tag and §32.5's three
dispositions in the same change, and an export with no locality would let a cross-machine slot
read a path the consumer cannot open - the silent-wrong outcome the corpus refuses. The interface
lands with `locality`, and `provides.state` is then *derived from this declaration* so a backup
edge cannot disagree with what the service writes.

**D2. Path-keyed, with the record beside it.**

```nix
state = {
  folders = {
    "/var/lib/postgres" = { owner = "postgres"; };
    "/var/cache/postgres" = { disposition = "derived"; };
  };
  dump = "pgDump";
  restore = "pgRestore";
};
```

The path is the identity, so no second name can collide with it or drift from it - the argument
`configData` already settled. `folders` is nested rather than `state` being the map directly,
because `dump` and `restore` are service-scope and would otherwise need a second `implKey` or a
reserved path key. Key lists mirror the existing pattern: `stateKeys = [ "folders" "dump" "restore" ]`,
`stateFolderKeys = [ "owner" "disposition" ]`, `dispositions` gains nothing (the config-file
`dispositions` list is a different domain; state's is its own `stateDispositions = [ "durable" "derived" ]`).

**D3. Hooks are unit references, not commands.**
`atoms.unitRef` and the existing `unit-reference-unknown` rule already state the invariant: a
module may only name its own units. That makes a hook part of the generation, subject to the
same sandboxing and ordering as the code that wrote the data, and it collapses P2's contract for
the common case to "start these two units".
*Alternative: a command string or a store path.* Rejected - it re-introduces an executable that
the plan would have to hash separately and that no service manager supervises.

**D4. Expressibility is a planner check, not a builder guess.**
The entry already knows `target = { system, serviceManager }` (`docs/plan.md:60-63`),
so "this folder needs an owner because this service manager can only express it for a named
account" is decidable where rows are produced. The builder then renders and raises only if a
plan it did not produce reaches it, which is the standing rule on that side.

**D5. State enters the key.**
Adding the record to `keyInput` re-keys an entry whose folder or owner moved. That is correct
rather than incidental: both change the unit the machine runs and the folders the machine must
carry, so the entry is genuinely different. The cost is that the committed fixture re-keys, which
is a regeneration and a budget re-measure rather than a decision.

**D6. The collision check runs after placement.**
Two entries claiming one folder is a fact about a machine, so it lands in the round that has
placement output - the same round as the port-claim checks - and the row names both entries. A
nested claim counts, because a backup of the outer folder would silently include the inner
service's data.

## Risks / Trade-offs

- **The declaration duplicates what a unit extension can already say** → the conflict row (one
  directive, one source) is part of this change, and the extension field remains legal for units
  with no state declaration so nothing is broken by omission.
- **A path-keyed map invites a machine-scope option later** → explicitly out of scope; if state
  ever needs merging across members, §15.3's taxonomy and §19.4's missing quantitative class have
  to land first, and this change adds no merge behaviour to lean on.
- **Re-keying the committed fixture hides regressions in the diff** → the golden comparison is
  field-by-field with prose keys excluded (`docs/plan.md:234-241`), so a regeneration
  shows exactly which fields moved; the perf budgets are re-measured in the same task rather than
  edited by hand.
- **`derived` is advisory until P2 exists** → nothing consumes it yet, so a wrong disposition is
  invisible today. Mitigated by rendering it into the unit as the cache directive, which makes it
  observable in bytes now rather than only when P2 lands.
- **A service manager outside systemd has no rendering yet** → the declaration is portable and
  the plan records it, but only the systemd binding renders it in this change. A launchd binding
  reads the same field; nothing about the plan changes when it arrives.

## Migration Plan

No deployed artifact changes shape without a re-key, and the re-key is the point: entries that
declare state are new entries. The committed fixture and the budgets are regenerated in the same
change. There is no compatibility path to keep, because no module declares state today - the key
does not exist.

## Open Questions

- Whether `derived` should also suppress the folder from the entry's record entirely once P2
  exists, or stay recorded and be skipped by the snapshot. Recording it is strictly more
  informative and costs one field, so it is recorded now; P2 can narrow later without a spec
  change.
