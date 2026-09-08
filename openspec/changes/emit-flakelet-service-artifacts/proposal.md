## Why

The plan has one realiser, and it produces a systemd portable service image nothing has ever
attached: every assertion in `tests/python/test_image.py` is bytes with a stub
`portablectl` and a stub `systemctl`. The architecture's second half - a machine actually
running what a plan says - is unproven, and nine open beads under `universe-463.4` (bundle,
verbs, staging, boot persistence, locking, delivery, VM proof) exist to build the host side by
hand.

flakelet (`~/Projects/flakelet`, beta, running production services) already is that host side:
generations under `/nix/var/nix/gcroots/flakelet/<name>/gen-<N>/`, per-entry and global flocks,
atomic state, `flakelet-boot.service` re-linking units out of a tmpfs, rollback, anti-flapping
holds, gc retention. Its `activate`/`prebuilt` seam consumes a **directory layout**, not an
adios module: `manager.rs:1349-1392` reads `units/`, then optional `generators/`,
`exports.json`, `state.json`, and `meta.json` is three optional strings
(`manager.rs:1252-1267`).

A throwaway spike measured on 2026-09-07 that the gap between the plan and that seam is one
rendering rule. From a plan evaluated by `planner.mkPlan`, `image/read.nix`'s existing
`renderUnit` output, wrapped in a `linkFarm`, activated in a NixOS VM and served an HTTP
request:

```
machine # flakelet[762]: spike-web: activating generation 1
machine # flakelet[762]: spike-web: updated to generation 1
machine: must succeed: curl -sf http://localhost:8080/ > /dev/null   (finished, 0.05s)
machine: flakelet status --json → "generation": 1, "last_error": null
subtest: the unit survives a reboot                                  (finished, 12.80s)
```

Three facts came out of that spike and they are why this change is small:

- **The naming already fits.** `nameOf = "${instance}-${service}"` (`image/read.nix:115`) and
  `unitFileName = "${name}-${unit}.service"` (`:159`) satisfy flakelet's `validate_name`
  (`manager.rs:1301-1312`) and `validate_units` (`:1314-1326`) unchanged. No mapping layer is
  needed - only a refusal for a name whose characters those validators reject.
- **The renderer is the backend.** `image/default.nix:43-57` already writes exactly these unit
  files and only then reaches for `mksquashfs`. Dropping the squashfs is the whole builder.
- **One thing is genuinely missing.** `renderUnit` emits `[Unit]` and `[Service]` only
  (`read.nix:415-437`). flakelet enables and starts per `[Install]` and deliberately leaves a
  unit without one to systemd, so a plan-rendered unit would be linked and never started.

## What Changes

- **A second realiser**: `flakelet/` turns one placed plan entry into a flakelet
  service artifact - `units/` plus `meta.json` - reusing `image/read.nix`'s `read`, `renderUnit`
  and `renderTimer` so the closure grammar and the unit rendering keep one definition in this
  repository.
- **Enablement becomes the binding's decision**: a long-running unit renders
  `[Install] WantedBy=multi-user.target`; a scheduled unit's **timer** carries
  `WantedBy=timers.target` and its service carries none, so deploying a scheduled service does
  not fire it. The plan keeps saying `schedule`; what enablement means is the backend's answer.
- **`meta.json` carries the plan's identity**: `flake_url = "plan:<entry key>"` and
  `settings_hash = <the entry's version digest>`. This is not decoration - the prebuilt branch
  of `update` reads our `meta.json` and compares that field to decide whether anything changed
  (`manager.rs:1023-1035`), so the plan's own identity drives the endpoint's no-op.
- **Refusals before bytes exist**: an entry whose derived name or unit file names the endpoint's
  validators would reject is a raise naming the entry, the name and the rule, the way every
  refusal on the realiser side raises.
- **A host file is a refusal too**: measured while building the worked deployment's own entries -
  `image/read.nix` renders `BindReadOnlyPaths=/run/portable-planner/<name>/files<path>` for a
  configuration file, and that directory is assembled by the image realiser's attach script.
  flakelet reads `units/` and `meta.json`, links and starts (`manager.rs:1349-1392`); there is no
  step in between. An entry shown a host file is therefore refused, naming the entry, the path and
  the missing step, rather than shipped as a unit that cannot start.
- **An end-to-end check**: a NixOS VM test that activates a planner-built artifact, reaches the
  service, survives a reboot and rolls back to a previous artifact - the first test in this
  repository where a real service manager runs what a plan said.

Not in this change, deliberately:

- **`state.json`.** The spike's own `flakelet status --json` reported
  `"export_blockers": [ "generation was built without state.json, redeploy it" ]`, so
  `export`/`import` and state migration stay unavailable until `declare-service-state` lands and
  gives the entry a state field to render from. Named dependency, not an oversight.
- **The library route.** `Manager::new(config: Config)` takes a value (`manager.rs:146-151`), so
  a later `hostd` can build desired state from the plan in memory - which is what makes
  set-arithmetic removal and plan-as-sole-authority possible without changing flakelet. This
  change stays on the `prebuilt` seam because the Nix half is identical either way; design.md
  records the trigger that moves us.
- **Delivery** (`nix copy` to a real host), **`exports.json`**, **group gates and cross-entry
  ordering** (P7, `universe-4k3`), and **non-systemd targets**.
- **Removing the portable-service image realiser.** Two realisers over one plan is the point:
  the image serves the store-less tier, and keeping both is what proves the plan is a contract
  rather than one builder's input format.

## Capabilities

### New Capabilities

- `realiser/flakelet-artifact`: what a flakelet service artifact built from one plan entry
  contains, how enablement is decided, what identity it carries, what it refuses, and what a
  real endpoint does with it.
