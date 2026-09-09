# Design

## D1 — What actually differs between the three builders

The three `artifacts.nix` files are not three designs. Read side by side, every line is one of five
things, and only two of them are facts about the folder:

| Step | wired-pair | portable-image | secret-delivery | Generic? |
| --- | --- | --- | --- | --- |
| real packages for the declaration | `packagesWith` | `paths`, `report` | `python3`, `serveScript`, `checkScript`, `caCert` | no — the folder's |
| which entry gets which realiser and profile | flakelet, four keys | image, `strict` and `default` | flakelet, three keys | no — the folder's |
| `mkPlan` over the declaration | identical | identical | identical | yes |
| a realiser call per placed entry | identical | identical | identical | yes |
| plan serialised, results collected, `passthru` | identical | identical | identical | yes |

So the generalisation is not a refactor of shared code out of three files. It is the observation that
three of the five steps take no folder-specific input at all, and the other two are *arguments*: a
package set the declaration is applied to, and a statement of how each entry is realised. That is why
`operator/` takes the deployment's `args` plus a realisation statement and needs nothing else, and why
the folder keeps both facts it owns.

## D2 — `read.nix` pure, `default.nix` derivations

`image/default.nix:1-2` states the shape the realisers already use: "read.nix is the whole reading,
and everything here is derivations over what that read returned". `operator/` follows it for a reason
beyond symmetry: the evaluating layer has no `pkgs`. `tests/default.nix` is handed `korora`, `systems`,
`folder`, `libSource`, `perfSource`, `repoSource`, `changesRoot`, `imageSource` and `flakeletSource`,
and `tests/unit/layers.nix` asserts that no file in `tests/unit/` names a built output. A unit suite
can therefore assert a reading and can never assert a derivation.

Everything the build *decides* goes in the reading: which entries are placed, which realiser and
profile each is stated to use, the artifact name each key projects onto, whether two keys collide,
whether the plan is applicable, and what the manifest says. Everything the build *makes* — the plan
file, the artifact per entry, the manifest file, the link farm — is derivations over that answer. The
consequence is that `tests/unit/deploy.nix` can hold the whole capability except the bytes, and the
bytes are what the machine layer is for.

## D3 — The manifest, and why a plan key is not a directory name

A consumer of a deployment build has to get from a plan key to the artifact built for it. Three ways
to do that, and why two fail:

| Approach | Why not |
| --- | --- |
| the key as the directory name | `issuer:api@alpha` in a path is legal and awful: every consumer quotes it, and `@` and `:` are the two characters this repository's own key grammar splits on |
| a name the folder chooses | what the folders do today (`issuer`, `probe`, `site-changed`), and it is exactly the local convention that cannot be generic |
| a projection plus a recorded mapping | one rule, and the mapping is data the tool reads |

So the artifact of `issuer:api@alpha` is `entries/issuer-api-alpha`, and `manifest.json` records
`"issuer:api@alpha" -> { path = "entries/issuer-api-alpha"; … }`. The tool never reconstructs a name;
it reads the mapping. A projection is not injective (`a:b@c` and `a-b@c` both project onto
`a-b-c`, and a member name may itself carry a hyphen), so a collision is an error row naming both
keys. That is the same posture the sibling change takes for its own name projection: "a refusal, not
a mangling".

The manifest carries, per placed entry: the artifact path, the realiser, the machine, the address out
of the machine record, the unit file names, and the entry key hash. Per value entry: the files, their
paths, their secrecy, and the delivery set. Nothing derived that the plan already holds — the plan
travels beside it and stays the single source for everything else.

## D4 — A build refuses; a plan does not

`mkPlan` returns `applicable = !diag.hasError diagnostics` (`lib/default.nix:115`) and `render` is
exported (`:72`), and today nothing acts on either: each `artifacts.nix` calls a realiser regardless,
and a deployment with an error row builds artifacts for whichever entries happen to have survived.

`operator/` is where that becomes a refusal, because it is the first layer allowed to raise. `lib/`
never raises; `image/` and `flakelet/` raise for a fact an entry does not record; `operator/` raises
for a deployment the planner itself called inapplicable, and the message is the rendered table. A
warning-only table builds — a warning that stopped a build would be an error.

## D5 — The realiser of an entry is stated, never guessed

`flakelet.artifact` takes `{ plan, key }` (`flakelet/default.nix:25-26`). `image.build` takes
`{ plan, key, profile, compression ? … }` (`image/default.nix:25-31`), and the comment there is
explicit that a profile "is a build input like the profile and never a plan fact". Nothing in a plan
entry says which of the two an entry wants, and nothing should: the same entry can legitimately be
both, which is what `portable-image` and `wired-pair` demonstrate between them.

So realisation is stated beside the deployment, keyed by plan key or by the `<instance>:<member>`
prefix of one:

```nix
realise = {
  default = { realiser = "flakelet"; };
  "watch:file" = { realiser = "image"; profile = "strict"; };
};
```

`default` is `flakelet` when the statement is omitted, because that is the realiser that needs no
further fact. An `image` entry with no `profile` is refused rather than defaulted — `image/read.nix`
would otherwise be handed a confinement decision nobody made. A realiser name nothing implements is
refused naming the two that exist.

## D6 — The order `apply` walks, and the one cycle that is legal

Two orderings matter and both come out of the plan:

1. **Values before units.** A unit whose `env` names `/run/vars/<instance>/<gen>/<file>` starts as
   soon as it is activated, so every value an entry's machine is in the delivery set of is written
   first.
2. **Provider before consumer.** `plan.<consumer>.reads.<slot>.entry` names the provider's own key
   (`"issuer:api@alpha"` in the secret-delivery plan), so the edges are already in the artifact.
   `dependsOn` is not that relation — a consumer's `dependsOn` is `["machine:beta@<hash>"]`, which is
   key provenance rather than order.

`CLAUDE.md` records that "two instances wiring each other is not a cycle: a capability's exports are a
function of module and settings, never of a wire. Do not add cycle detection." That invariant is about
keys, and it holds; but the *activation* graph of a mutual pair genuinely has no first element. So the
order is a topological walk that, on encountering a cycle, breaks it at the lowest key by sort order
and prints which edge it broke. Refusing would refuse a deployment the library considers correct.
Silence would make a one-off startup failure unexplainable.

## D7 — Python, and what would change that

The command's work is: run `nix build`, read two JSON files, sort entries, run `nix copy`, run `ssh`
with a here-document, run `flakelet activate` or the image's own `bin/attach`, and print a line per
step. That is orchestration of other programs plus a walk over decoded JSON.

| Language | For | Against |
| --- | --- | --- |
| Python 3.13 | `ruff`, `mypy --strict` and pytest are already configured and running over `perf/` and `tests/e2e/`; `runner.py` already shells out to `nix` and already refuses loudly | one more `mypy` root, and `ruff.toml`'s "this repository owns no python package" stops being true of the source tree |
| Rust | a shipped binary with no interpreter; matches flakelet's own language | a cargo toolchain, `clippy`, `deny` and a build step, in a repository with none of them, for a program that cannot run without `nix` on `PATH` anyway |
| shell | no new anything | the ordering walk, the manifest reading and the refusals are logic, and `shellcheck` is not a type checker |

Python, and the trigger to revisit is a requirement to run somewhere an interpreter is not: on the
target machine, or as a static binary. Neither is on the horizon, because every subcommand invokes
`nix` locally.

## D8 — Where the command runs, relative to rookery

A delivery has to run where the cluster's addresses resolve, which is why `delivery.deliver` goes
through `Cluster.run` and why `delivery_env` carries the caller's `PATH`, `HOME` and daemon socket. A
build has no such requirement and should not inherit that environment.

So the machine layer splits the command in two, exactly along the boundary that already exists:

- `planner build` runs in the pytest process, before any machine is dialled. Its output is a store
  path plus a manifest.
- `planner apply` runs through `Cluster.run` with `delivery_env`, given the already-built directory,
  so no evaluation and no build happens inside the cluster's user namespace.

`ssh` options stay a parameter. `-F /dev/null` and the throwaway-guest options are properties of a
rookery guest, not of an operator (`tests/e2e/delivery.py:201-232` explains why each is needed), so
`apply` honours `NIX_SSHOPTS` and takes `--ssh-key`, and the harness supplies the rest. A real
operator's ssh config is then the thing that configures a real operator's ssh.

## D9 — What is left of `delivery.py`

| Function | Where it goes |
| --- | --- |
| `copy_argv`, `install_argv`, `ssh_opts`, `delivery_env` | `cli/` — they are the command |
| `deliver`, `deliver_value`, `activate`, `status`, `rollback` | `cli/` — they are the command's steps |
| `machine_of`, `machines_placed`, `placed_key`, `machine_address`, `address_of`, `vars_entries`, `locked_url`, `service_name` | stay: the assertions read the plan too, and a test that reads the plan the way the tool does is a test that can disagree with it |
| `cluster_stage`, `await_ready`, `ssh_key`, `state_root`, `cut_is_cached` | stay: rookery, not the planner |

`tests/e2e/test_harness.py` keeps its purpose word for word — "the harness is code too, and its pure
half is a function of its arguments and needs no machine" — and the code whose pure half it asserts is
now mostly the command's. The `Recorder` idiom it already uses (a namespace that records argv instead
of running it) is what makes the command's ordering assertable without a machine.

## D10 — Discovery instead of registration

`docs/cluster.md:81` already says a third folder "needs no registration anywhere" because the runner
finds `test_*.py` by looking. The flake does not hold to that: three imports, three package rows and
five environment rows name the folders one by one.

Under this change `flake-module.nix` reads the directory: every `tests/e2e/*/deployment/default.nix`
becomes `packages.planner-e2e-<folder>`. The environment shrinks to what is not per-folder —
`PLANNER_E2E_GUEST_IMAGE`, `PLANNER_E2E_SSH_KEY`, `PLANNER_CLI`, `PLANNER_CLI_SRC` — plus the
deployment paths, which stay per-folder because a store path and a working-tree path are two different
answers (`flake-module.nix:140-153`). The `PLANNER_*`-unset skip idiom that `pytest.ini`'s `-rs` exists
for is unaffected: a folder skips when `PLANNER_CLI` is unset.

Building a deployment moves out of the app's closure as a result: `nix run .#planner-e2e` no longer
forces three link farms before pytest starts, and a folder that fails to build fails as a test error
naming the build. The guest image stays in the closure — it is shared, 3.7 GiB, and not per-folder.

## D11 — What the layer checks say about this

Three of them constrain the shape directly:

- **`testAReaderOpensAnEndToEndDirectory`** fails any path token in a folder's Nix that resolves
  outside the folder. So `deployment/default.nix` cannot `import ../../../operator`. It takes
  `operator` as an argument, the way it already takes `planner`.
- **`testAnEndToEndTestNeedsAMachine`** pins the layer root to exactly `conftest.py`, `delivery.py`,
  `guest.nix`, `runner.py`, `test_harness.py`. The command does not live there; it is a top-level
  directory of the repository, and the harness reaches it by the environment.
- **`testATopLevelEntryBelongsToNoStatedClass`** and **`testTheRootDoesNotSayWhatTheRepositoryIs`**
  make `operator/` and `cli/` two-line additions to `classOf` and `README.md` rather than silent
  ones.

The new folder-shape claims land in `tests/unit/layers.nix` beside those: a folder holds no builder,
and `flake-module.nix` names no folder.

## D12 — The seam with `generate-values-with-nixos-secrets`

That change is unstarted (`tasks.md` items 1.1 onwards unchecked) and its plan includes writing
`tests/e2e/generated-secret/artifacts.nix` "following `tests/e2e/secret-delivery/artifacts.nix`" and
adding its rows to `e2eArtifactPaths`. Both are superseded here: the folder it adds gets a
`deployment/default.nix` and no builder, and no flake row.

The value seam is `--values <dir>`, and it is deliberately a directory of bytes rather than a call
into a secret store. That keeps this change ignorant of generation and keeps the two changes
independent in either order: the secrets realiser produces the directory, or an operator fills it by
hand, and `apply` cannot tell.

## D13 — Two directories, and a flake module of its own for the command

`operator/` and `cli/` are one role and two kinds of thing, so they are two top-level directories
with two entries in `classOf`:

| | `operator/` | `cli/` |
| --- | --- | --- |
| language | Nix | Python |
| what it is | an evaluation | a program |
| who reads it | `mkDeployment` callers, and `tests/unit/operator.nix` | an operator, and `tests/e2e/` |
| closure | the artifacts it builds | an interpreter, `nix` and `openssh` |
| checked by | `nix-unit` | `mypy --strict`, `ruff`, pytest |

Merging them would put a python file under a directory the unit layer imports, and put a store
reference to an interpreter in the closure of the thing `tests/unit/operator.nix` evaluates. `perf/`
mixes `.nix` and `.py` and is the counter-example: nothing in `perf/eval.nix` and `perf/check.py`
refers to the other, and the pair is a harness rather than a deliverable.

The command's flake wiring is `cli/flake-module.nix`, imported by `flake.nix` beside
`./flake-module.nix` and `./devshells.nix`, because:

- **flake-parts already works this way here.** `devshells.nix` is a module of its own for the same
  reason: it is one deliverable's wiring, and a reader looking for the shell does not read the test
  registration to find it.
- **The root module is the registration point for the tests, the perf harness and the end-to-end
  layer** (262 lines before this change, and it is where the folder discovery of D10 lands). A
  package an operator installs does not belong in the file that wires the test suites.
- **Deleting or extracting the command is one directory and one import line.** The same is true of
  moving it to another repository, which is the likely end state once it stops being the only
  consumer of `operator/`.

`cli/flake-module.nix` owns `packages.planner-cli`, `apps.planner`, and the two variables the machine
layer needs to reach both (`PLANNER_CLI`, the wrapper; `PLANNER_CLI_SRC`, the source root
`test_harness.py` imports the pure half from). The root module reads those two from the CLI module's
own output rather than constructing them, so a rename cannot leave the app and the environment
disagreeing — the same property `e2eArtifactPaths` already has for the artifacts.
