## Context

See `proposal.md` - Why. The shapes that decide the approach are already in the tree:

- **The registry is a fixed key list read field by field.** `machineRegistryKeys`
  (`lib/resolve.nix:42-48`) is what `util.extraKeys` refuses against, and `machineFields`
  (`lib/resolve.nix:268-274`) reads each key with a shape through `declaredField`
  (`lib/resolve.nix:90-130`), so a value of the wrong kind is a row and a fallback rather than a type
  error inside an elaboration. `shapes` (`lib/resolve.nix:64-85`) carries `root`, `record`, `names`,
  `name` and `flag`, and no shape for a number.
- **A machine record is hashed, and the hash is depended on.** `machineKey` is
  `util.shortHash (builtins.toJSON record)` over the whole record (`lib/plan.nix:28`) built from
  `machineRecords` (`lib/resolve.nix:402-419`). Every placed entry carries
  `dependsOn = [ "machine:<name>@<key>" ]` inside its `keyInput` (`lib/plan.nix:778`, `:786-803`),
  and a per-placement generated value carries the same (`lib/plan.nix:955`). A field added to the
  record therefore re-keys every entry on the machine and every value delivered to it.
- **`machineRecords` and `targetOf` are already two projections of one reading.**
  `lib/resolve.nix:402-419` builds what the plan records about the machine; `lib/resolve.nix:425-438`
  builds what an entry was planned for, with the comment stating why the address is inside it - "an
  entry's key hashes the target: a field a module can render from and the key does not cover would be
  a key that does not describe the entry". A third projection is the natural place for a fact neither
  of them may carry.
- **The collision check is already generic over claimants.** `claimsOf` (`lib/plan.nix:714-726`)
  flattens one claimant's claims into `{ key, machine, kind, name }` records and `collisionRows`
  (`lib/plan.nix:733-757`) groups the flat list by machine and then by resource, emitting one row per
  resource with more than one distinct key. Nothing in it says a claimant is an entry; only its call
  site does (`lib/plan.nix:1098`) and only its message text does (`lib/plan.nix:638-666`).
- **A row's subject must be a plan key.** `isPlanKey` (`lib/diagnostics.nix:25-33`) admits
  `machine:alpha`, and the plan carries exactly that string as a machine record's key
  (`lib/plan.nix:1080`), but only for `usedMachines` (`lib/plan.nix:1078-1093`).

## Goals / Non-Goals

**Goals:**

- A deployment claiming a port or a path the machine's host image already holds is a row, from the
  plan alone, before anything is dialled, naming the machine and the entry.
- No existing deployment moves: no golden plan, no golden table, no entry key, no value key.
- One vocabulary for a port on a machine: the reservation states a protocol and a number, and the
  comparison is the one the entry-to-entry check already makes.

**Non-Goals:**

- **No probe.** The planner does not open a connection, does not read a filesystem and does not infer
  a reservation from a machine's `system` or `serviceManager`. `mkPlan` realises nothing and reads
  nothing, and a discovered reservation is a value that is not knowable at evaluation, which is
  `lib/excluded.nix`'s `lifecycle` construct: "the first value that is not knowable at evaluation".
- **No realiser behaviour.** A reservation opens no firewall, renders no socket unit and reaches no
  artifact. It is a declaration-versus-declaration consistency check, which is what a claim in this
  library already is.
- **No allocation.** The planner still picks no port and no path. A reservation narrows what a
  deployment may state; it does not make the planner state anything.
- **No new row identifier.** The reservation is a claimant, so it earns the rows a claimant earns.

## Decisions

### The reservation is a sixth registry key, not a top-level deployment record

The fact is about the machine: it is true of `alpha` whatever any instance declares, it is edited
when the host image changes, and it belongs beside the address a consumer dials and the tags a
placement selects on. Putting it in the registry also puts it in the one reading that already refuses
an unknown key and already rows a value of the wrong kind (`lib/resolve.nix:365-377`,
`lib/resolve.nix:90-130`), so the field costs a key name, a shape and a projection.

Alternative rejected: a top-level `reservations.<machine>` record beside `machines`. It is a second
place a machine is named, so a machine renamed in one and not the other is a silent no-op, and the
reading would have to invent its own unknown-machine row for a name the registry does not hold. The
registry already answers "which machines exist" once.

### The shape is `reserves.ports.<name> = { proto, number }` and `reserves.paths = [ … ]`

A port claim in a module is `claims.ports.<name> = { proto, count, fixed }` (`lib/module.nix:115-119`,
read into `alloc.ports` and compared as `"<proto>/<fixed>"` at `lib/plan.nix:701-709`). The
reservation mirrors the attribute-keyed shape, because a bare list of numbers in a registry is
unreadable six months later and the name is what an operator writes `sshd` or `resolved` into. It
does not mirror `fixed`: `fixed` in a claim distinguishes a stated number from the dynamic allocation
`lib/excluded.nix`'s `dynamicPort` records, and a reservation has no allocation to be distinguished
from, so the key is `number`. It carries no `count`, because the entry half compares one number
today; when the allocation table lands, a range is what both halves compare.

`paths` is a plain list of host paths, because a path is its own name and a second name for it would
be noise. The comparison is against the keys of an entry's `configData` record
(`lib/plan.nix:811`), which are host paths as written.

`shapes` gains `number = { what = "a number"; is = builtins.isInt; }`. The registry reading has never
had to read one; a port stated as `"22"` is then a row naming both kinds rather than a reservation
that silently matches nothing.

Alternative rejected: a single flat list of strings, `reserves = [ "tcp/22" "/etc/ssh/sshd_config" ]`,
matching the internal claim spelling exactly. It makes the reading one line and the declaration a
puzzle, and it puts the planner's internal comparison key into a deployment's own text, where a
change to that key becomes a breaking change to every registry.

### The reservation is kept out of every key by living in a third projection

`machineFields` reads it; a new `machineReservations` table beside `targets`
(`lib/resolve.nix:440`) projects it; `resolved` publishes it beside `machines` and `usedMachines`
(`lib/resolve.nix:1984-2004`). `machineRecords` (`lib/resolve.nix:402-419`) and `targetOf`
(`lib/resolve.nix:425-438`) are untouched, which is the whole mechanism: `machineKey` hashes the
record it is handed, so a fact that is not in the record is not in the key, and there is no exclusion
list to keep in step with a field list.

The consequence is deliberate and stated in the spec: the plan records the reservation nowhere. That
is the opposite of the `closure`/`units` rule (`lib/plan.nix:865-870`), where an empty value is
recorded because a realisation reads the field and cannot tell an empty answer from a missing one.
Nothing reads a reservation - no realiser, no subcommand - so recording it would be a fact carried
for no reader, at the price of re-keying every entry on the machine each time an operator corrects
it.

Alternative rejected: record it on the machine entry and exclude it from `machineKey`. That needs a
second projection anyway, and it leaves `machineKey` a hash of some of the record it labels, which is
exactly the property `targetOf`'s comment defends against. Alternative also rejected: record it and
accept the re-key. It re-keys generated values through `lib/plan.nix:955`, and a re-keyed value is a
regeneration request to an external tool for bytes that are still correct, which "Keys and identity"
already refuses for the delivery set.

### The machine claimant is `machine:<name>`, sorted with the entry keys

`claimsOf` returns claims tagged with the claimant's key; the reservations of the machines the plan
carries a record for are turned into claims of the same shape with `key = "machine:${machine}"`, and
appended to the same flat list at `lib/plan.nix:1098`. `collisionRows` needs no change: it groups by
machine and resource and sorts the distinct keys, so the machine takes part in the same ordering and
becomes the subject exactly when it sorts first. The two keys cannot be confused inside that list:
`machine` is a legal instance name (`CLAUDE.md`, Realisers), but only a placed entry claims anything
and a placed entry's key always carries the `@<machine>` an unplaced one does not
(`lib/plan.nix:774` against `lib/plan.nix:883`), so a claimant spelled `machine:alpha` is the
registry's and nothing else's. Both spellings are legal plan keys, which is all the subject rule
requires (`lib/diagnostics.nix:25-33`).

Only machines in `usedMachines` contribute claims. A machine nothing is placed on has no entry to
collide with, so the claim would be a group of one and no row; restricting it also guarantees the row
subject names a record the plan actually carries (`lib/plan.nix:1078-1093`), rather than a key a
reader cannot look up.

Alternative rejected: always subject the row to the machine when a reservation is one of the
claimants. It is a second ordering rule for the same row family, and the reader gains nothing: the
row names every claimant either way, and both the registry and the module are editable declarations.

### The rows are the existing two, and their text stops saying "entries"

`entry-port-claimed-twice` and `entry-host-path-claimed-twice` are what the collision is; a
`machine-reserves-a-claimed-port` twin would double the identifier table, double the row in
`docs/diagnostics.md` and make a reader ask which of the two a three-way collision earns. What
changes is text: the message template at `lib/plan.nix:750` reads "entries <keys> placed on <machine>
all …", and a machine record is not an entry placed on itself, so the template names the machine
once and lists its claimants without calling them entries. The resolution of `hostResources`
(`lib/plan.nix:644-665`) gains the reservation half where a reservation is among the claimants: an
author reading it is told the two declarations that disagree, the module's claim and the registry's
line.

No golden moves on account of the rewording, because `fixtures/minimal-typed-edge` produces none of
these rows today (`fixtures/minimal-typed-edge/plan/diagnostics.txt`).

The third claim kind, `entry-unit-directory-shared`, has no reservation half. A unit directory claim
is `<field>/<name>` in the service manager's namespace (`lib/plan.nix:672-696`) and the host path it
becomes is the realiser's to choose, so a machine cannot state one without the planner naming a
realiser. A machine that holds `/var/lib/postgresql` reserves it as a path, and it collides with a
`configData` path; it does not collide with a `stateDirectory` name, and the spec says so rather than
comparing two things that are not the same thing.

### This is not a bind-address comparison

`openspec/changes/type-a-port-claim-and-its-collision` owns the address on a claim: whether two
listeners on one machine are one collision depends on what each binds, and that change types the
claim and decides it. It answers a question about two declarations inside the deployment. A
reservation answers a different question - what the machine holds outside the deployment entirely -
and no amount of address typing produces the sshd nobody declared.

The two compose along one seam: the resource key a claim compares by. Today it is `"<proto>/<fixed>"`
(`lib/plan.nix:701-709`); when the address lands it gains an address component, and the reservation
states the same components because it is read into the same key. That is also why the reservation's
protocol is read the way a claim's protocol is read, rather than being given a domain of its own:
one change types both halves, or neither.

## Risks / Trade-offs

- **A deployment that works today starts failing.** → Only where the operator wrote a reservation the
  deployment contradicts, which is a deployment whose unit could not bind or whose file overwrote the
  host's. The field is opt-in and absent everywhere in this repository, so nothing that exists today
  moves; the failure arrives with the line that describes it.
- **A reservation is hand-maintained and can be wrong.** → Both directions fail open. A stale
  reservation produces a row for a resource the machine has since released, and the resolution names
  the registry line to delete; a missing one restores exactly today's silence. The planner cannot
  check it without becoming a probe, and a probe is the `lifecycle` exclusion.
- **A typo reserves nothing.** → `reserves.paths = [ "/etc/sshd_config" ]` matches no claim and earns
  no row, exactly as a claim of a path nobody else writes does. The alternative is validating a path
  against the machine, which is the same probe. The registry file being one short list a reader reads
  end to end is the mitigation.
- **A reservation with no protocol matches only a claim with no protocol.** → `portsOf` compares
  `"unstated/<number>"` when a claim states no `proto` (`lib/plan.nix:701-709`), and the reservation
  is read the same way, so the two halves agree by construction. It is still a footgun, and the fix
  belongs to the change that types the claim on both halves at once rather than to a second, private
  rule here.
- **Cost.** → One extra field read per machine and one extra claim per reserved resource in a list
  that is already grouped twice. Machines are the smallest dimension of a fleet, `perf/fleet.nix` at
  256 declares no reservation, and the gate is `nix build .#checks.x86_64-linux.planner-perf` with a
  margin of 0.15 per plan entry.
- **The plan carries no trace of the reservation.** → A reader of `plan.json` sees the row and not
  the declaration behind it. The row names the machine, the resource and the registry file, which is
  what a resolution is for, and the alternative costs every key on that machine.

## Open questions

- Whether a machine should be able to reserve an account or a group name. Nothing in a plan creates
  an account (`CLAUDE.md`, End-to-end layer), so a collision there is real, but the plan has no
  account claim to compare against - only `supplementaryGroups` read by name - and inventing one is a
  separate change. Left out deliberately rather than half-answered.
- Whether a reserved path should be compared against a generated value's delivered path. Those live
  under `/run` and are the library's own (`lib/resolve.nix`), so a machine reserving one is stating a
  conflict with the planner rather than with an entry, and the row would name no declaration the
  author wrote. Left out until a deployment shows the case.
- Whether `proto` becomes required, or defaults to `tcp`, on both halves. That decision belongs to
  `type-a-port-claim-and-its-collision`; this change reads whatever that one settles.
