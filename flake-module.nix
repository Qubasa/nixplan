{ inputs, ... }:
let
  # korora is pinned as a source, so types.nix is the entry point. Importing the
  # flake's default.nix warns instead.
  korora = import "${inputs.korora}/types.nix";
  systems = inputs.nixpkgs.lib.systems;
  folder = ./fixtures/minimal-typed-edge;
  planner = import ./lib { inherit korora systems; };
  worked = planner.mkPlan (import ./tests/unit/worked.nix { inherit planner folder; }).args;
  changesRoot = ./openspec/changes;
  imageSource = ./image;
  flakeletSource = ./flakelet;
  suites = import ./tests {
    inherit
      korora
      systems
      folder
      changesRoot
      ;
    libSource = ./lib;
    inherit imageSource flakeletSource;
    perfSource = ./perf;
    repoSource = ./.;
  };
in
{
  flake.lib = planner;

  flake.planner = {
    inherit worked suites;
    rendered = planner.render worked.diagnostics;
    failures = import ./tests/report.nix suites;
    failuresBySuite = builtins.mapAttrs (_: suite: import ./tests/report.nix suite) suites;
  };

  perSystem =
    { pkgs, system, ... }:
    let
      suite = pkgs.writeText "planner-suite.nix" ''
        import ${./tests} {
          korora = import ${inputs.korora}/types.nix;
          systems = (import ${inputs.nixpkgs}/lib).systems;
          folder = ${folder};
          libSource = ${./lib};
          imageSource = ${./image};
          flakeletSource = ${./flakelet};
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

      imageBuilder = import ./image {
        inherit (pkgs) lib;
        inherit pkgs planner;
      };

      flakeletBuilder = import ./flakelet {
        inherit pkgs planner;
      };

      wiredPairArtifacts = import ./tests/e2e/wired-pair/artifacts.nix {
        inherit pkgs planner flakeletBuilder;
      };

      portableImageArtifacts = import ./tests/e2e/portable-image/artifacts.nix {
        inherit pkgs planner imageBuilder;
      };

      secretDeliveryArtifacts = import ./tests/e2e/secret-delivery/artifacts.nix {
        inherit pkgs planner flakeletBuilder;
      };

      e2eGuest = import ./tests/e2e/guest.nix {
        inherit (pkgs) lib;
        inherit pkgs system;
        nixpkgs = inputs.nixpkgs;
        flakeletModule = inputs.flakelet.nixosModules.flakelet;
      };

      # One row per variable a machine-layer run reads off a built artifact. The app
      # exports these paths directly and `planner-e2e-env` prints the same rows out of
      # `e2eEnvPaths`, so neither can name an artifact the other does not.
      e2eArtifactPaths = {
        PLANNER_WIRED_PAIR = "${wiredPairArtifacts}";
        PLANNER_PORTABLE_IMAGE = "${portableImageArtifacts}";
        PLANNER_SECRET_DELIVERY = "${secretDeliveryArtifacts}";
        PLANNER_E2E_GUEST_IMAGE = "${e2eGuest}/nixos.qcow2";
        PLANNER_E2E_SSH_KEY = "${e2eGuest.sshPrivateKey}";
      };

      # The deployment of each folder is the one variable that names the working tree
      # in the shell and the store in the app, so both come out of one attrset rather
      # than being written twice. `store` is that subtree alone: naming the checkout
      # root instead would put every file in the runner's closure.
      e2eDeploymentPaths = {
        PLANNER_WIRED_PAIR_DEPLOYMENT = {
          store = ./tests/e2e/wired-pair/deployment;
          rel = "tests/e2e/wired-pair/deployment";
        };
        PLANNER_SECRET_DELIVERY_DEPLOYMENT = {
          store = ./tests/e2e/secret-delivery/deployment;
          rel = "tests/e2e/secret-delivery/deployment";
        };
      };

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
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          ${e2eExports}
          ${pkgs.lib.concatStrings (
            pkgs.lib.mapAttrsToList (name: paths: "export ${name}=${paths.store}\n") e2eDeploymentPaths
          )}
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
            python3 -m pytest -q -rs --no-header -p no:cacheprovider ${./tests/e2e}/test_harness.py
            touch "$out"
          '';

      packages.planner-perf = perf;
      packages.planner-perf-results = measurement;
      packages.planner-e2e-wired-pair = wiredPairArtifacts;
      packages.planner-e2e-guest = e2eGuest;
      packages.planner-e2e-portable-image = portableImageArtifacts;
      packages.planner-e2e-secret-delivery = secretDeliveryArtifacts;
      packages.planner-e2e-env = e2eEnvScript;
      packages.planner-e2e-env-paths = e2eEnvPaths;

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
