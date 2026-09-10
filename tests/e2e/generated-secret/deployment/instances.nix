{
  issuer,
  probe,
  idle,
}:
{
  instances = {
    issuer = {
      module = issuer.services.default;
      placement.every.api = {
        tags = [ "attests" ];
      };
      exposes = [ "api" ];
    };

    probe = {
      module = probe.services.default;
      placement.every.client = {
        tags = [ "verifies" ];
      };
      wire.api = {
        instance = "issuer";
        provides = "api";
      };
    };

    idle = {
      module = idle.services.default;
      placement.every.job = {
        tags = [ "waits" ];
      };
    };
  };
}
