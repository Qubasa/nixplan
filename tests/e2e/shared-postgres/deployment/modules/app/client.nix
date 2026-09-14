{
  consumeScript,
  postgresDatabase,
  grouped,
}:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  uses.db = {
    interface = postgresDatabase;
    reach = "one";
    # Naming `password` is what puts this machine in that value's delivery set.
    # The other database's value is named by nobody here, so no file of it
    # reaches this machine.
    reads = [
      "dsn"
      "username"
      "password"
      "version"
    ];
  };

  impl =
    {
      instance,
      member,
      results,
      ...
    }:
    let
      # The same pair the database member derives its own paths from, so two
      # instances of this module on one machine share nothing.
      name = "${instance}-${member}";
    in
    {
      # Only the script: its own wrapper resolves psql, so naming the package
      # here would be a declared root the entry mentions nowhere.
      closure = [ consumeScript ];

      units.write = {
        command = "${consumeScript}/bin/shared-postgres-consume";
        env = {
          DB_DSN = results.db.dsn;
          DB_USER = results.db.username;
          # A secret export resolves to its reference record, so the path is
          # asked for by name. Interpolating the export itself raises.
          DB_PASSWORD_FILE = results.db.password.path;
          DB_VERSION = results.db.version;
          LABEL = settings.label;
          RECORD_PATH = "/run/${name}/record";
        };
        # Oneshot and remaining after exit, so "the row went through" is a unit
        # state rather than a log line. The start timeout covers the retry the
        # script makes for cross-machine boot ordering, which is longer than
        # systemd's own default.
        oneShot = true;
        remainAfterExit = true;
        timeout = "300s";
        # Not root. The credential is delivered to the cluster's group and this
        # unit declares membership of it, so the service that uses the password
        # is the service that reads it. Its record goes under a runtime
        # directory the service manager creates for this account.
        user = "nobody";
        extends = [
          {
            extension = grouped;
            values = {
              supplementaryGroups = [ "postgres" ];
              # The directory the record goes in, so two instances of this module
              # on one machine own two directories: the service manager deletes a
              # runtime directory when its unit restarts, and a shared one would
              # take the other instance's record with it.
              runtimeDirectory = name;
            };
          }
        ];
      };
    };
}
