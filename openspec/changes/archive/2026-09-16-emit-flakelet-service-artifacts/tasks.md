## 1. Baseline and the input

- [x] 1.1 Record the spike as the before-state: paste the artifact layout it produced (`units/spike-web-web.service`, `meta.json`), the rendered unit file including the appended `[Install]` section, and the four VM observations (`activating generation 1`, the `curl` success, `flakelet status --json` reporting `"generation": 1, "last_error": null`, and the reboot subtest passing in 12.80s) into this task, together with the one blocker it reported: `"export_blockers": [ "generation was built without state.json, redeploy it" ]`

  The spike's store objects survived it, so this is its bytes and not a retelling.
  `/nix/store/gfd8mpzzv14216x8r726cabm6js3gwna-flakelet-spike-web`:

  ```
  <artifact>/meta.json -> /nix/store/07hj5anc8iplbahb547x8dx6qxd56q5p-meta.json
  <artifact>/units     -> /nix/store/3wbzwsrvbczc2hjy36i0nvj0ndcgplqd-spike-web-units
  <artifact>/units/spike-web-web.service
        -> /nix/store/iqcddjyks6011m5z74mmkp129si6ljvj-spike-web-web.service
  ```

  `meta.json`, verbatim - three `serde(default)` fields plus a version and a name:

  ```json
  {"flake_rev":"","flake_url":"plan:spike:web@vm","name":"spike-web","settings_hash":"13792305c5680264","version":1}
  ```

  `units/spike-web-web.service`, verbatim - `image/read.nix`'s `renderUnit` output with the one
  section it does not write appended last:

  ```ini
  [Unit]
  Description=spike:web web

  [Service]
  ExecStart=/nix/store/3n4qphl9s728sz8frmpqqrv9b1m87g68-python3-3.14.7/bin/python3 -m http.server 8080
  Environment=PYTHONUNBUFFERED=1

  [Install]
  WantedBy=multi-user.target
  ```

  The four VM observations, as the spike's run reported them:

  ```
  machine # flakelet[762]: spike-web: activating generation 1
  machine # flakelet[762]: spike-web: updated to generation 1
  machine: must succeed: curl -sf http://localhost:8080/ > /dev/null   (finished, 0.05s)
  machine: flakelet status --json → "generation": 1, "last_error": null
  subtest: the unit survives a reboot                                  (finished, 12.80s)
  ```

  And the one blocker it reported, which is why `state.json` is out of scope here:
  `"export_blockers": [ "generation was built without state.json, redeploy it" ]`.

  What the spike did *not* measure, and this change found on the first real entry: the worked
  deployment's units carry `BindReadOnlyPaths=/run/portable-planner/<name>/files<path>`, a
  directory the image realiser's attach script assembles and nothing on a flakelet host does. The
  spike's entry had no configuration data, so it never hit it. That is design.md D7 and the fifth
  requirement of the spec.
- [x] 1.2 Add the `flakelet` flake input pinned to a revision of `github:Mic92/flakelet` and verify `nix eval .#inputs.flakelet.rev` prints that revision and that `nix eval --raw .#inputs.flakelet.outPath` resolves without fetching anything else

  Pinned to `20a676fe96231575d51ff9553d1e31d325c8f0f8` (2026-09-07), with
  `inputs.nixpkgs.follows = "nixpkgs"` so one nixpkgs is fetched rather than two.

  The two verifications as written are not runnable: Nix 2.35.2 resolves `.#<attr>` against a
  flake's *outputs*, and a flake's `inputs` is not one of them - `nix eval .#inputs.korora.outPath`
  fails the same way on the input that was already pinned before this change. Exposing
  `flake.inputs` to make the command work would add an output nothing consumes. What was verified
  instead, same two claims:

  ```
  $ nix flake metadata --json | jq -r .locks.nodes.flakelet.locked.rev
  20a676fe96231575d51ff9553d1e31d325c8f0f8
  $ nix flake metadata --json --offline | jq -r '.locks.nodes | keys | join(" ")'
  adios flake-parts flakelet korora nixpkgs root systems treefmt-nix
  ```

  `--offline` resolving the lock and `nix build .#checks.x86_64-linux.planner-flakelet-vm`
  evaluating `inputs.flakelet.nixosModules.flakelet` are together the "resolves without fetching
  anything else" half: `adios` is flakelet's own input, and no third nixpkgs appears.
- [x] 1.3 Capture the perf baseline with `bash perf/measure.sh` and verify `nix build .#checks.x86_64-linux.planner-perf -L` passes against the committed budgets before anything changes, since this change adds a second consumer of the same reading

  Baseline taken before the first edit: `nix build .#checks.x86_64-linux.planner-perf -L` →
  `/nix/store/hp0n89rcp5ji9ppn11syhsmc412gcl36-planner-perf`, exit 0, so the committed budgets held
  on the tree this change started from. The measurement the check reads is `measure.sh`'s, run
  inside `packages.planner-perf-results` with the same fixtures and sizes.

## 2. The builder

- [x] 2.1 Add `flakelet/default.nix` exposing `artifact { plan, key }`, calling `reader.read` and `reader.renderUnit` from `image/read.nix` and assembling a `linkFarm` of `units/` plus `meta.json`; verify a case asserts the artifact's top level is exactly those two names and that `units/` holds one file per recorded unit

  `flakelet/default.nix` is the assembly; `flakelet/read.nix` is the reading it needs and
  `image/read.nix`'s `read`, `renderUnit` and `renderTimer` are what that reads with. Both take the
  reader they build on as an argument, because the suite and the check hold the two files as
  unrelated store paths and a relative import does not survive that. Asserted by
  `test_one_entry_becomes_one_artifact` (top level is exactly `meta.json` and `units`) and
  `testOneEntryBecomesOneArtifact` (one file per recorded unit).
- [x] 2.2 Render a scheduled unit's timer beside its service with `reader.renderTimer`; verify a case asserts an entry with a schedule produces both files and that an entry without one produces only the service file

  `testAScheduledUnitBringsItsTrigger` over the values and
  `test_a_scheduled_unit_brings_its_trigger` over the built directory: the scheduled fixture holds
  `nightly-only-sweep.service`, `nightly-only-sweep.timer` and `nightly-only-web.service`, and the
  long-running fixture holds no `.timer` at all.
- [x] 2.3 Expose the builder from `flake-module.nix` beside `imageBuilder`, and add `packages.planner-flakelet-artifact` built from a fixture entry; verify `nix build .#planner-flakelet-artifact` succeeds and `nix path-info -rS` shows the artifact's closure contains the units' referenced store paths

  ```
  $ nix build .#planner-flakelet-artifact --no-link --print-out-paths
  /nix/store/0sa8qzhncv5c5wm81l9iwxmjizb1bwvm-flakelet-svc-only
  $ nix path-info -rS /nix/store/0sa8qzhncv5c5wm81l9iwxmjizb1bwvm-flakelet-svc-only | tail -4
  …-coreutils-9.11                              51051736
  …-svc-only-web.service                        51052064
  …-flakelet-svc-only-meta.json                      232
  …-flakelet-svc-only                           51053088
  ```

  The unit's `ExecStart` names `coreutils`, and `coreutils` is in the artifact's closure: a machine
  that holds the artifact holds what its units run. The package is the check's long-running fixture
  rather than a worked entry, because the worked entries are refused here (1.1, design.md D7).

## 3. Enablement

- [x] 3.1 Append `[Install]` with `WantedBy=multi-user.target` to a long-running unit's rendered text in the flakelet builder only, leaving `image/read.nix`'s `renderUnit` unchanged; verify a byte case asserts the section is present, that it is last, and that the same entry built through the image realiser still carries no `[Install]`

  `test_a_long_running_unit_is_wanted` asserts all three against bytes, and the third as an
  equation rather than an absence: the flakelet unit file **is** the image realiser's rendering of
  the same entry plus `"\n[Install]\nWantedBy=multi-user.target\n"`, and that rendering carries no
  `[Install]`. `testALongRunningUnitIsWanted` asserts the section order (`[Unit]`, `[Service]`,
  `[Install]`) so "last" is a position and not a substring.
- [x] 3.2 Put `WantedBy=timers.target` on a scheduled unit's timer and no `[Install]` on its service; verify a byte case asserts both halves, since an `[Install]` on the service of a scheduled unit would fire the job at deploy time

  `test_a_scheduled_unit_is_not_fired_by_deploying_it` over the two files, and
  `testAScheduledUnitIsNotFiredByDeployingIt` over the sections of each. The timer also names its
  own service (`Unit=nightly-only-sweep.service`), which is what makes the pair a trigger rather
  than two unrelated units.
- [x] 3.3 Document the rule where it is made, in a comment naming what the plan says (`schedule`) and what the backend decides (what enabled means), so the next binding has the argument rather than the conclusion

  `flakelet/read.nix`, above `installSection`: the plan says *when* a unit runs, the backend says
  what that means, flakelet's answer is `systemd.rs:166-170` and the image realiser's answer is no
  `[Install]` at all. The comment carries the consequence too, that an `[Install]` on the service
  of a scheduled unit runs the job at deploy time, leaving the next binding the argument.

## 4. Identity

- [x] 4.1 Write `meta.json` as `{ version = 1; name; flake_url = "plan:<key>"; flake_rev = ""; settings_hash = <the entry's version digest>; }`; verify a case asserts every field's value against the entry it was built from, and that `settings_hash` equals the digest `image/read.nix` computes rather than the entry's key

  `test_the_artifact_carries_the_plans_identity` reads the built file and compares the whole
  document against the entry it was built from, so an added or renamed field fails it.
  `testTheArtifactCarriesThePlansIdentity` asserts `settings_hash == image.version` and
  `settings_hash != image.key` as separate claims.
- [x] 4.2 Verify the identity is what the endpoint compares: a case asserting two builds of one unchanged entry are byte-identical, that changing one unit field changes `settings_hash` and the artifact, and that changing a second entry leaves this artifact byte-identical

  `test_a_rebuild_is_identical`, `test_a_unit_field_change_is_a_new_generation` and
  `test_an_unrelated_edit_changes_nothing`, each on store paths: two equal paths are one store
  object, so the bytes are shared and not merely equal. The endpoint half is the VM's
  `an unchanged entry is a no-op` subtest, which restarts the activation unit and asserts the
  service's `MainPID` and generation are unchanged.

## 5. Refusals

- [x] 5.1 Refuse an entry whose derived service name is not accepted by the endpoint's rule — first character alphanumeric, then alphanumerics, `-` and `_`, no dots, at most 128 characters — raising with the entry, the derived name and the rule; verify cases assert the raise for an instance name carrying a dot and for one carrying a character outside the set, and no raise for a well-formed name

  `testAnUnusableInstanceName` asserts the raise for `web.one` and `web+one`, no raise for
  `web_one-1`, and the rule itself at its edges: 128 characters accepted, 130 refused, a leading
  `-` refused, the empty name refused. `test_an_unusable_instance_name_fails_the_build` asserts the
  sentence names the derived name and the rule.
- [x] 5.2 Refuse an entry that would render a unit file whose base does not equal the derived service name or begin with it followed by `-`, or that carries more than one `@`, raising with the entry and the unit name; verify a case asserts the raise and one asserts a well-formed set of unit names passes

  `testAUnitNameOutsideTheServicesNamespace`: the raise for a unit named `web@one@two`, no raise
  for the scheduled entry's well-formed set, and the rule at its edges - the service itself, a
  prefixed unit and one instance accepted; two instances, another service's prefix and a suffixless
  name refused. `test_a_unit_name_outside_the_namespace_fails_the_build` asserts the sentence names
  the entry and `svc-only-web@one@two.service`.
- [x] 5.3 Verify the refusals happen before any file is produced by asserting the raise fires on evaluation of the artifact rather than during its build

  Each refusal expression in `flakelet/check.nix` forces `(builder.artifact { … }).drvPath` and
  nothing else, and `test_flakelet.py::_refusal` evaluates it with `nix eval`. A raise there is a
  raise before a derivation existed, so there is nothing to build and no file to have written.

## 6. Byte tests

- [x] 6.1 Add `tests/python/test_flakelet.py` in the shape of `test_image.py` — reading a built artifact from an environment variable — covering the layout, the two `[Install]` cases, `meta.json`'s fields and the three determinism cases; verify the new pytest check builds and every case passes

  `$PLANNER_FLAKELET` names the artifact `checks.planner-flakelet` builds, the way
  `$PLANNER_IMAGES` does for the image check. Twelve cases: the layout twice (the two top-level
  names, and the whole recursive listing for "nothing is evaluated to activate it"), the timer
  pair, both `[Install]` halves, `meta.json`'s five fields, the three determinism comparisons and
  the four refusal sentences. `nix build .#checks.x86_64-linux.planner-flakelet -L` → `12 passed`.
- [x] 6.2 Wire the artifact fixture the tests read through `flakelet/check.nix` beside `image/check.nix`, building one artifact per case from real plan entries; verify the check's derivation names each fixture and that no case reads the working tree

  Every fixture is a `planner.mkPlan` result: `artifacts/long-running` and `artifacts/scheduled`
  are built, `refusals/{dotted-name,unusable-character,unit-outside-the-namespace,host-file,generated-file}`
  each carry the entry's plan as JSON plus the expression that refuses it, and the two host-file
  refusals are the worked deployment's own entries. The asserting half reads `$PLANNER_FLAKELET`
  and the files under it; the check copies `tests/python/*.py` into a build directory with no flake
  above it, so a case that reached for the working tree would have nothing to reach.

## 7. The end-to-end check

- [x] 7.1 Add `tests/nixos/flakelet.nix`: a `runNixOSTest` importing `flakelet.nixosModules.flakelet`, one entry declared with `prebuilt` pointing at a planner-built artifact, asserting the unit becomes active, that the service answers a request, and that `flakelet status --json` names the entry's plan key

  Two entries are declared with `prebuilt` (`demo-web`, `nightly-job`) and one is activated by
  hand (`roll-web`). The observations, from the run's own log:

  ```
  machine # flakelet[768]: demo-web: using prebuilt artifact /nix/store/…-flakelet-demo-web
  machine # flakelet[768]: demo-web: activating generation 1
  subtest: a long-running unit is started                        (finished, 0.06s)
  subtest: the service is reachable                              (finished, 0.06s)
  subtest: the running artifact names its entry                  (finished, 0.04s)
  subtest: nothing is evaluated to activate it                   (finished, 0.02s)
  ```

  `status --json` reports `locked_url = "plan:demo:web@vm"`, `generation = 1`,
  `last_error = null` and `demo-web-serve.service` among its units - the plan key reaches the
  machine's own answer about what it is running. The `nothing is evaluated` subtest reads the
  activation's journal back: `using prebuilt artifact` is there and `resolving` is not.
- [x] 7.2 Extend the test with the reboot subtest and a rollback subtest: activate a second artifact built from an edited entry, roll back, and assert the previous generation's units are running and reported active; verify the whole test passes as a supervised process and record its wall time

  The rollback pair differs in one unit field (`env.GENERATION`), which is what makes "the previous
  generation is running" observable rather than assumed: after `flakelet rollback roll-web`, the
  unit is active, `systemctl show -P Environment` reads `GENERATION=one`, `status --json` reports
  `generation = 1` and `changed.by = {"kind": "rollback", "from": 2}`, and the service answers on
  its port again. After `shutdown()`/`start()` both entries come back with no activation re-run by
  hand, and the rolled-back generation is the one that returns.

  Run as a supervised process (`hub` `flakelet-vm3`): exit 0, **49.9s** wall clock for
  `nix build .#checks.x86_64-linux.planner-flakelet-vm` with everything else cached, of which the
  test script itself was 44.91s and the reboot subtest 15.54s.
- [x] 7.3 Add a subtest asserting a scheduled entry's timer is enabled and its service was not started by the activation; verify it fails when `[Install]` is put on the service, which is the mistake the rule exists to prevent

  The subtest asserts the timer is active, that
  `/run/systemd/system/timers.target.wants/nightly-job-sweep.timer` exists and that no
  `multi-user.target.wants` link exists for the service, that the service's `ActiveState` is
  `inactive` with an empty `ExecMainStartTimestamp`, and that the job's side effect (`/tmp/swept`)
  is absent. `is-enabled` is deliberately not the assertion: the endpoint enables by linking out of
  the store, so systemd answers `linked-runtime`.

  Verified by making the mistake. With `renderUnit` changed to append `[Install]` unconditionally,
  the same check fails in that subtest and nowhere else:

  ```
  subtest: a scheduled unit is not fired by deploying it
  !!! Test "a scheduled unit is not fired by deploying it" failed with error:
      "command `test -e /run/systemd/system/multi-user.target.wants/nightly-job-sweep.service`
       unexpectedly succeeded"
  ```

  The mutation was reverted: the shipped `renderUnit` differs from the copy taken before it only
  where `nixfmt` collapsed the conditional onto one line.
- [x] 7.4 Expose the test as `checks.x86_64-linux.planner-flakelet-vm` and verify it is listed by `nix flake show --json` and builds from a clean checkout

  ```
  $ nix flake show --json | jq -r '.checks."x86_64-linux" | keys | join(" ")'
  planner-flakelet planner-flakelet-vm planner-images planner-perf planner-perf-checker
  planner-python planner-scenarios planner-tests treefmt
  ```

  Clean checkout: this tree's staged state materialised into a fresh git repository under `/tmp`
  and evaluated there offline produces the identical derivation,
  `/nix/store/nyldkq418cq0fix8nww81ndykwpl2lgi-vm-test-run-planner-flakelet.drv`, so nothing
  untracked leaks into the check.

## 8. Documentation

- [x] 8.1 Add `docs/flakelet.md`: the artifact's layout, the enablement rule and why it is the backend's, the identity fields and which one the endpoint compares, the refusals, and the two things deliberately absent (`state.json` with its dependency named, `exports.json` with its reason); verify every claim in it names the file or the measurement it comes from

  Layout and unit text are the built artifact's bytes; the enablement table cites
  `systemd.rs:166-170` for what the endpoint does and names the subtest that pins the scheduled
  half; the identity section cites `manager.rs:379-380` for what `status` shows,
  `manager.rs:1030-1036` with `generations.rs:14-18` for what is recorded, and
  `image/read.nix:122-135` for why the digest and not the key; the refusal table cites
  `manager.rs:1301-1326` and `image/default.nix:101-133`; and the absent half cites the spike's own
  `export_blockers` line and `manager.rs:1378-1383`. Removal and delivery are named there too,
  because a reader who does not find them should find out why.
- [x] 8.2 Point at it from `docs/README.md`'s output table and state in one line how the two realisers differ — store-backed against store-less — so a reader is not left guessing which one to build

  The document table gains a `flakelet.md` row, the tree listing gains `image/` and `flakelet/`,
  and the paragraph under the table states the difference with the command for each:
  store-less carries its own closure and is attached, store-backed carries units and is run out of
  the machine's own store.
- [x] 8.3 Add a paragraph to `notes/clan-portable-services-design.md` §16.7 recording that a flakelet artifact is a second binding over one unchanged plan, that enablement is a binding decision, and the trigger that moves us to linking `flakelet-core` (set-arithmetic removal or the plan as sole authority); verify it names `Manager::new` and `reconcile` rather than restating the conclusion

  Amendment dated 2026-09-07, beside the 2026-09-05 one it makes good on. It names
  `Manager::new(config: Config)` taking a value (`manager.rs:146-151`), `Origin::Declarative`, and
  `reconcile` removing declarative entries no longer in the config (`manager.rs:583-596`), and says
  which two things that route buys - set-arithmetic removal and the plan as sole authority - rather
  than asserting that the seam is temporary.

## 9. Verification

- [x] 9.1 Add one `tests/mapping.nix` entry per heading of this change's spec and cross-walk every scenario to the case that exercises it, using the external form for the pytest and VM cases; verify `nix eval --json .#planner.failuresBySuite` is empty

  Twenty-six headings, each mapped. The VM cases needed a third external form:
  `nixos/flakelet.nix::<subtest>`, which `suites/coverage.nix` resolves by looking for
  `subtest("<name>")` in the test file the way it looks for `def <name>(` in a Python one, which is
  what makes a mapping to a subtest nobody wrote a failure. `flakeletSpecRoot` is registered in
  `coverage.nix`'s `specSets`, so a scenario added to this spec later with neither a test nor a
  reason fails too.

  ```
  $ nix eval --json .#planner.failuresBySuite
  {"closure":[],"composition":[],"coverage":[],"diagnostics":[],"exclusions":[],"flakelet":[],
   "image":[],"interfaces":[],"perf":[],"plan":[],"platform":[],"resolution":[],"source":[],
   "units":[]}
  ```
- [x] 9.2 Run `openspec validate emit-flakelet-service-artifacts --strict` and confirm it passes with the artifacts as implemented

  `Change 'emit-flakelet-service-artifacts' is valid` - with the fifth requirement and its three
  scenarios (the host-file refusal) in the spec, and D7 in design.md.
- [x] 9.3 Run `nix build .#checks.x86_64-linux.planner-tests .#checks.x86_64-linux.planner-python .#checks.x86_64-linux.planner-images .#checks.x86_64-linux.planner-perf -L` and the two new checks, then `nix fmt`; verify all pass and that formatting touched only files this change edited

  All six built in one invocation, exit 0:

  ```
  planner-tests>    🎉 199/199 successful
  planner-python>   All checks passed!  /  Success: no issues found in 12 source files
  planner-images>   20 passed
  planner-flakelet> 12 passed
  planner-perf>     check.py: 0 failures, 0 invalid comparisons
  ```

  The VM check was already valid in the store from its own run of the identical derivation
  (`nyldkq418cq0fix8nww81ndykwpl2lgi`), so it printed nothing this time; `test script finished in
  44.91s` is that run's last line.

  `nix fmt` changed four files, all of them this change's own (`flakelet/check.nix`,
  `flakelet/read.nix`, `tests/nixos/flakelet.nix`, `tests/suites/flakelet.nix`); a second run
  reports `0 changed`. Two notes on what "all pass" means here:

  - `nixfmt`, `deadnix`, `shellcheck` and `yamlfmt` are clean.
  - The prose linters (`vale`, `harper`) fail repository-wide on markdown that predates this
    change: 351 findings under `openspec/changes/emit-systemd-portable-service-images`, 135 under
    `implement-minimal-typed-edge`, 35 in `docs/plan.md`. The `vale` findings in the files this
    change owns were fixed; the `harper` classes it reports on them are the repository's own house
    style (`realiser` as a spelling error, sentence length), so they are left as they are rather
    than this change rewriting the corpus.
