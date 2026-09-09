{ coreutils }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  # No slot, no generator, no capability. The machine this runs on is in the
  # cluster and in no delivery set, which is the only thing it is here to be.
  impl = _: {
    closure = [ coreutils ];

    units.mark = {
      command = "${coreutils}/bin/touch ${settings.markerPath}";
      oneShot = true;
      remainAfterExit = true;
    };
  };
}
