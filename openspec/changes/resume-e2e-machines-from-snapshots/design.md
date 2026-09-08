## Context

See proposal.md - Why for the measurement. The constraints that shape the approach, each read out
of rookery's own source or measured on this host rather than assumed:

- **A cut is a QEMU migration, not a disk snapshot.** A save stops the guest, migrates RAM and
  device state to a sidecar `.mig` file with `mapped-ram` + `multifd` and reflinks the disk overlay
  beside it (`rookery/CLAUDE.md` B17, `rookery/snapshot/migrate.py`). Everything that is not RAM,
  device state or that overlay is therefore outside the cut.
- **A snapshotted cluster can carry no virtiofs share.** `_stage_specs` builds each slot's `VmSpec`
  from `image`, `name`, `ssh_user`, `ssh_password`, `ssh_key`, `uefi`, `secure_boot` and `tpm` and
  nothing else (`rookery/snapshot/cluster_lineage.py:72-86`), and the docstring names the reason:
  "``gpu`` and virtiofs shares are unsupported (their device state does not survive migration
  save/restore)" (`:205-206`). Today's key seeding is a share (`delivery.booted`, `guest.nix`
  `fileSystems."/rookery"`), so it cannot be kept.
- **A credential in a cut is frozen into it.** On a hit the preparation body does not run at all, so
  the guest's `authorized_keys` is whatever the cut froze while `Vm.ssh*` authenticates with the key
  the fixture was declared with. A per-run key would have to be declared as an input to stay
  correct, and would then re-key every cut - a cache that never hits.
- **The login secret is deliberately not part of the key.** "The login secret itself is deliberately
  excluded: it is a connection credential, not a state determinant, and rotating it should not
  invalidate every cache entry" (`rookery/snapshot/lineage.py:146-148`). So a static credential is
  what the mechanism is built for.
- **The key folds in the base image by store identity, not by reading it.** `base_content_hash`
  returns the Nix store hash where one applies and reads no bytes (`rookery/qemu/disk.py:257-271`),
  so keying on a 2.2 GB qcow2 costs nothing per run and a rebuilt image is a clean miss.
- **A preparation body is scrubbed and confined.** It runs with `os.environ` reduced to
  `PATH`, `HOME`, `XDG_RUNTIME_DIR`, `TMPDIR`, `LANG`, `NIX_STORE_DIR`, `LC_*` and `ROOKERY_*` plus
  whatever the stage declared as `extra_env` (`rookery/snapshot/plugin.py:84-119`), on a thread
  confined by a Landlock ruleset that denies reads inside the project tree and execs outside
  rookery's infra binaries plus the declared `extra_tools` (`:129-169`, `rookery/landlock.py`).
- **A cut taken at "sshd answers" freezes a half-ready guest.** rookery's own example spells it out:
  `wait_for_ssh` attests the socket-activated vsock sshd, which answers before `multi-user.target`,
  so a branch resuming that cut runs before the login `PATH` is populated
  (`rookery/examples/snapshot-fixtures/test_cluster_lineage.py:157-168`).
- **A single-VM cut can only resume as slot 0.** "a RAM snapshot bakes the guest's index-0 network
  identity in, so it can only ever resume as index 0. For VMs that must talk, use the second
  example" (`rookery/examples/snapshot-fixtures/README.md:46-48`).
- **The guest is UEFI-only.** It boots systemd-boot on a GPT ESP (`tests/e2e/guest.nix`), while the
  snapshot fixtures default to BIOS and to `secure_boot=False`, `tpm=False`
  (`rookery/snapshot/cluster_lineage.py:182-184`) - a posture that differs from `VmSpec`'s own
  defaults (`uefi=True`, `secure_boot=True`, `tpm=True`, `rookery/qemu/spec.py:305-308`), which is
  what `delivery.booted` gets today.
- **nixpkgs publishes the key.** `nixos/tests/ssh-keys.nix` carries `snakeOilEd25519PrivateKey` and
  `snakeOilEd25519PublicKey`, commented "This key is used in integration tests / This is NOT a
  security issue" and taken from OpenSSH's own fuzz fixtures. A store file is mode 0444 and ssh
  refuses a private key that readable.

## Goals / Non-Goals

**Goals:**

- Remove the boot from the repeated cost of a run, and above all from the cost of one `-k`
  iteration, without changing what any existing test observes or what it is named.
- Keep the act under test - delivery, activation, redelivery, rollback, attachment - performed
  against the machines on every run, so no evidence is served from a cache.
- Keep a cut invalidated by everything that determines it: the guest image, the preparation, the
  cluster's shape, the host CPU and the QEMU build.
- Keep the failure mode of a stale or unusable cut a cold run, never a wrong pass.

**Non-Goals:**

- Proving rookery's snapshot machinery. Its own suite does that; this change consumes it, exactly as
  `prove-plan-on-real-machines` consumed the cluster machinery.
- A deeper lineage. One stage per folder, no branches (D1).
- Cutting a delivered, activated or attached machine (D1).
- Changing the plan, either realiser, the artifacts or any unit suite but the coverage cross-walk.
- Running the machine layer inside `nix build`. Unchanged and still impossible on a stock host.

## Decisions

**D1. Cut the boot, not the delivery.** The root stage ends when the machines are usable; the
delivery, the activation and the attachment stay ordinary session fixtures. Two reasons, one
measured and one structural. Measured: the boot is 13.50s and 14.90s of fixture setup while the
delivery that follows is 5.06s and the copy itself 0.35s, so the boot is where the time is.
Structural: what the delivery tests assert is host-side evidence of an act - the address dialled,
the endpoint's own report that it used a prebuilt artifact and resolved nothing, the attach script's
output. A preparation body does not run on a cache hit, so that evidence would either vanish or
have to be persisted into the guest and read back, which is a recording of the act rather than the
act. `tooling/machine-snapshots` states that boundary as a requirement.

*Alternative considered:* a second `delivered` stage with the observations written into the guest
during the preparation. Rejected: it buys ~5s and turns three requirements of `delivery/real-cluster`
into assertions about a cache.

**D2. `@cluster_snapshot_fixture`, one root stage per folder.** `wired-pair` needs two machines that
route to each other at `10.0.0.10` and `10.0.0.11`; `@snapshot_fixture` is single-VM, and two of them
are both slot 0 with no route between them. The whole-cluster decorator boots every slot in one
namespace and cuts them together, which is also what keeps a resumed guest's frozen DHCP lease and
ARP entry valid (rookery pins the gateway bridge MAC for exactly this). `portable-image` needs one
machine but declares its root the same way, from the same shared factory, so the two folders cannot
drift apart in how they boot.

**D3. The credential becomes the image's, and it is nixpkgs' snakeoil key.** Forced by Context: no
share in a cut, and a per-run key re-keys every cut. The alternatives:

- *A key generated at image-build time and exported beside the image.* Rejected: an input-addressed
  derivation rebuilt after a store GC produces different bytes at the same path, so a surviving
  cached image would authorize a key nobody holds any more - a silent, confusing breakage that would
  itself need a guard.
- *A keypair committed to this repository.* Rejected: real key material in the tree, against this
  repository's own rule, for no gain over a published one.
- *A deterministic key derived from a committed seed.* Rejected: the same key material wearing a
  disguise, plus a `cryptography` build dependency.
- *Password authentication (`ssh_password`, what rookery's examples use).* Rejected: it would delete
  the `PasswordAuthentication = false` invariant the guest asserts, and the delivery's `nix copy`
  would need `sshpass` in `NIX_SSHOPTS`.

nixpkgs' `snakeOilEd25519*` is published upstream, is in OpenSSH's fuzz fixtures, and is documented
as not a security issue; it authorizes nothing but an offline throwaway guest built from this
repository. The guest package exports the private half beside the image
(`e2eGuest.sshPrivateKey`), so one file defines both halves and the image and the run cannot drift.

**D4. The private key is copied to 0600 under the run's state root.** A store file is 0444 and ssh
refuses it. `delivery.ssh_key(root, source)` writes the copy and takes both paths as arguments, so
it is a pure function `tests/e2e/test_harness.py` can assert without a machine. It lands under
`delivery.state_root()` - the directory the runner already creates, keeps on failure and removes on
success - rather than a second temporary directory nobody owns. `state_root()` becomes memoized so
the fallback path yields one directory per process, and it is exposed as the `state_root` fixture
rookery resolves by name (`rookery/snapshot/plugin.py:256-279`); the short-prefix rule stays, since
a run-dir socket path still has to fit `AF_UNIX`'s 108 bytes.

**D5. The preparation body reads nothing and runs nothing.** It waits for readiness over rookery's
own channels and yields. That means no `extra_env`, no `extra_files`, no `extra_tools`: nothing for
the environment scrub to hide and nothing for the Landlock ruleset to deny, and no artifact path in
the cut's key - so editing a fixture's deployment does not invalidate the boot. This is the second
reason the delivery stays outside a preparation: it execs `nix` and reads `PLANNER_*`, both of which
would have to be declared, and the artifact paths would then re-key the boot on every fixture edit.

**D6. The cut is taken at `multi-user.target`, not at "sshd answers".** Each slot is waited to
`wait_for_ssh`, then to `multi-user.target`, then the cluster to `wait_ready` and
`wait_for_network`. Otherwise a resumed guest comes up mid-boot and the first test's `uname -r` runs
before the login `PATH` exists. *A resumed machine is usable at once* is the scenario that holds this
in place.

**D7. `uefi=True`, `secure_boot=False`, `tpm=False`.** The image boots systemd-boot from a GPT ESP,
so the fixture's BIOS default cannot boot it; Secure Boot stays off because the image is unsigned
and a cut of a refused boot cannot be captured; the TPM goes because nothing in the guest measures
anything, and dropping it drops a `swtpm` per machine. Each of the three is part of the key, so a
later change of posture is a clean miss.

**D8. Session scope, and the phases mutate the resumed cluster exactly as they mutated the booted
one.** The stage is declared `scope="session"`, so a folder obtains its cluster once. Nothing else
about the ordered phases changes: they still deliver, activate, cut the wire, redeliver, roll back
and reboot in file order.

## Risks / Trade-offs

- **[A cut of a networked cluster resumes with a frozen DHCP lease and ARP entry.]** → rookery gates
  a cut on network readiness before pausing and pins the gateway bridge MAC so unicast renewal still
  reaches it (`rookery/CLAUDE.md` invariant 7, `network.create_bridge`). A seeded resume that fails
  anyway is evicted and the stage re-prepared from the nearest healthy ancestor
  (`_evict_retry`), which for a single-stage lineage is a cold boot.
- **[Disk cost: the cache holds guest RAM.]** → 2048 MiB per machine per cut, so about 6 GiB for the
  three machines of the two folders, under `$XDG_CACHE_HOME/rookery/snapshots`. It is a cache root
  precisely because losing it only forces a re-prepare; `docs/cluster.md` gains
  `rookery snapshot list` and `rookery snapshot gc --all`.
- **[A resumed guest's wall clock is the cut's.]** → The scheduled entry's timer is installed after
  the resume and `schedule = "daily"`, so its next elapse is in the future by the guest's own clock,
  which is what `test_the_timer_the_schedule_declares_is_enabled` reads. If a very old cut ever
  breaks that, the stage takes a `max_age`.
- **[The image now authorizes a key anyone can fetch.]** → The guest is offline, throwaway, and
  built from this repository; the key is published by nixpkgs and by OpenSSH. The guest still refuses
  password authentication, and the assertion in `guest.nix` names the key so a future edit cannot
  quietly widen it to a real one.
- **[A developer's first run after this change is slower, not faster.]** → It is a cold run that also
  writes the cut. Stated in `docs/cluster.md` so a cold first run is not read as a regression.
- **[The e2e layer now depends on one more rookery subsystem.]** → It is resolved at run time from
  `$ROOKERY_FLAKE` like the rest of rookery, and its absence is the existing skip: the suites already
  skip themselves when rookery is not importable.

## Migration Plan

No state to migrate: the cache starts empty and the first run fills it. The share plumbing and the
per-run keypair are deleted in the same change that adds the stage, because a guest that still
mounted `/rookery` would fail the new assertion and a run that still generated a key would have
nothing to hand it to. Rolling back is reverting the change; the cache directory is reclaimable and
can be dropped with `rookery snapshot gc --all`.
