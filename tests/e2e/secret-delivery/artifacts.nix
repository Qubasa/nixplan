# One plan, three entries, and the three flakelet artifacts a machine takes. The
# secret this folder is about is in none of them: the plan names it and the
# delivery carries it, so the bytes are minted by the run and never by a build.
{
  pkgs,
  planner,
  flakeletBuilder,
}:
let
  # A public generated value. It travels in the plan because it is public, and no
  # machine holds a file of it because its generator is not deployed.
  caCert = "PLANNER-E2E-CA ${builtins.hashString "sha256" "secret-delivery"}";

  packages = {
    python3 = "${pkgs.python3Minimal}";
    coreutils = "${pkgs.coreutils}";
    serveScript = "${pkgs.writeText "secret-delivery-serve.py" (builtins.readFile ./serve.py)}";
    checkScript = "${pkgs.writeText "secret-delivery-check.py" (builtins.readFile ./check.py)}";
    inherit caCert;
  };

  result = planner.mkPlan (import ./deployment { inherit planner packages; }).args;

  keys = {
    issuer = "issuer:api@alpha";
    probe = "probe:client@beta";
    idle = "idle:job@gamma";
  };

  varsKeys = {
    session = "issuer:vars/session";
    ca = "issuer:vars/ca";
  };

  entries = builtins.mapAttrs (
    _: key:
    flakeletBuilder.artifact {
      plan = result.plan;
      inherit key;
    }
  ) keys;

  planFile = pkgs.writeText "planner-secret-delivery.json" (builtins.toJSON result.plan);
in
(pkgs.linkFarm "planner-secret-delivery-artifacts" (
  [
    {
      name = "plan.json";
      path = planFile;
    }
  ]
  ++ map (name: {
    inherit name;
    path = entries.${name};
  }) (builtins.attrNames entries)
)).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit
        entries
        keys
        varsKeys
        caCert
        ;
      plan = result;
    };
  })
