{
  python3,
  page,
  httpEndpoint,
}:

{ service, ... }:
let
  server = service "server" {
    module = import ./server.nix { inherit python3 page httpEndpoint; };

    # The port is the module's own fact rather than a deployment setting, because it is
    # half of the URL this module publishes.
    fixed.port = 8080;
  };
in
{
  services = { inherit server; };

  provides.page = server.provides.page;
}
