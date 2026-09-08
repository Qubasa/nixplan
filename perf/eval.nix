{
  korora,
  nixpkgs,
  fixture ? "worked",
  size ? "0",
  lib ? ./../lib,
  folder ? ./../fixtures/minimal-typed-edge,
  worked ? ./../tests/unit/worked.nix,
}:
let
  planner = import lib {
    korora = import "${korora}/types.nix";
    systems = (import "${nixpkgs}/lib").systems;
  };

  args =
    if fixture == "worked" then
      (import worked { inherit planner folder; }).args
    else if fixture == "fleet" then
      import ./fleet.nix {
        inherit planner;
        size = builtins.fromJSON size;
      }
    else if fixture == "mesh" then
      import ./mesh.nix {
        inherit planner;
        size = builtins.fromJSON size;
      }
    else
      throw "eval.nix: unknown fixture ${fixture}, expected worked, fleet or mesh";

  result = planner.mkPlan args;
  count = builtins.length (builtins.attrNames result.plan);
in
builtins.deepSeq result "entries=${toString count}\n"
