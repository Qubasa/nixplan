{ greeter }:

{ service, ... }:
let
  greet = service "greet" {
    module = import ./greet.nix { inherit greeter; };
    defaults.who = "world";
  };
in
{
  services = { inherit greet; };
}
