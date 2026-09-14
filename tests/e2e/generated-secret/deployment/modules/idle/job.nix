{ coreutils }:

_: {
  platforms = [ "x86_64-linux" ];

  # It declares no generator, reads no export and is in no delivery set. Being in
  # the cluster and holding nothing is the whole of what it is here for.
  impl =
    { instance, member, ... }:
    {
      closure = [ coreutils ];

      units.idle = {
        command = "${coreutils}/bin/touch /run/${instance}-${member}.ran";
        oneShot = true;
        remainAfterExit = true;
      };
    };
}
