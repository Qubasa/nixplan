## Context

See proposal.md - Why. What each side already holds:

- The record publishes `entries.<key>.key`, the artifact's version digest
  (`operator/read.nix:210`, `:492`).
- A flakelet endpoint stores that digest in the generation it keeps
  (`flakelet/read.nix:170`, `flakelet-core/src/generations.rs:12-29` at the locked revision) and
  reports it nowhere. `flakelet status --json` prints `ServiceStatus`
  (`flakelet-core/src/manager.rs:86-108`, `flakelet/src/main.rs:766-782`), which carries `name`,
  `flake`, `origin`, `generation`, `units`, `locked_url`, `pin`, `override_flake`, `degraded`,
  `held`, `disabled`, `last_error`, `updating`, `failed_units`, `unit_states`,
  `missing_providers`, `state`, `export_blockers` and `changed`, and no identity of the artifact.
  The one other JSON the tool prints is `export`'s `ExportMeta`, which does carry
  `settings_hash` and refuses every artifact of this repository, because `export_meta` requires an
  empty blocker list and our artifacts deliberately carry no `state.json`.
- `locked_url` is `plan:<plan entry key>` (`flakelet/read.nix:167`, `tests/e2e/delivery.py`), which
  is invariant under every content edit, so it answers nothing about staleness.
- What does move is `units`: the active generation's map of unit file name to the store path of
  that file (`manager.rs:1349-1377`). Our artifact is a farm of links, one `writeText` per unit
  (`flakelet/default.nix`), so those are paths the build itself holds at
  `<artifact>/units/<file>`.
- An image carries the digest in the name of the image file itself,
  `<name>_<version>.raw` (`image/read.nix:512`), and the command asks only
  `portablectl is-attached <path>` (`cli/remote.py:323-325`), which answers about the path it was
  given rather than about what the machine holds for that entry.

## Goals / Non-Goals

**Goals:**

- One verdict per line, from the build and the machine's own answer, with both identities printed
  when they differ.
- A verdict for both realisers, each from the fact its machine can actually report, in words that
  say which fact it was.
- No new field anywhere: nothing is published, planned or stored that is not already.

**Non-Goals:**

- No exit-status change. `operator/machine-report` already fixes the exit status to whether every
  machine answered, and a stale entry is an answer.
- No repair. `status` says what is; `apply` changes it.
- No comparison of the plan entry key. It moves with a machine's address and no artifact byte, so
  comparing it would report every entry on a re-addressed machine as stale.
- No new remote round trip per entry. What is compared comes out of the answer the command already
  gets.

## Decisions

### The verdict is computed from the record, and the record must carry it

`Entry` gains `digest`, read by `_entry` through the same `_text` that already refuses a missing
`path`, `realiser` or `machine`. A record with no `key` for a placed entry is therefore refused as a
record the command cannot read, which is the behaviour `manifest.VERSION` gating already establishes
for a record from another revision: both sides of the field move together, so a record without it is
not an older record, it is a malformed one.

Alternative considered: default a missing identity to "unknown" and print no verdict. Rejected - it
makes the absence of the publisher's own field a silent degradation of the report, and the report is
the thing being fixed.

### flakelet compares the unit files, and the line says so

The endpoint reports no identity, so `_read_status` compares what it does report: the unit paths
of the generation it runs against the unit files the build's own artifact carries, which
`manifest.unit_files` resolves. The line says `runs this build's units` or `runs units this build
did not produce`, and an answer carrying no unit at all says `reports nothing to compare`. None of
the three says `current`, because that word belongs to the identity comparison and this is a
narrower question.

The gap is exact and worth stating: the published digest also digests the closure, the host paths,
the service manager and the platform (`image/read.nix:264-280`), so an edit moving one of those
without moving a byte of any unit text runs this build's units and carries another identity. It is
mostly self-closing - a host path is in a unit's bind directives and a package is in its
`ExecStart` - so the residue is a declared closure root no unit mentions and a platform field no
unit text reaches. In exactly those cases `runs this build's units` is the true sentence and
`current` would be the false one, which is why this is the accurate answer rather than a
compromise.

Alternative considered: read the identity off the machine anyway, from
`<gcroot_dir>/<name>/gen-<N>/manifest.json`, with the generation number the status answer already
carries. Rejected - `gcroot_dir` is flakelet's own configuration (`flakelet-core/src/config.rs`
defaults it), the generation layout is its internal shape, and `cli/` holds no flakelet layout
today; a machine configuring another directory would answer "nothing to compare" while looking
like a working comparison.

Alternative considered: make the comparison exact by putting the entry's version digest into each
unit file's derivation name in `flakelet/default.nix`, so a moved digest moves every unit path.
Rejected - it lets a report's semantics dictate a realiser's derivation names, it adds a
`realiser/flakelet-artifact` delta and a guard to this change, and it buys only the residue above.

Because the weaker comparison is a fact about one revision of somebody else's tool, it is guarded
rather than trusted: `delivery.endpoint_refusal` reads the locked flakelet source, compares the
recorded field set of `ServiceStatus` against the resolved one and fails naming this decision and
`cli/report.py`. It fails open - an unresolvable or unparseable source skips - because an
unreadable signal is not evidence the answer moved.

### An image compares the attached image's name

`image_status_script` keeps `portablectl is-attached` and gains a listing of what the machine holds
attached, so the answer carries both the attachment state and the name of the image attached for that
entry. The name carries the digest, so the comparison is a name comparison and needs no new field on
the machine.

Alternative considered: read `attachment.json` out of the copied artifact on the machine, the way
`tests/e2e/wired-pair/test_wired_pair.py:739` reads `meta.json`. Rejected - that reads what was
copied, not what is attached, so an entry copied and never attached would report as current.

### The line's shape

`<key> <realiser> <what the machine said>` gains a clause after what the machine holds and before
the error it recorded: `current` or `holds <machine identity>, built <record identity>` where an
identity was compared, and `runs this build's units`, `runs units this build did not produce` or
`reports nothing to compare` where the unit files were. The prefix an operator greps is unchanged
in every case, which is what `docs/operator.md`'s table and `tests/e2e/wired-pair` read; the error
stays last, because a clause after `last error <e>` would read as part of the error.

## Risks / Trade-offs

- **The weaker comparison could be read as the stronger one.** → Its words are its own, no line of
  it says `current`, and `docs/operator.md` tables the two side by side.
- **The endpoint could gain the identity upstream and leave the weaker comparison in place.** →
  `delivery.endpoint_refusal` compares the recorded field set of `ServiceStatus` against the locked
  source and fails naming this decision.
- **`portablectl` output is a machine-specific format the command now parses more of.** → Only the
  image name is read, matched against the name the build published, and a listing the command cannot
  parse is reported as the machine's own answer rather than as a verdict, which is the rule
  `make-an-apply-observable` already sets for an unreadable endpoint answer.
- **A report line gets longer.** → The clause is inserted after what the machine holds, so the
  existing prefix an operator greps is unchanged.
- **The comparison could tempt a future change into exiting non-zero for a stale fleet.** → The spec
  states the exit status negatively for exactly that reason.
