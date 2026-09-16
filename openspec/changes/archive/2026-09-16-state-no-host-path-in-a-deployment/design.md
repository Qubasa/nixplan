## Context

See `proposal.md` - Why. What shapes the approach:

- `tests/unit/layers.nix` already scans raw file text of the machine layer: it resolves every path
  token a folder names (`tests/unit/layers.nix:189-218`), refuses a token that leaves the folder,
  compares documented examples byte for byte (`:386-404`), and crosses each folder's unit accounts
  against the guest image (`:604-660`). A text scan is therefore the established mechanism, not a new
  one.
- The scan reads comments too (`CLAUDE.md`, Known bugs), so a path written in a comment counts. That
  is deliberate there and is a hazard here: the rule must be about string literals, or a comment
  naming `/etc` fails the check.
- A derived path is only possible in the implementation half. A default is written in the composing
  module, which does not know the instance (`lib/compose.nix:30-31`), so the knobs being deleted
  cannot merely be given derived defaults.
- Deriving in the implementation needs `instance` and `member`, and `member` arrives with
  `openspec/changes/refuse-two-entries-claiming-one-host-resource`.
- `tests/e2e/newcomer/template/deployment/modules/hello/greet.nix` is shown in `docs/README.md` byte
  for byte (`tests/unit/layers.nix:386-404`), so editing the greeter edits the document in the same
  change.
- `tests/e2e/newcomer`'s test drives a workstation VM and never plans on the host
  (`CLAUDE.md`, End-to-end layer). Reading a path off the plan there means one more command on the
  workstation, not a host-side build.

## Goals / Non-Goals

**Goals:**

- One written rule, in the document a reader opens first, and two checks that hold it.
- Every folder of the machine layer at that rule, including the template a consumer copies.
- A failure that names the file, the line and the path.

**Non-Goals:**

- No library change, no new vocabulary, no new plan field.
- No rule about `fixtures/` or the unit suites' own deployments. Their subject is the library's
  reading rather than a machine, they are placed once, and their paths are compared against goldens;
  a derived path there would move a golden without proving anything about instancing.
- No rule about a path a test invents for itself. `portable-image`'s `/run/planner-assembly` fake
  root and `newcomer`'s `/opt/vendor/greeter` are claims the test makes, not restatements.
- No attempt to detect a host path inside a shell script a module carries. A script receives its paths
  in the environment, which is where the derivation already lands.

## Decisions

**A host path is a literal whose first segment is a machine root.** The list is `etc`, `var`, `run`,
`srv`, `opt`, `tmp`, `usr`, `home`, `root`, `nix`. This is what makes
`tests/e2e/wired-pair/deployment/default.nix:22`'s `"/index.html"` pass - a URL path - while
`"/run/cluster-probe.body"` fails. A first-segment list is a denylist of the roots a machine has,
chosen over an allowlist of permitted paths, which would be a list of the exceptions the rule exists
to remove.

**"Written out in full" means the literal carries no interpolation.** The check reads each line,
splits it on `"`, takes the string fragments, and fails a fragment that begins with `/`, has a machine
root as its first segment and contains no `${`. Splitting on the quote also catches a quoted attribute
name, which is how `configData."/etc/postgresql/postgresql.conf"` is written, and that is exactly a
host path the rule is about.

Alternative rejected: parsing with `ast-grep`. The suite is evaluated by nix-unit inside a pure
evaluation; it has no process to run. Alternative rejected: matching `"/[a-z]` anywhere in the line,
which would flag a comment and a URL.

**The test half is a set intersection per folder, not a pattern.** For each folder, the host paths
appearing in `deployment/**` and the host paths appearing in `test_*.py` are collected, and the
intersection has to be empty. This is what permits a test's own fake root while refusing a
restatement, and it needs no list of exceptions: once the deployments derive their paths, a
deployment has no full literal left to intersect with, so the second check becomes a guard against
regression - a test that hardcodes a path only fails once a deployment states it too, and a
deployment stating one already fails the first check. Both checks are therefore reported together, so
a folder that fails is told which of the two it failed.

**Every folder is brought to the rule in one change.** The alternative - a rule plus an exception list
draining over time - is the state the repository is in now, described as a convention in `CLAUDE.md`
and re-decided per folder. Seventeen sites is small enough to do at once, and each is the same edit:
delete the knob, derive `"${instance}-${member}"` in the implementation, read the path off the plan in
the test.

**The documented example derives too.** `newcomer`'s greeter writes `/run/<instance>-<member>.greeting`
rather than `/run/hello.greeting`, and `docs/README.md` moves with it. A consumer's first example is
where a convention is learned, and the derivation is three more characters of Nix than the literal.

**`newcomer`'s test asks the workstation.** The greeting path comes out of the plan the workstation
built, read with the command already installed there, in the same shape the folder already uses for
its other observations. Nothing about which machine computes what changes.

## Risks / Trade-offs

- **A check over raw text has false positives.** → The two narrowing rules are the machine-root list
  and the interpolation test, and both are asserted by their own scenarios: a URL path passes, a
  derived path passes. A genuine machine-owned literal that has to be written out later - a path the
  machine's own packaging fixes - would need a named exemption, and the check's failure message is
  where that shows up rather than in silence.
- **Five folders are edited at once, and each is a machine-layer folder whose run is minutes.** → The
  folders are independent and each verifies itself with its own `nix run .#planner-e2e <folder>`; no
  stage key moves, because nothing about the guest image or any stage declaration changes.
- **`docs/README.md` and the template must stay byte-equal.** → That equality is already a check
  (`tests/unit/layers.nix:386-404`), so the risk is a failing check rather than a silent drift.
- **A derived path is longer and less readable in a unit file.** → Accepted. What the reader of a unit
  file gains is the instance it belongs to, which is the fact they need when two of them are on one
  machine.
