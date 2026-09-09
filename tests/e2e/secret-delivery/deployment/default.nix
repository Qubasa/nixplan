{
  planner,
  packages,
}:
let
  inherit (packages)
    python3
    coreutils
    serveScript
    checkScript
    caCert
    ;

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) tokenEndpoint;

  issuerModule = {
    services.default = import ./modules/issuer/default.nix {
      inherit python3 serveScript tokenEndpoint;
    };
  };

  probeModule = {
    services.default = import ./modules/probe/default.nix {
      inherit python3 checkScript tokenEndpoint;
    };
  };

  idleModule = {
    services.default = import ./modules/idle/default.nix { inherit coreutils; };
  };

  deployment = import ./instances.nix {
    issuer = issuerModule;
    probe = probeModule;
    idle = idleModule;
  };
  registry = import ./machines.nix;
in
{
  inherit interfaces;

  args = {
    inherit (deployment) instances;
    inherit (registry) machines;

    interfaces = {
      "interfaces/default.nix" = interfaces;
    };

    # The state of a generated value is keyed by the value's own plan entry, so a
    # value that exists once for an instance has one answer about whether it has
    # been generated. The token's bytes are the operator's and appear nowhere
    # here; the certificate's are public and travel in the plan.
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
}
