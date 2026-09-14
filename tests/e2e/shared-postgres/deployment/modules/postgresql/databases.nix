{
  postgresql,
  initScript,
  bootstrapScript,
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

  # A default rather than fixed: two listeners on one machine need two numbers,
  # and the planner allocates none.
  claims.ports.postgres = {
    proto = "tcp";
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
      instance,
      member,
      target,
      alloc,
      vars,
      ...
    }:
    let
      # The pair an entry's plan key is built from, minus the machine: the same
      # member placed twice wants one path on each, and two entries of one
      # machine differ in the pair.
      name = "${instance}-${member}";
      stateName = "postgresql/${name}";
      stateDir = "/var/lib/${stateName}";
      configPath = "/etc/${name}/postgresql.conf";
      hbaPath = "/etc/${name}/pg_hba.conf";
      port = toString alloc.ports.postgres;
      specOf = db: "${db}:${ownerOf db}:${vars.${generatorOf db}.password.path}";

      # The cluster's directory, declared rather than made: the service manager owns
      # it for the unit, at the mode the server refuses to start without. Every
      # unit that opens it declares it, and one entry's repeated claim is one
      # claim.
      stateClaim = {
        stateDirectory = [ stateName ];
        stateDirectoryMode = "0700";
      };
    in
    {
      closure = [
        postgresql
        bootstrapScript
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

      # The cluster's one-time initialisation, in a unit of its own: whether it
      # runs is the absence of the file it writes, which is a declaration rather
      # than a shell test on the same path.
      units.bootstrap = stateClaim // {
        command = "${bootstrapScript}/bin/shared-postgres-bootstrap";
        oneShot = true;
        remainAfterExit = true;
        user = "postgres";
        startIfPathAbsent = "${stateDir}/PG_VERSION";
        env.PGDATA = stateDir;
      };

      # The DDL step, run as the cluster's own account: the password is
      # delivered to it, so nothing has to be root to read one.
      units.init = stateClaim // {
        command = "${initScript}/bin/shared-postgres-init";
        oneShot = true;
        remainAfterExit = true;
        user = "postgres";
        after = [ "bootstrap" ];
        requires = [ "bootstrap" ];
        env = {
          PGDATA = stateDir;
          PGCONFIG = configPath;
          PGPORT = port;
          DATABASES = concatStringsSep " " (map specOf names);
        };
      };

      # A configuration file of nothing but literals: its bytes are the plan's,
      # so the realiser assembles them at build time and the artifact carries the
      # file. The socket directory is the data directory because the compiled-in
      # default is `/run/postgresql`, which no plan creates and no machine has.
      configData.${configPath} = {
        mode = "0444";
        reload = [ "server" ];
        render = [
          {
            text = concatStringsSep "\n" [
              "listen_addresses = '0.0.0.0'"
              "port = ${port}"
              "unix_socket_directories = '${stateDir}'"
              "hba_file = '${hbaPath}'"
              "password_encryption = scram-sha-256"
              "max_connections = 32"
              "shared_buffers = '32MB'"
              "logging_collector = off"
              ""
            ];
          }
        ];
      };

      # The authentication file, declared beside the file that names it. Its
      # record is the one a store object carries, stated rather than defaulted,
      # because this deployment is realised by the realiser that binds store
      # objects and installs nothing: a record of its own would be refused.
      configData.${hbaPath} = {
        owner = "root";
        group = "root";
        mode = "0444";
        reload = [ "server" ];
        render = [
          {
            text = concatStringsSep "\n" [
              "local   all all                 trust"
              "host    all all 127.0.0.1/32    scram-sha-256"
              "host    all all ::1/128         scram-sha-256"
              "host    all all 0.0.0.0/0       scram-sha-256"
              ""
            ];
          }
        ];
      };

      # A daemon this fleet keeps: a crash is restarted by the service manager
      # rather than by the next apply.
      units.server = stateClaim // {
        command = concatStringsSep " " [
          "${postgresql}/bin/postgres"
          "-D"
          stateDir
          "-c"
          "config_file=${configPath}"
        ];
        user = "postgres";
        restart = "on-failure";
        restartSec = "1s";
        after = [ "init" ];
        requires = [ "init" ];
      };
    };
}
