<!--
A delta against `realiser/portable-service-image`, whose current text is
`openspec/specs/realiser/portable-service-image/spec.md`. Three requirements are added; nothing is
modified.

The evidence is the systemd 261 sources, named without a repository-rooted prefix as this
repository names foreign files. `portablectl --user` flips daemon and bus: one unprivileged
`systemd-portabled --user` per account on the session bus (portablectl.c:1664,
portabled.c:96-100), units landing in `$XDG_CONFIG_HOME/systemd/user.attached`
(path-lookup.c:308-309), privilege delegated to mountfsd and nsresourced rather than polkit in the
daemon (portabled-bus.c:314, :371), the whole stack mandatory (portable.c:626-644) and gated in
upstream's own test on kernel >= 6.5 with BPF LSM and polkit >= 124
(TEST-29-PORTABLE.user.sh:12-22). User portabled exists since systemd 260; the pinned nixpkgs
resolves systemd to 261.1, so the e2e guest can prove it.

Unit extraction in user mode reads the user unit directories - the `RUNTIME_SCOPE_GLOBAL` lookup,
portable.c:350-354 - and a system image silently yields no matching units, so the unit file
placement is per target scope, not a second copy. `PORTABLE_SCOPE=` in the image's os-release
gates attachment (portable.c:940-963; unset means `system`).

Signing is a hard requirement, not an accommodation: mountfsd applies `image_policy_untrusted` -
root and usr must carry signed dm-verity (mountwork.c:59-66) - to any image outside the system
trusted directories, and `~/.local/state/portables` is not one of them (mountwork.c:187-261); an
unsigned image escalates to an `auth_admin` polkit action, a hard failure for a non-interactive
run (io.systemd.mount-file-system.policy:59-66). Signed verity is also the supply-chain story for
a third-party machine the follow-up bundle change serves.

Persistent user attach copies an out-of-tree image to `~/.config/portables`, which the user image
search path never scans (portable.c:1787-1811 against discover-image.c:790-813, an upstream rough
edge), so the attach flow places the image into the account's state pool and attaches by name.

Profiles: upstream's user profiles drop `DynamicUser=yes` and `ProtectHome=yes` and keep
`PrivateUsers=yes`, and `trusted` is byte-identical (src/portable/profile diff). The reading's
denial table is `imageReader.denials` (`image/read.nix:49`), one of the three sites of the
two-point secrecy lattice, so it moves with the profile the scope selects rather than growing a
fourth site.
-->

## ADDED Requirements

### Requirement: An image built for a user-scope target is signed and states its scope

An image built for an entry whose target records `scope = "user"` SHALL place its unit files under
the user unit directory, `/usr/lib/systemd/user`, because unit extraction in user mode reads the
user unit directories (portable.c:350-354) and a system image silently yields no matching units.
It SHALL write `PORTABLE_SCOPE=` into its operating-system identity file with the scope the
entry's target records, because that field gates attachment and unset means `system`
(portable.c:940-963).

The image SHALL be squashfs carrying dm-verity with a signed roothash: mountfsd applies
`image_policy_untrusted` to any image outside the system trusted directories (mountwork.c:59-66,
:187-261), and an unsigned image escalates to an interactive polkit action, which is a hard
failure for a non-interactive run (io.systemd.mount-file-system.policy:59-66). The verity public
key SHALL be installed at provision time; the signing key SHALL be an operator argument to the
build, never a plan fact and never a file of the value source, so no plan and no artifact carries
it and rotating it re-keys nothing.

An image built for a system-scope target SHALL be the image this capability already describes,
unchanged.

#### Scenario: A user-scope image places its units where a user manager reads

- **WHEN** an image is built for an entry whose target records `scope = "user"`
- **THEN** its unit files SHALL sit under `/usr/lib/systemd/user`, each carrying the image's
  prefix
- **AND** its identity file SHALL carry `PORTABLE_SCOPE=` naming the user scope

#### Scenario: A user-scope image carries a signed verity roothash

- **WHEN** an image is built for a user-scope target with the operator's signing key
- **THEN** the image SHALL carry dm-verity with a roothash signed by that key
- **AND** an attachment on a machine provisioned with the matching public key SHALL succeed
  without an interactive grant

#### Scenario: The signing key is an operator argument and never a plan fact

- **WHEN** a deployment with a user-scope image entry is planned and built
- **THEN** the plan SHALL record no signing key and the value source SHALL hold none
- **AND** the key SHALL reach the build as an argument of the build alone

### Requirement: The attachment in user scope is the account's own

The attach script of a user-scope image SHALL address the account's own manager: every
`systemctl` it runs SHALL run `systemctl --user` and every `portablectl` SHALL run `portablectl
--user`, which is one unprivileged `systemd-portabled --user` per account on the session bus
(portablectl.c:1664, portabled.c:96-100). It SHALL chown nothing, because the account owns its
staging, and the staging discipline - created `0600`, set to the record's mode, moved onto its
destination - SHALL be unchanged.

The attach flow SHALL place the image into the account's state pool, `~/.local/state/portables`,
and attach it by name: persistent user attach copies an out-of-tree image to
`~/.config/portables`, which the user image search path never scans (portable.c:1787-1811 against
discover-image.c:790-813), so attaching by path would attach an image the account can never list
or detach by name again.

The script SHALL keep taking no decision from the operator: the scope it attaches under is the
entry's target's, read from the artifact, so the same script is what a local installer runs on a
machine no run can dial.

#### Scenario: The attach in user scope addresses the user manager

- **WHEN** the attach script of a user-scope image runs
- **THEN** every step it takes SHALL address the account's own manager and portabled, with
  `--user`
- **AND** no step SHALL chown a file

#### Scenario: The image is placed where the user search path scans

- **WHEN** the attach script of a user-scope image attaches
- **THEN** the image SHALL sit in the account's state pool, `~/.local/state/portables`
- **AND** the attachment SHALL name the image by name rather than by an out-of-tree path

### Requirement: A profile's denials are read per scope

A confinement profile SHALL be read per scope, and the reading's denial table SHALL follow the
scope's own profile. In user scope a profile SHALL drop `DynamicUser=yes` and `ProtectHome=yes`
and keep `PrivateUsers=yes`, as upstream's user profiles do, so the denials a profile derives from
`DynamicUser` SHALL be absent in user scope and the rows the planner produces from the table SHALL
follow. The `trusted` profile SHALL be one profile in both scopes, byte-identical, as upstream's
is.

The table SHALL stay one table read per scope rather than a second table beside the first, so the
capability-denial site count does not grow: a rule checked at three sites gains no fourth.

#### Scenario: A user profile drops what a user manager cannot grant

- **WHEN** an entry is attached in user scope under a profile that carries `DynamicUser=yes` in
  system scope
- **THEN** the rendered attachment SHALL carry no `DynamicUser=yes` and no `ProtectHome=yes`
- **AND** it SHALL keep `PrivateUsers=yes`

#### Scenario: The trusted profile is one profile in both scopes

- **WHEN** an entry stated `trusted` is read for a user-scope target and for a system-scope one
- **THEN** the profile applied SHALL be byte-identical in both readings
- **AND** the denial table SHALL answer the same denials for both

#### Scenario: A denial absent in user scope earns no row

- **WHEN** an entry whose unit needs an access only the `DynamicUser`-derived denials refuse is
  read for a user-scope target
- **THEN** the reading SHALL emit no denial row for it
- **AND** the same entry read for a system-scope target SHALL earn the row that table states
