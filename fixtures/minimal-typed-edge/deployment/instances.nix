{
  borgRepo,
  borgPush,
}:

{
  instances = {
    vault-repo = {
      module = borgRepo.services.default;
      settings.server.quota = 500;
      placement.every.server = { machines = [ "vault" ]; };

      wire.clients = {
        instance = "nightly";
        provides = "identity";
      };

      exposes = [ "repo" ];
    };

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
