## Why

An entry realised as a portable-service image is shown the values it generated and none of the
values it declared a read of. `generatedOf` in `image/read.nix:435-454` walks `entry.vars` and
nothing else, and `hostPathsOf` (`:562-591`) shows a host path for the deployed reference files of
exactly that walk. `entry.vars` is the member's own declaration: `lib/plan.nix:1080` fills it from
`placement.vars` through `varsRecord` (`lib/plan.nix:150-151`), and `placement.vars` is built over
`member.declaration.vars.generators` (`lib/resolve.nix:1476`, `:1696-1699`). A value another entry
generates reaches a consumer through the resolved read `readsRecord` publishes
(`lib/plan.nix:239-283`), which records the value by its path (`:279-281`) and which
`image/read.nix` never consults.

The bytes do arrive. A declared read is what puts the reader's machine in the value's delivery set
(`lib/plan.nix:165-168`), so the file is on the machine before any entry is activated. What is
missing is the statement that shows it to the unit.

**An operator hitting this today gets no diagnostic at all.** Evaluated on this tree over a
two-member deployment - a provider declaring `vars.token.files.secret` and publishing it as a
secret export, a consumer declaring `uses.cred.reads = [ "token" ]` and naming
`results.cred.token.path` in its unit's environment, both placed on one machine - `mkPlan` answers
`applicable = true` with an empty error list, the value entry records
`delivery = [ "one" ]` and `deliveryDerivedFrom = [ "app:only@one named token in uses.cred.reads"
… ]`, the consumer's unit records `TOKEN = /run/vars/vault/token/secret`, and the consumer records
no `vars` at all. Asked about that consumer, `imageReader.hostPaths` answers `[ ]`, the attachment
description `imageReader.attachment` produces carries `hostPaths = [ ]` and `generated = [ ]`, and
`imageReader.denials` under `strict` answers `[ ]` - while the same file, on the same machine, under
the same profile, earns the owning entry one denial naming
`root:root at mode 0400` and `a transient account`. One record, two readings, opposite answers.

Three consequences follow from the one omission, and none of them is reported anywhere:

- **The unit is shown nothing.** No `BindReadOnlyPaths` line is rendered
  (`image/read.nix:640-642`, spent at `:1008` and `:1115`) and no mount point is created
  (`image/default.nix:103-109`), so the path the unit's own environment names is absent from the
  unit's view of the filesystem. Outside `/run` that is a missing mount point on a read-only
  squashfs, which `CLAUDE.md:396-398` records as `226/NAMESPACE`; under `util.varsRoot`
  (`lib/util.nix:345`) the service manager's own `/run` tmpfs makes it a bare `ENOENT`. Either way
  the machine names neither the value nor the declaration, and a program that reads an unopenable
  credential as an absent one runs without it and reports success.
- **The profile denial table is blind to it.** `denialsOf` (`image/read.nix:602-635`) is handed
  `generatedOf entry` (`:704`, `:884`), so the readability rule `CLAUDE.md:364-367` asks at three
  sites is asked about the entry's own files only. `slot-reads-value-unreadable-by-user`
  (`lib/plan.nix:329-361`) covers the planner's half over `edge.entryVarsFiles` (`:360`), so the
  planner refuses a unit that cannot open a peer's value and the realiser does not.
- **A closure root naming a peer's value is not refused.** `referencePaths`
  (`image/read.nix:809-814`) is built from the same walk, so `closure-root-is-delivered`
  (`:928-929`) does not fire for it. Observed on the probe above: `referencePaths` is `[ ]` for the
  consumer.

The gap is untested. `tests/e2e/portable-image/` is the only image folder with a delivered secret
and that value is the entry's own generator - `vars.upstream` in
`tests/e2e/portable-image/deployment/modules/report/watch.nix:14-22`, named at `:75`, recorded as
`SECRET_VALUE = "watch:vars/upstream"` in
`tests/e2e/portable-image/test_portable_image.py:77`. Its one cross-entry read carries no value:
`mirror/copy.nix:9-13` reads `path`, which `watch.nix:66-68` publishes as a configuration file's
path. The cross-entry secret reads live in `tests/e2e/shared-postgres/`
(`deployment/modules/app/client.nix:17-22,49`), which is flakelet-realised
(`test_shared_postgres.py:533`).

The defect has been on record since `deliver-a-secret-without-exposing-it/proposal.md:40-46` named
it, and that change was narrowed for the reason `CLAUDE.md` records, leaving it unowned.

## What Changes

- **The values an entry is shown are its own and the ones its declared reads name.** One reading
  answers the union, and every consumer of the old walk reads the union instead: the host paths, the
  profile denial table, the reference paths and the attachment description. A value reached twice -
  by a second read of one provider's second export, or by a read and the entry's own generator - is
  one record, one bind, one mount point and one denial, the `dedup`-keeps-the-first discipline
  `CLAUDE.md` states for rows.
- **The join is by the path the read record already carries.** The plan records a secret read as
  `{ path, secrecy }` (`lib/resolve.nix:2077-2083`) and the value's own entry records the full file
  record beside its delivery set. The reading looks the path up in one index over the plan's value
  records, built once per reading. No plan field is added: the relation exists in evaluation as
  `edge.entryVarsFiles` and is deliberately unpublished, because `reads` is in an entry's key
  input (`lib/plan.nix:1086-1102`) and a read record carrying a peer's ownership would re-key every
  consumer whenever a peer's `mode` moved.
- **The deploy condition is unchanged and now applies to both halves.** A value the plan records as
  undeployed is shown at no path, whether the entry generated it or read it: it is on no machine, so
  the bind would mount nothing. `slot-reads-undeployed-value` (`lib/resolve.nix:2516-2525`) is the
  row an operator already gets for the read half.
- **A shown value path the reading can account for no delivered bytes of is a refusal, never a
  silent omission.** `operator/read.nix` produces `operator-entry-value-unaccounted` naming the
  entry, the slot and the value, and the builder's refusal carries that identifier, the way
  `operator-entry-access-denied` already mirrors `imageReader.denials` (`image/read.nix:212`,
  `operator/read.nix:388-399`). The condition is a plan the reading was handed whose read record
  names a path its value records do not deliver to that machine - a fact only a reading of the whole
  plan holds, which is why it is that reading's row and not `mkPlan`'s.
- **The version digest needs no widening and moves anyway.** `versionFor`
  (`image/read.nix:713-756`) already takes the digest over `hostPathsOf` (`:733-747`), and the
  requirement already names "the host paths it is shown"
  (`openspec/specs/realiser/portable-service-image/spec.md:767-774`). Widening the set therefore
  widens the digest by construction: a consumer that declares a read of a peer's value publishes a
  digest it did not publish before, which is correct and is stated rather than left to be inferred.
- **One rule for both realisers.** `bindsOf` is the shared reading's, and flakelet's wrapper renders
  it too (`tests/unit/flakelet.nix:708`), so a flakelet entry that reads a peer's value gains the
  same statement. flakelet's own predicates already admit it: `acceptsHostPath` answers true for a
  generated file whose `from` is its `path` (`flakelet/read.nix:137-142`) and its `pathRule`
  (`:128-135`) is written for exactly this case. The consequence is one new generation per affected
  flakelet entry on the first apply, which is the cost the digest requirement already records for a
  widening (`spec.md:782-784`).
- **An end-to-end proof in `tests/e2e/portable-image/`, as a new phase and not a new folder.** A
  cross-entry value read needs one machine, not two: the owner's placement puts the value on the
  reader's machine. The folder's cut is keyed by the guest image, the machine names and the stage's
  disk figure (`tests/e2e/delivery.py:877-942`, the key stated at `:919-923`) and none of the three
  moves, so the phase costs no cut. A new folder would pay a full cut and could not reuse the
  report module: `tests/unit/layers.nix:1036-1039` refuses a folder naming a sibling and
  `:1041-1044` refuses a byte-equal copy of a sibling's file.
- **Out of scope, named rather than designed.** Per-unit narrowing of the denial - naming the units
  that name the file rather than every unit of the entry - stays task 6.2 of
  `deliver-a-secret-without-exposing-it`. Nothing here changes which machine a value reaches, and
  the delivery set stays what the owner's placements and the declared reads make it.

This change is the first of the five demonstration changes; `openspec/changes/INTEGRATION.md`
records the order and every seam between them.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `realiser/portable-service-image`: MODIFIES `A path is shown only where bytes arrive at it` so
  the set is the entry's own generated files and the ones its declared reads name, and MODIFIES
  `A deployed value is denied to a unit only where its record cannot admit that unit's reader` so
  the denial table reads the same set. ADDS the single-record discipline for a value reached twice
  and the four readings that ask one list, and ADDS the refusal for a shown value path no
  delivered bytes are accounted for.
- `delivery/real-cluster`: ADDS the machine-layer proof - an image-realised consumer opening, on a
  real machine, a value a different entry generated, with the bind read off the artifact's own unit
  file and the file read off the machine.

## Impact

- `image/read.nix`: the value index over the plan, the union the reading answers, the unaccounted
  list, and `hostPathsOf`, `denialsOf`, `referencePaths` and the attachment description reading it.
  The three published entry points - `hostPaths`, `denials` and `versionFor` - take the union.
- `operator/read.nix`: builds the index once per reading, computes the union once per entry beside
  the denials it already computes, and produces `operator-entry-value-unaccounted`.
- `image/default.nix`: no edit. It maps `image.hostPaths` for the mount points (`:103-109`) and for
  the attach-time existence guard (`:344-348`), so both cover the new paths by existing. That it
  needs none is the evidence the seam is in the reading.
- `docs/diagnostics.md`: the new row. `docs/operator.md`: which values an entry is shown.
- `tests/unit/image.nix`, `tests/unit/operator.nix`: the new scenarios.
- `tests/e2e/portable-image/`: one interface export, one consumer module, one instance, one
  statement and one phase. `tests/e2e/shared-postgres/`: no edit, and the flakelet half of the rule
  is observed there.
- `openspec/changes/deliver-a-secret-without-exposing-it/tasks.md`: tasks 6.1 and 6.3 marked
  superseded by this change.
- `CLAUDE.md`: the invariant under "Realisers".
