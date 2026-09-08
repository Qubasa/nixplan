# The entry a machine attaches under a restricted profile.
#
# It declares one configuration file assembled from a file that lives on the
# machine, so the image carries a recipe and never those bytes, and one unit
# that reads the assembled file and then tries a write the profile denies. Both
# answers go to the journal, which is the service manager's own record of what
# the confinement did.
{
  report,
  reportFile,
  paths,
}:

_: {
  platforms = [ "x86_64-linux" ];

  provides.report = {
    interface = reportFile;
  };

  impl = _: {
    # The script alone: everything it runs is a reference of it, so the image
    # carries them without the entry declaring a root it never names.
    closure = [ report ];

    configData.${paths.assembled} = {
      mode = "0444";
      reload = [ "report" ];
      render = [
        { text = "# assembled on the machine, from a file the image never carried\n"; }
        { ref = paths.shown; }
      ];
    };

    provides.report.exports = {
      path = paths.assembled;
    };

    units.report = {
      command = report;
      env = {
        ASSEMBLED = paths.assembled;
        ORIGINAL = paths.shown;
      };
    };
  };
}
