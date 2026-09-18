## Why

Enrollment landed as a proof and not as a product. `enroll-a-friend-machine` put a friend machine
in the registry by its mesh name, minted a single-use credential, applied a user-scope entry over
the mesh and expired the node - on two real machines, in
`tests/e2e/friend-enrollment/test_friend_enrollment.py`. Every membership act in it is a raw shell
string a test composes: the group and the number the server's database assigned it
(`:456-462`), the credential (`:463-469`), the node list (`:237-245`) and the expiry (`:825-828`).
The folder says so in its own words - the operator's acts against the server "are `headscale`
invocations made over ssh" and "no unit of this deployment performs them" (`:15-18`). An operator
who is not this repository's test suite has nothing to run.

The command knows nothing of any of it. `planner`'s subcommands are exactly
`plan build apply status rollback` (`cli/planner.py:100-106`), and `git grep -l` for `enroll`,
`mesh`, `invite` or `credential` under `cli/` answers with no file at all.

The declared credential generator has never run. The folder's hub module
(`tests/e2e/friend-enrollment/deployment/modules/mesh/hub.nix:29-40`) declares `vars.enrollment`
with a `program`, and that program reads two names from its environment
(`tests/e2e/friend-enrollment/deployment/mint.sh:25-32`, spent at `:46` and `:48`) which `git grep
HEADSCALE_CONFIG\|HEADSCALE_OWNER` finds in `mint.sh` and in no other file of the tree. The reason
is structural rather than an oversight: a generator's program is run by the external secret backend
where generation runs (`secrets/read.nix:518-543`, `tests/e2e/generation.py:562-572`), and the
coordination server answers on a socket its own unit's state directory holds
(`hub.nix:144`) on a machine the generation host is not. The declaration is honest and inert.

The hub module cannot be reached by a real deployment. It lives inside an end-to-end folder, and
`tests/unit/layers.nix:210-222` refuses a path token in a folder's file that resolves outside that
folder (reported by `testAReaderOpensAnEndToEndDirectory`, `:1026-1034`) while `:224-235` refuses a
folder that names a sibling at all (`testAnEndToEndTestReadsAFileOfAnotherEndToEndTest`,
`:1036-1039`). A deployment that wants a coordination server copies 175 lines of yaml-in-nix.

The operator's own membership is harness python. `tests/e2e/delivery.py:614-696` brings up a
`tailscaled --tun=userspace-networking` node and `:574-611` resolves the mesh name inside the
dialing path with an ssh `ProxyCommand`, because a userspace node installs no OS resolver - the
fact `CLAUDE.md` records under "Enrollment and the mesh" - with `:784-813` running the whole thing
inside the cluster's namespaces. None of that is reachable by an operator either.

Provisioning exists as one guest image. `cli/remote.py:670-729` verifies the facts a user-scope run
rests on - the three fixed roots (`:86-88`, asked at `:683-697`), lingering and the user manager
(`:698-709`), the account's portabled and a traversable home where an image entry is placed
(`:637-667`, admitted at `:710`), `systemd-mountfsd.socket` and `systemd-nsresourced.socket`
(`:711-719`) and the kernel's userns knobs (`:720-728`) - and creates none of them. What creates
them is `tests/e2e/guest.nix`: the account with `linger` and `homeMode = "711"` (`:319-328`,
asserted at `:204-216`), `nix.settings.trusted-users` (`:335`, asserted `:219-220`), the three
tmpfiles roots (`:36-49`, `:337-341`, asserted `:222-229`), the verity certificate under
`/etc/verity.d` (`:61-68`, `:343-347`, asserted `:231-235`), the polkit rule (`:349-362`, asserted
`:237-242`), `systemd-mountfsd` and `systemd-nsresourced` copied in and enabled by drop-in
(`:364-385`, asserted `:174-186`), the user portabled and its D-Bus activation (`:387-392`,
asserted `:188-193`), and a systemd rebuilt with `-Dvmlinux-h=provided` off the guest kernel's own
BTF (`:70-98`, asserted `:196-201`). Root's one-time work is a file only this repository's test
machines read.

**The honest limit, stated before anything is promised.** A machine can receive a user-scope entry
only where all six of those facts hold. Five are declarations root makes once; the sixth, on the
pinned nixpkgs, is a rebuilt systemd, because that build has no `/sys/kernel/btf` and nsresourced
then exposes no user-namespace interface at all (`tests/e2e/guest.nix:70-82`). Below systemd 260
there is no per-user portabled to talk to, and the pinned nixpkgs resolves 261.1
(`openspec/changes/run-an-entry-without-root/design.md:22-23`). So a friend's arbitrary laptop
cannot receive a user-scope entry, and this change does not pretend otherwise: what it can do
unprovisioned is *join the mesh*, which needs a credential and a client and nothing else.
Receiving an entry is a second fact, and it costs one root declaration on a machine whose
configuration somebody can edit - the operator's own fleet, or a friend running NixOS who applies
one published module once. Membership and eligibility are two facts and this change keeps them
two.

## What Changes

- **Three enrollment verbs on the operator's command**, beside the five subcommands
  (`cli/planner.py:100-106`, one subparser each at `:135-205`): `invite` mints the credential the
  deployment declares, `members` prints what the coordination server admits, and `expel` ends one
  membership. Each takes a target the way every other subcommand does (`cli/manifest.py:219-262`),
  reads the coordination entry off the built deployment, and runs one step on that entry's machine
  over the channel every other remote step uses.
- **The deployment states which entry coordinates the mesh**, beside the realisation statement and
  never inferred, the way `realise` is stated (`operator/read.nix:637-650`). A statement naming no
  placed entry is a row, as a `realise` key naming no entry already is (`:690-703`), and the
  deployment record publishes the coordination facts the way it publishes each realiser's
  `scopes` and `holdings` (`:753-763`).
- **The operator's own configuration is a store object the published module renders**, named so
  that its extension is the one the server's own loader requires. That is what the harness works
  around by hand today: `test_friend_enrollment.py:192-203` states why the store object the unit is
  bound cannot be handed to the tool - it is named by a digest with no suffix - and `:393` installs
  a copy at a host path of the test's own. The workaround does not become the product: the unit
  keeps reading the declared `configData` file whose bytes the plan holds (`hub.nix:152-163`), and
  the operator's invocations read a second object built from the same derivation of the same socket
  path, so the two cannot disagree.
- **The declared credential generator becomes runnable, where the server answers.** `invite` runs
  the credential value's own `program` - the store path the plan records - on the coordination
  entry's machine with `out` set, the contract the external backend already runs a generator under
  (`secrets/read.nix:518-543`, `tests/e2e/generation.py:562-572`), and writes the files it wrote
  into the value source at the paths the plan names for them. The two environment names nothing
  sets (`mint.sh:25-32`) disappear: the program names the administrative object, and the numeric
  owner id it needs is read back the way the folder reads it (`:456-462`). The credential is still
  a generated secret delivered to no machine, its bytes still travel on a step's stream and enter
  no argument vector - the property `tests/e2e/test_harness.py:3602-3645` asserts over every
  encoding of the bytes - and the handover is still the operator's own act outside the tree.
- **A published mesh-hub module**, so a deployment places a coordination server without copying a
  test folder. What the cluster chose stops being the module's text and becomes a declaration: the
  plain HTTP url built from the machine's address (`hub.nix:68`) and the listener on every
  interface (`:72`), `verify_clients: false` with the reason the cluster has
  (`:97-102`), the empty relay url and path lists (`:103-104`), the embedded relay region
  (`:88-96`), the empty ACL policy path (`:127-132`), the disabled metrics listener (`:75`), the
  prefixes (`:80-83`) and the node expiry of zero (`:108-112`). Two of them the module refuses to
  default and takes as arguments of its own function, the way the folder's module already takes
  `{ headscale, mintProgram }` (`hub.nix:9`): the url a client is configured with, so no module
  silently chooses plain HTTP, and the admission policy, so no published module ships a
  deployment that admits everything by default.
- **A published provisioning module**, carrying the facts `cli/remote.py:670-729` verifies as one
  declaration a machine's own configuration imports: the account with lingering and a traversable
  home, the trusted login, the three tmpfiles roots, the verity certificate, the polkit rule, the
  two upstream sockets and the user portabled. It creates no credential, rebuilds no systemd and
  holds no verity private half; the two facts it cannot create it asserts, naming what to do. The
  proof is that `tests/e2e/guest.nix` becomes its consumer rather than a second copy of it - the
  tested path and the demo path become one text - and what stays in the guest is exactly the two
  guest facts: the snakeoil credential (`:147-150`, `:327`) and the systemd rebuilt for a nixpkgs
  whose sandbox has no BTF (`:70-98`).
- **The end-to-end folder proves the verbs.** `tests/e2e/friend-enrollment/` keeps its two
  machines and its phases and stops composing the server's own verbs: its hub becomes a consumer
  of the published module, its four cluster-only choices become four stated settings, and each
  membership phase runs a verb of the command. What stays harness-only is what only a test needs -
  the machines, the throwaway presenter node (`test_friend_enrollment.py:248-263`), and the
  operator's own userspace membership (`tests/e2e/delivery.py:614-696`).

Non-goals, named rather than designed: no self-installing bundle for a machine no run can dial,
which `openspec/changes/INTEGRATION.md:81-84` names and keeps reachable; no mesh-provider
abstraction and no slot pools, both parked with their triggers in
`openspec/changes/PARKED.md:29-38` and `:65-73`; no support for a machine whose systemd is older
than the per-user portabled, the floor being systemd 260; and no provisioning declaration for a
machine whose configuration this repository cannot express, for which
`cli/remote.py:670-729` stays the checklist. Every one of those is what
`openspec/changes/INTEGRATION.md:170-181` records the whole demo set as not closing, this change's
limit included.

## Capabilities

### New Capabilities

- `operator/enrollment-command`: the three verbs an operator runs against a coordination server
  the deployment places - how a verb learns which entry that is, what a verb may print, where the
  credential's bytes go, and which refusals are the command's own rather than a diagnostics row.
- `operator/machine-provisioning`: the one-time root work a machine needs before a run can write
  to it, as a published declaration a machine's own configuration imports, holding exactly the
  facts the preflight verifies and none of the facts a test machine needs.

### Modified Capabilities

- `tooling/consumer-surface`: the flake publishes the two modules, each under a name whose
  namespace says which kind it is - a planner leaf module a deployment composes, and a machine
  module a machine's own configuration imports - and neither is reachable only as a path inside
  this repository's source.
- `tooling/repository-shape`: a new top-level directory of published modules, and the class it
  belongs to.
- `delivery/real-cluster`: a membership act is a step of the operator's command, and the folder
  that proves enrollment holds no shell composing the coordination server's own verbs.

## Impact

- `cli/planner.py`: three subcommands and their help, in the one table at `:145-151`.
- `cli/enrollment.py` (new): the three verbs, the coordination entry's reading, and the value
  source write.
- `cli/manifest.py`: the coordination record the reading publishes, decoded and refused.
- `cli/remote.py`: one step per verb, addressed by the machine's scope like every other step.
- `operator/read.nix`: the coordination statement, its refusal, and the record's table.
- `modules/` (new top-level directory): the published mesh-hub leaf module and the published
  provisioning machine module, with `modules/flake-module.nix` in the flake's imports the way
  `cli/flake-module.nix` is (`flake.nix:43-48`).
- `flake.nix`, `flake-module.nix`: the two published outputs, and the published leaf module handed
  to every folder the way `operator` already is (`flake-module.nix:155-173`).
- `tests/unit/layers.nix`: `modules` in `classOf` (`:56-85`) and in `scannedDirectories`
  (`:296-307`).
- `tests/e2e/guest.nix`: imports the published provisioning module and keeps the two guest facts.
  The edit re-keys every folder's snapshot cut, so `rookery snapshot gc --all` follows it.
- `tests/e2e/friend-enrollment/`: the hub as a consumer, the cluster's choices as settings, and
  one verb per membership phase.
- `tests/e2e/test_harness.py`: the verbs' recorded argv, and the credential's absence from it.
- `docs/operator.md`, `docs/cluster.md`, `README.md`, `CLAUDE.md`.
- `lib/`, `image/`, `flakelet/`, `secrets/`: untouched. Nothing this change edits is evaluated by
  `perf/eval.nix`, so the gate is expected byte-stable.
