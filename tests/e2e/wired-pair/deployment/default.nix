# The only glue: close the package strings, import this directory's own
# interfaces, modules and deployment, and hand `mkPlan` its arguments.
#
# Nothing under this directory is edited from here. `packages.page` is the
# directory the served file lives in, which is what a caller varies to produce a
# second, observably different, deployment of the same source.
{
  planner,
  packages,
}:
let
  inherit (packages)
    python3
    curl
    coreutils
    page
    ;

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) httpEndpoint;

  pageModule = {
    services.default = import ./modules/page/default.nix {
      inherit python3 page httpEndpoint;
    };
  };

  probeModule = {
    services.default = import ./modules/probe/default.nix {
      inherit curl httpEndpoint;
    };
  };

  sweepModule = {
    services.default = import ./modules/sweep/default.nix { inherit coreutils; };
  };

  deployment = import ./instances.nix {
    page = pageModule;
    probe = probeModule;
    sweep = sweepModule;
  };
  registry = import ./machines.nix;
in
{
  inherit interfaces;

  args = {
    inherit (deployment) instances;
    inherit (registry) machines;

    interfaces = {
      "interfaces/default.nix" = interfaces;
    };

    # Row subjects: a module file relative to modules/, everything else relative
    # to this directory.
    sources = {
      deployment = "instances.nix";
      machines = "machines.nix";
      modules = {
        site = "page/default.nix";
        check = "probe/default.nix";
        sweep = "sweep/default.nix";
      };
      leaves = {
        site.server = "page/server.nix";
        check.client = "probe/client.nix";
        sweep.job = "sweep/job.nix";
      };
    };
  };
}
