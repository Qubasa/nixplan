# nixplan

**WIP**: This is in heavy LLM assisted prototyping phase, not for general use.

A Nix library to define multi machine service deployment that
outputs a JSON deployment plan akin to [disnix](https://github.com/svanderburg/disnix).

It's goal is to be a successor of the [clan inventory](https://clan.lol/docs/unstable/guides/inventory/intro-to-inventory),
while being more composable and fit more broad use-cases.
Main design goals:

- Uses [Modular NixOS services](https://github.com/NixOS/nixpkgs/blob/master/nixos/README-modular-services.md) to make deployment to macOS and embedded systems possible.
- Pluggable generation backend, a plan can generate a systemd [portablectl container](https://systemd.io/PORTABLE_SERVICES/) or a [flakelet](https://github.com/Mic92/flakelet) 
- An API first approach, so no nix eval failures, instead warnings and errors are collected and exposed over an attribute.
- No hard-coded flake dependency, dependency system can be freely chosen, build with [mana](https://github.com/hsjobeki/mana) in mind.
- No global fix point, thus no hidden dependencies between services, instead statically typed interfaces are required to share values.
- Instantiating a service multiple times should be possible.
- Build with replacable secret interfaces, uses [NixOS Vars](https://github.com/NixOS/nixpkgs/pull/547171) by default
- Multiple instances having their own postgresql should be possible.
- Multiple instance sharing a postgresql should be possible.

## What is where

```
lib/       the planner: a deployment in, a plan and a diagnostics table out
image/     a realiser: one plan entry as a systemd portable-service image
flakelet/  a realiser: one plan entry as a flakelet service artifact
operator/  a whole deployment built: the plan, a manifest, one artifact per entry
cli/       the operator's command, `planner`, which builds and applies one
tests/unit/  nix-unit suites over the library, the realisers and the build
tests/e2e/   three folders of real machines, and the harness they share
fixtures/  the worked deployment the unit suites evaluate, with its golden plan
perf/      two synthetic deployments, a measurement harness and committed budgets
docs/      the documentation, starting at docs/README.md
openspec/  the change records this repository was built from
```

## Commands

| Command | What it does |
| --- | --- |
| `nix run .#planner -- --help` | the operator's command: `plan`, `build`, `apply`, `status`, `rollback` |
| `nix build .#checks.x86_64-linux.planner-tests` | the unit suites |
| `nix build .#checks.x86_64-linux.planner-perf` | the evaluation-cost gate |
| `nix build .#checks.x86_64-linux.treefmt` | formatters, linters, type checker and prose |
| `nix develop` | the one shell, with the interpreter the machine layer runs under |

The machine layer needs real VMs, so it is an app rather than a check:
`nix run .#planner-e2e` boots the guests and runs all three folders.
