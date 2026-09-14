{
  curl,
  httpEndpoint,
}:

{ service, ... }:
let
  client = service "client" {
    module = import ./client.nix { inherit curl httpEndpoint; };
  };
in
{
  services = { inherit client; };
}
