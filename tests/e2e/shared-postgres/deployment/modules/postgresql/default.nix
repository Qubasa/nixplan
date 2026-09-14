{
  postgresql,
  initScript,
  version,
  postgresDatabase,
}:

{ service, ... }:
let
  cluster = service "cluster" {
    module = import ./databases.nix { inherit postgresql initScript postgresDatabase; };

    defaults.databases = { };

    # A port is an address, of the same class as a machine's, so a deployment
    # placing a second instance beside this one states its own number. The
    # version is fixed because the data source this module publishes carries it.
    defaults.port = 5432;
    fixed.version = version;
  };
in
{
  services = { inherit cluster; };

  # One capability per configured database, named by the database. The member's
  # resolved settings are what the root reads, so the keyset it re-exports and
  # the keyset the member declared are one value.
  provides = builtins.mapAttrs (db: _: cluster.provides.${db}) cluster.settings.values.databases;
}
