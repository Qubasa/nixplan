# One deployment, built. read.nix is the whole reading, and everything over it is
# derivations: the plan, the manifest, the diagnostics table, and one artifact per
# placed entry, in one link farm. mkGeneration is the same plan read as a
# configuration for the external secret generator.
#
# This is the first layer allowed to raise. `lib/` never does, the readings never
# do, and the realisers do it for a condition a row already reported. What this
# file raises for is a caller asking for the artifact of an entry of a deployment
# the planner called inapplicable, and a generation whose table carries an error,
# with the rendered table as the message either way.
# A deployment tree is always produced: it holds the plan and both halves of the
# diagnostics whatever the table says, and an artifact of no entry when the table
# carries an error. A table carrying warnings and no error builds; a warning that
# stopped a build would be an error.
#
# korora is the pin the library was instantiated from, and it is here because
# mkGeneration writes an expression that instantiates the same library again: a
# plan carrying a generated value's bytes cannot be a build artifact of a run
# that has generated nothing yet. nixpkgs arrives as `pkgs.path` and the library
# as `../lib`, so those two are not arguments.
{ korora }:
{
  mkDeployment =
    {
      pkgs,
      planner,
      args,
      realise ? {
        default.realiser = "flakelet";
      },
    }:
    let
      reader = import ./read.nix { inherit planner; };

      imageBuilder = import ../image {
        inherit (pkgs) lib;
        inherit pkgs planner;
      };

      flakeletBuilder = import ../flakelet { inherit pkgs planner; };

      result = planner.mkPlan args;

      reading = reader.read {
        inherit (result) plan diagnostics;
        inherit realise;
        storeDir = args.storeDir or builtins.storeDir;
      };

      artifactOf =
        key: entry:
        if entry.realiser == "image" then
          imageBuilder.build {
            inherit (result) plan;
            inherit key;
            inherit (entry) profile;
          }
        else
          flakeletBuilder.artifact {
            inherit (result) plan;
            inherit key;
          };

      realised = planner.util.filterAttrs (_: entry: entry.realised) reading.entries;

      # Nothing is realised for an inapplicable deployment, and asking for one
      # entry's artifact is answered with the table rather than with an absence.
      entries =
        if reading.refused then
          builtins.mapAttrs (_: _: throw reading.refusal) realised
        else
          builtins.mapAttrs artifactOf realised;

      links = if reading.refused then { } else entries;

      json = name: value: pkgs.writeText "planner-${name}.json" (builtins.toJSON value);

      farm = pkgs.linkFarm "planner-deployment" (
        [
          {
            name = "plan.json";
            path = json "plan" result.plan;
          }
          {
            name = "manifest.json";
            path = json "manifest" reading.manifest;
          }
          {
            name = "diagnostics.json";
            path = json "diagnostics" reading.diagnostics;
          }
          # The rendered table travels beside the rows because the reason a build
          # or an apply gives has to be the planner's own words, and rendering is
          # the planner's.
          {
            name = "diagnostics.txt";
            path = pkgs.writeText "planner-diagnostics.txt" (planner.render reading.diagnostics + "\n");
          }
        ]
        ++ map (key: {
          name = reading.entries.${key}.artifact;
          path = links.${key};
        }) (builtins.attrNames links)
      );

      built = farm.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          inherit (result) plan;
          inherit (reading) manifest diagnostics;
          inherit entries;
        };
      });
    in
    built;

  # The same deployment read as a configuration for the external secret
  # generator, plus the two things that configuration cannot carry. The contract
  # hands its deploy step a file list and no target, so the step is rendered
  # here; and the plan of a generated value is a function of what the backend
  # holds, so what is built is the expression the run evaluates.
  #
  # programs is the caller's store backend, one derivation per command of the
  # contract. Where bytes live is a fact about disk, so it is never the plan's.
  # source is the deployment's own directory, and the file a second evaluation
  # imports is its `args.nix`: a `default.nix` there takes `pkgs`, which no
  # evaluation outside a build can hand it. That file takes
  # { planner, packages, varsState } and returns { args }, and packages is what
  # it interpolates, so both stay readable in an evaluation that holds none of
  # this one's values.
  mkGeneration =
    {
      pkgs,
      planner,
      args,
      source,
      packages,
      backend,
      programs,
    }:
    let
      reader = import ../secrets/read.nix { inherit planner; };
      step = import ../secrets/backend.nix { inherit planner reader; };

      result = planner.mkPlan args;

      # The library has no prompt vocabulary, so nothing it plans can ask a
      # question. A prompt asked at all is a defect, and this makes it a named
      # failure rather than a wedged run.
      refuse = pkgs.writeTextFile {
        name = "planner-prompt-refused";
        executable = true;
        text = ''
          #!${pkgs.runtimeShell}
          echo "planner secrets: $1/$2 asked a prompt, and a plan carries none" >&2
          exit 1
        '';
      };

      deployRemote = pkgs.writeTextFile {
        name = "planner-deploy-remote";
        executable = true;
        text = ''
          #!${pkgs.runtimeShell}
          PATH=${pkgs.openssh}/bin:${pkgs.coreutils}/bin:$PATH
          export PATH
          exec ${pkgs.runtimeShell} ${
            pkgs.writeText "planner-deploy-remote.sh" (
              step.render {
                inherit (result) plan;
                get = "${programs.get}";
              }
            )
          } "$@"
        '';
      };

      configuration = reader.configuration {
        inherit (result) plan;
        inherit backend;
        backends = {
          prompt.refused.ask = refuse.drvPath;
          store.${backend} = builtins.mapAttrs (_: program: program.drvPath) programs // {
            deploy = {
              local = null;
              remote = deployRemote.drvPath;
            };
          };
        };
      };

      names = builtins.listToAttrs (
        map (value: {
          name = value.key;
          value = value.name;
        }) (reader.valuesOf result.plan)
      );

      expression = pkgs.writeText "planner-plan-expression.nix" ''
        { varsStateFile }:
        let
          planner = import ${../lib} {
            korora = import ${korora}/types.nix;
            systems = (import ${pkgs.path}/lib).systems;
          };
          deployment = import ${source}/args.nix {
            inherit planner;
            packages = builtins.fromJSON ${builtins.toJSON (builtins.toJSON packages)};
            varsState = builtins.fromJSON (builtins.readFile varsStateFile);
          };
        in
        planner.mkPlan deployment.args
      '';

      json = name: value: pkgs.writeText "planner-${name}.json" (builtins.toJSON value);

      # The plan's rows and the reading's, as one table. The farm carries both
      # halves of it whatever it says, the way a deployment build does, and an
      # error refuses the build with the rendered table rather than with a
      # sentence one condition wrote.
      reading = reader.generation { inherit (result) plan diagnostics; };

      farm = pkgs.linkFarm "planner-generation" [
        {
          name = "secrets.json";
          path = json "secrets" configuration;
        }
        {
          name = "names.json";
          path = json "names" names;
        }
        {
          name = "plan.nix";
          path = expression;
        }
        {
          name = "diagnostics.json";
          path = json "diagnostics" reading.diagnostics;
        }
        {
          name = "diagnostics.txt";
          path = pkgs.writeText "planner-diagnostics.txt" (planner.render reading.diagnostics + "\n");
        }
      ];
    in
    if reading.refused then throw reading.refusal else farm;
}
