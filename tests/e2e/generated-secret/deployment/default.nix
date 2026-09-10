# The deployment of the generated-secret folder, over the state it is planned
# against. A plan is a function of `varsState`, and the bytes of this deployment's
# values exist only once the generator has run, so the state is an argument here
# rather than a literal: the build states presence and no bytes, and the run
# states what the store backend answered.
{
  planner,
  packages,
  varsState ? null,
}:
let
  inherit (packages)
    python3
    coreutils
    issueScript
    attestScript
    mintProgram
    deriveProgram
    ;

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) attestation;

  # Presence and nothing else. It is what makes the unit files and the generator
  # configuration a function of the declaration alone: no artifact of this folder
  # can carry bytes that were not generated when it was built.
  declaredState = {
    "issuer:vars/root".key.present = true;
    "issuer:vars/token" = {
      secret.present = true;
      fingerprint.present = true;
    };
  };

  issuerModule = {
    services.default = import ./modules/issuer/default.nix {
      inherit
        python3
        issueScript
        mintProgram
        deriveProgram
        attestation
        ;
    };
  };

  probeModule = {
    services.default = import ./modules/probe/default.nix {
      inherit python3 attestScript attestation;
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
  inherit interfaces declaredState;

  args = {
    inherit (deployment) instances;
    inherit (registry) machines;
    varsState = if varsState == null then declaredState else varsState;

    interfaces = {
      "interfaces/default.nix" = interfaces;
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
