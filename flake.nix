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

    # korora publishes no tags, so the pin is a revision. This one is 2026-01-15.
    korora = {
      url = "github:adisbladis/korora/336685de099953ffd25e8d020cffe9a1de903420";
      flake = false;
    };

    # flakelet publishes no tags either. This revision is 2026-09-07, and it is the
    # endpoint the artifact realiser is proved against.
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
        ./cli/flake-module.nix
        ./devshells.nix
      ];

      perSystem = {
        treefmt = import ./treefmt.nix;
      };
    };
}
