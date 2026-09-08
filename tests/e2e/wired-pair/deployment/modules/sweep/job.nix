{ coreutils }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  impl = _: {
    closure = [ coreutils ];

    units.rotate = {
      command = "${coreutils}/bin/touch ${settings.markerPath}";
      # daily, so the next elapse stays in the future for the whole run. A nearer
      # schedule would fire mid-run, and "timer armed, job never ran" would stop holding.
      schedule = "daily";
      oneShot = true;
    };
  };
}
