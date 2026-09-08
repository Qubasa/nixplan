## 1. Baseline

- [ ] 1.1 Record today's behaviour as a throwaway probe: a scenario module whose implementation writes `state.folders."/var/lib/probe" = { owner = "probe"; }` plus a `dump` hook, and a second module that instead sets the systemd unit-extension field for a state directory; verify the plan records nothing for the first (`implementation-unknown-key` naming `state`) and records the second only inside `units.<name>.extends`, and paste both observations into the task as the before-state
- [ ] 1.2 Capture the perf baseline with `bash perf/measure.sh`, keep its output, and verify `nix build .#checks.x86_64-linux.planner-perf -L` passes against the committed `perf/budgets.json` before anything changes

## 2. Types

- [ ] 2.1 Add `absolutePath` to `lib/atoms.nix` beside `unitRef` and `userName` — a string beginning with `/` and containing no `.` or `..` component — with a comment stating that a state folder is a path on a machine and not a store path; verify a nix-unit case asserts one accepted and one rejected value per malformed shape through `type.verify`
- [ ] 2.2 Add `stateDispositions = [ "durable" "derived" ]` to `lib/module.nix` beside `dispositions`, with a comment stating why it is a separate domain from a configuration file's; verify the domain is read by exactly one reader by grepping the library for it

## 3. The declaration reader

- [ ] 3.1 Add `"state"` to `implKeys` (`lib/module.nix:86-91`) and add `stateKeys = [ "folders" "dump" "restore" ]` and `stateFolderKeys = [ "owner" "disposition" ]`; verify a case asserts a module declaring one folder and both hooks reads back exactly those fields, and that a module declaring no `state` produces no state record
- [ ] 3.2 Add `readState` beside `readUnit`, reading `folders` as a path-keyed map of `{ owner ? null, disposition ? "durable" }` and dropping a folder that produced an error row; verify a case asserts a folder with no `owner` records none rather than null, and that an omitted `disposition` records `durable`
- [ ] 3.3 Emit `state-malformed` when `state` is not an attribute set and `state-unknown-key`/`state-excluded-key` for a key outside `stateKeys`, reusing the existing `keyRow` so an excluded key carries its construct's trigger; verify a case asserts each row and that the plan is still produced
- [ ] 3.4 Emit `state-folder-unknown-key`, `state-folder-path` for a key failing `atoms.absolutePath`, `state-folder-in-store` for a path under the entry's `storeDir`, `state-folder-disposition` for a value outside `stateDispositions`, and `state-folder-owner-type` for an owner failing `atoms.userName`; verify one case per row asserting the row id, that the row names the declaring subject and the path, and that the offending folder is absent from the entry
- [ ] 3.5 Read `dump` and `restore` as unit references checked against the units the same module declared, emitting `state-hook-unknown` naming the hook, the name used and the declared units; verify a case asserts a hook naming an own unit is recorded and a hook naming a stranger's unit is a row with no hook recorded

## 4. Checks that need the target

- [ ] 4.1 Emit `state-directive-conflict` when a module declares a state folder and also applies a service manager's unit extension field for the same directive on one of its units, naming the folder, the unit and the field; verify a case asserts the row and that the entry still records the folder, so the declaration remains the single source
- [ ] 4.2 Emit `state-folder-owner-required` when an entry's `target.serviceManager` expresses a folder only for a named account — a durable folder outside the location that manager owns for state — and no `owner` was declared, naming the path, the machine and the service manager; verify a case asserts the row for a `/srv/...` folder on a systemd target and no row for the same folder with an owner

## 5. The plan entry

- [ ] 5.1 Record `state` in `placedEntry` (`lib/plan.nix:440-513`) as `{ folders, dump?, restore? }` with the absence rule applied so an entry declaring nothing carries no field, and add the record to `keyInput` (`:454-471`); verify a case asserts a folder path change moves that entry's key, an owner change moves it, and a neighbouring entry's key is unchanged
- [ ] 5.2 Verify the entry survives serialisation by extending the round-trip case in `tests/suites/plan.nix` to a plan carrying a state declaration, and assert an unplaced member's entry carries no state field

## 6. The machine-scope collision check

- [ ] 6.1 Add the post-placement check that two entries on one machine claim neither the same state folder nor nested folders, emitting `state-folder-collision` naming both entries and both paths, in the round that already has placement output beside the port-claim checks; verify cases assert the row for an identical path, the row for a nested path, and no row for the same path on two different machines

## 7. The rendered unit

- [ ] 7.1 Render the state directives in `image/read.nix` beside the environment and bind lines: a durable folder under `/var/lib` as `StateDirectory=` with the name relative to it, a derived folder under `/var/cache` as `CacheDirectory=`, and a declared `owner` as `User=`; verify a `tests/python/test_image.py` case asserts the rendered unit file's bytes contain the directives and that a unit whose entry declares no state is byte-identical to today's
- [ ] 7.2 Raise on a state declaration the builder cannot render — a folder needing an owner that has none, and a disposition outside the domain — naming the entry, the path and the field, the way `read.nix`'s other refusals raise; verify a case asserts each raise and its message names the entry and the path
- [ ] 7.3 Verify state participates in the image's identity: a byte-level case asserting two builds of one entry declaring state are identical, that changing the owner changes that entry's image, and that no other entry's image changes

## 8. The worked example and the fixture

- [ ] 8.1 Declare state in the worked example — `fixtures/minimal-typed-edge/modules/borg-repo/server.nix` writes `/srv/borg`, which needs an owner on a systemd target — with a comment stating why the declaration is not an export in this change and naming the excluded construct it would force; verify the example's diagnostics file is unchanged apart from rows this change intends
- [ ] 8.2 Regenerate the committed fixture with `python3 tests/regenerate.py` and re-measure the budgets with `bash perf/measure.sh`, recording which counters moved and why; verify `nix build .#checks.x86_64-linux.planner-perf -L` and the golden comparison both pass

## 9. Documentation

- [ ] 9.1 Document the `state` key on the implementation surface in `docs/authoring.md` beside `configData`: the shape, that the path is the identity, that hooks are the module's own units, that `derived` exists so a snapshot skips a cache, and that the declaration is the source from which a backend directive is rendered rather than a second spelling of one
- [ ] 9.2 Add `state` to the entry field table and the key contract in `docs/plan.md` (`:44-70`, `:210-225`), stating which readers the field exists for and that it names no service manager
- [ ] 9.3 Add every new row id to `docs/diagnostics.md`; verify `suites/source.nix::testEveryRowIsInTheReference` passes, which reads the library's own source rather than this list
- [ ] 9.4 Add a paragraph to `notes/clan-portable-services-design.md` §16.7 or beside §32.5 recording the decision that state is a declared plan fact and not an export in this change, naming `excluded.constructs.locality` as the trigger a `provides.state` would force and the follow-up change that lands it

## 10. Verification

- [ ] 10.1 Add one `tests/mapping.nix` entry per new spec heading and cross-walk every scenario in this change's three spec files to the case that exercises it, recording any deliberate omission with its reason; verify `nix eval --json .#planner.failuresBySuite` is empty
- [ ] 10.2 Run `openspec validate declare-service-state --strict` and confirm it passes with the artifacts as implemented
- [ ] 10.3 Run `nix build .#checks.x86_64-linux.planner-tests .#checks.x86_64-linux.planner-scenarios .#checks.x86_64-linux.planner-python .#checks.x86_64-linux.planner-perf .#checks.x86_64-linux.planner-images -L`, then `nix fmt`; verify all pass and that formatting touched only files this change edited
