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
    in
    {
      packages.${system}.default = import ./deployment {
        inherit pkgs;
        planner = nixplan.lib;
        operator = nixplan.operator;
      };
    };
}
