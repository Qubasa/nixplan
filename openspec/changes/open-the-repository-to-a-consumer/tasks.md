# Tasks

Ordered so each phase leaves the tree green. The outputs land first, because every later phase is
observed through them. The newcomer folder lands next and is red until the documented example is
buildable, so phase 5 is the phase that turns it green. The shell, the root and the command follow,
each independent of the others.

Each scenario's test belongs to one layer. A fact about evaluation is a nix-unit suite under
`tests/unit/`; a fact that needs a real `nix` invocation, a real ssh or a booted machine is a test
under `tests/e2e/`. The layer is named in the task that writes the test.

## 1. The outputs a consumer builds against

- [x] 1.1 `flake-module.nix`: `flake.operator = import ./operator;` beside `flake.lib`, replacing
  the `perSystem` `let` binding at `flake-module.nix:111` as the source of that value, so the
  folders and a consumer read one binding. `mkDeployment` takes the caller's `pkgs`, so the output
  is system-independent and sits outside `perSystem` (design D1). Verify
  `nix eval .#operator --apply builtins.attrNames` answers `["mkDeployment"]` and every
  `packages.planner-e2e-*` still builds to the store path it built to before.
- [x] 1.2 `flake.nix`: write the system list out as `x86_64-linux`, `aarch64-linux` and
  `aarch64-darwin`, delete the `systems` input and its `flake.lock` entry, and comment the removal
  with the platform the pinned nixpkgs dropped (design D4). Verify `nix flake show` completes and
  prints an output for each of the three, and `nix flake metadata --json` names no `systems` input.
- [x] 1.3 `cli/flake-module.nix`: `apps.default` alongside `apps.planner`, the same program. Verify
  `nix run . -- --help` prints the five subcommands.
- [x] 1.4 `tests/e2e/newcomer/test_newcomer.py`: `test_the_flake_names_its_outputs` and
  `test_a_consumer_reads_the_build_off_an_output`, the machine layer's tests for *The flake names
  its outputs* and *A consumer reads the build off an output*. Both are real `nix` invocations
  against the checkout and neither needs a machine. Verify each fails against the tree as it stood
  before 1.1 to 1.3 - the first inside the nixpkgs release note, the second on a missing attribute.

## 2. One published name, one thing

- [x] 2.1 `flake-module.nix`: rename `flake.planner` to `flake.debug`. This overrules the non-goal
  `clean-up-transplant-residue` recorded, which is argued in design D5. Verify
  `nix build .#planner` builds the command's wrapper and `nix eval --json .#debug.failures` answers
  `[]` on a green tree.
- [x] 2.2 `docs/tooling.md`, `docs/plan.md`, `CLAUDE.md`: every `.#planner.<field>` command line
  becomes `.#debug.<field>`. Verify each command in those documents runs as written, and
  `grep -F '.#planner.'` over the tree finds nothing outside `openspec/`.
- [x] 2.3 `tests/e2e/newcomer/test_newcomer.py`:
  `test_one_published_name_answers_two_different_things`
  and `test_the_test_results_are_reachable_under_a_name_of_their_own`, the machine layer's tests for
  the two scenarios of *A published name means one thing*. The first builds the advertised name and
  asserts a derivation came back; the second reads the suites off the new name and asserts no
  application or package uses it. Verify both fail before 2.1, the first with the `found a set`
  error the finding records.

## 3. The platform elaboration a consumer receives

- [x] 3.1 `lib/default.nix`: the library records the identity of the platform definitions it was
  applied to, as a value beside `platform`. The identity is what the caller passed in, not a name
  this library invents. Verify the exported value equals the revision this flake's lock records for
  its package set.
- [x] 3.2 `flake-module.nix`: `flake.mkLib` taking a caller's own `lib.systems` and returning the
  library elaborated against it, with `flake.lib` staying the applied default (design D2). Verify
  `nix eval .#mkLib` resolves and that a library obtained through it plans the worked fixture.
- [x] 3.3 `tests/unit/consumer.nix`: `testTheLibraryStatesWhoseNixpkgsElaboratedItsPlatforms` and
  `testAConsumerElaboratesAMachineWithItsOwnNixpkgs`, the evaluating layer's tests for the two
  scenarios of *The platform elaboration a consumer receives is a stated choice*. Both are pure
  evaluation and neither names a built output. Register the suite as `consumer` in `suites` in
  `tests/default.nix`. Verify `nix build .#checks.x86_64-linux.planner-tests` is green and that
  removing the recorded identity fails the first test by name.

## 4. The newcomer folder

- [ ] 4.1 `tests/e2e/newcomer/template/`: a `flake.nix` naming the published input and following
  its package set, and a deployment of one service placed on two machines by a tag, whose unit
  writes the address its entry was planned for. `tests/e2e/newcomer/deployment/default.nix` imports
  that deployment so the folder holds one (design D3). Verify
  `nix build .#planner-e2e-newcomer` reports two entry artifacts with different store paths.
- [ ] 4.2 `tests/e2e/delivery.py`: `cluster_stage` takes `offline`, and states in its docstring that
  a folder whose claim is about a machine fetching its own inputs is the one that turns it off.
  `tests/e2e/guest.nix`: the image carries `nix-command`, `flakes` and room for a build, with an
  assertion naming the folder that needs them. Verify `nix build .#planner-e2e-guest` is green and
  that removing the experimental features fails the assertion.
- [ ] 4.3 `tests/e2e/newcomer/test_newcomer.py`: three machines through the folder's own cluster
  stage; the workstation handed the source and the credential with one `nix copy`; the template
  copied and locked with `--override-input`; then
  `test_the_template_names_the_published_flake`,
  `test_the_machine_builds_the_deployment_it_was_handed`,
  `test_one_apply_reaches_both_machines`, `test_the_machine_that_built_it_runs_none_of_it` and
  `test_the_workstation_asks_both_machines_what_they_hold`, the machine layer's tests for the five
  scenarios of *The machine layer walks a newcomer's route* (design D6). Verify
  `nix run .#planner-e2e newcomer` is green, and that the module skips itself with a reason naming
  egress when the cluster cannot reach the substituter.
- [ ] 4.4 `tests/e2e/newcomer/test_newcomer.py`:
  `test_a_consumer_is_asked_for_an_input_only_this_flake_pins`,
  the machine layer's test for the second scenario of *The flake publishes every layer a consumer
  builds with*. It asserts the template's lock holds the package set and this repository and
  nothing else. Verify it fails when the template is given a korora input the call needs.

## 5. The documented example is the folder

- [ ] 5.1 `docs/README.md`: replace the smallest working example with the newcomer folder's own
  deployment text, and say where the deployment is built. Verify the two texts are byte-equal.
- [ ] 5.2 `tests/unit/layers.nix`: `testTheExampleADocumentShowsIsTheExampleAFolderHolds`, the
  evaluating layer's test for that scenario, comparing the fenced block of the document against the
  folder's files and naming both on a difference. Verify it is red against a one-character edit to
  either side.
- [ ] 5.3 `tests/e2e/newcomer/test_newcomer.py`: `test_the_documented_smallest_example_is_built`,
  the machine layer's test for the second scenario of *The example a document shows is the example
  a test builds*. It asserts the build produced an artifact for the placed entry and that no
  realiser refused a fact the plan reported no row about. Verify it is red until
  `report-every-refusal-as-a-row` lands the `pruned` fix, and record here which of its requirements
  turned it green (design D7).
- [ ] 5.4 The consumer flake's text and the block `docs/operator.md` shows for a downstream flake
  are one text, checked the same way as 5.2. Verify a rename of an output breaks the document and
  the test together rather than the test alone.

## 6. The shell and the root

- [ ] 6.1 `devshells.nix`: add `config.packages.planner-cli` to the shell's packages, and derive the
  root from the flake rather than from `git rev-parse --show-toplevel` in the caller's directory
  (design D8). Where the working tree is genuinely wanted, compare it with the flake's own root and
  refuse with both named rather than choosing. Verify `nix develop -c planner --help` prints the
  subcommands, and that entering the shell from an unrelated repository sets no directory of that
  repository on `PYTHONPATH`.
- [ ] 6.2 `flake-module.nix:193`: `planner-e2e-env` refuses when it is not run from a checkout of
  this repository, naming what it needed, instead of continuing with an empty root. Verify running
  it from `/tmp` prints the refusal and exits non-zero.
- [ ] 6.3 `README.md`: name rookery beside `nix run .#planner-e2e`, and say a reader without access
  to it cannot run that command. Verify `testTheRootDoesNotSayWhatTheRepositoryIs` passes with
  `rookery` added to its needle list.
- [ ] 6.4 `tests/unit/layers.nix`:
  `testACommandTheRootAdvertisesNeedsSomethingThisRepositoryCannotProvide`, the evaluating layer's
  test for that scenario, and the needle-list addition from 6.3. Verify the test is red against the
  root as it stood before 6.3.
- [ ] 6.5 `tests/e2e/newcomer/test_newcomer.py`:
  `test_the_shell_carries_the_command_its_documentation_is_about` and
  `test_the_shell_is_entered_from_outside_this_checkout`, the machine layer's tests for the two
  scenarios of *The one shell is a shell of this checkout*. Both enter the shell with a real `nix`
  invocation and neither needs a machine. Verify the second fails against the hook as it stood
  before 6.1, by finding a foreign directory on `PYTHONPATH`.

## 7. The command a newcomer types

- [ ] 7.1 `cli/planner.py`: the help text states what a target may be, the shape of a plan key for
  `--only`, that `rollback` takes exactly one `--only`, and where `docs/operator.md` is (design
  D10). Verify `planner --help` and `planner rollback --help` each name every constraint their
  parser enforces.
- [ ] 7.2 `cli/planner.py` and `cli/apply.py`: `apply --dry-run`. It makes every refusal a real run
  makes, prints the value writes, the copies and the activations it would perform in walk order, and
  contacts nothing (design D9). Verify the printed lines of a dry run and of the same run without
  the flag differ in nothing but the machine's own reports, by `diff`.
- [ ] 7.3 `tests/e2e/test_harness.py`: `test_a_run_is_asked_what_it_would_do` and
  `test_a_dry_run_of_a_deployment_the_planner_refuses`, the machine layer's tests for the two new
  scenarios of *The command refuses before it dials*. They run against a recording namespace, in the
  file that already holds the other two scenarios of that requirement. Verify
  `nix build .#checks.x86_64-linux.planner-delivery` is green and that letting one dial through
  fails the first test.
- [ ] 7.4 `tests/e2e/newcomer/test_newcomer.py`: `test_the_help_text_is_read_as_the_only_document`,
  the machine layer's test for *The help text is read as the only document*. Verify it fails against
  the help text as it stood before 7.1.
- [ ] 7.5 `docs/operator.md`: `--dry-run` in the command's synopsis and one paragraph on what it
  prints and what it does not ask. Verify the example output in the document is the output of the
  command as run.

## 8. The command a document advertises

- [ ] 8.1 Run `nix fmt` on a clean checkout and record here whether it succeeds. If it does, delete
  the sentence at `docs/tooling.md:301-302`. If it does not, name the files and the condition in
  that sentence, and exclude them in `treefmt.nix` where the exclusion is right (design D11). Verify
  the document and the observed behaviour agree, and record the observation in this task.
- [ ] 8.2 `tests/unit/layers.nix`: `testADocumentAdvertisesACommandItAlsoSaysFails`, the evaluating
  layer's test for that scenario. It scans the documents for a command shown and elsewhere reported
  as failing, and names the document and both places. Verify it is red against the tree as it stood
  before 8.1.

## 9. Documentation and invariants

- [ ] 9.1 `docs/operator.md`: the deployment build as an output rather than a path, the downstream
  flake in full, and `flake.mkLib` beside `flake.lib` with what choosing one over the other decides.
  Verify every command in it runs as written and the downstream flake it shows is the one 5.4
  compares against.
- [ ] 9.2 `docs/README.md` and `docs/tooling.md`: the output surface as a table - `lib`, `mkLib`,
  `operator`, `debug`, the packages and the applications - and the newcomer folder in the layer
  list. Verify `testAFileNamesAPathThatIsNotThere` passes.
- [ ] 9.3 `docs/cluster.md`: the newcomer folder, what its cut holds, and why its test builds a
  flake at run time. Verify the folder count each document states matches the folders present.
- [ ] 9.4 `CLAUDE.md`: the invariants this change creates - the deployment build as an output and
  why the realisers are not, that `flake.debug` is the development attrset and `planner` is the
  command, the recorded platform identity and `mkLib`, that the newcomer deployment holds no path
  interpolation and why, that the documented example and the folder are one text, and the shell's
  root. Verify the file passes vale under `nix build .#checks.x86_64-linux.treefmt`.
- [ ] 9.5 Registration: `consumer` in `suites` in `tests/default.nix`, and the four spec paths of
  this change in `accountable` in `tests/unit/coverage.nix`. Verify the coverage cross-walk reports
  an empty difference over the four files.

## 10. Verification

- [ ] 10.1 `nix build .#checks.x86_64-linux.planner-tests -L`: green, with the cross-walk empty over
  this change's four spec files.
- [ ] 10.2 `nix build .#checks.x86_64-linux.treefmt -L`: green, including vale over the documents
  this change edits.
- [ ] 10.3 `nix run .#planner-e2e`: green for every folder, with the count recorded here against the
  count before the change.
- [ ] 10.4 Prove the new assertions can fail: point the consumer flake at a stale store path and
  confirm only the equality test fails; drop `apps.default` and confirm only the discovery test
  fails; add a path interpolation to the newcomer deployment and confirm the unit-layer scan and the
  equality test both fail; remove `planner` from the shell and confirm only the shell test fails.
  Revert each and confirm the tree is byte-identical to before the mutation.
- [ ] 10.5 Walk the route by hand, in a clean directory outside this checkout, using only the
  committed documents: write the flake, build the deployment, apply it. Record here every step that
  needed a fact no document states.
