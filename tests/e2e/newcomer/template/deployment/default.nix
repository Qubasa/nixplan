{
  pkgs,
  planner,
  operator,
}:
let
  greeter = pkgs.writeShellApplication {
    name = "greet";
    # `sleep` comes from here rather than from the machine: a unit of a service
    # artifact runs with the PATH the artifact carries, and the machine's own is
    # not a fact the plan records.
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      printf 'hello %s from %s\n' "$GREET_WHO" "$GREET_WHERE" > "$GREET_PATH"
      exec sleep infinity
    '';
  };

  hello = {
    services.default = import ./modules/hello/default.nix { greeter = "${greeter}"; };
  };

  deployment = import ./instances.nix { inherit hello; };
  registry = import ./machines.nix;
in
operator.mkDeployment {
  inherit pkgs planner;

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
