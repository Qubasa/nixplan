{ coreutils }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  impl = _: {
    closure = [ coreutils ];

    units.rotate = {
      command = "${coreutils}/bin/touch ${settings.markerPath}";
      schedule = "daily";
      oneShot = true;
    };
  };
}
