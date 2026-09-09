# Two deployments from one source that differ in the served file. That is what
# gives the redelivery and rollback tests an entry whose identity changed.
#
# What the folder owns is the packages its modules run and the statement of how
# its entries are realised; the planning, the realising and the collecting are
# the repository's, and arrive as `operator`.
{
  pkgs,
  planner,
  operator,
}:
let
  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) httpEndpoint;

  registry = import ./machines.nix;

  pageDirOf =
    name: text:
    pkgs.writeTextFile {
      name = "cluster-page-${name}";
      destination = "/index.html";
      inherit text;
    };

  argsOf =
    page:
    let
      pageModule = {
        services.default = import ./modules/page/default.nix {
          python3 = "${pkgs.python3Minimal}";
          inherit page httpEndpoint;
        };
      };

      probeModule = {
        services.default = import ./modules/probe/default.nix {
          curl = "${pkgs.curl}";
          inherit httpEndpoint;
        };
      };

      sweepModule = {
        services.default = import ./modules/sweep/default.nix {
          coreutils = "${pkgs.coreutils}";
        };
      };

      deployment = import ./instances.nix {
        page = pageModule;
        probe = probeModule;
        sweep = sweepModule;
      };
    in
    {
      inherit (deployment) instances;
      inherit (registry) machines;

      interfaces = {
        "interfaces/default.nix" = interfaces;
      };

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

  buildOf =
    name: text:
    operator.mkDeployment {
      inherit pkgs planner;
      args = argsOf "${pageDirOf name text}";
    };
in
{
  default = buildOf "first" "cluster page, first delivery\n";
  changed = buildOf "second" "cluster page, second delivery\n";
}
