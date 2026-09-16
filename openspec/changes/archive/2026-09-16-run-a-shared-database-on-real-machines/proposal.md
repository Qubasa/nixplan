## Why

Nothing in this repository has ever run a stateful service. Every deployment the end-to-end layer
applies is one process that echoes a value: `tests/e2e/portable-image/deployment/default.nix:32` is
`exec sleep infinity`, `tests/e2e/wired-pair/deployment/modules/page/server.nix:34` is
`python3 -m http.server`, and `tests/e2e/newcomer/template/deployment/modules/hello/greet.nix:9-20`
writes one greeting. So the question a reader actually has - can two services share one database -
is answered by no artifact in the tree, and the shape the design corpus was written for
(`notes/examples/instance-as-group/`, `pg-shared` at `deployment/instances.nix:115-131`) is a
sketch whose README says "design sketch, not executable".

The shape is already expressible. A member handle carries its resolved settings and its capabilities
(`lib/compose.nix:58,63-70`), a root may re-export a member's capability
(`fixtures/minimal-typed-edge/modules/borg-repo/default.nix:21`), and a declaration is read once
against resolved settings (`lib/compose.nix:31`), so a leaf that writes
`provides = lib.mapAttrs (…) settings.databases` publishes one capability per configured database and
the two readings agree by construction. Two instances wiring two capabilities of one provider
instance needs no library change at all. What is missing is the evidence: no folder proves it, and
the claims that make it worth having - that one process serves both, that each consumer's credential
reaches its own machine and no other, that the far consumer reads over the network - are asserted
nowhere.

## What Changes

- **A new end-to-end folder, `tests/e2e/shared-postgres/`**, deploys one PostgreSQL cluster instance
  that publishes one capability per configured database, and two consumer instances that each wire
  one of them. One consumer shares the cluster's machine; the other is on a second machine and
  reaches it over the address and port the plan recorded.
- **The delivery set is proven by absence as well as presence.** Each database's password is its own
  generated value, delivered from an operator-supplied value source. The `eu` password exists on the
  cluster's machine and on the `eu` consumer's machine; it does not exist on the `us` consumer's
  machine, and the reverse. Today that claim rests on `tests/e2e/secret-delivery/`, where the
  non-recipient machine runs nothing at all; here the non-recipient is a working consumer of the same
  provider.
- **Database isolation is asserted against the running server**, not against the plan: the `eu`
  credentials are refused by the `us` database.
- **One process, two databases.** The entry declares two units - a one-shot initialisation and the
  long-running server, ordered by `after`/`requires` - and the test reads back one `MainPID` for both
  databases.
- **The guest image gains a `postgres` account**, with the assertion that says why: a machine that
  hosts a database has a database account, and nothing in a plan creates one. This re-keys every
  snapshot cut in `tests/e2e/`, which is one cold run.
- **No library change.** The folder is written against the vocabulary as it stands: the server's
  knobs are command-line flags rather than a configuration file, so `flakelet/read.nix:125`'s refusal
  of an assembled host path never fires; the password is read by the root-run initialisation unit, so
  the `0400 root` write at `cli/remote.py:284` is never asked to serve a non-root reader; and the
  port is `fixed`, because `lib/module.nix:329` allocates nothing.

## Capabilities

### Modified Capabilities

- `delivery/real-cluster`: a deployment in which two instances take one capability each from one
  provider instance is applied to real machines, and what that folder proves - one process behind
  two databases, a routable data source read from another machine, per-consumer credentials bounded
  by the delivery set, and isolation enforced by the server - is stated.
- `tooling/test-layers`: the new folder's shape and registration, and the guest image's database
  account as an invariant with its cost.

## Impact

- `tests/e2e/shared-postgres/`: new folder - `deployment/` (machines, instances, interfaces, the
  cluster module and the consumer module) and one `test_shared_postgres.py`. Discovered by existing
  `deployment/default.nix` globbing; `flake-module.nix` naming it would fail
  `testAnEndToEndFolderIsAddedWithoutEditingTheFlake`.
- `tests/e2e/guest.nix`: the `postgres` account and its assertion. Every cut's key moves, so the
  next run of every folder is cold; `rookery snapshot gc --all` reclaims the orphans.
- `tests/unit/coverage.nix`: this change's spec files, so the cross-walk does not report them as
  unclassified.
- `CLAUDE.md`: the folder's invariants - why the server takes flags instead of a configuration file,
  why the password is read by the root unit, and what the account costs.
- No file under `lib/`, `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. The four
  library changes this folder makes a user want are
  `openspec/changes/hold-a-long-running-daemon`,
  `openspec/changes/open-a-delivered-value-to-its-reader`,
  `openspec/changes/take-effect-on-a-second-apply` and
  `openspec/changes/cut-a-member-and-wire-its-place`; this change deliberately lands before them, so
  each of those has a working deployment to prove itself against.
