{
  python3,
  checkScript,
  tokenEndpoint,
}:

{ service, ... }:
{
  services.client = service "client" {
    module = import ./client.nix { inherit python3 checkScript tokenEndpoint; };
  };
}
