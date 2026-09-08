# Real machines, and what a delivery does to one

Every suite in the unit layer - the nix-unit suites [`tooling.md`](tooling.md) lists, and the
specification cross-walk it derives - evaluates a plan or inspects the bytes one produces. This
layer hands a built artifact to a machine that did not build it, over a network, and then asks that
machine what it now runs.

None of it is a `check`. A build sandbox has no `/dev/kvm`, no `/dev/net/tun` and no
`/dev/vhost-vsock`, and it cannot ask a daemon whether a delivered path is valid, so the machine
layer is one app:

```bash
nix run .#planner-e2e                  # 29 passed in 78.65s - both folders, three machines
nix run .#planner-e2e wired-pair       # 21 passed in 60.87s - two machines
nix run .#planner-e2e portable-image   # 8 passed in 18.24s - one machine
nix run .#planner-e2e -- nosuchfolder  # refused, without building or booting anything
```

`$ROOKERY_FLAKE` has to name a rookery you can fetch; it defaults to
`git+ssh://git@github.com/Qubasa/rookery`. Anything after a folder name is handed to pytest, so a
`-k` expression still selects within the folder (`../tests/e2e/runner.py`, `main`).

An unknown folder is refused first, before the host is probed and before rookery is resolved: a
typo is the caller's, and naming the folders that exist is useful on a host that could not boot one
anyway.

```
===========================================
  NO END-TO-END TEST NAMED 'nosuchfolder'
===========================================
  the end-to-end tests are:
    portable-image
    wired-pair
===========================================
```

## The host it needs

`host_problems` in `../tests/e2e/runner.py` probes four things by opening or reading them, and
prints one banner - `THIS HOST CANNOT RUN THE CLUSTER` - naming every one that is missing. No VM is
started.

| Prerequisite | Why the run needs it |
| --- | --- |
| `/dev/kvm`, and your user in `kvm` | rookery refuses to fall back to TCG emulation, so KVM is required |
| `/dev/net/tun` | the cluster LAN is real taps in a network namespace |
| `/dev/vhost-vsock`, i.e. `vhost_vsock` loaded | the control channel into each guest is vsock |
| `/proc/sys/user/max_user_namespaces` above zero | rookery runs every cluster in an unprivileged user namespace |

Each line the banner prints is the path, what the kernel said about it, and that reason, so a
missing device reads as `/dev/vhost-vsock: No such file or directory - the control channel into
each guest is vsock`. The banner ends with the fix and with `No VM was started.`; on NixOS the fix
is:

```nix
boot.kernelModules = [ "tun" "vhost_vsock" ];
users.users.<you>.extraGroups = [ "kvm" ];
```

Nothing checks `PATH`. `qemu`, `pasta`, `dnsmasq`, `ip`, `nsenter` and `ssh` all arrive from
rookery's own propagated closure, which the runner walks transitively and prepends
(`propagated_closure`) - the `-dev` outputs propagate the real ones one level down, so a
single-level walk would lose exactly those binaries.

rookery itself is private, so it is not an input of this flake: making it one would make every
output here unevaluable for anyone without that access. It is built at run time from
`$ROOKERY_FLAKE` with your own credentials, and an unresolvable reference is refused with the
reference named. rookery reaches pytest through `PYTHONPATH`, which only holds within one python
minor version, so the runner also compares the two interpreters and refuses with both named: this
repository's `python3` is 3.14 while rookery is built for 3.13, which is why the app's pytest
environment is `pkgs.python313` (`../flake-module.nix`, `clusterPytestEnv`).

## The two folders

Each directory under `../tests/e2e/` is one end-to-end test and its own fixture: exactly one
`test_*.py`, an `artifacts.nix` that realises the deployment it delivers, and a `deployment/` of
`machines.nix`, `instances.nix`, `interfaces/` and `modules/`. The runner discovers them by looking
for `test_*.py` under each directory, so a third folder needs no registration anywhere.

`../tests/e2e/delivery.py` is the shared driver both folders import, `../tests/e2e/guest.nix` is
the guest both boot, and `../tests/e2e/test_harness.py` asserts the driver's pure half - which
machine a key names, which address a delivery dials, which end-to-end tests exist - without a
machine, as the `planner-delivery` check.

### `wired-pair` - 21 tests, two machines, 61s

Two machines, one plan, and the wire between them. The phases are ordered and the file order is the
order, so each test asserts the state it depends on rather than assuming it: the participants are
real machines running nothing yet; both entries are delivered by `nix copy` and activated through
the endpoint; the receiving machine evaluated nothing and can reach no store but its own; the wire
is traffic to the address the plan recorded, and cutting the far end is visible; an unchanged
redelivery is a no-op, a changed one is generation 2 and a rollback returns generation 1; a
scheduled entry is registered with its timer enabled and is not fired by deploying it; and both
machines reboot with the entries coming back without a second delivery.

One test per scenario of
[`delivery/real-cluster/spec.md`](../openspec/changes/prove-plan-on-real-machines/specs/delivery/real-cluster/spec.md),
named after it.

### `portable-image` - 8 tests, one machine, 18s

One machine and two built images, one planned for it and one planned for a machine of another
architecture. What the machine does with them is the subject: the image is attached by the
`bin/attach` script the artifact itself carries rather than by anything the harness wrote, the unit
that attachment names becomes active, the identity `portablectl` needs is the image's own and names
the entry rather than the host it was built on, and the command that unit runs is a path inside the
image the service manager records as its `RootImage`; the confinement profile the entry was stated
under is the one the machine enforces, read twice - once by the confined unit, which reaches only
the copy it was shown, and once over ssh, where the operator's own file is plainly there; an image
built for `aarch64-linux` is refused by its own script on an `x86_64-linux` host; and `bin/detach`
removes the units and the staging directory attaching made while leaving the host file the image
was shown.

One test per scenario of
[`realiser/portable-service-image/spec.md`](../openspec/changes/emit-systemd-portable-service-images/specs/realiser/portable-service-image/spec.md)
that is about what a real machine does with a built image.

## What a delivery is

The plan is the only thing the driver reads to decide where a delivery goes: an entry's key names
its machine, the machine's record carries the address, and an entry asked for on a machine the plan
did not place it on is refused rather than dialled. Both folders hand their artifacts over as
bytes, built here:

```
packages.planner-e2e-wired-pair/     packages.planner-e2e-portable-image/
  site/          check/               confined/     # planned for the machine the run boots
  site-changed/  sweep/               foreign/      # planned for aarch64-linux
  plan.json      plan-changed.json    plan.json
```

`nix copy --to ssh://root@<address> --no-check-sigs <artifact>` is the delivery, run inside the
cluster's namespace through rookery's `Cluster.run`, and `flakelet activate <name> <path>` over the
vsock control channel is the activation. `NIX_SSHOPTS` carries `-F /dev/null`, which is load-bearing
rather than tidy: inside rookery's single-uid user namespace a real-root-owned `ssh_config` appears
owned by `nobody` and ssh refuses to read it at all, so the copy fails with
`Bad owner or permissions`.

## The guest image

```bash
nix build .#packages.x86_64-linux.planner-e2e-guest --no-link --print-out-paths
# /nix/store/jmhlh2kvn6i0vjnyf0fx5zmb08ma4s75-planner-e2e-guest-image
```

Its `nixos.qcow2` is the disk every machine boots, and is what the app and the shell export as
`$PLANNER_E2E_GUEST_IMAGE`. The guest's own `toplevel` travels beside the image rather than in a
`passthru`, because `make-disk-image` builds inside a VM whose result carries none: the qcow2
references nothing, while the system inside it references everything.

One image serves both folders, and it carries no artifact of any plan, no credential and no
declared flakelet service: the endpoint is enabled with an empty service set, so everything a
machine runs arrived by delivery, and the run generates its own key pair and the guests install the
public half from a read-only virtiofs share at boot (`cluster-authorized-key.service`).

Because rookery is resolved at run time, `base-image-configuration.nix` is not available at
evaluation and this configuration is ours, and every invariant a rookery guest has to hold is an
`assertion` in `../tests/e2e/guest.nix` whose message names what depends on it. A trim that drops
one fails `nix build` instead of producing a guest that boots and is never reachable. The
portable-service manager the second folder needs is one of them, in the same form:

> `tests/e2e/portable-image/` attaches a planner-built image by running the artifact's own
> `bin/attach` on this guest, and that script calls `portablectl`, which talks to
> systemd-portabled: a systemd built without portabled would leave that test asserting against a
> stand-in, which is the one thing this layer exists to avoid.

The others are the `virtiofs` module, the vsock transport, `nofail` on every non-root mount,
networkd rather than dhcpcd, systemd-boot on a blank OVMF varstore, the primary UART as the kernel
console, no guest firewall, the empty service set, no password authentication, the virtiofs report
unit the host reads share readiness from, and systemd's own package in the system profile. They are
rookery's, copied from its `nix/base-image-configuration.nix:25-59`; when a rookery bump breaks a
boot, diff `../tests/e2e/guest.nix` against `$ROOKERY_FLAKE/nix/base-image-configuration.nix`.

## Running pytest by hand

`devShells.planner-cluster` is the app's environment without its `exec`, assembled by the runner's
own `--print-env` so the shell and `nix run .#planner-e2e` cannot drift apart:

```bash
nix develop .#planner-cluster --command python3 --version
# Python 3.13.13 - rookery's minor version, not this repository's 3.14
nix develop .#planner-cluster --command pytest tests/e2e/portable-image/test_portable_image.py -k confinement
# 1 passed, 7 deselected in 16.06s
```

It is a shell of its own because of that interpreter: a 3.14 pytest imports no 3.13 rookery, and one
shell carrying both would leave `python3` ambiguous. Every variable it exports names a built store
path, except the two an edit has to be able to change: the deployment and the harness itself come
from the working tree, because that is the point of running by hand.

| Variable | What it names | Set by |
| --- | --- | --- |
| `PLANNER_WIRED_PAIR` | the realised wired-pair artifacts | app and shell |
| `PLANNER_WIRED_PAIR_DEPLOYMENT` | that folder's deployment - the store path in the app, the working tree in the shell | app and shell |
| `PLANNER_PORTABLE_IMAGE` | the two built images | app and shell |
| `PLANNER_E2E_GUEST_IMAGE` | the qcow2 every machine boots | app and shell |
| `PLANNER_E2E` | the layer's root, on `PYTHONPATH` so a test can `import delivery` | app; the shell puts the working tree there instead |
| `PLANNER_E2E_STATE` | the run's state root | `runner.py` |

The driver and the deployment being the working tree is the point of running by hand: an edit to
either is what runs. A shell opened where `$ROOKERY_FLAKE` cannot be fetched still opens, saying so,
and the suites then skip themselves naming what is unset. A missing device prints the banner at
entry rather than refusing: the environment is still correct, and the boot is what would fail.

## When a run fails

The runner keeps its state directory and prints `cluster state kept for inspection: <path>`; a run
that passes removes it. While a cluster is live, rookery's own CLI is on `PATH` in that shell -
`rookery status` for the table of clusters, `rookery ssh <id> alpha -- systemctl status ...`,
`rookery console <id> beta` for the serial log, `rookery display <id> alpha` for SPICE and
`rookery down <id>` to end it - and needs either the run's `$XDG_RUNTIME_DIR` or
`--run-dir <state>/rookery/rookery-<pid>-<id>`.

That state root is a short `mkdtemp` on purpose: the virtiofs socket is
`<state>/rookery/rookery-<pid>-<id>/vm-<i>/virtiofs-<tag>.sock` and `AF_UNIX` truncates at 108
bytes, so a deeper root - pytest's own `tmp_path_factory` is already one byte over - makes
`virtiofsd` exit during startup with nothing but the socket path to say why.
