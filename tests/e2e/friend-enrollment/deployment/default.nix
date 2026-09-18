# One deployment across two machines whose one unusual fact is an address: the
# friend machine is declared by the name a mesh gives it, and nothing below the
# registry can tell that name from any other. The coordination server that
# hands out the name is itself an entry of this deployment, placed on the
# operator's own machine, so the folder proves the operator story rather than
# wiring a mesh into the guest image.
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
  mesh = import ./mesh.nix;
  verity = import ../verity.nix { inherit (pkgs) writeText; };

  # The server's own tool, on the minting script's PATH rather than on the
  # caller's, and `jq` beside it because the tool answers a credential as one
  # JSON object and the file this generator writes holds the key alone. The
  # declared expiry is prepended as a shell assignment, because `readFile`
  # interpolates nothing and an expiry the deployment states is not a knob of
  # the environment.
  mintKey = pkgs.writeShellApplication {
    name = "planner-friend-enrollment-mint";
    runtimeInputs = [
      pkgs.headscale
      pkgs.jq
    ];
    text = ''
      expiry=${pkgs.lib.escapeShellArg mesh.expiry}
      ${builtins.readFile ./mint.sh}
    '';
  };

  # A generator's program is recorded as exactly one store path and nothing
  # else, and the tool that realises one runs its output as a program, so the
  # output has to be a single file: the wrapper's own bytes carry the PATH that
  # `runtimeInputs` built, so the file copied out of it still finds the tool.
  mintProgram = pkgs.runCommand "planner-friend-enrollment-mint-program" { } ''
    cp ${mintKey}/bin/planner-friend-enrollment-mint "$out"
  '';

  # `coreutils` is a runtime input because a unit of a service artifact runs
  # with the PATH the artifact carries and never the machine's.
  runScript = pkgs.writeShellApplication {
    name = "planner-friend-enrollment-run";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./run.sh;
  };

  # The store path as a string, never the derivation: every reading in `lib/`
  # walks a unit record for line breaks and store paths, and a derivation
  # attribute set reaches nixpkgs' own `stdenv` through its inputs, where that
  # walk runs out of stack.
  meshModule = {
    services.default = import ./modules/mesh/default.nix {
      headscale = "${pkgs.headscale}";
      mintProgram = mintProgram.drvPath;
      inherit (mesh) domain port stunPort;
    };
  };

  guestappModule = {
    services.default = import ./modules/guestapp/default.nix {
      runScript = "${runScript}";
    };
  };

  registry = import ./machines.nix;

  # One build and not two. A second one was made, stating that the declared
  # credential's bytes are in the value store, and measured against this one:
  # `manifest.json` came out byte for byte identical, and `plan.json` differed
  # in nothing but the value entry's own key and the `bytes = "absent"` marker
  # on its one file. The command cannot tell them apart, and does not look: the
  # source is measured against the values some machine receives, this one is
  # delivered to none, and no module of `cli/` reads that marker at all. So the
  # folder's runs are made against this build before the server exists and
  # after it has minted, and the plan says what is true of both: the generator
  # is declared, it has not run, and the entry records the file's path anyway.
  # That last part is why a plan carries `deploy` - nothing binds the path of a
  # value no machine holds - and the credentials the runs present are minted
  # against the running server and handed over outside this tree, which is the
  # whole ceremony this folder exists to prove.
in
{
  default = operator.mkDeployment {
    inherit pkgs planner;

    # The friend machine is deployed as an account, so its entry is a portable
    # image that account attaches: its units are rendered where an account's
    # own manager reads them, its roothash is signed and its attach addresses
    # that account's own portabled. `default` rather than `trusted`, because
    # under that scope `default` is the profile with `DynamicUser=yes` and
    # `ProtectHome=yes` dropped and `PrivateUsers=yes` kept.
    realise."guestapp:run" = {
      realiser = "image";
      profile = "default";
    };

    signing = { inherit (verity) privateKey certificate; };

    args = {
      inherit
        (import ./instances.nix {
          mesh = meshModule;
          guestapp = guestappModule;
        })
        instances
        ;
      inherit (registry) machines;

      sources = {
        deployment = "instances.nix";
        machines = "machines.nix";
        modules = {
          mesh = "mesh/default.nix";
          guestapp = "guestapp/default.nix";
        };
        leaves = {
          mesh.hub = "mesh/hub.nix";
          guestapp.run = "guestapp/run.nix";
        };
      };
    };
  };
}
