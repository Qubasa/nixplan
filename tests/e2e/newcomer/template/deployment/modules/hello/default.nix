{ greeter }:

{ service, ... }:
let
  greet = service "greet" {
    module = import ./greet.nix { inherit greeter; };
    defaults.who = "world";
    defaults.greetingPath = "/run/hello.greeting";
  };
in
{
  services = { inherit greet; };
}
