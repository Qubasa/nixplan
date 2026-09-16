# Design

## D1 - An output, not a documented import of the source

`operator/default.nix` is already a function of `{ pkgs, planner, args, realise }` and nothing else,
and `flake-module.nix:111` already binds it as `operator = import ./operator;`. The distance between
that binding and a consumer is one line. Three ways to close it:

| Approach | What a consumer writes | Why not |
| --- | --- | --- |
| document the path | `import "${inputs.nixplan}/operator"` | the source layout becomes the interface: moving `operator/default.nix` breaks a caller who never named a file, and nothing in this tree fails when it happens |
| a flake-parts module a consumer imports | `imports = [ nixplan.flakeModules.deployments ];` | the caller has to run flake-parts, and this repository would own an option namespace in the caller's flake |
| an output | `nixplan.operator.mkDeployment { … }` | one name, checked by evaluating the flake |

The third. `mkDeployment` takes the caller's own `pkgs`, so the output is system-independent and
sits beside `flake.lib` rather than under `perSystem`: a consumer on aarch64 building for x86_64
reaches one name, and this flake's own system list decides nothing about theirs.

The realisers stay unpublished. A consumer states which realiser an entry uses through `realise`,
and the deployment build calls it; a caller who wants `image.build` for one entry outside a
deployment is asking for something no document describes. An entry point published is an entry point
kept.

korora never reaches a consumer. `flake.lib` is already applied to the pin at `flake.nix:19-22`.
The alternative - asking a consumer to add `inputs.korora` with `flake = false` and to pass
`import "${korora}/types.nix"` - makes a caller pin a library they never name, at a revision
that has to match ours or the types compare unequal.

## D2 - Whose nixpkgs elaborates a consumer's platforms

`systems = inputs.nixpkgs.lib.systems` (`flake-module.nix:6`) is applied at `flake-module.nix:8` and
published at `:28`. A consumer following their own nixpkgs gets `pkgs` from theirs and platform
elaboration from ours. That matters because `platform` is a field of every placed entry and every
entry key is a hash over the entry, so a nixpkgs bump on either side can move keys with nothing in
the consumer's tree changing. A moved key is a redeployed unit.

| Approach | Cost |
| --- | --- |
| keep the pin, say nothing | today: two nixpkgs decide one plan and neither is named |
| the consumer must pass `systems` | the trivial case grows an argument, and a caller who does not care about platform records has to know what `lib.systems` is before writing a deployment |
| the pin is the default and is recorded, and a constructor takes the consumer's | one more name in the output surface |

The third. `flake.lib` stays the applied library and records which nixpkgs elaborated it, as a value
a consumer can read and compare - the same revision the flake's own lock names. Beside it,
`flake.mkLib { systems }` returns the library elaborated against a caller's own `lib.systems`. A
consumer who wants one nixpkgs deciding everything writes one line; a consumer who does not care
writes none, and either way the answer to "which nixpkgs decided this key" is in the plan's own
neighbourhood rather than in this repository's lock.

Recording it is the load-bearing half. The choice between two elaborations is a real trade - ours is
tested by `tests/unit/platform.nix` against the doubles this flake claims, theirs is the one their
`pkgs` agrees with - and a consumer can only make the trade when both are named.

## D3 - The newcomer's flake is a committed template, locked at run time

The claim under test is that a stranger, reading only committed documentation, reaches a running
service. Two shapes carry a downstream flake:

- **A flake written at run time.** Nothing to maintain, but its text lives inside a test as a
  format string, and a reader who wants the example has to read a test to find it. It also cannot
  be copied onto a machine as what it is: a directory.
- **A committed template that names the published input.** `template/flake.nix` is the line a
  reader writes, so it is readable where a reader looks, and it is a directory a run can copy. Its
  one hazard - a committed reference to a repository nobody can fetch during a test - is answered
  by `nix flake lock --override-input nixplan path:<source>`, which resolves the input to the tree
  under test without fetching the published one and records that in the lock.

The second. A committed lock is the thing that is deliberately absent: the run writes it, so the
resolution is always this checkout and never a revision that was current when somebody committed.
`nixpkgs` follows `nixplan/nixpkgs`, so the deployment is evaluated against the packages the
library was built against rather than against a second pin.

The residual risk is that the template and the block a document shows drift apart. That is the same
risk D7 answers for the deployment itself, and it is answered the same way: one of the two is
checked against the other in the evaluating layer, where a text comparison costs nothing.

## D4 - `nix flake show`: narrow the list, drop the input

`systems.url = "github:nix-systems/default"` names four doubles, one of which the pinned nixpkgs
removed with a `throw`. Reproduced: `nix flake show` walks the systems in order and dies inside the
nixpkgs release note for `x86_64-darwin`, having printed the aarch64 outputs and nothing more. Two
fixes:

| Fix | Result |
| --- | --- |
| keep `nix-systems/default` and subtract the systems the pin refuses | the flake carries a subtraction list, which is a claim about which platforms this nixpkgs refuses, restated here and stale the moment nixpkgs adds or removes one |
| write the list out and delete the input | the flake states the three doubles it claims, in the file that claims them |

The loser is the subtraction. Keeping the input leaves two sources for one fact - the input's four
doubles and this flake's list of exceptions - and the exception list is silently wrong in the
direction that hurts: a platform nixpkgs later removes stays claimed until somebody runs the
discovery command on it. An input whose only work is to spell four strings pays no rent either.
`x86_64-linux`, `aarch64-linux` and `aarch64-darwin` are written into `flake.nix` with a comment
naming the removal, and a reader who wants a fourth adds it and finds out at once whether it
evaluates.

## D5 - One name, one thing, and the non-goal this overrules

`flake.planner` (`flake-module.nix:30`) is an attrset of test results: `worked`, `suites`,
`rendered`, `failures` and `failuresBySuite`. `apps.<system>.planner` is the operator's command.
`nix run .#planner` reaches the application because `nix run` looks in `apps` first; every other
command reaches the attrset, and `nix build .#planner` reports `expected flake output attribute
'planner' to be a derivation or path but found a set`. `README.md:42` sends a reader to that name.

`clean-up-transplant-residue` recorded "renaming the `planner*` flake outputs, `flake.planner`" as
an explicit non-goal. That decision was right when it was written: no application held the name, and
renaming would have churned a dozen documented commands for a naming preference.
`apply-deployments-with-an-operator-command` then created `apps.planner`, and the preference became
a collision a reader hits with the second command they type. This change overrules the non-goal and
names it here rather than quietly diverging.

The debug attrset moves to `flake.debug`, not the application. The application's name is the
program's name, it is what an operator installs, and it is what `docs/operator.md` is about. The
attrset is a development convenience whose whole audience reads `docs/tooling.md`, so it is the
side that pays the rename: eleven command lines in `docs/tooling.md`, one in `docs/plan.md`, and one
in `CLAUDE.md`.

## D6 - The walk runs on a machine, not here

`tests/e2e/newcomer/` is worth a boot only if what it observes cannot be observed here. Two claims
were available:

| Claim | Why not |
| --- | --- |
| a scratch flake built on this host produces the store path `.#planner-e2e-newcomer` produces | one comparison covering every input, but it proves a property of two evaluations on the machine that already has the library, its nixpkgs and its store |
| a machine holding nothing but a template and this checkout's source builds the deployment and applies it to two others | the reader's own position, and every step of it is a command that machine runs |

The second. The host computes one thing - the store path `nix flake metadata --json` resolves the
checkout to - and hands the workstation that and the credential the image authorizes with one
`nix copy` inside the cluster's namespace. `nix flake lock --override-input nixplan path:<source>`
is where the template stops naming the published flake and starts naming the tree under test; the
substitution is written into the lock, so it is readable evidence rather than a flag nobody sees.

The template is a committed directory, not a string written at run time. A reader copies a
directory, the folder's own `deployment/default.nix` imports it so the flake still holds one
deployment per folder, and the text a document shows is the text the machine builds.

Store-path equality is not asserted, because the two builds are no longer both here. What replaces
it is stronger about the thing that was uncertain: the artifact each machine runs was built by a
machine that had nothing but the source, and the two entries of one instance are two artifacts,
since the greeting each unit writes names the address its entry was planned for.

## D7 - The document is the fixture

`docs/README.md:52-125` shows an example that plans clean and does not build. The reason a document
can hold an unbuildable example is that nothing builds it. Two ways to stop that:

| Approach | Why not |
| --- | --- |
| a test that extracts fenced blocks from prose and evaluates them | the test owns a parser for markdown, and a document is then written against the parser |
| the document and the fixture are one text, compared | the comparison is a string equality in the evaluating layer, and the fixture is built by the machine layer already |

The second. The block a document shows and the file `tests/e2e/newcomer/deployment/` holds are
compared for equality by a unit test, and the folder is built and applied by the machine layer.
Neither layer learns anything about the other, and a documented example that stops building fails
the build of a folder rather than a reader's afternoon.

This change does not fix what the current example runs into. `pruned` (`lib/plan.nix:559`) drops an
empty `closure` and an absent `units`, and `required` (`image/read.nix:118-123`) refuses the entry
that results, with `mkPlan` reporting an empty table throughout. That is a refusal that is not a
row, which is the rule `report-every-refusal-as-a-row` owns, and its requirement is where the fix
belongs. What this change owns is the claim that makes the defect fail something: the example a
document shows is the example a test builds.

## D8 - The shell's root, and the command it is about

`planner_root="$(git rev-parse --show-toplevel)"` (`devshells.nix:21`) answers about the process's
working directory. `nix develop /path/to/nixplan` from an unrelated repository therefore puts *that*
repository's `tests/e2e` and `cli` on `PYTHONPATH`, and outside a git repository the command fails,
the hook continues, and the exported value is `/tests/e2e:/cli`. Both are silent.

The shell knows its own flake at build time, so the root is a store path the hook already has - the
same value `${./.}` gives the module that writes the hook. Using it turns the failure mode inside
out: a shell entered from anywhere is a shell of the checkout it was built from. Where the intent is
the working tree rather than the store copy - editing `delivery.py` and re-running pytest - the hook
compares the two and refuses with both named, rather than choosing one. `planner-e2e-env`
(`flake-module.nix:193`) has the same line for the same reason and takes the same treatment, except
that it genuinely wants the working tree, so its refusal is "run this from a checkout of nixplan"
rather than a fallback.

`planner` joins the shell's packages. `docs/operator.md` is a document about a command that the one
shell of this repository did not carry, and a reader following it typed `nix run .#planner --` at
every step.

## D9 - `--dry-run` is a flag of `apply`, not a subcommand

Every refusal the command can make from the plan, the deployment record and the value source already
happens before the first dial (`specs/operator/apply-command/spec.md`, *The command refuses before
it dials*). A dry run is that prefix, plus the printed form of the steps the walk would take, and
then a stop.

| Shape | Why not |
| --- | --- |
| a sixth subcommand, `preview` | the argument surface doubles: `--values`, `--only`, `--ssh-key` and `--user` all bear on what the walk would be, so the subcommand is `apply` with one word changed |
| `--dry-run` on `apply` | one flag, and the flag's presence is the only difference between the two runs |
| a dry run that asks each machine what it holds | asking is dialling, and what a machine holds is `status`, which `make-an-apply-observable` owns |

The middle. The output is the lines `apply` prints, in the order `apply` would print them, so the
two runs are comparable by eye and by `diff`. A dry run contacts nothing, which is also what makes
it the answer to "what will this do" from a laptop that cannot reach the machines yet.

## D10 - The help text is somebody's only document

`cli/planner.py:100-136` builds a parser whose help text names five subcommands, a target and four
options. Read as the only document a user has, it cannot reach an applied deployment: nothing says
what makes a directory a built deployment, that a flake reference has to name a `mkDeployment`
result, what a plan key looks like for `--only`, or that `docs/operator.md` exists. `rollback`
enforces exactly one `--only` in the parser and says nothing about it in the help.

The fix is not a second document. `argparse` already carries `epilog` and per-option `help`, and the
facts above are four sentences. What the requirement holds is the standard: a reader with the help
text and no repository can name a target, restrict a run, and find the fuller document. A manual
page was considered and dropped - nothing in this repository installs one, and a page nobody opens
is a second copy of the same four sentences.

## D11 - A documented command either works or names its condition

`docs/tooling.md:278` advertises `nix fmt`. Twenty-three lines later, `docs/tooling.md:301-302` says
the same command "currently fails on files this library does not own", naming neither the files nor
the condition under which it happens. A reader who runs it and sees a failure cannot tell whether
their edit caused it. `treefmt.nix:104-115` excludes `fixtures/**` and `openspec/**` and does not
exclude `workdirs/**`, which holds git worktrees of this same tree and is the obvious candidate -
obvious, and not established by anything committed.

The requirement is therefore about the document rather than about a cause: a command a document
advertises either succeeds on a clean checkout, or the document names exactly what has to be true
for it to. The task that implements it runs the command on a clean checkout and settles which of the
two applies, because guessing at the cause in a specification record would put a third unverified
sentence beside the two that already disagree.

## D12 - Where the test layer stops being the supported place

`flake-module.nix:115-121` discovers a deployment at `tests/e2e/<name>/deployment/default.nix` and
nowhere else. That discovery is right and stays: it is the registration rule for the machine layer,
and `apply-deployments-with-an-operator-command` added it so a folder needs no flake edit.

What was wrong is that it was the only route. With `flake.operator` published, a deployment lives in
the consumer's own tree and reaches `mkDeployment` by name, and the folders under `tests/e2e/` are
what they say they are - tests. The newcomer folder is the proof that the two routes are one: the
folder is discovered by this flake and the same deployment is built by a flake that has never heard
of `tests/e2e`.
