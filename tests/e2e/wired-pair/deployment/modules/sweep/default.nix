# The scheduled root. One member, offering nothing and reading nothing: this
# instance is here for what a deployment does to a schedule.
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
