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
        tags = [ "issues" ];
      };
      exposes = [ "api" ];
    };

    probe = {
      module = probe.services.default;
      placement.every.client = {
        tags = [ "reads" ];
      };
      wire.api = {
        instance = "issuer";
        provides = "api";
      };
    };

    idle = {
      module = idle.services.default;
      placement.every.job = {
        tags = [ "idles" ];
      };
    };
  };
}
