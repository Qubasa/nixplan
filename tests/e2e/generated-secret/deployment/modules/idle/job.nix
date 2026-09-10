{ coreutils }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  # It declares no generator, reads no export and is in no delivery set. Being in
  # the cluster and holding nothing is the whole of what it is here for.
  impl = _: {
    closure = [ coreutils ];

    units.idle = {
      command = "${coreutils}/bin/touch ${settings.markerPath}";
      oneShot = true;
      remainAfterExit = true;
    };
  };
}
