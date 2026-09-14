## Why

A machine is the one participant in a deployment that cannot say what it is already doing. The
registry reads five keys and refuses every other one (`lib/resolve.nix:42-48`, read field by field at
`lib/resolve.nix:268-274`), and `docs/authoring.md:735` states the rule as "A machine declares those
five keys and nothing else." None of the five is a reservation: `address`, `tags`, `system`,
`serviceManager` and `microarchitecture` are what a consumer dials, what a placement selects on and
what a target is elaborated from. What the host image on that machine already listens on, and which
files it already owns, is a fact the deployment has nowhere to write.

The claim index is built from placed service entries and nothing else. `lib/plan.nix:1098` is
`concatLists (map (e: e.rows) serviceEntries) ++ collisionRows (concatMap claimsOf serviceEntries)`,
and `claimsOf` returns claims only for a record carrying an entry's `claims` field
(`lib/plan.nix:714-726`). The machine records built two lines above it (`lib/plan.nix:1078-1093`)
carry `address`, `tags`, `system`, `serviceManager` and `microarchitecture`, and contribute no claim.
So a deployment claiming port 22, 53 or 80, or declaring `configData."/etc/ssh/sshd_config"`, is
applicable, the plan is produced with an empty table, and the unit then fails to bind or overwrites a
file the machine was relying on. Nothing in the table says which declaration to edit, because the
planner never held the other half of the comparison.

The hazard is live in this repository, in its own worked fixture. `borg-repo`'s server claims
`tcp/22` (`fixtures/minimal-typed-edge/modules/borg-repo/server.nix:14-18` over the `fixed.port = 22`
of `fixtures/minimal-typed-edge/modules/borg-repo/default.nix:13-15`), placed on `vault`, and
`fixtures/minimal-typed-edge/plan/diagnostics.txt` records no row about it - correctly, because
nobody told the planner that a machine running sshd holds that port. The end-to-end layer is the same
shape from the other side: its whole delivery channel is TCP sshd on the guest
(`tests/e2e/guest.nix:130-138`, "The TCP listener is the delivery channel"), so a folder whose module
claimed `tcp/22` would break the channel the run uses to deliver it, and the planner would say
nothing. Today the only place that list can live is outside the deployment entirely, in whatever the
operator keeps beside it, and nothing crosses the two.

## What Changes

- **A machine MAY declare the host resources it already holds.** The machine registry gains a sixth
  key, `reserves`, with two members: `reserves.ports.<name> = { proto = "tcp"; number = 22; }` and
  `reserves.paths = [ "/etc/ssh/sshd_config" ]`. The key is optional, and an absent one means *not
  stated, do not check*, so no deployment that exists today moves: every machine of `fixtures/` and
  `perf/` declares nothing and produces the same plan bytes and the same table.
- **A reservation is a claimant like any other.** A resource a machine reserves and a placed entry
  claims earns the row that resource's kind already has - `entry-port-claimed-twice` and
  `entry-host-path-claimed-twice` - rather than an identifier of its own. The machine's claimant key
  is `machine:<name>`, which is the record key the plan already carries (`lib/plan.nix:1080`) and a
  valid row subject (`lib/diagnostics.nix:25-33`). It enters the same sort every entry key enters, so
  it is the row's subject exactly when it sorts first, and the row names it either way. Its
  resolution names both declarations a reader can edit: the entry's claim and the registry's
  reservation.
- **A reservation enters no key.** It is read into the machine field reading and projected into its
  own table, not into `machineRecords` (`lib/resolve.nix:402-419`) and not into `targetOf`
  (`lib/resolve.nix:425-438`). A machine record is hashed into `machineKey` (`lib/plan.nix:28`),
  which every placed entry depends on (`lib/plan.nix:778`) and every per-placement generated value
  depends on (`lib/plan.nix:955`), so recording a reservation there would re-key every entry on that
  machine and ask an external generator to regenerate bytes that are still correct.
- **The planner reserves nothing on its own behalf and reads no machine.** A reservation is a
  declaration, never a probe. A discovered one is `lib/excluded.nix`'s `lifecycle` row - "the first
  value that is not knowable at evaluation" - and stays out until that construct lands.
- **No realiser reads a reservation.** It opens no firewall port, renders no socket unit and writes
  no file. It is a declaration-versus-declaration consistency check, which is what every claim in
  this library already is.

## Capabilities

### New Capabilities

<!-- none: a machine's registry and the collision rows are capabilities that exist -->

### Modified Capabilities

- `planner/machine-platform`: the registry reads a sixth, optional key stating the host resources the
  machine already holds, and that key is outside the machine's own key and every entry's key.
- `planner/diagnostics`: a resource a machine reserves and a placed entry claims earns the row that
  resource's kind already has, with the machine named as one of the claimants.

## Impact

- `lib/resolve.nix`: `machineRegistryKeys` gains `reserves` (`:42-48`); `shapes` gains a number shape
  (`:64-85`), the registry reading having needed only names, name lists, records and booleans so far;
  `machineFields` reads the record and its two members (`:268-274`); `resolved` publishes a
  reservation table beside `machines` (`:1984-2004`). `machineRecords` and `targetOf` are untouched,
  which is what keeps the field out of every key.
- `lib/plan.nix`: the reservations of the machines the plan carries a record for become claims in the
  same flat list `collisionRows` already folds (`:1098`), so the check itself does not change. The
  message template of `hostResources` (`:638-666`) stops saying "entries", because one claimant may
  be a machine, and the resolution names the registry where a reservation is among the claimants.
- `tests/unit/resolution.nix` and `tests/unit/plan.nix`: the registry scenarios and the row
  scenarios. `tests/unit/diagnostics.nix` covers the new code by construction - its purity scan and
  its row-versus-refusal cross-walk read the sources they are handed - and no new identifier is
  introduced for it to account for.
- `fixtures/minimal-typed-edge/plan/*` and `perf/`: byte-identical. No machine in either declares a
  reservation, and the plan records the field nowhere, so there is nothing for `pruned` to drop and
  no golden to regenerate. The fixture deliberately keeps its unreserved `tcp/22` claim: adding a
  reservation there would make the worked deployment inapplicable and move both goldens.
- `docs/authoring.md`: the machine key table and the "five keys and nothing else" sentence at `:735`.
  `docs/diagnostics.md`: the two row descriptions under "What two entries of one machine both claim",
  whose heading no longer describes what the rows are about.
- `CLAUDE.md`: the reservation beside the claim index under Diagnostics, and why it is outside the
  machine record under Keys and identity.
- Nothing under `image/`, `flakelet/`, `secrets/`, `operator/` or `cli/` changes. No plan field is
  added, so no realiser and no subcommand sees anything new; what changes is that a deployment
  contradicting a stated reservation carries an error row and does not build.
- `openspec/changes/type-a-port-claim-and-its-collision` owns the address on a claim. The two
  compose: that change decides which addresses on one machine are two listeners, this one decides
  what the machine itself holds. Neither answers the other's question.
