## Context

See proposal.md - Why. What each side already holds:

- The record publishes `entries.<key>.key`, the artifact's version digest
  (`operator/read.nix:210`, `:492`).
- A flakelet endpoint stores that digest as the generation's `settings_hash`
  (`flakelet/read.nix:170`), and `docs/flakelet.md:88-92` records that it is carried into the
  generation the endpoint keeps, so it is a field of the JSON `cli/report.py:221` already decodes and
  then reads `generation` and `locked_url` out of.
- An image carries the digest in the name of the image file itself,
  `<name>_<version>.raw` (`image/read.nix:512`), and the command asks only
  `portablectl is-attached <path>` (`cli/remote.py:323-325`), which answers about the path it was
  given rather than about what the machine holds for that entry.

## Goals / Non-Goals

**Goals:**

- One verdict per line, from the record and the machine's own answer, with both identities printed
  when they differ.
- The same verdict for both realisers, from the fact each one's machine can actually report.
- No new field anywhere: nothing is published, planned or stored that is not already.

**Non-Goals:**

- No exit-status change. `operator/machine-report` already fixes the exit status to whether every
  machine answered, and a stale entry is an answer.
- No repair. `status` says what is; `apply` changes it.
- No comparison of anything but the published identity. The plan entry key moves with a machine's
  address and no artifact byte, so comparing it would report every entry on a re-addressed machine as
  stale.
- No new remote round trip per entry. The identity comes out of the answer the command already gets.

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

### flakelet compares the endpoint's `settings_hash`

`_read_status` already decodes the endpoint's JSON list. It gains the entry's own digest as an
argument and reads `settings_hash` off the same generation record it reads `generation` and
`locked_url` off. Where the field is absent from an endpoint's answer the line says the endpoint
reported no identity, which is a fourth thing to say rather than a silent "current": an endpoint
that does not report one cannot be compared, and `docs/flakelet.md:136-137` already records that an
older generation can lack fields.

### An image compares the attached image's name

`image_status_script` keeps `portablectl is-attached` and gains a listing of what the machine holds
attached, so the answer carries both the attachment state and the name of the image attached for that
entry. The name carries the digest, so the comparison is a name comparison and needs no new field on
the machine.

Alternative considered: read `attachment.json` out of the copied artifact on the machine, the way
`tests/e2e/wired-pair/test_wired_pair.py:739` reads `meta.json`. Rejected - that reads what was
copied, not what is attached, so an entry copied and never attached would report as current.

### The line's shape

`<key> <realiser> <what the machine said>` gains a trailing clause: `current` where the identities
agree, and `holds <machine identity>, built <record identity>` where they do not. The existing text
is untouched, because `docs/operator.md:386-399` tables it and `tests/e2e/wired-pair` reads it.

## Risks / Trade-offs

- **An endpoint's answer may not carry `settings_hash` on an old generation.** → That is a fourth
  answer ("the endpoint reported no identity"), not a verdict, and it is stated in the spec rather
  than collapsed into either side.
- **`portablectl` output is a machine-specific format the command now parses more of.** → Only the
  image name is read, matched against the name the build published, and a listing the command cannot
  parse is reported as the machine's own answer rather than as a verdict, which is the rule
  `make-an-apply-observable` already sets for an unreadable endpoint answer.
- **A report line gets longer.** → The clause is appended, so the existing prefix an operator greps
  is unchanged.
- **The comparison could tempt a future change into exiting non-zero for a stale fleet.** → The spec
  states the exit status negatively for exactly that reason.
