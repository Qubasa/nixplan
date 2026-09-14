{
  postgresql,
  initScript,
  postgresDatabase,
}:

{ settings, ... }:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    listToAttrs
    ;

  names = attrNames settings.databases;
  ownerOf = db: settings.databases.${db}.owner;
  generatorOf = db: "password-${db}";

  over = f: listToAttrs (map (db: f db) names);
in
{
  platforms = [ "x86_64-linux" ];

  # Fixed rather than a default, because the data source this module publishes is
  # built from it.
  claims.ports.postgres = {
    proto = "tcp";
    count = 1;
    fixed = settings.port;
  };

  # One value per database, for the instance rather than per placement: the
  # consumer on another machine has to present the bytes this cluster checks
  # against.
  vars = over (db: {
    name = generatorOf db;
    value = {
      per = "instance";
      # Delivered to the account the cluster runs as, group-readable so a
      # consumer that declares this group opens it too. No unit of this
      # deployment reads a credential as root.
      files.password = {
        secrecy = "secret";
        owner = "postgres";
        group = "postgres";
        mode = "0440";
      };
    };
  });

  provides = over (db: {
    name = db;
    value.interface = postgresDatabase;
  });

  impl =
    {
      target,
      alloc,
      vars,
      ...
    }:
    let
      port = toString alloc.ports.postgres;
      specOf = db: "${db}:${ownerOf db}:${vars.${generatorOf db}.password.path}";
    in
    {
      closure = [
        postgresql
        initScript
      ];

      provides = over (db: {
        name = db;
        value.exports = {
          dsn = "postgresql://${ownerOf db}@${target.address}:${port}/${db}";
          username = ownerOf db;
          password = vars.${generatorOf db}.password;
          version = settings.version;
        };
      });

      # The DDL step, run as the cluster's own account: the password is
      # delivered to it, so nothing has to be root to read one.
      units.init = {
        command = "${initScript}/bin/shared-postgres-init";
        oneShot = true;
        remainAfterExit = true;
        user = "postgres";
        env = {
          PGDATA = settings.dataDir;
          PGPORT = port;
          DATABASES = concatStringsSep " " (map specOf names);
        };
      };

      # A configuration file of nothing but literals: its bytes are the plan's,
      # so the realiser assembles them at build time and the artifact carries the
      # file. The socket directory is the data directory because the compiled-in
      # default is `/run/postgresql`, which no plan creates and no machine has.
      configData."/etc/postgresql/postgresql.conf" = {
        mode = "0444";
        reload = [ "server" ];
        render = [
          {
            text = concatStringsSep "\n" [
              "listen_addresses = '0.0.0.0'"
              "port = ${port}"
              "unix_socket_directories = '${settings.dataDir}'"
              "password_encryption = scram-sha-256"
              "max_connections = 32"
              "logging_collector = off"
              ""
            ];
          }
        ];
      };

      # A daemon this fleet keeps: a crash is restarted by the service manager
      # rather than by the next apply.
      units.server = {
        command = concatStringsSep " " [
          "${postgresql}/bin/postgres"
          "-D"
          settings.dataDir
          "-c"
          "config_file=/etc/postgresql/postgresql.conf"
        ];
        user = "postgres";
        restart = "on-failure";
        restartSec = "1s";
        after = [ "init" ];
        requires = [ "init" ];
      };
    };
}
