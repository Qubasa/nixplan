# The entry planned for the other architecture.
#
# Nothing about this module is unusual: it declares the platform of the machine
# the registry says it runs on and reads the path its sibling published. What
# makes it worth building is the target the plan records, which is what the
# attach script compares against the machine it is run on.
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
