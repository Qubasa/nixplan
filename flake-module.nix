{ inputs, ... }:
let
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

      pytestEnv = pkgs.python3.withPackages (ps: [ ps.pytest ]);

      clusterPytestEnv = pkgs.python313.withPackages (ps: [ ps.pytest ]);

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

      e2eGuest = import ./tests/e2e/guest.nix {
        inherit (pkgs) lib;
        inherit pkgs system;
        nixpkgs = inputs.nixpkgs;
        flakeletModule = inputs.flakelet.nixosModules.flakelet;
      };

      e2eRunner = pkgs.writeShellApplication {
        name = "planner-e2e";
        runtimeInputs = [
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          export PLANNER_WIRED_PAIR=${wiredPairArtifacts}
          export PLANNER_WIRED_PAIR_DEPLOYMENT=${./tests/e2e/wired-pair/deployment}
          export PLANNER_PORTABLE_IMAGE=${portableImageArtifacts}
          export PLANNER_E2E_GUEST_IMAGE=${e2eGuest}/nixos.qcow2
          export PLANNER_E2E=${./tests/e2e}
          exec ${clusterPytestEnv}/bin/python3 ${./tests/e2e/runner.py} "$@"
        '';
      };

      onPythonPath = dir: ''
        case ":''${PYTHONPATH-}:" in
          *":${dir}:"*) ;;
          *) export PYTHONPATH="${dir}''${PYTHONPATH:+:$PYTHONPATH}" ;;
        esac
      '';

      plannerShell = pkgs.mkShell {
        packages = [ pytestEnv ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          # A check copies `delivery.py` in beside the tests; here it is a path.
          # Without it the two cluster suites fail to import rather than skip.
          ${onPythonPath "$planner_root/tests/e2e"}
        '';
      };

      clusterShell = pkgs.mkShell {
        packages = [
          clusterPytestEnv
          pkgs.nix
          pkgs.openssh
        ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          export PLANNER_WIRED_PAIR=${wiredPairArtifacts}
          export PLANNER_WIRED_PAIR_DEPLOYMENT="$planner_root/tests/e2e/wired-pair/deployment"
          export PLANNER_PORTABLE_IMAGE=${portableImageArtifacts}
          export PLANNER_E2E_GUEST_IMAGE=${e2eGuest}/nixos.qcow2
          ${onPythonPath "$planner_root/tests/e2e"}
          if rookery_env=$(${clusterPytestEnv}/bin/python3 ${./tests/e2e/runner.py} --print-env); then
            eval "$rookery_env"
          else
            echo "planner-cluster: no rookery, so the end-to-end tests will skip themselves" >&2
          fi
          echo "planner-cluster: pytest tests/e2e/<folder>/test_<folder>.py" >&2
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

      devShells.planner = plannerShell;
      devShells.planner-cluster = clusterShell;

      apps.planner-e2e = {
        type = "app";
        program = "${e2eRunner}/bin/planner-e2e";
        meta.description = "Run the planner's end-to-end tests on real machines";
      };
    };
}
