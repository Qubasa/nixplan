## Why

This repository was transplanted out of `universe-deploy`, where the planner was one package
beside a blog and a large design corpus. The library, its two realisers, its tests and its docs
came across; the corpus did not. What is left behind is residue a reader trips over and no check
catches: fifteen path citations in the worked fixture that name folders this repository does not
have, one 53 KB corpus file kept only because two exclusion rows cite it, a performance
measurement whose inputs are the entire repository, and a cross-walk that verifies half of its own
bookkeeping.

## What Changes

- Every path this repository's code, tests, fixtures and documentation name SHALL resolve inside
  it, and a check SHALL fail naming the file and the token when one does not. Records under
  `openspec/` are outside that rule: a record describes the repository as it was when it was
  written.
- The dangling citations in `fixtures/minimal-typed-edge/` are repaired: each one either states the
  fact it was citing or is deleted. The fixture's evaluated content does not change, so
  `plan/backup.json` stays byte-identical. `plan/diagnostics.txt` is a hand-written document rather
  than a generated one - `nix eval --raw .#planner.rendered` is the two rows the deployment
  produces, not that file's 262 lines - so its prose is repaired too, and the rows
  `tests/unit/plan.nix` parses out of it are untouched.
- `notes/unaddressed.md` is deleted. The two exclusion triggers that cite it
  (`lib/excluded.nix:26,58`) and the one documentation row (`docs/diagnostics.md:161`) state their
  fact instead of pointing at a corpus that is not here. The `notes/**` formatter exclusion goes
  with it.
- The repository root gains a `README.md`: what the library is, the tree, and the commands that
  check it. `docs/README.md` stays the reading order for the library itself.
- The performance measurement's inputs narrow from the whole tree to the library, the perf harness
  and the fixture. Editing documentation currently changes the measurement's derivation, which
  makes a cached measurement rarer than it needs to be and puts prose inside a performance result's
  identity.
- The specification cross-walk verifies its second list: an excuse naming a specification that does
  not exist fails, as a missing accountable specification already does.
- **Non-goals**: renaming the `planner*` flake outputs, `flake.planner`, `PLANNER_*` environment
  variables or the library's own name to match the repository's; prose-linting the `openspec/`
  records; archiving the implemented changes; adding CI.

## Capabilities

### New Capabilities

- `tooling/repository-shape`: what may exist in this repository, and which references its files may
  make. Owns the rule that a named path resolves, the rule that every file belongs to a stated
  class, and what the root states about itself.

### Modified Capabilities

- `tooling/nix-unit-suite`: the cross-walk's totality requirement extends to the excuse list, so an
  excuse for a specification that no longer exists is a failure rather than a dead key.
- `tooling/evaluation-performance`: a measurement's inputs are the measured library, the harness and
  the fixture, so a documentation edit does not invalidate it.

## Impact

- `tests/unit/layers.nix`: the path-resolution and stand-in checks generalise from `tests/e2e/` to
  the repository, and gain the file-class rule.
- `tests/unit/coverage.nix`: one more assertion over `excused`; the three specification paths of
  this change enter `accountable` as their tests are written.
- `flake-module.nix`: `plannerSrc = ./.` is replaced by the three inputs `measure.sh` already takes
  separately (`--lib`, `--root`, `--folder`).
- `lib/excluded.nix`, `docs/diagnostics.md`, `fixtures/minimal-typed-edge/**` (comments and prose
  only), `treefmt.nix`, new `README.md`; `notes/` is removed.
- Between this proposal and its implementation `checks.planner-tests` is red: the three new
  `spec.md` files are unclassified until `accountable` names them, which is what the cross-walk is
  for.
