## 1. Cross-walk bookkeeping, before anything else

- [x] 1.1 Add this change's three delta specs to `excused` in `tests/unit/coverage.nix` with the
  reason already used for an unstarted change ("an unimplemented change: no task of
  clean-up-transplant-residue has been done"): `clean-up-transplant-residue/specs/tooling/`
  `{repository-shape,nix-unit-suite,evaluation-performance}/spec.md`. Verify
  `nix build .#checks.x86_64-linux.planner-tests -L` is green again and reports 237 successful
  tests, so the tree is not left red while the rest of the work happens.

## 2. The reference check

- [x] 2.1 In `tests/unit/layers.nix`, lift the scanner out of the end-to-end scope: parameterise
  `namedPathsOf` over a root and a set of files instead of `e2eRoot + "/${folder}"`, keeping
  `pathTokens`, `dirnameOf` and the `unresolved` failure shape unchanged. Verify the existing
  `testAReaderOpensAnEndToEndDirectory` and `testAnEndToEndTestReadsAFileOfAnotherEndToEndTest`
  still pass with no change to their expected values.
- [x] 2.2 Add repo-relative token recognition per design D1: strip a trailing `:N`, `:N-M` or
  `:N,M`, accept a token whose first segment is an existing top-level entry, resolve it against the
  repository root. Verify with a throwaway `nix eval` over the helper that
  `lib/resolve.nix:377`, `tests/e2e/wired-pair/deployment` and
  `fixtures/minimal-typed-edge/plan/backup.json` resolve while `/run/vars/hostKey/x`,
  `ssh://borg@vault.example:22/srv`, `manager.rs:1349-1392` and `pkgs/planner/lib` are not treated
  as tokens of this repository.
- [x] 2.3 Add `testAFileNamesAPathThatIsNotThere` over the scanned set of design D2 (`lib`, `image`,
  `flakelet`, `perf`, `tests`, `fixtures`, `docs`, root `*.nix`), failing with `file: line: token`.
  Verify it currently fails naming the fifteen fixture citations, and record that list in this task
  as the work list for 2.5.

  It names 44, not fifteen. The fifteen are there; the other 29 are the same residue in files the
  design counted by hand only under `{interfaces,modules,plan}`, plus a class the design did not
  separate: a citation into another repository whose first segment collides with a top-level entry
  of this one (`lib/exports/…` and `lib/inventory/…` are clan-core, `lib/systems/default.nix` is
  nixpkgs, `lib/systemd/portable/profile/` is a machine's filesystem, `lib/python3` is a store
  path's interior). Design D3 governs those: repaired by naming the repository the file belongs to,
  not tolerated by an allow-list.

  ```
  docs/README.md: 51: ./lib
  docs/authoring.md: 458: ./client.nix
  docs/flakelet.md: 86: lib/artifact.nix
  fixtures/minimal-typed-edge/README.md: 12: ../binary-caches/
  fixtures/minimal-typed-edge/README.md: 12: ../instance-as-group/
  fixtures/minimal-typed-edge/README.md: 12: ../secrets-per-instance/
  fixtures/minimal-typed-edge/README.md: 13: ../one-daemon-two-networks/
  fixtures/minimal-typed-edge/README.md: 26: ../instance-as-group/modules/mygame/package.nix
  fixtures/minimal-typed-edge/README.md: 27: ./default.nix
  fixtures/minimal-typed-edge/README.md: 47: lib/inventory/distributed-service/all-services-wrapper.nix
  fixtures/minimal-typed-edge/README.md: 51: lib/inventory/distributed-service/service-module.nix
  fixtures/minimal-typed-edge/README.md: 67: lib/exports/exports.nix
  fixtures/minimal-typed-edge/README.md: 68: lib/exports/test_integration.nix
  fixtures/minimal-typed-edge/README.md: 127: ../one-daemon-two-networks/plan/zerotier.json
  fixtures/minimal-typed-edge/README.md: 201: ../firewall/
  fixtures/minimal-typed-edge/README.md: 201: ../quiesce-group/
  fixtures/minimal-typed-edge/README.md: 205: ../firewall/README.md
  fixtures/minimal-typed-edge/deployment/instances.nix: 25: lib/exports/exports.nix
  fixtures/minimal-typed-edge/interfaces/default.nix: 12: ../../binary-caches/README.md
  fixtures/minimal-typed-edge/interfaces/default.nix: 25: ../../secrets-per-instance/interfaces/default.nix
  fixtures/minimal-typed-edge/interfaces/default.nix: 56: ../../firewall/README.md
  fixtures/minimal-typed-edge/interfaces/exports.nix: 36: ../../instance-as-group/interfaces/exports.nix
  fixtures/minimal-typed-edge/interfaces/exports.nix: 79: ../../secrets-per-instance/interfaces/exports.nix
  fixtures/minimal-typed-edge/modules/borg-push/client.nix: 67: ../../../one-daemon-two-networks/plan/zerotier.json
  fixtures/minimal-typed-edge/modules/borg-push/client.nix: 96: ../../../secrets-per-instance/plan/secrets.json
  fixtures/minimal-typed-edge/modules/borg-repo/server.nix: 43: lib/inventory/distributed-service/service-module.nix
  fixtures/minimal-typed-edge/plan/README.md: 40: ../../one-daemon-two-networks/plan/zerotier.json
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 68: lib/exports/exports.nix
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 70: lib/exports/test_integration.nix
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 80: lib/inventory/distributed-service/service-module.nix
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 86: lib/inventory/distributed-service/all-services-wrapper.nix
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 134: ../../secrets-per-instance/interfaces/exports.nix
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 170: ../../binary-caches/
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 194: ../../firewall/README.md
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 198: ../../firewall/
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 199: ../../quiesce-group/
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 209: ../../secrets-per-instance/interfaces/exports.nix
  fixtures/minimal-typed-edge/plan/diagnostics.txt: 216: ../../secrets-per-instance/README.md
  image/read.nix: 43: lib/systemd/portable/profile/
  lib/platform.nix: 101: lib/systems/default.nix
  tests/e2e/runner.py: 209: lib/python3
  tests/e2e/runner.py: 211: lib/python3
  tests/unit/image.nix: 7: tests/python/test_image.py
  tests/unit/perf.nix: 7: tests/mapping.nix
  ```
- [x] 2.4 Add `testARecordIsReadAsHistory` asserting `openspec/` is outside the scanned set and
  stating why in the test's own comment. Verify it passes and that removing `openspec/` from the
  exemption makes it fail, so the exemption is asserted rather than implied.
- [x] 2.5 Repair the fifteen citations in `fixtures/minimal-typed-edge/` (6 to
  `../../secrets-per-instance/`, 3 to `../../firewall/`, 2 to `../../binary-caches/`, 2 to
  `../../one-daemon-two-networks/`, 1 to `../../instance-as-group/`, 1 to `../../quiesce-group/`)
  by stating the fact each cited or deleting the clause, comments and prose only. Verify
  `testAFileNamesAPathThatIsNotThere` passes, `git diff --stat fixtures/` shows no change to
  `plan/backup.json`, and `planner-tests` still reports the golden plan test and the
  exclusion-table row count as passing.

  `plan/diagnostics.txt` does change: it holds eleven of the citations and is a hand-written
  document rather than a generated one (`nix eval --raw .#planner.rendered` is eight lines against
  its 262), so the byte-identity this task originally asked of it was a claim about the wrong
  file. Every one of the eleven is under an `x` counterfactual row; the `  ! ` rows
  `tests/unit/plan.nix` parses are untouched and 242/242 tests pass. `plan/backup.json` is
  byte-identical, checked against `nix eval --json .#planner.worked.plan | jq -S .`.
- [x] 2.6 Repair the same class of reference in `docs/` and `tests/` if 2.3 names any. Verify the
  check passes over the whole scanned set and that `nix build .#checks.x86_64-linux.planner-tests`
  is green.

## 3. The corpus file

- [x] 3.1 Rewrite the two `trigger` sentences in `lib/excluded.nix:26,58` to state the fact they
  currently delegate to `notes/unaddressed.md` (design D5). Verify `planner-tests` passes, in
  particular `tests/unit/exclusions.nix`, whose rows read those constructs.
- [x] 3.2 Rewrite the `externals` row of `docs/diagnostics.md:161` the same way. Verify no file
  outside `openspec/` names `notes/` any more: `rg -n 'notes/' lib tests docs perf image flakelet
  fixtures *.nix` is empty.
- [x] 3.3 Delete `notes/` and drop its `treefmt.nix` exclusion. Verify
  `nix build .#checks.x86_64-linux.treefmt` and `.#checks.x86_64-linux.planner-tests` are both
  green.

## 4. The measurement's inputs

- [x] 4.1 Add a `worked` argument to `perf/eval.nix` (default `./../tests/unit/worked.nix`) and a
  `--worked` flag to `perf/measure.sh`, refusing with the path when it names no file, as
  `--lib`/`--folder` already do. Verify a working-tree run still works:
  `nix run .#planner-perf -- --fixtures worked --sizes 4 --repeats 1`.
- [x] 4.2 Replace `plannerSrc = ./.` in `flake-module.nix:58` with the four explicit inputs
  (`${./lib}`, `${./perf}`, `${./fixtures/minimal-typed-edge}`, `${./tests/unit/worked.nix}`) for
  both `measurement` and the `planner-perf` application. Verify
  `nix build .#checks.x86_64-linux.planner-perf -L` reports `0 failures, 0 invalid comparisons`
  and that the `worked`, `fleet` and `mesh` fixtures are all measured.

  The fourth input costs what one more attribute in the applied argument set costs, and the
  budgets had no headroom: `sets.bytes` +16 bytes and `envs.bytes` +8 bytes per evaluation, on
  every one of the nine fixtures, plus `gc.totalBytes` on `worked` and `fleet-4`. That is a
  deliberate harness change that moves counters, so `perf/budgets.json` is re-recorded from
  `planner-perf-results` by the procedure in `docs/tooling.md` - only the counters that moved, at
  the file's own ceiling-to-four-decimals rounding. `worked` also gains headroom the change earns:
  `nrFunctionCalls` 474.375 → 473.875 and `values.number` 1059.875 → 1059.75. The gate then
  reports `0 failures, 0 invalid comparisons` over worked, fleet-{4,16,64,256} and
  mesh-{4,16,64,256}.
- [x] 4.3 Record the evidence in this task: `nix eval --raw
  .#packages.x86_64-linux.planner-perf-results.drvPath`, then append a blank line to
  `docs/plan.md`, `git add` it, evaluate again, and confirm the two paths are equal where they
  previously differed (`0h4hjwz4ay6c7sm6r56ch9wpp2h97zri` → `rnqwyfql8p3ip2g7c5v7p6v1xda2py4b`).
  Restore `docs/plan.md`.

  Both evaluations are
  `/nix/store/7wbnk22zpkh9gg1kdmc0w4rkvsird91n-planner-perf-results.drv`. A documentation edit no
  longer moves the measurement's identity.
- [x] 4.4 Add the omission entry for *A file the measurement does not read is edited* to `omitted`
  in `tests/unit/coverage.nix` with design D7's sentence: the observation is a derivation's input
  set, which the evaluating layer cannot read without reading the flake that runs it. Verify
  `planner-tests` passes and the reason appears in the check's output.

## 5. The tree's own shape

- [x] 5.1 Add `testATopLevelEntryBelongsToNoStatedClass` to `tests/unit/layers.nix` with one row
  per top-level entry and its class (design D8), failing with the entry and the classes that exist.
  Verify it passes on the current tree and fails when a scratch directory is added.

  The nine classes the specification names do not cover four entries this repository has, so the
  table states three more: `.envrc` and `.gitignore` are the checkout's own configuration,
  `LICENSE.md` is the licence, and `.omp` joins `styles/`, `treefmt.nix` and `ruff.toml` under the
  formatter's own configuration. Added `scratch/`, the test names it with the eleven classes.
- [x] 5.2 Write the root `README.md`: what the library is, the tree, the checks, the two shells,
  and a pointer to `docs/README.md` (design D9). Verify `nix build
  .#checks.x86_64-linux.treefmt` is green, so vale and the `Universe` style pass on it.
- [x] 5.3 Add `testTheRootDoesNotSayWhatTheRepositoryIs` asserting the root document exists and
  names the layout and the checks. Verify it fails with `README.md` removed and passes with it.

  With `README.md` removed the test reports `present = false` and lists all fifteen things the
  document has to name; the file is read behind a `pathExists` guard so the absence is a named
  failure rather than an abort of the suite.

## 6. The cross-walk's second direction

- [x] 6.1 Add `testAnExcuseOutlivesItsSpecification` to `tests/unit/coverage.nix`: every key of
  `excused`, and every heading in `omitted` and `aliased`, names something that exists. Verify it
  fails when a fabricated `excused` key is added and passes on the current lists.

  A fabricated key reports
  `excused: no-such-change/specs/tooling/gone/spec.md names no spec.md under openspec/changes`.
- [x] 6.2 Move this change's three delta specs from `excused` to `accountable` and delete the
  temporary excuse from task 1.1. Verify `planner-tests` names no unaccounted scenario and reports
  the six new tests of this change (four in `layers.nix`, one in `coverage.nix`, one omission).

## 7. Verification

- [x] 7.1 Build every check and both artifact packages:
  `nix build .#checks.x86_64-linux.{planner-tests,planner-perf,planner-perf-checker,planner-delivery,treefmt} .#planner-e2e-wired-pair .#planner-e2e-portable-image -L`.
  Record each result here, with the test counts for `planner-tests` and `planner-delivery`.

  | Output | Result |
  | --- | --- |
  | `checks.planner-tests` | 242/242 successful |
  | `checks.planner-perf` | `check.py: 0 failures, 0 invalid comparisons` over nine fixtures |
  | `checks.planner-perf-checker` | ran 13 tests |
  | `checks.planner-delivery` | 8 passed |
  | `checks.treefmt` | green: nixfmt, deadnix, shellcheck, yamlfmt, ruff, mypy and vale |
  | `planner-e2e-wired-pair` | built |
  | `planner-e2e-portable-image` | built |

  237 tests before this change, 242 after: `testAFileNamesAPathThatIsNotThere`,
  `testARecordIsReadAsHistory`, `testATopLevelEntryBelongsToNoStatedClass` and
  `testTheRootDoesNotSayWhatTheRepositoryIs` in `layers.nix`, and
  `testAnExcuseOutlivesItsSpecification` in `coverage.nix`, beside the one omission.
- [x] 7.2 Confirm the fixture's evaluated content is untouched: `nix eval --json
  .#planner.worked.plan | jq -S . | diff - fixtures/minimal-typed-edge/plan/backup.json` is empty.

  Empty.
