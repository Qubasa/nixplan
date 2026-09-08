# Two instances, one wire, and no machine named here: the placements select on
# the tags ./machines.nix carries, so this file holds neither a machine name
# nor an address.
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

    # A third entry, scheduled rather than long-running. Delivering it installs
    # a trigger; what starts the unit is the schedule, so one boot can observe
    # an armed timer beside a service that has never run.
    sweep = {
      module = sweep.services.default;
      placement.every.job = {
        tags = [ "serves" ];
      };
    };
  };
}
