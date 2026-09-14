## 1. Record what exists

- [ ] 1.1 Record, with a throwaway `mkPlan`, that a unit declaring `command = "x\nUser=root"` is
  planned with `applicable = true` and renders a `[Service]` section carrying that second line, and
  that the same value in `env.X` is `unit-env-value-newline`. This is the red evidence the
  generalised rule is measured against; keep the rendered bytes.
- [ ] 1.2 Record that a `configData` attribute name of `"/etc/x$(id -u).conf"` reaches
  `image/default.nix`'s attach script unescaped, by building one entry of a throwaway deployment and
  reading `passthru.attach`. Keep the rendered line so task 5.1 can be compared against it.
- [ ] 1.3 Record what nix does with a derived unit file name carrying `?` - a store name nix admits -
  and with one carrying a space, and confirm neither abort names the entry or the declaration. Keep
  both messages.
- [ ] 1.4 Record the version digest and the rendered unit bytes of one `fixtures/minimal-typed-edge`
  entry and of `watch:file` of `tests/e2e/portable-image`, so that "no golden and no digest moves" is
  compared against bytes rather than against a description.

## 2. A value a unit file cannot carry, for every field

- [ ] 2.1 Replace the `record.env` scan in `lib/module.nix:769-775` with a walk of every string the
  recorded unit carries at any depth, including each field of each extension application under
  `extends`, and verify against 1.1 that the walk reports the command, the environment value and an
  extension field value, and reports nothing for a value withheld by `withheld`
  (`lib/module.nix:714-718`).
- [ ] 2.2 Replace the row at `lib/module.nix:829-838` with `unit-value-newline`, naming the entry,
  the unit and the field path the value sits at, built with `diag.error`. Verify the message names
  `command` for a command and `env.X` for an environment value, and that no message says
  "environment assignment" for a field that is not one.
- [ ] 2.3 Verify the nine fields whose atoms are grammars earn no second row: plan a unit declaring
  `user = "root\nPrivateUsers=no"` and assert exactly one row, `unit-field-type-mismatch`, and that
  the value is not recorded.
- [ ] 2.4 Generalise the realiser's scan and refusal (`image/read.nix:600-614`, `:634-638`) the same
  way, reading the same record, and move the account's id (`image/read.nix:155`) to
  `unit-value-newline`. Verify a throwaway `image.build` of the 1.1 entry refuses naming the entry,
  the unit and the field, and that `tests/unit/diagnostics.nix`'s refusal-versus-row cross-walk is
  green.
- [ ] 2.5 Add `testANewlineInACommandIsARow`, `testANewlineInAnExtensionValueIsTheSameRow`,
  `testANewlineInAUserNameIsReportedOnceByItsType` and `testAValueCarryingASpaceAndAQuoteIsNoRow` to
  `tests/unit/plan.nix`, and `testACommandCarriesANewline` to `tests/unit/image.nix`. Verify each is
  red against the unpatched tree and green after 2.1-2.4.
- [ ] 2.6 Move the existing `unit-env-value-newline` assertions at `tests/unit/plan.nix:1307-1319`
  and `tests/unit/image.nix:660-669` onto the new identifier rather than adding assertions beside
  them, keeping `testAnEnvironmentValueCarriesASpace` and `testAnEnvironmentValueCarriesANewline` as
  the scenarios they answer. Verify no suite names the old identifier
  (`grep -r unit-env-value-newline` finds only `openspec/`).

## 3. The grammar a rendered step can carry

- [ ] 3.1 Add the one statement of the renderable-word grammar to `lib/util.nix` beside
  `keySeparators` (`lib/util.nix:69-82`), as the rule, the admitted character list and the predicate,
  copied verbatim from `secrets/read.nix:53-70` including the reason. Verify by a throwaway
  evaluation that the predicate answers identically to `secrets/read.nix`'s `unrenderable` on
  `/run/vars/a/b/c`, `a b`, `a"b` and `a$(b)`.
- [ ] 3.2 Have `secrets/read.nix` read `wordRule` and `wordAdmits` off `planner.util` instead of
  stating them, and verify `secrets-rendered-word-refused` keeps its identifier, its subject and its
  sentence: the existing secrets suite scenario for it stays green with no edit.
- [ ] 3.3 Add `config-file-path-refused` (error) to `readConfigFile` (`lib/module.nix:872-985`),
  naming the entry, the path and what the grammar admits, and leave the refused file out of the
  returned record. Verify with a throwaway deployment declaring two configuration files, one refused:
  the other file, the units and the closure are recorded unchanged and the refused path appears in no
  field of `plan`.
- [ ] 3.4 Verify the subject of the row is one a rendered table can carry - a plan key, not the
  offending path - so `diagnostic-subject-invalid` cannot be earned by reporting a bad path, and the
  path travels in the message.
- [ ] 3.5 Add `testANewlineInAConfigurationFilePathIsARow`,
  `testAConfigurationFilePathCarryingAShellMetacharacterIsARow`,
  `testAConfigurationFilePathCarryingAQuoteIsARow`, `testARefusedPathIsLeftOutOfTheEntryRecord` and
  `testOneGrammarAnswersForBothRenderedSteps` to `tests/unit/plan.nix`. Verify each is red before 3.3
  and green after; the last one asserts that the library's predicate and the secrets reading's are
  one value rather than two equal ones.

## 4. The name this realiser derives

- [ ] 4.1 Add `acceptsName`, `nameRule`, `acceptsUnit` and `unitRule` to `image/read.nix`'s exported
  set (`image/read.nix:409-424`), written as the sentence a refusal prints, admitting a leading ASCII
  alphanumeric followed by ASCII alphanumerics, `_`, `-` and `.`. Verify each name in the tree is
  admitted: `vault-repo-server`, `watch-file`, `mirror-copy`, and every unit file name they derive.
- [ ] 4.2 Refuse a derived service name or unit file name outside the rule in `image/read.nix`'s
  `read`, with an account naming `operator-entry-name-refused`. Verify against 1.3 that the refusal
  names the entry, the derived name and the rule, and that it is reached before the store name is
  built.
- [ ] 4.3 Change `refusedNames` in `operator/read.nix:167-176` to ask the stated realiser for its two
  rules rather than testing `realiser == "flakelet"`, and verify a deployment stating `image` for an
  entry whose instance name carries `?` is inapplicable, carries one
  `operator-entry-name-refused` row naming the entry and the rule, builds both tables and no
  artifact.
- [ ] 4.4 Add `testAUnitNameOutsideTheRuleIsRefusedNamingTheEntry`, `testTheNameRefusalIsPrecededByItsRow`
  and `testANameTheRuleAdmitsBuilds` to `tests/unit/image.nix` and `tests/unit/operator.nix` as the
  layer each belongs to. Verify the first two are red before 4.2 and 4.3, and that
  `operator.testANameTheEndpointRefusesIsARowBeforeItIsARaise` (`tests/unit/operator.nix:1239`),
  which is the flakelet half of the same rule, stays green with no edit.

## 5. What a generated script carries

- [ ] 5.1 Escape the path in all six messages of `image/default.nix` (`:154`, `:196`, `:209`, `:263`,
  `:315`, `:389-394`), and verify against 1.2 that the rendered attach script carries the path as an
  escaped word in the message as well as in the argument beside it.
- [ ] 5.2 Escape the unit list word by word at `image/default.nix:332`, `:344`, `:345` and `:360`,
  and verify the rendered script carries one escaped word per unit and that the detach and attach
  scripts of `watch:file` differ from 1.4's recording only in those lines.
- [ ] 5.3 Change `install -d -m 0755` to `0711` at `image/default.nix:191` and `:324`, and verify by
  running the artifact's own attach script under a `PORTABLE_PLANNER_ROOT` of a throwaway directory
  - the way `tests/e2e/portable-image` does - that the staging tree is `0711` and each staged file
  carries its own declared mode.
- [ ] 5.4 Add `testEveryPathAGeneratedScriptNamesIsEscaped`, `testAUnitListIsEscapedWordByWord` and
  `testTheStagingDirectoryIsTraversableAndNotListable` to `tests/unit/image.nix`, each reading the
  rendered script text of a built entry. Verify each is red before 5.1-5.3.
- [ ] 5.5 Add `test_a_staged_file_is_readable_through_a_directory_nobody_may_list` to
  `tests/e2e/portable-image/test_portable_image.py`, in the phase that already runs the attach script
  on a machine, asserting the unit reads its staged file while listing the staging directory as an
  unprivileged account is refused. Verify with `nix run .#planner-e2e portable-image`.
- [ ] 5.6 Verify no version digest moved: the digest recorded in 1.4 is unchanged, because the digest
  is over the plan facts the artifact holds and not over the script's bytes
  (`image/read.nix:447-486`). Record the digests compared.

## 6. Registration and documentation

- [ ] 6.1 Move `refuse-a-value-a-unit-file-cannot-carry/specs/planner/diagnostics/spec.md` and
  `.../specs/realiser/portable-service-image/spec.md` from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse expires the moment a task of this change is ticked - and
  verify the scenario cross-walk is green: every scenario heading finds the test name it derives, in
  exactly one layer.
- [ ] 6.2 Update `docs/diagnostics.md`: replace `unit-env-value-newline` at `:176` with
  `unit-value-newline` described as every field a unit file carries, add `config-file-path-refused`
  to the `config-file-*` rows at `:180-183`, and add `acceptsName` and `acceptsUnit` of
  `image/read.nix` to the list of rules a reading asks each realiser for at `:60-62`. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
- [ ] 6.3 Record in `CLAUDE.md`: under Diagnostics, that the newline rule is about every string a
  unit record carries at any depth and why one identifier covers every field; that a configuration
  file's host path is held to the renderable-word grammar whose one home is `lib/util.nix`, and that
  a refused path is left out of the record; under Realisers, that each realiser states its own name
  rule and the reading asks the stated one rather than testing which it is, and that the staging
  directory is `0711` for the reason the value directories are. Verify the file still lints.
- [ ] 6.4 Verify `docs/authoring.md` says nothing that contradicts the two new rules, and add the
  path grammar where it documents `configData`. Verify by reading the rendered document, and by
  `nix build .#checks.x86_64-linux.treefmt`.

## 7. Verification

- [ ] 7.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including `tests/unit/diagnostics.nix`'s purity scan - no `throw`, `abort`, `assert`, `.check ` or
  `korora.check` enters `lib/*.nix` - and its refusal-versus-row cross-walk over the two changed
  accounts.
- [ ] 7.2 Verify the golden plan and the golden diagnostics table are byte-equal to what is
  committed: `nix eval --json .#debug.worked.plan | jq -S .` against
  `fixtures/minimal-typed-edge/plan/*`, and `diagnostics.txt` unchanged. No fixture path or name is
  outside either grammar, so nothing here may move.
- [ ] 7.3 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold: the
  record walk of task 2.1 is a new per-unit cost and `perf/mesh.nix` holds the tree's largest unit
  records. Record the measured cost per entry for sizes 64 and 256 if the margin moved by more than
  half of the 0.15 allowance.
- [ ] 7.4 Run `nix run .#planner-e2e -- portable-image shared-postgres wired-pair` and verify no
  folder regressed: the image folder covers the escaped scripts and the narrowed staging directory,
  and the other two cover an entry the three rules do not concern.
