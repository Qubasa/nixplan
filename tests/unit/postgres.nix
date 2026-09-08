# One provider instance and two consumers, planned in evaluation.
#
# These ten claims were asserted through a serialised corpus: Nix wrote a plan
# to JSON, a Python loader re-typed it, and pytest asserted on the copy. Every
# one of them is an attribute of the value `mkPlan` returns, so they are
# asserted on that value here and the serialisation boundary is gone
# (design.md D7).
#
# Two deployments over one configuration, differing in one line: the first wires
# each application to its own database, the second wires both to `billing`. The
# interface, the two modules and the machine registry are the ones the corpus
# carried, taken here because these claims need them.
{ planner, support }:
let
  inherit (builtins) attrNames;
  inherit (support) rowIds;

  k = planner.korora;

  # Three exports and no bound on either half: what resolves in this subset.
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

  # A literal string. A fixture references a package and realises nothing.
  postgresql = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-postgresql-16.4";

  # One cluster process, one data directory, one capability per database. Which
  # databases exist is the `databases` setting, so the capability set is the
  # deployment's decision and no database name appears in the module.
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

  # An application that puts the database it was handed into its environment.
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
    # The cluster lives here, and one of the two applications with it.
    one = {
      address = "one.example:22";
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };

    # The other application. It reads a provider on `one`: what `reach = "one"`
    # requires is a single placement of the capability, not a shared machine.
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

  # `analytics` is what differs between the two deployments: the database
  # `app-analytics` names.
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

  # Each application owns its own database.
  perApplication = deploymentReading "analytics";

  # Both applications name `billing`. This subset puts no cardinality on a
  # capability, so two readers of one schema resolve.
  sharedDatabase = deploymentReading "billing";
in
{
  # No row and an applicable plan: the whole fleet resolves.
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

  # The value each application reads is the one its own wire named.
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

  # The capability set is derived from a setting the deployment wrote, so it is
  # the deployment's decision and not the module's.
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

  # One reader each, and neither export records the other's reader.
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

  # One cluster entry, not one per consumer.
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

  # `reach = "one"` asks for a single placement of the capability, not a shared
  # machine: the provider is on `one` and this consumer is on `two`.
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

  # A wire is a read, not an ordering: the only edge the consumer carries is the
  # machine it is placed on.
  testAWireAddsNoDependencyEdge = {
    expr = perApplication.plan."app-analytics:server@two".dependsOn;
    expected = [ "machine:two@${perApplication.plan."machine:two".key}" ];
  };

  # Two instances naming one database resolve, and both are handed one value.
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

  # The export both named records both readers.
  testBothReadersAreRecordedOnTheOneExport = {
    expr = sharedDatabase.plan."pg:main@one".provides.billing.exports.dsn.readBy;
    expected = [
      "app-analytics:server@two"
      "app-billing:server@one"
    ];
  };

  # The database nobody named is still published, with nobody recorded on it.
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
