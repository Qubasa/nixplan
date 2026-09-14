{
  cluster,
  app,
}:

{
  instances = {
    # One instance, one placement, two capabilities: the member publishes one per
    # configured database and the root re-exports them under the database's name.
    pg = {
      module = cluster.services.default;
      settings.cluster.databases = {
        eu.owner = "app_eu";
        us.owner = "app_us";
      };
      placement.every.cluster = {
        tags = [ "database" ];
      };
      exposes = [
        "eu"
        "us"
      ];
    };

    # Two cuts of one module. The app composes a consumer and a database of its
    # own; an operator who already runs a cluster removes the database and wires
    # the slot its binding left open. The module source is the same file the
    # third instance below keeps whole.
    near-app = {
      module = app.services.default;
      members.own.enable = false;
      settings.client = {
        label = "near";
        recordPath = "/run/shared-postgres/near.json";
      };
      placement.every.client = {
        tags = [ "near" ];
      };
      wire.client.db = {
        instance = "pg";
        provides = "eu";
      };
    };

    far-app = {
      module = app.services.default;
      members.own.enable = false;
      settings.client = {
        label = "far";
        recordPath = "/run/shared-postgres/far.json";
      };
      placement.every.client = {
        tags = [ "far" ];
      };
      wire.client.db = {
        instance = "pg";
        provides = "us";
      };
    };

    # The same module, uncut: it runs the database it owns and wires nothing.
    own-app = {
      module = app.services.default;
      settings.client = {
        label = "own";
        recordPath = "/run/shared-postgres-own/own.json";
      };
      placement.every.client = {
        tags = [ "far" ];
      };
      placement.every.own = {
        tags = [ "far" ];
      };
    };
  };
}
