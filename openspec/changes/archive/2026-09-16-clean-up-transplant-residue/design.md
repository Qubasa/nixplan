## Context

See proposal.md - Why. Three facts about the current tree shape the approach.

`tests/unit/layers.nix` already holds a path scanner: `pathTokens` (`layers.nix:53-67`) pulls every
`./…` and `../…` token out of a file's code lines, `namedPathsOf` resolves each against the
directory of the file that wrote it, and `unresolved`/`outside` fail with the file and the token.
Its scope is `tests/e2e/<folder>/**` only. Extending the scope is the whole of the first
requirement; the mechanism exists.

The dangling references are of three kinds. Fifteen relative literals in
`fixtures/minimal-typed-edge/{interfaces,modules,plan}` name six corpus folders that were never
copied (`../../secrets-per-instance/` 6, `../../firewall/` 3, `../../binary-caches/` 2,
`../../one-daemon-two-networks/` 2, `../../instance-as-group/` 1, `../../quiesce-group/` 1). Three
repo-relative prose references name `notes/unaddressed.md` (`lib/excluded.nix:26,58`,
`docs/diagnostics.md:161`), which exists but is a 53 KB corpus file with no other reader. The
records under `openspec/` name `pkgs/planner/…`, `pkgs/qubasa-blog/…` and
`notes/clan-portable-services-design.md`, which is what a record written in another repository
says.

The measured evaluation's inputs are the whole tree: `flake-module.nix:58` sets
`plannerSrc = ./.` and derives `perfRoot` from it. Measured: appending one byte to `docs/plan.md`
moved `planner-perf-results.drv` from `0h4hjwz4ay6c7sm6r56ch9wpp2h97zri` to
`rnqwyfql8p3ip2g7c5v7p6v1xda2py4b`.

## Goals / Non-Goals

**Goals:**

- One check in the evaluating layer that fails on an unresolvable reference, so the residue cannot
  come back the next time a directory moves.
- The tree's top-level shape stated as data a test reads, rather than as a habit.
- A performance result whose identity is the code it measured.

**Non-Goals:**

- Rewriting the `openspec/` records to describe this repository. A record is evidence of a decision
  taken at a time, and editing it to match a later tree destroys exactly the thing it is for.
- Renaming `planner*` outputs, `flake.planner` or `PLANNER_*` to match the repository name. The
  variables are read by `tests/e2e/runner.py` and named in every document; the rename buys nothing
  a reader does not already have from the flake's description.
- Any change to what the planner computes. `plan/backup.json` is compared field by field by
  `tests/unit/plan.nix`, and this change must leave it byte-identical.

## Decisions

### D1: One scanner, two token classes, resolved differently

A relative token (`./x`, `../x`) is resolved against the directory of the file that wrote it, as
`layers.nix` already does. A repo-relative token - `lib/excluded.nix`, `tests/e2e/wired-pair/`,
`fixtures/minimal-typed-edge/plan/backup.json` - is resolved against the repository root, and is
recognised by its first segment being a top-level entry that exists. That test is what keeps the
scanner off `/run/vars/hostKey/…` (an absolute path on a machine), `ssh://borg@vault.example:22/…`
(a URL), `manager.rs:1349-1392` (a citation into the flakelet endpoint's source) and
`nixos-unstable/…` (a channel). A trailing `:N`, `:N-M` or `:N,M` is stripped before resolving, so
`lib/resolve.nix:377` is a reference to that file.

Alternative considered: scan only path literals an evaluator reads, and leave prose alone. Rejected
because every one of the fifteen dangling citations is in a comment - prose is where this residue
lives, and a check that skips it would have passed on the transplant.

Alternative considered: a shell or CI grep. Rejected: the repository's rule is that a claim about
the tree is a nix-unit test over `readDir`/`readFile` (`tooling/test-layers`), so the check runs
wherever the flake evaluates.

### D2: The scanned set is named, and `openspec/` is not in it

The scanner reads the library, the realisers, the perf harness, the tests, the fixtures, the
documentation and the root's own Nix files. `openspec/` is exempt, and the exemption is asserted by
its own test rather than left as an omission a reader has to notice.

### D3: An exemption states its reason, and there is no allow-list of paths

A reference the scanner cannot resolve is repaired or deleted; there is no list of tolerated
tokens. The one structural exemption is `openspec/` (D2). This is the same discipline
`lib/excluded.nix` applies to constructs: a thing left out carries the sentence saying why, in the
file where the rule lives.

### D4: The fixture is repaired in comments and prose only

Each citation either states the fact it was citing ("a sibling design sketch declares
`localPrivateKey` as a secret export" rather than a path into a folder that is not here) or is
deleted where the sentence survives without it. Three constraints: `tests/unit/exclusions.nix`
parses the README's exclusion table by its header line and counts rows until a blank line
(`exclusions.nix:183-208`), so the table's rows must survive verbatim; no `.nix` file under
`fixtures/` may change in anything but comments, because `tests/unit/plan.nix` and
`tests/unit/composition.nix` evaluate that tree as committed; and `plan/diagnostics.txt` is a
hand-written document, not a generated one, so its prose is repairable but the `  ! ` rows
`tests/unit/plan.nix` parses out of it are not. Measured: `nix eval --raw .#planner.rendered` is
eight lines, the committed file is 262, and every dangling citation in it sits under an `x`
counterfactual row.

### D5: `notes/unaddressed.md` goes, and its two facts move into the rule they justify

`lib/excluded.nix` rows carry a `trigger` sentence - the thing that would bring an excluded
construct back. Two of them currently delegate that sentence to the corpus file. They will state it
("an address assigned only after a daemon authenticates, which two of the twelve mesh sketches
need"), which is what a reader of a refusal wants at the refusal. `docs/diagnostics.md:161`
follows. The `notes/**` formatter exclusion in `treefmt.nix` goes with the directory.

### D6: The measurement takes four explicit inputs, not the tree

`measure.sh` already takes `--lib`, `--root` and `--folder` separately, so the flake passes
`${./lib}`, `${./perf}` and `${./fixtures/minimal-typed-edge}` instead of slicing them out of one
whole-tree store path. One more input is needed and is easy to miss: `perf/eval.nix:24` imports
`./../tests/unit/worked.nix`, the loader that turns the fixture into planner arguments, so
narrowing the store copy would break that relative import. `eval.nix` gains a `worked` argument
(defaulting to `./../tests/unit/worked.nix` for a working-tree run) and `measure.sh` gains
`--worked`, so the four inputs are the library, the harness, the fixture and the fixture's loader.

Alternative considered: `lib.fileset` over the tree. Rejected - it is the same set of inputs
expressed as a filter rather than as four names, and the harness's own flags already name them.

Alternative considered: move `worked.nix` into `perf/`. Rejected: it is the unit layer's loader,
read by `tests/unit/support.nix`, and the perf harness is its second reader.

### D7: One scenario is an omission, with its reason

*A file the measurement does not read is edited* is a property of the flake's derivation inputs.
The evaluating layer cannot observe it without reading the flake that runs it, which is exactly the
second class `omitted` exists for in `tests/unit/coverage.nix`. It goes in `omitted` with that
sentence, and the task that narrows the inputs records the two derivation hashes as its evidence.

### D8: The top-level classes are a table in the test

The test holds one row per top-level entry with the class it belongs to, and fails on an entry that
has no row. A new directory is then a one-line decision at review time rather than an unnoticed
addition.

### D9: The root `README.md` states the repository; `docs/README.md` stays the library's own entry

The root file says what the library is in two sentences, shows the tree, lists the checks and the
two shells, and points at `docs/README.md` for the reading order. It restates nothing else, so the
two files cannot drift into two answers.

## Risks / Trade-offs

- **The scanner flags prose that is not a path** (a package name with a slash, a citation into
  another project's source) → the first-segment test in D1 means a token only counts when its first
  segment is an existing top-level entry of this repository. `manager.rs:1349`, `/run/vars/…` and
  `ssh://…` are all outside that set. Any residual false positive is a signal that a name collides
  with a top-level directory name, which is worth knowing.
- **A repaired comment loses a pointer a reader wanted** → the repair states the fact rather than
  deleting the sentence, so what the citation was evidence for survives; only the unreachable path
  goes.
- **Narrowing the measurement's inputs silently drops a file the evaluation reads** → the failure
  mode is loud: `perf/eval.nix` cannot import what is not in the sandbox, so the perf check fails
  with the missing path rather than measuring something smaller. The four inputs are verified by
  running the gate, not by reading the diff.
- **`checks.planner-tests` is red between this proposal and its implementation** → intended and
  bounded: the three `spec.md` files of this change are unclassified until `accountable` names
  them, which is the cross-walk doing its job. Task 1 closes it first, before any other edit.
- **Deleting `notes/unaddressed.md` loses the corpus's own wording** → the file remains in the
  `universe-deploy` history it came from; what this repository needs from it is two trigger
  sentences, and they end up in the row they justify.

## Migration Plan

Not applicable: no consumer outside this repository reads any of these files, and the flake's
output names do not change.

## Open Questions

- `LICENSE.md` carries `Copyright 2023-2026 Clan contributors`, inherited from the repository this
  code came from. Whether this repository keeps that attribution is the owner's to state; it does
  not affect the specs, the approach or the tasks.
