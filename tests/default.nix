{
  korora,
  systems,
  folder,
  libSource,
  perfSource,
  repoSource,
  changesRoot,
  imageSource,
  flakeletSource,
}:
let
  planner = import libSource { inherit korora systems; };
  support = import ./unit/support.nix { inherit planner folder perfSource; };
in
let
  suites = {
    interfaces = import ./unit/interfaces.nix { inherit planner support; };
    composition = import ./unit/composition.nix { inherit planner support; };
    resolution = import ./unit/resolution.nix { inherit planner support; };
    diagnostics = import ./unit/diagnostics.nix { inherit planner support libSource; };
    plan = import ./unit/plan.nix { inherit planner support folder; };
    postgres = import ./unit/postgres.nix { inherit planner support; };
    perf = import ./unit/perf.nix { inherit planner support; };
    exclusions = import ./unit/exclusions.nix { inherit planner support; };
    units = import ./unit/units.nix { inherit planner support; };
    platform = import ./unit/platform.nix { inherit planner support systems; };
    closure = import ./unit/closure.nix { inherit planner support; };
    image = import ./unit/image.nix { inherit planner support imageSource; };
    flakelet = import ./unit/flakelet.nix {
      inherit
        planner
        support
        flakeletSource
        imageSource
        ;
    };
    layers = import ./unit/layers.nix { inherit support repoSource; };

    coverage = import ./unit/coverage.nix {
      inherit support changesRoot perfSource;
      unitSuites = unitTestNames;
    };
  };

  unitTestNames = builtins.mapAttrs (_: suite: builtins.attrNames suite) suites;
in
suites
