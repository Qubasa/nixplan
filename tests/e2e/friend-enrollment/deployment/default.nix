# One deployment across two machines whose one unusual fact is an address: the
# friend machine is declared by the name a mesh gives it, and nothing below the
# registry can tell that name from any other. The coordination server that
# hands out the name is itself an entry of this deployment, placed on the
# operator's own machine, so the folder proves the operator story rather than
# wiring a mesh into the guest image.
#
# The server is the module this repository publishes, handed to this folder as
# an argument the way the deployment build is: a folder that held a module of
# its own would hold a module no deployment outside it could name, and this one
# is the module a consumer composes. The two facts it refuses to default are
# stated here - the url a client is configured with, and who is admitted - and
# the four its own cluster chose are settings of the instance.
#
# The realisation statement is here for the reason it is in every folder:
# nothing in a plan says whether an entry wants an image or a flakelet
# artifact, and an account can attach an image and can run no flakelet. The
# signing pair is an argument of the build and a fact of no plan.
#
# Beside it is the statement of which entry coordinates the mesh. Nothing
# infers it: the three verbs read it off the built deployment, and the two
# objects they spend are named by the names the published module publishes,
# resolved against this entry's own closure.
{
  pkgs,
  planner,
  operator,
  coordination,
}:
let
  mesh = import ./mesh.nix;
  verity = import ../verity.nix { inherit (pkgs) writeText; };

  hub = coordination {
    inherit pkgs;
    inherit (mesh) domain group expiry;

    # Plain HTTP over the address the registry declares, which is a decision
    # about a network with no route to anybody else's. The published module
    # refuses to make it, so this cluster makes it here.
    clientUrl = { address, port }: "http://${address}:${toString port}";

    # An empty path admits everybody, which is what a cluster of two machines
    # on one LAN wants and what no published module may default to.
    policy = {
      mode = "file";
      path = "";
    };
  };

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
  guestappModule = import ./modules/guestapp/default.nix {
    runScript = "${runScript}";
  };

  registry = import ./machines.nix;

  entry = "mesh:hub@hub";
  credential = "mesh:vars/enrollment";

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
  # value no machine holds - and the credentials the runs present are minted by
  # `planner invite` against the running server and handed over outside this
  # tree, which is the whole ceremony this folder exists to prove.
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

    # Which entry an enrollment verb acts against, and which generated value is
    # the join credential it mints. The two objects are named rather than
    # pathed: the build resolves each name against that entry's own closure, so
    # the command reproduces no rule of the module's.
    coordinate = {
      inherit entry credential;
      inherit (hub.names) program configuration;
    };

    signing = { inherit (verity) privateKey certificate; };

    args = {
      inherit
        (import ./instances.nix {
          coordination = hub.root;
          guestapp = guestappModule;
        })
        instances
        ;
      inherit (registry) machines;

      sources = {
        deployment = "instances.nix";
        machines = "machines.nix";
        modules = {
          guestapp = "guestapp/default.nix";
        };
        leaves = {
          guestapp.run = "guestapp/run.nix";
        };
      };
    };
  };
}
