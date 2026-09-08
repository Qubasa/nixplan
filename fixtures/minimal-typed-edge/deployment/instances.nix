{
  borgRepo,
  borgPush,
}:

{
  instances = {
    # Two instances, two wires, and the wires point at each other. Reading them
    # as a cycle is the mistake ../plan/diagnostics.txt has a row for; §29.5 is
    # why there is none.
    vault-repo = {
      module = borgRepo.services.default;
      settings.server.quota = 500;
      placement.every.server = { machines = [ "vault" ]; };

      # The set-valued wire. `provides = "identity"` names a capability the
      # `nightly` instance exposes, and `reach = "all"` in
      # ../modules/borg-repo/server.nix decides that the far end is every
      # placement of it rather than one. The deployment writes neither the arity
      # nor the machine list: the arity is the module's declaration and the list
      # is `nightly`'s placement.
      #
      # This is the line clan-core has no spelling for. There, a consumer indexes
      # a clan-global attrset keyed by the string
      # "service:instance:role:machine" (`clan-core/lib/exports/exports.nix:25`), so the
      # far end is chosen inside the consuming module by string arithmetic and a
      # typo is a missing attribute rather than a row.
      wire.clients = {
        instance = "nightly";
        provides = "identity";
      };

      exposes = [ "repo" ];
    };

    # Three placements from one tag, and the tag is the only place a machine list
    # appears in this folder. `placement.every` is clan's `roles.<r>.tags` with
    # the same meaning and no third field, and it needs no allocation row of its
    # own: its placements are a function of the deployment and the registry, so
    # they reproduce without anything persisted.
    #
    # `placement.pick` is not here and is not needed. Nothing in this deployment
    # delegates a choice, and `pick` is what would make the planner stateful.
    nightly = {
      module = borgPush.services.default;
      settings.client.path = "/home";
      placement.every.client = { tags = [ "backed-up" ]; };

      wire.repo = {
        instance = "vault-repo";
        provides = "repo";
      };

      exposes = [ "identity" ];
    };
  };
}
