# One deployment of one entry on one machine, whose only unusual fact is the
# machine's scope: it is deployed as an account, so the image is a user-scope
# portable image, its roothash is signed, its units are rendered where a user
# manager reads them and its attach addresses that account's own portabled.
#
# The realisation statement is here for the reason it is in every folder:
# nothing in a plan says whether an entry wants an image or a flakelet
# artifact, and an account can attach an image and can run no flakelet. The
# signing pair is an argument of the build and a fact of no plan.
{
  pkgs,
  planner,
  operator,
}:
let
  verity = import ../verity.nix { inherit (pkgs) writeText; };

  # `coreutils` is a runtime input because a unit of a service artifact runs
  # with the PATH the artifact carries and never the machine's.
  serveScript = pkgs.writeShellApplication {
    name = "planner-user-scope-serve";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./serve.sh;
  };

  # The store path as a string, never the derivation: every reading in `lib/`
  # walks a unit record for line breaks and store paths, and a derivation
  # attribute set reaches nixpkgs' own `stdenv` through its inputs, where that
  # walk runs out of stack.
  serveModule = {
    services.default = import ./modules/serve/default.nix { serveScript = "${serveScript}"; };
  };

  registry = import ./machines.nix;
in
{
  default = operator.mkDeployment {
    inherit pkgs planner;

    # `default` rather than `trusted`, because a user-scope `default` is the
    # profile with `DynamicUser=yes` and `ProtectHome=yes` dropped and
    # `PrivateUsers=yes` kept, which is the confinement an account can be given.
    realise."serve:app" = {
      realiser = "image";
      profile = "default";
    };

    signing = { inherit (verity) privateKey certificate; };

    args = {
      inherit (import ./instances.nix { serve = serveModule; }) instances;
      inherit (registry) machines;

      varsState."serve:vars/served".token.present = true;

      sources = {
        deployment = "instances.nix";
        machines = "machines.nix";
        modules.serve = "serve/default.nix";
        leaves.serve.app = "serve/app.nix";
      };
    };
  };
}
