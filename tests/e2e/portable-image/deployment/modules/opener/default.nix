{
  opener,
  reportFile,
  grouped,
}:

{ service, ... }:
let
  read = service "read" {
    module = import ./read.nix {
      inherit
        opener
        reportFile
        grouped
        ;
    };
  };
in
{
  services = { inherit read; };
}
