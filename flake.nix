{
  description = "nixplan";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # korora publishes no tags, so the pin is a revision with its date.
    # 336685de099953ffd25e8d020cffe9a1de903420 is 2026-01-15.
    korora = {
      url = "github:adisbladis/korora/336685de099953ffd25e8d020cffe9a1de903420";
      flake = false;
    };

    # flakelet publishes no tags either, so the pin is a revision with its
    # date. 20a676fe96231575d51ff9553d1e31d325c8f0f8 is 2026-09-07. It is the
    # endpoint the artifact realiser is proved against: the VM check activates
    # a planner-built artifact with this binary and this NixOS module.
    flakelet = {
      url = "github:Mic92/flakelet/20a676fe96231575d51ff9553d1e31d325c8f0f8";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        inputs.treefmt-nix.flakeModule
        ./flake-module.nix
      ];

      perSystem =
        { config, pkgs, ... }:
        {
          treefmt = import ./treefmt.nix;

          devShells.default = pkgs.mkShell {
            inputsFrom = [
              config.treefmt.build.devShell
              # python3 and pytest, for the planner's own linters and helpers.
              # `devShells.planner-cluster` is deliberately not here: its pytest is
              # rookery's python 3.13 and its shell builds a 2.2 GB guest image.
              config.devShells.planner
            ];
          };
        };
    };
}
