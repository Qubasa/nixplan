{
  python3,
  issueScript,
  mintProgram,
  deriveProgram,
  attestation,
}:

{ service, ... }:
let
  api = service "api" {
    module = import ./api.nix {
      inherit
        python3
        issueScript
        mintProgram
        deriveProgram
        attestation
        ;
    };

    # The port is half of the URL this module publishes, so it is the module's own
    # fact rather than a deployment setting.
    fixed.port = 8081;
  };
in
{
  services = { inherit api; };

  provides.api = api.provides.api;
}
