## Why

The diagnostics half of an authoring loop is production grade and the ergonomics half does not
exist. Evaluation is total: `lib/default.nix:1-8` states it, and
`tests/unit/diagnostics.nix:474-509` holds it by scanning every comment-stripped line of `lib/**`
plus `operator/read.nix` for `throw`, `abort`, `assert `, `.check ` and `korora.check`. A row is six
required fields (`lib/diagnostics.nix:45-63`), the same fact produced twice is one row (`:128-139`),
and a table is ordered by identifier, then subject, then message (`:141-169`), so two iterations of
one deployment diff cleanly. `docs/diagnostics.md` catalogues 172 row identifiers: 141 under "Every
row the planner can produce" (`docs/diagnostics.md:95-299`), 20 under "Every row the deployment
build can produce" (`:300-328`) and 11 under "Every row the secrets reading can produce"
(`:329-350`).

The loop is already proven on a machine that is not this host.
`tests/e2e/newcomer/test_newcomer.py:687-706` copies the consumer, rewrites one line of the
template's leaf module so a declared closure root sits outside the store, and builds it with a real
`nix build` there; `:709-729` reads the identifier, the subject and the message back out of
`diagnostics.json` and finds the same message inside `diagnostics.txt`. What that proves is the
table. What it does not give an author is a way to ask for the table.

Five gaps, each verified:

- There is no rows-only answer. `cli/planner.py:100-106` is `plan build apply status rollback`, and
  `build` realises the farm: it resolves the target through `manifest.resolve`, which runs
  `nix build` with `--no-link --print-out-paths` for anything that is not already a built directory
  (`cli/manifest.py:248-255`), then reports what the result holds (`cli/planner.py:41-47`). An
  author who wants the rows pays for every artifact of the deployment.
- The six-field row does not reach the author. `cli/manifest.py:123-130` carries four fields and
  `:664-679` decodes four, dropping `evidence` and `resolution` - the two fields that say what was
  observed and what to edit.
- The flake publishes no scaffold. `flake-module.nix:50-79` publishes `lib`, `mkLib`, `operator` and
  `debug`, and `flake.nix:31-53` adds no other output; there is no `templates`. The only scaffold in
  the tree is `tests/e2e/newcomer/template/`, and `README.md:48-50` and `:82-84` tell a reader to
  read it out of `tests/`.
- There is no machine-readable description of the authoring vocabulary. The vocabulary is prose
  tables in `docs/authoring.md`: the leaf declaration keys at `:137-146`, a generator's keys at
  `:252-260`, the `impl` argument at `:324-333`, the unit record at `:383-408`, a configuration
  file's keys at `:561-568`, the registry keys at `:809-816` and the instance keys at `:894-902`.
  The machine-checkable half is korora typedefs in `lib/atoms.nix:79-201` with the enumerated
  domains at `:111-157`, the key lists in `lib/module.nix:26-35`, `:130-144` and
  `lib/resolve.nix:37-61`, and the unit vocabulary in `lib/module.nix:84-103`. The two halves
  already disagree: `lib/resolve.nix:52-61` admits eight registry keys and
  `docs/authoring.md:809-818` names six and says "A machine declares those six keys and nothing
  else", missing `scope` and `sealRecipient`, both of which landed.
- The inner loop costs a full package-set instantiation. The published template's entry point takes
  `pkgs` (`tests/e2e/newcomer/template/deployment/default.nix:1-5`) and its flake hands it
  `nixpkgs.legacyPackages.${system}` (`tests/e2e/newcomer/template/flake.nix:18`), so every question
  about the declarations is asked through nixpkgs. A package-set-free entry point already exists and
  is used by exactly one folder: `operator/default.nix:351-362` records why `mkGeneration` imports a
  deployment's `args.nix` rather than its `default.nix` - "a `default.nix` there takes `pkgs`, which
  no evaluation outside a build can hand it" - and the one `args.nix` in the tree is
  `tests/e2e/generated-secret/deployment/args.nix:6-10`, whose three formals are `planner`,
  `packages` and `varsState`, and which returns `{ args }`.

Three failures are uncatchable, and they are the ones a language model hits.
`docs/diagnostics.md:372-386` names them: an `abort`, a missing attribute - including an `impl`
dereferencing a slot that did not deliver, because a refused read leaves `results` without that key
at all (`docs/authoring.md:649-658`) - and a function called without an argument its pattern
requires. `docs/authoring.md:659-662` states the consequence that makes them expensive rather than
merely uncaught: `applicable` forces every row of every entry, so one unguarded read leaves nothing
rendered for any entry, and the row that was produced dies with the table. A fourth trap is recorded
under Known bugs in `CLAUDE.md`: a deployment that hands a module a derivation instead of `"${drv}"`
ends the evaluation in `error: stack overflow; max-call-depth exceeded` inside nixpkgs' own
`stdenv`, because the walk that reads a unit record for line breaks recurses into every attrset it
meets (`lib/util.nix:398-413`, gated by `lib/util.nix:435-444`).

## What Changes

- **A rows-only answer that realises nothing.** `mkDeployment` publishes the rendered table beside
  the rows it already publishes (`operator/default.nix:341-347`), so the two halves of the table are
  two attributes of the deployment rather than two files of a built farm, and both are the planner's
  own words - the text is the one `operator/default.nix:328` already writes into `diagnostics.txt`,
  bound once and spent twice. A new subcommand, `planner diagnose`, prints the rendered table and
  exits non-zero where a row carries an error, the way `build` already does
  (`cli/planner.py:41-47`); `--json` prints the rows instead, in the order
  `lib/diagnostics.nix:141-169` put them. Reading the record wholesale stays refused by
  construction: `operator/default.nix:71-75` and `:299-303` map every entry and every machine
  artifact of an inapplicable deployment onto `throw reading.refusal`, so an answer is the two named
  attributes and never the whole passthru.
- **A package-set-free entry point in the published scaffold.** The scaffold gains an `args.nix`
  beside its `default.nix`, taking the three formals
  `tests/e2e/generated-secret/deployment/args.nix:6-10` takes, and its `default.nix` composes it the
  way `tests/e2e/newcomer/deployment/default.nix:1-7` composes the template. Its flake publishes a
  `diagnostics` output built from `planner.mkPlan` over those args with store-shaped placeholder
  packages - the `tests/unit/worked.nix:6-9` precedent, where the argument exists so a real package
  set can be handed to the same deployment - so an author's question costs one library evaluation
  and no package set. One deployment text, two entry points, and the build remains the authority for
  the rows only a real store path can decide.
- **The scaffold is published under a name.** `templates.default` names
  `tests/e2e/newcomer/template`, so `nix flake init -t` hands a reader the text
  `tests/unit/layers.nix:389-407` already asserts byte for byte against `README.md` and
  `docs/README.md`, and `tests/unit/layers.nix:715` already holds to the no-host-path scan. The
  directory does not move: moving it would edit four registration points and two documents to
  produce a second copy that can drift, and what is missing is a name rather than a location.
  `README.md:48-50` and `:82-84` stop telling a reader to read a path under `tests/`.
- **The authoring vocabulary is published as data, projected and never restated.** The library
  publishes `vocabulary`, assembled in a new `lib/vocabulary.nix` from the tables `lib/atoms.nix`,
  `lib/module.nix` and `lib/resolve.nix` already hold, and `packages.planner-schema` is that value
  as one JSON file. What a projection can express is a name: every unit field, leaf key, registry
  key, instance key, `impl` field, configuration-file key and directory kind, each with the korora
  type name its atom carries (`lib/module.nix:1149` already reads that name for a row), plus the
  enumerated domains, which are lists of strings (`lib/atoms.nix:128-157`). What it cannot express
  is a predicate: an atom's `verify` is a function (`lib/module.nix:944`), which is the limit
  `CLAUDE.md` records for `identityOf` and for the platform record's absent `is*` predicates.
  `domains.isZeroDuration` (`lib/atoms.nix:111`) is itself a function riding that table, so the
  projection publishes the list-valued members and refuses the rest rather than serialising one. The
  172 row identifiers are deliberately not projected: their one home is the production sites,
  `docs/diagnostics.md` is the table `tests/unit/diagnostics.nix:511-541` already crosses them
  against, and a third copy would be a second thing to maintain for an answer `planner diagnose`
  gives exactly.
- **The six-field row reaching the author is consumed, not redefined.** The decode that drops
  `evidence` and `resolution` (`cli/manifest.py:123-130`, `:664-679`) is owned by
  `answer-a-machine-question-as-a-record`; `openspec/changes/INTEGRATION.md` records the seam. This
  change consumes the restored fields and defines neither the record nor the two fields.
- **The four traps become one documented set.** None of the three interpreter traps can become a
  row, because `builtins.tryEval` catches a `throw` and a failed `assert` and none of an abort, a
  missing attribute, or a function called without a required argument (`CLAUDE.md`, Purity and
  totality, and `lib/diagnostics.nix:84-86` beside the guard that relies on it). Each becomes a
  sentence an author is handed instead: what ends the evaluation, what the interpreter prints, and
  the edit that fixes it, in the section `docs/authoring.md:644-673` already is, with the fourth
  trap added there and the schema naming that section rather than copying it. The fourth trap is
  reducible to a row, and this change deliberately does not add it: a derivation is recognisable by
  the attributes it carries before anything forces its inputs, so the walk at
  `lib/util.nix:398-413` could refuse one and name the field path, but that row's home is a planner
  capability this change does not own.
- **What the change buys is a figure.** The rows of the published scaffold are answered today
  through `nixpkgs.legacyPackages` and afterwards through the library alone, so the cost of one
  iteration is the count of values each evaluation forces. It is measured with `NIX_SHOW_STATS`,
  which is the same counter set `perf/measure.sh` reads, and recorded in this change's tasks as a
  figure beside the two commands that produced it. It is not a `perf/budgets.json` counter:
  `perf/eval.nix` evaluates no package set, so neither number is a cost the gate can hold, and the
  claim is a ratio between two invocations rather than a budget.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `tooling/consumer-surface`: modifies `The example a document shows is the example a test builds`
  so the one text the documents show is also the text the published scaffold hands a reader and
  carries both entry points; adds the published vocabulary as data and what a projection may and may
  not express; adds the reading of a deployment's declarations with no package set instantiated; and
  adds the rule that a failure the interpreter does not let the library catch is named in one place
  an author is handed.
- `operator/deployment-build`: adds the rows and the rendered table as an answer a caller reads
  without realising anything, with the command that prints them and its exit status; and modifies
  `An inapplicable deployment is not built` so the machine-readable half is reachable from an
  evaluation as well as from a build, and reading the record wholesale is the refusal rather than
  the table.

## Impact

- `lib/vocabulary.nix`: new, the projection. Under `lib/`, so `tests/unit/diagnostics.nix:486` holds
  it to the purity scan by existing and `classOf` in `tests/unit/layers.nix` needs no edit.
- `lib/default.nix`: publishes `vocabulary` beside `atoms`, `excluded`, `platform` and `util`
  (`lib/default.nix:57-64`). Outside `mkPlan`, so no gated counter reads it.
- `lib/module.nix`: exports `moduleKeys` beside the six tables it already exports (`:212-220`).
- `lib/resolve.nix`: exports `machineRegistryKeys`, `instanceKeys`, `everyKeys` and
  `reservationKeys` from the attrset at `:206-207`, which is built once per library import.
- `operator/default.nix`: the rendered table published beside the rows, one expression spent twice.
- `cli/planner.py`: the `diagnose` subcommand, its parser entry and its `--json` flag.
- `cli/diagnose.py` or the existing reading in `cli/manifest.py`: the two ways a target answers - a
  built directory's two files, and an evaluated attribute - decided in tasks.
- `flake-module.nix`: `templates.default`, and `packages.planner-schema`.
- `tests/e2e/newcomer/template/`: `args.nix`, the composed `default.nix`, and the `diagnostics`
  output in its `flake.nix`.
- `README.md`, `docs/README.md`: the shown blocks, which are the files
  (`tests/unit/layers.nix:389-407`), and the command table at `README.md:90`.
- `docs/authoring.md`, `docs/diagnostics.md`, `docs/tooling.md`: the four traps in one section, the
  published vocabulary and the two new outputs beside the four at `docs/tooling.md:16-31`.
- `tests/unit/layers.nix:1084-1090`: the example folder's file list gains `args.nix`.
- `tests/unit/consumer.nix`: the projection, the published template and the two entry points; the
  suite exists and is already handed `planner` and `repoSource` (`tests/default.nix:48-58`).
- `tests/e2e/newcomer/test_newcomer.py`: the scaffold initialised, the rows-only answer on the
  machine, and the cost of the two entry points measured. The folder's own capability licenses this:
  `openspec/specs/tooling/test-layers/spec.md:229` says other changes may add scenarios to it and
  none may redefine what it is.
