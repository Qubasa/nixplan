## 1. Record what exists

- [x] 1.1 Record, with a throwaway `mkPlan`, that a unit declaring `command = "x\nUser=root"` is
  planned with `applicable = true` and renders a `[Service]` section carrying that second line, and
  that the same value in `env.X` is `unit-env-value-newline`. This is the red evidence the
  generalised rule is measured against; keep the rendered bytes.
  - At `b7dd7e1`, a throwaway probe over a checkout of the base: `command` newline gives
    `applicable = true`, `rows = []`, and `renderUnit` produces
    `[Service]\nExecStart=…/bin/borg serve\nUser=root\nPrivateUsers=no\n` - two directives the
    module wrote and the vocabulary never declared. `env.X = "a\nUser=root"` gives
    `applicable = false`, `rows = ["unit-env-value-newline"]`.
- [x] 1.2 Record that a `configData` attribute name of `"/etc/x$(id -u).conf"` reaches
  `image/default.nix`'s attach script unescaped, by building one entry of a throwaway deployment and
  reading `passthru.attach`. Keep the rendered line so task 5.1 can be compared against it.
  - At `b7dd7e1` the attach script carries `echo "assembled /etc/x$(id -u).conf"`,
    `fail "the reference … that /etc/x$(id -u).conf is assembled from …"` and
    `install -d -m 0755 "$root$(dirname '/run/…/etc/x$(id -u).conf')"`; the check script carries
    `echo "config /etc/x$(id -u).conf current"`. Each is a command substitution the machine runs as
    root. The planner recorded the path with no row and `applicable = true`.
- [x] 1.3 Record what nix does with a derived unit file name carrying `?` - a store name nix admits -
  and with one carrying a space, and confirm neither abort names the entry or the declaration. Keep
  both messages.
  - `?`: the plan is applicable with no row, nix accepts the store name, and the build dies in the
    image root builder with `mkdir: missing operand` (the `?` glob expanded to nothing).
  - A space: nix rewrites the *derivation* name to `sv-c-only-img-…` while the unit file keeps the
    space, and mksquashfs dies with
    `Cannot stat source directory ".../sv-c-only-img-5dc6814fa678619e/sv" because No such file or directory`.
  - Neither message names the entry or the declaration.
- [x] 1.4 Record the version digest and the rendered unit bytes of one `fixtures/minimal-typed-edge`
  entry and of `watch:file` of `tests/e2e/portable-image`, so that "no golden and no digest moves" is
  compared against bytes rather than against a description.
  - `vault-repo:server@vault` `5779f65711249b33`, `nightly:client@alpha` `f9c5abc5de99c60d`,
    `watch:file@alpha` `bcd4e274769be7b8`, `mirror:copy@elsewhere` `ee80d28a6fc47880`, with each
    entry's rendered unit bytes and `watch:file`'s attach, detach and check scripts kept.

## 2. A value a unit file cannot carry, for every field

- [x] 2.1 Replace the `record.env` scan in `lib/module.nix:769-775` with a walk of every string the
  recorded unit carries at any depth, including each field of each extension application under
  `extends`, and verify against 1.1 that the walk reports the command, the environment value and an
  extension field value, and reports nothing for a value withheld by `withheld`
  (`lib/module.nix:714-718`).
  - `util.stringsDeep` beside `storePathsDeep`, filtered by `util.carriesLineBreak`. The scan reads
    `record`, which is `typed` minus `withheld`, so a withheld value is not walked;
    `plan.testANewlineInAUserNameIsReportedOnceByItsType` asserts the one-row half.
- [x] 2.2 Replace the row at `lib/module.nix:829-838` with `unit-value-newline`, naming the entry,
  the unit and the field path the value sits at, built with `diag.error`. Verify the message names
  `command` for a command and `env.X` for an environment value, and that no message says
  "environment assignment" for a field that is not one.
  - `unit `say` … sets `command` to a value containing a line break`, evidence "a unit file is line
    oriented, so a value it carries has no second line to put the rest on, whatever field the value
    sits at". `plan.testANewlineInACommandIsARow` asserts the evidence carries no "environment".
- [x] 2.3 Verify the nine fields whose atoms are grammars earn no second row: plan a unit declaring
  `user = "root\nPrivateUsers=no"` and assert exactly one row, `unit-field-type-mismatch`, and that
  the value is not recorded.
  - `plan.testANewlineInAUserNameIsReportedOnceByItsType`: rows `["unit-field-type-mismatch"]`, the
    recorded unit's fields are `["command"]`.
- [x] 2.4 Generalise the realiser's scan and refusal (`image/read.nix:600-614`, `:634-638`) the same
  way, reading the same record, and move the account's id (`image/read.nix:155`) to
  `unit-value-newline`. Verify a throwaway `image.build` of the 1.1 entry refuses naming the entry,
  the unit and the field, and that `tests/unit/diagnostics.nix`'s refusal-versus-row cross-walk is
  green.
  - `image.testACommandCarriesANewline` asserts the raise and that `renderUnit` raises with it.
    `diagnostics.testARealiserRefusesAConditionNoRowReports` is green at 38 refusals (36 before:
    the two new image name refusals).
- [x] 2.5 Add `testANewlineInACommandIsARow`, `testANewlineInAnExtensionValueIsTheSameRow`,
  `testANewlineInAUserNameIsReportedOnceByItsType` and `testAValueCarryingASpaceAndAQuoteIsNoRow` to
  `tests/unit/plan.nix`, and `testACommandCarriesANewline` to `tests/unit/image.nix`. Verify each is
  red against the unpatched tree and green after 2.1-2.4.
  - Red at `b7dd7e1` (the same suite files copied onto a base checkout):
    `testANewlineInACommandIsARow`, `testANewlineInAnExtensionValueIsTheSameRow`,
    `testACommandCarriesANewline`. The other two are **green at the base too, and necessarily so**:
    they assert the rule does *not* over-report, which is the half a base with no rule already
    satisfies. Kept as the guard against the new walk producing a second row.
- [x] 2.6 Move the existing `unit-env-value-newline` assertions at `tests/unit/plan.nix:1307-1319`
  and `tests/unit/image.nix:660-669` onto the new identifier rather than adding assertions beside
  them, keeping `testAnEnvironmentValueCarriesASpace` and `testAnEnvironmentValueCarriesANewline` as
  the scenarios they answer. Verify no suite names the old identifier
  (`grep -r unit-env-value-newline` finds only `openspec/`).
  - Both moved in place, `` `MOTD` `` and `` `PEM` `` becoming `` `env.MOTD` `` and `` `env.PEM` ``.
    `grep -rn unit-env-value-newline` outside `openspec/` finds nothing.

## 3. The grammar a rendered step can carry

- [x] 3.1 Add the one statement of the renderable-word grammar to `lib/util.nix` beside
  `keySeparators` (`lib/util.nix:69-82`), as the rule, the admitted character list and the predicate,
  copied verbatim from `secrets/read.nix:53-70` including the reason. Verify by a throwaway
  evaluation that the predicate answers identically to `secrets/read.nix`'s `unrenderable` on
  `/run/vars/a/b/c`, `a b`, `a"b` and `a$(b)`.
  - Both answer `[false true true true]` on those four words.
- [x] 3.2 Have `secrets/read.nix` read `wordRule` and `wordAdmits` off `planner.util` instead of
  stating them, and verify `secrets-rendered-word-refused` keeps its identifier, its subject and its
  sentence: the existing secrets suite scenario for it stays green with no edit.
  - `secrets.testAnAddressTheRenderedStepCannotCarryIsARow` compares the whole row and is green
    unedited.
- [x] 3.3 Add `config-file-path-refused` (error) to `readConfigFile` (`lib/module.nix:872-985`),
  naming the entry, the path and what the grammar admits, and leave the refused file out of the
  returned record. Verify with a throwaway deployment declaring two configuration files, one refused:
  the other file, the units and the closure are recorded unchanged and the refused path appears in no
  field of `plan`.
  - `plan.testARefusedPathIsLeftOutOfTheEntryRecord`, plus a throwaway build where the entry's whole
    `configData` key disappears when its only file is refused.
- [x] 3.4 Verify the subject of the row is one a rendered table can carry - a plan key, not the
  offending path - so `diagnostic-subject-invalid` cannot be earned by reporting a bad path, and the
  path travels in the message.
  - Subject `svc:only@one`; the path is in the message and the resolution.
- [x] 3.5 Add `testANewlineInAConfigurationFilePathIsARow`,
  `testAConfigurationFilePathCarryingAShellMetacharacterIsARow`,
  `testAConfigurationFilePathCarryingAQuoteIsARow`, `testARefusedPathIsLeftOutOfTheEntryRecord` and
  `testOneGrammarAnswersForBothRenderedSteps` to `tests/unit/plan.nix`. Verify each is red before 3.3
  and green after; the last one asserts that the library's predicate and the secrets reading's are
  one value rather than two equal ones.
  - The first four are in `tests/unit/plan.nix` and all four are red at `b7dd7e1`.
  - **Moved**: `testOneGrammarAnswersForBothRenderedSteps` is in `tests/unit/diagnostics.nix`
    instead. `tests/unit/plan.nix` is handed no `secretsSource` and no `libSource`, and the
    assertion needs both; the diagnostics suite is the one that already crosses "one rule, one
    home" and is handed every reading. **Design changed**: two Nix functions are never `==`, even
    when one is `inherit`ed from the other (`(let f = x: x; in { inherit f; }).f == f` is `false`),
    so "one value rather than two equal ones" cannot be asserted by equality. The test asserts it
    the way the tree already asserts a single home: the grammar literal appears in exactly one of
    `lib/**`, `operator/read.nix`, `secrets/read.nix`, `image/read.nix` and `flakelet/read.nix`,
    namely `lib/util.nix`, and the library's predicate, the secrets reading's and the
    configuration-file row agree word for word.

## 4. The name this realiser derives

- [x] 4.1 Add `acceptsName`, `nameRule`, `acceptsUnit` and `unitRule` to `image/read.nix`'s exported
  set (`image/read.nix:409-424`), written as the sentence a refusal prints, admitting a leading ASCII
  alphanumeric followed by ASCII alphanumerics, `_`, `-` and `.`. Verify each name in the tree is
  admitted: `vault-repo-server`, `watch-file`, `mirror-copy`, and every unit file name they derive.
  - `image.testANameTheRuleAdmitsBuilds` admits the three and a `borg-repo.v2` unit's own
    `.service` and `.timer`. A scan of every placed entry of `fixtures/minimal-typed-edge`, the two
    perf fixtures and all eight e2e deployment builds finds no derived name, unit file name or
    `configData` path outside either new grammar.
- [x] 4.2 Refuse a derived service name or unit file name outside the rule in `image/read.nix`'s
  `read`, with an account naming `operator-entry-name-refused`. Verify against 1.3 that the refusal
  names the entry, the derived name and the rule, and that it is reached before the store name is
  built.
  - `operator.testAUnitNameOutsideTheRuleIsRefusedNamingTheEntry`. The refusal is the first branch
    of `read`, above `entryRealisesNothing`, so no derivation name exists when it fires.
  - **Caveat, recorded rather than fixed**: `flakelet/read.nix` delegates to this same `read`, so a
    flakelet entry whose unit attribute name carries `@` is now refused by the image reading with
    no `operator-entry-name-refused` row above it - `operator/read.nix` asks flakelet, whose own
    rule admits one `@`. That entry does not build today either: `flakelet/default.nix` names a
    derivation after the unit file and nix refuses `@` in a store name. The message is strictly
    better than the nix-level abort it replaces, and narrowing flakelet's own unit rule is outside
    this change (design.md: "No change to `flakelet/read.nix`'s name rule").
- [x] 4.3 Change `refusedNames` in `operator/read.nix:167-176` to ask the stated realiser for its two
  rules rather than testing `realiser == "flakelet"`, and verify a deployment stating `image` for an
  entry whose instance name carries `?` is inapplicable, carries one
  `operator-entry-name-refused` row naming the entry and the rule, builds both tables and no
  artifact.
  - `operator.testAUnitNameOutsideTheRuleIsRefusedNamingTheEntry`: one row, subject
    `sv?c:only@one`, message carrying `imageReader.nameRule`, `reading.refused = true` so
    `operator/default.nix` links the two tables and the artifact of no entry.
  - Consequence, fixed in the same commit: `operator.testAMemberIsNamedInsideTheValueNamespace`
    stated `image` precisely because flakelet refused `svc-vars/x` and the image realiser was asked
    nothing. Both endpoints now refuse it, so the test expects the row and its comment says why;
    its own claim - a record is classified by what it records - is untouched.
- [x] 4.4 Add `testAUnitNameOutsideTheRuleIsRefusedNamingTheEntry`, `testTheNameRefusalIsPrecededByItsRow`
  and `testANameTheRuleAdmitsBuilds` to `tests/unit/image.nix` and `tests/unit/operator.nix` as the
  layer each belongs to. Verify the first two are red before 4.2 and 4.3, and that
  `operator.testANameTheEndpointRefusesIsARowBeforeItIsARaise` (`tests/unit/operator.nix:1239`),
  which is the flakelet half of the same rule, stays green with no edit.
  - The first two are in `tests/unit/operator.nix` (they need the row and the raise together), the
    third in `tests/unit/image.nix`. All three are stronger than red at `b7dd7e1`: they name
    `imageReader.nameRule` and `imageReader.accounts.nameRefused`, which the base does not define,
    so the base cannot evaluate them at all. The flakelet half is green, unedited.

## 5. What a generated script carries

- [x] 5.1 Escape the path in all six messages of `image/default.nix` (`:154`, `:196`, `:209`, `:263`,
  `:315`, `:389-394`), and verify against 1.2 that the rendered attach script carries the path as an
  escaped word in the message as well as in the argument beside it.
  - All six go through `escapedWord`, which closes the double-quoted string around a
    `quoted`-always word. The rendered bytes a machine prints are unchanged, because the quotes are
    shell syntax: the throwaway run below printed `assembled /etc/thing.conf`.
    `image.testEveryPathAGeneratedScriptNamesIsEscaped` asserts no occurrence of a path sits inside
    a double-quoted region of the attach, detach or check script.
- [x] 5.2 Escape the unit list word by word at `image/default.nix:332`, `:344`, `:345` and `:360`,
  and verify the rendered script carries one escaped word per unit and that the detach and attach
  scripts of `watch:file` differ from 1.4's recording only in those lines.
  - `image.testAUnitListIsEscapedWordByWord`. Diffed against 1.4: the attach script differs in
    exactly the six escaped messages, the two `systemctl` unit lists, the `started` message and the
    `install -d` line; the detach script in its one `systemctl stop`; the check script in its eight
    messages. Nothing else moved.
- [x] 5.3 Change `install -d -m 0755` to `0711` at `image/default.nix:191` and `:324`, and verify by
  running the artifact's own attach script under a `PORTABLE_PLANNER_ROOT` of a throwaway directory
  - the way `tests/e2e/portable-image` does - that the staging tree is `0711` and each staged file
  carries its own declared mode.
  - **Design changed, recorded here**: the per-file `install -d` inside `assemble` is gone rather
    than re-moded. It spelled the parent as `"$root$(dirname '<path>')"`, which is a command
    substitution over an interpolated path - the sharpest instance of the defect in 1.2 - and
    `install -d` creates intermediate components at the umask and not at `-m`, so a mode named for
    the leaf alone left `files/` and `files/etc/` listable. The attach script now names every
    component of the tree in one `install -d -m 0711`.
  - Run under `PORTABLE_PLANNER_ROOT=/tmp/pa/root` with `umask 000`, stubbed `portablectl` and
    `systemctl`: `/run/portable-planner`, `…/svc-only`, `…/files` and `…/files/etc` are all `711`
    and the staged file is `444`, its declared mode.
- [x] 5.4 Add `testEveryPathAGeneratedScriptNamesIsEscaped`, `testAUnitListIsEscapedWordByWord` and
  `testTheStagingDirectoryIsTraversableAndNotListable` to `tests/unit/image.nix`, each reading the
  rendered script text of a built entry. Verify each is red before 5.1-5.3.
  - All three red at `b7dd7e1`. Reading a rendered script in a pure evaluation needed two things:
    `tests/unit/image.nix` now imports `image/default.nix` against a stub `pkgs` whose builders
    answer with the same keyed fake store path `assemble` already answers with, except
    `writeShellScript`, which answers with its text; and nixpkgs' own `lib` is threaded to that one
    suite as `nixpkgsLib`, because `lib.escapeShellArg` is what the build spends and a suite
    measuring the escaping against a restatement of it would be measuring its own copy.
- [x] 5.5 Add `test_a_staged_file_is_readable_through_a_directory_nobody_may_list` to
  `tests/e2e/portable-image/test_portable_image.py`, in the phase that already runs the attach script
  on a machine, asserting the unit reads its staged file while listing the staging directory as an
  unprivileged account is refused. Verify with `nix run .#planner-e2e portable-image`.
  - Added beside the other cases of the `assembling` phase. It asserts the entry's own staging
    directory and the leaf holding the file are both `711`, that `nobody` reads the staged file by
    its full path, and that `nobody` may list neither directory. `nix run .#planner-e2e
    portable-image`: 36 passed (35 before this case).
- [x] 5.6 Verify no version digest moved: the digest recorded in 1.4 is unchanged, because the digest
  is over the plan facts the artifact holds and not over the script's bytes
  (`image/read.nix:447-486`). Record the digests compared.
  - `watch:file@alpha` `bcd4e274769be7b8` and `mirror:copy@elsewhere` `ee80d28a6fc47880`, both
    equal to 1.4. `vault-repo:server@vault` `5779f65711249b33` and `nightly:client@alpha`
    `f9c5abc5de99c60d`, both equal, with their rendered unit bytes byte-equal too.

## 6. Registration and documentation

- [x] 6.1 Move `refuse-a-value-a-unit-file-cannot-carry/specs/planner/diagnostics/spec.md` and
  `.../specs/realiser/portable-service-image/spec.md` from `excused` to `accountable` in
  `tests/unit/coverage.nix` - the excuse expires the moment a task of this change is ticked - and
  verify the scenario cross-walk is green: every scenario heading finds the test name it derives, in
  exactly one layer.
  - `coverage.testAScenarioGainsNoTest` and `coverage.testEverySpecificationIsClassified` green.
- [x] 6.2 Update `docs/diagnostics.md`: replace `unit-env-value-newline` at `:176` with
  `unit-value-newline` described as every field a unit file carries, add `config-file-path-refused`
  to the `config-file-*` rows at `:180-183`, and add `acceptsName` and `acceptsUnit` of
  `image/read.nix` to the list of rules a reading asks each realiser for at `:60-62`. Verify
  `nix build .#checks.x86_64-linux.treefmt` passes, vale included.
  - Done; `diagnostics.testTheLibraryGainsARow` and `testADocumentTabulatesARowTheTreeCannotProduce`
    are green, and treefmt exits 0.
- [x] 6.3 Record in `CLAUDE.md`: under Diagnostics, that the newline rule is about every string a
  unit record carries at any depth and why one identifier covers every field; that a configuration
  file's host path is held to the renderable-word grammar whose one home is `lib/util.nix`, and that
  a refused path is left out of the record; under Realisers, that each realiser states its own name
  rule and the reading asks the stated one rather than testing which it is, and that the staging
  directory is `0711` for the reason the value directories are.
  - Two bullets under Diagnostics, three under Realisers (the third records the escaping rule and
    that `lib.escapeShellArg` leaves a safe-looking word bare). The file lints.
- [x] 6.4 Verify `docs/authoring.md` says nothing that contradicts the two new rules, and add the
  path grammar where it documents `configData`. Verify by reading the rendered document, and by
  `nix build .#checks.x86_64-linux.treefmt`.
  - Nothing contradicted it: the unit vocabulary section already refuses a raw stanza as
    `implementation-unknown-key`. Added "A unit file is line oriented" under the vocabulary and
    "A host path is one shell word" under Configuration files.

## 7. Verification

- [x] 7.1 Run `nix build .#checks.x86_64-linux.planner-tests` and verify every suite is green,
  including `tests/unit/diagnostics.nix`'s purity scan - no `throw`, `abort`, `assert`, `.check ` or
  `korora.check` enters `lib/*.nix` - and its refusal-versus-row cross-walk over the two changed
  accounts.
  - Exit 0; `nix eval --json .#debug.failures` is `[]`. The refusal cross-walk reads 38 refusals
    (36 before) with `unaccounted`, `namedByNoProducer` and `unexamined` all empty.
- [x] 7.2 Verify the golden plan and the golden diagnostics table are byte-equal to what is
  committed: `nix eval --json .#debug.worked.plan | jq -S .` against
  `fixtures/minimal-typed-edge/plan/*`, and `diagnostics.txt` unchanged. No fixture path or name is
  outside either grammar, so nothing here may move.
  - `diff` against `fixtures/minimal-typed-edge/plan/backup.json` is empty, and `git status` shows
    no change under `fixtures/` or `perf/`. `plan.testTheRenderedTableMatchesTheCommittedOne` and
    the rest of the plan suite are green.
- [x] 7.3 Run `nix build .#checks.x86_64-linux.planner-perf` and verify the nine budgets hold: the
  record walk of task 2.1 is a new per-unit cost and `perf/mesh.nix` holds the tree's largest unit
  records. Record the measured cost per entry for sizes 64 and 256 if the margin moved by more than
  half of the 0.15 allowance.
  - **The gate is red at `b7dd7e1` and equally red here**: `perf/check.py` reports
    `81 failures, 0 invalid comparisons, 81 of 81 gated figures compared` against both the base's
    own measurement and this tree's. `perf/budgets.json` is untouched.
  - The change's own cost, base measurement against this tree's, per plan entry: every gated
    counter moves between +0.5% and +5.6%, which is under half the 0.15 allowance, so the figures
    are recorded rather than gated. Largest: `list.elements` +5.63% at `fleet-256`,
    `nrPrimOpCalls` +5.19% at `mesh-256`. At size 64: `mesh` `nrThunks` 459.21 → 473.26 (+3.06%),
    `nrFunctionCalls` 315.54 → 330.56 (+4.76%), `nrPrimOpCalls` 243.78 → 256.11 (+5.06%),
    `list.elements` 147.93 → 155.58 (+5.17%). At size 256: `mesh` `nrThunks` 438.83 → 452.84
    (+3.19%), `nrFunctionCalls` 306.65 → 321.65 (+4.89%), `nrPrimOpCalls` 237.45 → 249.79 (+5.19%),
    `list.elements` 144.74 → 152.40 (+5.29%). Cost per entry still falls as the fleet grows, so the
    1.25 growth bound is unaffected.
- [x] 7.4 Run `nix run .#planner-e2e -- portable-image shared-postgres wired-pair` and verify no
  folder regressed: the image folder covers the escaped scripts and the narrowed staging directory,
  and the other two cover an entry the three rules do not concern.
  - The app takes one folder per invocation, so this was three runs rather than one; the tasks
    line's `--` form collects nothing and reports `file or directory not found: shared-postgres`.
    `portable-image` 36 passed, `shared-postgres` 18 passed, `wired-pair` 37 passed.
