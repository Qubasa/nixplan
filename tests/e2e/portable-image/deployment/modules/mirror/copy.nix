{
  coreutils,
  reportFile,
}:

_: {
  platforms = [ "aarch64-linux" ];

  uses.source = {
    interface = reportFile;
    reach = "one";
    reads = [ "path" ];
  };

  impl =
    { results, ... }:
    {
      closure = [ coreutils ];

      units.mirror = {
        command = "${coreutils}/bin/cat ${results.source.path}";
        oneShot = true;
      };
    };
}
