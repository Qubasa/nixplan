{
  report,
  reportFile,
  paths,
  grouped,
}:

{ service, ... }:
let
  file = service "file" {
    module = import ./watch.nix {
      inherit
        report
        reportFile
        paths
        grouped
        ;
    };
  };
in
{
  services = { inherit file; };

  provides.report = file.provides.report;
}
