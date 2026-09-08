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
