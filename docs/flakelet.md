# The flakelet service artifact

The second realiser over one unchanged plan. It turns one placed plan entry into the directory
layout [flakelet](https://github.com/Mic92/flakelet) already activates — unit files and a metadata
document — for a machine that runs a service out of its own store rather than out of an image.
The other realiser, [the portable service image](../image/), serves the store-less tier; nothing
in the plan tells the two apart, which is the claim keeping both of them is evidence for.

```
nix build .#planner-e2e-wired-pair                # four artifacts, from the end-to-end fixture
nix build .#checks.x86_64-linux.planner-tests     # their bytes, per case, in tests/unit/flakelet.nix
nix run .#planner-e2e wired-pair                  # a real endpoint runs them, see cluster.md
```

## The layout

`flakelet/default.nix` writes exactly two names, because that is what the endpoint
reads (`manager.rs:1349-1392`: `units/` is required, `generators/`, `exports.json` and
`state.json` are optional, and `meta.json` is three optional strings at
`manager.rs:1250-1267`):

```
<artifact>/
<artifact>/meta.json
<artifact>/units
<artifact>/units/svc-only-web.service
```

A unit file is `<instance>-<service>-<unit>.service`, and a scheduled unit adds
`<instance>-<service>-<unit>.timer` beside it. Those names are `image/read.nix`'s
`unitFileName` and `timerFileName` (`:142-143`) unchanged: they already satisfy the endpoint's
`validate_name` and `validate_units` (`manager.rs:1301-1326`), which is why this realiser refuses
a name rather than mapping one.

The unit text is `image/read.nix`'s `renderUnit` (`:446-491`) plus one section:

```
[Unit]
Description=svc:only web

[Service]
ExecStart=/nix/store/97d5ygrvqj55f4nx1x34wfdcc7qn11c0-coreutils-9.11/bin/sleep infinity
TimeoutStartSec=30m
Environment=LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
```

Activating it needs no evaluator, no service-flake source and no network: the units name store
paths and the artifact's closure carries them, which `nix path-info -rS
.#planner-e2e-wired-pair` shows.

## Enablement is the backend's decision

The plan says *when* a unit runs — a `schedule` or nothing. What "enabled" means is the backend's
answer, and the two realisers give different ones:

| Entry | flakelet artifact | portable-service image |
| --- | --- | --- |
| a long-running unit | `[Install] WantedBy=multi-user.target` | no `[Install]`; `portablectl attach` then `systemctl start` |
| a scheduled unit | the **timer** carries `WantedBy=timers.target`, the service carries nothing | no `[Install]` on either |

flakelet links every unit into `/run/systemd/system`, then enables and starts the ones that carry
an `[Install]` section and leaves the rest to systemd, to be pulled in on demand by a socket or a
timer (`systemd.rs:166-170`). An `[Install]` on the service of a scheduled unit would therefore run the
job once at deploy time and again on its schedule - which is why
`tests/unit/flakelet.nix`'s `testAScheduledUnitIsNotFiredByDeployingIt` reads the two rendered
files, and why `tests/e2e/wired-pair/test_wired_pair.py` asserts the same thing on a real machine:
`test_a_scheduled_unit_is_not_fired_by_deploying_it` finds an empty `ExecMainStartTimestamp` and
`test_the_timer_the_schedule_declares_is_enabled` finds the timer listed.

The section is rendered in `flakelet/read.nix` and nowhere else: `image/read.nix` is untouched, so
a `wantedBy` field never enters the plan's unit vocabulary and one backend's enablement model does
not become a plan fact (design.md D2 of this change).

## The identity the endpoint compares

`meta.json` is the three fields flakelet reads back, plus its own `version` and `name`:

```json
{"flake_rev":"","flake_url":"plan:svc:only@one","name":"svc-only","settings_hash":"4bd7d4046677e9b1","version":1}
```

- **`flake_url`** is `plan:<entry key>`. Its only consumer is display and provenance — the same
  spirit as flakelet's own `prebuilt:<name>` default (`Mic92/flakelet/lib/artifact.nix`) — and it
  is what `flakelet status --json` shows as `locked_url` (`manager.rs:379-380`).
- **`settings_hash`** is the entry's version digest from `image/read.nix:264-280`, which digests
  what the artifact is made of: name, units, closure, store directory, service manager, host paths
  and platform. It is carried into the generation the endpoint records
  (`manager.rs:1030-1036`, `generations.rs:14-18`), so what a machine reports about a running
  artifact is a plan fact.
- Deliberately **not the entry's key**: a key moves when a configuration file's content hash
  moves, and that content never enters the artifact, so keying on it would restart a service whose
  bytes are unchanged (`image/read.nix:109-120`).

A redelivery therefore decides by that digest rather than by a rebuild.
`tests/unit/flakelet.nix`'s `testAChangedUnitFieldIsANewGeneration` reads one entry twice for one
version and a changed unit field for another; on real machines the same decision is
`tests/e2e/wired-pair/test_wired_pair.py`'s `test_an_unchanged_entry_is_a_no_op`, which leaves
generation 1 and the running process alone, and `::test_a_changed_entry_is_a_new_generation`.

## What it refuses

Every refusal is a raise while the artifact is being evaluated, before any file exists: the suite
forces the read with `deepSeq` under `tryEval` and asserts that it did not succeed
(`tests/unit/flakelet.nix`'s `raises`, used by `testAnUnusableInstanceName`,
`testAUnitNameOutsideTheServicesNamespace` and `testAnEntryShownAConfigurationFile`), so no
derivation is instantiated either.

| Refusal | Rule |
| --- | --- |
| a derived service name the endpoint would reject | `validate_name` (`manager.rs:1301-1312`): at most 128 characters, first an ASCII alphanumeric, then alphanumerics, `-` and `_`; no dots |
| a unit file name outside the service's namespace | `validate_units` (`manager.rs:1314-1326`): the base is the service name or begins with `<name>-`, with at most one `@` |
| an entry shown a host file it would have to assemble | this realiser runs no step on the machine, and a configuration file's bytes are assembled by the image realiser's attach script (`image/default.nix:101-133`); flakelet has no such step |

The name refusals are the endpoint's own rules, restated where the deployment can be told about
them. The host-file refusal is this realiser's own limit, and it is narrower than a ban on host
paths: a **delivered** generated file is its own source, so `from` equals `path` and the bytes are
already at that path before the entry is activated. Only a path this realiser would have to
create - a configuration file assembled from the plan - is refused. The worked deployment's four
entries all render one, so they are built by the image realiser instead (design.md D7);
`tests/e2e/secret-delivery/` is the case that is not, and it is a flakelet artifact.

A delivered value's bytes are also why the artifact holds none of them. `image/read.nix` refuses
an environment value carrying a newline and quotes every other one, so what the unit records is a
path and never the content behind it.

Everything else a plan can be wrong about is already refused by the shared reading
`image/read.nix`, one definition for both realisers: an undeclared store path, a closure root that
is a reference, a machine that does not run systemd, an entry with no unit.

## Deliberately absent

- **`state.json`.** flakelet's `export`/`import` needs it and reports its absence itself: the
  throwaway spike's `flakelet status --json` answered
  `"export_blockers": [ "generation was built without state.json, redeploy it" ]`. Writing one
  needs a state field on the entry, which the `declare-service-state` change adds. Named
  dependency, not an oversight.
- **`exports.json`.** It would put a second wiring engine on the machine, resolving claims against
  `/etc/flakelet/providers.d` at activation time, while this architecture resolves wires at
  evaluation time with typed values and hands the result to the unit as a value
  (`docs/plan.md`). The field is optional to the endpoint (`manager.rs:1378-1383`), so leaving it
  out costs nothing.
- **Removal.** Under the `prebuilt` seam, `/etc/flakelet/config.json` is written by flakelet's own
  NixOS module, so an entry the plan drops is removed by that module rather than by anything here.
  Set-arithmetic removal and the plan as sole authority are what the library route
  (`Manager::new(config: Config)`, `reconcile`) buys, and design.md D1 records the trigger.
- **Delivery.** Copying an artifact's closure to a real host is `nix copy`, and no script here
  wraps it.
