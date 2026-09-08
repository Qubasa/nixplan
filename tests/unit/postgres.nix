{ planner, support }:
let
  inherit (builtins) attrNames;
  inherit (support) rowIds;

  k = planner.korora;

  postgresqlDatabase = k.interface {
    name = "postgresql-database";
    exports = {
      dsn = {
        type = k.url;
        secrecy = "public";
      };
      username = {
        type = k.string;
        secrecy = "public";
      };
      version = {
        type = k.string;
        secrecy = "public";
      };
    };
  };

  postgresql = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-postgresql-16.4";

  cluster =
    { settings, ... }:
    let
      each =
        f:
        builtins.listToAttrs (
          map (db: {
            name = db;
            value = f db;
          }) settings.databases
        );
    in
    {
      platforms = [ "x86_64-linux" ];

      claims.ports.sql = {
        proto = "tcp";
        count = 1;
        fixed = 5432;
      };

      provides = each (_: {
        interface = postgresqlDatabase;
      });

      impl =
        { machine, alloc, ... }:
        {
          provides = each (db: {
            exports = {
              dsn = "postgresql://${db}_owner@${machine}.example:${toString alloc.ports.sql}/${db}";
              username = "${db}_owner";
              version = "16.4";
            };
          });

          closure = [ postgresql ];

          units.postgres.command = "${postgresql}/bin/postgres -D ${settings.dataDir} -p ${toString alloc.ports.sql}";
        };
    };

  appServer = _: {
    uses.db = {
      interface = postgresqlDatabase;
      reads = [
        "dsn"
        "username"
      ];
    };

    impl =
      { results, ... }:
      {
        units.app = {
          command = "/bin/app";
          env = {
            DATABASE_URL = results.db.dsn;
            DATABASE_USER = results.db.username;
          };
        };
      };
  };

  postgresRoot =
    { service, ... }:
    let
      main = service "main" {
        module = cluster;
        defaults = {
          dataDir = "/var/lib/pg-shared";
          databases = [ ];
        };
      };
    in
    {
      services = { inherit main; };
      provides = main.provides;
    };

  appRoot =
    { service, ... }:
    {
      services.server = service "server" { module = appServer; };
    };

  machines = {
    one = {
      address = "one.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    two = {
      address = "two.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };

  sources = {
    deployment = "deployment/instances.nix";
    machines = "deployment/machines.nix";
    modules = {
      pg = "postgresql/default.nix";
      app-billing = "app/default.nix";
      app-analytics = "app/default.nix";
    };
    leaves = {
      pg.main = "postgresql/cluster.nix";
      app-billing.server = "app/server.nix";
      app-analytics.server = "app/server.nix";
    };
  };

  deploymentReading =
    analytics:
    planner.mkPlan {
      inherit machines sources;
      interfaces."interfaces/default.nix" = { inherit postgresqlDatabase; };
      instances = {
        pg = {
          module = postgresRoot;
          placement.every.main.machines = [ "one" ];
          settings.main.databases = [
            "billing"
            "analytics"
          ];
          exposes = [
            "billing"
            "analytics"
          ];
        };

        app-billing = {
          module = appRoot;
          placement.every.server.machines = [ "one" ];
          wire.db = {
            instance = "pg";
            provides = "billing";
          };
        };

        app-analytics = {
          module = appRoot;
          placement.every.server.machines = [ "two" ];
          wire.db = {
            instance = "pg";
            provides = analytics;
          };
        };
      };
    };

  perApplication = deploymentReading "analytics";

  sharedDatabase = deploymentReading "billing";
in
{
  testTheFleetResolves = {
    expr = {
      rows = rowIds perApplication;
      applicable = perApplication.applicable;
    };
    expected = {
      rows = [ ];
      applicable = true;
    };
  };

  testEachApplicationIsHandedItsOwnDatabase = {
    expr = {
      billingUrl = perApplication.plan."app-billing:server@one".env.DATABASE_URL;
      analyticsUrl = perApplication.plan."app-analytics:server@two".env.DATABASE_URL;
      billingUser = perApplication.plan."app-billing:server@one".env.DATABASE_USER;
      analyticsUser = perApplication.plan."app-analytics:server@two".env.DATABASE_USER;
    };
    expected = {
      billingUrl = "postgresql://billing_owner@one.example:5432/billing";
      analyticsUrl = "postgresql://analytics_owner@one.example:5432/analytics";
      billingUser = "billing_owner";
      analyticsUser = "analytics_owner";
    };
  };

  testTheDeploymentDecidesWhichDatabasesExist =
    let
      cluster' = perApplication.plan."pg:main@one";
      setting = cluster'.settings.main.databases;
    in
    {
      expr = {
        source = setting.source;
        published = attrNames cluster'.provides;
        fromTheSetting = planner.util.sortStrings setting.value;
      };
      expected = {
        source = "deployment";
        published = [
          "analytics"
          "billing"
        ];
        fromTheSetting = [
          "analytics"
          "billing"
        ];
      };
    };

  testTheTwoReaderListsAreDisjoint =
    let
      exports = capability: perApplication.plan."pg:main@one".provides.${capability}.exports;
    in
    {
      expr = {
        billing = (exports "billing").dsn.readBy;
        analytics = (exports "analytics").dsn.readBy;
      };
      expected = {
        billing = [ "app-billing:server@one" ];
        analytics = [ "app-analytics:server@two" ];
      };
    };

  testOneClusterEntryServesBothApplications = {
    expr = {
      keys = attrNames perApplication.plan;
      units = attrNames perApplication.plan."pg:main@one".units;
    };
    expected = {
      keys = [
        "app-analytics:server@two"
        "app-billing:server@one"
        "machine:one"
        "machine:two"
        "pg:main@one"
      ];
      units = [ "postgres" ];
    };
  };

  # reach = "one" asks for a single placement of the capability, not for a shared
  # machine.
  testAReachOneReadCrossesAMachineBoundary =
    let
      read = perApplication.plan."app-analytics:server@two".reads.db;
    in
    {
      expr = {
        reach = read.reach;
        delivered = read.delivered;
        entry = read.entry;
        provider = perApplication.plan."pg:main@one".placement.machines;
        consumer = perApplication.plan."app-analytics:server@two".placement.machines;
      };
      expected = {
        reach = "one";
        delivered = true;
        entry = "pg:main@one";
        provider = [ "one" ];
        consumer = [ "two" ];
      };
    };

  testAWireAddsNoDependencyEdge = {
    expr = perApplication.plan."app-analytics:server@two".dependsOn;
    expected = [ "machine:two@${perApplication.plan."machine:two".key}" ];
  };

  testTwoInstancesReadingOneDatabaseResolve = {
    expr = {
      rows = rowIds sharedDatabase;
      applicable = sharedDatabase.applicable;
      sameUrl =
        sharedDatabase.plan."app-billing:server@one".env.DATABASE_URL
        == sharedDatabase.plan."app-analytics:server@two".env.DATABASE_URL;
    };
    expected = {
      rows = [ ];
      applicable = true;
      sameUrl = true;
    };
  };

  testBothReadersAreRecordedOnTheOneExport = {
    expr = sharedDatabase.plan."pg:main@one".provides.billing.exports.dsn.readBy;
    expected = [
      "app-analytics:server@two"
      "app-billing:server@one"
    ];
  };

  testAnExportNobodyNamedKeepsAnEmptyReaderList =
    let
      unnamed = sharedDatabase.plan."pg:main@one".provides.analytics;
    in
    {
      expr = {
        exports = attrNames unnamed.exports;
        readBy = unnamed.exports.dsn.readBy;
      };
      expected = {
        exports = [
          "dsn"
          "username"
          "version"
        ];
        readBy = [ ];
      };
    };
}
