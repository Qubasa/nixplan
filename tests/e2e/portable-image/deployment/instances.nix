{
  report,
  mirror,
}:
{
  instances = {
    watch = {
      module = report.services.default;
      placement.every.file = {
        tags = [ "attaches" ];
      };
      exposes = [ "report" ];
    };

    mirror = {
      module = mirror.services.default;
      placement.every.copy = {
        tags = [ "elsewhere" ];
      };
      wire.source = {
        instance = "watch";
        provides = "report";
      };
    };
  };
}
