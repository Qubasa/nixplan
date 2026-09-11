## 1. Record what exists

- [ ] 1.1 List this change's four spec files under `excused` in `tests/unit/coverage.nix` with the
  reason the tree uses for an unimplemented change, and verify
  `nix build .#checks.x86_64-linux.planner-tests` reports no unclassified specification
- [ ] 1.2 Record the rendered unit file and the version digest of one fixture entry and one
  `tests/e2e/wired-pair` entry before any edit, so "unchanged for an entry that declares nothing" is
  compared against bytes rather than against a description
- [ ] 1.3 Record the current refusal text and account of `extensionFieldUnknown`
  (`image/read.nix:108-111,406`) and confirm by a throwaway `mkPlan` that a deployment declaring an
  unrenderable extension field is `applicable = true` today

## 2. The vocabulary

- [ ] 2.1 Add a `restartPolicy` atom over `no`, `on-failure`, `on-abnormal`, `always` to
  `lib/atoms.nix`, and verify a throwaway korora `verify` accepts the four and refuses a fifth
- [ ] 2.2 Add `restart` and `restartSec` to `unitVocabulary` in `lib/module.nix`, and verify a
  throwaway plan records both on a unit that declares them and neither on a unit that does not
- [ ] 2.3 Add the row for `restartSec` with no `restart`, and verify the row names the module and the
  unit and that the delay is not recorded
- [ ] 2.4 Add `unit-restart-contradicts-one-shot` and `unit-restart-on-scheduled`, and verify
  `oneShot` + `on-failure` produces no row while the two contradictions do
- [ ] 2.5 Verify the entry key moves when a policy is added and not otherwise, by planning the
  recorded fixture entry twice

## 3. Rendering

- [ ] 3.1 Render `Restart=`/`RestartSec=` in `renderUnit` (`image/read.nix`) from the recorded
  fields, and verify the rendered bytes of the entry recorded in 1.2 are unchanged when it declares
  neither
- [ ] 3.2 Verify the same unit rendered through `flakelet/read.nix` carries the directives and its
  `[Install]` section, with no second mapping table in that file
- [ ] 3.3 Extend the directive-table check so a plan field this realiser cannot render fails the
  build, and verify by removing one mapping in a throwaway edit that the build refuses rather than
  dropping the field

## 4. Configuration files whose bytes exist at build time

- [ ] 4.1 Change `hostPathsOf` so a `source` file's `from` is its own store path, and verify the
  rendered bind names the store path and the attach script stages nothing for it
- [ ] 4.2 Add the build-time assembly of a text-only `render` list in the shared reading, and verify
  the assembled bytes equal the concatenated literals and that the recorded `contentHash` still
  describes them
- [ ] 4.3 Show a text-only `render` file from the assembled store path under `image`, and verify the
  image carries the empty mount point and the attach script assembles nothing for it
- [ ] 4.4 Carry the assembled file in the flakelet artifact beside `meta.json` and `units/`, and
  verify an entry with no configuration file produces a byte-identical artifact to the one recorded
  in 1.2
- [ ] 4.5 Restate `pathRule` and `acceptsHostPath` in `flakelet/read.nix` over the narrowed rule, and
  verify a `source` file and a text-only `render` are accepted while a `ref`-bearing recipe is
  refused naming the reference
- [ ] 4.6 Verify the `ref`-bearing refusal is reported as a row by `operator/read.nix` first, and
  that `tests/unit/diagnostics.nix` still crosses every refusal against a row

## 5. The unrendered-field row

- [ ] 5.1 Add `operator-entry-extension-field-unrendered` to `operator/read.nix`, read off the
  stated realiser's own directive table rather than a list restated there, and verify a deployment
  declaring an unrenderable field is inapplicable and builds its plan, both tables and no artifact
- [ ] 5.2 Give `image/read.nix`'s `extensionFieldUnknown` account that row id, and verify
  `tests/unit/diagnostics.nix` passes with no refusal accounting for itself as unreported
- [ ] 5.3 Verify a field a realiser's table does carry produces no row, and that adding a mapping to
  the table needs no edit under `operator/`

## 6. Tests

- [ ] 6.1 Add the vocabulary scenarios to `tests/unit/module.nix` and the two contradiction rows to
  `tests/unit/diagnostics.nix`, and verify each fails against the pre-change tree
- [ ] 6.2 Add the rendering scenarios to `tests/unit/image.nix` and `tests/unit/flakelet.nix`,
  including the two "unchanged" cases against the bytes recorded in 1.2
- [ ] 6.3 Add the disposition scenarios: a `source` file accepted by both realisers, a text-only
  `render` accepted by both, a `ref`-bearing recipe refused by flakelet and assembled by `image`
- [ ] 6.4 Add the deployment-build scenarios to `tests/unit/operator.nix`
- [ ] 6.5 Register every new scenario in `tests/unit/coverage.nix`, move this change's spec files
  from `excused` to `accountable`, and verify the suite reports no unmapped scenario

## 7. On machines, and documents

- [ ] 7.1 Give `tests/e2e/shared-postgres/`'s server `restart = "on-failure"` with a `restartSec`,
  and add a scenario that kills the server's main process and observes it running again without an
  apply
- [ ] 7.2 Replace that folder's flag list with a `configData` file under flakelet, and verify the
  entry builds, the file is bound at the declared path, and the server reads it
- [ ] 7.3 Update `docs/authoring.md` (the vocabulary table and the two contradiction rows),
  `docs/flakelet.md` (which host paths are accepted and why), `docs/plan.md` and
  `docs/diagnostics.md` (three new row ids), and verify
  `nix build .#checks.x86_64-linux.treefmt` passes
- [ ] 7.4 Update `CLAUDE.md`: the flakelet refusal is now about when bytes exist, the restart domain
  and why it is four values, and remove the note that `shared-postgres` takes flags because flakelet
  refuses configuration files
- [ ] 7.5 Run `nix run .#planner-e2e -- shared-postgres wired-pair portable-image` and verify no
  folder regressed
