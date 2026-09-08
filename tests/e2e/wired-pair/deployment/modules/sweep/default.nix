{ coreutils }:

{ service, ... }:
let
  job = service "job" {
    module = import ./job.nix { inherit coreutils; };
    defaults.markerPath = "/run/cluster-sweep.ran";
  };
in
{
  services = { inherit job; };
}
