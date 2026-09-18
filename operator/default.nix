# One deployment, built. read.nix is the whole reading, and everything over it is
# derivations: the plan, the manifest, the diagnostics table, and one artifact per
# placed entry, in one link farm. mkGeneration is the same plan read as a
# configuration for the external secret generator.
#
# This is the first layer allowed to raise, and what it raises for is a caller
# asking for the artifact of an entry of an inapplicable deployment, or a
# generation whose table carries an error, with the rendered table as the message
# either way. The tree itself is always produced.
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
      # The operator's own image signing key, one per operator and never per
      # entry: a user-scope image is attached from outside the system trusted
      # directories, so its dm-verity roothash has to be signed. It reaches the
      # image build and nothing else - no plan field, no reading field, no
      # manifest field and no artifact holds it - so rotating it re-keys
      # nothing, and a user-scope build handed none is the image builder's own
      # refusal.
      signing ? null,
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
            inherit key signing;
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

      # One shell word, the library's own escape rather than a second copy of
      # it. Every path, mode and account below reaches a script through it, in a
      # message as much as in an argument: `lib.escapeShellArg` leaves a
      # safe-looking word bare, and a message that re-parses a path is a message
      # the next deployment spells differently.
      inherit (planner.util) shellQuote;

      # The sealing tool, absolute: nothing in a plan provisions a package and a
      # machine's own `PATH` is not a fact the build records, so the program
      # arrives in the artifact's own closure and is named by its store path.
      age = "${pkgs.age}/bin/age";

      # The machine's own identity file, minted at provision time by the
      # operator. This names the path; the machine holds the bytes, and nothing
      # in this tree ever holds, reads or transports the private half.
      identity = "/var/lib/planner/age.key";

      # Every directory of one plaintext's own chain, each named rather than
      # left to `install -d` to create along the way, because a component
      # `install -d` creates for itself is created at the caller's umask and not
      # at the mode. `0711` is the write step's own mode and for its own reason:
      # a unit reaches its value by the full path, so traversal is the only
      # access any account needs, and a listable directory publishes the value
      # file names of every entry on the machine. The chain starts at the value
      # root, whose parent is the machine's.
      chainOf =
        file:
        let
          root = planner.util.varsRoot;
          parts = builtins.filter (p: p != "") (
            pkgs.lib.splitString "/" (pkgs.lib.removePrefix root (builtins.dirOf file.path))
          );
        in
        [ root ]
        ++ pkgs.lib.genList (i: "${root}/${builtins.concatStringsSep "/" (pkgs.lib.take (i + 1) parts)}") (
          builtins.length parts
        );

      # The restore of one value. A plaintext already there is left alone: a
      # restore must never replace a fresher delivery with an older seal.
      # Otherwise the seal is opened into a temporary created `0600` before its
      # first byte, inside the plaintext's own chain, then owned, chmodded to the
      # record and moved into place. That is the write step's discipline and it
      # is here for the same reason - the move is what makes the window in which
      # the bytes are readable by anyone the record excludes empty rather than
      # narrow - and no step of it reads the environment's umask. In user scope
      # the ownership step is a no-op, the account owning what it writes.
      #
      # A copy that is simply not there is named and costs no exit status: the
      # machine is where it is today, the report says so per value, and a boot
      # before the first apply is not a failure of this unit. A copy that is
      # there and does not open is the failure, and the rest are still restored.
      #
      # The tool's own diagnosis goes to `/dev/null` and this file's own line is
      # the message: a copy sealed to a rotated identity and a copy whose bytes
      # were damaged are one condition the design does not claim to tell apart,
      # and a parser echoing the bytes it refused is a log line holding bytes
      # nothing asked it to hold.
      restoreOf =
        userScope: file:
        let
          path = shellQuote file.path;
          sealed = shellQuote file.sealed;
          tmp = shellQuote "${file.path}.unsealing";
          owned = shellQuote "${file.owner}:${file.group}";
          # An account owns what it creates and can hand a file to nobody else,
          # so the ownership is stated only where the scope grants it: a record
          # a user scope cannot honor is a planner refusal long before this
          # script exists, and the mode is the account's own to set.
          own = if userScope then "" else "chown ${owned} \"$tmp\"\n    ";
        in
        ''
          if [ -e ${path} ]; then
            :
          elif [ ! -e ${sealed} ]; then
            printf 'planner unseal: no sealed copy of %s on this machine\n' ${path} >&2
          else
            tmp=${tmp}
            trap 'rm -f "$tmp"' EXIT
            install -m 0600 /dev/null "$tmp"
            if ${age} --decrypt --identity ${shellQuote identity} ${sealed} > "$tmp" 2>/dev/null; then
              ${own}chmod ${shellQuote file.mode} "$tmp"
              mv -f "$tmp" ${path}
              trap - EXIT
              printf 'unsealed %s\n' ${path}
              restored=$((restored + 1))
            else
              rm -f "$tmp"
              trap - EXIT
              printf 'planner unseal: the sealed copy of %s did not open\n' ${path} >&2
              failed=$((failed + 1))
            fi
          fi
        '';

      # The one question `planner status` asks a machine about its seals,
      # answered for every value of that machine in one run: whether the copy is
      # there and whether it opens, and nothing about any byte of it. The trial
      # is the only answerable question - a native recipient stanza names no
      # recipient, so a sealed file is attributable to no key by inspection - and
      # a copy sealed to a rotated identity and a copy whose bytes were damaged
      # are both `unreadable`, which is what the word says rather than claiming
      # to know which. The status is a question and never a verdict, so the
      # program always exits zero and the report decides.
      trialOf =
        file:
        let
          sealed = shellQuote file.sealed;
        in
        ''
          if [ ! -e ${sealed} ]; then
            printf '%s absent\n' ${sealed}
          elif ${age} --decrypt --identity ${shellQuote identity} ${sealed} > /dev/null 2>&1; then
            printf '%s opens\n' ${sealed}
          else
            printf '%s unreadable\n' ${sealed}
          fi
        '';

      # A oneshot that orders and does not require. `Before=` alone orders
      # without pulling anything in, so the unit is wanted by its manager's own
      # default target as well; and because nothing requires it, a machine whose
      # seals do not open still starts its readers and they still fail on the
      # file that is not there, which is today's behaviour with the report
      # naming it.
      unitOf =
        record: program:
        ''
          [Unit]
          Description=planner: restore this machine's sealed values
          After=local-fs.target
        ''
        + pkgs.lib.optionalString (record.before != [ ]) ''
          Before=${builtins.concatStringsSep " " record.before}
        ''
        + ''

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=${program}

          [Install]
          WantedBy=${if record.scope == "user" then "default.target" else "multi-user.target"}
        '';

      # One artifact per machine the reading records as sealing, addressed by
      # that machine's own name: a name carrying a key separator is refused
      # before any key exists and machine names are unique by construction, so
      # there is no projection here and no collision analogue. It is a function
      # of the value file records delivered there, of the machine's scope and of
      # the units it precedes, and of the recipient in no part, so a rotation
      # rebuilds nothing.
      unsealerOf =
        machine: record:
        let
          userScope = record.scope == "user";

          preamble = ''
            #!${pkgs.runtimeShell}
            set -eu

            PATH=${pkgs.coreutils}/bin
            export PATH
          '';

          directories = pkgs.lib.unique (
            planner.util.sortStrings (builtins.concatLists (map chainOf record.files))
          );

          unseal = pkgs.writeScript "planner-unseal-${machine}" (
            preamble
            + ''

              restored=0
              failed=0
            ''
            + pkgs.lib.optionalString (record.files != [ ]) ''
              install -d -m 0711 ${builtins.concatStringsSep " " (map shellQuote directories)}
            ''
            + builtins.concatStringsSep "" (map (restoreOf userScope) record.files)
            + ''

              if [ "$restored" -eq 0 ]; then
                printf 'nothing to unseal\n'
              fi

              # Non-zero so that the failure is visible in the machine's own
              # service manager, after every value that could be restored was.
              if [ "$failed" -ne 0 ]; then
                exit 1
              fi

              exit 0
            ''
          );

          check = pkgs.writeScript "planner-unseal-check-${machine}" (
            preamble + "\n" + builtins.concatStringsSep "" (map trialOf record.files) + "\nexit 0\n"
          );
        in
        pkgs.linkFarm "planner-unseal-${machine}" [
          {
            name = "bin/unseal";
            path = unseal;
          }
          {
            name = "bin/check";
            path = check;
          }
          {
            name = record.unit;
            path = pkgs.writeText "planner-unseal-${machine}.service" (unitOf record unseal);
          }
        ];

      sealing = planner.util.filterAttrs (_: record: record.sealed) reading.machines;

      # Nothing is built for an inapplicable deployment here either, and asking
      # for one machine's unsealer is answered with the table.
      machines =
        if reading.refused then
          builtins.mapAttrs (_: _: throw reading.refusal) sealing
        else
          builtins.mapAttrs unsealerOf sealing;

      machineLinks = if reading.refused then { } else machines;

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
        ++ map (machine: {
          name = reading.machines.${machine}.artifact;
          path = machineLinks.${machine};
        }) (builtins.attrNames machineLinks)
      );

      built = farm.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          inherit (result) plan;
          inherit (reading) manifest diagnostics;
          inherit entries machines;
        };
      });
    in
    built;

  # The same deployment read as a configuration for the external secret
  # generator, plus the two things that configuration cannot carry: the deploy
  # step, which the contract hands a file list and no target, and the plan of a
  # generated value, which is a function of what the backend holds and is
  # therefore built as the expression the run evaluates.
  #
  # `source` is the deployment's own directory, and the file a second evaluation
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
                # The sealing program, named absolutely the way `get` is: the
                # plan holds no store path to a tool, and what a step seals with
                # is this build's answer rather than the machine's `PATH`.
                seal = "${pkgs.age}/bin/age";
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
