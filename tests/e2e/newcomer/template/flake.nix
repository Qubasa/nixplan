{
  description = "two machines and one greeting";

  # The published flake, written the way a reader outside this repository writes
  # it. A run of this folder locks the template against the checkout under test
  # instead, with `nix flake lock --override-input`, so this line is never edited
  # and never fetched: the lock records the substitution and the test reads it.
  inputs.nixplan.url = "github:Qubasa/nixplan";

  # One nixpkgs, the one the library is built against. A second pin here would
  # evaluate the deployment against packages the library never saw.
  inputs.nixpkgs.follows = "nixplan/nixpkgs";

  outputs =
    { nixpkgs, nixplan, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # The declarations asked with no package set instantiated. `args.nix` takes
      # the packages its modules interpolate, so a stand-in answers for one, and
      # the stand-in is a store path rather than a name: the planner recognises a
      # store path by the store directory and the shape of a hash, so a name it
      # cannot recognise turns the rows about declared closure roots off instead
      # of answering them. Those rows are about whatever was handed in, which is
      # why `packages.default` stays the authority for them.
      asked =
        nixplan.lib.mkPlan
          (import ./deployment/args.nix {
            packages.greeter = "/nix/store/9zv4c8m2kq7r5xn3bdlp6yfs0agh1jw2-greet";
          }).args;
    in
    {
      packages.${system}.default = import ./deployment {
        inherit pkgs;
        planner = nixplan.lib;
        operator = nixplan.operator;
      };

      # The rows and the table rendered from them, under the two names the
      # deployment build publishes them under, so one command reads either
      # answer: `planner diagnose .#diagnostics` here, `planner diagnose
      # .#default` over the build.
      diagnostics = {
        inherit (asked) diagnostics;
        rendered = nixplan.lib.render asked.diagnostics + "\n";
      };
    };
}
