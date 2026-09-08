# Two instances, one wire, and no machine named here: the placements select on
# the tags ./machines.nix carries.
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

    # Planned for the machine tagged `elsewhere`, which declares another
    # architecture. Its image builds, carries and refuses.
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
