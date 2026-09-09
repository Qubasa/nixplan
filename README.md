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
