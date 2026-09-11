Reproduce before repairing. Every task that fixes something names the check that is red first, and a
task is done only when that check is green and the reason it was red is understood. A scenario
heading in this change's specs names its test by construction (`test<CamelCase>` under nix-unit,
`test_<snake_case>` under pytest), so each phase adds the tests its spec's headings name.

Do not regenerate the golden plan or re-record the perf budgets in any phase before 9. They move once,
at the end, from one measurement.

## 1. Registration, so the tree stays green while the change is open

- [x] 1.1 Add this change's seven spec paths to `excused` in `tests/unit/coverage.nix` with the
      reason this repository uses for an unimplemented change, and verify
      `nix eval --json .#debug.failuresBySuite.coverage` is `[]`. Each later phase moves its own spec
      path from `excused` to `accountable` as it lands, so the cross-walk is never claiming more than
      the tree holds.

## 2. The activation order takes every resolved read

- [x] 2.1 Write the failing check first: in `tests/unit/operator.nix` or the `cli` layer's own suite,
      assert against `fixtures/minimal-typed-edge/plan/backup.json` that the order puts
      `vault-repo:server@vault` after all three `nightly:client@*` entries, or that a mutual pair is
      reported. Observe it red - today the walk answers
      `order=(vault-repo:server@vault, nightly:client@alpha, beta, gamma)` with `broken=()`.
- [x] 2.2 Teach `cli/order.py`'s `edges` the per-provider shape (`slot["entries"]`, an attrset keyed
      by provider plan key) beside `slot["entry"]`, dropping providers outside the applied set as it
      already does, and verify 2.1 is green.
- [x] 2.3 Per design D1, make a delivered, resolved read whose shape `edges` does not recognise an
      `ApplyError` naming the consumer and the slot, and verify with a synthetic plan carrying an
      unknown read shape that the command refuses rather than ordering against nothing.
- [x] 2.4 Add the tests the `operator/apply-command` scenario headings name for the set-read and
      mutual-pair cases (`testAnEntryReadingASetOfProvidersFollowsAllOfThem`,
      `testAMutualPairIsReportedHoweverEachSideReadsTheOther`), including the case where the set-read
      consumer sorts below its providers, and verify each fails with 2.2 reverted.
- [x] 2.5 Move `hold-every-stated-guarantee/specs/operator/apply-command/spec.md` from `excused` to
      `accountable` once every heading in it has its test, and verify
      `nix eval --json .#debug.failuresBySuite.coverage` is `[]`.

## 3. The command announces and refuses before it acts

- [x] 3.1 Announce the rollback step before it is attempted: apply `cli/apply.py`'s `_taking`
      discipline to `cli/report.py:183-190`, and verify with a test that a rollback the machine
      refuses has already printed its step line.
- [x] 3.2 Resolve every artifact a run will need - including `image_file(entry)`, today called inside
      the copy loop at `cli/apply.py:183` - before the first dial, and verify with a deployment whose
      second machine's image record names no image that nothing was written or copied.
- [x] 3.3 Route the last unguarded read in `cli/manifest.py` (`_rows`, line 362) through `_load`, and
      verify a built directory whose `diagnostics.json` is not JSON is refused by name rather than a
      `JSONDecodeError`.
- [x] 3.4 Add the tests the two `Every refusal a run can make without a machine precedes the first
      machine` headings name, and verify each is red before its repair.

## 4. The record of an entry both sides agree on

- [x] 4.1 Write the failing check first: a deployment placing one service that publishes an export
      and runs nothing (`impl = _: { }`) is planned, built and then read by the command; observe every
      subcommand die on `path as None` from `cli/manifest.py:328`.
- [x] 4.2 Decide the record in one place per design D10's sibling decision in the spec - an entry with
      no artifact records no path rather than a null one - and change `operator/read.nix:206,435` and
      `cli/manifest.py:189-192,328` together so the absence is read as an absence.
- [x] 4.3 Make a command that needs an artifact for such an entry refuse naming that entry alone, and
      verify a command that does not need it proceeds; add the tests the two
      `The record a build publishes is one every command can read` headings name.
- [x] 4.4 Move `specs/operator/deployment-build/spec.md` to `accountable` and verify the coverage suite
      is `[]`.

## 5. The reading of a plan is total

- [x] 5.1 Write the failing check first: a generator declaring no files is planned, and the plan is
      fed to `operator/read.nix`; observe `error: attribute 'files' missing at operator/read.nix:326`,
      and confirm `builtins.tryEval` does not catch it.
- [x] 5.2 Record `files` on a value entry whether or not it is empty, beside the `delivery` field
      `lib/plan.nix:748-752` already keeps for the same reason, and verify the planner reports the
      generator's own row while the entry still records an empty file set.
- [x] 5.3 Per design D2, make `operator/read.nix` produce a row naming the entry and the field for any
      field the plan may omit, rather than reading it bare, and verify 5.1 now yields a table.
- [x] 5.4 Add the tests the two `The reading is total over a plan the planner pruned` headings name,
      and verify each is red with 5.2 and 5.3 reverted.

## 6. `lib/` stops raising

- [x] 6.1 Write the failing checks first, one per confirmed site: an instance with no `module`
      (`lib/resolve.nix:217`), a string `wire` (`:908`), a non-set `wire.<slot>` (`:916`), a string
      `exposes` (`:274`), a string `placement.every.<m>.machines` (`:383`), string machine `tags`
      (`:188`), a numeric machine `system` (`:203`). Observe each end the evaluation, and record which
      of them `tryEval` cannot catch.
- [x] 6.2 Introduce the one guarded field reading of design D5 in `lib/resolve.nix` - a field read
      with its expected shape, its subject and its row - and verify it produces a row for a malformed
      value without ending the evaluation.
- [x] 6.3 Migrate all seven sites to it and verify every check from 6.1 is green, each naming the
      declaration and the field.
- [x] 6.4 Move the export atom check to where the export is used and put it under the guard
      (`lib/resolve.nix:798-803`), and verify a published export with no atom, and one whose atom is
      not an atom, each yield `export-atom-missing-type` naming the interface and the export.
- [x] 6.5 Make the refusal channel accept only text (`lib/resolve.nix:1012-1018`): a `refused` that is
      not text is a row, and one carrying nothing is not rendered with an empty message. Verify with a
      fold refusing with a set and with `null`.
- [x] 6.6 Verify `lib/` still holds its purity scan: `nix eval --json .#debug.failuresBySuite.diagnostics`
      is `[]` and no `throw`, `abort`, `assert`, `.check ` or `korora.check` was added under `lib/`.
- [x] 6.7 Add the tests the `planner/diagnostics` headings name for the deployment half, the atom and
      the refusal channel, then move `specs/planner/diagnostics/spec.md` to `accountable` and verify
      the coverage suite is `[]`.

## 7. Names, identity and attribution

- [x] 7.1 Write the failing check first: machines `alpha` and `be@ta`, an instance-wide generator
      owned on `alpha` whose secret is read by an entry on `be@ta`. Observe
      `delivery == [ "alpha" "ta" ]`, `applicable = true` and an empty diagnostics table.
- [x] 7.2 Refuse a machine, instance, member or generator name carrying `@`, `:` or `/` per design D3,
      in the reading of each, before any key is built. Verify 7.1 now yields a row naming the machine
      and no delivery set derived from that key, and verify every fixture and every `perf/` deployment
      still plans with no name row.
- [x] 7.3 Write the failing check for the second spelling: `services.pg = service "postgres" { … }`
      today gives `error: attribute 'postgres' missing`, naming nothing.
- [x] 7.4 Make the attribute key a member's identity per design D4: `lib/resolve.nix:536,923` read the
      attribute key, `lib/compose.nix:24-30` stops feeding identity from the argument, and a
      declaration carrying two spellings is a row naming both. Migrate every caller in this tree, with
      no compatibility path, and verify 7.3 is a row.
- [x] 7.5 Reach interface rows from the modules rather than the attribution list per design D6
      (`lib/interface.nix:377-386`), and verify two modules importing an unlisted interface with a
      malformed declared id, and an unlisted interface whose fold is not a function, each produce the
      row a listed one would.
- [x] 7.6 Add the tests the `planner/plan-artifact` headings name, move that spec path to
      `accountable`, and verify the coverage suite is `[]`.

## 8. The image stages a file at its declared mode, and the checks can fail

- [x] 8.1 Write the failing check first: an image entry declaring
      `configData."/etc/app.conf" = { mode = "0600"; render = [ { text = "token="; } { ref = <secret>; } ]; }`,
      and observe in `image/default.nix:144-172` that the staged file is created by `: >` under the
      attaching umask and chmod-ed only after the secret is appended.
- [x] 8.2 Create the staged file with its declared mode per design D7, and verify the mode is correct
      from the file's first existence, is unaffected by a permissive umask, and that an assembly
      interrupted after the append leaves nothing readable more widely than declared.
- [x] 8.3 Add the tests the three `realiser/portable-service-image` headings name, move that spec path
      to `accountable`, and verify the coverage suite is `[]`.
- [x] 8.4 Replace the tautology at `tests/unit/vars.nix:872` with an observation of the property per
      design D9 (`builtins.hasContext` on the recorded `program`), and verify the new form fails when
      a context-carrying string is recorded and passes for a plain store path.
- [x] 8.5 Replace `tests/unit/interfaces.nix:696`'s two applications of one pure function with the
      suite's `support.anotherEvaluation`, and verify it still passes for the right reason - two
      independent library evaluations.
- [x] 8.6 Rebuild the e2e provenance guard from the declaration rather than the values the run just
      read (`tests/e2e/generation.py`, `tests/e2e/generated-secret/test_generated_secret.py:291-293`),
      and verify it raises for a stored value whose declaration has moved and stays silent otherwise.
- [x] 8.7 Delete the implementation-echo expectations at `tests/unit/operator.nix:467-470,1134-1138`,
      `tests/unit/perf.nix:148` and `tests/unit/consumer.nix:88-92`, per the repository's standard that
      a test asserts what a consumer observes; verify the suites are still green and that
      `tests/unit/image.nix:1127` still asserts the digest invariant those echoes claimed to cover.
- [x] 8.8 Make `perf/check.py` refuse a gated fixture with no measurement and report comparisons made
      against comparisons covered per design D8, and verify a run with only `worked.json` fails naming
      the eight absent fixtures rather than printing `0 failures`.
- [x] 8.9 Add the tests the `tooling/test-layers` headings name, move that spec path to `accountable`,
      and verify the coverage suite is `[]`.

## 9. Documents, then one measurement

- [x] 9.1 Correct `docs/README.md:186,196` on the key shape of `varsState` and on what it can change,
      against `lib/resolve.nix:562-563` and the golden plan, and verify the document's fenced examples
      still evaluate to what the surrounding prose says.
- [x] 9.2 Correct `docs/plan.md:269-273`, which contradicts itself on whether a plan carries bytes,
      and the missing "absent when" note on `files.<file>`; `docs/operator.md:203-204,434`, which
      predate the `program` field; `docs/diagnostics.md`, missing `vars-program-malformed` and
      misstating `probes`'s trigger; `docs/tooling.md`'s stale counts; `docs/flakelet.md`'s four stale
      `image/read.nix` citations; `fixtures/minimal-typed-edge/README.md`'s line count; and
      `treefmt.nix`'s comment attributing vulture's finding to the wrong file. Verify with
      `nix build -L .#checks.x86_64-linux.treefmt`.
- [x] 9.3 Cross-check the row table against the tree per design D10: every `id = "…"` under `lib/` has
      a line in `docs/diagnostics.md` and every line names a row the tree produces. Verify the check
      fails when a row is added without its line.
- [x] 9.4 Derive or check the counts a document records rather than writing them by hand, and verify
      the check fails when a suite gains a test.
- [x] 9.5 Add the excuse-expiry check the `A specification is classified exactly once` heading names -
      an excuse whose ground is that its change is unimplemented, for a change that is implemented -
      and verify it is red for a deliberately stale excuse. The double-listing half of that
      requirement already landed as `testEverySpecificationIsClassified`'s `doubled` field.
- [x] 9.6 Add the invariants this change creates to `CLAUDE.md`: an unrecognised resolved read is a
      refusal; `files` is recorded like `delivery`; a name carrying `@`, `:` or `/` is a row; the
      attribute key is a member's identity; interface rows are reached from the modules; a staged file
      is created with its mode. Verify `nix build -L .#checks.x86_64-linux.treefmt` (vale included).
- [x] 9.7 Move `specs/tooling/repository-shape/spec.md` to `accountable`, verify `excused` holds no
      path of this change, and verify the coverage suite is `[]`.

## 10. Verification

- [x] 10.1 `nix build -L --no-link .#checks.x86_64-linux.planner-tests`: green. 407 unit tests, from
      the 382 this change started at, measured against `9ce69dc`: `diagnostics` 22 -> 35, `plan`
      29 -> 35, `operator` 29 -> 31, `resolution` 43 -> 44, `coverage` 8 -> 10, `exclusions`
      16 -> 17, and every other suite unchanged in count, three of them with a tautology replaced
      by an observation. The last four of those tests are the review's own: an unattributed fold
      row, a refused sibling read, a module that is not a function, and a record of the wrong kind.
- [x] 10.2 Regenerated: `nix eval --json .#debug.worked.plan | jq -S .` is byte-identical to the
      committed golden. No entry key moved and no field appeared, which is the expected reading of
      this change against this fixture: every generator in it declares files, so the always-present
      `files` field was already recorded, and the fixture declares no malformed value, no name
      carrying a separator and no member spelled twice, so no new row is earned.
- [x] 10.3 Re-recorded from `planner-perf-results`, with `check.py`'s own `figure` rounding and
      `margin` 0.15 / `growth` 1.25 untouched. Every one of the 81 gated figures moved up by about
      7% per plan entry, uniformly across sizes 4, 16, 64 and 256 - `worked`'s `nrThunks` 726.18 ->
      794.73, `fleet-16`'s 388.76 -> 420.90, `fleet-256`'s 305.03 -> 328.30, `mesh-256`'s 367.24 ->
      390.84 - so the cost is a constant added to the reading of one entry rather than a new term in
      how the reading grows. The three sources are the guarded field reading, the key-grammar check
      on every name, and the interface rows now earned from the modules rather than from
      attribution; none is avoidable without giving up the guarantee it holds. Recorded twice: once
      for the change and once for the review's library repairs, which moved every figure a further
      0.4% to 1% and no figure's growth across sizes.
      `.#checks.x86_64-linux.planner-perf` and `planner-perf-checker` exit 0.
- [x] 10.4 `.#checks.x86_64-linux.planner-delivery` and `.#checks.x86_64-linux.treefmt`: green. The
      delivery check's 65 tests are the 54 this change started at plus nine the specs' headings name
      and two the review added about a malformed file inside a build.
- [x] 10.5 `nix run .#planner-e2e` with `PYTHONPATH` unset: 78 passed, none skipped, in 174s. The
      75 recorded at the start is beaten by three, which is `portable-image`'s three assembly tests;
      `newcomer`'s eight cases skip themselves on a host that gives the cluster no egress and ran
      here.
- [x] 10.6 Each repair reverted, its named check observed red, restored:
      - a set-valued read is an ordering edge (`cli/order.py`) ->
        `test_an_entry_reading_a_set_of_providers_follows_all_of_them`
      - an unrecognised read shape is a refusal (`cli/order.py`) ->
        `test_a_resolved_read_recorded_in_an_unknown_shape_is_refused`
      - the rollback step is announced before it is attempted (`cli/report.py`) ->
        `test_a_step_the_machine_refuses_is_named_by_the_run_that_took_it`
      - every artifact a run needs is resolved before the first dial (`cli/apply.py`) ->
        `test_an_artifact_the_run_needs_later_is_missing`
      - an entry with no artifact records no path (`operator/read.nix`) ->
        `test_an_entry_declares_no_unit`
      - a value entry records its file set, empty or not (`lib/plan.nix`) ->
        `plan.testAGeneratorDeclaresNoFiles`
      - the reading is total over a field the plan pruned (`operator/read.nix`) -> the `operator`
        suite's two `operator-plan-field-missing` tests
      - a malformed declaration is a row, never a raise (`lib/resolve.nix`) -> the `diagnostics`
        suite's declaration tests
      - a name carrying a key separator is a row (`lib/resolve.nix`) ->
        `plan.testAMachineNameCarriesTheKeySeparator` and
        `plan.testAnInstanceOrMemberNameCarriesTheKeySeparator`
      - the attribute key is a member's identity (`lib/resolve.nix`) ->
        `plan.testAMemberIsDeclaredUnderAKeyOtherThanItsOwnName`
      - an interface earns its rows from the modules that imported it (`lib/default.nix`) -> four
        `diagnostics` tests, two of them about an interface the deployment lists nowhere
      - a staged file is created at its declared mode (`image/default.nix`) ->
        `portable-image::test_the_assembly_of_a_file_fails_part_way` and
        `::test_the_mode_does_not_depend_on_the_attaching_environment`, both red with the recipe
        reverted to `: >` and green with it restored. The second was rewritten first: with the old
        recipe chmod-ing at the end, the finished file's mode alone could not tell the two recipes
        apart, so it now reads the mode of the assembly as well as of the finished file. All three
        assembly tests were then moved onto the machine, where the rest of the folder observes: the
        script is the artifact's own under a root of the run's choosing, the two commands that would
        attach are answered by a `PATH` that refuses, and one case is one ssh command because the
        guest's per-connection sshd stops accepting a burst of short logins.
