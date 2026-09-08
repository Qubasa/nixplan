{
  coreutils,
  reportFile,
}:

{ service, ... }:
let
  copy = service "copy" {
    module = import ./copy.nix { inherit coreutils reportFile; };
  };
in
{
  services = { inherit copy; };
}
