# One deployment, three entries, and a generated secret none of them carries.
# The plan names the value and the operator's own value source carries its bytes,
# so they are minted by the run and never by a build.
{
  pkgs,
  planner,
  operator,
}:
let
  # A public generated value. It travels in the plan because it is public, and no
  # machine holds a file of it because its generator is not deployed.
  caCert = "PLANNER-E2E-CA ${builtins.hashString "sha256" "secret-delivery"}";

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) tokenEndpoint;

  python3 = "${pkgs.python3Minimal}";

  issuerModule = {
    services.default = import ./modules/issuer/default.nix {
      serveScript = "${pkgs.writeText "secret-delivery-serve.py" (builtins.readFile ./serve.py)}";
      inherit python3 tokenEndpoint;
    };
  };

  probeModule = {
    services.default = import ./modules/probe/default.nix {
      checkScript = "${pkgs.writeText "secret-delivery-check.py" (builtins.readFile ./check.py)}";
      inherit python3 tokenEndpoint;
    };
  };

  idleModule = {
    services.default = import ./modules/idle/default.nix {
      coreutils = "${pkgs.coreutils}";
    };
  };

  deployment = import ./instances.nix {
    issuer = issuerModule;
    probe = probeModule;
    idle = idleModule;
  };
  registry = import ./machines.nix;
in
{
  default = operator.mkDeployment {
    inherit pkgs planner;

    args = {
      inherit (deployment) instances;
      inherit (registry) machines;

      interfaces = {
        "interfaces/default.nix" = interfaces;
      };

      # The state of a generated value is keyed by the value's own plan entry, so
      # a value that exists once for an instance has one answer about whether it
      # has been generated. The token's bytes are the operator's and appear
      # nowhere here; the certificate's are public and travel in the plan.
      varsState = {
        "issuer:vars/session".token = {
          present = true;
        };
        "issuer:vars/ca"."ca.pub" = {
          present = true;
          content = caCert;
        };
      };

      sources = {
        deployment = "instances.nix";
        machines = "machines.nix";
        modules = {
          issuer = "issuer/default.nix";
          probe = "probe/default.nix";
          idle = "idle/default.nix";
        };
        leaves = {
          issuer.api = "issuer/api.nix";
          probe.client = "probe/client.nix";
          idle.job = "idle/job.nix";
        };
      };
    };
  };
}
