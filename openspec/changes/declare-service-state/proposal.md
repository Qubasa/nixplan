## Why

A service's mutable state has no declaration site. `implKeys` is
`[ "units" "configData" "provides" "closure" ]` (`lib/module.nix:86-91`), so
the only way a module can say "I write `/var/lib/postgres`" today is the
systemd-tagged extension field `stateDirectory`
(`docs/authoring.md:289-297`) — a value tagged `backend = "systemd"`, invisible
to a launchd target, invisible to the plan, and therefore invisible to every reader that
needs it.

Three readers need it, and only one of them is an application:

- **P2 `statectl`** — snapshot, restore and GC per backend, whose charter says it is "the one
  component whose correctness cannot be verified from Nix"
  (`notes/clan-portable-services-design.md:741-748`). It must know the folder set without
  evaluating Nix.
- **P7** — snapshot before an irreversible activation (§8.3), state-migration sequencing on
  machine replace, and the in-flight multi-phase operations §8.7 admits into the register.
- **the binding that renders the unit** — `StateDirectory=`/`User=` on systemd, something
  else elsewhere.

None of the three can be served by a wire, because a wire is optional by construction and
state is not: a service with no backup instance wired still has to be snapshotted before P7
does something irreversible to it. So state is a **declared fact that lands in the plan**,
and any typed edge to a backup service is a later consumer of that same declaration rather
than its source.

## What Changes

- **`implKeys` gains `state`**: `{ folders = { "<abs path>" = { owner ? null; disposition ? "durable"; }; }; dump ? null; restore ? null; }`.
  Path-keyed, exactly as `configData` is path-keyed (`configData."<path>"` carrying
  `{ mode, reload, computed }`, `docs/plan.md:66`), because the path is the
  identity and needs no second name.
- **`dump` and `restore` are unit references**, not executables: a name the module declared
  itself, checked the way `unitReferenceKeys` are checked, so P2's contract for the common
  case shrinks to "start these two units" instead of an untyped seven-operation plugin.
- **`disposition` is `durable | derived`**, so a snapshot skips caches. systemd's own
  semantics call `CacheDirectory=` disposable, and a snapshot that copies a cache is a bug.
- **The plan entry gains `state`**, absent when empty per the absence rule
  (`docs/plan.md:23-25`), and it enters `keyInput`
  (`lib/plan.nix:454-471`): moving a folder or changing its owner changes the
  rendered unit and the folders a machine must carry, so it re-keys the entry.
- **The realiser renders the directive from the declaration**, never the reverse: a `durable`
  folder under `/var/lib` becomes `StateDirectory=`, a `derived` folder under `/var/cache`
  becomes `CacheDirectory=`, `owner` becomes `User=`, and a folder no directive can express
  without an owner is a diagnostics row rather than a silent omission.
- **Refusals**: a malformed `state`, an unknown or excluded key, a relative path or one under
  the store directory, a disposition outside the domain, an owner failing `atoms.userName`, a
  hook naming a unit the module did not declare, two declarations of one directive (a state
  folder plus a systemd `stateDirectory` extension field on the same unit), and two entries
  on one machine claiming the same or a nested path.

Not in this change, deliberately:

- **`provides.state` / `uses.state` and the platform-shipped `state` interface.** An atom
  carries `type` and `secrecy` only (`lib/interface.nix:23-26`); `locality` is an
  excluded construct whose recorded trigger is "the first export in the target whose value is
  a unix socket path or a loopback port" (`lib/excluded.nix:20-23`). A state
  folder is exactly such a value, so exporting one **forces** locality — the bound, the
  provider tag, and §32.5's three dispositions. Keeping state off the export plane in this
  change leaves that construct unforced and correctly excluded; the follow-up that adds
  `provides.state` is the change that lands it.
- Host-side folder creation for paths outside `/var/lib` (endpoint work, `universe-463.4`),
  the P2 plugin contract itself, snapshot transport, and authoring a backup module.

## Capabilities

### New Capabilities

- `planner/state-declaration`: what a module says about the mutable state it writes, how the
  hooks that dump and restore it are named, and every way the declaration is refused.

### Modified Capabilities

- `planner/plan-artifact`: the entry gains a `state` field and the key contract gains its
  inputs.
- `realiser/portable-service-image`: the rendered unit gains the state directives derived
  from the declaration, and the image refuses a folder it cannot express.
