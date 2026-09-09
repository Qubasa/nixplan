# nixplan

**WIP**: This is in heavy LLM assisted prototyping phase, not for general use.

A Nix library to define multi machine service deployment that
outputs a JSON deployment plan akin to [disnix](https://github.com/svanderburg/disnix).

It's goal is to be a successor of the [clan inventory](https://clan.lol/docs/unstable/guides/inventory/intro-to-inventory),
while being more composable and fit more broad use-cases.
Main design goals:

- An API first approach, so no nix eval failures, instead warnings and errors are collected and exposed over an attribute.
- No hard-coded flake dependency, dependency system can be freely chosen, build with [mana](https://github.com/hsjobeki/mana) in mind.
- No global fix point, thus no hidden dependencies between services, instead statically typed interfaces are required to share values.
- Pluggable generation backend, a plan can generate a systemd [portablectl container](https://systemd.io/PORTABLE_SERVICES/) or a [flakelet](https://github.com/Mic92/flakelet) 
- Instantiating a service multiple times should be possible.
- Multiple instances having their own postgresql should be possible.
- Multiple instance sharing a postgresql should be possible.



## The tree

```
lib/          the library: interfaces, composition, resolution, the plan and its diagnostics
image/        a realiser: a store-less systemd portable service image a machine attaches
flakelet/     a realiser: a store-backed service artifact a running endpoint activates
fixtures/     the worked deployment the suites evaluate as committed, and its golden plan
tests/unit/   the evaluating layer, run by nix-unit
tests/e2e/    the machine layer, run by pytest against booted guests
perf/         the measurement harness, its recorded budgets and the budget checker
docs/         how to use the library, starting at docs/README.md
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

Three artifacts are built rather than checked, because each one is bytes a machine takes:

```bash
nix build .#planner-e2e-wired-pair       # the flakelet realiser over the wired deployment
nix build .#planner-e2e-portable-image   # the image realiser over the confined one
nix build .#planner-e2e-secret-delivery  # the three services a delivered secret runs between
```

## The shell

```bash
nix develop  # the library, its suites, the perf harness and the formatters
```

The machine layer needs six more variables, each naming a built artifact, and the
rookery it runs under. `eval "$(planner-e2e-env)"` exports them, and builds the guest
image the first time it is called, so entering the shell does not.
