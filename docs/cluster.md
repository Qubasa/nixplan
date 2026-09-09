# Real machines, and what a delivery does to one

Every suite in the unit layer - the nix-unit suites [`tooling.md`](tooling.md) lists, and the
specification cross-walk it derives - evaluates a plan or inspects the bytes one produces. This
layer hands a built artifact to a machine that did not build it, over a network, and then asks that
machine what it now runs.

None of it is a `check`. A build sandbox has no `/dev/kvm`, no `/dev/net/tun` and no
`/dev/vhost-vsock`, and it cannot ask a daemon whether a delivered path is valid, so the machine
layer is one app:

```bash
nix run .#planner-e2e                  # three folders, six machines
nix run .#planner-e2e wired-pair       # two machines
nix run .#planner-e2e portable-image   # one machine booted, two images built
nix run .#planner-e2e secret-delivery  # three machines
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
    secret-delivery
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
minor version, so the runner also compares the two interpreters and refuses with both named.
Neither side names a version: `../pytest-env.nix` takes this nixpkgs' default `python3` and
rookery takes its own. The one dev shell that carries that environment lives in
`../devshells.nix`.

## The three folders

Each directory under `../tests/e2e/` is one end-to-end test and its own fixture: exactly one
`test_*.py` and a `deployment/` of `default.nix`, `machines.nix`, `instances.nix`, `interfaces/` and
`modules/`. A folder carries no builder of its own. Its `deployment/default.nix` takes `pkgs`,
`planner` and `operator`, applies its own packages to its own modules, states how its entries are
realised, and returns one deployment build per name:

```nix
{ pkgs, planner, operator }:
{
  default = operator.mkDeployment { /* args, and realise when the default is wrong */ };
}
```

A build named `default` is exposed as `packages.planner-e2e-<folder>`, and any other name as
`packages.planner-e2e-<folder>-<name>`, which is where `planner-e2e-wired-pair-changed` comes from.
A folder owns its fixture and the statement of how its entries are realised; the planning, the
realising and the collecting are the repository's and arrive as `operator`, documented in
[`operator.md`](operator.md).

Both discoveries happen by looking. The runner finds a folder's tests as `test_*.py` under each
directory, and `../flake-module.nix` finds a folder's deployment at
`tests/e2e/<folder>/deployment/default.nix`, so a fourth folder needs no registration anywhere and
the flake names no folder. `../tests/unit/layers.nix` holds both halves: no file of a folder names
`mkPlan`, a link farm or either realiser's builder, and every folder carrying a deployment is
reachable as a package.

`../tests/e2e/delivery.py` is what only a test needs: the plan readers its assertions use, the ssh
options a throwaway guest has to be reached with, the run's state root, and the cluster stage. It
carries no delivery step. Copying an artifact, writing a generated value, activating an entry,
asking a machine what it holds and rolling one entry back are steps of the command, and
`../tests/e2e/test_harness.py` asserts that pure half without a machine, as the `planner-delivery`
check. `../tests/e2e/guest.nix` is the guest every machine boots.

What the command itself is held to lives in the
[specification of applying a deployment](../openspec/changes/apply-deployments-with-an-operator-command/specs/operator/apply-command/spec.md),
and the division is the same one: a scenario a recorder can observe is asserted in
`../tests/e2e/test_harness.py`, and a scenario that needs a machine to answer is asserted in a
folder.

### `wired-pair` - two machines

Two machines, one plan, and the wire between them. The phases are ordered and the file order is the
order, so each test asserts the state it depends on rather than assuming it: the participants are
real machines running nothing yet; both entries are applied by the command, copied with `nix copy`
and activated through the endpoint; the receiving machine evaluated nothing and can reach no store
but its own; the wire is traffic to the address the plan recorded, and cutting the far end is
visible; an unchanged redelivery is a no-op, a changed one is generation 2 and a rollback returns
generation 1; a scheduled entry is registered with its timer enabled and is not fired by deploying
it; and both machines reboot with the entries coming back without a second delivery.

One test per scenario of
[`delivery/real-cluster/spec.md`](../openspec/changes/prove-plan-on-real-machines/specs/delivery/real-cluster/spec.md),
named after it, plus one per scenario of
[`tooling/machine-snapshots/spec.md`](../openspec/changes/resume-e2e-machines-from-snapshots/specs/tooling/machine-snapshots/spec.md),
which is about how the machines were obtained rather than what the plan claims.

### `secret-delivery` - three machines

Three machines and one generated secret, and the subject is the set. `issuer` on `alpha` generates
a session token; `probe` on `beta` declares a read of it; `gamma` runs a service that declares no
generator and no slot. The plan names two machines in that value's delivery set and the run
delivers the bytes to exactly those, so the third machine holding nothing is an assertion rather
than an omission. The consumer then authenticates with the file it was given and is refused
without it, which is what makes the delivery the thing under test rather than the path. A second
value is declared `deploy = false`: its public half travels in the plan as an export the consumer
reads from its environment, and no machine holds a file of it.

One test per scenario of
[`delivery/real-cluster/spec.md`](../openspec/changes/deliver-secrets-across-machines/specs/delivery/real-cluster/spec.md).

### `portable-image` - one machine, two images

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

## Where the machines come from

Each folder's machines are a `@cluster_snapshot_fixture` stage, declared through
`delivery.cluster_stage` so every folder states the same posture once: UEFI, no Secure Boot, no TPM,
2048 MiB and two CPUs per machine, session-scoped. The stage's body only waits - each machine to
its vsock sshd and then to `multi-user.target`, then the cluster to its DHCP leases - and yields.
The first run boots the machines and rookery cuts them there; every later run resumes that cut,
which is RAM, device state and the disk overlay of every slot, taken as one consistent
whole-cluster cut so the frozen leases and the route between the two machines still hold.

```
                          total   wired-pair setup   portable-image setup
before this stage existed 76.4s              13.50s                14.90s
cold (boot and cut)       80.9s              11.74s                11.29s
warm (resume)             60.9s               1.41s                 2.74s
```

The setup rows are the whole cost of obtaining the machines, so that is where the change lands: a
warm run of the layer pays four seconds for three machines instead of twenty-six. The totals move
a few seconds run to run (a second pair of samples read 83.3s and 65.1s), so the setup rows are
the claim. Selecting one test feels it most - `nix run .#planner-e2e portable-image -k confinement`
is 4.0s warm.

What is *not* in the cut is everything the tests are about. The delivery, the activation, the
redelivery, the rollback and the attachment run against the machines on every run, warm or cold,
because the evidence those tests read is the report the machines and those acts produce - and a
preparation body does not run on a cache hit, so anything it produced would be a replay.
`test_a_cut_carries_no_delivery` holds that line from the other side: freshly obtained machines
report no registered entry and hold no artifact.

The cut's key is content-addressed over the guest image, the preparation's source and its
project-local closure, the cluster's shape, the host CPU, the QEMU build and the python environment
rookery itself runs in. Anything moving there is a miss and a cold prepare, never a stale pass: a
rookery nixpkgs bump that moved its interpreter from 3.13 to 3.14 re-keyed both cuts, and the next
run boots. Nothing about the artifacts is in the key, because the preparation never reads them, so
editing a folder's deployment leaves the boot cached.

```bash
rookery snapshot list        # the cached cuts and their sizes, about 2 GiB per machine
rookery snapshot explain KEY # which key input differs, when a hit was expected
rookery snapshot gc --all    # drop them; the next run is cold and republishes
```

The cache lives under `$XDG_CACHE_HOME/rookery/snapshots` and is reclaimable by construction:
losing it costs one cold run. It accretes, though. A key input that moves does not replace the old
entry, it orphans it, and an orphan is about 2 GiB per machine, so an afternoon of editing the
preparation body left seven entries and 21.8 GB here. `gc --all` is the hygiene; there is no
automatic eviction.

The folders keep one cut each rather than sharing one, because a cut's shape is
`vms=2;0:alpha:root;1:beta:root` against `vms=1;0:alpha:root`. That is not cosmetic: a resume seeds
one overlay and one RAM file per slot, and each slot's address is frozen inside its own saved RAM,
so there is nothing coherent for a one-machine cluster to do with beta's. Sharing would also mean
one preparation function for both folders, and a session-scoped fixture instantiates once - both
folders would then share one live cluster, which is exactly what `test_a_cut_carries_no_delivery`
and the attach tests deny. Two cuts cost 11s once and 2 GiB each; sharing would save neither the
setup time (a two-slot resume is not dearer than a one-slot one) nor the isolation.

## Building here and applying there

A run drives the operator's command, and the two halves of it run in two places
([design D8](../openspec/changes/apply-deployments-with-an-operator-command/design.md)):

- `planner build <flake reference>` runs in the pytest process, with `subprocess.run`, before a
  machine is dialled. A build is `nix build` and a read of two files, and it needs no cluster. The
  reference is `$PLANNER_E2E_FLAKE#planner-e2e-<folder>`, so what a folder applies is what
  `nix build` of that attribute produces.
- `planner apply`, `planner status` and `planner rollback` run through rookery's `Cluster.run`,
  because the machines' addresses exist only in the cluster's network namespace.

No evaluation and no build therefore happens inside the cluster's user namespace, and a folder whose
deployment fails to build fails as a test error naming the build rather than as a missing artifact.
A built deployment is the tree [`operator.md`](operator.md) describes:

```
/nix/store/...-planner-deployment/
  plan.json  manifest.json  diagnostics.json  diagnostics.txt
  entries/site-server-alpha  entries/check-client-beta  entries/sweep-job-alpha
```

`Cluster.run` replaces the environment rather than extending it, so `delivery.command_env` carries
the caller's own: the command shells out to `nix copy`, which needs its `PATH`, its `HOME` and its
daemon socket. It adds one variable, `NIX_SSHOPTS`.

Those ssh options are the guest's, and the harness is what supplies them
(`delivery.guest_ssh_options`). `-F /dev/null` is load-bearing rather than tidy: inside rookery's
single-uid user namespace a real-root-owned `ssh_config` appears owned by `nobody`, and ssh then
refuses to read it at all and fails to connect with `Bad owner or permissions`. The guest is
generated per run, so no host key was accepted beforehand and no known-hosts file, global or
per-user, exists to have written one to. The command extends what it inherits and adds nothing but
`-i` for `--ssh-key`, which is why a run passes no `--ssh-key`: the key is already in the options.

The plan stays the only answer about where a step goes: an entry's key names its machine, the
machine's record carries the address, and an entry asked for on a machine the plan did not place it
on is refused rather than dialled. `../tests/e2e/delivery.py` keeps those readers because the
assertions read the plan too, and a test that reads a plan the way the tool does is a test that can
disagree with the tool. What a folder delivers, it takes from `manifest.json`: the artifact the
build produced for that plan key, copied to the address the plan recorded and activated there
through the endpoint, both over the guest's TCP sshd.

A generated value is not an artifact. Its bytes are the operator's, and a folder that needs one
writes it into a value source directory under the run's state root and applies with
`planner apply --values <dir>`. The command checks that source against the plan before it dials,
writes each declared file at mode 0400 outside the store, and writes it only to the machines the
value's `delivery` set names.

## The guest image

```bash
nix build .#packages.x86_64-linux.planner-e2e-guest --no-link --print-out-paths
# /nix/store/jmhlh2kvn6i0vjnyf0fx5zmb08ma4s75-planner-e2e-guest-image
```

Its `nixos.qcow2` is the disk every machine boots, and is what the app and `planner-e2e-env` export as
`$PLANNER_E2E_GUEST_IMAGE`. The guest's own `toplevel` travels beside the image rather than in a
`passthru`, because `make-disk-image` builds inside a VM whose result carries none: the qcow2
references nothing, while the system inside it references everything.

One image serves every folder, and it carries no artifact of any plan and no declared flakelet
service: the endpoint is enabled with an empty service set, so everything a machine runs arrived by
delivery. It does carry the run's credential, and that is deliberate. A snapshot cut is RAM plus
device state, so a resumable cluster can mount no virtiofs share to be handed a key over, and a
key generated per run would have to be a key input of the cut and would then re-key it on every
run. Root therefore authorizes nixpkgs' published snakeoil key
(`nixos/tests/ssh-keys.nix`, `snakeOilEd25519PublicKey`, commented there as "NOT a security
issue"), the guest package exports the private half beside the image as `sshPrivateKey`, and the
run copies that store file to mode 0600 because ssh refuses to read a private key a store's 0444
leaves readable by everyone. Password authentication stays refused.

Because rookery is resolved at run time, `base-image-configuration.nix` is not available at
evaluation and this configuration is ours, and every invariant a rookery guest has to hold is an
`assertion` in `../tests/e2e/guest.nix` whose message names what depends on it. A trim that drops
one fails `nix build` instead of producing a guest that boots and is never reachable. The
portable-service manager `portable-image` needs is one of them, in the same form:

> `tests/e2e/portable-image/` attaches a planner-built image by running the artifact's own
> `bin/attach` on this guest, and that script calls `portablectl`, which talks to
> systemd-portabled: a systemd built without portabled would leave that test asserting against a
> stand-in, which is the one thing this layer exists to avoid.

The others are the vsock transport, `nofail` on every non-root mount, networkd rather than dhcpcd,
systemd-boot on a blank OVMF varstore, the primary UART as the kernel console, no guest firewall,
the empty service set, that the only way in is the one key the image carries with no password
accepted, that no filesystem is a virtiofs share, and systemd's own package in the system profile.
Most are rookery's, copied from its `nix/base-image-configuration.nix:25-59`; when a rookery bump
breaks a boot, diff `../tests/e2e/guest.nix` against
`$ROOKERY_FLAKE/nix/base-image-configuration.nix`. The last two are this layer's own, and they are
what keeps the guest snapshottable.

## Running pytest by hand

`nix develop` is one shell, and the machine layer's environment is not in it at entry: most
variables in the table below name a built artifact, and a store reference in the hook would make
entering the checkout build the guest image. `planner-e2e-env` prints those exports when it is
called, followed by the runner's own `--print-env`, so a manual `pytest` runs against the same
artifacts and the same rookery `nix run .#planner-e2e` would have used:

```bash
nix develop --command bash -c 'eval "$(planner-e2e-env)"; python3 --version'
# Python 3.14.7 - this repository's; the runner refuses if rookery's minor differs
nix develop --command bash -c 'eval "$(planner-e2e-env)"; pytest tests/e2e/portable-image/test_portable_image.py -k confinement'
# 1 passed - the machine was resumed, not booted
```

`nix develop` consumes `-k` as its own `--keep-going`, which is why the selection sits inside
`--command bash -c '…'`. The first call builds every artifact it names, the guest image included;
after that it is a store lookup.

The interpreter is the one thing neither side pins: `PYTHONPATH` carries rookery only within one
minor version, so the runner compares the two and refuses with both named when they diverge - a
rookery nixpkgs bump is what moves them. `planner-e2e-env` prints that refusal, exports the
artifacts anyway, and the suites then skip themselves naming rookery.

Every variable it exports names a built store path, except the ones an edit has to be able to
change: each folder's deployment, the harness itself and the checkout a build resolves against come
from the working tree, because that is the point of running by hand.

| Variable | What it names | Set by |
| --- | --- | --- |
| `PLANNER_CLI` | the operator's command, as an executable | app and `planner-e2e-env` |
| `PLANNER_CLI_SRC` | the command's source root, put on `PYTHONPATH` by `../tests/e2e/runner.py` so a test reads a built deployment the way the command reads it | app and `planner-e2e-env` |
| `PLANNER_E2E_FLAKE` | the checkout, the base of the flake reference a folder builds | app and `planner-e2e-env` |
| `PLANNER_WIRED_PAIR_DEPLOYMENT` | that folder's deployment - the store path in the app, the working tree in the shell | app and `planner-e2e-env` |
| `PLANNER_PORTABLE_IMAGE_DEPLOYMENT` | the same, for that folder | app and `planner-e2e-env` |
| `PLANNER_SECRET_DELIVERY_DEPLOYMENT` | the same, for that folder | app and `planner-e2e-env` |
| `PLANNER_E2E_GUEST_IMAGE` | the qcow2 every machine boots | app and `planner-e2e-env` |
| `PLANNER_E2E` | the layer's root, on `PYTHONPATH` so a test can `import delivery` | app; the shell puts the working tree there instead |
| `PLANNER_E2E_STATE` | the run's state root | `runner.py` |
| `PLANNER_E2E_SSH_KEY` | the store file holding the key the image authorizes | app and `planner-e2e-env` |

One deployment row exists per folder, and the rows are written from the same discovery the packages
are, so a fourth folder gains its variable by existing. No variable names a built
deployment: the machine layer builds one with the command, which keeps three link farms out of the
app's closure and lets a folder's build failure be a test error. A folder skips itself when a
variable it needs names nothing, and `-rs` in `../pytest.ini` is what prints the reason.

The harness and the deployments being the working tree is the point of running by hand: an edit to
any of them is what runs. A checkout where `$ROOKERY_FLAKE` cannot be fetched still opens its
shell, and `planner-e2e-env` says so rather than failing. A missing device prints the banner there
too: the environment is still correct, and the boot is what would fail.

## When a run fails

The runner keeps its state directory and prints `cluster state kept for inspection: <path>`; a run
that passes removes it. While a cluster is live, rookery's own CLI is on `PATH` in a shell that has
evaluated `planner-e2e-env` -
`rookery status` for the table of clusters, `rookery ssh <id> alpha -- systemctl status ...`,
`rookery console <id> beta` for the serial log, `rookery display <id> alpha` for SPICE and
`rookery down <id>` to end it - and needs either the run's `$XDG_RUNTIME_DIR` or
`--run-dir <state>/rookery/rookery-<pid>-<id>`.

That state root is a short `mkdtemp` on purpose, and the `state_root` fixture in
`../tests/e2e/conftest.py` is how rookery is told to use it: the sockets underneath it are
`<state>/rookery/rookery-<pid>-<id>/vm-<i>/<name>.sock` and `AF_UNIX` truncates at 108 bytes, so a
deeper root - pytest's own `tmp_path_factory` is already over - makes the daemon behind one exit
during startup with nothing but the socket path to say why. The run's private copy of the image's
key lands there too, so it is removed with the rest when a run passes.
