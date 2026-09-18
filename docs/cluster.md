# Real machines, and what a delivery does to one

Every suite in the unit layer - the nix-unit suites [`tooling.md`](tooling.md) lists, and the
specification cross-walk it derives - evaluates a plan or inspects the bytes one produces. This
layer hands a built artifact to a machine that did not build it, over a network, and then asks that
machine what it now runs.

None of it is a `check`. A build sandbox has no `/dev/kvm`, no `/dev/net/tun` and no
`/dev/vhost-vsock`, and it cannot ask a daemon whether a delivered path is valid, so the machine
layer is one app:

```bash
nix run .#planner-e2e                   # every folder, one after another
nix run .#planner-e2e shared-postgres   # two machines, one cluster, two databases
nix run .#planner-e2e wired-pair        # two machines
nix run .#planner-e2e portable-image    # one machine booted, two images built
nix run .#planner-e2e secret-delivery   # three machines
nix run .#planner-e2e generated-secret  # three machines, a real generator and a real store backend
nix run .#planner-e2e newcomer          # three machines, and a build that runs on one of them
nix run .#planner-e2e user-scope        # one machine, deployed as an account
nix run .#planner-e2e friend-enrollment # one machine reached only by its mesh name
nix run .#planner-e2e -- nosuchfolder   # refused, without building or booting anything
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
    friend-enrollment
    generated-secret
    newcomer
    portable-image
    secret-delivery
    shared-postgres
    user-scope
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

## The folders

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
`tests/e2e/<folder>/deployment/default.nix`, so another folder needs no registration anywhere and
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
[specification of applying a deployment](../openspec/specs/operator/apply-command/spec.md),
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

The folder's third build is `retired`, whose instances are its own minus `sweep`, exposed as
`packages.planner-e2e-wired-pair-retired` by the name rule above. `site` is placed on the same tag,
so the server machine stays named and reachable while `sweep:job` on it is a holding no build names,
which is what the three session-scoped phases at the end of the file are for: a report against
`retired`, which names the holding and exits zero; an apply of `retired` without `--retire`, which
announces the same holding, says nothing was removed and leaves the entry running; and the same
apply with the flag, which asks the endpoint to remove it and reports what the endpoint kept.
`sweep`'s own unit is started by hand before that, because the folder's schedule is `daily` and the
job fires during no run, and the file it wrote is read back after the retirement: a retirement
deletes no state.

One test per scenario of
[`delivery/real-cluster/spec.md`](../openspec/specs/delivery/real-cluster/spec.md),
named after it, plus one per scenario of
[`tooling/machine-snapshots/spec.md`](../openspec/specs/tooling/machine-snapshots/spec.md),
which is about how the machines were obtained rather than what the plan claims, plus the scenarios
of
[`apply-command/spec.md`](../openspec/changes/retire-an-entry-a-build-no-longer-names/specs/operator/apply-command/spec.md)
and
[`machine-report/spec.md`](../openspec/changes/retire-an-entry-a-build-no-longer-names/specs/operator/machine-report/spec.md)
that need an endpoint to answer for what the machine still holds.

### `secret-delivery` - three machines

Three machines and one generated secret, and the subject is the set. `issuer` on `alpha` generates
a session token; `probe` on `beta` declares a read of it; `gamma` runs a service that declares no
generator and no slot. The plan names two machines in that value's delivery set and the run
delivers the bytes to exactly those, so the third machine holding nothing is an assertion rather
than an omission. The consumer then authenticates with the file it was given and is refused
without it, which is what makes the delivery the thing under test rather than the path. A second
value is declared `deploy = false`: its public half travels in the plan as an export the consumer
reads from its environment, and no machine holds a file of it.

Each of the three machines declares a `sealRecipient`, so a delivery leaves a sealed copy of every
value beside the plaintext and each machine is given the unsealer the build made for it. `gamma`
declares a recipient and receives no value, which is what shows that the unsealer follows the
delivery set rather than the placement: the deployment record's table of machines names `alpha` and
`beta` and nothing else.

The folder's first phase is provisioning, the one thing an operator does before an apply: the
parent directory is created `0700` and the age identity whose public line the registry declares is
installed at `/var/lib/planner/age.key` at `0400`, on every machine. A phase and never a
preparation of the snapshot cut, because a preparation body does not run on a cache hit and a file
left by an earlier run is a replay rather than evidence.

Three phases then read what a delivery left. The applied phase asserts the copy beside the value,
that the copy and the directory holding it are the unsealing account's alone whatever the record
opens the plaintext to, and that a second apply reports the unsealer install as unchanged. It then
produces each condition the report has a line for and repairs it: a copy replaced by bytes the
machine cannot open, a copy removed, and both copies of a value cleared together, which is what a
report naming a missing value needs now that a reboot no longer produces one. The machine's own
`bin/unseal` is run on the machine over one damaged copy and one good one, and it names the value it
could not open, leaves that path empty and restores the other.

The last phase is still the reboot, because `/run` is still what a reboot empties, and it is the
claim the whole change is for: no command is run against the machine afterwards, every value is at
its own path again with the ownership and mode its record states, and the reader the phase before it
stopped comes up against the restored file and reads the bytes of the last delivery. Each of those
tests repairs what it damaged, since the file order is the order and nothing is restored between
phases, so the phase below each one starts from a machine holding everything.

One test per scenario of
[`delivery/real-cluster/spec.md`](../openspec/specs/delivery/real-cluster/spec.md), plus the
scenarios of
[`generated-values/spec.md`](../openspec/changes/unseal-a-value-after-a-reboot/specs/delivery/generated-values/spec.md),
[`apply-command/spec.md`](../openspec/changes/unseal-a-value-after-a-reboot/specs/operator/apply-command/spec.md)
and
[`machine-report/spec.md`](../openspec/changes/unseal-a-value-after-a-reboot/specs/operator/machine-report/spec.md)
that need a machine to answer for the copies it holds.

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

The folder also owns every claim this repository makes about `portablectl`, because it is the only
place a real one runs. It builds the same deployment a second time as
`planner-e2e-portable-image-changed`, attaches neither, and asks `planner status` three times: the
machine holding this build is `current`, the machine read against the second build carries both
identities, and an apply repeated over an attached entry says so instead of running the attach
script again. One phase stops the units and leaves the image attached, because the tool prints
another word for that and only the word for a detached image reads as absence.

`beacon:ping` is the entry that is there to be dropped: one instance on the booted machine's own
tag, declaring one long-running unit and no host path, and a third build, `retired`, whose instances
are the folder's own without it. Its phases come after the one that leaves the machine with nothing
attached, which is why the first of them re-attaches that entry's image with the artifact's own
`bin/attach`, and the rest report and apply `retired` with `--retire`. What they assert is the half
only a real `portablectl` answers: an image the machine holds for no entry of the build is named as
the machine listed it and no plan key is derived from that name, an image of an earlier build of an
entry the build still names is the line that carries both identities rather than a second line
about a holding, and a retired image is detached with the service manager knowing none of the units
the attachment created. That retirement is `portablectl detach --now` over the name the listing
printed and not the artifact's own script: `bin/detach` is still what the detaching phase runs and
is not what retires a holding.

One test per scenario of
[`realiser/portable-service-image/spec.md`](../openspec/specs/realiser/portable-service-image/spec.md)
that is about what a real machine does with a built image, plus the image scenarios of
[`machine-report/spec.md`](../openspec/changes/answer-whether-a-machine-is-current/specs/operator/machine-report/spec.md)
and the repeated-apply scenario of
[`apply-command/spec.md`](../openspec/specs/operator/apply-command/spec.md), plus the image
scenarios of
[`machine-report/spec.md`](../openspec/changes/retire-an-entry-a-build-no-longer-names/specs/operator/machine-report/spec.md)
and the retired-image scenario of
[`apply-command/spec.md`](../openspec/changes/retire-an-entry-a-build-no-longer-names/specs/operator/apply-command/spec.md).

### `generated-secret` - three machines

The same delivery-set claims as `secret-delivery`, over bytes nothing here wrote. `issuer:api` on
`alpha` declares two generators, `root` and a `token` that reads it; `probe:client` on `beta`
declares a read of the secret export, which is what puts `beta` in the value's delivery set; the
instance on `gamma` declares neither a generator nor a read. Each generator declares the `drvPath`
of the program that produces it, the external tool runs those programs in its own sandbox, and
`../tests/e2e/generated-secret/deployment/backend.py` is the `age` store backend that keeps what
they produced under the run's own state root. The folder's third build is that same `age`, so a
run mints its identity with the one it was built against rather than with whatever the host has on
`PATH`.

The folder builds its plan twice, because a plan is a function of `varsState`. Its
`deployment/args.nix` is the deployment on its own, taking `{ planner, packages, varsState }` and
returning arguments: `deployment/default.nix` calls it against a declared state, every file
present and no bytes, so that the unit files and the generator configuration are a function of the
declaration alone. `operator.mkGeneration` writes the second evaluation out as `plan.nix` beside
the configuration, and `../tests/e2e/generated-secret/test_generated_secret.py` evaluates it at
run time against the state the backend answered, which is the plan every assertion reads. That is
what the folder's `generation` build is: `secrets.json`, `names.json` and `plan.nix`, none of them
carrying a byte of any value.

`../tests/e2e/generation.py` is the operator side: it resolves the tool from `$NIXOS_SECRETS_FLAKE`
with `--refresh`, reads `varsState` from the backend one declared file at a time, fetches the bytes
of a public file only, and compares each stored value's recorded provenance with the plan key it
was generated from before anything is delivered. An unresolvable tool and a kernel that denies the
sandbox its user namespace each skip the folder with a reason, which `../pytest.ini`'s `-rs` prints.
What the whole composition is and what it inherits from the external tool is
[secrets.md](secrets.md).

One test per scenario of
[`delivery/generated-values/spec.md`](../openspec/specs/delivery/generated-values/spec.md),
plus the one scenario
[`delivery/real-cluster/spec.md`](../openspec/specs/delivery/real-cluster/spec.md)
adds: a value's bytes come from a real generator rather than from the test.

### `newcomer` - three machines, and a walk that runs on one of them

Three machines, and the subject is not the deployment: it is whether somebody who is not this
repository can build and apply one. A workstation boots beside `alpha` and `beta`, belongs to no
plan, and runs every step of the walk itself. What this host does is hand that machine two store
paths - the checkout's tracked content, and the key the image authorizes - with one `nix copy`
inside the cluster's namespace. Nothing else about the walk happens here.

`template/` is what a reader copies: a `flake.nix` naming the published input, and a deployment of
one module placed on two machines by a tag. The run copies it onto the workstation, and the
workstation locks it with `nix flake lock --override-input nixplan path:<source>`, which is where
the template stops naming the published flake and starts naming the tree under test. The lock
records the substitution, and the first test reads it there rather than trusting it: the input is
still `github:Qubasa/nixplan`, its resolution is the copied source, and `nixpkgs` is a `github:`
entry the machine fetched over the network for itself.

Then, three commands, each of them `nix run path:<source> --` on the workstation: `build`
substitutes what the machine's store lacks and builds the deployment there; `apply` copies each
artifact to the machine its entry names and activates it there; `status` asks both machines what
they hold. The greeting each unit writes names the address its entry was planned for, so the two
entries of one instance are two artifacts and not one copied twice, and the workstation itself runs
neither - it holds every artifact in its store, which is not a deployment.

The folder's own `deployment/default.nix` imports `template/deployment`, so this flake builds the
same deployment as `packages.planner-e2e-newcomer` and the two routes are one text rather than two
copies. That package is not what the test reads. A build on this host would prove a deployment
evaluates here, and the claim is that a machine holding nothing but the template and a source
reference can do it, so every evaluation and every build of the walk happens on the workstation,
out of the template's own flake, at run time. Its cut holds the boot and nothing of the walk: no
lock, no store the walk filled, no artifact, which is why the fetch is paid on every run.

This is the one cluster of the layer that is not hermetic. `delivery.cluster_stage` takes
`offline=False` for it, which adds the `pasta` uplink and an upstream for the cluster's resolver,
because a machine that obtains its own inputs cannot be observed doing so against a local cache.
What it goes out for is the command's interpreter and the build's inputs, around 340 MB; the
nixpkgs *source* is already in the image, since a NixOS system pins its own flake in the registry,
and nix never downloads a locked input whose hash is already valid in the store. Without egress
the folder skips itself and says so: a green run there would be a lie. The image carries
`nix-command`, `flakes` and 6 GiB of spare filesystem for the same machine.

### `shared-postgres` - two machines, one cluster, two databases

One instance publishes one capability per configured database, and two other instances each wire
one of them. `pg:cluster` on `alpha` runs two units - a root one-shot that initialises the data
directory, writes the authentication file and applies each role's delivered password, and a
long-running server as the machine's `postgres` account, ordered after it. `near-app:client` shares
that machine and reads the `eu` database; `far-app:client` is on `beta` and reads `us` over the
address and port the plan recorded.

What only this folder can show is the negative half of a delivery set. Each database's password is
its own generated value, and the machine that is left out of one set is a working consumer of the
same provider rather than a machine running nothing: `beta` holds `password-us` and no file of
`password-eu` exists on it. Beside that, one cluster identifier answers both databases, a
credential of one is refused by the other with the server's own message, and restarting the server
leaves the data written before it readable and the one-shot's start timestamp where it was.

Two accommodations the vocabulary forces are visible in the folder's own text. The server's knobs
are command-line flags rather than a configuration file, because the flakelet realiser runs no step
on the machine that could assemble one; and the one-shot is the only reader of a delivered
password, because a delivered value lands at `0400 root` and the account the server runs as cannot
open one. The account itself is declared in `../tests/e2e/guest.nix`: nothing in a plan creates one.

The data directory is state, so this folder's stage declares its own disk through
`delivery.cluster_stage`'s `disk_gib` rather than growing the shared image, which is part of every
other folder's cut key.

One test per scenario of
[`delivery/real-cluster/spec.md`](../openspec/specs/delivery/real-cluster/spec.md),
named after it.

### `user-scope` - one machine, deployed as an account

One machine, and the privilege is the subject. Its registry record declares `scope = "user"`, so
every step of the run addresses an ordinary account rather than root: the guest provisions that
account the way [`operator.md`](operator.md) documents it - the roots writable, lingering enabled
and the verity public half installed - and nothing in the folder's own text is root.

The deployment places one image entry on that machine and delivers one generated value to it,
stating no ownership on the value's file, because a delivery in this scope cannot chown and a
record that stated an owner would be a planner row rather than a test. Every host path a unit reads
is derived inside `impl` from the entry's own identity, as the host-path scan over every folder's
deployment requires.

What the phases assert is the scope's own three claims: the preflight question was asked on that
machine before anything there was written, the entry's units are the account's own - the user
service manager runs them, `portablectl --user` holds the image attached and the served port is one
no account needs a capability to bind - and a reboot brings them back, because lingering is what
starts the account's manager with nobody logged in.

One test per scenario of
[`apply-command/spec.md`](../openspec/changes/run-an-entry-without-root/specs/operator/apply-command/spec.md)
and
[`portable-service-image/spec.md`](../openspec/changes/run-an-entry-without-root/specs/realiser/portable-service-image/spec.md)
that needs a machine to answer.

### `friend-enrollment` - two machines, one of them reached only by a name

Two machines, and the difference between their addresses is the whole folder. `hub` declares an
address the cluster's own network resolves and runs the coordination server as a planned entry like
any other, with a unit, a state directory and a configuration file the module derives from its own
identity, rather than as something the guest image was wired with. `friend` declares no address the
operator can route to: its registry `address` is the name the mesh gives it, and its record states
`scope = "user"`, so once it is a member the entry placed there is an ordinary account's image
entry and nothing about that entry is about enrollment.

The credential is a generated secret of the deployment. The hub entry's generator mints one
single-use key with a stated expiry, `deploy = false` keeps it off every machine, and the operator
reads it out of the value source and hands it over outside the tree, which is the one step no
command of this repository takes. Its bytes reach no plan field and no argument vector, the
discipline every secret value of this tree already has.

The transport is the host's own and not the operator's network. The run brings up an unprivileged
userspace-networking node inside the cluster's namespace, and every ssh command reaches a mesh name
through a `ProxyCommand` of that node, because a node with no OS resolver of its own resolves the
name only inside the dialling path.

The phases are ordered and the file order is the order: the friend joins with the credential and
the server's node list names it; an apply over the mesh name asks the user-scope preflight first
and activates the entry under the account's own manager; a second machine presenting the same key
is refused by the server in the server's own words, as is a key past its expiry; and a declared
machine that never joined is refused at its first step, naming what the dial answered, with nothing
written anywhere after the refusal. The last phase expires the friend's node on the server, which
removes the wire every phase above it stood on: the report names the machine as one it could not
ask and exits non-zero.

One test per scenario of
[`machine-enrollment/spec.md`](../openspec/changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md)
that needs a machine to answer.

## Where the machines come from

Each folder's machines are a `@cluster_snapshot_fixture` stage, declared through
`delivery.cluster_stage` so every folder states the same posture once: UEFI, no Secure Boot, no TPM,
2048 MiB and two CPUs per machine, hermetic, session-scoped. `newcomer` is the one folder that
states otherwise - 4096 MiB, because one evaluation of nixpkgs needs more than 2 GiB, and
`offline=False` - and both are part of the cut's key, so its machines are never the machines of
another folder. The stage's body only waits - each machine to its vsock sshd and then to
`multi-user.target`, then the cluster to its DHCP leases - and yields. The first run boots the
machines and rookery cuts them there; every later run resumes that cut, which is RAM, device state
and the disk overlay of every slot, taken as one consistent whole-cluster cut so the frozen leases
and the route between the two machines still hold.

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
([design D8](../openspec/changes/archive/2026-09-16-apply-deployments-with-an-operator-command/design.md)):

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

`secret-delivery` commits a credential of its own for the same reason, and it is a throwaway in the
same sense. Both halves of an age identity are in
`../tests/e2e/secret-delivery/throwaway-age-identity.txt`: the public line is the `sealRecipient` of
all three machines, because a deployment the build already read cannot name a recipient a run mints,
and the private half is what that folder's first phase installs on each machine. It opens nothing
but the test tokens that folder mints on an offline guest, and nothing outside the folder reads
either half.

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

`user-scope` needs the portabled an account can reach, which is a different thing from the one
`portable-image` uses. The image therefore enables `systemd-mountfsd.socket` and
`systemd-nsresourced.socket`, the two daemons a user portabled delegates a mount and a user
namespace to, runs the per-user `systemd-portabled`, and provisions one unprivileged account: linger
enabled, so its service manager is up with nobody logged in, the deployment's fixed roots writable
by it, and the public half of the key that folder's images are signed with installed. The pinned
nixpkgs resolves systemd 261, and the per-user portabled exists since 260, so the guest can hold
the whole stack rather than a stand-in of it.

A mesh is two programs rather than a configuration, so the image runs the mesh client as a system
daemon (`tailscaled`) and carries the coordination server as a machine program (`headscale`). The
machine that coordinates a mesh and the machine that joins one are therefore the same one image:
nothing has to be delivered to make a member, and no plan states either program. Neither costs a
run anything until a login presents a credential: a client with no login server stated dials
nobody, and a server nothing started listens nowhere. Every other folder's machines therefore
carry the two and notice neither. What they do notice is the cut: every property of this image is
in every snapshot cut's key, so one more of them makes the next run of every folder cold and
leaves the cuts taken before it to be reclaimed, which is what the paragraph below is about.

Editing `../tests/e2e/guest.nix` re-keys every cut, and the stale ones have to go before anything
else runs: `rookery snapshot gc --all`, then the next run boots. A resumed cut is frozen RAM naming
a system generation the new disk does not carry, so `/run/current-system/sw/bin` is a directory of
dangling links and every remote command answers `mkdir: command not found` while `$PATH` reads
correctly. That reads as a broken write script and is a stale cut.

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
| `PLANNER_GENERATED_SECRET_DEPLOYMENT` | the same, for that folder | app and `planner-e2e-env` |
| `PLANNER_NEWCOMER_DEPLOYMENT` | the same, for that folder | app and `planner-e2e-env` |
| `PLANNER_SHARED_POSTGRES_DEPLOYMENT` | the same, for that folder | app and `planner-e2e-env` |
| `PLANNER_USER_SCOPE_DEPLOYMENT` | the same, for that folder | app and `planner-e2e-env` |
| `PLANNER_E2E_GUEST_IMAGE` | the qcow2 every machine boots | app and `planner-e2e-env` |
| `PLANNER_E2E` | the layer's root, on `PYTHONPATH` so a test can `import delivery` | app; the shell puts the working tree there instead |
| `PLANNER_E2E_STATE` | the run's state root | `runner.py` |
| `PLANNER_E2E_SSH_KEY` | the store file holding the key the image authorizes | app and `planner-e2e-env` |

One deployment row exists per folder, and the rows are written from the same discovery the packages
are, so a folder gains its variable by existing. No variable names a built
deployment: the machine layer builds one with the command, which keeps every link farm out of the
app's closure and lets a folder's build failure be a test error. A folder skips itself when a
variable it needs names nothing, and `-rs` in `../pytest.ini` is what prints the reason.

The harness and the deployments being the working tree is the point of running by hand: an edit to
any of them is what runs. A checkout where `$ROOKERY_FLAKE` cannot be fetched still opens its
shell, and `planner-e2e-env` says so rather than failing. A missing device prints the banner there
too: the environment is still correct, and the boot is what would fail.

Two variables of the fourth folder are inputs rather than exports. `$NIXOS_SECRETS_FLAKE` names the
external secret generator and defaults to the revision `../tests/e2e/generation.py` records, and
`$PLANNER_SECRETS_SSH_OPTS` reaches the `ssh` of the rendered deploy step unquoted, which is how a
run states how to reach a guest whose host key nobody has accepted. Both are in
[secrets.md](secrets.md).

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
