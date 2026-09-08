## Why

Every `nix run .#planner-e2e` boots every guest from cold, and the boot is the largest single cost
of the run. Measured on this host at `bebb39e`, `nix run .#planner-e2e -- -q --durations=15`:
**76.36s** for 29 tests, of which **28.40s is the two boots and nothing else** - 13.50s of fixture
setup before the first `wired-pair` test and 14.90s before the first `portable-image` test - against
5.06s for the delivery that follows. The repository's own earlier probe agrees on where the time
goes: 10.49s to a reachable vsock sshd, 10.67s to a complete DHCP lease, and **0.35s** for the
`nix copy` the delivery test is actually about
(`prove-plan-on-real-machines/tasks.md:32-35`). A full run boots three guests across the two
folders, so the fixed cost is paid twice, and it is paid again in full for every `-k` iteration a
developer makes - one selected test out of `wired-pair` cost 31.48s of a 59.25s suite (`:100,117`).

rookery already solves this and this repository does not use it. `rookery.snapshot`'s
`@cluster_snapshot_fixture` cuts a whole networked cluster - RAM, device state and the disk overlay
of every slot, in one consistent cut - and resumes it on the next run instead of booting and
preparing it again. The cut's key is content-addressed over the base image, the preparation's own
source and project-local closure, and the cluster's shape, so an input that moves is a **miss**,
never a stale pass.

## What Changes

- **The machine layer's cluster becomes a snapshot stage.** Each end-to-end folder declares one
  root stage that boots its machines and waits until they are usable; on a warm cache the stage is
  resumed and nothing boots. `delivery.booted` is deleted.
- **BREAKING: the guest image carries the credential.** A cut is RAM plus device state, so a
  resumable cluster can mount no virtiofs share, and a per-run credential would re-key every cut
  and never hit the cache. The image authorizes nixpkgs' published snakeoil key
  (`nixos/tests/ssh-keys.nix`, `snakeOilEd25519PublicKey`); the run uses the private half from the
  same file. The `rookery` share, `cluster-authorized-key.service`,
  `rookery-virtiofs-report.service`, the `virtiofs` initrd module and `delivery.keypair` are
  deleted, and `design.md D6` of `prove-plan-on-real-machines` ("the run generates a throwaway key
  pair and seeds it over a virtiofs share") is superseded.
- **Delivery, activation and attachment are not cut.** They stay live pytest fixtures, run against
  the machines on every run. They are the acts under test, and their evidence - the address dialled,
  the endpoint's own report of the activation, the attach script's output - is host-side and would be
  replayed rather than observed if it moved into a preparation body.
- **The harness gains `delivery.cluster_stage`, `delivery.await_ready` and `delivery.ssh_key`**, and
  a shared `tests/e2e/conftest.py` whose `state_root` fixture is the one rookery resolves by name.
  A private key in the store is mode 0444 and ssh refuses it, so `ssh_key` copies it to 0600 under
  the run's own state root.
- **`PLANNER_E2E_SSH_KEY`** joins the environment the runner and the cluster shell export, sourced
  from the guest package so the image and the key cannot drift apart.
- **Five new end-to-end tests**, one per scenario this change adds: that a prepared cluster is
  cached, that a resumed machine is usable at once and keeps the address its slot was cut with, that
  the machines are reached with the key the image carries, and that no host directory is mounted in
  a machine.

## Capabilities

### New Capabilities

- `tooling/machine-snapshots`: how the machine layer obtains its machines. That a cluster is
  prepared once and resumed afterwards, that a resumed machine is fully usable and keeps the
  identity its slot was cut with, that the credential is the image's rather than the run's, and
  that no observation a test asserts is ever replayed from a cut.

### Modified Capabilities

- `delivery/real-cluster`: *No test double is involved* is restated. "Each machine SHALL be a booted
  kernel of its own" becomes a kernel of its own that either booted this run or was restored from a
  cut of one, and the requirement gains the line that draws the boundary: a machine's *state* may be
  restored, but every fact a test asserts SHALL be produced by that machine during the run.

## Impact

- `tests/e2e/guest.nix`: the share, the key-seeding oneshot, the virtiofs report unit and the
  `virtiofs` initrd module go; a static authorized key arrives. Two assertions are replaced by two
  others - that the only way in is the image's key, and that the guest mounts no virtiofs at all.
- `tests/e2e/delivery.py`: `keypair` and `booted` out, `ssh_key`, `await_ready` and `cluster_stage`
  in. Every pure function the delivery uses is untouched.
- `tests/e2e/{wired-pair,portable-image}/test_*.py`: the `keydir` fixture and the `booted` context
  manager are replaced by the folder's own root stage; `run` derives from it. Every existing test
  keeps its name, its fixture and its subject.
- `tests/e2e/conftest.py`: new, one fixture.
- `tests/e2e/test_harness.py`: gains the pure claims of `ssh_key` (a 0600 copy of the image's key).
- `flake-module.nix`, `devshells.nix`: one exported variable each.
- `tests/unit/coverage.nix`: the two new spec files join `accountable`.
- `docs/cluster.md`: the credential and the snapshot cache, including how to clear it.
- `CLAUDE.md`: the invariants a future edit must not break - no share in a snapshotted guest, why
  the credential is static, and what must never move into a preparation body.
- No library, realiser, plan or fixture behaviour changes. `lib/`, `image/`, `flakelet/`, `perf/`
  and every unit suite but `coverage.nix` are untouched.
