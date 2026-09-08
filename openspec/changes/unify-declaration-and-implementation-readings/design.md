## Context

See proposal.md — Why for the measured split brain. The mechanics that produce it:

| Reading | Site | `settings` it sees | What is taken from it |
| --- | --- | --- | --- |
| asking half | `lib/compose.nix:27` — `declaration = module { settings = defaults // fixed; }` | defaults + fixed | `provides`: the capability set, what a root re-exports, what an instance may `exposes`, what a `wire` may name |
| implementation half | `lib/resolve.nix:203` — `member.module { settings = settings.values; }` | defaults + deployment + fixed | `impl`, exports, units, the plan's `provides` |

Three constraints shape the approach:

- `compose.mkRoot` already runs **per instance** (`lib/resolve.nix:98`), so the composition step is not shared between instances and may see one instance's settings.
- `service` already returns `defaults` and `fixed` without forcing its declaration (`lib/compose.nix:30-35`), and `resolveSettings` needs nothing but those two and the deployment's literal `settings` attrset. Settings can therefore be resolved before the declaration is forced, with no cycle: the deployment's `settings` is data from `deployment/instances.nix` and depends on no resolution result.
- The corpus's own published module already assumes the target behaviour: `examples/instance-as-group/modules/postgresql/databases.nix:27-31` derives `provides` from `settings.databases`. The subset cannot express its own reference example today.

The root's re-export map is the one place that genuinely cannot survive unchanged: a root that writes `provides.billing = main.provides.billing` names a capability before settings exist. Whole-set forwarding (`provides = main.provides;`) needs no names and was verified working on the probe.

## Goals / Non-Goals

**Goals:**

- One module application per member, against resolved settings, feeding both halves.
- The two postgres scenarios carry no deployment's database names in module files.
- The unreachable failure mode disappears by construction rather than by a new diagnostic: with one reading, the two capability sets cannot differ, so there is nothing left to detect.

**Non-Goals:**

- Handing a root its own settings. A root stays a function of `{ service, ... }`; it forwards a member's capability set instead of computing names from settings. A root that wants to rename a settings-derived capability is out of scope.
- Any change to slots, wiring, arity, secrecy, placement, the diagnostics record shape or the plan schema.
- Deriving a capability set from anything other than settings (a wire, a placement, another instance). The declaration half stays a function of the module and its settings alone, which is what keeps the graph acyclic.

## Decisions

### D1 — `service` is closed over a settings resolver; the declaration is read once

`service` takes the resolver as its first argument and returns the resolved settings and the raw declaration alongside what it returns today:

```nix
  service =
    settingsOf: name: args:
    let
      defaults = args.defaults or { };
      fixed = args.fixed or { };
      settings = settingsOf { inherit name defaults fixed; };
      declaration = args.module { settings = settings.values; };
    in
    {
      inherit name defaults fixed settings declaration;
      module = args.module;
      unknownKeys = util.extraKeys serviceKeys args;
      provides = builtins.mapAttrs (
        capability: declared: declared // { member = name; inherit capability; }
      ) (declaration.provides or { });
    };

  mkRoot = root: settingsOf: root { service = service settingsOf; };
```

`resolveSettings` loses its `member` argument and takes `name`, `defaults` and `fixed` directly, because it now runs before a member value exists; its `values`, `sources` and `rows` outputs are unchanged apart from `member.name` becoming `name` in the row text.

`mkInstance` supplies the resolver, which is the only place that knows the deployment file and the subject strings the rows need:

```nix
          root = compose.mkRoot idecl.module (
            { name, defaults, fixed }:
            compose.resolveSettings {
              inherit name defaults fixed deploymentFile;
              subject = "${iname}:${name}";
              moduleFile = moduleFileOf iname;
              settings = idecl.settings or { };
            }
          );
```

and `mkMember` reads what the member already holds instead of resolving and re-applying:

```nix
          settings = member.settings;

          declaration = module.read {
            inherit reg;
            subject = moduleSubject;
            module = moduleLabel;
            declaration = member.declaration;
          };
```

Everything downstream of `mkMember` is untouched: `settings.rows` still enters `memberRows` (`lib/resolve.nix:296`), and `mkPlacement` already reads the resolved declaration (`lib/resolve.nix:397`).

**Alternative — diagnose the disagreement instead (option B).** Keep both readings and emit a `provides-settings-dependent` row when the two capability keysets differ. Rejected: it does not make the module reusable, and it cannot even report the sharp case. On the probe, wiring a consumer to a deployment-added capability killed the evaluation of `diagnostics` itself with `attribute 'db' missing`, so the row would never be read. It also leaves the duplicate module application in place.

**Alternative — hoist the names into the module's closure.** `scenario.nix` passes `databases` to the root import. Rejected as the endpoint: it de-hardcodes the module file but pins the names at package-instantiation time (`package.nix` with `lib.modules.importApply`), so two deployments of one flake still cannot differ. It is what today's design permits and nothing more.

### D2 — a root forwards a member's capability set rather than naming it

Roots whose capability names come from settings write `provides = main.provides;`. Roots re-exporting statically named capabilities keep writing `provides.identity = client.provides.identity;` — unchanged, and `interfaces.nix`'s re-export-by-value test still describes that path. The member/capability provenance each entry carries (`lib/compose.nix:37-44`) is what makes the forwarded set addressable, so `exposes` and `wire` keep working on the forwarded names.

Rejected alternative: hand the root its resolved settings so it can compute names. It would make a root a second place where settings are read, against the requirement that a root forwards nothing, for no case the corpus has.

### D3 — the scenarios move their names into the deployment

`deployment/instances.nix` writes `settings.main.databases = [ "eu" "us" ]` beside the `exposes` list it already writes. `modules/postgresql/cluster.nix` folds over `settings.databases`, and its file-head comment explaining the two-reading workaround is deleted rather than reworded — it documents behaviour this change removes. `modules/postgresql/default.nix` declares `defaults.databases = [ ]`: a cluster that serves nothing until a deployment names something, so a deployment that forgets the knob gets an `exposes-unknown-capability` row naming an empty provided set instead of inheriting somebody else's two databases.

`exposes` stays an explicit list rather than being derived from the setting. It is the allowlist for cross-instance addressing, and a deployment naming a database is not the same decision as publishing it to siblings.

The names are the applications that own the databases (`billing`, `analytics`) rather than regions. One instance is one cluster: one process, one data directory, one fixed port on one machine, so a capability here is a namespace inside that cluster and a role to reach it, and a region name would claim an isolation the deployment does not have.

### D4 — the performance budget is re-pinned to the measurement, not waived

This decision predicted that removing the second module application would lower the gated counters and that the ratchet would print replacement figures to lower. The measurement falsifies the prediction: the second reading only ever forced a declaration's `provides`, never an `impl`, so it was nearly free, and the per-member settings resolver adds about what it removed. On the worked fixture the whole evaluation moves by less than a tenth of a percent (`nrFunctionCalls` 7955 -> 7959, `nrThunks` 15364 -> 15353). Per plan entry, six of the nine gated counters fall and `nrFunctionCalls`, `envs.bytes` and `gc.totalBytes` rise by at most 0.4%. Because the committed figures were pinned at the previous measurement with no headroom, that hair of a rise fails fourteen gated comparisons.

`perf/budgets.json` is therefore re-pinned to the new measurement with fresh interpreter version and date provenance, in both directions, rather than waived: the margin stays 0.15, no counter is ungated and the growth bound is untouched. The gate keeps measuring what it measured before, against numbers that describe what the library now costs.

## Risks / Trade-offs

- **A root that names a settings-derived capability is now a missing attribute at composition time, uncatchable by `tryEval`** → the two scenario roots are converted to whole-set forwarding in the same change, and `docs/authoring.md` §3 states the rule beside the existing re-export example. This failure mode already exists for a misspelled re-export and is recorded as a deliberate omission in `tests/mapping.nix`.
- **`service` and `mkRoot` are published (`lib/default.nix:68`), so an out-of-tree caller breaks** → **BREAKING**, called out in the proposal; the only in-tree caller is `tests/suites/interfaces.nix:392`, and `docs/README.md:171` documents the new shape. No compatibility wrapper: this repository replaces rather than deprecates.
- **A knob feeding a capability set makes `provides` sensitive to a deployment typo** → the existing `settings-undeclared-knob` row fires on the typo and the member's own declared value is what the set is derived from, which is the third scenario in the delta spec.
- **Settings resolution now happens inside composition, so a resolver that raised would raise earlier than today** → `resolveSettings` builds rows and never raises (the `source` suite already forbids raising calls under `lib/`), and the change adds no call that can.

## Migration Plan

Single commit, no staged rollout: the library, its one in-tree caller, the two scenarios, the budgets and the docs move together. Rollback is a revert; nothing is persisted and no artifact schema changes, so a reverted planner reads the same deployment files it read before — except the two scenarios, which are part of the same revert.

Verification order: the per-row suites (`composition`, `interfaces`, `resolution`) prove nothing regressed in the settings surface, the scenario suite plus pytest prove the deployment-named capability set resolves end to end, and the perf gate supplies the new budget figures.
