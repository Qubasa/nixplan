{ coreutils }:

{ service, ... }:
{
  # No knob and no capability left to state. The member is composed so that the
  # deployment places a service on a machine that receives no generated value.
  services.job = service "job" {
    module = import ./job.nix { inherit coreutils; };
  };
}
