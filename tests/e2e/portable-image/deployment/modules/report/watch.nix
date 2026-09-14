{
  report,
  reportFile,
  paths,
  grouped,
}:

_: {
  platforms = [ "x86_64-linux" ];

  # A delivered secret this confined entry has to open. Owned by nobody and
  # readable by its group, which the unit below declares: the profile runs the
  # unit under a transient account, so the group is the only thing that can
  # admit it.
  vars.upstream = {
    per = "instance";
    files.secret = {
      secrecy = "secret";
      owner = "nobody";
      group = "nogroup";
      mode = "0440";
    };
  };

  provides.report = {
    interface = reportFile;
  };

  impl =
    { vars, ... }:
    {
      # Only the script is a closure root. Everything it runs is a reference of it.
      closure = [ report ];

      configData.${paths.assembled} = {
        mode = "0444";
        reload = [ "report" ];
        render = [
          { text = "# assembled on the machine, from a file the image never carried\n"; }
          { ref = paths.shown; }
        ];
      };

      # The other half of the reload rule: one file names a unit and this one
      # names none, so an edit reaching both reloads exactly one.
      configData.${paths.quiet} = {
        mode = "0444";
        reload = [ ];
        render = [
          { text = "# named by no unit\n"; }
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
          SECRET = vars.upstream.secret.path;
        };
        extends = [
          {
            extension = grouped;
            values.supplementaryGroups = [ "nogroup" ];
          }
        ];
      };
    };
}
