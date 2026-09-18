# The deployment itself, stated once and with no package set: every package a
# module interpolates is an argument here, so asking what these declarations earn
# costs one evaluation of the library and instantiates nothing. `default.nix`
# beside this file is the other entry point - it builds those packages out of a
# caller's own set and hands the same value to the deployment build.
#
# The ellipsis answers the arguments this deployment needs nothing from: the
# convention hands an `args.nix` the library, the packages and the state its
# generated values exist in, and this one declares no interface and no generator.
{ packages, ... }:
let
  inherit (packages) greeter;

  hello = {
    services.default = import ./modules/hello/default.nix { inherit greeter; };
  };

  deployment = import ./instances.nix { inherit hello; };
  registry = import ./machines.nix;
in
{
  args = {
    inherit (deployment) instances;
    inherit (registry) machines;

    # A module that declares no interface wires to nothing, so the attribution
    # this argument carries is empty rather than absent.
    interfaces = { };

    sources = {
      deployment = "instances.nix";
      machines = "machines.nix";
      modules = {
        greeter = "hello/default.nix";
      };
      leaves = {
        greeter.greet = "hello/greet.nix";
      };
    };
  };
}
