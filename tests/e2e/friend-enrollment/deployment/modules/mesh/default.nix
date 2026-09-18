{
  headscale,
  mintProgram,
  domain,
  port,
  stunPort,
}:

{ service, ... }:
let
  hub = service "hub" {
    module = import ./hub.nix { inherit headscale mintProgram; };

    # Fixed rather than defaulted: a second instance of this module would be a
    # second membership authority, and the three numbers and names below are
    # the ones the registry's own addresses already agree with. A deployment
    # that could choose them could choose a mesh its own machines cannot join.
    fixed = {
      inherit domain port stunPort;
    };
  };
in
{
  services = { inherit hub; };
}
