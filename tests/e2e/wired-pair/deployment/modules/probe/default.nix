# The fetching root. One member, and it offers nothing: this instance only
# reads.
{
  curl,
  httpEndpoint,
}:

{ service, ... }:
let
  client = service "client" {
    module = import ./client.nix { inherit curl httpEndpoint; };
    defaults.recordPath = "/run/cluster-probe.body";
  };
in
{
  services = { inherit client; };
}
