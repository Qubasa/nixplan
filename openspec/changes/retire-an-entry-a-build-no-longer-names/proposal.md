## Why

There is no way to decommission a service. Deleting a member from a deployment removes it from the
plan, from `manifest.json` and from every report line, and leaves it running on the machine forever:
`cli/report.py:372-391` looks for what a machine holds only under the entries the current build
names, so an entry the build dropped appears in no answer, and no subcommand ever removes one -
`image/default.nix:378-385` builds a `bin/detach` into every image artifact that only a test runs
(`tests/e2e/portable-image/test_portable_image.py:380`), and nothing in `cli/` ever calls
`flakelet remove`. An operator's only recourse today is to ssh in and run the endpoint's tool by
hand, against a name the build no longer prints.

## What Changes

- The report gains a fifth thing it says. Beside held, absent, no endpoint and unreachable, it names
  per machine every holding the machine runs that this build does not name, with the identity or
  name the machine gave it. The line does not change the exit status, for the reason staleness and a
  missing value do not: an orphan is an answer a machine gave, and changing it is an apply's work.
- `apply` asks the same question, announces the same lines before it writes anything, and retires
  nothing unless it is asked to. A new `--retire` takes the retirement; without it the announcement
  says what would be retired and that nothing was removed.
- A retirement is the endpoint's own verb and deletes no state: `flakelet remove` without `--purge`,
  which keeps and lists the state folders, and `portablectl detach --now` for an image, which stops
  the units before it unlinks them. No state directory, no delivered value and no staged file is
  deleted, and the announcement says what was kept. A retirement never runs a script out of the
  retired entry's own artifact: that artifact is not in the build being applied and nothing on the
  machine roots it, so `bin/detach` stays the artifact's own contract and is not what retires an
  orphan.
- The retirement is the first thing a run does on a machine, before the value writes and before any
  copy or activation, because the host resources an orphan holds - a port, a unit file name, a host
  path - are exactly what a renamed entry needs back before it can start.
- `--only` never makes an entry an orphan. A holding is an orphan when the deployment places no
  entry that owns it at all; the selection decides which machines are asked and nothing about what
  counts as unnamed.
- The deployment record publishes, per realiser the reading is handed, what a machine's own answer
  names that realiser's holdings by. The command recognises a holding by what is published and by
  nothing else, so a declaratively configured flakelet service and a portable image some other tool
  attached are neither reported nor retired. The literal `plan:` that
  `tests/e2e/delivery.py:36` keeps equal to `flakelet/read.nix:194` by comment becomes one published
  fact the test reads.
- Retiring from a machine the build no longer names at all is **out of scope**, stated plainly
  rather than worked around: `lib/plan.nix:1404-1418` emits a `machine:<name>` record only for a
  machine some placement selected, so a machine whose every entry was dropped carries no address
  anywhere in the new build. No machine-identity field is invented for it, and `docs/operator.md`
  states the operator's own order of work instead.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `operator/machine-report`: adds the fifth answer a report gives - a holding the build does not
  name - the rule that it costs no exit status, the rule that a holding is recognised only by what
  the record publishes, and the rule that the selection bounds which machines are asked rather than
  what counts as unnamed.
- `operator/apply-command`: adds the question every apply asks, the announcement it makes, the
  `--retire` step, where the step sits in the walk, what the step may and may not remove, the
  interaction with `--only`, and the stated limit that a machine the build does not name is out of
  reach.
- `operator/deployment-build`: adds one published fact - per realiser the reading is handed, what a
  machine's own answer names that realiser's holdings by - read off the realiser itself rather than
  restated by the reading. The record's stated version moves with it, because a command that read an
  older record would report no holding and a false negative here reads as nothing to retire.

## Impact

- `cli/remote.py`: the question that lists what a machine holds, per realiser; the retirement step,
  per realiser; the reading of each answer into holdings.
- `cli/report.py`: the orphan lines, beside the value lines, and the recognition rule.
- `cli/apply.py`: the question, the announcement, the retirement step and its place in the walk.
- `cli/planner.py`: `--retire` on `apply`, and its help.
- `cli/manifest.py`: the published per-realiser record read off `manifest.json`.
- `operator/read.nix`: the record's new table, asked of the stated realiser.
- `flakelet/read.nix`, `image/read.nix`: each publishes what a machine's answer names its holdings
  by, beside the name and unit rules it already publishes.
- `tests/e2e/wired-pair/`: a third build that drops one entry, and the flakelet retirement phases.
- `tests/e2e/portable-image/`: a second entry on the booted machine, a third build that drops it,
  and the image retirement phases.
- `tests/e2e/test_harness.py`, `cli/counterexample_test.py`: the argv of a retirement, the
  refusals, the exit status and the selection rules.
- `tests/e2e/delivery.py`: reads the published literal instead of keeping its own copy equal.
- `tests/unit/operator.nix`: the published table.
- `docs/operator.md`, `docs/cluster.md`, `CLAUDE.md`.
