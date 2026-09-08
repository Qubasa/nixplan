## 1. Scaffolding

- [x] 1.1 Add the `korora` flake input pinned to revision `336685de099953ffd25e8d020cffe9a1de903420` with a comment recording that upstream publishes no tags and giving the revision's date; verify `nix eval .#` still evaluates and that `flake.lock` gained exactly one node by inspecting the diff
- [x] 1.2 Create `flake-module.nix` exposing the library, a `checks.<system>.planner-tests` entry and a `packages.<system>.planner-perf` harness entry, and import it from `flake.nix` beside `pkgs/qubasa-blog/flake-module.nix`; verify `nix eval .#checks.x86_64-linux --apply builtins.attrNames` lists the test check
- [x] 1.3 Create `lib/default.nix` with `mkPlan { interfaces, instances, machines }` returning `{ plan = { }; diagnostics = [ ]; applicable = true; }` and nothing else; verify `nix eval .#lib.mkPlan --apply 'f: builtins.isFunction f'` returns true and `nix fmt` leaves the repository root unchanged
- [x] 1.4 Confirm the repository root needs no entry in `treefmt.nix` `settings.global.excludes` by running `nix fmt` and checking `git status` reports no modification to files under the repository root

## 2. The type layer and interfaces

- [x] 2.1 Create `lib/atoms.nix` defining `url` and `secretRef` with `korora.typedef` on top of the korora types, and re-export korora's own primitives under one attribute set; verify a test asserts `url.verify "ssh://x"` is null and `url.verify 3` is a string
- [x] 2.2 Create `lib/interface.nix` with the export atom schema `{ type, secrecy ? "public" }`, the two-value `secrecy` domain, and `interface { name, exports }`; verify a test asserts an omitted `secrecy` reads as `public` and that `interface` returns a value carrying no reference to any registry
- [x] 2.3 In `lib/interface.nix`, refuse an atom key outside `{ type, secrecy }` with an error row whose message names the key and the condition that would introduce it, using the two triggers `interfaces/exports.nix` already states for `locality` and `lifecycle`; verify tests assert a row for each of the two keys and that neither is silently dropped
- [x] 2.4 Implement interface identity by value, with `name` used only in rendering, and a row for a wire whose two interfaces differ but share a `name`; verify a test wires two same-named distinct interfaces and asserts one error row carrying both declaring files
- [x] 2.5 Evaluate `fixtures/minimal-typed-edge/interfaces/exports.nix` and `interfaces/default.nix` unmodified against this layer; verify both files evaluate and produce two interfaces with four exports between them, and that no edit to either file was needed

## 3. The asking half and composition

- [x] 3.1 Create `lib/module.nix` reading a leaf module's asking half: `platforms`, `claims.ports.<n>`, `vars.<gen>.files.<f>.secrecy`, `uses.<slot>`, `provides.<cap>` and `impl`; verify a test evaluates `modules/borg-repo/server.nix` and `modules/borg-push/client.nix` unmodified and reads back the declared slots and capabilities
- [x] 3.2 Implement the slot schema with `reach` defaulting to `one`, `reads` defaulting to every export of the interface, a row for `reach = "local"` naming the locality this subset does not declare, and a row for a `reads` entry the interface does not declare; verify one test per row plus a test that an omitted `reach` behaves as `one`
- [x] 3.3 Create `lib/compose.nix` implementing `service "<name>" { module, defaults, fixed }`, the member settings namespace keyed by member name including for a single-member root, and capability re-export; verify a test evaluates both `default.nix` roots unmodified and asserts that a setting written without the member name is a row
- [x] 3.4 Implement `defaults` and `fixed`, with a deployment definition against a `fixed` path producing an error row naming the deployment file and the module file; verify tests cover a default overwritten, a fixed path written and the plan recording the source of each resolved setting
- [x] 3.5 Implement `exposes` and the rule that an unexposed capability is not addressable from outside its instance; verify a test wires to an unexposed capability and asserts a row listing what that instance does expose

## 4. Resolution

- [x] 4.1 Create `lib/resolve.nix` round 3: turn each slot into an edge by resolving `wire.<slot>` against the named instance's exposed capabilities, with rows for an unknown instance and an unknown capability carrying the candidate list; verify tests for both misses assert the candidate list is present and non-empty
- [x] 4.2 Implement the unwired-slot row, so a slot with no wire resolves to no value at all; verify a test asserts the row and asserts that no attribute a consumer could default against is produced
- [x] 4.3 Implement the secrecy rule: a `reads` entry naming a `secret` export is refused on every machine regardless of placement; verify tests cover the refusal, a producer using its own secret through its own unit without a slot, and a secret export with no reader being accepted
- [x] 4.4 Implement round 6 placement from `placement.every.<member>` over `machines` and `tags` against the machine registry, and fixed port allocation from `claims.ports.<n>.fixed` with a row for a claim carrying no `fixed`; verify tests cover a tag placing three machines, a named machine list, and the refused dynamic claim
- [x] 4.5 Implement the `reach` check against the placements of the wired capability: `one` against two placements is a row naming the slot and both placements, and `all` produces an attribute set keyed by machine even at one placement; verify one test per case, including the single-placement set not collapsing
- [x] 4.6 Implement round 7: call `impl` in dependency order, produce exports, and check keyset equality at the producing capability for both an omission and an extra; verify tests for both directions assert the row names the publishing file and the interface's declaring file
- [x] 4.7 Implement the acyclicity property that a capability's exports depend on module and settings and never on a wire, so two instances wiring each other resolve without either appearing in the other's dependency list; verify a test over the worked deployment asserts both entries resolve and neither dependency list names the other

## 5. Diagnostics

- [x] 5.1 Create `lib/diagnostics.nix` with the record shape `{ id, subject, severity, message, evidence, resolution }`, the two-value severity domain, and deterministic ordering by identifier then subject; verify a test evaluates one input twice and asserts the two tables are equal including order
- [x] 5.2 Make every function in the library return its rows alongside its value, with no ambient accumulator, and make `mkPlan` return `plan`, `diagnostics` and an applicability flag derived from whether any row is an error; verify tests assert a plan is produced beside an error row and that a warning alone leaves the plan applicable
- [x] 5.3 Refuse an absolute path as a row subject, so a rendered table does not differ between checkouts; verify a test asserts a row for a subject that is not a plan key, a deployment-relative path or an issue identifier
- [x] 5.4 Implement rendering to the row format `examples/*/plan/diagnostics.txt` uses, as a function of the table alone; verify a test renders a two-row table and asserts the output shape, and a second test asserts an instance producing no rows leaves rendering unchanged
- [x] 5.5 Implement the rule that a module cannot set the severity of a planner row, with a warning row naming the attempt; verify a test asserts the declared severity had no effect and that the warning names the module

## 6. Plan emission

- [x] 6.1 Create `lib/plan.nix` emitting entries keyed by instance, service and machine, with a placement-free entry for a service with no units; verify a test asserts `builtins.toJSON` succeeds on the worked deployment's plan and that reading it back yields an equal value
- [x] 6.2 Implement key derivation over instance, service, closure strings, resolved environment, dependency keys and machine key; verify tests assert an unrelated setting change leaves an unrelated key unchanged, a read value change moves the reader's key, and two evaluations of one input produce equal keys
- [x] 6.3 Implement dependency edges as keys that appear elsewhere in the same plan, carrying the depended-on entry's key hash; verify a test asserts every dependency string in the worked deployment's plan resolves to an entry in that same plan
- [x] 6.4 Implement the absent-value recording: a named entry with a null value and an absent marker, the row it produced named on the entry, and any artifact derived from an incomplete set recorded as not computed; verify tests cover the ungenerated placement and the file rendered over an incomplete set
- [x] 6.5 Implement the secret-versus-public recording rule, so a `secret` export and a `secret` generated file appear as path references and their bytes appear nowhere in the plan; verify a test greps the serialised plan for the fixture's secret bytes and asserts they are absent
- [x] 6.6 Implement the plane recording: hashed environment for a value a unit reads from its environment, content hash plus reload targets for a rendered file, closure membership for a value interpolated into a store path; verify tests assert a file content change moves the content hash and not the closure, and an environment change moves the key and not the closure
- [x] 6.7 Add the re-keying warning row when a set-valued read's membership is part of the reading entry's key; verify a test adds a tag to a machine and asserts the reading entry's key changed and the warning row is present

## 7. The nix-unit suite

- [x] 7.1 Create `tests/default.nix` aggregating the suites and wire it to `pkgs.nix-unit` from the pinned nixpkgs at 2.35.1; verify `nix run .#checks.x86_64-linux.planner-tests` or the documented equivalent runs every test and exits non-zero when one fails
- [x] 7.2 Split the suites by subject — interfaces, composition, resolution, diagnostics, plan — with one test per specification scenario named after that scenario; verify each file evaluates on its own and that a deliberately broken expectation reports the test name plus both values
- [x] 7.3 Write the total-evaluation property test as `builtins.tryEval` over a deep force of a deployment carrying an unwired slot, a secret read, a keyset violation, an arity violation and an interface mismatch at once; verify the test asserts evaluation completed and that the table carries one row per mistake
- [x] 7.4 Write the source-text check that no file under `lib/` calls korora's raising entry point or a raise builtin; verify the check fails when a raising call is temporarily introduced and that the failure names the file
- [x] 7.5 Write the golden comparison helper that reports differing keys and fields rather than printing whole artifacts, and a separate documented regeneration command that is not run by the suite; verify a deliberate one-field drift reports that entry and field only, and that a failed comparison leaves the fixture on disk unchanged
- [x] 7.6 Create the scenario-to-test mapping file under `tests/` listing every scenario in this change's five specifications against its test name, with a reason recorded for each scenario deliberately not exercised, plus a check that fails on an unmapped scenario; verify the check fails when a scenario is added to a spec with no test and no recorded reason

## 8. Fixture reconciliation

- [x] 8.1 Evaluate `fixtures/minimal-typed-edge/deployment/` with fixture store path strings for `borgbackup` and `openssh`, and write the produced plan to a scratch file; verify the evaluation produces five entries, one per placement, and that the two entries the committed file elides are among them
- [x] 8.2 Diff the produced plan against `fixtures/minimal-typed-edge/plan/backup.json` field by field and record every difference in a reconciliation note under the change directory, sorted into placeholder, correction to the folder, and defect in the library; verify every difference appears in exactly one bucket and none is left unclassified
- [x] 8.3 Fix every difference in the defect bucket in `lib/`, re-run the diff, and confirm that bucket is empty; verify by re-reading the reconciliation note and the fresh diff together
- [x] 8.4 Stop and open a bead for any difference that means a construct in `fixtures/minimal-typed-edge/` is wrong rather than the library, naming the file and the construct; verify by listing the beads opened, or by recording that none was needed
- [x] 8.5 Replace `fixtures/minimal-typed-edge/plan/backup.json` with the reconciled plan carrying real hashes, real store path strings and all five entries, keeping the prose `note` fields; verify `jq -e .` parses it and that no value in it contains an ellipsis or an invented hash
- [x] 8.6 Move the `elided` block's explanation into `fixtures/minimal-typed-edge/README.md` and update that file's `Files` table row counts and its opening claim that the folder is not executable; verify the table's line counts match `wc -l` for every file it lists
- [x] 8.7 Add the golden plan test and the diagnostics row test comparing the worked deployment against the reconciled fixture and against the two rows `plan/diagnostics.txt` attributes to this deployment; verify both pass and that the diagnostics test asserts no third row is produced
- [x] 8.8 Add the test refusing a fixture that carries an ellipsis or an invented hash; verify it fails when an ellipsis is temporarily reintroduced into the fixture

## 9. Performance harness and budgets

- [x] 9.1 Create `perf/fleet.nix` generating a synthetic deployment as a pure function of fleet size, containing a set-valued read whose provider is placed on every machine; verify two generations at one size are equal and that the generator reads no time, filesystem or environment value
- [x] 9.2 Create `perf/measure.sh` running one evaluation per fixture under `NIX_SHOW_STATS_PATH`, forcing the plan deeply, writing one JSON result per fixture and size, and recording the interpreter version; verify the script passes `shellcheck` and `shfmt -d`, and that two runs over one fixture produce identical gated counters
- [x] 9.3 Create `perf/check.py` comparing results against budgets, gating on the reproducible counters and reporting wall clock, failing when a gated counter is not reproducible across the runs it was given; verify it passes `ruff format`, `ruff check` and `mypy`, and that it fails on a synthetic non-reproducible input
- [x] 9.4 Record budgets in `perf/budgets.json` as cost per plan entry, each with fixture name, interpreter version, date and the ratchet margin; verify the checker rejects an entry missing any of the four fields
- [x] 9.5 Implement the two-sided ratchet, with the below-budget failure message carrying the replacement figure ready to paste; verify a test lowers a measurement below margin and asserts the message contains the new figure
- [x] 9.6 Implement the growth bound across fleet sizes 4, 16, 64 and 256 with the bound stated in the budget file; verify the checker fails on a synthetic quadratic series at the largest size and passes on a linear one, and that the failure names the counter and the two sizes
- [x] 9.7 Add the harness to the flake's checks so the gate runs with the tests; verify a deliberate regression in `lib/` fails the check and that the failure names the counter, fixture, budget and measured value
- [x] 9.8 Confirm a measurement covers evaluation only, with no store write and no network; verify by running the harness with the network unavailable on a checkout whose evaluation caches are empty and comparing gated counters against a warm run

## 10. Verification

- [x] 10.1 Cross-walk every requirement and scenario across the five specifications to a test name in `tests/` or to a recorded omission, and confirm the mapping check from 7.6 passes; verify by running that check and reading its output
- [x] 10.2 Confirm that no construct in the folder's exclusion table is silently accepted, by writing one deployment per excluded construct and asserting each produces a row naming its trigger; verify the count of such deployments matches the count of rows in the README's exclusion table
- [x] 10.3 Run `nix fmt` and confirm the working tree is clean under the repository root, and run `nix flake check` restricted to the planner checks rather than the whole flake; verify both by inspecting `git status` and the check output
- [x] 10.4 Run `openspec validate implement-minimal-typed-edge --strict` and confirm it passes with the artifacts as implemented
- [x] 10.5 Update `universe-bki` with the reconciliation outcome and open the follow-on bead for the clan-core conversion the README's falsifiable claim names, depending on `universe-bki`; verify `bd show` prints both and that the dependency edge exists
