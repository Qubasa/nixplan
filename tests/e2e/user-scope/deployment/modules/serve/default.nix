{ serveScript }:

{ service, ... }:
let
  app = service "app" {
    module = import ./app.nix { inherit serveScript; };
  };
in
{
  services = { inherit app; };
}
