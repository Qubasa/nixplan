## 1. The rule

- [x] 1.1 Add the rule to `README.md` beside the design goals at `README.md:17-20`: a deployment
  declares intent and never plumbing, a host path is derived by the module that needs it from the
  identity of its own entry or arrives through an export and a wire, no deployment declaration
  carries one, and a test asserting one reads it off the plan. Verify `nix build
  .#checks.x86_64-linux.treefmt` passes, vale included.
- [x] 1.2 Record the same rule in `CLAUDE.md` under a heading of its own, naming the two checks that
  hold it and the two exemptions (a test's own fake root; the unit suites' fixtures).

## 2. The checks

- [x] 2.1 Add the host-path scan to `tests/unit/layers.nix`: over every `.nix` file under
  `tests/e2e/*/deployment/` and `tests/e2e/*/template/deployment/`, collect the string fragments of
  each line, and report `<file>:<line>: <path>` for a fragment beginning with `/` whose first segment
  is one of `etc`, `var`, `run`, `srv`, `opt`, `tmp`, `usr`, `home`, `root`, `nix` and which contains
  no `${`. Add `testADeploymentStatesAHostPath`, and verify it is red against the tree as it stands
  today - seventeen sites, listed in `proposal.md` - and green after task group 3.
- [x] 2.2 Add `testAUrlPathIsNotAHostPath` and `testADerivedPathIsPermitted`, asserting the scan's
  own classification over the two shapes, including `tests/e2e/wired-pair/deployment/default.nix`'s
  `"/index.html"`.
- [x] 2.3 Add the per-folder intersection check and `testATestRestatesAPathItsDeploymentCarries` plus
  `testATestCarriesAPathOfItsOwn`, over the host paths of `deployment/**` and of the folder's
  `test_*.py`. Verify red with a temporary constant restating a deployment path and green without it.
- [x] 2.4 Add `testTheRootDocumentStatesHowAPathReachesAUnit`, reading a literal of the rule out of
  `README.md`, and verify it is red with that sentence deleted.

## 3. The folders

- [x] 3.1 `tests/e2e/wired-pair/`: derive the probe's record path and the sweep's marker path from
  `instance` and `member`, delete `defaults.recordPath` and `defaults.markerPath`, and read both
  paths off the plan in `test_wired_pair.py`. Verify `nix run .#planner-e2e wired-pair`.
- [x] 3.2 `tests/e2e/secret-delivery/`: the same for the probe and the idle job, and delete the
  deployment statement at `deployment/instances.nix:18`. Read `RECORD_PATH` off the plan in
  `test_secret_delivery.py`. Verify `nix run .#planner-e2e secret-delivery`, including the phases that
  rotate a value and reboot a machine.
- [x] 3.3 `tests/e2e/generated-secret/`: the same for its probe and idle job. Verify the two plans the
  folder builds - `deployment/args.nix` against declared state and the generation's own `plan.nix` -
  agree on the derived paths, then `nix run .#planner-e2e generated-secret`.
- [x] 3.4 `tests/e2e/portable-image/`: derive the shown, assembled and quiet paths in
  `deployment/default.nix`'s modules rather than stating them, and read them off the plan's
  `configData` keyset and the entry's recipe in `test_portable_image.py`. Keep the folder's fake root
  `/run/planner-assembly` as the test's own. Verify `nix run .#planner-e2e portable-image`, including
  the assembly cases that run the attach script under that root.
- [x] 3.5 `tests/e2e/newcomer/template/`: derive the greeting path in `modules/hello/greet.nix`,
  delete `defaults.greetingPath`, and update `docs/README.md` so the shown text is byte-equal again.
  Verify `testTheDocumentedExampleIsTheTemplate`-class byte comparisons in `tests/unit/layers.nix`
  are green.
- [x] 3.6 `tests/e2e/newcomer/test_newcomer.py`: read the greeting path out of the plan the
  workstation built, with one more command on the workstation, and delete the `GREETING` constant.
  Verify `nix run .#planner-e2e newcomer` on a host with egress; verify it skips cleanly without.
- [ ] 3.7 Verify the scan is green over the whole layer: `testADeploymentStatesAHostPath` and the
  intersection check both report empty.

## 4. Registration and verification

- [x] 4.1 Move this change's two spec files from `excused` to `accountable` in
  `tests/unit/coverage.nix`, the excuse having expired with the first ticked task, and verify the
  cross-walk finds all six derived test names.
- [ ] 4.2 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green.
- [ ] 4.3 Run `nix run .#planner-e2e` and verify all six folders pass; record which folders were
  cold. No stage key moves in this change, so a cold run means a stage declaration was touched by
  mistake.
- [x] 4.4 Run `nix build .#checks.x86_64-linux.treefmt` and verify formatters, `ruff`, `mypy` and
  `vale` are green.
