# The nix-unit suite: the evaluating layer of this package's two. One test per
# scenario of the specifications this package answers for, named after that
# scenario by construction, split by subject.
#
# The entry point takes store paths rather than reading the working tree, so
# the suite runs the same way from a check and from a shell:
#
#   nix build .#checks.x86_64-linux.planner-tests
#
# `libSource` is the library, `folder` is
# fixtures/minimal-typed-edge/, `repoSource` is the repository itself, which the
# layer checks read the tree's shape out of, and `changesRoot` is
# `openspec/changes/`, which the cross-walk reads the scenario headings out of.
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

    # The cross-walk takes the names of every suite including its own, because
    # its own tests observe scenarios of `tooling/test-layers` and
    # `tooling/nix-unit-suite` like any other. That is not a cycle: the names
    # are this attrset's keys, which are known without evaluating any value.
    coverage = import ./unit/coverage.nix {
      inherit support changesRoot perfSource;
      unitSuites = unitTestNames;
    };
  };

  unitTestNames = builtins.mapAttrs (_: suite: builtins.attrNames suite) suites;
in
suites
