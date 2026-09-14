{ coreutils }:

_: {
  platforms = [ "x86_64-linux" ];

  impl =
    { instance, member, ... }:
    {
      closure = [ coreutils ];

      units.rotate = {
        command = "${coreutils}/bin/touch /run/${instance}-${member}.ran";
        # daily, so the next elapse stays in the future for the whole run. A nearer
        # schedule would fire mid-run, and "timer armed, job never ran" would stop holding.
        schedule = "daily";
        oneShot = true;
      };
    };
}
