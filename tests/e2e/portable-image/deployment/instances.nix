{
  report,
  mirror,
  beacon,
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

    # The entry a build is allowed to drop: placed on the booted machine's own
    # tag, wired to nothing and wired from nothing, so `retired` below is the
    # folder's own instances without it.
    beacon = {
      module = beacon.services.default;
      placement.every.ping = {
        tags = [ "attaches" ];
      };
    };
  };
}
