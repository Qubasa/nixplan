{ coreutils }:

{ service, ... }:
{
  services.job = service "job" {
    module = import ./job.nix { inherit coreutils; };
    defaults.markerPath = "/run/secret-delivery-idle.ran";
  };
}
