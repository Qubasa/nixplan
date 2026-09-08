{
  report,
  reportFile,
  paths,
}:

{ service, ... }:
let
  file = service "file" {
    module = import ./watch.nix {
      inherit
        report
        reportFile
        paths
        ;
    };
  };
in
{
  services = { inherit file; };

  provides.report = file.provides.report;
}
