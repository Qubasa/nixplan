{
  page,
  probe,
  sweep,
}:
{
  instances = {
    site = {
      module = page.services.default;
      placement.every.server = {
        tags = [ "serves" ];
      };
      exposes = [ "page" ];
    };

    check = {
      module = probe.services.default;
      placement.every.client = {
        tags = [ "fetches" ];
      };
      wire.upstream = {
        instance = "site";
        provides = "page";
      };
    };

    sweep = {
      module = sweep.services.default;
      placement.every.job = {
        tags = [ "serves" ];
      };
    };
  };
}
