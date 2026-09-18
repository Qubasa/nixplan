{
  beacon,
  probeCommand,
}:

_: {
  platforms = [ "x86_64-linux" ];

  impl =
    {
      instance,
      member,
      ...
    }:
    let
      # Both derived from the entry's own identity, because this folder's
      # deployment writes no host path: a second entry of this module on one
      # machine claims its own directory and writes its own file.
      directory = "${instance}-${member}";
      heartbeat = "/run/${directory}/beacon.txt";
    in
    {
      # Only the scripts are closure roots. Everything they run is a reference
      # of one, and the probe is a root because a unit field naming a store path
      # the entry does not declare is a row.
      closure = [ beacon ] ++ (if probeCommand == null then [ ] else [ probeCommand ]);

      units.ping = {
        command = "${beacon} ${heartbeat}";
        runtimeDirectory = [ directory ];
      }
      // (
        if probeCommand == null then
          { }
        else
          {
            probe = "${probeCommand} ${heartbeat}";
            probeTimeout = "30s";
          }
      );
    };
}
