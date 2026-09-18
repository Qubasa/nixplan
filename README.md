# nixplan

**WIP**: This is in heavy LLM assisted prototyping phase, not for general use.

A prototype to make selfhosted agentic app distribution feasable.
Problem: You vibe code an app, but you want to distribute it to your friends,
it needs a postgresql on a server and an app with credentials on your friends computer.


Making someone join a space is then equivalent to building a set of user services and handing them over.

We achieve this by allowing services to be deployed anywhere, Android / embedded devices,
even where there is no root and the machine is not part of the space.


---

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

A deployment declares intent and never plumbing. Instantiating a service twice is what the rule
serves: a host path a unit needs is derived by the module that needs it, out of the identity of
its own entry, or reaches that module through an export and a wire, so the second instance gets a
path of its own instead of a collision. Two consequences are checked rather than remembered: no
deployment declaration carries a host path, and a test that has to assert one reads it off the
plan.

## Using it from your own flake

Two outputs are the whole interface: `lib`, the planner, and `operator`, the build over
a plan. Neither is system-specific, because both take your own `pkgs`. `mkLib` is beside
them for a consumer who wants their own package set to elaborate the platform records too.

This is not an illustration of that wiring: it is `tests/e2e/newcomer/template/flake.nix`,
byte for byte, and a machine of `tests/e2e/newcomer/` locks it against this checkout, builds
the deployment it names and applies it to two other machines.

```nix
{
  description = "two machines and one greeting";

  # The published flake, written the way a reader outside this repository writes
  # it. A run of this folder locks the template against the checkout under test
  # instead, with `nix flake lock --override-input`, so this line is never edited
  # and never fetched: the lock records the substitution and the test reads it.
  inputs.nixplan.url = "github:Qubasa/nixplan";

  # One nixpkgs, the one the library is built against. A second pin here would
  # evaluate the deployment against packages the library never saw.
  inputs.nixpkgs.follows = "nixplan/nixpkgs";

  outputs =
    { nixpkgs, nixplan, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = import ./deployment {
        inherit pkgs;
        planner = nixplan.lib;
        operator = nixplan.operator;
      };
    };
}
```

The `template/` directory beside that file holds the deployment: one service, two machines,
and a tag that places it on both. [docs/README.md](docs/README.md) shows it and
[docs/operator.md](docs/operator.md) walks the build and the apply end to end.

## Commands

| Command | What it does |
| --- | --- |
| `nix run . -- --help`, or `nix run .#planner` | the operator's command: `plan`, `build`, `apply`, `status`, `rollback` |
| `nix run .#planner-view -- <target>` | the read-only view of a built deployment, served on the loopback interface: the machines, the entries, the typed edges and the rows. It takes a deployment this checkout can build and a browser to read it in, which this repository does not publish - see [docs/view.md](docs/view.md) |
| `nix build .#checks.x86_64-linux.planner-tests` | the unit suites |
| `nix build .#checks.x86_64-linux.planner-perf` | the evaluation-cost gate |
| `nix build .#checks.x86_64-linux.treefmt` | formatters, linters, type checker and prose |
| `nix develop` | the one shell, with the interpreter the machine layer runs under |

The machine layer needs real VMs, so it is an app rather than a check:
`nix run .#planner-e2e` boots the guests and runs all six folders. It resolves **rookery**
(`git+ssh://git@github.com/Qubasa/rookery`) at run time, and that repository is private and is
not published here: a reader without access to it cannot run that command, and every folder of
the machine layer skips itself saying so. Everything above needs nothing but this checkout.
