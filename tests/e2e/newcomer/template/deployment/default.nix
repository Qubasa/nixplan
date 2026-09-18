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

  # The deployment is stated in `args.nix` and nowhere else. This file builds the
  # programs its units run and hands the same declarations to the build, so the
  # two entry points differ in the package set and never in the deployment. A
  # module is handed the store path as a string: an unbuilt derivation is an
  # attribute set whose inputs reach nixpkgs' own stdenv, where the reading that
  # walks a unit record runs out of stack.
  deployment = import ./args.nix { packages.greeter = "${greeter}"; };
in
operator.mkDeployment {
  inherit pkgs planner;
  inherit (deployment) args;
}
