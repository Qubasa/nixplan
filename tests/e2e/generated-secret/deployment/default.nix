# Three builds of one deployment: the artifacts three machines take, the
# generator configuration an operator runs before anything is delivered, and the
# `age` the run mints its own identity with.
#
# The state everything here is planned against is presence and nothing else,
# which is what makes the unit files and the configuration a function of the
# declaration alone: no artifact of this folder can carry a byte that was not
# generated when it was built. The run re-evaluates `args.nix` against what the
# store backend answered, and that second plan is what its assertions read.
{
  pkgs,
  planner,
  operator,
}:
let
  python3 = "${pkgs.python3Minimal}";

  # A single executable file rather than a `bin` directory: the generator
  # realises a derivation and runs its output as a program, so the output has to
  # be one.
  program =
    name: source:
    pkgs.writeTextFile {
      name = "planner-e2e-${name}";
      executable = true;
      text = ''
        #!${python3}/bin/python3
        ${builtins.readFile source}
      '';
    };

  mint = program "mint" ./mint.py;
  derive = program "derive" ./derive.py;

  backendSource = pkgs.writeText "planner-e2e-age-backend.py" (builtins.readFile ./backend.py);

  # One program per command of the contract's store backend, each with `age` and
  # coreutils on its path. The storage root, the recipient and the identity are
  # the run's, so they arrive from the environment.
  backendCommand =
    command:
    pkgs.writeTextFile {
      name = "planner-e2e-age-${command}";
      executable = true;
      text = ''
        #!${pkgs.runtimeShell}
        PATH=${pkgs.age}/bin:${pkgs.coreutils}/bin:$PATH
        export PATH
        exec ${python3}/bin/python3 ${backendSource} ${command} "$@"
      '';
    };

  ageCommands = builtins.listToAttrs (
    map
      (command: {
        name = command;
        value = backendCommand command;
      })
      [
        "get"
        "set"
        "exists"
        "delete"
        "list"
        "fixup"
      ]
  );

  packages = {
    inherit python3;
    coreutils = "${pkgs.coreutils}";
    issueScript = "${pkgs.writeText "generated-secret-issue.py" (builtins.readFile ./issue.py)}";
    attestScript = "${pkgs.writeText "generated-secret-attest.py" (builtins.readFile ./attest.py)}";
    mintProgram = mint.drvPath;
    deriveProgram = derive.drvPath;
  };

  deployment = import ./args.nix { inherit planner packages; };
in
{
  default = operator.mkDeployment {
    inherit pkgs planner;
    inherit (deployment) args;
  };
  generation = operator.mkGeneration {
    inherit pkgs planner packages;
    inherit (deployment) args;
    source = ./.;
    backend = "age";
    programs = ageCommands;
  };

  # The same `age` the store backend runs, so a run mints its identity with it
  # rather than with whatever the host happens to carry.
  age = pkgs.age;
}
