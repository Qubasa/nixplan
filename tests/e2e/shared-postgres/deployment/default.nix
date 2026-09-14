# One database cluster serving two databases, and two consumers that each wire
# one of them. The cluster is deployed once; the two consumers are placed
# differently, so one deployment holds both a local and a routable read of the
# same provider.
#
# What the folder owns is the packages its units run and the deployment's own
# text; the planning, the realising and the collecting are the repository's and
# arrive as `operator`.
{
  pkgs,
  planner,
  operator,
}:
let
  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) postgresDatabase;

  inherit (pkgs) postgresql;

  initScript = pkgs.writeShellApplication {
    name = "shared-postgres-init";
    runtimeInputs = [
      postgresql
      pkgs.coreutils
    ];
    text = builtins.readFile ./init.sh;
  };

  bootstrapScript = pkgs.writeShellApplication {
    name = "shared-postgres-bootstrap";
    runtimeInputs = [ postgresql ];
    text = builtins.readFile ./bootstrap.sh;
  };

  consumeScript = pkgs.writeShellApplication {
    name = "shared-postgres-consume";
    runtimeInputs = [
      postgresql
      pkgs.coreutils
    ];
    text = builtins.readFile ./consume.sh;
  };

  clusterModule = {
    services.default = import ./modules/postgresql/default.nix {
      postgresql = "${postgresql}";
      initScript = "${initScript}";
      bootstrapScript = "${bootstrapScript}";
      inherit (postgresql) version;
      inherit postgresDatabase;
    };
  };

  # What the consumer needs to run as an account rather than as root:
  # membership of the group the credential is delivered to, and a runtime
  # directory the service manager creates owned by that account.
  grouped = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      supplementaryGroups = {
        type = planner.korora.listOf planner.korora.string;
      };
      runtimeDirectory = {
        type = planner.korora.string;
      };
    };
  };

  appModule = {
    services.default = import ./modules/app/default.nix {
      consumeScript = "${consumeScript}";
      postgresql = "${postgresql}";
      initScript = "${initScript}";
      bootstrapScript = "${bootstrapScript}";
      inherit (postgresql) version;
      inherit postgresDatabase grouped;
    };
  };

  registry = import ./machines.nix;

  # Two builds of one deployment, differing in one declaration: the second apply
  # has to converge a database that already exists onto the owner the deployment
  # now names, which a first apply of anything cannot show.
  built =
    euOwner:
    let
      deployment = import ./instances.nix {
        cluster = clusterModule;
        app = appModule;
        inherit euOwner;
      };
    in
    operator.mkDeployment {
      inherit pkgs planner;

      args = {
        inherit (deployment) instances;
        inherit (registry) machines;

        interfaces = {
          "interfaces/default.nix" = interfaces;
        };

        # Both passwords are the operator's own bytes, minted by the run and
        # written into its value source. Neither generator names a program, so
        # neither is produced by the external tool.
        varsState = {
          "pg:vars/password-eu".password = {
            present = true;
          };
          "pg:vars/password-us".password = {
            present = true;
          };
          "own-app:vars/password-private".password = {
            present = true;
          };
        };

        sources = {
          deployment = "instances.nix";
          machines = "machines.nix";
          modules = {
            pg = "postgresql/default.nix";
            near-app = "app/default.nix";
            far-app = "app/default.nix";
            own-app = "app/default.nix";
          };
          leaves = {
            pg.cluster = "postgresql/databases.nix";
            near-app.client = "app/client.nix";
            far-app.client = "app/client.nix";
            own-app.client = "app/client.nix";
            own-app.own = "postgresql/databases.nix";
          };
        };
      };
    };
in
{
  default = built "app_eu";
  changed = built "app_eu_next";
}
