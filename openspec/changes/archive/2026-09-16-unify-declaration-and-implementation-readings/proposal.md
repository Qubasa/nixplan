## Why

A leaf module is read twice with two different settings values, and the two readings disagree about which capabilities exist. `lib/compose.nix:27` reads the module against `defaults // fixed` and takes the capability set from it; `lib/resolve.nix:203` reads the same module against resolved settings (`defaults // deployment // fixed`) and takes the exports, units and the plan's `provides` from it. A deployment can therefore change the value inside an export but not which capabilities an instance offers, so every module whose capability set is a user choice — a database per schema, a vhost per site, a network per zone — has to bake the names into module source. `tests/scenarios/*/modules/postgresql/default.nix:12-15` writes `[ "eu" "us" ]` for exactly this reason, which makes that module unusable by anyone who does not run those two databases.

Measured on a probe copy of `shared-postgres` whose cluster derives `provides` from `settings.databases`: with the deployment writing `settings.main.databases = [ "eu" "us" ]` over a default of `[ "eu" ]`, the plan published `pg:main@one.provides.us` with full exports and `keysetEqualsInterface: true`, while the instance layer reported `exposes-unknown-capability: instance 'pg' exposes 'us', which its root does not provide`. Wiring an application to that same capability took the whole artifact down with `error: attribute 'db' missing … server.nix:27`, because the wire was refused against the asking half's smaller set and a refused read is uncatchable. The disagreement has no diagnostic; the invariant is written down only as prose inside a scenario module comment.

## What Changes

- A member's declaration is read **once**, against the settings the instance actually runs with, so the capability set a root publishes and the exports its `impl` produces come from one value. The `exposes`/`wire` layer and the plan can no longer disagree.
- The set of capabilities an instance provides may depend on a member's settings. A knob a capability set is derived from stays an ordinary default or fixed value, so `settings-undeclared-knob` and `settings-fixed-path` keep covering typos and fixed-path writes.
- **BREAKING** `service` is closed over the resolver that turns a member's own `defaults` and `fixed` into resolved settings, and `mkRoot` takes that resolver as a second argument. Both are part of the published library surface (`lib/default.nix:68`), so a caller building roots outside a deployment passes a resolver.
- A root that re-exports a settings-derived capability forwards the member's whole set (`provides = main.provides;`) instead of naming each capability. Roots re-exporting statically named capabilities are unaffected.
- The two postgres scenarios stop hardcoding database names: the list moves to `deployment/instances.nix` as `settings.main.databases`, and the module files carry no deployment's names.
- One module application per member disappears. Measured, the change is cost-neutral rather than cheaper: the removed reading only ever forced a declaration's `provides`, and the per-member settings resolver costs about what it saved, so six of the nine gated counters fall and three (`nrFunctionCalls`, `envs.bytes`, `gc.totalBytes`) rise by at most 0.4%. `perf/budgets.json` is re-pinned to the measurement with fresh provenance.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `planner/typed-edge`: the requirement "A composition decides which settings a deployment may move" gains the single-reading rule and the consequence that a capability set may be derived from resolved settings. Today's behaviour — the asking half read against defaults and fixed alone — is what the change removes.

## Impact

- `lib/compose.nix`: `service` gains the resolver argument and returns the member's resolved settings and its declaration; `resolveSettings` takes `name`, `defaults` and `fixed` directly instead of an already-built member; `mkRoot` gains its second argument.
- `lib/resolve.nix`: `mkInstance` builds the per-member resolver from the deployment's `settings` and hands it to `mkRoot`; `mkMember` stops resolving settings and stops re-applying the module, reading what the member already holds.
- `lib/default.nix`: the published `service` and `mkRoot` change shape.
- `tests/suites/interfaces.nix:392` and any other direct `mkRoot`/`service` call in the per-row suite.
- `tests/scenarios/shared-postgres/` and `tests/scenarios/two-readers-one-database/`: root, cluster and deployment files; the pytest modules gain the assertion that the deployment's list decides the published capability set.
- `perf/budgets.json`: lowered figures with fresh provenance.
- `docs/authoring.md` (§3 Roots), `docs/README.md:171`: the composition surface and what a root may derive from settings.
- No change to interfaces, slots, wiring, placement, the diagnostics record shape or the plan artifact schema.
