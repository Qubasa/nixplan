## 1. Registration while the change is in flight

- [x] 1.1 `git add openspec/changes/normalise-folds-and-report-refused-reads/` so the flake can see the change, and add `normalise-folds-and-report-refused-reads/specs/planner/interface-fold/spec.md` to `excused` in `tests/unit/coverage.nix` with the precedent reason `hold-declaration-shape-and-fold-set-reads` used while in flight ("an unimplemented change: no task of normalise-folds-and-report-refused-reads has been done, so nothing in this package claims to satisfy it yet"); verify `nix eval --json .#planner.suites.coverage.testEverySpecificationIsClassified.expr` reports empty `unclassified`, `vanished` and `unreadable`
- [x] 1.2 Confirm the tree is green before any edit: verify `nix eval --json .#planner.failures` is `{}`

## 2. The guarded half of a refused fold

- [x] 2.1 Add `testAGuardedConsumerStillReportsARefusedFold` to `tests/unit/resolution.nix`, beside `testARefusedFoldLeavesTheSlotAbsent`, using the file's own `folding`/`planOf`/`soleRoot` helpers: one provider placed twice, an interface whose fold returns `{ refused = "<why>"; }`, and two consuming entries that read the slot under `results ? <slot>`; assert one `interface-fold-refused` row per consuming entry with two different subjects, both rows carrying the fold's own message, `reads.<slot>.delivered = false` on both consumers, `applicable = false`, and every provider and machine entry still present in the plan
- [x] 2.2 Add `testTwoConsumersOfOneFoldReceiveOneValue`: two consuming entries reading one interface with `reach = "all"` over the same providers and the same `reads`; assert both received the identical folded value and that each entry's own unit records the different bytes it rendered from it, so the plan holds two outputs of one policy
- [ ] 2.3 Add `testTwoConsumersReadingDifferentExportsFoldDifferentSets`: one interface with two exports and a fold that reports the export names it was given per provider entry; one consumer reads one export, the other reads both; assert each consumer's folded value names only its own declared exports and that the export a consumer did not name is absent rather than null
- [ ] 2.4 Verify the suite is green and the three tests are the only additions: `nix eval --json .#planner.failuresBySuite.resolution` is `{}`

## 3. The scenario the suite cannot assert

- [ ] 3.1 Register `An unguarded consumer of a refused fold ends the evaluation` in `omitted` in `tests/unit/coverage.nix`, with a reason naming the class it shares with `A module's own code raises an uncatchable error` (a missing attribute is what `builtins.tryEval` does not catch, so a test of the propagation would abort this suite rather than fail it) and naming `testAGuardedConsumerStillReportsARefusedFold` as the half that is containable; verify `nix eval --json .#planner.suites.coverage.testEveryScenarioHasATest.expr` lists the title under `excused` and not under `unaccounted`
- [ ] 3.2 Record the measurement that stands in for it, the way `clean-up-transplant-residue` task 4.3 records its one unobservable counter: build a throwaway two-consumer deployment through `nix eval .#lib --apply`, evaluate it three ways - a fold returning `{ refused = ...; }` with an unconditional `results.<slot>` read, the same fold with both consumers guarded, and a raising fold with both consumers guarded - and quote each result in this task; delete the probe afterwards and confirm nothing was written into the tree

## 4. Coverage cross-walk closure

- [ ] 4.1 Move `normalise-folds-and-report-refused-reads/specs/planner/interface-fold/spec.md` from `excused` to `accountable` in `tests/unit/coverage.nix`; verify `nix eval --json .#planner.failuresBySuite.coverage` now names unmapped scenario headings rather than an unclassified file
- [ ] 4.2 Confirm the five scenarios of the modified requirement resolve: `A fold raises`, `A refused fold leaves the slot absent` and `A declared fold is not a function` to the tests that already carry those titles from `hold-declaration-shape-and-fold-set-reads`, `A guarded consumer still reports a refused fold` to task 2.1, and `An unguarded consumer of a refused fold ends the evaluation` to the `omitted` entry from task 3.1; verify none of the five appears in the coverage suite's `unaccounted`
- [ ] 4.3 Confirm the two scenarios of the added requirement resolve to tasks 2.2 and 2.3; verify `nix eval --json .#planner.failuresBySuite.coverage` is `{}`

## 5. Documentation

- [ ] 5.1 Replace the fold example in the interfaces section of `docs/authoring.md` with a normalising fold: validate, refuse by returning `{ refused = "<why>"; }`, and return one record per provider carrying that provider's entry key and its read exports; verify the example's argument shape agrees with `lib/resolve.nix`'s set-reach branch and its constructor fields with `lib/interface.nix`
- [ ] 5.2 Add a row to that section's fact table stating that a fold's output is whatever its consumers can use and that rendering bytes is the consuming implementation's, and replace the sentence after the `reach` section saying a consumer "walks nothing" with the rule it should carry: a second interface is for a different policy, never for a different output format; verify no sentence in the file still implies one fold serves one format
- [ ] 5.3 Extend `When a read is refused` and `Where a refusal lives` in `docs/authoring.md` with the reportability condition: the row, the undelivered read and the inapplicable plan happen either way, an implementation that reads the absent slot unconditionally ends the evaluation of the whole table, and a slot whose interface declares a fold that can refuse is therefore read under `results ? <slot>`; verify the sections still state that an unwired slot's own row precedes any implementation, so guarding is scoped to a refusing fold rather than recommended everywhere
- [ ] 5.4 Add the same condition to the `interface-fold-raised` and `interface-fold-refused` rows in `docs/diagnostics.md`; verify every row id the library can emit still appears exactly once in that file
- [ ] 5.5 Record the invariant in `CLAUDE.md` under "Interfaces, composition, reads": a fold normalises and refuses while rendering stays in the consumer, one interface has one fold for every consumer, and a refusal is rendered only where no implementation forces the absent slot; verify the file still names every registration point it names today
- [ ] 5.6 Confirm no document names a path that is not there: verify `nix eval --json .#planner.failuresBySuite.layers` is `{}`, which includes the scan asserting that every path written in any file, comments included, resolves

## 6. Verification

- [ ] 6.1 Run `nix build .#checks.x86_64-linux.planner-tests -L` as a supervised process and confirm it passes; verify `nix eval --json .#planner.failures` is `{}`
- [ ] 6.2 Confirm no re-measurement is owed, per design D6: run `nix build .#checks.x86_64-linux.planner-perf -L` as a supervised process and verify it passes against the committed `perf/budgets.json` with no figure edited
- [ ] 6.3 Confirm the goldens did not move: `nix eval --json .#planner.worked.plan | jq -S .` still equals `fixtures/minimal-typed-edge/plan/backup.json`, the rendered table still equals `fixtures/minimal-typed-edge/plan/diagnostics.txt`, and `git status --porcelain fixtures` is empty
- [ ] 6.4 Run `nix fmt` and confirm the only changes are formatting of the markdown this change touched, and that `fixtures/**` is untouched
