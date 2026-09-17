## Context

See proposal.md for why. What shapes the approach:

- A value's path has one home, `util.varsRoot = "/run/vars"` (`lib/util.nix:334`), spent once at
  `lib/resolve.nix:1591`. That root has a second consumer, `util.varsPathsIn`
  (`lib/util.nix:341-349`), which recognises a value's path inside an arbitrary string by its shape.
  `vars-path-off-delivery-set` (`lib/plan.nix:648-676`) and `vars-not-deployed-opened` are built on
  it.
- Two layers write a value and neither states a mode of its own: `cli/remote.py:326-384` and the
  `deploy.remote` step `secrets/backend.nix:69-96` renders. Both read the file record, both create
  the file `0600` before its first byte, own it, chmod it and move it, and both set ownership and
  mode again on every apply.
- The remote half of the rendered step is one `ssh` command whose `'$4'` to `'$7'` are re-parsed on
  the machine and held by `util.wordRule` (`lib/util.nix:129-167`) and nothing else. Fourteen sites
  across four positions depend on that grammar, so widening it is not available. An age native
  recipient is one word of that grammar already, which D7 leans on.
- `lib/**` and `operator/read.nix` never raise; every check there is a diagnostics row
  (`tests/unit/diagnostics.nix`). `operator/default.nix` is on the realisers' side and may raise.
- No host path is written in a deployment (`tests/unit/layers.nix`), and every path a unit needs is
  derived by the library from the identity of the thing it belongs to.
- A file record enters the value entry's key input whole, less ownership fields sitting at their
  defaults: `fileKeyInput = withoutDefaults ownershipDefaults (fileRecord file)`
  (`lib/plan.nix:114-148`). A field added to `fileRecord` re-keys every generated value in every
  deployment.
- The machine reading already has a third projection: `machineReservations`
  (`lib/resolve.nix:617-619`), outside `machineRecords` (`:576-593`) and outside `targetOf`
  (`:599-613`), because `machineKey` hashes the record every placed entry depends on. A fact read
  there enters no key. `sealRecipient` is read in the same projection, for the same reason.
- The live `planner/machine-platform` spec has the registry refuse any key it does not name, so a
  new key needs that spec's registry-keys requirement amended. `run-an-entry-without-root` amends
  the same requirement with `scope`; each change's delta states its own key only and reads the
  other as a seam, and whichever lands second restates the requirement text over the amended base.
- A machine's scope - `system` or `user`, unstated meaning `system` - is `run-an-entry-without-root`'s
  key. This change reads the recorded scope where that change records it; until it lands every
  machine reads as system scope and the user-scope half below is inert.

## Goals / Non-Goals

**Goals:**

- A machine that has rebooted holds its values again before the entries that read them start, with
  no operator and no network.
- Zero movement in any key: no entry key, no value key, no delivery set, no `varsState` answer.
- One mechanism for both writers of a value, and one behaviour whichever realiser realises the
  entries on the machine.
- A machine that cannot recover by itself is a machine an operator can see, from the report, without
  rebooting it.

**Non-Goals:**

- Sealing anything that is not a delivered generated value. Configuration files, closures and
  artifacts are store objects; the store is not cleared by a reboot.
- Protecting a value from the machine it is delivered to. The machine holds the plaintext under
  `/run` while it runs; the seal is about what survives a reboot, not about confining a compromised
  host.
- Any capability only one realiser has. The unsealer is a machine-scoped artifact of the deployment
  build, not a realiser's.
- Connection pinning. What identity a run dials is a separate, currently unowned concern; the
  recipient below authenticates nothing and is spent only by the seal.

## Decisions

### D1 The mechanism: `age`, sealed to a declared native recipient, opened with an identity file the machine minted

`age` takes a native X25519 recipient - `age1` followed by 58 characters of the bech32 alphabet
(`qpzry9x8gf2tvdw0s3jn54khce6mua7l`), one word, no spaces - and the matching identity file, which
`age-keygen -o <path>` writes while printing the public line. That line is what the registry
declares: the machine registry gains `sealRecipient`, its grammar `ageRecipientRule` stated beside
`wordRule` in `lib/util.nix`, its atom `ageRecipient` in `lib/atoms.nix` reading the grammar the way
`restartPolicy` reads `restartPolicies`, so the domain has one home. A line the grammar refuses is
`machine-seal-recipient-malformed`, an error row naming the machine and the registry file, and the
value is left out of every projection - which drops no placement, because the recipient sits in no
target.

**The identity file.** `/var/lib/planner/age.key` in both scopes, mode `0400`, its directories
`0700`, owned by root on a system-scope machine and by the deploying account on a user-scope one.
It is created at provision time by a documented one-liner - `age-keygen -o /var/lib/planner/age.key`
under an `install -d -m 0700` of its parent - whose printed public line the operator pastes into the
registry. Root at provision time, never at deploy time; and nothing in this repository ever holds,
reads or transports the private half. Because the identity file's owner is the scope's own account,
the unseal step needs no privilege beyond that account, which is what lets the unit be a user unit
in user scope (D3).

**The warning.** A machine in a value's delivery set stating no `sealRecipient` is
`machine-receives-a-value-unsealed`, a warning row with subject `machine:<name>`, naming the values
delivered there - one row per machine however many values, produced where the delivery set is built
(`lib/plan.nix`). A warning and not an error because the deployment is realisable, the delivery
works, and refusing it would break a fleet that works today for a property it never had. That
machine is delivered to exactly as it is today: plaintext only, no unsealer, no recovery.

**Why not an SSH recipient, which the first draft of this change sealed to.** `age` also accepts an
SSH public key as a recipient, and a machine already publishes one: its own sshd's. Rejected on
four counts. The public key line carries spaces, so it can never be a rendered word and the
rendered step needed a recipients file in the store to carry it; opening it requires the daemon's
`0600 root:root` private key file directly - `age` supports no agent - so the unseal had to run as
root and could never be a user unit; only two key types are usable, so a third type needed a
warning row of its own and a type table beside the atom; and `age`'s own README calls SSH support
"a convenience feature", which is a sentence about deprecation risk. A native recipient is one
word, its identity file is owned by whichever account the scope names, no unusable recipient type
exists so that row and its type table are deleted rather than carried, and the feature the design
leans on is `age`'s core. The cost is one provisioning step per machine, which the provisioning of
the roots performs anyway.

**Alternative considered and rejected: seal on the machine to its own public line.** Sealing on the
machine to the key it holds needs no recipient in flight at all. Rejected because the recipient
would then be whatever the machine happens to hold rather than what the deployment declared, which
removes the one comparison that makes a rotation visible, and because it would make the delivery
itself depend on the sealing tool being on the machine before the first value is written.

**Alternative considered and rejected: send only the seal and let the machine unseal it at delivery
time.** It halves the sends and proves openability at delivery. Rejected because the external
generator's `deploy.remote` step copies nothing to the machine and so cannot rely on an unsealer
being there, and because it would make the two writers of a value behave differently, which is the
one thing the invariant index insists they do not.

**The dependency, stated plainly.** This adds a runtime dependency on `age` in two places. On the
operator's workstation, because the seal is made where the plaintext already is: the command's own
wrapper names it (`cli/flake-module.nix`, the way it already names `PLANNER_CLI` and
`PLANNER_CLI_SRC` off the module's own attributes), so what a run seals with is the build's answer
and not the caller's `PATH`, and a run that must seal and finds no such program refuses before it
dials. On every machine that receives a sealed value, because that machine opens the seal at boot:
it arrives in the closure of that machine's unsealer artifact, which the apply copies with the same
`nix copy` it already spends per entry artifact. Nothing in a plan provisions a package and the
machine's own `PATH` is not a fact the plan records, so the artifact carrying it is the only honest
route. The pinned nixpkgs resolves `age.version` to 1.3.1; no version string is compared, because a
bump that changes nothing would fail the suite for nothing - the guard below is the constraint.

**The guard.** The behaviour this design depends on is a round trip: mint a throwaway pair with the
resolved `age-keygen`, seal a known string to the printed recipient with the resolved `age`, open it
with the identity file, compare. It fails naming this decision when the resolved tool stops
behaving that way, and it skips, stating what named nothing, where the tool cannot be resolved -
the precedent being `delivery.endpoint_refusal` and the external generator's schema digest in
`tests/e2e/generation.py`, both of which fail when the upstream contract moves and skip when it
cannot be read.

**Linkability.** A native recipient stanza names no recipient: its argument is the ephemeral share,
and the age v1 specification's licence for a recipient implementation to include an identifier is
one the native recipient does not use, so a sealed file is attributable to nobody by inspection.
That is why there is no sidecar and nothing to read back (D4): the only way to ask whether a copy
opens is to ask the tool that owns the format, which is the trial.

### D2 Where the sealed copy lives, and at what mode

`util.sealedRoot`, stated in `lib/util.nix` immediately beside `varsRoot` and `varsPathsIn`, and
`util.sealedPathOf`, which answers a file's sealed path from its runtime path by replacing the root
and appending the extension `age` publishes for its own files. A sealed path is therefore derived
from the value's identity exactly as far as the runtime path is - the instance, the generator and
the file name - and no deployment states one, which is the rule `tests/unit/layers.nix` scans for.

The root is `/var/lib/planner/sealed`, and the two properties that decide it are that a service
manager does not clear it across a reboot, which `/run` is precisely not, and that it is **outside
`varsRoot`**. The second is the trap this design most easily falls into: `varsPathsIn` matches
`varsRoot` plus three components of `[^/[:space:]"]+`, so a sealed copy under `/run/vars/...` would
be recognised as a generated value's path inside any string that named it, and
`vars-path-off-delivery-set` and `vars-not-deployed-opened` would start firing on a copy no module
declared. Stating the two roots beside each other is what lets a reader see they are disjoint, and
the delta spec makes the disjointness a scenario rather than a comment. The root is the same path
in both scopes - no path is a function of the account, so no uid enters anything - and making it
writable by the deploying account on a user-scope machine is provision-time work,
`run-an-entry-without-root`'s to state and its preflight's to verify.

**Mode.** The sealed file is `0400` and its directories are `0700`, owned by the account the scope
names - root on a system-scope machine, the deploying account on a user-scope one - whatever the
value's record says about the plaintext. The plaintext's chain is `0711` for the reason the
invariant index gives - a file the record opens to an account is unreachable behind a directory only
root may traverse - and the sealed copy is the inverse case: it is ciphertext, its only reader is
the unseal step, and that step runs as the identity file's owner and needs nothing else to
traverse. `0711` here would publish the value file names of every entry on the machine to any
account for no gain. The record's `owner`, `group` and `mode` still decide the plaintext, on
delivery and on restore.

### D3 What the unseal unit is

**One artifact per machine, produced by the deployment build, installed by the command, realised by
no realiser.** `operator/read.nix` gains a per-machine reading beside its per-entry one: for every
machine a delivered value reaches whose record states a recipient, it records the value file records
delivered there, the machine's scope, and the units the boot-time unit must precede.
`operator/default.nix` builds one artifact from that record and puts it in the same link farm as the
entries, at `machines/<name>`; the machine name needs no projection, since a name carrying a key
separator is refused before any key exists (`lib/util.nix:111-127`) and machine names are unique by
construction, so no `operator-entry-name-collision` analogue is possible. The artifact is a function
of the value file records and the scope and of nothing else - not of the recipient - so a rotation
leaves it unchanged.

**Why not a plan entry.** A plan entry belongs to an instance and a member; this belongs to neither,
and the invariant that a realiser realises exactly a plan entry is what keeps `image/` and
`flakelet/` readable. Making it an entry would require a synthetic instance nobody declared, a
member name nobody can address, a realiser statement about it, and a place in `keyInput` - and it
would make one of the two realisers responsible for a fact about the machine rather than about the
entry. Making it a realiser's would make it flakelet-only or image-only, and a value is delivered to
a machine whichever realiser its entries use. The layer that already builds things a realiser does
not - `plan.json`, `manifest.json`, both halves of the diagnostics - is the layer that builds this.

**Why the command installs it rather than an endpoint activating it.** `flakelet activate` is a
flakelet-only route and `portablectl` an image-only one, and the machine's own service manager is
what both have in common: the registry already requires every placed machine to declare one
(`lib/resolve.nix`, `machine-target-incomplete`). So the apply symlinks the artifact's unit into the
service manager's own unit directory, reloads it if the link changed, enables it, and prints whether
it changed anything - the same shape as the value write and the activation. The step is taken before
the first value is written to that machine, so an interrupted run leaves a machine that can open
whatever it already holds.

**Scope.** On a system-scope machine the unit is a system oneshot, `WantedBy=multi-user.target`, run
by the system manager as root, which owns the identity file there. On a user-scope machine it is a
**user unit**, `WantedBy=default.target`, run by the account's own manager as the account, which
owns the identity file there; the install goes through that manager, and the step chowns nothing,
because the account owns its own tree. Lingering is what makes a user manager a boot-time one, and
lingering is a fact of `run-an-entry-without-root`'s preflight - cited here as the seam, not
restated: this change asks no runtime question of its own.

**The unit's name.** One hyphen wide: `planner-unseal.service`. Every unit file a realiser derives is
`<instance>-<service>-<unit>.service` or `.timer` (`image/read.nix:208`, `:244-253`), which carries at
least two hyphens outside its components, so no entry can spell this name however its instance,
member and unit are called. That is a property of the derivations rather than a row: the machine's
reservation joined the host-resource claim index because a collision there is reachable, and this one
is not, and a row nobody can earn is a row nobody can test. The delta spec makes the disjointness a
scenario instead.

**Ordering.** `Before=` every unit file of every entry on that machine whose plan record names a
value's path, read off `util.varsPathsDeep` of that entry's own record - the library's own
recogniser, asked of `units` and `configData` the way `imageReader.hostPaths` already asks of them.
That relation is the same one the command's restart step uses (`cli/apply.py:125-178` maps a resolved
read to the value entry whose declared file path it names), expressed where the build can see it: a
declared read lands the provider's path in the consumer's own record, and an owner's unit names its
own generator's file, so one rule covers both and an entry that opens no value is not ordered behind
the oneshot. The unit is wanted by its manager's default target as well, because `Before=` alone
orders and does not pull in: a unit nothing wants is never in the transaction it would have ordered.

**What it does.** For each value file of that machine, in plan key order: if the plaintext is already
there, leave it - a restore must never replace a fresher delivery with an older seal. Otherwise open
the sealed copy with `/var/lib/planner/age.key`, into a temporary created `0600` in the plaintext's
own `0711` parent chain, own it, chmod it to the record and move it into place, which is the write
step's discipline and for the same reason; in user scope the ownership step is a no-op, the account
owning everything it writes. It prints one line per value it restored and `nothing to unseal` when
it restores none. A seal it cannot open is reported and skipped, every other value is still
restored, and the unit exits non-zero so that the failure is visible in the machine's own service
manager. Because `Before=` orders and does not require, the readers still start and still fail on
the file that is not there, which is exactly where this change leaves a machine it cannot help:
today's behaviour, with the report naming it and a second apply as the recovery.

### D4 Rotation

A rotated or lost identity makes every sealed copy on that machine unopenable, and the design
detects it in one way at two sites: **the trial**. The machine's unsealer carries a check that asks,
per sealed copy, whether it opens, and prints nothing about the bytes; the boot-time unit runs the
open for real, and `planner status` runs the check. So an operator learns that a machine will not
recover before the reboot that would have proved it, and learns it from the machine rather than from
a record of what a past run did. A pasted-wrong public line is the same case caught the same way:
every seal written to it fails the trial on the next `status`, with no reboot spent.

**The cost is a re-apply of the values, and that is the honest answer.** It is also cheap: the sealed
copy is rewritten on every apply regardless, because two sealings of one file differ - `age` draws a
fresh ephemeral key per file - so there is nothing to compare and nothing to skip. A rotation
therefore costs one `age-keygen` on the machine, one registry edit, and one `planner apply` with the
value source, and no regeneration of anything: the bytes are unchanged, no key moves (D5), and the
restart step still fires only for a plaintext that moved.

**The sealed copy records no recipient, and there is no sidecar.** A recipient recorded beside the
file would be a second copy of a line the plan's machine record already carries, which a stale build
can disagree with - and the file itself offers nothing to read instead: a native recipient stanza's
argument is the ephemeral share, not an identifier of the recipient, so a sealed file is
attributable to no key by inspection (D1, linkability). The trial answers the only answerable
question with the tool that owns the format.

**What the report cannot tell apart.** A copy sealed to a rotated identity and a copy whose bytes
were damaged are both copies that do not open, and the line says that rather than claiming to know
which. It is the same rule the write step follows when it says `changed` rather than what it changed
to.

### D5 What must not move

Nothing about the seal enters any key. Not a field on the file record, not a field on the value
entry, not a marker anywhere: the sealed path is a pure function of the runtime path, computed by
whoever needs it. The layers that need it are the build reading (`operator/read.nix`, which renders
the unsealer and publishes the machines table) and the two writers, and the command learns it from
the deployment record rather than deriving it, because `cli/` imports nothing under `lib/`.

The recipient is recorded once, on the plan's `machine:<name>` record, the way the address is - and
as an explicit absence where none is declared, kept the way a placed entry's `closure` and `units`
are kept, because an absent field means the plan does not know and a reader must be able to tell a
machine that seals nothing from a record written before the field existed. It is read in the third
projection of the machine reading, beside `reserves`, and therefore enters `machineKey` no more than
the reservation does: `machineKey` hashes `machineRecords`, and the recipient is not in it.

The reason the sealed path is not a plan field is mechanical as well as principled. `fileKeyInput`
is `withoutDefaults ownershipDefaults (fileRecord file)` (`lib/plan.nix:148`), so the whole file
record less defaulted ownership is in the value entry's key input; a `sealed` field on `fileRecord`
would re-key every generated value in every deployment, for a path that is a function of the path
already there. Under "Keys and identity" the rule is that a field enters a key only where its value
differs from the default it would resolve to unstated, and the deeper rule is that the delivery set
is deliberately not in a value's key because a machine joining changes no byte - a recipient is the
same kind of fact. A value sealed to a new recipient is the same value.

So: `keyInput` of a value entry stays `{ instance, generator, per, deploy, files, dependsOn, machine
}` plus `program` where one was declared (`lib/plan.nix:1275-1283`); `keyInput` of a placed entry is
untouched; `varsState` stays keyed by the value's entry rather than by machine, so one value has one
answer about whether it exists however many machines hold a copy; and the delivery set stays what
the owner's placements and the declared reads make it.

### D6 What this does not do

It does not make this project a secret manager. The bytes still originate outside: from the operator's
`--values` source, which nothing in this repository fills, or from the external generator, which this
project configures and does not implement. The seal is a copy of bytes that were delivered, made to a
recipient the operator declared, and it can produce no value that was never delivered.

What an operator still owns: minting and rotating the bytes; the value source and its custody; the
provision-time `age-keygen` and the registry line naming each machine's recipient; the decision to
re-apply after a rotation; and every machine that states no recipient, which recovers the way it
does today - by an apply.

### D7 The two writers, and the words the rendered step can carry

`cli/remote.py` seals in the process that read the value source and sends the ciphertext on a step of
its own, before the plaintext step, on the step's input stream. Two steps rather than one framed
payload, because a step is a script plus one stream and the plaintext step is unchanged - the line it
prints, the record it reads and the `changed`/`unchanged` answer all stay where the existing
requirements put them. The sealed step's line is new and prefixed differently, so a caller filtering
the log for `value ` or `restart ` reads what it read before.

`secrets/backend.nix` seals in the same place - locally, after the store backend's `get` has written
the plaintext into the step's one temporary - and sends the ciphertext with a second `ssh`, sealed
copy first, so an interrupted run never leaves a sealed copy older than the plaintext beside it. The
recipient is an ordinary rendered word: `ageRecipientRule` is a subset of `util.wordRule`'s class -
`age1` plus bech32 is alphanumeric throughout - so the recipient read off the plan's machine record
joins `renderedWords` (`secrets/read.nix:280-324`) and is checked by `secrets-rendered-word-refused`
by construction like every other word of the table. The first draft's workaround - a recipients
file in the store, handed per machine, because an SSH public key line carries spaces and could not
be a word - is deleted with the mechanism that needed it, not kept. What the step still takes from
its caller is the sealing program, beside `get`, because the plan does not hold a store path to a
tool; and what `secrets/read.nix` gains beside the recipient is two file-scope entries in
`renderedWords` - the sealed path and its parent - both derived from `path`, so the rows about them
exist by construction: `secrets-rendered-word-refused` for a word outside the grammar, and the
`id = null` account `pathNamesNoDirectory` for a path that names no directory. A machine whose
record states no recipient gets today's single `deliver`.

### D8 The deployment record

`manifest.json` gains `machines`, one record per machine a delivered value reaches, stating whether
its values are sealed and, where they are, the artifact that opens them. It does not restate the
recipient: the command reads that from the plan's `machine:<name>` record, with a reader of this
change's own beside the one that already reads a value's machine address there
(`cli/manifest.py:241-258`), because a third copy of one line is a third thing that can disagree.

The table is required, not optional, for the reason a record carrying no `entries` table is refused
rather than read as a deployment that places nothing: a reader of the old shape would read a missing
table as a fleet whose machines seal nothing, which is the silent failure the table exists to
prevent. So the record's `version` becomes 2 and the command implements 2 only. No dual reading and
no compatibility path, per "Replace, do not deprecate": a deployment record is a build artifact, and
rebuilding is what a consumer of a new command does anyway.

### D9 Where the evidence goes

The recovery claim is only provable on a machine that reboots, and `tests/e2e/secret-delivery/`
already reboots one as its last phase. Its phases are order-dependent, the file order is the order,
and nothing is restored between them. Two constraints frame the identity: a deployment is evaluated
when the artifact set is built, before any phase runs, so a recipient minted by a phase cannot be
declared; and a snapshot preparation body runs no program, so nothing may be minted there either.
The design that satisfies both:

- A throwaway identity pair is generated once at authoring time and committed, clearly named as a
  throwaway: the public line is the `sealRecipient` literal in `deployment/machines.nix` - one
  alphanumeric word, so the no-host-path scan of `tests/unit/layers.nix` has nothing to see - and
  the private half sits beside the test as `throwaway-age-identity.txt`. The precedent is the guest
  image's own login: `tests/e2e/guest.nix:67-70` authorizes nixpkgs' published snakeoil key, on the
  record as "NOT a security issue", because a committed credential that authorizes nothing but an
  offline throwaway guest is not a secret. This identity opens nothing but test tokens on that same
  guest.
- The folder's **first phase** provisions each machine the way an operator would: `install -d -m
  0700` and the identity file at `/var/lib/planner/age.key`, mode `0400` - a phase and never a
  preparation, so the evidence is a run and not a replay, and no snapshot cut moves. No guest image
  edit and no `rookery snapshot gc` is needed.
- All three machines declare the recipient; `gamma` declares one too and receives no value, which is
  what proves the unsealer follows the delivery set rather than the placement.
- Two new tests join the `applied` phase, after the existing removal test and before the `rotated`
  fixture: one replaces `beta`'s sealed copy of the session token with bytes it cannot open and reads
  the report; the other clears both copies of it and is the rewritten home of the
  `A machine that lost its values` scenario. Both leave the machine repaired by the apply each makes,
  and the seal is rewritten by every later apply anyway, so the phases below them are unaffected.
- The `rebooted` phase stays last and its test is rewritten: the machine holds its values again with
  no command run against it, and its reader starts and reads the bytes the last delivery wrote. It
  leaves the machine holding every value and a started reader, which is what the old phase left
  behind after its own apply.
- One test runs the unsealer's own program by hand on the machine, with the plaintext cleared, to
  observe what a seal it cannot open does - the precedent being `tests/e2e/portable-image/`, which
  runs an artifact's attach script on the machine rather than inventing an answer on the host.

## Risks / Trade-offs

- [A machine's `/var/lib` is not persistent - an impermanence setup, a read-only root] → the sealed
  copy vanishes with the plaintext and the machine is exactly where it is today: the report names the
  missing value and an apply restores it. The design states the persistence requirement in the
  library rather than assuming it, and the report's "no sealed copy" line is what an operator sees.
- [The seal is only as strong as the identity file] → an account that can read
  `/var/lib/planner/age.key` can open every sealed value on the machine. On a system-scope machine
  that account is root; on a user-scope machine it is the deploying account, which is the same
  boundary the plaintext under `/run` already has there. The exposure is the scope's own, not a new
  one.
- [An operator pastes a wrong or stale public line] → every seal written to it fails the trial, so
  the next `status` names the machine with no reboot spent, and the fix is a registry edit and an
  apply. The registry line and the machine's identity file can only be compared by the trial,
  because a native seal names no recipient.
- [Two more steps per value per machine, one `nix copy` per sealing machine] → an apply's login count
  per machine rises. The guest's sshd is socket activated and a burst of short logins can be refused
  by its own trigger limit, which is why the report's question stays one per machine and the unsealer
  install is one step per machine rather than per value.
- [`age` becomes load-bearing on every machine that holds a value] → the closure grows per machine by
  the tool and its runtime. It arrives with the artifact the apply copies, so it is visible in the
  step log and in the record rather than assumed on the machine, and D1's guard is what fails when
  the tool's own contract moves.
- [A rotation leaves seals nobody can open until the next apply] → detected by the trial, reported by
  `status`, repaired by the apply that would happen anyway.
- [The unsealer is ordered before readers but does not require them] → a machine whose seals do not
  open starts its readers and they fail. Requiring them would leave an operator with a unit that was
  never attempted and no clue which file was missing, which is worse, and it would let one damaged
  copy hold back every entry on the machine.

## Migration Plan

This change depends on no other open change and lands in one piece. The seams it reads - the
machine's scope, the lingering fact of the preflight - degrade to today's behaviour where
`run-an-entry-without-root` has not landed: every machine reads as system scope and the unit is a
system oneshot.

An existing fleet needs one provisioning step per machine - the `age-keygen` one-liner and the
registry paste - and one `planner apply` per deployment. Before it, machines hold plaintext and no
sealed copy, and `status` says so per value; after it, every machine whose record states a recipient
holds both and recovers by itself. A machine provisioned later joins at its next apply. Nothing on a
machine has to be removed, and no value is regenerated: no key moves, so every artifact and every
value entry is the one already there.

Rollback is the previous build: the sealed copies and the unsealer unit are inert to a command that
does not know about them, and the plaintext path, its ownership and its mode are unchanged
throughout. A deliberate removal is disabling `planner-unseal.service` in the machine's own manager
and deleting `/var/lib/planner/sealed` and `/var/lib/planner/age.key` on each machine; the command
of the previous shape refuses the new deployment record by its version, which is the intended way
round.
