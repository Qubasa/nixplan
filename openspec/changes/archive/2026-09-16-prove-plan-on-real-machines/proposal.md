## Why

The flakelet realiser is activated by a real endpoint on a real service manager, but the machine
that activates it was handed the artifact before it booted: `virtualisation.additionalPaths`
(`tests/nixos/flakelet.nix:141-147`) puts every store path in the guest's store at
image-build time, and the two declared entries name a `prebuilt` path the guest's own closure
already refers to. Nothing crosses a network, so the step an operator actually performs - build
here, copy there, activate there - is the one step no check exercises. The previous change said so
in as many words: **delivery (`nix copy` to a real host) is out of scope**
(`openspec/changes/emit-flakelet-service-artifacts/proposal.md:75-76`).

The second unobserved claim is larger. The planner's whole thesis is that a wire is resolved once,
at evaluation, into a value: `borg-repo/server.nix` exports
`url = "ssh://borg@${settings.host}:${toString alloc.ports.ssh}/srv/borg"` and the consumer reads
it out of `results` (`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:79-84`). Every
test in this repository stops at the string. Whether a machine can *reach* the address the plan
computed for it, from the machine the plan placed the consumer on, has been asserted by nobody -
and that is the property a deployment planner exists to get right.

Writing the fixture for that observation surfaced a gap in the planner itself. A machine's address
is on its record and in the plan (`lib/resolve.nix:198`, `lib/plan.nix:609-610`), but
an implementation is never handed it: `implArgs` is `{ machine, vars, instance, settings, alloc,
results }` plus `target`, and `target` carries `{ system, serviceManager }` only
(`lib/resolve.nix:558-567,210-224`). A service that must publish its own endpoint is therefore told
its address a second time through `settings`, as `borg-repo/server.nix:80` is. Two declaration
sites for one fact is the defect this repository refuses everywhere else, and a wire whose far end
is an address cannot be honest until it is one site.

`~/Projects/rookery` closes the observation gap with no test double in sight. It boots N real QEMU
VMs rootless, each on its own linked clone, inside a per-cluster namespace bundle: a real
dual-stack LAN on `10.0.0.0/22` with real DHCP leases from dnsmasq, deterministic addresses known
before boot (`rookery/qemu/spec.py:62,110-123`), real DNS, and `Cluster.run`, which enters the
cluster's user and network namespaces only (`rookery/qemu/access.py:106`), leaving a host-side
command able to see the host's `/nix/store` and reach a guest's IP. That is exactly the shape a delivery
needs, and rookery's own documentation names this use: "Needed to drive `clan`, `nixos-anywhere`,
or `nix copy`, whose VM addresses only exist there" (`docs/rookery.md:340`).

## What Changes

- **The planner hands an implementation the machine it was planned for, address included.**
  `target` gains `address`, and because a unit may now be rendered from it, the address becomes an
  input to the entry's key. One declaration site for one fact; a deployment stops restating in
  `settings` what the machine registry already says.
- **A new capability, `delivery/real-cluster`**: what delivering a built artifact to a real machine
  consists of, what identity travels with it, what a second delivery of an unchanged entry does,
  and what a plan's cross-machine wire looks like once it is traffic rather than a string.
- **A two-machine deployment fixture** whose plan places a producing service on one machine and a
  consuming service on another, wired by a typed edge. The producer publishes its endpoint from the
  target the planner handed it; the consumer reads that endpoint out of `results`. Both entries are
  built by the existing flakelet realiser - **no realiser changes**.
- **A guest image this repository owns and this repository alone**: a NixOS configuration carrying
  the invariants a rookery guest needs, each asserted in its own build the way rookery asserts them
  (`rookery/nix/base-image-configuration.nix:25-59`), plus `services.flakelets.enable` with *zero*
  declared services, leaving the machine holding flakelet's boot and reconcile units
  (flakelet `modules/nixos.nix:42-97`) and knows nothing about the artifacts it will be given. It
  carries **no credential**: the run generates a throwaway key pair and seeds it over a virtiofs
  share, so nothing secret is committed and no image is baked around a key.
- **Delivery over the wire**: a plain `nix copy --to ssh://root@<the address the plan carries>`
  from the developer's own store, run through `Cluster.run` inside the cluster's netns, followed by
  `flakelet activate` over rookery's control channel. The receiving machine evaluates nothing and
  fetches nothing.
- **Observations a machine has to answer**: the consumer on machine B reaches the producer on
  machine A at the planned address; the port the planner allocated is the port a socket is
  listening on; a second delivery of an unchanged entry is a no-op; a changed entry is a new
  generation and a rollback returns the previous one; a reboot brings both back; flakelet's
  reconcile leaves a hand-activated entry alone.
- **The entry point is `nix run .#planner-cluster`**, a runner that checks the host, resolves
  rookery **at run time** from `$ROOKERY_FLAKE` with the caller's own credentials, and runs pytest
  against store paths baked into it. **No flake input is added**: this flake stays evaluable, and
  lockable, on a machine with no access to a private repository.
- **The half that needs no machine stays in `nix flake check`**: the address the plan carries, the
  refusal of a machine an entry was not placed on, and the bytes of both artifacts are asserted by
  a new sandboxed check, so CI still covers everything that is not a boot.

## Capabilities

### New Capabilities

- `delivery/real-cluster`: what a delivery of one built artifact to one real machine is, what it
  refuses, what a redelivery does, and which of the plan's claims a cluster of real machines is
  able to falsify - the addresses it computed, the ports it allocated, and the wires it resolved.

### Modified Capabilities

- `planner/plan-artifact`: an implementation receives the machine it was planned for including its
  address, and the address is an input to the entry's key. Written as a delta under
  `specs/planner/plan-artifact/` because `openspec/specs/` is empty and the capability exists only
  in the unarchived `implement-minimal-typed-edge` change.

## Impact

- `lib/resolve.nix`: `targetOf` gains `address`; the key input follows from it. This is
  the only library change, and `tests/suites/` and `perf/budgets.json` follow it.
- `cluster/` (new): the guest image, the two-machine deployment fixture, the delivery
  driver and the runner script.
- `tests/python/test_cluster.py` (new): the suite, held to the existing
  `checks.planner-python` bar (ruff, mypy `--strict`).
- `flake-module.nix`: `apps.planner-cluster`, `checks.planner-cluster-offline`,
  `packages.planner-cluster-image`, `packages.planner-cluster-artifacts`.
- `tests/mapping.nix` and `tests/suites/coverage.nix`: the cross-walk for both specs.
- `docs/`: `cluster.md` (the host contract, what a run observes, how to attach to a
  live cluster), plus the README and tooling tables.
- `flake.nix`: unchanged. No new input, no `nixConfig`.
- Nothing under `image/` or `flakelet/` changes.
