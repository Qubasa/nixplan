## 1. Baseline and registration, before `lib/` is touched

- [x] 1.1 Record the perf baseline before editing anything under `lib/`: run `bash perf/measure.sh`
  (or `~/.claude/outputs/measure-perf.sh worked 0`) and paste the nine counters into the change's
  working notes. A new vocabulary field is read for every unit of every entry, so the gated counters
  will move; the recorded baseline is what says by how much. The gate is two-sided with a 0.15
  margin, so a regression is a task to fix and never a re-recorded budget.
- [x] 1.2 Register this change's three delta specs in `excused` in `tests/unit/coverage.nix`, one
  line per file, each reason naming this change in the shape `excuseNamesChange`
  (`tests/unit/coverage.nix:373-378`) matches - "an unimplemented change: no task of
  probe-a-service-before-it-counts-as-live has been done, ..." - for
  `changes/probe-a-service-before-it-counts-as-live/specs/planner/unit-vocabulary/spec.md`,
  `.../specs/realiser/flakelet-artifact/spec.md` and
  `.../specs/realiser/portable-service-image/spec.md`. Verify with
  `nix build .#checks.x86_64-linux.planner-tests` after 1.4: an unclassified `spec.md` fails
  `testEverySpecificationIsClassified`.
- [x] 1.3 **Leave every checkbox of this file unchecked for as long as the excuse stands.**
  `changeHasLanded` (`tests/unit/coverage.nix:380-385`) reads this `tasks.md` for a single `- [x]`
  line, and `staleExcuses` (`:387-397`) fails the suite for an excuse whose change has landed, so
  ticking one box while the three paths are excused turns the suite red for a reason that reads like
  a missing test. The paths move to `accountable` and the boxes are ticked in the one edit task 8.4
  makes. Verify by ticking nothing until then, and by `nix build
  .#checks.x86_64-linux.planner-tests` staying green through every task below.
- [x] 1.4 `git add` every new file of this change before evaluating anything - the flake does not see
  an untracked path and the failure reads as a missing file. That is the three spec files, `design.md`,
  `proposal.md`, `tasks.md`, and every new file a later task creates. Verify with
  `nix eval --json '.#debug.failures'` returning something other than a file-not-found error.

## 2. The vocabulary

- [x] 2.1 Add the zero-duration predicate to `lib/atoms.nix`, exported beside `portRange` and
  `domains`, covering every spelling of zero the `duration` type admits (`0`, `0s`, `0min`, and a
  concatenation whose components are all zero). Leave the `duration` type itself unchanged: `timeout`
  and `restartSec` may legitimately state zero, and narrowing the type would re-key plans that do.
  Verify by a `tests/unit/support.nix` or `tests/unit/units.nix` case asserting the predicate over
  `0`, `0s`, `00min`, `1s` and `0s1s`.
- [x] 2.2 Add `probe = atoms.string` and `probeTimeout = atoms.duration` to `unitVocabulary` in
  `lib/module.nix`. Verify that `unitKeys` grows by existing and that a unit declaring both records
  both, with `nix eval --json .#debug.worked.plan | jq` on a scratch deployment.
- [x] 2.3 Add the pair rows to `lib/module.nix`, behind one `unit ? probe || unit ? probeTimeout`
  gate per unit (design D8): `unit-probe-without-timeout`, `unit-probe-timeout-without-probe` and
  `unit-probe-timeout-unbounded`, each an error naming the module and the unit, and none of them
  recording either field. Verify with the `tests/unit/units.nix` cases of task 6.1.
- [x] 2.4 Add the shape rows to `lib/module.nix`: `unit-probe-on-one-shot` and
  `unit-probe-on-scheduled`, each an error naming the module and the unit, neither field recorded.
  Verify that a probe beside `restart = "on-failure"` earns no row (`tests/unit/units.nix`).
- [x] 2.5 Add `unit-probe-declared-twice` to `lib/module.nix`, computed once per entry over the unit
  set behind the same gate, naming the module and both units, recording neither statement. Verify
  with a two-unit module in `tests/unit/units.nix`.
- [x] 2.6 Confirm by test rather than by reading that no scan needed extending: `closure-path-undeclared`
  reaches a store path inside a probe (`lib/plan.nix:566-573` hands the scan the unit record minus
  `env` and `extends`), `vars-path-off-delivery-set` reaches a value path in one, and
  `unit-value-newline` reaches a line break in one. If any does not, extend the scan at its own site
  and never by adding a field list.

## 3. The derived unit

- [x] 3.1 Add the derived probe file name to `unitFilesOf` in `image/read.nix`, as
  `"${name}-health.service"`, emitted where any unit of the entry records a probe. Verify that
  `operator/read.nix`'s deployment record `units` list, the per-machine unit-file index, the image's
  own unit rule and `flakelet/read.nix`'s `acceptsUnit` all see it with no edit of their own
  (`tests/unit/operator.nix`, `tests/unit/flakelet.nix`).
- [x] 3.2 Add `probe = "ExecStart"` and `probeTimeout = "TimeoutStartSec"` to `unitDirectives` in
  `image/read.nix`, with a line saying the file they reach is the derived one. Verify that no build
  fails with the vocabulary-field-unrendered refusal for a probed entry (`tests/unit/image.nix`).
- [x] 3.3 Add `renderProbe` to `image/read.nix`: `Type=oneshot`, `After=` and `Requires=` the probed
  unit's own file, `ExecStart=` the probe, `TimeoutStartSec=` the bound, the probed unit's `User=`
  where it declared one, the entry's host-path binds, no directory of any kind and no install
  section. Verify the rendered text in `tests/unit/image.nix`.
- [x] 3.4 Render it from `renderedUnitsBy` rather than from either realiser's wrapper, so the two
  realisers produce one text (design D5). Verify in `tests/unit/flakelet.nix` that the flakelet and
  image renderings of one probed entry's probe unit are equal and that neither carries `[Install]`.
- [x] 3.5 Add the probe file to `attachment.units` in `image/read.nix` from the same helper
  `unitFilesOf` uses, so the attach script's `systemctl start` starts it. Verify the attachment
  record in `tests/unit/image.nix`.
- [x] 3.6 Add the four accounts of design D7 to `image/read.nix`'s `accounts` table and the refusals
  that carry them, for a hand-written plan recording a probe with no bound, a bound with no probe, a
  zero bound, or two probes in one entry. Verify with `nix build .#checks.x86_64-linux.planner-tests`:
  `tests/unit/diagnostics.nix` fails an account naming a row nobody produces, so this task is only
  green after 2.3 and 2.5.
- [x] 3.7 Confirm `flakelet/read.nix` needs no edit: its `acceptsUnit` accepts the derived name, its
  `renderUnit`/`renderTimer` wrappers are not in the probe's path, and its `accounts` table gains
  nothing. If an edit turns out to be needed, it is a line of `flakelet/read.nix` and never a second
  rendering of the probe.

## 4. The unit-file namespace

- [x] 4.1 Add `operator-entry-probe-unit-file-taken` to `operator/read.nix`, an error naming the
  entry, the declared unit and the file, for an entry whose own declared unit spells its derived
  probe file. Verify in `tests/unit/operator.nix` that the row fires for a unit named `health` on a
  probed entry, that renaming either removes it, and that two entries on one machine deriving one
  probe file still earn `operator-entry-unit-file-collision`.

## 5. Documentation of the rows and the field

- [x] 5.1 Add every new identifier to the table in `docs/diagnostics.md`:
  `unit-probe-without-timeout`, `unit-probe-timeout-without-probe`, `unit-probe-timeout-unbounded`,
  `unit-probe-on-one-shot`, `unit-probe-on-scheduled`, `unit-probe-declared-twice` and
  `operator-entry-probe-unit-file-taken`. Verify with `nix build .#checks.x86_64-linux.planner-tests`:
  `tests/unit/diagnostics.nix` cross-walks that document against the rows the tree writes in both
  directions, so a missing entry and a stale one both fail.
- [x] 5.2 Add `probe` and `probeTimeout` to the unit vocabulary table in `docs/authoring.md`, beside
  `restart`/`restartSec`, and one paragraph on what a probe is for, that an entry carries one, and
  what each realiser does with it. Verify by reading the rendered table: the two fields sit in the
  same table as the fields they pair with.

## 6. Unit tests, one layer each

- [x] 6.1 `tests/unit/units.nix` (nix-unit): `A unit that says how it is probed`, `A probe whose
  value is not a command`, `A probe with no bound`, `A bound with no probe`, `A bound that spells no
  bound`, `A one-shot unit asking to be probed`, `A scheduled unit asking to be probed`, `Two units
  of one entry declaring a probe`, `A probed unit that is also restarted on failure`, `A probe
  interval is not a vocabulary field`, `A probe carrying a line break`.
- [x] 6.2 `tests/unit/plan.nix` (nix-unit): `An entry that declares no probe keeps its key`, `The
  plan says how to probe and never whether it is healthy`, `A probe adds no unit to the plan`.
- [x] 6.3 `tests/unit/closure.nix` (nix-unit): `A probe naming an undeclared store path`.
  `tests/unit/vars.nix` (nix-unit): `A probe naming a value the machine does not receive`.
- [x] 6.4 `tests/unit/flakelet.nix` (nix-unit): `A probed entry carries one more unit file`, `The
  derived probe unit is ordered against the unit it probes`, `The derived probe unit takes the probed
  unit's account`, `The derived probe unit carries no install section`, `The derived probe unit
  claims no directory`, `The derived name is one the endpoint accepts`, `A changed probe moves the
  artifact's identity`, `A probe is published among the artifact's unit files`, `The probe unit is
  the one file both realisers render alike`.
- [x] 6.5 `tests/unit/image.nix` (nix-unit): `An image of a probed entry carries the probe unit`, `A
  probe field the directive table does not name`, `An image's probe is shown what the entry is
  shown`, `A changed probe is a different image`, `The probe is attached and started with the entry's
  units`.
- [x] 6.6 `tests/unit/operator.nix` (nix-unit): `A declared unit spelling the derived probe file`.
- [x] 6.7 Verify the whole set with `nix build .#checks.x86_64-linux.planner-tests` and
  `nix eval --json '.#debug.failures'` returning `[]`. Every heading above is implementable in
  exactly one layer, which is what `tests/unit/coverage.nix` cross-walks: a name present in both the
  pytest and the nix-unit layer is a failure, not a bonus.

## 7. The end-to-end proof

- [x] 7.1 Add a third deployment build to `tests/e2e/wired-pair/deployment/default.nix` whose served
  unit declares a probe that fails, keeping every host path derived from the entry's own identity -
  `tests/unit/layers.nix` scans a folder's deployment for a written host path. Verify with
  `nix build .#packages.x86_64-linux.planner-e2e-wired-pair-<name>`.
- [x] 7.2 Add the pytest phases to `tests/e2e/wired-pair/test_wired_pair.py`, **last in file order**
  (design D9: a rolled-back activation records a hold keyed on the artifact, and the folder's phases
  are session-scoped, order-dependent and never restored between them): `A failing probe leaves the
  previous generation running`, `A failing probe is a failed apply`, `A passing probe activates the
  new generation`. Verify with `nix run .#planner-e2e wired-pair`.
- [x] 7.3 Add the image half to `tests/e2e/portable-image/`, also last in file order: a build whose
  probe fails, and the pytest phase `A failing probe fails the attach and changes nothing else`,
  asserting that the step fails, that the command names the entry, the machine and what the machine
  printed, and that the image the machine holds is still attached. Verify with
  `nix run .#planner-e2e portable-image`.
- [x] 7.4 Leave `tests/e2e/shared-postgres/` alone. Its killed-main-process phase is the nearest
  existing shape and it proves the service manager's `restart`, which is the other half of the pair
  and already asserted; a probe added there would re-prove nothing and would re-key that folder's
  snapshot cut.

## 8. Verification and closing

- [x] 8.1 `fixtures/minimal-typed-edge` is **not** touched: no declaration of it gains a probe, so
  `fixtures/minimal-typed-edge/plan/backup.json` is not regenerated and
  `fixtures/minimal-typed-edge/plan/diagnostics.txt` is unchanged. If a later decision does add a
  probe to that fixture, regenerate with `nix eval --json .#debug.worked.plan | jq -S .` and say so
  in the commit.
- [x] 8.2 Run `nix build .#checks.x86_64-linux.planner-perf`. The gate is two-sided with a 0.15
  margin and it fails a refactor that costs evaluation; compare against the 1.1 baseline and fix a
  regression at its site (design D8) rather than re-recording a budget.
- [x] 8.3 Run `nix eval --json '.#debug.failures'` and require `[]`, then
  `nix build .#checks.x86_64-linux.planner-tests` and `nix build .#checks.x86_64-linux.treefmt`.
- [x] 8.4 In **one** edit, now that every heading of task groups 6 and 7 has its test: delete this
  change's three `excused` entries from `tests/unit/coverage.nix`, add the same three paths to
  `accountable`, and tick every checkbox of this file. The three steps are one edit because the
  excuse is stale the moment a box is ticked (`changeHasLanded`, `tests/unit/coverage.nix:380-385`)
  and `accountable` is unsatisfiable until the tests exist, so any other order puts the suite red in
  between. Verify with `nix build .#checks.x86_64-linux.planner-tests`: no unclassified spec, no
  stale excuse, and the heading cross-walk satisfied in both directions. The registration points
  this change touches are exactly
  `accountable`/`excused` in `tests/unit/coverage.nix` and nothing else: no new suite, so `suites` in
  `tests/default.nix` is untouched; no new top-level path, so `classOf` in `tests/unit/layers.nix`
  is untouched; no new python directory, so `programs.mypy.directories` in `treefmt.nix` and `src`
  in `ruff.toml` are untouched; no new directory kind, so `directoryKinds` in `lib/module.nix` is
  untouched; no new excluded construct, so `lib/excluded.nix` is untouched - a probe interval and a
  failure threshold are `implementation-unknown-key` rather than exclusions, because the vocabulary
  already refuses the three restart policies that need a `Type=` the same way; and the `README.md`
  literals are unchanged.
- [x] 8.5 Add this change's invariants to `CLAUDE.md`: under **Realisers**, that the probe is one
  derived `<name>-health.service` per entry because that is the only file flakelet's activation
  starts, that it carries no `[Install]` and is therefore rendered by the shared reading and by
  neither wrapper, that it inherits the probed unit's account and declares no directory because a
  runtime directory is deleted when the declaring unit exits, and that the image realiser carries and
  starts it and rolls nothing back; under **Keys and identity**, that a probe and its bound are unit
  fields and therefore in the entry's key, so a changed probe is a new generation and a new image;
  under **The operator's command**, that a value that moved does not re-run a probe because
  `try-restart` skips a completed oneshot. Name the registration point of 8.4 in the same edit.
  Verify with `nix build .#checks.x86_64-linux.treefmt`, which lints `CLAUDE.md`.
