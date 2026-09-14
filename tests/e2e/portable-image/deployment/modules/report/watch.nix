{
  report,
  reportFile,
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
    {
      instance,
      member,
      vars,
      ...
    }:
    let
      # All three derived from the entry's own identity: a second entry of this
      # module on one machine is shown its own file and assembles its own two.
      shown = "/var/lib/${instance}-${member}/upstream.txt";
      assembled = "/etc/${instance}-${member}/report.conf";
      quiet = "/etc/${instance}-${member}/quiet.conf";
    in
    {
      # Only the script is a closure root. Everything it runs is a reference of it.
      closure = [ report ];

      configData.${assembled} = {
        mode = "0444";
        reload = [ "report" ];
        render = [
          { text = "# assembled on the machine, from a file the image never carried\n"; }
          { ref = shown; }
        ];
      };

      # The other half of the reload rule: one file names a unit and this one
      # names none, so an edit reaching both reloads exactly one.
      configData.${quiet} = {
        mode = "0444";
        reload = [ ];
        render = [
          { text = "# named by no unit\n"; }
          { ref = shown; }
        ];
      };

      provides.report.exports = {
        path = assembled;
      };

      units.report = {
        command = report;
        env = {
          ASSEMBLED = assembled;
          ORIGINAL = shown;
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
