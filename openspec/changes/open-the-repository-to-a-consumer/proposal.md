## Why

A stranger who clones this repository can plan a deployment and cannot build one. `flake.lib =
planner` (`flake-module.nix:28`) publishes the library and nothing beside it: the deployment build
is a `perSystem` `let` binding (`flake-module.nix:111`), and the two realisers reach the flake only
as source paths handed to the test suites (`flake-module.nix:11-13`). `nix eval .#operator` fails,
and the exported library carries no `mkDeployment`. The one reachable form is
`import "${inputs.nixplan}/operator"`, a path inside this flake's own source, and no document names
it.

The documented route asks for more than a consumer can give. `docs/operator.md:43` states the
planner as `import "${nixplan}/lib" { inherit korora systems; }`, so a caller has to supply korora,
a non-flake input this repository pins (`flake.nix:19-22`) that no document tells anyone how to
obtain, and `systems`, which decides how a machine's platform record is elaborated
(`flake-module.nix:6,8`). A platform record enters every entry key, so the argument a consumer is
asked for silently decides the identity of every entry. `docs/authoring.md` never uses the word
flake, and no committed document shows a downstream one.

Hand-discovery does not recover from that. `systems.url = "github:nix-systems/default"`
(`flake.nix:6`, read at `flake.nix:35`) claims `x86_64-darwin`, a platform the pinned nixpkgs
removed with a `throw`, and `nix flake show` therefore dies inside a nixpkgs release note before it
prints one output of this flake. `nix run .` fails because the flake declares no default app.
`nix build .#planner` answers `expected flake output attribute 'planner' to be a derivation or path
but found a set`, because the debug attrset at `flake-module.nix:30` occupies the name the
operator's application uses, and `README.md:42` sends the reader to that name.

The one example a document does show does not build. The smallest working example of
`docs/README.md:52-125` plans with an empty table and `applicable = true`, and then fails to
realise: `pruned` (`lib/plan.nix:559`) drops an empty `closure` and an absent `units` from a placed
entry, and `required` in the image reader (`image/read.nix:118-123`), which the flakelet realiser
reuses, refuses an entry that records no `closure`. A unit that depends on no store path and a
service that computes an export and runs nothing are both unbuildable, and no row says so.

What is left of a supported route runs through the test layer. `buildsOf` is applied to folders
discovered under `tests/e2e/<name>/deployment/default.nix` and nowhere else
(`flake-module.nix:115-121`), so the only place this repository knows how to build a deployment from
is a folder inside its own checkout. The shell a newcomer enters points the same way: it carries no
`planner` (`devshells.nix:14-19`), and its hook resolves the *current directory's* git top level
(`devshells.nix:21`, and the same line at `flake-module.nix:193`), so entering it from an unrelated
repository sets `PYTHONPATH` to that repository's paths and entering it from outside a git
repository sets `/tests/e2e:/cli`.

## What Changes

- **The deployment build is a flake output.** `flake.operator` sits beside `flake.lib`, so a
  consumer reaches `mkDeployment` by name rather than by a path into this source. Neither output
  asks for korora: the library a consumer receives is already applied to the pin this flake carries.
- **The library states which nixpkgs elaborated its platforms, or takes the consumer's.**
  `flake.lib` records the nixpkgs its `systems` argument came from, and a constructor beside it
  takes a consumer's own. A consumer following their own nixpkgs can therefore say which one decided
  an entry key, instead of discovering the answer when a key moves.
- **The output surface answers the ordinary commands.** The system list is written out and the
  `nix-systems/default` input is deleted, so `nix flake show` evaluates every system this flake
  claims. A default application exists, so `nix run .` runs the operator's command.
- **BREAKING - `flake.planner` is renamed to `flake.debug`.** The debug attrset of test results and
  the operator's application cannot both be `planner`: `nix build .#planner` is an error today. This
  overrules the non-goal `clean-up-transplant-residue` recorded (its proposal line 35), which was
  written when no application held the name. `docs/tooling.md`, `docs/plan.md` and `CLAUDE.md` move
  with it.
- **The documented example is a deployment a test builds.** The smallest example a document shows
  and the deployment `tests/e2e/newcomer/` holds are one text, so an example that stopped building
  fails a check rather than a reader. The pruning defect the current example hits is named here and
  fixed by `report-every-refusal-as-a-row`, which owns the rule that a refusal is a row.
- **A newcomer folder in the machine layer.** `tests/e2e/newcomer/` holds a template - a flake
  naming the published input, and a deployment of one service on two machines - and three machines
  boot for it. A workstation belonging to no plan is handed the template and the source of this
  checkout, locks the one against the other, builds the deployment in its own store, applies it to
  the other two and reports what they hold. Every step runs there; this host contributes the source
  and the credential and nothing else.
- **The shell is a shell of this checkout.** It carries `planner` on `PATH`, takes its root from the
  flake rather than from the caller's working directory, and refuses rather than pointing at a
  foreign tree.
- **The root names what a command needs and this repository cannot provide.** `nix run
  .#planner-e2e` is advertised beside the fact that it resolves rookery, which is private, so a
  reader learns that before the run rather than at `docs/cluster.md:67`.
- **The help text of `planner` stands on its own.** It states what a target is, what a plan key
  looks like, that `rollback` takes exactly one `--only`, and where the fuller document is.
- **`apply --dry-run`.** Every refusal the command makes before its first dial is made, and the
  steps it would take are printed in the order it would take them, with no machine contacted. That
  is the first thing an operator wants before touching real machines.
- **`nix fmt` stops contradicting itself.** `docs/tooling.md:278` advertises the command and
  `docs/tooling.md:301-302` describes it as failing "on files this library does not own", naming
  neither the files nor the condition. Either the command succeeds on a clean checkout, or the
  document names exactly what has to be true.

Not in this change, deliberately:

- **The pruning defect behind the unbuildable example.** `pruned` dropping an empty `closure` and
  an absent `units`, and the realisers raising for what it dropped, is a refusal that is not a row.
  `report-every-refusal-as-a-row` owns that rule and that fix. This change owns only the claim that
  a documented example is an example a test builds, which is what makes the defect visible.
- **Publishing the realisers as outputs of their own.** `flake.operator` is what a consumer builds a
  deployment with, and it decides the realiser per entry from the realisation statement. An
  `image`-only or `flakelet`-only consumer wants one entry realised, which is a narrower need than
  anything documented, and a published entry point is a contract to keep.
- **A stable schema for `plan.json` and the deployment record.** `operator/deployment-build` owns
  both, `version` is `1`, and nothing here versions or freezes them. `make-an-apply-observable`
  owns reading `version` at all.
- **rookery.** It stays private and stays resolved at run time. What changes is that the root says
  so where the command that needs it is named.
- **A published deployment template or a `nix flake init` template.** The scratch flake the newcomer
  test writes is the documented text; committing a second flake to this tree is argued against in
  design D3.

## Capabilities

### New Capabilities

- `tooling/consumer-surface`: what this flake publishes to somebody who is not this repository -
  which layers are outputs, what one published name means, whether the ordinary discovery commands
  answer, whose nixpkgs elaborated the platforms a consumer gets, and whether a documented example
  is one a test builds.

### Modified Capabilities

- `tooling/test-layers`: the machine layer gains the newcomer folder, and a folder's fixture may be
  built from a directory the test creates outside the checkout rather than only from the folder.
- `tooling/repository-shape`: the root and the one shell are things a newcomer reads and enters, so
  a command the root advertises names what it needs, the shell carries the command its documentation
  is about and refuses a foreign tree, a program's help text stands alone, and a document does not
  advertise a command it also reports as failing.
- `operator/apply-command`: the refusals the command makes before its first dial become reachable on
  their own, as `--dry-run`.
