## Context

See `proposal.md` — Why. Requirements are in `specs/planner/typed-edge/`, `specs/planner/diagnostics/`, `specs/planner/plan-artifact/`, `specs/tooling/evaluation-performance/` and `specs/tooling/nix-unit-suite/`. This document covers how those are arrived at and where the boundaries fall.

Four facts about the current repository shape everything below.

This repository has never held executable design code. `pkgs/qubasa-blog/` is a site, `notes/` is a design record and seven worked example folders, and `openspec/specs/` is empty. Three OpenSpec changes have landed and all three wrote prose. This change therefore introduces a source tree, a test runner, a measurement harness and a budget file at once, and each of those is a first.

The subject folder is a counter-proposal. `fixtures/minimal-typed-edge/interfaces/exports.nix` writes two-field export atoms where adopted `§32.1` writes four, and `plan/diagnostics.txt`'s last gap row says so and names the change that owes the narrowing. That change is not this one. The library implements two fields because two is what the subset needs, and it refuses the other two loudly rather than accepting them, so nothing here can be read as `§32` having been narrowed by implementation.

The expected output already exists and is partly fictional. `plan/backup.json` was written by hand, elides two entries by name, and carries invented key hashes such as `sha256-a41e07d2` and shortened store paths such as `/nix/store/8m2c...-borgbackup-1.4.0`. It is a reviewed expectation rather than a golden file, and turning it into one is real work with a real chance of finding the design wrong.

The measurement question has an answer that is better than the obvious one. On this repository's Nix, 2.35.2, `NIX_SHOW_STATS_PATH` counters are byte-identical across repeated runs of one expression while `cpuTime` moves by roughly fifteen per cent over three runs of the same trivial recursion. Allocation counts are therefore a gate and wall clock is not, which is what makes a performance budget usable in CI on the first day rather than after somebody has tuned the noise out of it.

## Goals / Non-Goals

**Goals:**

- One evaluable library whose refusals are the ones the folder argues for, so the argument becomes checkable rather than repeated.
- A fixture reconciliation that produces evidence: every difference between the hand-written plan and the first generated one is recorded and answered, and some of those answers will be corrections to the folder.
- Budgets that fail a build on day one, expressed so that they stay meaningful as fixtures grow.
- A test suite whose coverage obligation is mechanical, because the specifications are almost entirely refusals and a missed refusal is invisible.

**Non-Goals:**

- Any part of the runtime plane. No orchestrator, no host agent, no register, no activation. `posts/02-the-deployment-plan.md` draws the line and this change stays above it.
- Any construct the folder's own exclusion table defers: `locality`, `lifecycle`, probes, facts, `per`, `deploy`, routable secrets, `placement.pick`, `strategy`, member cuts, externals, and the collect family. Each is refused with a row naming its trigger rather than silently ignored.
- Deriving anything. Packages enter fixtures as literal store path strings.
- Changing the status of any section of `notes/clan-portable-services-design.md`.
- Extending the blog series, which is closed at seven parts.

## Decisions

### The source tree is the repository root

The specification grouping `planner/` was established by `add-collect-slot-chain-rules` and the blog calls this component the planner throughout, so the directory keeps the same word: a reader moving between `openspec/specs/planner/` and the code does not have to translate. It sits under `pkgs/` beside `pkgs/qubasa-blog/`, on instruction, so that every source tree this repository owns is reachable from one directory and the flake module sits where the other flake module sits.

*Alternative considered: `planner/` at the repository root.* It was the original decision here, on the grounds that every other entry under `pkgs/` is a derivation and a pure library that realises nothing is not one. Overruled: the library is exposed as `packages.<system>.planner-perf` plus a `checks` entry, so the tree does carry derivations, and one directory for owned source beats a taxonomy nobody has to maintain.

The tree is a library directory, a tests directory and a perf directory, plus `flake-module.nix` imported from `flake.nix` beside the blog's. `treefmt.nix` excludes `notes/**` and `.beads/**` and nothing else that matters here, so the repository root is formatter-clean from its first commit and needs no exclusion added.

### korora is pinned by revision and only its non-raising entry point is used

korora publishes no tags. `git ls-remote --tags` on `adisbladis/korora` returns nothing, so a version pin is a revision pin with a date comment, and revision `336685de099953ffd25e8d020cffe9a1de903420` is what the current branch resolves to. It is not in nixpkgs, so it is a new flake input.

korora offers two ways to apply a type. `verify` returns null on success and a string on failure. `check` raises. The library uses `verify` exclusively, and a test greps library source for `check` and for raise builtins, because the total-evaluation property in `specs/planner/diagnostics/` is exactly the kind of property that one convenient call deletes. korora's error strings are already the message half of a diagnostic record, so the type layer needs no wrapper beyond attaching a subject.

Two atoms the folder writes do not exist upstream. `korora.url` and `korora.secretRef` appear in `interfaces/exports.nix` and korora has neither, so the library defines them with `korora.typedef` and exposes them on the value it hands to interface files. This is worth stating because it means the folder's `interfaces/exports.nix` is evaluable as written, without an edit, which is the first small piece of evidence that the surface is real.

### nix-unit comes from the pinned nixpkgs, not from its own flake

`nix-unit` is in the repository's already-pinned nixpkgs at 2.35.1, which is also its latest upstream tag. Taking it from there rather than adding `github:nix-community/nix-unit` as an input avoids a second nixpkgs and a second Nix in the lock file, and avoids the skew where the test runner links one interpreter while the developer's shell runs another.

*Alternative considered: the nix-unit flake as an input.* Rejected on lock-file size and on the skew. The trade is that a nixpkgs bump can move the runner underneath the suite; the performance harness already records the interpreter version with every measurement, so that move shows up as an invalidated comparison rather than as a silent change.

### The pipeline is the adopted eight rounds with three of them absent

`posts/03-evaluation-order.md` traces eight rounds. This subset runs five of them and refuses the inputs the other three would serve.

Round 1 evaluates each instance's root with its settings. Round 2 evaluates each member's asking half. Round 3 turns slots into edges, which is where wire resolution, interface identity, the `reads` membership check and the secrecy refusal all land. Round 6 places from `placement.every` and allocates fixed port claims. Round 7 calls `impl` in dependency order, produces exports, and checks keyset equality and arity.

Round 4, joining requirements against published facts, is absent because there is no fact register and this subset declares no requirements. Round 5, turning locality into co-placement, is absent because no atom carries a locality; this is the same deletion the folder argues for, and it is why `reach = "local"` is a refusal here rather than a third value. Round 8's plane derivation collapses to a single rule, since with no lifecycle tag the plane is decided by where `impl` put the value and nothing else.

Allocation deserves its own sentence. The folder's only claim is `fixed`, so the library satisfies fixed claims and refuses a claim without one, with a row saying that dynamic allocation needs the persisted allocation table this subset does not carry. Refusing is better than inventing a port, because a port chosen without a persisted table would move on the next evaluation and re-key the entry that claimed it.

### Diagnostics accumulate in the return value

Every internal function returns its value alongside the rows it produced, and callers concatenate. No mutable accumulator and no ambient list exists, because either would be a second way for a row to exist and the folder's whole subject is that a check nothing enforces gets skipped.

Row order is made deterministic by sorting on the identifier and then the subject before rendering. `specs/planner/diagnostics/` requires two runs over one input to produce equal tables including order, and attribute set traversal order in Nix is by key rather than by insertion, so the sort is what makes the guarantee hold across a refactor that changes where a row is produced.

The subject of a row is a plan key, a path relative to the deployment root, or an issue identifier. Absolute paths are refused because they would make a rendered table differ between two checkouts, which would break both the golden comparison and any future review of a rendered file.

### Total evaluation is bounded by what the interpreter lets a caller catch, and the boundary is written down

`builtins.tryEval` on this Nix catches `throw` and a failed `assert`. It does not catch `abort`, and it does not catch a missing attribute: `builtins.tryEval (let s = {}; in s.nope)` propagates rather than returning a record. It is also lazy, so `builtins.tryEval { a = throw "x"; }` reports success and only `builtins.tryEval (builtins.deepSeq x true)` reports the failure.

Three things follow. The property test forces deeply inside the catch. A missing attribute inside library source is a bug that fails the suite loudly, which is right. And the claim the library makes is "no library path raises", verified by construction and by a source-text check, rather than "nothing can raise", which would be false and which `specs/planner/diagnostics/` therefore does not say.

### The hand-written plan is reconciled once and then becomes the fixture

`plan/backup.json` cannot be the comparison target as it stands. Two of five entries are elided by name, every key hash is invented, and every store path is shortened with an ellipsis. The first generated plan is therefore diffed against it field by field, and every difference is put into one of three buckets: a placeholder the fixture never claimed to be real, a correction to the folder because the generated value is right, or a defect in the library. The third bucket is the point of the exercise.

The reconciled file replaces the hand-written one, the `elided` block moves to the README where the argument for eliding two entries still serves a reader, and a test refuses a fixture that still carries an ellipsis or an invented hash. Prose fields are excluded from the comparison by an explicit key list rather than by a heuristic, so adding a note to the fixture cannot silently weaken the test.

The diagnostics file is compared differently. It is hand-wrapped prose with five counterfactual rejections and five gap rows that this deployment does not produce, so a byte comparison is meaningless. The comparison is over the rows this deployment produces: the identifier, the subject, the severity and the message, against the two rows the committed file marks as belonging to the deployment.

### Performance gates on allocation counts, normalised per plan entry, with a two-sided ratchet

The measurement is `NIX_SHOW_STATS_PATH` over one evaluation that forces the plan deeply. The gated counters are the ones observed to be reproducible: thunk count, function calls, primop calls, value count, set and environment bytes, list elements, update copies and total bytes collected. Three runs of one expression produced identical figures for all of them; `cpuTime` over the same three runs moved from 0.0138 to 0.0159, which is why it reports and never gates.

Each budget is a cost per plan entry rather than a total. A fixture that grows by an entry then consumes no headroom, which matters because the worked deployment is about to gain the two entries the fixture elides.

The ratchet runs in both directions. A measurement above budget fails, and a measurement materially below budget also fails, with the message carrying the figure to paste into the budget file. One-sided budgets rot: an optimisation lands, the slack is never reclaimed, and a later regression hides inside it. The margin that counts as material lives in the budget file rather than in the harness, so that widening it is a reviewable edit.

*Alternative considered: gate on wall clock with a generous multiplier.* Rejected. A multiplier wide enough to survive a loaded CI runner is wide enough to hide the regression that matters, and the counters make it unnecessary.

### The scaling gate exists because of one specific quadratic

A synthetic deployment is generated at four fleet sizes and the growth of each gated counter is checked against a bound the budget file states. The synthetic deployment must contain a set-valued read whose provider is placed on every machine, because that is where the square hides: resolving `reach = "all"` naively for every consumer walks every placement, and with a consumer per machine that is the fleet size squared. The folder's own deployment has four machines and would never show it.

The generator is a pure function of the fleet size. No time, no filesystem, no environment, so two runs at one size produce equal deployments and the comparison across sizes is a comparison of the library rather than of the fixture.

### The blast radius is one file in `notes/`

`fixtures/minimal-typed-edge/plan/backup.json` gets reconciled and `README.md` gets the `elided` explanation plus two rows in its file table. Nothing else under `notes/` changes, no sibling folder is touched, and `notes/clan-portable-services-design.md` gains nothing. This is what the scope decision in the proposal buys, and it is worth naming as a design property rather than leaving it implied: the implementation is falsifiable against the corpus precisely because it did not get to edit the corpus first.

## Risks / Trade-offs

**The reconciliation finds the folder wrong in a way that changes the surface.** → That is a success rather than a failure, and the tasks treat it as one: differences are recorded with their resolution, and a difference that means a construct is wrong stops the change and opens a bead rather than being papered over in the fixture. The two most likely candidates are the shape of a `reach = "all"` entry whose bytes are absent, and whether `configData` recorded as not computed is a field or an absence.

**A missing attribute in library source escapes the total-evaluation property.** → Accepted and documented. `tryEval` does not catch it, and catching it would need every attribute access in the library to go through a helper, which costs more than it buys. The suite fails loudly instead, and `specs/planner/diagnostics/` says which failures the library contains and which it does not.

**Budgets recorded against one interpreter go stale on a nixpkgs bump.** → The harness records the interpreter version with every figure and reports a version mismatch as an invalid comparison rather than a failure, so a bump produces a task rather than a red build nobody can act on.

**The two-sided ratchet is noisy while the library is young.** → Expected during initial development and cheap to answer, because the failure message carries the replacement figure. If it becomes a burden the margin widens in the budget file, which is one reviewable line.

**korora is a single-maintainer dependency with no releases.** → It is a small pure-Nix library pinned by revision, the library uses one entry point of it, and the type layer is the piece with the clearest replacement path if that ever matters. Recording it here so the choice is visible rather than inherited.

**Five specifications for one library is a lot of surface for a first change.** → Two of the five are about this repository's own tooling rather than about the planner, and they are the two that would otherwise never get written down. The coverage obligation in `specs/tooling/nix-unit-suite/` is what keeps the other three honest.

## Migration Plan

Nothing is deployed and nothing is replaced, so there is no rollback beyond reverting a commit. Two ordering constraints are real.

The library has to produce a plan before the fixture can be reconciled, and the fixture has to be reconciled before the golden test can pass. The golden test is therefore written first and expected to fail, the reconciliation is a reviewed step with its own record, and only then does the suite go green.

Budgets have to be recorded against a library that already evaluates the worked deployment and the synthetic fleet, and they have to be committed in the same change rather than a later one. The proposal says from the first commit that adds the library, and the tasks order it that way: harness first, then the figures it produced, then the gate that enforces them.

## Open Questions

Whether the reconciled fixture should also carry the rendered diagnostics as a committed file, or whether comparing the row records is enough. Comparing records is what the specification requires and it is what the tasks implement. A rendered file would additionally pin the row format, which is useful the day a second folder is converted and useless before then. Deferrable because adding it later changes no requirement and no task already written.
