{
  beacon,
  probeCommand,
}:

{ service, ... }:
let
  ping = service "ping" {
    module = import ./ping.nix { inherit beacon probeCommand; };
  };
in
{
  services = { inherit ping; };
}
