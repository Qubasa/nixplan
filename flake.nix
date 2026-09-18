{
  description = "nixplan";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      # Written out rather than taken from `nix-systems/default`, which names
      # `x86_64-darwin` - a platform the pinned nixpkgs removed with a `throw`, so
      # `nix flake show` died in a release note before it reached an output here.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
        ./flake-module.nix
        ./cli/flake-module.nix
        ./view/flake-module.nix
        ./published/flake-module.nix
        ./devshells.nix
      ];

      perSystem = {
        treefmt = import ./treefmt.nix;
      };

      # The scaffold under a name, so a reader initialises it rather than reading a
      # path inside this source. It names the one directory two documents show and a
      # machine of the end-to-end layer proves, because a published copy would be the
      # second text kept equal by hand that the shown-example check exists to refuse.
      # It is here rather than in `flake-module.nix`, whose text may name no
      # end-to-end folder: a folder is discovered there and never listed.
      flake.templates.default = {
        path = ./tests/e2e/newcomer/template;
        description = "two machines and one greeting: the smallest deployment that works";
        welcomeText = ''
          Two entry points over one deployment text. `deployment/args.nix` states the
          declarations and takes the packages it interpolates; `deployment/default.nix`
          composes it with your own package set and builds it.

          What the declarations earn, with no package set instantiated:

              nix eval --raw .#diagnostics.rendered

          An empty table is a deployment the planner accepts. `nix build .#default` is
          the authority for a row about the store path a package resolves to.

          Four conditions end an evaluation instead of earning a row. Each is named
          with what the interpreter prints and the edit that resolves it, under "What
          ends an evaluation" in the planner's docs/authoring.md.
        '';
      };
    };
}
