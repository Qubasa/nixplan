## Context

See proposal.md - Why. The constraints that shape the approach, each measured or quoted rather
than assumed:

- **The plan carries a machine's address; an implementation does not receive it.** `implArgs` is
  `{ machine, vars, instance, settings, alloc, results }` plus `target`, and `target` is
  `{ system, serviceManager }` only (`lib/resolve.nix:558-567,210-224`). The address
  is on the machine record (`resolve.nix:198`), carried into the plan at `plan.nix:609-610`, and
  hashed into nothing an implementation can read.
- **A target is already a key input.** "One target record per machine rather than one per
  placement: a target is a function of the machine, and an entry's key hashes it"
  (`resolve.nix:222-224`). Whatever a module may render from must therefore travel in
  that record, or the key stops covering what the entry is made of.
- **rookery addresses are deterministic before boot.** VM *i* holds `10.0.0.(10+i)` from a
  MAC-keyed static dnsmasq reservation, and the EUI-64 IPv6 equally
  (`rookery/qemu/spec.py:62,110-141`, `network.py:297-364`). A plan written against `10.0.0.10` and
  `10.0.0.11` is a plan written against addresses the cluster really hands out, so the equality can
  be asserted rather than read back and believed.
- **`Cluster.run` is the only path from the harness to a machine's IP, and it keeps the host mount
  namespace.** It enters the user and net namespaces only (`rookery/qemu/access.py:106`), so a
  command it runs sees the store the harness sees and can reach `10.0.0.x` (proven by rookery's own
  `c.run(["ping", ..., c.ip_of("m1")])`, `rookery/qemu/tests/test_api_integration.py:134-136`).
- **`Vm.ssh*` is vsock-only** (`access.py:7-13,489-531`) and there is no `ssh://` helper and no
  file-transfer helper on `Vm` or `Cluster`. Control commands ride rookery's vsock channel; the
  delivery uses the guest's ordinary TCP sshd on the cluster LAN.
- **A guest built the way rookery's is has a working store**: no `nix.*` option appears anywhere in
  rookery's images, so `nix.enable` defaults true, `nix-store` is on `PATH`, the daemon is socket
  activated and `trusted-users` is `[ "root" ]`. `nix-command`/`flakes` are **not** enabled, so the
  receiving side must be the stable `nix-store --serve` protocol that `ssh://` speaks.
- **rookery is private and unpublished.** `github:Qubasa/rookery` answers 404 and
  `git+ssh://git@github.com/Qubasa/rookery` cannot be fetched without the caller's SSH
  credentials. A flake input is eager: adding one makes every output of this flake, including the
  seven checks that have nothing to do with clusters, unevaluable for anyone without that access.
- **rookery cannot run inside `nix build` on a stock host.** `/dev/net/tun` and `/dev/vhost-vsock`
  are not sandbox defaults and a flake's `nixConfig.extra-sandbox-paths` is honoured only for a
  trusted user who accepted it (`rookery/nix/integration-test.nix:14-33`); a `containers.<name>`
  test also stamps `requiredSystemFeatures = [ "uid-range" ]`, absent from a builder's default
  feature set (`nixpkgs nixos/lib/testing/run.nix:53-57`, `nixos/modules/config/nix.nix:34-39`).
  And the sandbox mounts `/nix/store` without `/nix/var/nix/db`, so nothing inside it can ask
  whether a path is valid - which is what `nix copy` must ask first.

## Goals / Non-Goals

**Goals:**

- One command whose subject is two machines and the network between them, with no stub, double,
  recording or injected store path anywhere in it.
- A delivery step that is the operator's step, run the way an operator runs it: from a real store,
  with a real daemon, to the address the plan recorded.
- Falsifiability of the planner's cross-machine claims: the address, the allocated port, and the
  resolved wire, each observed from the machine that has to rely on it.
- One declaration site for a machine's address, in the planner, not in the fixture.
- A flake that anyone can still evaluate, lock, and check.

**Non-Goals:**

- Changing either realiser or the flakelet artifact's shape. The one library change is the machine
  value handed to an implementation, and it exists because the fixture cannot be honest without it.
- Proving rookery. Its own suite does that; this change consumes it.
- A `nix build`-shaped check over the cluster. It is not possible on a stock host (Context), and a
  check that only one machine can run is a check that lies about the rest.
- Online clusters, `pasta` egress and NAT. The cluster is offline, and that is load-bearing
  evidence (D7), not a simplification.
- Secure Boot, TPM, snapshots, SPICE and the firmware TUI. Available in rookery, irrelevant here.

## Decisions

**D1. `target` gains `address`, and the entry key follows.** The machine value an implementation
receives becomes `{ system, serviceManager, address }`, each present only when the machine declared
it, following the shape `targetOf` already has (`resolve.nix:210-220`) and the absent-not-null rule
the record next to it follows (`plan.nix:612-616`). Because a target is hashed into the entry key
(Context), the address becomes a key input for free - which is required, not incidental: a unit
rendered from an address must not share a key with a unit rendered from a different one.

The consequence is stated rather than hidden: changing a machine's address re-keys **every** entry
placed on it, including entries that never read it. The planner cannot know which implementations
dereferenced the field - `impl` is a function - and the alternative is a key that does not cover
what the entry is made of, which is the worse failure. The alternative of a separate
`machineAddress` argument outside `target` was rejected for exactly this reason: it would put a
renderable fact outside the value the key hashes.

**D2. The entry point is `nix run .#planner-cluster`; there is no cluster check.** The runner is a
script whose derivation bakes in the image, both artifacts, the deployment and the suite as store
paths, so `nix run` builds everything this repository owns through the ordinary pure path. It then:

1. checks the host and fails loudly, naming the missing device, module or group membership, before
   any VM is started (rookery's `preflight()` does most of this; the runner adds the ones rookery's
   published list omits, notably `/dev/vhost-vsock`);
2. resolves rookery **at run time** from `$ROOKERY_FLAKE` (default
   `git+ssh://git@github.com/Qubasa/rookery`) with `nix build`, using the caller's own credentials;
3. runs pytest with the store paths in the environment, passing extra arguments through.

This is what solves the private-input problem: nothing in this flake's evaluation refers to
rookery, so the lock is unchanged, every existing check still evaluates for everyone, and the
credential requirement lands on the person who has the credential, at the moment they run the
command. It is also what solves the sandbox-store problem: the delivery runs against the caller's
real store and real daemon, so `nix copy` is `nix copy`, with no chroot store and no
`closureInfo` reconstruction in between.

**D3. The half that needs no machine is a sandboxed check, `checks.planner-cluster-offline`.**
Dropping the cluster check must not drop CI coverage of everything that is not a boot: the plan's
address, the refusal of a machine an entry was not placed on, the two artifacts' bytes, and the
delivery driver's pure half. Those run in `pkgs.runCommand` with pytest over built artifacts, the
way `checks.planner-flakelet` already does. `nix flake check` therefore still fails when the fixture, the
driver's addressing or the rendered units regress; only the boot is outside it.

**D4. The interpreter comes from rookery, or the runner refuses.** rookery is a
`buildPythonApplication` with no `python3Packages.rookery` attribute, and its runtime binaries
reach `PATH` only through its own wrapper. The runner therefore assembles the environment
explicitly: each `propagatedBuildInputs` entry's `bin` on `PATH` (read from the package's
`nix-support/propagated-build-inputs`, which is what nixpkgs' python wrapper does), and
`${rookery}/lib/python3.X/site-packages` on `PYTHONPATH`. If that `python3.X` is not the version
this repository's pytest environment was built against, the runner **stops with a banner naming
both versions** rather than importing across a version boundary. Normally they agree: rookery's
`Qubasa/nixpkgs?ref=rutabaga_gfx` pin is documented as reverted to upstream nixos-unstable
(`rookery/docs/GPU_ACCEL_DEBUG.md:14-16`).

**D5. The guest image is this repository's, with rookery's invariants restated as assertions.**
Without a flake input, `${inputs.rookery}/nix/base-image-configuration.nix` is unavailable at
evaluation, so the configuration is ours: `qemu-guest` profile, systemd-boot on a GPT ESP,
serial console on the primary UART, `virtiofs` in the initrd, `vmw_vsock_virtio_transport` for the
vsock sshd, networkd as the only DHCP client, `nofail` on every non-root mount, firewall off. Each
one is carried with the assertion that rookery carries for it
(`rookery/nix/base-image-configuration.nix:25-59`), so a future trim fails `nix build` rather than
producing a guest that never becomes reachable. On top of that: `services.flakelets.enable = true`
with no declared services, and nothing else.

Alternative rejected: vendoring rookery's file. It would drift with no signal. The assertions are
the signal, and `docs/cluster.md` names the file they were copied from.

**D6. The image carries no credential; the run seeds one over virtiofs.** The suite generates an
ed25519 key pair into its own temporary directory, exports that directory as the reserved `rookery`
virtiofs share (mounted at `/rookery`, `rookery/qemu/spec.py:238-241`), and the guest installs it
at boot from `/rookery/authorized_keys` into root's `authorized_keys` with root ownership. A
generated key means no secret is committed here and none is borrowed from rookery; a boot-time
install rather than `authorizedKeysFiles` pointing into the share means sshd's `StrictModes` is
never in play, and the unit is a `nofail`-shaped oneshot so a share-less boot of the same image
still comes up. The image is therefore reusable and unprivileged: without the share, nobody can log
in as root over the LAN.

**D7. The cluster is offline, and that is the evidence for "nothing was fetched".** `offline=True`
is rookery's default and gives dnsmasq no upstream server at all
(`rookery/qemu/network.py:355-359`), so a machine has no route to any substituter. A unit that runs
therefore runs from paths that arrived by delivery, and the requirement is topology rather than a
log line. It also removes the nftables NAT prerequisite from the host contract
(`rookery/qemu/preflight.py:688-689`).

**D8. Control and delivery use different channels, deliberately.** Readiness, assertions and
`flakelet` invocations go over rookery's vsock SSH (`Vm.ssh_succeed`), which is up before the LAN
is; the delivery goes over the guest's TCP sshd at the plan's address through `Cluster.run` with
`NIX_SSHOPTS` carrying the generated key. An assertion then never depends on the channel it is
asserting about: the LAN being usable is the thing under test.

**D9. One cluster per run, and the phases are ordered.** The requirements are a state machine -
deliver, activate, observe, redeliver unchanged, change, roll back, reboot. The suite is therefore a
session-scoped cluster fixture plus one test per phase in file order, with the ordering stated in
the file's header and each test asserting the state it depends on rather than assuming it. Two
clusters would double a multi-minute boot for no additional truth.

**D10. The cross-walk uses the external form for the cluster scenarios and the nix-unit suites for
the planner ones.** The `delivery/real-cluster` scenarios are pytest cases named in
`tests/mapping.nix` the way the VM scenarios already are; the `planner/plan-artifact`
delta's scenarios are value-level and belong in the existing `plan` and `resolution` suites, where
key-input and machine-record behaviour is already asserted.

## Risks / Trade-offs

- **A library change lands in a change whose subject is a test** → it is the one change the fixture
  cannot be honest without (proposal.md - Why), it is specified as its own delta with its own
  scenarios, and it is the first task group, reviewed and gated on its own tests before any cluster
  code exists.
- **Adding an address to the target moves the perf counters, and the gate has no headroom**
  (measured: `planner-perf` reports `0.0% of headroom` on the `mesh-4` counters, within a 15%
  margin) → the task list re-measures before and after with `perf/measure.sh` and records the
  delta; `budgets.json` is only moved if the gate actually fails, and then with the measurement
  quoted next to it.
- **Re-keying every entry on a machine whose address changed (D1)** → stated in the spec as a
  scenario rather than left as a surprise, and the same scenario pins that nothing else about the
  plan moves with it.
- **The cluster is outside `nix flake check`** → D3 keeps everything that is not a boot inside it,
  and `docs/cluster.md` states plainly that the boot is a command a human runs. The alternative was
  a check only one configured machine can run.
- **rookery's guest invariants are restated, not imported (D5)** → each is carried with its
  assertion, so a violated invariant fails our build, and `docs/cluster.md` names the upstream file
  to diff against when rookery moves.
- **Real boots are slow and can wedge** → every wait is a rookery wait with a timeout
  (`wait_ready`, `wait_for_network`, `wait_for_unit`, `wait_until_succeeds`), never a sleep, and the
  runner prints the state directory it kept on failure so the cluster can be inspected after the
  fact (`rookery/qemu/api.py:1116-1119`).
- **A version skew between this flake's python and rookery's** → the runner refuses with both
  versions named (D4) rather than importing across it.
- **`nix copy` needs the guest to accept unsigned paths** → `root` is a trusted user on a stock
  NixOS guest, so `--no-check-sigs` is accepted; the guest is a throwaway with a generated key and
  no route off the cluster.

## Migration Plan

Additive except for one library field. `target` gaining `address` changes entry keys for any
deployment whose machines declare an address - including the worked deployment, whose golden plan
and committed diagnostics are regenerated as part of the task that makes the change. Rolling back
is reverting that field and deleting the new outputs; no data or state persists anywhere.

## Open Questions

- Whether the reboot phase uses an in-guest `systemctl reboot` over the control channel or
  rookery's QMP `Vm.reset()` (`rookery/qemu/api.py:581-589`). Both reboot a real kernel; the
  in-guest form is the honest one for a service-manager claim and is assumed in the tasks. It
  changes one call.
- Whether the consumer's unit fetches once at start (a oneshot that records its result) or on a
  timer. The oneshot is assumed, because "the request succeeded" is then a unit state a machine
  reports rather than a file a test greps. It changes the fixture's unit, not the spec.
