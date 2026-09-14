{ coreutils }:

{ service, ... }:
let
  job = service "job" {
    module = import ./job.nix { inherit coreutils; };
  };
in
{
  services = { inherit job; };
}
