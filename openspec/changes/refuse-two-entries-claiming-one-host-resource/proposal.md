## Why

An entry's key is `<instance>:<member>@<machine>`, and the library already holds that two entries of
one machine are two different things: `image/read.nix:179-182` says the unit-file prefix
`<instance>-<service>` is "collision-free by construction rather than by convention". Nothing holds
the same for what those entries claim *on the machine*. A host path a module writes is
`configData.<path>` (`lib/module.nix:85`), a port is `claims.ports.<name>.fixed`
(`lib/module.nix:115-119`), and a directory the service manager creates for a unit is an extension
field (`image/read.nix:82-83`). Two entries on one machine may claim the same one of each, and the
plan is produced with no row.

The failures that follows are silent and already observed. `CLAUDE.md` records one of them as a fixed
bug: "the service manager deletes a runtime directory when its unit restarts, so two instances
sharing one name on a machine lose each other's records, which is how `own-app` first failed". The
fix was a convention inside one test folder
(`tests/e2e/shared-postgres/deployment/modules/app/client.nix:65`), not a rule the planner holds, so
the next module to hardcode `/etc/postgresql/postgresql.conf`
(`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:101`) re-earns it. Two
entries writing one host path is two renderings of one file where the second apply wins; two entries
claiming one fixed port is a daemon that cannot bind and no plan field that says why. Both are
diagnosable from the plan alone, before anything is dialled.

A module that wants to avoid the collision cannot fully do so today either. `implArgs`
(`lib/resolve.nix:1199-1206`) hands an implementation `instance`, `machine`, `settings`, `alloc`,
`vars`, `results` and `target` - every part of its own entry key except the member it is. A leaf that
derives a path from `instance` alone is still wrong the moment a root composes two of it
(`tests/e2e/shared-postgres/deployment/modules/app/default.nix:15-31` composes one database and one
client; a second database in that root would collide with the first).

## What Changes

- **A host resource claimed by two entries on one machine is a diagnostics row.** Three claims are
  read off what the plan already records, so no new plan field and no new module vocabulary is
  introduced:
  - `entry-host-path-claimed-twice` (error): two entries placed on one machine declare one
    `configData` host path.
  - `entry-port-claimed-twice` (error): two entries placed on one machine claim one fixed port with
    one protocol.
  - `entry-unit-directory-shared` (warning): two entries placed on one machine declare one unit
    directory name under `runtimeDirectory`, `stateDirectory` or `cacheDirectory` in an extension
    application. A warning rather than an error, because a shared state directory is a plausible
    handoff between two entries while a shared runtime directory is the data loss `CLAUDE.md`
    records - the row names it, the build still happens.
- **A row is per machine, and one entry placed on many machines is one claim.** The same member
  placed on two machines claims its path on each of them and is not a collision with itself.
- **An implementation is handed the member it belongs to.** `implArgs` gains `member`, so a leaf can
  derive a unique path from the pair that identifies its entry (`instance`, `member`) without the
  root having to pass its own name down through settings. No plan field and no key input changes: the
  key already hashes `instance` and `service` (`lib/plan.nix:661-662`).
- **No allocation, no path convention.** The planner still chooses nothing: it does not invent a
  path, does not pick a port, and does not publish `paths.state`-style helpers. A second instance's
  port remains a fact the deployment states, which is the `dynamicPort` excluded construct
  (`lib/excluded.nix:32-35`) and is where it stays until the allocation table lands.

## Capabilities

### New Capabilities

<!-- none: both rows and the argument addition belong to capabilities that exist -->

### Modified Capabilities

- `planner/diagnostics`: a host resource two entries of one machine both claim is a row, with the
  three claims the plan records, the per-machine scope, and the negative case of one member placed on
  two machines.
- `planner/plan-artifact`: an implementation is handed the member it belongs to, beside the machine
  it was planned for, so a module can derive a per-entry name.

## Impact

- `lib/plan.nix`: the per-machine claim index and its rows, built in `entries` (`lib/plan.nix:877-964`),
  which is the one site that holds every placed entry at once. `placedEntry` grows a `claims` field
  beside `name`, `rows` and `value`; `pruned` drops empty records, so the index reads the pre-pruned
  values rather than the plan. Grouping is by machine and then by claim, so the cost is linear in
  entries and stays inside the perf budgets (`perf/`, margin 0.15 at sizes 4/16/64/256).
- `lib/resolve.nix`: `member` added to `implArgs` (`lib/resolve.nix:1199-1206`).
- `tests/unit/`: one suite gains the four scenarios; `diagnostics.nix`'s purity scan and its row-versus-refusal
  cross-walk already cover new rows by construction, and the new rows fire nowhere in
  `fixtures/minimal-typed-edge` or `perf/` (one hub per fleet, one port claim per machine, one
  `configData` path per machine), so no golden plan or golden diagnostics table moves.
- `tests/unit/coverage.nix`: this change's two spec files in `accountable`.
- `docs/`: the two new row identifiers where the row table lives.
- `CLAUDE.md`: the rule and why the directory row is a warning while the other two are errors; and
  `member` beside `instance` under the implementation arguments.
- Nothing under `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. A realiser is
  handed the same plan; what changes is that a deployment which would have produced two writers of
  one file now carries an error row and does not build.
