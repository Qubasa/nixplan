# Five deployments from one source. `default` and `changed` differ in the served
# file, which is what gives the redelivery and rollback tests an entry whose
# identity changed. `retired` is the folder's own instances minus `sweep`, so
# the machine stays named and reachable while `sweep:job@alpha` is a holding no
# build names. `probed` and `healthy` declare a probe on the served unit, one
# the page answers and one it does not, and they are builds of their own because
# a probe is a unit field: giving `default` one would put a second unit file in
# the artifact every phase above reads as the entry's only one.
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
    {
      page,
      health ? null,
      without ? [ ],
    }:
    let
      pageModule = {
        services.default = import ./modules/page/default.nix {
          python3 = "${pkgs.python3Minimal}";
          curl = "${pkgs.curl}";
          inherit page health httpEndpoint;
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
      # A build drops an instance rather than declaring its own set: the folder
      # states its instances in one place, and what `retired` is is that
      # statement minus one name.
      instances = removeAttrs deployment.instances without;

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
    args:
    operator.mkDeployment {
      inherit pkgs planner;
      args = argsOf args;
    };

  first = "${pageDirOf "first" "cluster page, first delivery\n"}";
in
{
  default = buildOf { page = first; };
  changed = buildOf { page = "${pageDirOf "second" "cluster page, second delivery\n"}"; };
  retired = buildOf {
    page = first;
    without = [ "sweep" ];
  };
  # The page directory carries `/index.html` and nothing else, so one request
  # the server answers and one it refuses are the two probes.
  probed = buildOf {
    page = first;
    health = "/absent.html";
  };
  healthy = buildOf {
    page = first;
    health = "/index.html";
  };
}
