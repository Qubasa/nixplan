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

Start from the scaffold rather than from a path in this source:

```bash
nix flake init -t github:Qubasa/nixplan
```

That writes one service, two machines and a tag that places it on both. The three blocks
below are the files it writes, byte for byte, and a machine of the end-to-end layer locks
the same text against this checkout, builds the deployment and applies it to two other
machines. Its `flake.nix`:

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

      # The declarations asked with no package set instantiated. `args.nix` takes
      # the packages its modules interpolate, so a stand-in answers for one, and
      # the stand-in is a store path rather than a name: the planner recognises a
      # store path by the store directory and the shape of a hash, so a name it
      # cannot recognise turns the rows about declared closure roots off instead
      # of answering them. Those rows are about whatever was handed in, which is
      # why `packages.default` stays the authority for them.
      asked =
        nixplan.lib.mkPlan
          (import ./deployment/args.nix {
            packages.greeter = "/nix/store/9zv4c8m2kq7r5xn3bdlp6yfs0agh1jw2-greet";
          }).args;
    in
    {
      packages.${system}.default = import ./deployment {
        inherit pkgs;
        planner = nixplan.lib;
        operator = nixplan.operator;
      };

      # The rows and the table rendered from them, under the two names the
      # deployment build publishes them under, so one command reads either
      # answer: `planner diagnose .#diagnostics` here, `planner diagnose
      # .#default` over the build.
      diagnostics = {
        inherit (asked) diagnostics;
        rendered = nixplan.lib.render asked.diagnostics + "\n";
      };
    };
}
```

The deployment has two entry points over one text. `deployment/args.nix` states the
declarations and takes every package a module interpolates as an argument, so the rows it
earns are readable with no package set instantiated:

```nix
# The deployment itself, stated once and with no package set: every package a
# module interpolates is an argument here, so asking what these declarations earn
# costs one evaluation of the library and instantiates nothing. `default.nix`
# beside this file is the other entry point - it builds those packages out of a
# caller's own set and hands the same value to the deployment build.
#
# The ellipsis answers the arguments this deployment needs nothing from: the
# convention hands an `args.nix` the library, the packages and the state its
# generated values exist in, and this one declares no interface and no generator.
{ packages, ... }:
let
  inherit (packages) greeter;

  hello = {
    services.default = import ./modules/hello/default.nix { inherit greeter; };
  };

  deployment = import ./instances.nix { inherit hello; };
  registry = import ./machines.nix;
in
{
  args = {
    inherit (deployment) instances;
    inherit (registry) machines;

    # A module that declares no interface wires to nothing, so the attribution
    # this argument carries is empty rather than absent.
    interfaces = { };

    sources = {
      deployment = "instances.nix";
      machines = "machines.nix";
      modules = {
        greeter = "hello/default.nix";
      };
      leaves = {
        greeter.greet = "hello/greet.nix";
      };
    };
  };
}
```

`deployment/default.nix` composes it with your own package set and builds it, stating no
part of the deployment itself:

```nix
{
  pkgs,
  planner,
  operator,
}:
let
  greeter = pkgs.writeShellApplication {
    name = "greet";
    # `sleep` comes from here rather than from the machine: a unit of a service
    # artifact runs with the PATH the artifact carries, and the machine's own is
    # not a fact the plan records.
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      printf 'hello %s from %s\n' "$GREET_WHO" "$GREET_WHERE" > "$GREET_PATH"
      exec sleep infinity
    '';
  };

  # The deployment is stated in `args.nix` and nowhere else. This file builds the
  # programs its units run and hands the same declarations to the build, so the
  # two entry points differ in the package set and never in the deployment. A
  # module is handed the store path as a string: an unbuilt derivation is an
  # attribute set whose inputs reach nixpkgs' own stdenv, where the reading that
  # walks a unit record runs out of stack.
  deployment = import ./args.nix { packages.greeter = "${greeter}"; };
in
operator.mkDeployment {
  inherit pkgs planner;
  inherit (deployment) args;
}
```

Three more files hold the deployment: the registry, the instances, and the one module a
reader edits first. [docs/README.md](docs/README.md) shows them and
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
