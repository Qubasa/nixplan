## Context

See proposal.md - Why, including the spike measurement. The constraints that shape the approach:

- `image/read.nix` is a pure function of the plan and raises rather than defaulting (`:1-13`).
  `read` returns `units`, each carrying `file`, `timer`, `directives` and the entry's `record`
  (`:370-388`), and `renderUnit`/`renderTimer` turn one of those into text (`:394-455`). The
  squashfs is the only part of `image/default.nix` that is not shared.
- flakelet's `read_contents` requires a non-empty `units/` and accepts optional `generators/`,
  `exports.json` and `state.json`; `meta.json` is `{ flake_url, flake_rev, settings_hash }`, all
  `serde(default)` (`manager.rs:1252-1267`, `:1349-1392`).
- The prebuilt branch of `update` does no Nix at all: it checks the path exists, loads our
  `meta.json`, and carries `settings_hash` into the comparison that decides whether to switch
  (`manager.rs:1023-1035`).
- `validate_name` is `[A-Za-z0-9][A-Za-z0-9_-]{0,127}` with no dots (`manager.rs:1301-1312`);
  `validate_units` requires each unit's base to equal the service name or start with
  `<name>-`, with at most one `@`, and the suffix to be one of service, socket, target, timer,
  path (`:1270`, `:1314-1326`).
- Activation is whole-entry: stop, unlink, symlink the new units into `/run/systemd/system`,
  `daemon-reload`, then enable and start per `[Install]` (`design.md:123-133` in that repository).

## Goals / Non-Goals

**Goals:**

- One realiser that a real service manager runs, with the reading shared with the image realiser
  rather than duplicated.
- The endpoint's change detection driven by the plan's own identity.
- An end-to-end check that would fail if any link in plan → unit → activation → reboot broke.

**Non-Goals (design-level):**

- No second reader. If a fact is needed, it is added to `image/read.nix` and both realisers see
  it; a `flakelet/read.nix` exists only if the enablement rule and the name refusal grow past a
  handful of lines.
- No host-side tooling. This change writes no bundle, no delivery script and no state file; the
  endpoint is flakelet's own binary, invoked as it already is.
- No change to the plan's vocabulary. Everything here is a rendering decision.

## Decisions

**D1. The `prebuilt` seam now; the library route when removal or authority forces it.**
`services.<name>.prebuilt` and `flakelet activate` take a store path and evaluate nothing, which
is what the spike used and what this change ships.
*Alternative: link `flakelet-core` from our own `hostd` immediately.* Deferred, with the trigger
stated so the decision is not re-litigated: `Manager::new(config: Config)` takes a value
(`manager.rs:146-151`), an entry present in that `Config` is `Origin::Declarative`
(`:270-271`), and `reconcile` removes declarative entries no longer in it (`:583-596`). The
library route is therefore what makes **set-arithmetic removal** and **the plan as sole authority**
possible - and additionally leaves the machine unable to evaluate at all, since a hand-built
`Config` bypasses the `adios`/`flakelet_lib` requirement `Config::load` enforces
(`config.rs:129-131`). Move when either of those is needed. **The Nix half of this change is
identical under both routes**, which is why shipping the seam first costs nothing.
*Consequence to state plainly:* under this route `/etc/flakelet/config.json` is written by
flakelet's NixOS module, so an entry the plan drops is not removed by anything. Removal is
therefore absent from the spec rather than asserted, and it is the first thing the library route
buys.

**D2. `[Install]` is rendered by the binding, not added to the unit vocabulary.**
The plan already says `schedule`; whether "enabled" means `multi-user.target`, a timer, or
`portablectl attach` is the backend's answer, and the portable-service realiser wants no
`[Install]` at all. Putting it in the vocabulary would make one backend's enablement model a plan
fact.
*Alternative: a `wantedBy` unit field.* Rejected - it names a systemd target in a portable
vocabulary, and the corpus already refuses that class of leak (`§16.7`).

**D3. Names are refused, not mapped.**
Measured: `nameOf` and `unitFileName` already satisfy both validators for names made of
`[A-Za-z0-9_-]`. A mapping layer would introduce a second identity for one entry and a collision
class (`a:b` and `a-b` both mapping to `a-b`) that does not exist today.
*Alternative: normalise unusable characters.* Rejected for exactly that collision, and because a
refusal names the deployment's mistake where it was written.

**D4. `meta.json` carries the plan key and the entry version.**
`flake_url = "plan:<key>"` reuses a field whose only consumer is display and provenance, in the
same spirit as flakelet's own `prebuilt:<name>` default. `settings_hash = image.version` is
load-bearing rather than cosmetic: it is the field the endpoint compares. The entry's `version`
is the right value because it digests what the artifact is made of - name, units, closure, store
directory, service manager, host paths, platform (`read.nix:117-127`): an equal version therefore
means equal bytes.
*Alternative: the entry's `key`.* Rejected for the reason `read.nix` already gives: a key moves
when a configuration file's content hash moves, and that content is not in the artifact, so
keying on it would restart a service whose bytes are unchanged.

**D5. Both realisers stay.**
The image serves the store-less tier and the artifact serves the store-backed one, over one
unchanged plan. Keeping both is the strongest available evidence that the plan is a contract; the
day the plan needs a field for only one of them is the day that claim is in trouble.

**D6. No `exports.json`, no `state.json`, on purpose.**
`exports.json` would put a second wiring engine on the machine, resolving claims against
`/etc/flakelet/providers.d` at activation time, while this architecture resolves wires at
evaluation time with typed values. `state.json` needs the entry field `declare-service-state`
adds; until then `export`/`import` is blocked, which the endpoint reports itself.

**D7. A host path is refused, because the step that would serve it is the image realiser's.**
Measured, not anticipated: building the worked deployment's `vault-repo:server@vault` produced
`BindReadOnlyPaths=/run/portable-planner/vault-repo-server/files/srv/borg/.ssh/authorized_keys:...`,
a path the image realiser's attach script assembles (`image/default.nix:101-133`) and nothing on a
flakelet host does. The endpoint reads `units/` and `meta.json`, links and starts
(`manager.rs:1349-1392`), so a unit rendered this way would fail at start.
*Alternative: render the bind from the plan's own path.* Rejected for the half that has no answer:
a configuration file's bytes exist only where something assembles them, and this change writes no
host-side tooling (Goals / Non-Goals). *Alternative: ship it and document the gap.* Rejected -
every other missing fact on this side is a raise naming the entry, and a unit that cannot start is
worse than no artifact.
*Consequence:* the worked deployment's four entries are all refused here, so the fixtures and the
demonstration package are entries that are shown no host file. The refusal is what the assembly
step's absence looks like from the outside, and it is the second thing the host-side work buys
after `state.json`.

## Risks / Trade-offs

- **flakelet is beta and says its interface may still change** → the input is pinned to a
  revision, the fields we write are the three `serde(default)` ones plus a directory layout, and
  the VM check fails loudly if the seam moves. Nothing in this change reaches into its internals.
- **Per-entry atomicity** → two entries of one machine can be half-updated; group gates are P7's
  (`universe-4k3`) and are named as out of scope rather than silently assumed.
- **A store and a daemon are required on the target** → this realiser does not serve the
  embedded tier; that is the image realiser's job, which is why D5 keeps it.
- **Removal is not provable under D1's route** → stated in the spec by omission and in D1 by
  name, so nobody reads the VM check as proving desired-state convergence.
- **The endpoint may start a unit the plan did not intend to run** → the scheduled-unit scenario
  exists precisely to pin that, because getting `[Install]` wrong on a timer fires a backup job
  at deploy time.

## Migration Plan

Additive: a new builder, a new flake input, a new check. No existing output changes shape, the
image realiser is untouched, and the plan is unchanged, leaving nothing to migrate and nothing to
roll back beyond removing the new outputs.

## Open Questions

- Whether the flakelet input is pinned to `github:Mic92/flakelet` or vendored. Pinning is assumed
  in the tasks; vendoring changes only the input line and not the specs, the approach or the task
  breakdown.
