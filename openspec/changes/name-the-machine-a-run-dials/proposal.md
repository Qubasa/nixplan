## Why

A run writes secrets to whatever answers at an address. `lib/resolve.nix:52-59` lists the six keys a
machine registry record may carry - `address`, `tags`, `system`, `serviceManager`,
`microarchitecture`, `reserves` - and none of them is an identity, so a deployment cannot state
which machine it means. `cli/remote.py:262-273` then appends the command's own ssh options to the
caller's `NIX_SSHOPTS`, which is right for the options it adds and is the hole for the ones it does
not: `tests/e2e/delivery.py:332-347` sends a throwaway guest's `StrictHostKeyChecking=no` and
`UserKnownHostsFile=/dev/null` through that variable, and an operator whose shell exports it for any
reason gets a working apply that delivered a token to an impostor. The command prints nothing about
the options it connected with (`cli/apply.py:254`, `cli/report.py:116,250`), so the difference
between a verified run and an unverified one is invisible in its own output.

## What Changes

- **The registry states the machine's identity.** `machineRegistryKeys` gains `hostKey`, a string
  holding one ssh public key line, read with a new `sshPublicKey` atom in `lib/atoms.nix` over a
  grammar whose home is `lib/util.nix` beside `wordRule` and `envNameRule`. A line the grammar
  refuses is `machine-host-key-malformed` and is left out of the projection, so no malformed line
  reaches a `known_hosts` file.
- **The identity is read in the third projection of the machine reading, beside `reserves`.** It
  enters neither `machineRecords` (`lib/resolve.nix:576-593`) nor `targetOf`
  (`lib/resolve.nix:599-613`) nor any key input, because `machineKey`
  (`lib/plan.nix:31`, applied at `:1342`) hashes the record every placed entry and every
  per-placement value depends on through its own `dependsOn`. Rotating a host key would otherwise
  ask for a redelivery of every entry on the machine and a regeneration of bytes that are still
  correct.
- **The plan's `machine:<name>` record carries it as an explicit absence**, the way `address` does,
  and `operator/read.nix` publishes it per entry beside `address` (`:138-140`, `:608-621`). Those
  are the two places `cli/manifest.py` already reads an address from - `address_of` for a placed
  entry (`:219-238`) and `machine_address` off the plan's own machine record for a value's machine
  (`:241-257`) - so the identity reaches both kinds of step through the channel that exists.
- **A value delivered to a machine that declares no `hostKey` is a warning.**
  `machine-receives-a-value-unauthenticated`, produced where the delivery set is
  (`lib/plan.nix:1314-1320`), subject `machine:<name>`, which is a record the plan carries for every
  machine of any delivery set. A warning and not an error: every deployment that works today and
  every end-to-end folder declares no identity, an error would refuse all of them, and a warning
  that stopped a build would be an error.
- **The run pins the host key it was given.** For a machine whose record states a `hostKey` the
  command writes the `known_hosts` file of the run from the plan and connects with
  `UserKnownHostsFile` pointing at it and `StrictHostKeyChecking=yes`. Every step against that
  machine goes through those options, `nix copy` included, because `nix copy` reaches the machine
  over ssh and reads the same variable.
- **An inherited option that would disable the pinning is a refusal, not a silent override.**
  `StrictHostKeyChecking` or `UserKnownHostsFile` arriving from the caller's `NIX_SSHOPTS` while the
  run would dial a machine that declares a `hostKey` is refused naming the machine and the option.
  Appending cannot override - ssh takes the first value it is given, which is why the command's
  bounds on silence are appended in the first place - so refusing is the only honest answer, and
  prepending would silently defeat an operator's own statement.
- **A machine that declares no `hostKey` behaves exactly as today, and the line says so.** The
  command reports, per machine it will contact and before the first step, the address it will dial
  and either the algorithm and `SHA256:` fingerprint it pinned or that the machine states no
  identity and the caller's own options decide. The report and every refusal are computed from the
  plan, the deployment record, the value source and the connection options, all read before the
  first dial, so `--dry-run` and a real run stay comparable line by line.
- **The guest image's host key becomes a known value.** `tests/e2e/guest.nix` installs nixpkgs'
  `snakeOilPrivateKey` as the guest's only host key and exports `sshHostPublicKey` beside the
  `sshPrivateKey` it already exports, so one file still defines both halves of both credentials.
  `flake-module.nix` hands that line to each folder's `deployment/default.nix` as a fourth argument,
  the way `operator` already arrives as an argument rather than as an import, and the folders that
  dial a machine declare `hostKey` from it and connect pinned for real.
- **The harness stops sending the operator's command an option the command would refuse.**
  `command_env` carries the guest's properties minus the two the command now owns; a new
  `harness_env` keeps the full unpinned set for the harness's own `ssh` and `nix copy`, and
  `newcomer` keeps it too, its template stating no identity and exercising the compatible answer on
  a real machine.

Not in this change, deliberately:

- **The `deploy.remote` step `secrets/backend.nix` renders.** That step is a build artifact carrying
  an address and an `ssh` command of its own, and pinning it means putting a `known_hosts` file into
  a generation the external tool runs. It is a second channel with a second owner, and the
  capability that owns it is `delivery/generated-values`. This change leaves it unpinned and says so
  rather than designing a second delivery of one fact.
- **A flag for accepting an unverified machine.** `deliver-a-secret-without-exposing-it` proposed
  `--accept-new-host-key` and `--known-hosts`. A machine stating no `hostKey` is already the
  accepting case, and a second spelling of it on the command line would make the deployment's own
  statement optional.
- **Verifying that the key a machine presents is the key the registry named.** ssh does that, from
  the file the command writes, and a second comparison in python would be a reimplementation of the
  protocol's own check against an answer the command would have to parse out of ssh's stderr.

### Relationship to `deliver-a-secret-without-exposing-it`

That change's "A run cannot tell the machine it means from whatever answers at the address" paragraph
(its `proposal.md:15-22`) is this gap, cited against the same two files. Its argv complaint is
already fixed: a value's bytes travel on the step's input stream (`cli/apply.py:266-268`,
`cli/remote.py:326-384`) and enter no argv on either host. Its verdict:

- **Superseded here**, and to be struck from it: tasks 3.1, 3.2, 3.3 and 3.4 (the registry field,
  its exclusion from the hashed record, the two evaluation tests and the golden), 5.1, 5.2 and 5.3
  (the connection options, the reported line and the machine-free tests of them), and 7.5 (the
  throwaway guest's accommodation leaving `NIX_SSHOPTS`). Its `specs/operator/machine-identity/spec.md`
  is superseded whole: this change states the same three requirements against
  `planner/machine-platform`, `planner/secret-delivery` and `operator/apply-command` rather than
  inventing a capability for them, and it differs on three decisions - one key rather than a list,
  a warning rather than a refusal for a machine stating none, and no command-line accommodation.
- **Left to it**: the generated file's `mode` and `owner` (phase 1, since landed as
  `planner/secret-delivery`'s ownership requirement, which it should reconcile), the type-mismatch
  row that prints the value it refuses (phase 2), the value source's posture check (4.4), the
  image's mount point for a file it did not generate and the per-unit confinement denial (phase 6),
  and the machine-layer observation that a delivery in flight leaves the bytes in no process table
  (7.2, 7.3).
- **Narrowed, not archived.** What remains of it is real and unimplemented. It should drop
  `specs/operator/machine-identity/spec.md`, the eleven tasks above and the
  `operator/machine-identity` entry of its `## Capabilities`, and keep the rest. Its own `excused`
  entries in `tests/unit/coverage.nix` move with the file.
- **The superseded capability is not adopted, it is deleted.**
  `operator/machine-identity` has never landed: `openspec/specs/` holds no such directory, so it is
  a proposal rather than a base text, and this change states its three facts against the three
  capabilities that already own them. Routing them through a fourth path would build the diamond
  rather than remove it, because two of the three deltas here are MODIFIED blocks against sentences
  of the live specs that are now wrong, and neither sentence can move into a new capability:
  `planner/machine-platform` says the registry "SHALL refuse any other key", so an identity stated
  in one capability and refused by another is a contradiction between two live specs; and
  `operator/apply-command` says "An option the caller stated for the connection SHALL win over the
  command's own value for the same option", which is the licence this bug is written under and is
  in the requirement this change owns.

## Capabilities

### New Capabilities

- none.

### Modified Capabilities

- `planner/machine-platform`: a machine declares the identity it presents, in a projection no key
  reads, and the plan's machine record carries it beside the address.
- `planner/secret-delivery`: a machine in a delivery set that states no identity is a warning row
  naming the machine and the values it receives.
- `operator/apply-command`: the run pins the identity the deployment stated, refuses an inherited
  option that would disable the pinning, and reports what it connected with.
