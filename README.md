# nixplan

A Nix library that turns a declarative fleet deployment into a plan: one entry per placed service,
with every cross-service read resolved, every store path declared and every refusal stated as a
diagnostic row rather than a thrown error. Two realisers read that plan and neither adds a field to
it, so what a machine is handed follows from the deployment and nothing else.

## The tree

```
lib/          the library: interfaces, composition, resolution, the plan and its diagnostics
image/        a realiser: a store-less systemd portable service image a machine attaches
flakelet/     a realiser: a store-backed service artifact a running endpoint activates
fixtures/     the worked deployment the suites evaluate as committed, and its golden plan
tests/unit/   the evaluating layer, run by nix-unit
tests/e2e/    the machine layer, run by pytest against booted guests
perf/         the measurement harness, its recorded budgets and the budget checker
docs/         how to use the library
openspec/     the specification records each change is written against
styles/       the prose rules the formatter holds documentation to
```

## Checking it

```bash
nix build .#checks.x86_64-linux.planner-tests -L         # the evaluating layer, one nix-unit run
nix build .#checks.x86_64-linux.planner-perf -L          # measured counters against their budgets
nix build .#checks.x86_64-linux.planner-perf-checker -L  # the budget checker's own tests
nix build .#checks.x86_64-linux.planner-delivery -L      # a delivery onto a booted guest
nix build .#checks.x86_64-linux.treefmt -L               # nixfmt, shellcheck, yamlfmt and vale
nix fmt                                                  # the same formatters, writing
```

Two artifacts are built rather than checked, because each one is bytes a machine takes:

```bash
nix build .#planner-e2e-wired-pair      # the flakelet realiser over the end-to-end deployment
nix build .#planner-e2e-portable-image  # the image realiser over the other one
```

## Two shells

```bash
nix develop .#planner          # the library, its suites and the perf harness
nix develop .#planner-cluster  # the above plus what a real two-machine run needs
```

## Reading it

`docs/README.md` is the reading order for the library itself: what it is, the smallest working
example, and one document each for authoring, diagnostics, the plan artifact, the tooling, the
flakelet realiser and a real cluster.
