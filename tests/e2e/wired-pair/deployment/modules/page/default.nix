# The serving root. One member, and the endpoint it publishes re-exported so a
# sibling instance can wire it.
{
  python3,
  page,
  httpEndpoint,
}:

{ service, ... }:
let
  server = service "server" {
    module = import ./server.nix { inherit python3 page httpEndpoint; };

    # The port is half of the URL this module publishes as a fact about itself,
    # so the deployment does not get to move it - the same reason
    # fixtures/minimal-typed-edge/modules/borg-repo/default.nix fixes its
    # own.
    fixed.port = 8080;
  };
in
{
  services = { inherit server; };

  provides.page = server.provides.page;
}
