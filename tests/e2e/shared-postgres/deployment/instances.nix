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
      settings.client.label = "near";
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
      settings.client.label = "far";
      placement.every.client = {
        tags = [ "far" ];
      };
      wire.client.db = {
        instance = "pg";
        provides = "us";
      };
    };

    # The same module, uncut: it runs the database it owns and wires nothing. Both
    # of its members are on the machine the shared cluster is already on, so the
    # deployment states the port its own listener takes and nothing else.
    own-app = {
      module = app.services.default;
      settings.client.label = "own";
      settings.own.port = 5433;
      placement.every.client = {
        tags = [ "private" ];
      };
      placement.every.own = {
        tags = [ "private" ];
      };
    };
  };
}
