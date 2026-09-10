{ inputs, ... }:
let
  # korora is pinned as a source, so types.nix is the entry point. Importing the
  # flake's default.nix warns instead.
  korora = import "${inputs.korora}/types.nix";
  systems = inputs.nixpkgs.lib.systems;
  platformSource = inputs.nixpkgs.rev;
  folder = ./fixtures/minimal-typed-edge;
  planner = import ./lib { inherit korora systems platformSource; };
  worked = planner.mkPlan (import ./tests/unit/worked.nix { inherit planner folder; }).args;
  changesRoot = ./openspec/changes;
  imageSource = ./image;
  secretsSource = ./secrets;
  flakeletSource = ./flakelet;
  operatorSource = ./operator;
  suites = import ./tests {
    inherit
      korora
      systems
      platformSource
      folder
      changesRoot
      ;
    libSource = ./lib;
    inherit
      imageSource
      secretsSource
      flakeletSource
      operatorSource
      ;
    perfSource = ./perf;
    repoSource = ./.;
  };
in
{
  flake.lib = planner;

  # The library elaborated against a caller's own platform definitions. `flake.lib`
  # is the pin this flake carries, applied and recorded, and this is the way out of
  # it: a consumer following another package set hands its own `lib.systems` here
  # and states the identity beside it, so one package set decides every entry key
  # instead of two.
  flake.mkLib =
    {
      systems,
      platformSource ? null,
    }:
    import ./lib { inherit korora systems platformSource; };

  # The deployment build, published for a consumer that is not this repository.
  # `flake.lib` alone leaves a caller able to plan and unable to build, and the
  # only other reach is a path inside this flake's source, which is not an
  # interface. `mkDeployment` takes the caller's own `pkgs`, so it is a
  # system-independent output like the library beside it.
  flake.operator = import ./operator { korora = inputs.korora; };

  # The suites, their failures and the worked plan, under a name no application and
  # no package uses. `planner` is the command.
  flake.debug = {
    inherit worked suites;
    rendered = planner.render worked.diagnostics;
    failures = import ./tests/report.nix suites;
    failuresBySuite = builtins.mapAttrs (_: suite: import ./tests/report.nix suite) suites;
  };

  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      suite = pkgs.writeText "planner-suite.nix" ''
        import ${./tests} {
          korora = import ${inputs.korora}/types.nix;
          systems = (import ${inputs.nixpkgs}/lib).systems;
          platformSource = "${platformSource}";
          folder = ${folder};
          libSource = ${./lib};
          imageSource = ${./image};
          secretsSource = ${./secrets};
          flakeletSource = ${./flakelet};
          operatorSource = ${./operator};
          perfSource = ${./perf};
          repoSource = ${./.};
          changesRoot = ${changesRoot};
        }
      '';

      # Named separately rather than sliced out of one copy of the tree, so editing a
      # document does not invalidate a recorded measurement.
      perfRoot = ./perf;
      libRoot = ./lib;
      workedLoader = ./tests/unit/worked.nix;

      measurement =
        pkgs.runCommand "planner-perf-results"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.nix
            ];
          }
          ''
            export HOME="$(mktemp -d)"
            export NIX_CONFIG="experimental-features = nix-command"
            mkdir -p "$out"
            bash ${perfRoot}/measure.sh \
              --korora ${inputs.korora} \
              --nixpkgs ${inputs.nixpkgs} \
              --root ${perfRoot} \
              --lib ${libRoot} \
              --folder ${folder} \
              --worked ${workedLoader} \
              --out "$out"
          '';

      perf = pkgs.writeShellApplication {
        name = "planner-perf";
        runtimeInputs = [
          pkgs.jq
          pkgs.python3
          pkgs.nix
        ];
        text = ''
          out=$(mktemp -d)
          trap 'rm -rf "$out"' EXIT
          bash ${perfRoot}/measure.sh --korora "${inputs.korora}" \
            --nixpkgs "${inputs.nixpkgs}" --root ${perfRoot} \
            --lib ${libRoot} --folder ${folder} --worked ${workedLoader} \
            --out "$out" "$@"
          python3 ${perfRoot}/check.py --results "$out" --budgets ${perfRoot}/budgets.json
        '';
      };

      pytestEnv = import ./pytest-env.nix pkgs;

      # The one function that builds a deployment, handed to every folder as an
      # argument. A folder resolves no path outside itself, which is what the
      # end-to-end path scan holds it to.
      operator = import ./operator { korora = inputs.korora; };

      e2eRoot = ./tests/e2e;

      # Discovery rather than registration: a folder holding a deployment is a
      # package of this flake without a line here, the way the runner already
      # finds a folder's tests by looking.
      e2eFolders = builtins.filter (
        name: builtins.pathExists (e2eRoot + "/${name}/deployment/default.nix")
      ) (builtins.attrNames (builtins.readDir e2eRoot));

      buildsOf =
        folder:
        import (e2eRoot + "/${folder}/deployment/default.nix") {
          inherit pkgs planner operator;
        };

      # A folder's `default` build is the folder's own package name; any other
      # build of the same folder is suffixed with its own.
      e2eDeployments = builtins.listToAttrs (
        builtins.concatLists (
          map (
            folder:
            pkgs.lib.mapAttrsToList (build: deployment: {
              name = "planner-e2e-${folder}" + (if build == "default" then "" else "-${build}");
              value = deployment;
            }) (buildsOf folder)
          ) e2eFolders
        )
      );

      e2eGuest = import ./tests/e2e/guest.nix {
        inherit (pkgs) lib;
        inherit pkgs system;
        nixpkgs = inputs.nixpkgs;
        flakeletModule = inputs.flakelet.nixosModules.flakelet;
      };

      # One row per variable a machine-layer run reads off a built artifact. The app
      # exports these paths directly and `planner-e2e-env` prints the same rows out of
      # `e2eEnvPaths`, so neither can name an artifact the other does not. A
      # deployment is absent on purpose: the machine layer builds one with the
      # command, so no link farm is forced before pytest starts.
      e2eArtifactPaths = {
        PLANNER_E2E_GUEST_IMAGE = "${e2eGuest}/nixos.qcow2";
        PLANNER_E2E_SSH_KEY = "${e2eGuest.sshPrivateKey}";
        PLANNER_CLI = pkgs.lib.getExe config.packages.planner;
        PLANNER_CLI_SRC = "${config.packages.planner-src}";
      };

      envNameOf = folder: pkgs.lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] folder);

      # The declaration of each folder is the one variable that names the working
      # tree in the shell and the store in the app, so both come out of one attrset
      # rather than being written twice. `store` is that subtree alone: naming the
      # checkout root instead would put every file in the runner's closure.
      e2eDeploymentPaths = builtins.listToAttrs (
        map (folder: {
          name = "PLANNER_${envNameOf folder}_DEPLOYMENT";
          value = {
            store = e2eRoot + "/${folder}/deployment";
            rel = "tests/e2e/${folder}/deployment";
          };
        }) e2eFolders
      );

      e2eExports = pkgs.lib.concatStrings (
        pkgs.lib.mapAttrsToList (name: path: "export ${name}=${path}\n") e2eArtifactPaths
      );

      e2eEnvPaths = pkgs.writeText "planner-e2e-env-paths" e2eExports;

      # The attribute is named as a string and built when the script runs. An
      # interpolation here would put the guest image in the closure of every shell
      # this script is in, and entering the checkout would build it.
      e2eEnvScript = pkgs.writeShellApplication {
        name = "planner-e2e-env";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
        ];
        text = ''
          root="$(git rev-parse --show-toplevel)"
          cat "$(nix build --no-link --print-out-paths "$root#planner-e2e-env-paths")"
          printf 'export PLANNER_E2E_FLAKE=%q\n' "$root"
          ${pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (
              name: paths: "printf 'export ${name}=%q\\n' \"$root/${paths.rel}\"\n"
            ) e2eDeploymentPaths
          )}
          if ! ${pytestEnv}/bin/python3 ${./tests/e2e/runner.py} --print-env; then
            echo "planner-e2e-env: no rookery, so the end-to-end tests will skip themselves" >&2
          fi
        '';
      };

      e2eRunner = pkgs.writeShellApplication {
        name = "planner-e2e";
        runtimeInputs = [
          pkgs.git
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          ${e2eExports}
          ${pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (name: paths: "export ${name}=${paths.store}\n") e2eDeploymentPaths
          )}
          # `planner build` resolves a flake reference, so the checkout is what it
          # is given. A run from outside one sets nothing and the folders skip.
          if root="$(git rev-parse --show-toplevel 2> /dev/null)"; then
            export PLANNER_E2E_FLAKE="$root"
          fi
          export PLANNER_E2E=${./tests/e2e}
          exec ${pytestEnv}/bin/python3 ${./tests/e2e/runner.py} "$@"
        '';
      };

    in
    {
      checks.planner-tests =
        pkgs.runCommand "planner-tests"
          {
            nativeBuildInputs = [ pkgs.nix-unit ];
          }
          ''
            export HOME="$(mktemp -d)"
            nix-unit --eval-store "$HOME" ${suite}
            touch "$out"
          '';

      checks.planner-perf =
        pkgs.runCommand "planner-perf"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            python3 ${perfRoot}/check.py --results ${measurement} --budgets ${perfRoot}/budgets.json
            touch "$out"
          '';

      checks.planner-perf-checker =
        pkgs.runCommand "planner-perf-checker"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            cp ${./perf}/check.py ${./perf}/check_test.py .
            python3 -m unittest discover -s . -p 'check_test.py' -v
            touch "$out"
          '';

      checks.planner-delivery =
        pkgs.runCommand "planner-delivery"
          {
            nativeBuildInputs = [ pytestEnv ];
          }
          ''
            export PYTHONPATH=${./cli}
            python3 -m pytest -q -rs --no-header -p no:cacheprovider ${./tests/e2e}/test_harness.py
            touch "$out"
          '';

      packages = e2eDeployments // {
        planner-perf = perf;
        planner-perf-results = measurement;
        planner-e2e-guest = e2eGuest;
        planner-e2e-env = e2eEnvScript;
        planner-e2e-env-paths = e2eEnvPaths;
      };

      # An app rather than a check: a build sandbox has no tun device and no vhost-vsock,
      # and cannot ask the daemon whether a path is valid, which is what a delivery does
      # first.
      apps.planner-e2e = {
        type = "app";
        program = "${e2eRunner}/bin/planner-e2e";
        meta.description = "Run the planner's end-to-end tests on real machines";
      };
    };
}
