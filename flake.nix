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

    korora = {
      url = "github:adisbladis/korora/336685de099953ffd25e8d020cffe9a1de903420";
      flake = false;
    };

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
        ./devshells.nix
      ];

      perSystem =
        { config, pkgs, ... }:
        {
          treefmt = import ./treefmt.nix;

          devShells.default = pkgs.mkShell {
            inputsFrom = [
              config.treefmt.build.devShell
              config.devShells.planner
            ];
          };
        };
    };
}
