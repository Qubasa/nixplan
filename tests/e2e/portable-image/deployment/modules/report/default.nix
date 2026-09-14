{
  report,
  reportFile,
  grouped,
}:

{ service, ... }:
let
  file = service "file" {
    module = import ./watch.nix {
      inherit
        report
        reportFile
        grouped
        ;
    };
  };
in
{
  services = { inherit file; };

  provides.report = file.provides.report;
}
