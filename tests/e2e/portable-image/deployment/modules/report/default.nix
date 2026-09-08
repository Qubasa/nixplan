# The reporting root. One member, and the path it keeps its assembled file at
# re-exported so a sibling instance can wire it.
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
