# Running it

Every command below is run from the repository root and needs no network beyond
resolving the pinned inputs. The one exception is the machine layer, which
resolves rookery at run time and boots virtual machines.

## Look at the worked deployment

```bash
nix eval --json .#debug.worked.plan | jq keys      # the eleven entries
nix eval --json .#debug.worked.diagnostics | jq    # the rows, as records
nix eval --raw  .#debug.rendered                   # the rows, rendered
nix eval --json .#debug.worked.applicable          # false: one row is an error
```

## What this flake publishes

Four outputs are system-independent, because each one takes the caller's own
package set rather than choosing one:

| Output | What it is |
| --- | --- |
| `lib` | the library, elaborated against the nixpkgs this flake pins |
| `mkLib { systems, platformSource ? null }` | the same library against a caller's own platform definitions, which decides every entry key |
| `operator` | `mkDeployment`, the whole deployment built - see [operator.md](operator.md) |
| `debug` | the worked fixture, the suites and their failures, for reading a value while iterating |

`lib` and `mkLib` are the two answers to one question and a consumer picks one;
`debug` is this repository's own and no consumer needs it. The per-system
attributes are `packages`, `apps` and `checks`, each tabled further down.

## The two layers

A planner test is one of two things, and there is no third:

- a **nix-unit suite** under `tests/unit/`, whose subject is a
  value an evaluation can hold;
- an **end-to-end test** under `tests/e2e/<name>/`, whose subject
  needs a booted machine.

Which layer a test belongs to is decided by its subject, and each fact is
asserted in one layer and never in both. A property no pure evaluation can
observe is asserted on a machine; everything else is asserted in evaluation,
where a failure is an attribute path rather than a boot.

The rule is checked rather than advised. `tests/unit/layers.nix` reads the tree
it is evaluated from and fails a build when it has drifted: the tests root holds
those two directories and nothing else beside `default.nix` and `report.nix`,
the evaluating layer is Nix and only Nix, each end-to-end directory holds
exactly one `test_*.py` with its fixture inside it, no directory reaches into a
sibling by path or by name, a fixture two of them need lives at the layer root,
nothing names a directory that has been deleted, no end-to-end folder carries a
builder of its own, every folder carrying a deployment is reachable as a package
while the flake names no folder, and no test writes an
executable standing in for `portablectl`, `systemctl`, `nix-store` or `ssh`. One
behaviour asserted in both layers is a failure too, reported with both files, by
`tests/unit/coverage.nix`.

## Run the evaluating layer

```bash
nix build .#checks.x86_64-linux.planner-tests -L      # every nix-unit suite
```

The last line is the count. Take the number from there rather than from this
page.

Faster, while iterating - the same suites evaluated directly, with no derivation
in the way:

```bash
nix eval --json .#debug.failures                    # [] on a green tree
nix eval --json .#debug.failuresBySuite             # suite -> its failing test names
nix eval --json .#debug.suites.plan.testThePlanSerialises | jq   # expr vs expected
nix eval --json .#debug.suites --apply 'builtins.mapAttrs (_: builtins.attrNames)'
```

`git add` a new file before evaluating: the flake does not see an untracked
path, and the failure looks like a missing file rather than an unstaged one.

The suites, and how many tests each holds:

| Suite | Tests | Subject |
| --- | --- | --- |
| `interfaces` | 26 | interface identity by value, export atoms, the omission rule |
| `composition` | 21 | roots, members, the settings namespace, defaults and fixed |
| `resolution` | 43 | wiring, arity, secrecy, placement, keyset equality |
| `diagnostics` | 32 | totality, ordering, severity, rendering, the scan that finds no raising call under `lib/`, and the row table against `docs/diagnostics.md` |
| `plan` | 35 | keys, planes, absences, dependencies, serialisation, the golden fixture |
| `postgres` | 10 | one provider instance and two consumers, planned |
| `exclusions` | 17 | one deployment per excluded construct, each refused, and the counts the fixture README records about its own folder |
| `vars` | 24 | a generated value's cardinality, its delivery set, its entry and the program that produces it |
| `units` | 31 | the portable unit vocabulary, per field |
| `platform` | 19 | a machine's target, elaborated |
| `closure` | 25 | what a unit may name and what it must declare |
| `image` | 28 | the portable-service-image realiser's reading of an entry |
| `flakelet` | 14 | the flakelet realiser's reading: enablement, identity, the two name refusals |
| `operator` | 31 | the deployment build's reading: the artifact name, `manifest.json`, the realiser statement, its refusals |
| `secrets` | 12 | the secrets realiser's reading: a plan as a generator configuration, the name projection, the rendered deploy step |
| `consumer` | 2 | what this flake publishes: the recorded platform identity, and a plan keyed by a caller's own nixpkgs |
| `perf` | 6 | the synthetic fleet is deterministic and realises nothing |
| `layers` | 17 | the shape of the test tree itself, the root document and the one shell |
| `coverage` | 10 | every specification heading is a test, an omission or an alias, and every figure this document records |

That column is a value, not a tally kept by hand:

```bash
nix eval --json '.#debug.suites' \
  --apply 'builtins.mapAttrs (_: s: builtins.length (builtins.attrNames s))'
```

Nineteen suites, counted as the keys of `suites` in `tests/default.nix`, and
403 tests, counted as the test attributes of the files under `tests/unit/`. Both
numbers, and every figure in the table above, are compared against the tree by
`coverage.testASuiteGainsATest`, so a suite that gains a test fails a check
naming this document rather than leaving a stale number in it. That
attrset is the only registration point: a suite file nothing there imports is a
file nothing runs, and the key names are what the coverage cross-walk reads. A
suite that asserts a directory's reading takes it as an argument threaded from
`flake-module.nix` - `operator` takes `operatorSource` and `imageSource` the way
the two realiser suites take theirs - because a suite may name no built output.

`support.nix` and `worked.nix` sit in the same directory and are not suites:
they are the helpers and the worked deployment the suites are written against.

## Run the machine layer

Two machines and the network between them are devices a build sandbox does not
have, so this layer is an app rather than a check:

```bash
ROOKERY_FLAKE=/path/to/rookery nix run .#planner-e2e                 # five folders
ROOKERY_FLAKE=/path/to/rookery nix run .#planner-e2e portable-image  # one folder
```

See [cluster.md](cluster.md) for the host it needs, the five folders, what a run
observes and how to drive `pytest` by hand against the working tree.

The pure half of that layer needs no machine and is a check like any other:
`nix build .#checks.x86_64-linux.planner-delivery -L`, 81 tests over
`tests/e2e/test_harness.py`. Most of them are the command's rather than the
harness's now - the order `apply` walks, the refusals it makes before it dials -
because the harness hands the command a recorder in place of a process table and
reads the argv it produced. The check exports `PYTHONPATH` naming `cli/`, since
that is where those modules live. `nix develop` carries the same `pytest`, so
`PYTHONPATH=cli pytest -q tests/e2e/test_harness.py` runs the same 81 against
the working tree.

## Mapping a specification scenario to a test

No committed table of pairs exists. A `#### Scenario:` heading names its own
test, and `tests/unit/coverage.nix` is the set difference between the headings
of the specifications this package answers for and the test names that exist.

**A heading becomes a name.** Its words are lowercased, an apostrophe is dropped
rather than split on, and every other run of non-alphanumerics is one separator,
so a hyphen, a comma and a space are the same thing. The words then spell the
name twice, once per layer: `test_<snake>` for a machine test and `test<Camel>`
for a nix-unit test. *An end-to-end test carries its own fixture* requires
`test_an_end_to_end_test_carries_its_own_fixture` or
`testAnEndToEndTestCarriesItsOwnFixture`, and the check resolves whichever layer
defines it. A name defined in both layers is a behaviour asserted twice, which
is a failure naming both files rather than a matter of an author's judgement.

**The residue is two lists**, both in `tests/unit/coverage.nix`, and nothing
else:

| List | Entries | What an entry says |
| --- | --- | --- |
| `omitted` | 11 | a heading this project deliberately does not observe, mapped to the sentence saying why. Two classes only: a failure `builtins.tryEval` does not catch, so asserting it would end the evaluation that would report it; and a property of running the suite that the suite cannot observe about itself without reading the flake that runs it. An omission for a heading that has since gained a test fails as stale, and an empty reason fails as no reason. |
| `aliased` | 21 | a heading two capabilities word differently, mapped to the one test that observes it under the other's words. The named test must exist in one of the layers, and an alias for a heading whose own derived name is already a test fails as redundant. |

A third file's names count as tests that exist without being a third layer:
`perf/check_test.py`, the budget checker's own `unittest`. It sits beside the
tool it tests rather than in either layer - a budget checker is not the planner
- but the `tooling/evaluation-performance` headings it observes are this
package's, so calling them omissions would be a false sentence.

The same suite classifies every `spec.md` in the repository: `accountable` lists
the thirty-four this package's tests answer for, `excused` maps each of the others
to the reason they are not this package's - an excluded construct, a
specification a later change's delta removed, a change nothing here implements
yet. A new specification is a failure naming the file rather than a silently
smaller check.

To add a scenario:

1. Add it to a spec under `openspec/changes/`.
2. `nix eval --json .#debug.failuresBySuite.coverage` now names
   `testAScenarioGainsNoTest`, and the failure prints the two names the heading
   requires along with any existing name that shares a long prefix with them -
   which is what a rewording leaves behind.
3. Write the test in exactly one layer, under the name the heading derives. Or
   add the heading to `omitted` with a reason, or to `aliased` with the test
   that already observes it.

## Regenerate the golden fixture

`fixtures/minimal-typed-edge/plan/backup.json` is the produced plan,
committed. `testTheGoldenPlanMatches` in `tests/unit/plan.nix` compares it with
`.#debug.worked.plan` field by field, and reports the attribute paths that
differ rather than two documents. Every field participates, because the fixture
carries nothing the planner did not write.

```bash
nix eval --json .#debug.worked.plan | jq -S . \
  > fixtures/minimal-typed-edge/plan/backup.json
```

This is a **separate action from running the suite**, and it is a person's:
evaluation cannot write to the working tree, so a failing comparison leaves the
fixture on disk untouched and nothing rewrites it on your behalf. Regenerate
only after reading why the comparison failed.

## The performance gate

```bash
nix build .#checks.x86_64-linux.planner-perf -L        # measured counters vs budgets
nix build .#packages.x86_64-linux.planner-perf-results # the raw measurements
nix run   .#planner-perf -- --sizes 4,16               # measure and check, ad hoc
```

The harness evaluates one deployment per fixture and size under
`NIX_SHOW_STATS`, forces the plan deeply, and writes one JSON result per run.
Options (`perf/measure.sh`): `--fixtures worked,fleet,mesh`,
`--sizes 4,16,64,256`, `--repeats 2`.

The two sized fixtures cover the two ways a fleet grows, and the second exists
because the first cannot see the difference between a scan and a lookup:

| Fixture | Grows | Covers |
| --- | --- | --- |
| `fleet` | the number of entries, each entry's own work constant | the pipeline: resolution, placement, one set-valued read landing in one entry |
| `mesh` | one entry's work, the plan still linear in the fleet | an entry that declares one closure root, one unit and one render fragment per machine, and every list the library then crosses against another |

`tests/unit/perf.nix` asserts that shape (`testTheMeshPlansOneFleetSizedEntry`):
a fixture that collapsed its per-machine items into one would keep measuring
and stop covering anything.

**The gate is the sandboxed one.** `checks.planner-perf` measures inside a
build sandbox with empty evaluation caches, and `budgets.json` is recorded from
`packages.planner-perf-results`, which runs there too - those two agree run
after run, and two independent builds produce byte-identical gated counters.
`nix run .#planner-perf` measures on your machine with your `nix.conf`, so it
is for iterating on a change and reading the direction a counter moved; its
absolute figures drift from the budgets by a fraction of a percent and it will
report failures the gate does not. On the tree this page was written against the
gate passed with `0 failures` while `nix run .#planner-perf -- --sizes 4,16`
reported fifteen. Never re-record a budget from it.

What is gated and what is not:

- **Gated**: counters that are equal across repeated runs of one input on one
  interpreter - `nrThunks`, `nrFunctionCalls`, `nrPrimOpCalls`, `values.number`,
  `sets.bytes`, `envs.bytes`, `list.elements`, `nrOpUpdateValuesCopied`,
  `gc.totalBytes`. A counter that is not reproducible fails the check rather
  than being averaged.
- **Advisory**: wall clock and CPU time are reported and never gate.
- Budgets are **cost per plan entry**, in `perf/budgets.json`, each fixture
  carrying the interpreter version and date it was recorded against.

The ratchet is two-sided. Above budget fails; more than the margin *below*
budget also fails, with the replacement figure ready to paste:

```
FAIL: gated counter nrThunks of fixture worked costs 345.875 per plan entry,
      more than the 15% margin below its budget of 900;
      lower the budget of worked to "nrThunks": 345.875
```

A growth bound applies to **every fixture measured at more than one size**, at
the sizes stated in the budget file: per-entry cost must stay within the bound
as the fleet grows. Today every counter *falls* from 4 to 256 in both fixtures
(`fleet` `nrThunks` ratio 0.48, `mesh` 0.54).

**A cost the counters cannot see.** A membership test written as `elem` over a
fleet-sized list is one primop call that allocates nothing, so a quadratic
built out of `elem` moves no gated counter at any size - `mesh` at 2048 spent a
quarter of its evaluation there while every per-entry counter stayed flat. Time
is the only observable, and time never gates, so measure it deliberately
instead: build `planner-perf-results` with `--fixtures mesh --sizes
256,512,1024,2048` before and after the change and compare `cpuTime` per entry
across sizes. A per-entry figure that rises with size is a super-linear term;
one that stays flat is not.

**After a deliberate library change that moves counters**: rebuild
`planner-perf-results`, re-record the per-entry figures in `budgets.json`, and
re-run the gate. Do not widen a budget to make a regression pass - the point of
the ratchet is that both directions are a decision.

## The other checks

```bash
nix build .#checks.x86_64-linux.planner-perf-checker -L  # the checker's own 13 tests
nix build .#checks.x86_64-linux.treefmt -L               # every formatter and linter, python included
nix fmt                                                  # the same set, applied to the tree
```

`treefmt.nix` runs `ruff format`, `ruff check` and `mypy --strict` over the
Python here beside the Nix formatters, so an edit is told about a lint by
`nix fmt` rather than by a build. `ruff.toml` holds the rules, and its `src`
names the three roots a first-party module is imported from: `cli`, `perf` and
`tests/e2e`. mypy runs once per directory of top-level modules, because that is
what each `import` expects to be beside:

| mypy root | Holds | Also sees |
| --- | --- | --- |
| `perf` | the budget checker and its own tests | nothing else |
| `cli` | the operator's command | nothing else |
| `tests/e2e` | the harness and `test_harness.py` | `cli`, and pytest |
| `e2e-folders` | each folder under `tests/e2e/`, as a module list | `cli`, and pytest |

The last row is a label rather than a path: mypy descends into a subdirectory
only when it is a package, and an end-to-end folder is not one, so naming the
folders as modules of the `tests/e2e` directory is what gets them checked at
all. That list is read rather than written: `builtins.readDir` over `tests/e2e`
answers it, and a folder is therefore checked by existing.

The command carries its own flake module, `cli/flake-module.nix`, imported by
`flake.nix` beside `flake-module.nix` and `devshells.nix`. The root module is
where the suites, the performance harness and the end-to-end layer are
registered, and a package an operator installs does not belong in that file:
deleting the command is deleting one directory and one import line. The root
module reads `PLANNER_CLI` and `PLANNER_CLI_SRC` off the two attributes that
module publishes rather than constructing either, so a rename cannot leave the
app and the machine layer's environment disagreeing.

Everything the flake exposes, so a reader can tell what runs where:

| `nix build .#checks.x86_64-linux.<name>` | Needs | Subject |
| --- | --- | --- |
| `planner-tests` | nothing | the nineteen nix-unit suites, evaluated |
| `planner-delivery` | nothing | the pure half of the machine layer: the order `apply` walks, the refusals it makes before it dials, addressing |
| `planner-perf` | nothing | the counter budgets and the growth bound |
| `planner-perf-checker` | nothing | the budget checker's own tests |
| `treefmt` | nothing | formatting and linting, repository-wide: nixfmt, deadnix, shellcheck, yamlfmt, vale, `ruff`, `mypy --strict` |

| `nix run .#<name>` | Needs | Subject |
| --- | --- | --- |
| `planner` | `nix`, and ssh reach to the machines for `apply` | the operator's command: build a deployment and put it on the machines it names - [operator.md](operator.md) |
| `planner-e2e` | `/dev/kvm`, `/dev/net/tun`, `/dev/vhost-vsock`, `$ROOKERY_FLAKE`, and `$NIXOS_SECRETS_FLAKE` for `tests/e2e/generated-secret` | real machines, a delivery between them, and the wire the planner resolved - [cluster.md](cluster.md) |
| `planner-perf` | nothing | the same measurement and check, on your machine rather than in a sandbox |

| `nix build .#packages.x86_64-linux.<name>` | Subject |
| --- | --- |
| `planner` | the command itself, as `result/bin/planner` |
| `planner-src` | its source root, which `test_harness.py` imports the pure half from |
| `planner-e2e-wired-pair` | one folder's deployment, built: the plan, `manifest.json`, the diagnostics and one artifact per placed entry |
| `planner-e2e-wired-pair-changed` | the second build of that same folder, which differs in the file it serves |
| `planner-e2e-portable-image` | that folder's deployment: two images, one of them for a machine this host is not |
| `planner-e2e-secret-delivery` | that folder's deployment: three entries and two generated values |
| `planner-e2e-generated-secret` | that folder's deployment: three entries and two values a real generator produces |
| `planner-e2e-generated-secret-generation` | its `secrets.json`, `names.json` and the `plan.nix` the run evaluates against the state the backend answered |
| `planner-e2e-generated-secret-age` | the `age` the folder's store backend runs, so a run mints its identity with that one |
| `planner-e2e-guest` | the guest image every machine boots |
| `planner-e2e-env` | the script `nix develop` carries: the exports a manual `pytest` run needs |
| `planner-e2e-env-paths` | those exports as a file, built when the script is called |
| `planner-perf` | the ad-hoc measurement script |
| `planner-perf-results` | the raw measurements the budgets are recorded from |

The `planner-e2e-<folder>` rows are one per folder and build rather than a list
written here: `flake-module.nix` reads `tests/e2e/*/deployment/default.nix`, so a
further folder becomes a package by existing.
