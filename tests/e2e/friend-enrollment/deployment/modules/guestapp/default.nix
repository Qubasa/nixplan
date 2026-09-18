{ runScript }:

{ service, ... }:
let
  run = service "run" {
    module = import ./run.nix { inherit runScript; };
  };
in
{
  services = { inherit run; };
}
