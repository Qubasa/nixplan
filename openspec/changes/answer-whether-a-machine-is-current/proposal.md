## Why

The build publishes an identity per entry so that a report can compare a machine against a build, and
the report never compares.

`operator/read.nix:210` computes `digest = imageReader.versionFor { inherit key entry; }` and
`:492` writes it into the deployment record as that entry's `key`. `report-every-refusal-as-a-row`
states why: "The identity a build publishes for a placed entry SHALL be the identity the machine's own
endpoint records for the artifact of that entry, so that a report can compare what a machine holds
against what a build holds", and the endpoint does record it - `flakelet/read.nix:170` puts the same
digest in the artifact's `settings_hash`, and an image's file name carries it
(`image/read.nix:512`).

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
keeps, so it is in the JSON `cli/report.py:221` already parses and then reads two fields out of.
`tests/e2e/wired-pair/test_wired_pair.py:739-741` performs the comparison by hand, against the
artifact's `meta.json` read over ssh, which is evidence that the identities line up and that the
command is the only thing not doing it.

The identity is already computed, already published, already stored on the machine, already carried
in the answer the command parses, and already required to be comparable. The only missing step is the
comparison.

## What Changes

- **A report line says whether the machine is current.** For each entry asked about, the report
  states whether the identity the endpoint holds is the identity this build published for that entry,
  and where it is not, prints both.
- **The comparison identity is read from the deployment record, never recomputed.** The command reads
  the published identity out of the record, so a report cannot disagree with the build it was run
  against. A record carrying no published identity for a placed entry is refused as a record the
  command cannot read, the way a record of another version already is.
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
  answer carrying a matching and a non-matching identity.
- `tests/e2e/wired-pair` and `tests/e2e/portable-image`: a report after an apply says current, and a
  report after a second build of an edited deployment says the machine holds the older identity.
- `docs/operator.md`: the report's vocabulary and the worked example.
