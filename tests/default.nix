{
  korora,
  systems,
  folder,
  libSource,
  perfSource,
  repoSource,
  changesRoot,
  imageSource,
  operatorSource,
  secretsSource,
  flakeletSource,
}:
let
  planner = import libSource { inherit korora systems; };
  support = import ./unit/support.nix { inherit planner folder perfSource; };
in
let
  # Adding a suite file means adding it here. This attrset is the only place a suite
  # is registered, and coverage.nix cross-walks its names against the specifications.
  suites = {
    interfaces = import ./unit/interfaces.nix { inherit planner support; };
    composition = import ./unit/composition.nix { inherit planner support; };
    resolution = import ./unit/resolution.nix { inherit planner support; };
    diagnostics = import ./unit/diagnostics.nix {
      inherit
        planner
        support
        libSource
        operatorSource
        imageSource
        flakeletSource
        ;
    };
    plan = import ./unit/plan.nix {
      inherit
        planner
        support
        folder
        imageSource
        ;
    };
    postgres = import ./unit/postgres.nix { inherit planner support; };
    perf = import ./unit/perf.nix { inherit planner support; };
    exclusions = import ./unit/exclusions.nix { inherit planner support; };
    vars = import ./unit/vars.nix { inherit planner support; };
    secrets = import ./unit/secrets.nix { inherit planner support secretsSource; };
    units = import ./unit/units.nix { inherit planner support; };
    platform = import ./unit/platform.nix { inherit planner support systems; };
    closure = import ./unit/closure.nix { inherit planner support; };
    image = import ./unit/image.nix { inherit planner support imageSource; };
    operator = import ./unit/operator.nix {
      inherit
        planner
        support
        operatorSource
        imageSource
        flakeletSource
        ;
    };
    flakelet = import ./unit/flakelet.nix {
      inherit
        planner
        support
        flakeletSource
        imageSource
        operatorSource
        ;
    };
    layers = import ./unit/layers.nix { inherit support repoSource; };

    # coverage is handed the names of every suite including its own. Not a cycle:
    # attribute names are known without forcing the values.
    coverage = import ./unit/coverage.nix {
      inherit support changesRoot perfSource;
      unitSuites = unitTestNames;
    };
  };

  unitTestNames = builtins.mapAttrs (_: suite: builtins.attrNames suite) suites;
in
suites
