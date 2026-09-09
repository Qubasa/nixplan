{
  python3,
  serveScript,
  tokenEndpoint,
}:

{ service, ... }:
let
  api = service "api" {
    module = import ./api.nix { inherit python3 serveScript tokenEndpoint; };

    # The port is the module's own fact rather than a deployment setting, because it is
    # half of the URL this module publishes.
    fixed.port = 8080;
  };
in
{
  services = { inherit api; };

  provides.api = api.provides.api;
}
