{
  opener,
  reportFile,
  grouped,
}:

_: {
  platforms = [ "x86_64-linux" ];

  # A read of the export another entry's generated file backs. The read is what
  # puts that value on this entry's machine, so the bytes are there before this
  # entry is activated and the path the record carries is the value's own.
  uses.upstream = {
    interface = reportFile;
    reach = "one";
    reads = [ "secret" ];
  };

  impl =
    {
      instance,
      member,
      results,
      ...
    }:
    let
      # Derived from the entry's own identity, because this folder's deployment
      # writes no host path: a second entry of this module on one machine claims
      # its own directory and writes its own copy.
      directory = "${instance}-${member}";
      copy = "/run/${directory}/opened.txt";
    in
    {
      closure = [ opener ];

      units.open = {
        command = "${opener} ${copy}";
        runtimeDirectory = [ directory ];
        oneShot = true;
        remainAfterExit = true;
        env.SECRET = results.upstream.secret.path;
        extends = [
          {
            # The profile runs this unit under a transient account, so the group
            # the value is delivered to is the only thing that can admit it.
            extension = grouped;
            values.supplementaryGroups = [ "nogroup" ];
          }
        ];
      };
    };
}
