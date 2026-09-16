## Why

`README.md:17-20` states three design goals in three lines: instantiating a service multiple times
should be possible, multiple instances having their own PostgreSQL should be possible, and multiple
instances sharing one should be possible. `tests/e2e/shared-postgres/` proves the third and only the
third. The first two are contradicted by the folder's own text:

- the cluster module writes one absolute configuration path for every instance of itself,
  `configData."/etc/postgresql/postgresql.conf"`
  (`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:101`);
- its data directory is a literal default, `/var/lib/postgresql/data`
  (`.../modules/postgresql/default.nix:14`), with the second instance's written out by hand as
  `/var/lib/postgresql/own` (`.../modules/app/default.nix:18`);
- both instances fix the same port, `fixed.port = 5432` (`.../modules/postgresql/default.nix:18` and
  `.../modules/app/default.nix:20`);
- so the two clusters cannot be placed on one machine, and the folder does not place them there: the
  private one is on `beta` by tag (`.../instances.nix:71-73`) and the shared one on `alpha`. Two
  instances of one module on one machine is therefore untested, and the deployment that would test it
  is one the module as written cannot express.

The deployment also states file plumbing the reader of a deployment should never see:
`recordPath = "/run/shared-postgres/near.json"` three times (`.../instances.nix:34,50,66`), and the
consumer module then derives its runtime directory back out of that string with
`baseNameOf (dirOf settings.recordPath)` (`.../modules/app/client.nix:65`). An operator is being
asked for a path so that a module can recover a directory name it already knows.

Two claims the folder does make are already real and are not re-litigated here: the machines are
rookery VMs resumed from a snapshot cut
(`tests/e2e/shared-postgres/test_shared_postgres.py:214-223`, `delivery.cluster_stage`), and the
applications genuinely speak SQL to a real server - `psql` writes a row and reads it back over the
recorded address (`.../deployment/consume.sh:19-56`) against `postgres` started from the entry's own
closure (`.../modules/postgresql/databases.nix:121-134`). What is missing is the second cluster
beside the first, and the proof that each application reached the one it wired and not the other.

## What Changes

- **Two instances of one database module run on one machine.** `own-app` is placed on the machine
  that already holds the shared cluster, so `alpha` runs four entries: the shared cluster, the
  consumer that shares its machine, the private cluster and the application that owns it. `beta`
  keeps the remote consumer, so the "working consumer outside one delivery set" claim is unchanged.
- **Every host path is derived by the module from its own entry identity.** The data directory, the
  unix socket directory, the configuration file path, the consumer's record and the runtime directory
  that holds it are all built from `instance` and `member`, which
  `refuse-two-entries-claiming-one-host-resource` hands the implementation. No module carries an
  absolute path with no interpolation in it, and no two entries of one machine claim one path.
- **The deployment states intent only**: which databases exist and who owns them, each consumer's
  label, and the port of the second cluster. It states no path. `recordPath` is deleted as a knob,
  and the consumer's runtime directory stops being reverse-engineered from it.
- **A port is a default rather than a fixed fact.** The leaf keeps `5432` as a default and the
  private instance states `5433`, because the planner allocates nothing (`lib/excluded.nix:32-35`) and
  two listeners on one machine need two ports. The module's `url`-shaped export is still built from
  the resolved value, so nothing about the data source changes.
- **The test reads paths off the plan.** The configuration path comes from the entry's `configData`
  keyset, the data directory and the record path from the units' recorded environment. No absolute
  path is written in `test_shared_postgres.py`.
- **New assertions, all against the machines**: the two clusters are two processes with two data
  directories, two ports and two sockets on one machine; each application's row is in the cluster it
  wired and the other cluster's `system_identifier` differs; the shared cluster carries no `private`
  database and the private one carries neither `eu` nor `us`; a credential of the shared cluster is
  refused by the private one.

## Capabilities

### New Capabilities

<!-- none: the folder's claims belong to capabilities that exist -->

### Modified Capabilities

- `delivery/real-cluster`: two instances of one module deployed to one machine with no shared host
  resource, each application reaching the instance it wired and no other, and the deployment stating
  no host path.
- `tooling/test-layers`: the folder's shape after the move - which machine holds what, which stage
  key moves, and the space a machine running two clusters declares.

## Impact

- `tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix`: paths derived from
  `instance` and `member`; the port claim reads a defaulted knob.
- `.../modules/postgresql/default.nix`, `.../modules/app/default.nix`: the `dataDir` and `recordPath`
  defaults are deleted, the port becomes a default, and the app root composes the private cluster
  without naming a path.
- `.../modules/app/client.nix`: the record path and the runtime directory are derived; `settings.label`
  is the only knob left.
- `.../deployment/instances.nix`: `own-app` placed beside the shared cluster with its own port, and
  no path in the file.
- `.../deployment/machines.nix`: the tag that places the private instance on `alpha`.
- `.../deployment/init.sh`, `.../deployment/consume.sh`: unchanged in what they do; the socket
  directory and `PGDATA` arrive in the environment as they already do.
- `tests/e2e/shared-postgres/test_shared_postgres.py`: path constants deleted and read off the plan;
  the private cluster's keys and its value's delivery set move from `beta` to `alpha`; the new
  scenarios above; `disk_gib` raised for the machine that now holds two data directories, which
  re-keys this folder's cut and no other (`CLAUDE.md`, machine layer snapshots).
- `tests/unit/layers.nix`: `statefulFolders` recognises a folder by the text `dataDir`
  (`tests/unit/layers.nix:700`). The derived directory keeps a name carrying that text, or the
  detection is changed with it; a folder that writes state and is no longer recognised makes
  `undeclaredSpace` pass vacuously.
- `tests/unit/coverage.nix`: this change's two spec files in `accountable`.
- `CLAUDE.md`: the folder's invariants that move - the port is a default and why, the paths are
  derived, and which machine holds which cluster.
- No file under `lib/`, `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. The one
  library fact this change needs is `member` in the implementation arguments, which
  `openspec/changes/refuse-two-entries-claiming-one-host-resource` carries; that change lands first
  and its rows are what keeps a future collision from being silent again.
