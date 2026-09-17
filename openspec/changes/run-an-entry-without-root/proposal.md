## Why

A deployment assumes root at every layer and nothing states it. The command connects as root by
default (`cli/apply.py:216`, `cli/remote.py:299`, `cli/remote.py:316`) and every remote step is
written as if that login can do anything: a value write chowns the file it installs
(`cli/remote.py:378`), the attach script chowns every staged configuration file
(`image/default.nix:189-195`), the staging roots sit under `/run` (`lib/util.nix:334`,
`image/read.nix:296`), and every rendered unit is a system unit some manager root runs. No machine
declares which privilege it offers, no row refuses a declaration the available privilege cannot
honor, and no realiser says which privilege it emits for - so a fleet that must run without root, a
friend's laptop whose account is the only privilege there is, cannot be declared at all. That fleet
is the project's goal: user-scope deployment is the substrate for a machine nobody can dial that
receives a self-installing package and runs the operator's services as an ordinary account.

The frame is "deploy as an account, not as a mode". Root is the account that passes every check
trivially, so there is one model and no second code path: root work moves to provision time, an
apply never needs it, and every declared fact a scope cannot honor is a diagnostics row rather than
a silent downgrade.

## What Changes

- The machine registry gains one key, `scope`, values `system` and `user`, unstated meaning
  `system`. The domain is stated once in `lib/atoms.nix` the way `restartPolicies` is
  (`lib/atoms.nix:17`). A value outside it is `machine-scope-unknown` and the machine's target is
  incomplete, so its placements are dropped - the same completeness reading an `address = 22`
  already gets. `scope` enters `machineRecords` and `targetOf` only when it is `user`, the
  `microarchitecture` precedent (`lib/resolve.nix:587-592`): stating the default re-keys nothing,
  and flipping to `user` re-keys every entry on the machine, which is right because rendered
  units, attach argv and profiles all change.
- Four scope-crossing error rows, produced in the planner walk where
  `placement-platform-mismatch` is produced: `unit-account-in-user-scope`,
  `unit-groups-in-user-scope`, `port-privileged-in-user-scope` and
  `value-ownership-in-user-scope`. A user manager cannot switch accounts, cannot grant a group,
  cannot bind below 1024 and cannot chown a delivered file; each row names the declaration to
  edit, and a `mode` stays honoured.
- The run verifies before it writes. One preflight question per user-scope machine, asked before
  any mutation on that machine - before the retire step of
  `retire-an-entry-a-build-no-longer-names`, before any value write, copy or activation: the roots
  writable by the account, lingering active, the user manager reachable, the user portabled
  reachable where an image entry is placed, `systemd-mountfsd.socket` and
  `systemd-nsresourced.socket` live, unprivileged user namespaces permitted. A failed fact is the
  command's own refusal naming the machine, the requirement and what the machine answered; a
  system-scope machine is asked nothing new; under `--dry-run` the question goes through the
  replaced channel like every remote step (`cli/apply.py:182-207`).
- Each realiser publishes the `scopes` it can realise beside the name and unit rules it already
  publishes (`operator/read.nix:180-190`, `:313-323`): the image realiser publishes
  `[ "system" "user" ]`, flakelet publishes `[ "system" ]` - its core writes
  `/run/systemd/system` and `/var/lib/flakelet` (`systemd.rs:13`), and a user mode is upstream
  work. The reading crosses the stated realiser's scopes against the entry's machine scope; a
  mismatch is `operator-entry-scope-unsupported`, and the realiser's own refusal carries that
  identifier the way every realiser refusal already carries its row's.
- The portable image learns user scope. An image built for a user-scope target places its unit
  files under `/usr/lib/systemd/user` (portable.c:350-354), writes `PORTABLE_SCOPE=` into its
  os-release (portable.c:940-963), and is squashfs plus dm-verity with a signed roothash, because
  mountfsd applies `image_policy_untrusted` to any image outside the system trusted directories
  (mountwork.c:59-66) and an unsigned image escalates to an interactive polkit action
  (io.systemd.mount-file-system.policy:59-66). The verity public key is installed at provision
  time; the signing key is an operator argument to the build, never a plan fact and never in the
  value source. The attach runs `systemctl --user` and `portablectl --user`, places the image into
  `~/.local/state/portables` and attaches by name - persistent user attach copies into
  `~/.config/portables`, which the user image search path never scans (portable.c:1787-1811
  against discover-image.c:790-813) - and chowns nothing. Profiles are read per scope: the user
  profiles drop `DynamicUser=yes` and `ProtectHome=yes` and keep `PrivateUsers=yes`, `trusted` is
  byte-identical, and `imageReader.denials` follows the scope's own profile.
- flakelet is declared system-only rather than half-working: an entry whose machine's scope is
  `user` and whose stated realiser is flakelet is refused with
  `operator-entry-scope-unsupported`, and the sentence names the upstream facts.
- The provisioning invariant is stated once and documented: **root at provision time, never at
  deploy time**. Provision time makes the fixed roots writable by the deploying account on a
  user-scope machine; no path moves with scope, so no uid enters a plan and nothing re-keys.
- Out of scope, named rather than designed: an unmanaged machine nobody can dial, whose
  realisation is one exported per-machine bundle - artifacts, sealed values, unsealer and an
  installer that is the one-machine apply walk run locally - is the follow-up change
  `build-a-bundle-for-a-machine-a-run-cannot-dial`. This change must not block it: attach scripts
  keep taking no decision from the operator, and the preflight stays a list of questions a local
  installer could ask.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `planner/machine-platform`: adds the `scope` registry key, its domain and its default, the
  `machine-scope-unknown` row and the incomplete-target consequence, the key participation rule -
  `scope` enters the machine record and the target only when it is `user` - and the four
  scope-crossing rows a placement onto a user-scope machine can earn.
- `operator/apply-command`: adds the preflight question a run asks every user-scope machine before
  it writes anything there, the facts it verifies, the shape of its refusal, its place before
  every other step of the walk including the retire step, and its behaviour under the mode that
  asks rather than acts.
- `operator/deployment-build`: adds the `scopes` each realiser publishes beside its name and unit
  rules, the table the record carries, and the `operator-entry-scope-unsupported` row where the
  stated realiser excludes the machine's scope.
- `realiser/portable-service-image`: adds the image built for a user-scope target - user unit
  directory, `PORTABLE_SCOPE=`, signed dm-verity with a provision-time public key and an
  operator-argument signing key - the attach flow in user scope, and the per-scope profile and
  denial reading.
- `realiser/flakelet-artifact`: adds the statement that this realiser realises the system scope
  alone, and the refusal an entry in user scope receives.

## Impact

- `lib/atoms.nix`: the `scopes` domain and its atom, beside `restartPolicies`.
- `lib/resolve.nix`: the registry key, `machine-scope-unknown`, the conditional entry into
  `machineRecords` and `targetOf`, and the four scope-crossing rows.
- `lib/plan.nix`: the `value-ownership-in-user-scope` reading over the delivered file records.
- `cli/remote.py`: the preflight question, and `--user` argv where a machine's scope is `user`.
- `cli/apply.py`: the preflight's place in the walk, before every other step on the machine.
- `cli/report.py`: the status questions of a user-scope machine address the user manager.
- `operator/read.nix`: the published `scopes` table and `operator-entry-scope-unsupported`.
- `image/read.nix`: the per-scope profiles and denials, the user unit directory, the scope in the
  attachment description.
- `image/default.nix`: `PORTABLE_SCOPE=`, the verity signing, and the user-scope attach script.
- `flakelet/read.nix`: publishes `scopes = [ "system" ]`.
- `docs/plan.md`, `docs/diagnostics.md`, `docs/operator.md` (the provisioning invariant),
  `docs/cluster.md`, `CLAUDE.md`.
- `tests/e2e/guest.nix` and a user-scope end-to-end folder: the pinned nixpkgs already resolves
  systemd to 261.1, and user portabled exists since systemd 260, so the guest can prove the whole
  stack - `systemd-mountfsd`, `systemd-nsresourced`, lingering and the signed image.
