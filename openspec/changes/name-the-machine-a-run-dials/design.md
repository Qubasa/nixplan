## Context

See `proposal.md` - Why. What matters for the approach is the shape of the three layers the fact
has to cross.

The registry reading is stratified. `lib/resolve.nix:459-466` reads each machine key with its shape
into `machineFields`, and three projections come off that one reading: `machineRecords`
(`:576-593`), which is the record the plan keys and hashes; `targetOf` (`:599-613`), which is the
target every placed entry records and every implementation is handed; and `machineReservations`
(`:617-619`), which is read by no key, no realiser and no subcommand. `lib/plan.nix:31` is
`machineKey`, a digest over whatever record it is handed, and `:1342` hands it
`resolved.machines`, which is the first projection. Every placed entry and every per-placement
generated value names that digest in its own `dependsOn`.

The command has one option string and one environment for a whole run. `cli/remote.py:262-273`
splits the caller's `NIX_SSHOPTS`, adds `-i` for `--ssh-key` and appends `BOUNDS`, and `:276-296`
hands that one string to every `ssh` (`:316-323`) and the same variable to every `nix copy`
(`:299-313`, which reaches the machine over ssh and reads the environment). Appending is deliberate
and correct for the three bounds on silence, and it is exactly why it cannot carry an option that
has to win.

`tests/e2e/delivery.py:332-347` is the other half of the bug in the tree: a throwaway rookery guest
is reached with `StrictHostKeyChecking=no` and `UserKnownHostsFile=/dev/null`, sent to the operator's
own command through `NIX_SSHOPTS` at `:350-359`. The guest's host keys are generated at first boot
inside the overlay, so a resumed snapshot cut presents whatever its cut froze and no deployment can
state it.

## Goals / Non-Goals

**Goals:**

- One registry field, one atom, one grammar, and a projection no key reads.
- A per-machine connection posture decided by the deployment, effective for every program the
  command reaches a machine through.
- An inherited option that would weaken that posture refused by name, before the first dial.
- Every end-to-end folder green, with at least one of them connecting pinned against a real sshd.

**Non-Goals:**

- Pinning the `deploy.remote` step `secrets/backend.nix` renders. That step is a build artifact
  carrying its own `ssh` command and its own address, so pinning it means putting a host-identity
  file into a generation an external tool runs, under a second owner
  (`delivery/generated-values`). This change leaves it as it is and says so.
- A command-line accommodation for an unverified machine. A machine stating no `hostKey` already is
  the accepting case; a flag would make the deployment's own statement optional.
- Re-verifying inside the command what ssh verifies from the file the command wrote. The protocol's
  check is the check, and a second one in python would have to parse ssh's stderr for its answer.
- Any second machine-identity field. Contract C1 fixes this change as the only owner of one.

## Decisions

### D1 - One key line, not a list

`hostKey` is one string holding one public key line, not a list of them.

A host-identity file may carry several entries for one host, so a list is expressible. It is still
the wrong shape here. ssh orders the host key algorithms it will accept by the keys it already knows
for the host, so a file naming exactly one key makes ssh ask the machine for that algorithm, and a
machine offering several host keys answers with the one that is pinned. A list would therefore buy
nothing for the case it looks like it is for - a rotation window - and would cost the thing the
field exists for: "any of these answered, so the run continued" is the same hole as no field at all,
reached more slowly. A rotation is an edit of the declaration, and the plan is a function of the
declaration.

One line is also one atom, one row and one thing to render. A list is a row per element, an order
that enters no key, and a question about whether an empty list differs from an absent field.

Rejected alternative: `hostKeys`, a list, which `deliver-a-secret-without-exposing-it` proposed
(its `tasks.md:65-69`). The narrower field is the one this change states, which is one of the three
decisions that supersede its spec rather than implement it.

### D2 - The identity is read in the third projection, and enters no key

`hostKey` is read in `machineFields` with the rest of the registry and projected beside
`machineReservations` (`lib/resolve.nix:617-619`). It is not in `machineRecords`, not in `targetOf`,
and in no `keyInput`.

The reason is the one CLAUDE.md states for the reservation, under "Keys and identity". `machineKey`
is a digest over the first projection, every placed entry on the machine names that digest in its
`dependsOn`, and so does every per-placement generated value. A host key in the first projection
would therefore mean that correcting a typo in one line of the registry re-keys every entry on the
machine and every value delivered to it: a redelivery of artifacts that did not change and a
regeneration of bytes that are still correct, because an operator rotated a key. An entry key is a
statement about what was built for the machine, and which key its sshd offers is not one of those
facts.

It is not in `targetOf` for a second, independent reason. A target is what an implementation is
handed and what a module may render from, and every field of it is hashed for exactly that reason
(`lib/resolve.nix:595-598`). Nothing a module renders is a function of the machine's host key, and
putting it there would both re-key and hand a module a credential-shaped string it has no business
interpolating.

### D3 - The grammar has one home, and the atom reads it

`lib/util.nix` gains the rule beside `keySeparators`, `wordRule` and `envNameRule`:

```
sshKeyAlgorithm = "[a-z][a-z0-9-]*(@[a-z0-9._-]+)?";
sshKeyBlob = "([A-Za-z0-9+/]{4})*([A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=|[A-Za-z0-9+/]{4})";
sshKeyComment = "[^[:cntrl:]]+";
sshPublicKeyRule = "${sshKeyAlgorithm} ${sshKeyBlob}( ${sshKeyComment})?";
sshPublicKeyAdmits = "an algorithm name, the key in base64 and an optional comment, as one line";
unpinnable = value: !(isString value) || match sshPublicKeyRule value == null;
```

`lib/atoms.nix` gains `sshPublicKey = korora.typedef "sshPublicKey" (v: !util.unpinnable v)` and
therefore gains `util` as an argument, wired in `lib/default.nix`. That is the one structural
consequence of putting the rule in its one home, and it is the right way round: the row in
`lib/resolve.nix` names `util.sshPublicKeyAdmits`, so the refusal and the grammar cannot drift, the
way `unit-env-name-malformed` and `envNameRule` already cannot.

What the rule holds, and why each part is load-bearing:

- **No line break, by construction.** `builtins.match` anchors the whole string, the algorithm and
  blob classes carry no whitespace, and `[^[:cntrl:]]` excludes every control character, so `\n`
  and `\r` are refused wherever they appear. A line break is the one failure that is not merely a
  bad value: the command writes `<address> <hostKey>` as one entry of a file read one entry per
  line, so a break would end that entry and open a second one naming whatever followed it - an
  identity the deployment never stated, inserted by the deployment.
- **Padded base64 of a length that decodes.** The blob alternation forces a length that is a
  multiple of four with correct padding, so a grammatical line always decodes. That is what lets
  the command compute a fingerprint for its report with no failure mode of its own, and it is the
  reason the command performs no syntax check of its own.
- **An algorithm name and nothing else in that position.** `[a-z][a-z0-9-]*` with an optional
  `@domain` part admits `ssh-ed25519`, `ssh-rsa`, `ecdsa-sha2-nistp256` and
  `sk-ssh-ed25519@openssh.com`, and refuses the two things that would change the meaning of the
  line: a `known_hosts` marker such as `@revoked` or `cert-authority`, and a line that already
  carries a host field in front of the algorithm, whose second word would then have to be an
  algorithm name and is not base64.
- **The comment stays free.** `[^[:cntrl:]]+` admits the spaces a real comment carries, and the
  space before it is required to be followed by something, so a trailing space is a refusal rather
  than an empty comment.

The library does not decode the base64 and does not check that the bytes inside name the algorithm
in front of them. Nix has no base64 decoder in `builtins`, an atom that needed one would be a build,
and a key whose blob disagrees with its algorithm is refused by ssh from the file the command wrote
- reported as the machine step it is. Pretending to a check the layer cannot make is worse than
naming the check the protocol makes.

### D4 - A refused line is recorded nowhere, and earns both rows

`machine-host-key-malformed` is an error, and the projection records `null` for that machine. This
is the treatment a name carrying a key separator gets: the value is left out of everything built
from it, so no consumer of the plan is ever handed a line it cannot write into a host-identity
file, and a hand-written plan cannot smuggle one past the command either.

The machine therefore also earns `machine-receives-a-value-unauthenticated` where it receives a
value, which is two rows for one mistaken line. That is deliberate and has a precedent stated in
CLAUDE.md under "Keys and identity": completeness is read off the value the reading produced rather
than off the presence of the key, so `address = 22` is as incomplete as no address and earns both
the malformed declaration and the incomplete target. Two facts are true - the line is not a key,
and the machine's identity is unstated - and each has its own resolution.

### D5 - The warning is produced where the delivery set is, and its subject is the machine

The row is built in `lib/plan.nix`, in the walk that already computes `delivery` (`:1314-1320`),
over the union of the delivery sets grouped by machine. One row per machine, naming the values,
subject `machine:<name>`.

The subject is the machine because the resolution is the machine's: declare `hostKey` in the
registry. Subjecting each value instead would put one row per value in the table for one missing
line and would name, as the thing at fault, a declaration that is correct. `machine:<name>` is a
record the plan carries for every machine this row can name: a delivery set is the owning member's
surviving placements plus the machine of a placed reader, both of which carry a placement, and
`lib/plan.nix:1402,1419` builds a machine record for every machine of `usedMachines`.

The severity is a warning, and the defence is two sentences. Every deployment in this repository and
every folder under `tests/e2e/` states no identity today, so an error would refuse all of them at
once - a change that made the tree unbuildable to report a fact about it. And CLAUDE.md's rule is
that a warning that stopped a build would be an error: the row is a statement an operator acts on
between one apply and the next, not a contradiction in the declaration, since the deployment is
coherent and what it does not say is which machine it trusts. The planner's own refusal has a
sharper home anyway - the command refuses the run that would actually weaken the pinning, from the
options it was given.

Cost: one pass over the delivery lists the walk already built, grouped by machine. No new index and
nothing per placed entry.

### D6 - The field reaches the command through the two readers `address` already has

`lib/plan.nix:1404-1419` records `hostKey` in the `machine:<name>` record, unconditionally and
`null` where none was stated or the statement was refused - the group `address` and `tags` are in,
not the group pruned of nulls. A reader must not be able to mistake the field for a plan that does
not carry it, which is the reason the deployment record carries `address` as an explicit absence.

`operator/read.nix` reads it off that record with `machineRecordOf` the way it reads the address
(`:138-140`) and publishes it per entry in the manifest beside `address` (`:608-621`), the empty
string normalising to an absence exactly as the address does. No row about it is produced there:
the planner holds that fact one stratum up, and a row here would restate a decision about a plan
the planner already reported on.

That gives the command the two readers it already has for an address, and it needs both:

- `cli/manifest.py:219-238` reads a placed entry's address off the deployment record, for a copy, an
  activation, a status question and a rollback.
- `cli/manifest.py:241-257` reads a value machine's address off the plan's own `machine:<name>`
  record, because "a value's machine need run no entry at all".

No new channel, no new artifact field, and the identity travels with the address to both kinds of
step.

Rejected alternative: a `machines` table in the manifest. It is the tidier home for a per-machine
fact, but it is a new shape in a record another change is also editing, and it buys nothing: the
plan's own machine record is already what the command reads for a value's machine.

One other change consumes this field and adds none of its own:
`unseal-a-value-after-a-reboot` reads the same record as the recipient a sealed value is sealed to
(C3), and it owns the question of whether the stated algorithm is one its backend can seal to,
refusing an unsealable one in `operator/read.nix`. This atom therefore holds the line's form and
says nothing about its type: a registry may state any algorithm ssh carries, and which of them a
seal accepts is the sealing layer's fact about its own tool.

### D7 - The channel becomes per machine, and the refusal is what makes appending safe

`remote.channel` stops returning one option string and returns a channel value that answers, per
machine, the option string and the `nix copy` environment for that machine. What it composes for a
machine that states a `hostKey`, in order:

1. the caller's own `NIX_SSHOPTS`, as today;
2. `-i` for `--ssh-key`, as today;
3. `-o UserKnownHostsFile=<the run's file> -o GlobalKnownHostsFile=/dev/null -o
   StrictHostKeyChecking=yes -o CheckHostIP=no`;
4. `BOUNDS`, as today.

For a machine that states none, step 3 is absent and the string is the string the command composes
today, byte for byte.

The run's file is one file for the whole run, written before the first dial under a directory the
run owns, carrying one `<address> <hostKey>` entry per machine that states one. It is written in
both modes, because `--dry-run` replaces the channel every remote step goes through and nothing
else (`cli/apply.py:182-207`): a mode that also skipped writing the file would be a second copy of
the walk.

Step 3 is appended, not prepended, and that is only sound because of the refusal. The command's
options are appended so that the caller's own value wins for the same option, which is what the
bound on silence requires and what `docs/operator.md:625-638` documents. So before composing
anything, the command reads the caller's `NIX_SSHOPTS` for `StrictHostKeyChecking` and
`UserKnownHostsFile`, in every spelling ssh accepts (`-o k=v`, `-ok=v`), and refuses naming the
machine and the option where the run would dial a machine that states a `hostKey`. The refusal is
made from the plan, the deployment record and the options, which is before the first dial, so it is
identical in a dry run.

Prepending was considered and rejected twice over: it would silently defeat an option the operator
wrote, which is the behaviour this change exists to remove, and it would have to prepend the whole
step-3 group, which would also take `CheckHostIP` and `GlobalKnownHostsFile` away from a caller who
legitimately set them.

Only those two options are refused, because only those two can weaken the posture.
`GlobalKnownHostsFile` cannot: a conflicting entry in a caller's global file makes ssh fail closed
under `StrictHostKeyChecking=yes`. `CheckHostIP` cannot either, the key being pinned by the name the
command dialled; it is set to `no` so that a hostname address needs no second entry per resolved
address, and a caller's own value wins, as with the bounds.

The boundary of that read is `-o`, and `-F` is deliberately outside it. Both settings can also
arrive from a configuration file a caller names with `-F <file>`, and the command neither reads
such a file nor refuses a run for naming one. Three reasons. A command-line `-o` beats a
configuration file in ssh's own precedence, so step 3 wins over whatever the file says, and the
only channel that can precede step 3 is `NIX_SSHOPTS` itself, which is what the refusal reads.
Reading the file would make the command an ssh configuration parser - `Match` blocks, `Include`
directives, first-value-wins per host pattern - and a run would then refuse or proceed on the
command's reading of that file rather than on ssh's. And `-F` is load-bearing in the safe
direction: `tests/e2e/delivery.py:334-335` states `-F /dev/null`, which disables user
configuration, and an operator's own file is where their `ProxyJump`, `User` and `IdentityFile`
legitimately live. The spec states this boundary out loud rather than leaving a reader to take the
refusal for an airtight guarantee: the honest claim is that no option of the run's own option set
can weaken the pinning, not that nothing on the host can.

`nix copy` needs the same posture and takes it from the environment, so the copy environment is
computed per machine from the same composition. That is what makes "one machine, one option set for
every step" true for the one step that is performed by another program.

### D8 - The report names a fingerprint, not the line

One line per machine the run will contact, before the first step line, in machine order:

```
alpha at 10.0.0.11 pinned to ssh-ed25519 SHA256:<base64>
beta at 10.0.0.12 states no host key, connecting with the caller's own options
```

The fingerprint is the algorithm and the `SHA256:` digest of the decoded blob, which is the identity
`ssh-keygen -l` prints and `ssh` itself prints when it asks about an unknown host, so an operator
can compare the line against the machine without a conversion. Printing the raw base64 instead is 68
noisy characters per machine, and truncating it would print an identity that is not one. The decode
cannot fail, because D3's grammar admits only a blob that decodes.

The second line is the compatible answer, said out loud. The whole point of reporting is that an
operator can tell the two postures apart from their own output, which is the thing the command
cannot do today.

### D9 - The guest image's host key becomes a known value

The end-to-end folders keep working by making the guest's identity a fact, not by declining to state
one. Taking the warning everywhere was the alternative and it fails the thing worth proving: with no
folder stating a `hostKey`, nothing in the tree ever opens a pinned connection to a real sshd, and
the accommodation this change is about stays in use.

- `tests/e2e/guest.nix` installs nixpkgs' `snakeOilEd25519PrivateKey` as the guest's only sshd host
  key: `services.openssh.hostKeys` naming `/etc/ssh/ssh_host_ed25519_key` with type `ed25519`, and
  `environment.etc` installing that path as a copy at mode `0600`, because sshd refuses a host key
  others can read and a store file is `0444`. NixOS' key generation skips a path that already holds
  bytes, so the declared key is the image's and nothing is generated at boot. The file exports
  `sshHostPublicKey = sshKeys.snakeOilEd25519PublicKey` beside the `sshPrivateKey` it already
  exports, so one file still defines both halves of both credentials, and gains an assertion saying
  so - the discipline the client key's assertion already states.
- The host key is `ssh-ed25519` and not the ECDSA `snakeOilPrivateKey`, which was the first choice
  because it made the image's host identity a different pair from the client credential it
  authorizes. `unseal-a-value-after-a-reboot` seals a value to this same line and its backend seals
  to `ssh-ed25519` and `ssh-rsa` alone, refusing anything else with a warning of its own, and
  nixpkgs' `nixos/tests/ssh-keys.nix` publishes exactly one ed25519 snakeoil pair. So the image's
  host identity and the client credential it authorizes are one published pair. That is harmless
  for an offline throwaway guest whose cluster has no uplink, and the assertion in `guest.nix` says
  why the two coincide rather than leaving a reader to wonder.
- `flake-module.nix:169-173` hands each folder's `deployment/default.nix` that line as a fourth
  argument beside `pkgs`, `planner` and `operator`. An argument and not an import, because a folder
  resolves no path outside itself; a string and not the guest attrset, so that evaluating a
  folder's deployment cannot drag the image's system closure into it.
- The folders that dial a machine - `wired-pair`, `secret-delivery`, `portable-image`,
  `shared-postgres`, `generated-secret` - state `hostKey` from that argument for every machine,
  and connect pinned. `portable-image`'s `elsewhere` is never booted and never dialled; it states
  the same line, which costs nothing either way.
- `tests/e2e/delivery.py` splits what is one function today. `command_env` - the environment the
  operator's own command is handed - carries the guest's properties minus the two options the
  command now owns: `-F /dev/null` (load-bearing, and its reason is unchanged), `-i`,
  `GlobalKnownHostsFile=/dev/null` and `BatchMode=yes`. A new `harness_env` keeps the full unpinned
  set for the harness's own `ssh` and `nix copy`, which reach a guest the harness has no deployment
  for. `guest_ssh_options` itself is unchanged and stays the harness's posture.
- `newcomer` states no `hostKey` and is the folder that proves the compatible answer on a real
  machine. Its template is byte-compared against `docs/README.md`'s smallest example and is a
  standalone flake with no access to the image's exports, so it could not state one honestly; and
  it is the deployment whose machines are addressed late, which is the case the optional field is
  for. Its workstation invocation keeps `guest_ssh_options` as its `NIX_SSHOPTS`
  (`tests/e2e/newcomer/test_newcomer.py:436-438`), which is exactly the inherited option set that
  is refused for a machine stating an identity and accepted for one that does not.
- Editing `tests/e2e/guest.nix` re-keys every snapshot cut. `rookery snapshot gc --all` before the
  next run, then one cold run of every folder. This is the same cost the `postgres` account already
  imposed once, and it is a task rather than a surprise.

`tests/e2e/test_harness.py:838-854` asserts that `command_env` carries
`UserKnownHostsFile=/dev/null`. That assertion pins the behaviour this change removes: it moves to
the harness's own helper, and the test of `command_env` asserts the two options are absent, which is
now a contract rather than an incidental - an option the command would refuse must not be in the
environment the harness hands it.

## Risks / Trade-offs

- **An operator's `~/.ssh/config` carries `StrictHostKeyChecking no`** → No effect. A command-line
  `-o` beats a configuration file, and the command's step-3 options are command-line options. The
  only channel that can precede them is `NIX_SSHOPTS`, which is exactly what the refusal reads. The
  command deliberately does not add `-F /dev/null`: an operator's `ProxyJump` and `User` are theirs.
- **A refusal blocks a run that used to work** → By design, and only where the deployment states an
  identity and the environment states the opposite. The resolution is one sentence in the refusal:
  unset the option, or remove `hostKey`. Nothing refuses a run whose machines state none, which is
  every deployment that exists before this change.
- **A machine's key rotates and the run stops** → It stops closed, which is the point, and the
  report's fingerprint line is what identifies the disagreement. The resolution is to state the new
  line; D1 says why one line suffices during the change.
- **Every machine record in the plan gains a key** → `fixtures/minimal-typed-edge/plan/backup.json`
  has to be regenerated although the fixture's own declarations do not change. Four machine records
  gain `"hostKey": null` and nothing else moves, no key included; that is the diff to check.
- **The new field costs evaluation** → One `declaredField` read and one grammar check per machine,
  plus one grouped pass over the delivery lists, against a budget measured per plan entry. A machine
  record is itself a plan entry, so the per-entry figure is diluted rather than loaded. The gate is
  two-sided with a 0.15 margin: if it moves, gate the grammar check on a stated value and keep the
  budget, never re-record it.
- **`lib/atoms.nix` gains an argument** → One line in `lib/default.nix`, and the counterexample
  probes and the perf harness instantiate the library through the same entry point, so nothing else
  constructs `atoms` by hand. Checked by evaluating `.#debug.failures`.
- **The guest's host key is a snakeoil pair published in nixpkgs, and the same pair it authorizes
  for the client** → It authorizes nothing: it is the identity of an offline throwaway guest whose
  cluster has no uplink except `newcomer`'s, and the pair is already published for exactly this
  use. The alternative - a per-run key - would have to be a snapshot key input and would re-key
  every cut on every run, which is the reason the client key is the image's and not the run's. A
  second pair of a sealable type would have to be minted and carried in this tree; D9 says why the
  published one wins, and the coincidence is asserted rather than left implicit.
- **`generated-secret`'s external generator still delivers unpinned** → Stated as a non-goal above.
  It is a second channel rendered by `secrets/backend.nix` into a build artifact, and the folder
  keeps `guest_ssh_options` for it.

## Migration Plan

Replacement, not deprecation. There is no compatibility shape to keep: `hostKey` is a new optional
key, a deployment that states none produces the plan and the table it produced before, and the
command's composed options for such a machine are byte-identical to today's.

Order, so that each phase leaves the tree green: the grammar and the atom, then the registry
reading and the projection, then the plan's machine record and the golden, then the warning row,
then the deployment record, then the command's channel and its report, then the harness and the
guest image, then the documents. The command cannot be written before the plan carries the field,
and the folders cannot pin before the image has a known key.

Rollback is per phase and needs no data migration: removing the field from a registry restores the
previous plan exactly, since no key is a function of it.
