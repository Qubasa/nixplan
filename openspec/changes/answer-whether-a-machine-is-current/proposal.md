## Why

The build publishes an identity per entry so that a report can compare a machine against a build, and
the report never compares.

`operator/read.nix:210` computes `digest = imageReader.versionFor { inherit key entry; }` and
`:492` writes it into the deployment record as that entry's `key`. `report-every-refusal-as-a-row`
states why: "The identity a build publishes for a placed entry SHALL be the identity the machine's own
endpoint records for the artifact of that entry, so that a report can compare what a machine holds
against what a build holds", and each endpoint does record it - `flakelet/read.nix:170` puts the same
digest in the artifact's `settings_hash`, and an image's file name carries it
(`image/read.nix:512`). Recording it and reporting it are two things: the image's own file name is
what the machine names back, while `flakelet status --json` prints `ServiceStatus`
(`flakelet-core/src/manager.rs:86-108` at the locked revision) and keeps the digest in the
generation it stores. What that answer does carry is the unit files of the generation it runs,
which are files of the artifact the build produced.

Then the command drops it. `cli/manifest.py:347-366` builds an `Entry` from `path`, `realiser`,
`profile`, `machine`, `address` and `units`, and reads no `key`. `cli/report.py:216-233` renders
`generation <n> of <locked_url>` out of the endpoint's answer and compares it with nothing. So the
four answers `operator/machine-report` requires a report to keep apart - held, absent, no endpoint,
unreachable - are answered, and the fifth question an operator actually has is not:

> is what this machine is running the deployment I just built, or an older one?

Today the two cases print the same shape of line and are told apart by an operator eyeballing a hash
they must find in `manifest.json` themselves. The consequences are ordinary: an apply that stopped
half way (`cli/apply.py` is fail-stop through `remote.taking`, and recovery is "run apply again")
which some machines are current and some are not, and the command whose job is to say what each
machine holds cannot say which is which. `docs/operator.md`'s worked report shows generations and
locked URLs and no verdict.

Two more places state the comparison as a settled fact. `docs/operator.md:197` documents the field
as "the artifact's own identity digest, which is what the machine's endpoint stores for it as
`settings_hash`. A report can therefore compare what a machine holds against what a build holds",
and `docs/flakelet.md:88-92` records that the digest is carried into the generation the endpoint
keeps. `tests/e2e/wired-pair/test_wired_pair.py:739-741` performs the comparison by hand, against
the artifact's `meta.json` read over ssh, which is evidence that the identities line up and that
the command is the only thing not doing it.

What that hand comparison reaches for is also what the endpoint's answer withholds, and this change
found it out rather than assuming it: the digest is stored and not reported, so a flakelet entry is
compared by the unit files the answer does carry, in words that say so. An image is compared by its
identity, because the machine names it.

Everything needed is already computed, already published, already on the machine, and already
required to be comparable. The missing step is the comparison.

## What Changes

- **A report line says whether the machine is current.** For each entry asked about, the report
  states whether what the machine holds is what this build published: by identity where the machine
  names one, printing both where they differ, and by the files of the artifact where it does not.
- **The comparison identity is read from the deployment record, never recomputed.** The command reads
  the published identity out of the record, so a report cannot disagree with the build it was run
  against. A record carrying no published identity for a placed entry is refused as a record the
  command cannot read, the way a record of another version already is.
- **A weaker comparison says that it is one.** Where an endpoint names no identity the line says
  whether the machine runs this build's units rather than saying `current`, and where it names
  nothing comparable the line says so.
- **An image is compared by the artifact the machine holds.** An image's identity is in the name of
  the image the machine has attached, so an attached image from an older build is reported as an older
  build rather than as attached.
- **Staleness is a line, not an exit status.** A report whose machines all answered exits zero
  whatever the answers were, which is what `operator/machine-report` already requires; a stale entry
  is a fact about the machine, and changing it is `apply`'s job. This is stated so that a later change
  does not quietly make a fleet mid-apply exit non-zero.

## Capabilities

### Modified Capabilities

- `operator/machine-report`: a report answers whether what a machine holds is what the build
  published, reads that identity from the deployment record, distinguishes an older build from an
  absent entry for both realisers, and keeps its exit status a statement about whether every machine
  answered.

## Impact

- `cli/manifest.py`: `Entry` gains the published identity, and `_entry` reads it.
- `cli/report.py`: the status line carries the verdict; the image branch reads the attached image's
  name rather than only the attachment state.
- `cli/remote.py`: the image status script reports which image is attached, not only that one is.
- `tests/e2e/test_harness.py`: the four existing answers gain the comparison, over a fake endpoint
  answer carrying matching unit files, differing ones and none, and over a listing carrying a
  matching identity and an older one; plus the guard on the locked endpoint's own answer.
- `tests/e2e/delivery.py`: what the locked endpoint reports is recorded and compared, so the weaker
  comparison cannot outlive the reason for it.
- `tests/e2e/wired-pair` and `tests/e2e/portable-image`: a report after an apply says the machine
  runs this build, and a report after a second build of an edited deployment says it does not.
- `docs/operator.md`: the report's vocabulary and the worked example.
