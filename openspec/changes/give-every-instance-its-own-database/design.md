## Context

See `proposal.md` - Why. The constraints that decide the shape:

- A default cannot see the instance. `lib/compose.nix:30-31` reads a declaration as
  `module { settings = settings.values; }`, and the `defaults` and `fixed` a root writes
  (`tests/e2e/shared-postgres/deployment/modules/postgresql/default.nix:13-19`) are written in the
  composing module, which does not know which instance a deployment will make of it. A path can
  therefore not be a derived default; it has to be derived where the identity is, which is the
  implementation. `implArgs` hands `instance`, `machine`, `settings`, `alloc`, `vars`, `results` and
  `target` (`lib/resolve.nix:1199-1206`), and `member` arrives with
  `openspec/changes/refuse-two-entries-claiming-one-host-resource`.
- A port cannot be derived at all. `claims.ports.<name>.fixed` is read in the declaration half
  (`tests/e2e/shared-postgres/deployment/modules/postgresql/databases.nix:26-30`), which sees only
  settings, and the planner allocates nothing (`lib/module.nix:346-350`, `lib/excluded.nix:32-35`).
  Two listeners on one machine therefore need two stated numbers.
- The machine layer's guest image owns the `postgres` account and its home,
  `/var/lib/postgresql` at mode 700 (`tests/e2e/guest.nix:145-152`). Two clusters can each own a
  subdirectory of it; neither can create the parent.
- One case is one ssh command (`tests/e2e/shared-postgres/test_shared_postgres.py:24-28`): the guest's
  sshd is per-connection socket activated and a burst of logins hits the socket's trigger limit.
- A stage's shape, memory, cpus, `offline` and `disk_gib` are all part of the snapshot cut's key
  (`tests/e2e/delivery.py:382-446`). `names` does not change here, so the two-machine shape stays; a
  raised `disk_gib` re-keys this folder's cut and no other.

## Goals / Non-Goals

**Goals:**

- Two instances of one PostgreSQL module running at once on one machine, each with its own data
  directory, configuration file, port and socket, none of them stated by the deployment.
- Each application proven to reach the instance it wired, by the servers' own answers.
- Every path the test asserts read out of the plan.

**Non-Goals:**

- No library change. The one library fact needed is `member` in the implementation arguments, carried
  by the change that lands before this one.
- No third machine and no third cluster. `beta` keeps exactly what it has, so the delivery-set claims
  `run-a-shared-database-on-real-machines` made are untouched.
- No change to what the two shell scripts do. `init.sh` and `consume.sh` already take `PGDATA`, the
  port and the record path from the environment.
- No replication, no failover, no connection pooling. The claim is instancing.

## Decisions

**The derived name is `${instance}-${member}`.** It is exactly the pair an entry's plan key is built
from, minus the machine, which is right for a path: the same member placed on two machines wants the
same path on each, and two entries of one machine differ in the pair. The separator is `-` because a
plan key's own separators (`:`, `@`) are refused in the names that enter it
(`lib/resolve.nix:204-207`), so `-` cannot collide with anything a name may carry, and it is the
separator `image/read.nix:179-182` already projects a key's name onto.

Placement of each derived path:

| what | where it lands |
| --- | --- |
| data and socket directory | `/var/lib/postgresql/<instance>-<member>` |
| configuration file | `/etc/<instance>-<member>/postgresql.conf` |
| consumer's record | `/run/<instance>-<member>/record` |
| consumer's runtime directory | `<instance>-<member>` |

The socket directory stays the data directory, for the reason the folder already records: the
compiled-in default is `/run/postgresql`, which no plan creates and no machine has. It is now
per-entry for free.

Alternative rejected: keeping the knobs with derived defaults. Impossible, per Context - a default is
written where the instance is unknown. Alternative rejected: passing the instance name down as a
setting from the deployment. That is the plumbing the change removes, one level of indirection later.

**The consumer's runtime directory is derived, not recovered from a path.**
`tests/e2e/shared-postgres/deployment/modules/app/client.nix:65` currently computes
`baseNameOf (dirOf settings.recordPath)` to get a directory name it is about to need. With the
derivation in one place, the extension is handed `"${instance}-${member}"` and the record is a file
inside it. The record file's name loses the instance (it is `record`, not `own.json`), because the
directory already carries it and a reader of the machine finds the file by the directory.

**The private cluster's port is stated by the deployment; the leaf defaults to 5432.** A port is an
address, of the same class as `machines.<name>.address`, which no one expects a module to invent.
`fixed.port = 5432` becomes `defaults.port = 5432`, so the shared instance keeps the number it has
and `own-app` states `5433` for its own database member. Nothing else about the module changes: the
`dsn` export is built from `alloc.ports.postgres` either way, and the port is a key input through
`alloc` (`lib/plan.nix:676`), so the private entry is keyed by its own number. `CLAUDE.md`'s note
that the port is fixed "because the data source this module publishes is built from it" is what moves
- an export built from a knob does not require the knob be fixed, it requires it be resolved, which a
default is.

**Placement is a tag.** `machines.nix` gives `alpha` a tag for the private instance, and
`instances.nix` places both of `own-app`'s members on it. Tags are how this folder already places
things, and an explicit machine list would be the second convention.

**The test reads paths, not constants.** Each path comes out of the built plan:

| assertion | plan field |
| --- | --- |
| configuration file path | the entry's `configData` keyset |
| data and socket directory | `units.init.env.PGDATA` of the cluster entry |
| record path | `units.write.env.RECORD_PATH` of the consumer entry |
| port | `alloc.ports.postgres` |
| data source | `provides.<capability>.exports.dsn` |

`test_shared_postgres.py` therefore carries no absolute path, and a broken derivation is a red test
rather than a stale constant that still matches.

**The two servers are distinguished by the server's own answer.** `pg_control_system()`'s
`system_identifier` is generated by `initdb`, so two clusters have two identifiers; the folder already
reads it into each consumer's record (`tests/e2e/shared-postgres/deployment/consume.sh:56`). The
assertions compare the two identifiers, ask each server for its `datname` list, and present the
shared instance's credential to the private instance's port and read the refusal. Each is one ssh
command whose output is `key=value` lines, using the `psql` the cluster entry's own closure carries
(`test_shared_postgres.py:194-206`).

**Resources.** `memory_mib` stays 2048 and the rendered configuration keeps `max_connections = 32`
with a small `shared_buffers`, so two clusters fit; `disk_gib` rises because `alpha` now holds two
data directories beside two delivered closures. Both figures are key inputs of this folder's cut
only.

## Risks / Trade-offs

- **The first run after this change is cold for this folder.** → `disk_gib` is part of the key; the
  shared image is untouched, so no other folder's cut moves. `rookery snapshot list` shows the
  orphan and `rookery snapshot gc --all` reclaims it.
- **Two clusters on one 2 GiB machine could swap or be OOM-killed.** → `shared_buffers` is small and
  `max_connections` is 32 per cluster; if the machine is observed short, `memory_mib` is the knob and
  raising it re-keys this folder's cut only. The failure mode is loud: a unit that does not reach
  active inside the existing 300 s waits.
- **`tests/unit/layers.nix` recognises a stateful folder by the text `dataDir`
  (`tests/unit/layers.nix:700`).** → The derived directory keeps a name carrying that text, or the
  detection moves with it in the same change. A folder that writes state and is no longer recognised
  makes `undeclaredSpace` pass vacuously, which is why it is a task with its own scenario.
- **The private instance's value moves machine.** → `own-app:vars/password-private` is delivered to
  `alpha` instead of `beta`, so the per-machine credential assertions and the value source layout
  change with it. The plan's own `delivery` record is what the test reads, so the assertion follows
  the record rather than a constant.
- **Two `postgres`-owned data directories under one home.** → The account and the home are the guest
  image's (`tests/e2e/guest.nix:145-152`), mode 700 and owned by `postgres`; both init units run as
  `postgres` and each creates its own subdirectory, which is what the existing one already does.
