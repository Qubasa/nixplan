{
  consumeScript,
  postgresDatabase,
  grouped,
  postgresql,
  initScript,
  bootstrapScript,
  version,
}:

{ service, ... }:
let
  # The composition an author writes first: a consumer and the database it
  # needs, bound inside the module. The binding is the capability value off the
  # sibling's handle, so this file names no instance and no deployment.
  own = service "own" {
    module = import ../postgresql/databases.nix {
      inherit
        postgresql
        initScript
        bootstrapScript
        postgresDatabase
        ;
    };

    fixed.databases.private.owner = "app_private";
    defaults.port = 5432;
    fixed.version = version;
  };

  client = service "client" {
    module = import ./client.nix { inherit consumeScript postgresDatabase grouped; };

    defaults.label = "unnamed";

    wire.db = own.provides.private;
  };
in
{
  services = { inherit own client; };
}
