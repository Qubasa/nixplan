{
  python3,
  page,
  httpEndpoint,
}:

{ service, ... }:
let
  server = service "server" {
    module = import ./server.nix { inherit python3 page httpEndpoint; };

    fixed.port = 8080;
  };
in
{
  services = { inherit server; };

  provides.page = server.provides.page;
}
