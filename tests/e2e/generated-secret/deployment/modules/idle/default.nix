{ coreutils }:

{ service, ... }:
{
  services.job = service "job" {
    module = import ./job.nix { inherit coreutils; };
    defaults.markerPath = "/run/generated-secret-idle.ran";
  };
}
