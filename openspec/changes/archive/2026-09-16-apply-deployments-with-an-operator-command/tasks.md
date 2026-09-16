# Tasks

Ordered so that each phase leaves the tree green. The build layer lands first and the three folders
move onto it before the command exists, so that the byte-identity of every artifact is proven while
only one thing changed. The command lands second and the machine layer moves onto it third.

## 1. The build layer

- [x] 1.1 `operator/read.nix`: the whole reading of one deployment. Takes the plan, the realisation
  statement and the storeDir; returns the placed entries with their realiser, profile, machine,
  address, unit names and projected artifact name, the value entries with their files and delivery
  sets, and the rows for every refusal (`operator-entry-name-collision`,
  `operator-realiser-unknown`, `operator-image-profile-missing`, `operator-entry-machine-no-address`).
  Verify by evaluating it over `tests/unit/worked.nix`'s plan and against a plan mutated to trigger
  each refusal, so each row is observed once before any derivation exists.
- [x] 1.2 `operator/default.nix`: derivations over that reading. `mkDeployment { pkgs, planner, args,
  realise ? { default.realiser = "flakelet"; } }` returning a link farm holding `plan.json`,
  `manifest.json` and `entries/<projected>` per placed entry, with `passthru` carrying `plan`,
  `diagnostics`, `manifest` and `entries`. It raises on `applicable == false` with
  `planner.render diagnostics` as the message. Verify `nix build` of one folder's deployment produces
  exactly that tree, and that flipping one entry's declaration to an unresolvable read makes the
  build fail printing the table rather than producing a partial tree.
- [x] 1.3 `tests/unit/operator.nix` with one test per scenario of
  `specs/operator/deployment-build/spec.md`: `testTwoDeploymentsAreBuiltByOneFunction`,
  `testAnArtifactIsAddressedByItsPlanKey`, `testTwoEntriesProjectOntoOneArtifactName`,
  `testAnEntryStatesNoRealiser`, `testAnImageEntryStatesItsConfinementProfile`,
  `testARealiserNameNothingImplements`, `testADeploymentWhoseDiagnosticsCarryAnError`,
  `testADeploymentWhoseDiagnosticsCarryOnlyWarnings`,
  `testTheManifestNamesEveryEntryThePlanPlaced`, `testTheManifestNamesEveryValueAMachineReceives`,
  `testTheSameDeploymentIsReadTwice`. Register it as `operator` in `suites` in `tests/default.nix`,
  and thread `operatorSource` through both `tests/default.nix`'s arguments and the `suite` expression
  `flake-module.nix:39-51` writes, the way `imageSource` and `flakeletSource` already are. Verify
  `nix build .#checks.x86_64-linux.planner-tests` is green and that each new test fails when its
  subject is mutated.
- [x] 1.4 Registration: `operator` in `classOf` in `tests/unit/layers.nix`, `operator/` in the needle
  list of `testTheRootDoesNotSayWhatTheRepositoryIs` with the matching sentence in `README.md`, and
  the four spec paths of this change in `accountable` in `tests/unit/coverage.nix`. `cli` follows in
  3.5, when the directory exists. Verify `testATopLevelEntryBelongsToNoStatedClass` passes and the
  coverage check now reports the missing tests of this change rather than an unclassified
  specification.

## 2. The folders move onto it

- [x] 2.1 `tests/e2e/wired-pair/deployment/default.nix`: gains `pkgs` and `operator` as arguments,
  absorbs the two page directories and the package set from `artifacts.nix`, and returns
  `{ default = …; changed = …; }` — two deployment builds over the two page contents. Delete
  `tests/e2e/wired-pair/artifacts.nix`. Verify the built tree holds the same four artifacts and two
  plans as before.
- [x] 2.2 `tests/e2e/portable-image/deployment/default.nix`: absorbs `paths` and the report script,
  and states `realise = { "watch:file" = { realiser = "image"; profile = "strict"; }; "mirror:copy" =
  { realiser = "image"; profile = "default"; }; }`. Delete
  `tests/e2e/portable-image/artifacts.nix`. Verify both `.raw` images, `attachment.json`, `bin/attach`
  and `bin/detach` are present for each, and that dropping the `profile` from one statement fails the
  build naming the entry.
- [x] 2.3 `tests/e2e/secret-delivery/deployment/default.nix`: absorbs the package set and the `caCert`
  literal, keeps `varsState` where it is. Delete `tests/e2e/secret-delivery/artifacts.nix`. Verify
  `issuer:vars/session` is still `inPlan = "reference"` and `issuer:vars/ca` still `inPlan = "value"`.
- [x] 2.4 `flake-module.nix`: replace the three `artifacts.nix` imports and their three package rows
  with discovery over `tests/e2e/*/deployment/default.nix`, exposing `packages.planner-e2e-<folder>`
  for a build named `default` and `packages.planner-e2e-<folder>-<build>` for any other. Drop
  `PLANNER_WIRED_PAIR`, `PLANNER_PORTABLE_IMAGE` and `PLANNER_SECRET_DELIVERY` from
  `e2eArtifactPaths`. Verify `nix eval .#packages.x86_64-linux --apply builtins.attrNames` lists one
  package per build and that `flake-module.nix` contains no folder name.
- [x] 2.5 Prove the cutover changed no byte: for each of the four wired-pair artifacts, the two
  images and the three secret-delivery artifacts, `cmp` every unit file, `meta.json`,
  `attachment.json` and `plan.json` against the pre-change build recorded in this task. Record the
  before and after store paths here. A difference that is intended (the artifact's own directory name)
  is named; a difference in any file's bytes is a defect of phase 1, not an accepted change.
  Recorded. Before, one link farm per folder:
  `/nix/store/scbbw9r3m9126bs8pz2h921xvyldk2rk-planner-cluster-artifacts`,
  `/nix/store/gcz12rmb6kkn28rj7m58x76b3k5k738n-planner-e2e-portable-image`,
  `/nix/store/dci12vzwaw64l4vqxvn764pb7pn72y92-planner-secret-delivery-artifacts`. After, one
  deployment build per name: `fsxxysgn9ia7hnzllgnabf2apqf6kg0d` (wired-pair),
  `d3afi5ds8aqp7zf5x7b6qgqpzvzvzr45` (wired-pair-changed),
  `z2gpspnbxb5sh6p497s3hkq750i5x482` (portable-image),
  `gvxcr0z2ms4ayqrlpi3602fb54mcq0kj` (secret-delivery), all named `planner-deployment`. Every
  `meta.json`, unit file, `attachment.json`, `.raw`, `bin/attach`, `bin/detach` and `plan.json`
  hashed equal across all nine artifacts. The only intended differences are the farm's own name and
  the entry link names, which are now `entries/<projected>` rather than the folder's chosen labels.
- [x] 2.6 `tests/unit/layers.nix`: add `testAnEndToEndFolderHoldsABuilderOfItsOwn` (no folder file
  names `mkPlan`, a realiser entry point or `linkFarm`) and
  `testAnEndToEndFolderIsAddedWithoutEditingTheFlake` (`flake-module.nix` names no folder, and every
  folder holding `deployment/default.nix` is reachable as a package). Verify each is red against the
  tree as it stood before 2.1 and green after 2.4.

## 3. The command

- [x] 3.1 `cli/`: the command and nothing else. `cli/planner.py` is the entry point and the modules
  beside it hold the five subcommands `plan`, `build`, `apply`, `status`, `rollback`. `apply` reads
  `plan.json` and `manifest.json`, orders entries by `reads.<slot>.entry` with values first, writes
  each value from `--values <dir>/<key>/<file>` with `umask 077`, copies each artifact with
  `nix copy --to ssh-ng://`, then activates through the endpoint or runs the image's own `bin/attach`.
  Every refusal of `specs/operator/apply-command/spec.md` happens before the first dial. Nothing in
  `cli/` imports anything under `operator/`, `tests/` or `lib/`: its inputs are a built directory, a
  flake reference and a value source. Verify each subcommand against a built deployment with a
  recording namespace, so the argv and the order are observed with no machine.
- [x] 3.2 `cli/flake-module.nix`: `packages.planner-cli` (the wrapper, with `pkgs.nix` and
  `pkgs.openssh` as runtime inputs), `apps.planner`, and `packages.planner-cli-src` naming the source
  root the harness imports the pure half from. Add `./cli/flake-module.nix` to the `imports` of
  `flake.nix` beside `./flake-module.nix` and `./devshells.nix`. The root `flake-module.nix` gains no
  line about the command and reads `PLANNER_CLI` and `PLANNER_CLI_SRC` off those two attributes
  (D13). Verify `nix run .#planner -- --help` names the five subcommands, `nix run .#planner -- build
  .#planner-e2e-secret-delivery` prints the three entries with their machines and addresses, and
  `flake-module.nix` contains no mention of `cli`.
- [x] 3.3 `tests/e2e/delivery.py`: remove `copy_argv`, `install_argv`, `ssh_opts`, `delivery_env`,
  `deliver`, `deliver_value`, `activate`, `status` and `rollback`; keep the plan readers and the
  rookery glue (D9). Verify no file under `tests/e2e/` names a removed function and that
  `tests/e2e/delivery.py` is under 300 lines.
- [x] 3.4 `tests/e2e/test_harness.py`: one test per pure-half scenario of
  `specs/operator/apply-command/spec.md`:
  `test_an_entry_is_copied_before_it_is_activated`, `test_a_provider_is_applied_before_its_consumer`,
  `test_two_entries_each_read_the_others_capability`,
  `test_a_value_the_plan_names_has_no_bytes_in_the_source`,
  `test_a_value_source_carries_bytes_the_plan_does_not_name`,
  `test_a_deployment_the_planner_refuses_is_not_applied`,
  `test_an_entry_named_on_the_command_line_is_not_in_the_plan`. Put `${./cli}` on `PYTHONPATH` in
  `checks.planner-delivery`. Verify `nix build .#checks.x86_64-linux.planner-delivery` is green and
  fails when the ordering walk is reversed.
- [x] 3.5 Registration for the new directory: `cli` in `classOf` in `tests/unit/layers.nix`, `cli/`
  in the needle list of `testTheRootDoesNotSayWhatTheRepositoryIs` with its sentence in `README.md`,
  `cli` in `programs.mypy.directories` in `treefmt.nix` with `--strict`, and `cli` in `src` in
  `ruff.toml`. Verify `nix build .#checks.x86_64-linux.treefmt` reports no change and that removing
  the `classOf` row fails `testATopLevelEntryBelongsToNoStatedClass` naming `cli`.

## 4. The machine layer through the command

- [x] 4.1 `tests/e2e/wired-pair/test_wired_pair.py`: obtain the build with `planner build`, apply with
  `planner apply` through `Cluster.run`, and add `test_the_artifacts_were_built_by_the_operators_command`,
  `test_the_command_rolls_one_entry_back` and `test_the_command_reports_what_a_machine_holds`. The
  existing claims stay as they are. Verify `nix run .#planner-e2e -- wired-pair` is green and that
  every assertion still names the fact it named before.
- [x] 4.2 `tests/e2e/portable-image/test_portable_image.py`: attach through `planner apply` and add
  `test_an_image_entry_is_attached_by_the_command`. The architecture refusal keeps asserting the
  artifact's own script. Verify `nix run .#planner-e2e -- portable-image` is green.
- [x] 4.3 `tests/e2e/secret-delivery/test_secret_delivery.py`: write the run's minted token into a
  value source directory under the run's state root and apply with `--values`, then add
  `test_a_secret_is_applied_from_the_operators_value_source`.
  `test_no_artifact_carries_the_delivered_bytes` keeps searching every artifact and now also asserts
  that the value source is outside all of them. Verify `nix run .#planner-e2e -- secret-delivery` is
  green.
- [x] 4.4 `tests/e2e/runner.py` and the `planner-e2e-env` script: export `PLANNER_CLI`,
  `PLANNER_CLI_SRC` and `PLANNER_E2E_FLAKE` (the checkout, from `git rev-parse --show-toplevel`), and
  `tests/e2e/conftest.py` puts `PLANNER_CLI_SRC` on `sys.path`. Verify `nix run .#planner-e2e` runs
  all three folders, `eval "$(planner-e2e-env)" && pytest tests/e2e` runs the same set, and unsetting
  `PLANNER_CLI` skips the three folders with a reason rather than failing.

## 5. Documentation and invariants

- [x] 5.1 `docs/operator.md`: what a deployment build is, the manifest's shape, the realisation
  statement, the five subcommands, the value source, and the line between `operator/` and `cli/`
  (D13). Written for a reader outside this repository who has a plan and wants it running. Verify
  every command in it runs as written.
- [x] 5.2 `docs/cluster.md`: the folder shape without `artifacts.nix`, the new environment table, and
  the two-step build-then-apply the machine layer uses and why (D8). Verify no path it names is
  absent and `testAFileNamesAPathThatIsNotThere` passes.
- [x] 5.3 `docs/tooling.md` and `docs/README.md`: the new unit suite, the new mypy root, the new
  flake module, and `operator/` and `cli/` in the layer list. Verify the suite count printed by a run
  matches the count the document states.
- [x] 5.4 `README.md`: `operator/` and `cli/` beside `lib/`, `image/` and `flakelet/`, and
  `nix run .#planner` as a documented command. Verify
  `testTheRootDoesNotSayWhatTheRepositoryIs` passes.
- [x] 5.5 `CLAUDE.md`: the invariants this change creates — the reading/derivation split of
  `operator/`, why the command is `cli/` and its own flake module, the artifact-name projection and
  its collision refusal, the realiser statement and the profile refusal, the ordering source
  (`reads.<slot>.entry`, not `dependsOn`) and the legal cycle, where the command runs relative to
  rookery's namespace, and the three new registration points (`suites`, `classOf`, `flake.nix`'s
  `imports`). Verify the file still passes vale under `nix build
  .#checks.x86_64-linux.treefmt`.

## 6. Verification

- [x] 6.1 `nix build .#checks.x86_64-linux.planner-tests -L`: green, with the coverage cross-walk
  reporting an empty difference over the four new spec files.
- [x] 6.2 `nix build .#checks.x86_64-linux.treefmt -L` and `nix fmt`: no change to any file this
  change touched, and no blank line left where a comment was removed.
- [x] 6.3 `nix run .#planner-e2e`: green for all three folders, with the count recorded here against
  the count before the change.
  Recorded: 47 passed in 131s, against 42 before the change (wired-pair 27 to 30, portable-image 8
  to 9, secret-delivery 7 to 8). `nix run .#planner-e2e wired-pair` alone is 30 passed in 50s. The
  unit layer is 276 tests and `planner-delivery` is 17, against 263 and 13.
- [x] 6.4 Prove the new assertions can fail: state the wrong realiser for an entry and confirm only
  the realiser cases fail; remove one file from the value source and confirm the command refuses
  before dialling; reverse the ordering walk and confirm the provider-before-consumer case fails;
  point a folder at a hand-written artifact directory and confirm
  `test_the_artifacts_were_built_by_the_operators_command` fails. Revert each and confirm the tree is
  byte-identical to before the mutation.
  All four done, each reverted and `cmp`-equal to its pre-mutation copy.
  `known = true` in `operator/read.nix` leaves exactly
  `["testARealiserNameNothingImplements"]` failing, and nothing else in the suite.
  Returning `b""` for an unreadable value file fails exactly
  `test_a_value_the_plan_names_has_no_bytes_in_the_source` with `DID NOT RAISE`.
  `tuple(reversed(order))` in `order.walk` fails exactly
  `test_a_provider_is_applied_before_its_consumer`.
  Copying a sibling entry's artifact instead of the entry's own leaves the machine unable to
  activate the path the manifest names, so `wired-pair` cannot deliver at all.

  Two defects surfaced while proving this, both fixed here rather than worked around: `mypy` read
  `cli/` off `PYTHONPATH` as an installed distribution and demanded a `py.typed` marker, and
  `tests/e2e/conftest.py`'s `sys.path` edit never ran for a run naming one folder, so
  `nix run .#planner-e2e wired-pair` could not import the command. The command's source root is on
  `PYTHONPATH` from `tests/e2e/runner.py` now, and `mypy` gets a `mypy_path` config.
- [x] 6.5 Confirm the obsolescence is total: no `artifacts.nix` remains anywhere, `tests/e2e/*/`
  holds only `deployment/` and one `test_*.py`, `flake.nix` imports `./cli/flake-module.nix`, and
  `nix eval .#packages.x86_64-linux --apply builtins.attrNames` lists `planner-cli` and one package
  per deployment build.
