{
  korora,
  systems,
  # nixpkgs' own `lib`, for the one suite that reads a rendered script: the image
  # builder takes it, and a suite handing it a restatement would measure the
  # escaping against its own copy rather than against the one the build spends.
  nixpkgsLib,
  platformSource,
  folder,
  libSource,
  perfSource,
  repoSource,
  openspecRoot,
  imageSource,
  operatorSource,
  secretsSource,
  flakeletSource,
}:
let
  planner = import libSource { inherit korora systems platformSource; };
  support = import ./unit/support.nix {
    inherit
      planner
      folder
      perfSource
      korora
      systems
      ;
  };
in
let
  # Adding a suite file means adding it here. This attrset is the only place a suite
  # is registered, and coverage.nix cross-walks its names against the specifications.
  suites = {
    interfaces = import ./unit/interfaces.nix { inherit planner support libSource; };
    composition = import ./unit/composition.nix { inherit planner support; };
    resolution = import ./unit/resolution.nix { inherit planner support; };
    counterexamples = import ./unit/counterexamples.nix {
      inherit
        planner
        support
        operatorSource
        imageSource
        flakeletSource
        secretsSource
        ;
    };
    consumer = import ./unit/consumer.nix {
      inherit
        planner
        support
        korora
        systems
        libSource
        repoSource
        folder
        ;
    };
    diagnostics = import ./unit/diagnostics.nix {
      inherit
        planner
        support
        libSource
        operatorSource
        imageSource
        flakeletSource
        repoSource
        secretsSource
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
    secrets = import ./unit/secrets.nix {
      inherit
        planner
        support
        secretsSource
        operatorSource
        imageSource
        flakeletSource
        ;
    };
    units = import ./unit/units.nix { inherit planner support; };
    platform = import ./unit/platform.nix { inherit planner support systems; };
    closure = import ./unit/closure.nix { inherit planner support; };
    image = import ./unit/image.nix {
      inherit
        planner
        support
        imageSource
        nixpkgsLib
        ;
    };
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
        support
        flakeletSource
        imageSource
        operatorSource
        ;
    };
    layers = import ./unit/layers.nix { inherit support repoSource; };

    # coverage is handed the names of every suite including its own. Not a cycle:
    coverage = import ./unit/coverage.nix {
      inherit
        support
        openspecRoot
        perfSource
        repoSource
        ;
      unitSuites = unitTestNames;
    };
  };

  unitTestNames = builtins.mapAttrs (_: suite: builtins.attrNames suite) suites;
in
suites
