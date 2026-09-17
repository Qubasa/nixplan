## Context

See `proposal.md` - Why. What shapes the approach is where root is currently assumed and what the
systemd 261 sources permit an account to do.

Root is assumed at four layers and stated at none. The command's connection defaults
(`cli/apply.py:216`, `cli/remote.py:299`, `cli/remote.py:316`) make every remote step a root
step; the value write chowns (`cli/remote.py:378-382`); the attach script chowns every staged
file (`image/default.nix:189-195`); and every rendered unit assumes a system manager. The fixed
roots - `util.varsRoot` at `/run/vars` (`lib/util.nix:334`) and the image staging root at
`/run/portable-planner` (`image/read.nix:296`) - are writable by root alone on an unprovisioned
machine.

The registry side has a precedent for every mechanism this change needs. A value domain with one
home is `restartPolicies` (`lib/atoms.nix:17`, the atom at `:99`, the export at `:101`). A field
that enters the machine record only when stated off its default is `microarchitecture`
(`lib/resolve.nix:587-592`). A refused declaration that makes the target incomplete and drops the
placements is the `address = 22` reading. A crossing between a placement and its machine is
`placement-platform-mismatch`, a refusal and not a filter. A realiser fact the reading asks the
realiser for is `operator/read.nix:180-190` and `:313-323`.

On the systemd side, user portabled exists since 260 and the pinned nixpkgs resolves systemd to
261.1. `portablectl --user` runs one unprivileged `systemd-portabled --user` per account on the
session bus (portablectl.c:1664, portabled.c:96-100), delegating privilege to
`systemd-mountfsd` and `systemd-nsresourced` (portabled-bus.c:314, :371; portable.c:626-644).
mountfsd applies `image_policy_untrusted` - signed dm-verity on root and usr - to any image
outside the system trusted directories (mountwork.c:59-66, :187-261), and an unsigned image
escalates to an `auth_admin` polkit action (io.systemd.mount-file-system.policy:59-66). Unit
extraction in user mode reads the user unit directories (portable.c:350-354), `PORTABLE_SCOPE=`
gates attachment (portable.c:940-963), and persistent user attach copies to
`~/.config/portables`, which the user image search path never scans (portable.c:1787-1811
against discover-image.c:790-813). flakelet's core writes `/run/systemd/system` (systemd.rs:13)
and `/var/lib/flakelet`; it has no user mode.

## Goals / Non-Goals

**Goals:**

- One model, not two code paths: root is the account that passes every check trivially, so every
  planner check, every realiser rendering and every command step is written for an account and
  root is the account for which nothing is refused.
- Every declared fact a scope cannot honor is an error row naming the declaration to edit, never a
  silent downgrade.
- Every runtime prerequisite of a user-scope run is verified by a preflight question before the
  run writes anything.
- Root work moves to provision time, once per machine, and the invariant is one sentence: root at
  provision time, never at deploy time.
- The image realiser realises both scopes; flakelet states its limit instead of half-working.

**Non-Goals:**

- An unmanaged machine nobody can dial. The exported per-machine bundle - artifacts, sealed
  values, unsealer, an installer that is the one-machine apply walk run locally - is
  `build-a-bundle-for-a-machine-a-run-cannot-dial`, a named follow-up this change must not block
  and does not design.
- A user mode for flakelet. Its core writes paths only root owns, and teaching it user scope is
  upstream work.
- Any path that moves with the scope. The roots are fixed in both scopes, so no uid enters a plan
  and nothing re-keys.
- Rootless provisioning. Making the roots writable, installing the verity public key and enabling
  lingering are root's work, done once, and this change only documents them.

## Decisions

### D1 - Scope is a machine fact entering the key only when it is `user`

The registry gains `scope`, values `system` and `user`, unstated meaning `system`, domain stated
once in `lib/atoms.nix` the way `restartPolicies` is. It enters `machineRecords` and `targetOf`
only when it is `user`, the `microarchitecture` precedent (`lib/resolve.nix:587-592`): stating
the default re-keys nothing, and flipping to `user` re-keys every entry on the machine, which is
right because rendered units, attach argv and profiles all change. Implementations read
`target.scope`, absent meaning `system`. A value outside the domain is `machine-scope-unknown`
and the target is incomplete, so the placements are dropped - completeness is read off the value,
as `address = 22` already is.

Rejected: **a global mode flag.** A deployment-wide `--user` or a top-level `mode` makes a mixed
fleet undeclarable - the operator's managed servers and a friend's laptop are one deployment -
and puts the fact where no key can read it, so flipping it would either re-key nothing or re-key
everything, both wrong. The scope is a fact about a machine, and the registry is where facts
about machines live.

### D2 - A statement the scope cannot honor is an error row

Four rows, all errors, produced in the planner walk where `placement-platform-mismatch` is:
`unit-account-in-user-scope`, `unit-groups-in-user-scope`, `port-privileged-in-user-scope`,
`value-ownership-in-user-scope`. Each is a refusal and not a filter, and `mode` stays honoured on
a delivered file because the account can chmod what it owns.

Rejected: **collapsing ownership to the account with a warning.** Rejected at checkpoint. A
declaration that says `owner = "postgres"` and a delivery that silently writes the file as the
deploying account is a plan that lies about the machine; the secrecy lattice reads ownership at
three sites, and a collapsed owner would make all three reason from a fact the machine does not
hold. Refusing names the declaration to edit; collapsing hides it until an access fails on the
machine.

Rejected: **dropping the reading of directives the scope cannot render.** Prohibited. A
`DynamicUser` denial silently skipped, or a `supplementaryGroups` silently unrendered, is the
`unit-directory-declared-twice` lesson again: a fact dropped before the check cannot fire the
check, and the unit fails on the machine naming nothing. Everything is rendered or refused, never
dropped.

### D3 - Paths do not move with scope; provision time makes them writable

`util.varsRoot`, the sealed root and the image staging root are the same paths in both scopes. No
path is a function of the account, so no uid enters a plan and nothing re-keys. Provision time -
root, once per machine - makes those roots writable by the deploying account on a user-scope
machine, through a tmpfiles.d rule or a documented one-liner in `docs/operator.md`. The invariant
sentence, stated in that document: root at provision time, never at deploy time.

Rejected: **a second varsRoot per scope.** A per-account root - `~/.local/state/vars` or an
XDG-derived path - puts the account's name into every value path, every `BindReadOnlyPaths` line
and every entry key that renders one, so renaming an account re-keys and redelivers bytes that
are still correct, and the plan stops being a function of the deployment's text. One path, made
writable once, keeps the plan account-free.

### D4 - The run verifies before it writes, and the refusal is the command's own

One preflight question per user-scope machine, before any mutation there - before the retire step
of `retire-an-entry-a-build-no-longer-names`, before any value write, copy or activation. The
facts: the three roots writable by the account, lingering active, the user manager reachable, the
user portabled reachable where an image entry is placed, `systemd-mountfsd.socket` and
`systemd-nsresourced.socket` live, unprivileged user namespaces permitted. A failed fact is the
command's own refusal - not a diagnostics row, because the plan holds no runtime fact - naming the
machine, the requirement and what the machine answered, and nothing after it is attempted on that
machine. A system-scope machine is asked nothing new. Under `--dry-run` the question goes through
the replaced channel like every remote step (`cli/apply.py:182-207`), so it is recorded rather
than asked and the walk stays comparable line by line. The question stays a list a local
installer could ask, which is what keeps the bundle follow-up unblocked.

### D5 - A realiser publishes its scopes and the reading crosses

Each realiser publishes `scopes` beside the name and unit rules it already publishes
(`operator/read.nix:180-190`, `:313-323`): image `[ "system" "user" ]`, flakelet `[ "system" ]`.
The reading crosses the stated realiser's scopes against the entry's machine scope; a mismatch is
`operator-entry-scope-unsupported`, and the realiser's own refusal carries that identifier. The
published table lands in the `realisers` table of `manifest.json` that the retire change
introduces, so that change's holdings question includes a realiser on a machine only where its
scopes admit the machine's scope, and its argv carries `--user` exactly where the scope is
`user`.

Rejected: **the reading inferring scope support from the realiser's name.** The reading
classifies nothing by name - `statesShownPaths` is recognised by the published predicates
(`operator/read.nix:187`) - and a name switch would be the first, drifting the moment a third
realiser exists.

### D6 - The user image is signed dm-verity, and the signing key is an operator argument

A user-scope image is squashfs plus dm-verity plus a signed roothash, because mountfsd's
`image_policy_untrusted` demands it for any image outside the system trusted directories and an
unsigned image dies on an interactive polkit action a non-interactive run cannot answer. The
verity public key is installed at provision time; the signing key is an argument to the build,
never a plan fact and never in the value source, so no artifact and no plan carries it and
rotating it re-keys nothing. Signing is also the supply-chain story for the third-party machine
of the bundle follow-up, a second reason it is a hard requirement rather than an accommodation.

### D7 - The attach in user scope is the account's own, into the state pool

The attach script runs `systemctl --user` and `portablectl --user`, chowns nothing, keeps the
staging discipline unchanged, and places the image into `~/.local/state/portables` before
attaching by name, because persistent user attach copies an out-of-tree image to
`~/.config/portables`, which the user image search path never scans - attaching by path would
strand an image the account can never list or detach by name. The script keeps taking no
decision from the operator: the scope comes from the artifact, which is what lets the same
script run under a local installer.

### D8 - Profiles are read per scope, one table

User-scope profiles drop `DynamicUser=yes` and `ProtectHome=yes` and keep `PrivateUsers=yes`, as
upstream's do; `trusted` is byte-identical. `imageReader.denials` follows the scope's profile, so
the `DynamicUser`-derived denials are absent in user scope and the planner's rows follow. One
table read per scope, not a second table: the denial comparison is one rule checked at three
sites, and a fourth site is a place to forget it.

### D9 - The walk order across changes is a stated seam

preflight question (this change) -> retirement (retire change, opt-in) -> unsealer install
(unseal change) -> value writes -> copy -> activation -> value-driven restarts. This change
states only its own step; `openspec/changes/INTEGRATION.md` is the one place the whole line is
written out.

## Risks / Trade-offs

- **The NixOS wiring for user portabled, mountfsd and nsresourced is young.** systemd 261.1 is in
  the pinned nixpkgs, but the module options for enabling the two sockets and the user daemon in
  a guest are fresh, and upstream gates its own test on kernel and polkit versions
  (TEST-29-PORTABLE.user.sh:12-22). → The e2e work starts with a spike task that proves the bare
  stack in the guest - sockets live, an account attaches a signed image by hand - before any
  folder depends on it.
- **Verity signing key custody.** The key is an operator argument, so the operator holds it; a
  lost key means rebuilt provisioning (a new public key installed), and a leaked key signs
  images the machines trust. → Documented beside the provisioning one-liner in
  `docs/operator.md`; the build never writes the key anywhere, and no plan, artifact or value
  source carries it.
- **Reaching a user bus over ssh needs `XDG_RUNTIME_DIR`.** A non-interactive login has no
  session, so `systemctl --user` answers nothing unless lingering keeps the manager alive and
  the run addresses the account's runtime directory. → Lingering is a provisioning fact the
  preflight verifies, and the remote steps state `XDG_RUNTIME_DIR` explicitly rather than
  hoping the login shell set it.
- **A re-keying flip.** Flipping a machine to `user` re-keys every entry on it, which redelivers
  and re-attaches everything there. → That is correct, not a cost to engineer away: every
  rendered unit, every attach argv and every profile changed. Stating the default re-keys
  nothing, which is the half operators do daily.
- **The preflight is one more question per user-scope machine per run.** → One question, folded
  the way the holdings and value questions already fold, and a system-scope fleet pays nothing.

## Migration Plan

Nothing migrates. `scope` unstated means `system`, which enters no record and no key, so every
existing registry, plan, fixture and golden is byte-identical - the perf baseline and the golden
comparison in the tasks are the evidence, not the hope. The published `scopes` table rides the
`realisers` table and record version the retire change introduces; whichever lands second amends
the same table, and `openspec/changes/INTEGRATION.md` records the seam. A user-scope machine is
new declaration surface: nothing existing can be on one until an operator states it, and stating
it requires the provisioning this change documents.
