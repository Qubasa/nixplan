{
  perSystem =
    { config, pkgs, ... }:
    let
      pytestEnv = import ./pytest-env.nix pkgs;

      # A shell hook runs again on every nested entry, so a plain prepend would grow
      # PYTHONPATH without bound.
      onPythonPath = dir: ''
        case ":''${PYTHONPATH-}:" in
          *":${dir}:"*) ;;
          *) export PYTHONPATH="${dir}''${PYTHONPATH:+:$PYTHONPATH}" ;;
        esac
      '';
    in
    {
      devShells.planner = pkgs.mkShell {
        packages = [ pytestEnv ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          # A check copies `delivery.py` in beside the tests; here it is a path.
          # Without it the two cluster suites fail to import rather than skip.
          ${onPythonPath "$planner_root/tests/e2e"}
        '';
      };

      devShells.planner-cluster = pkgs.mkShell {
        packages = [
          pytestEnv
          pkgs.nix
          pkgs.openssh
        ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          export PLANNER_WIRED_PAIR=${config.packages.planner-e2e-wired-pair}
          export PLANNER_WIRED_PAIR_DEPLOYMENT="$planner_root/tests/e2e/wired-pair/deployment"
          export PLANNER_PORTABLE_IMAGE=${config.packages.planner-e2e-portable-image}
          export PLANNER_E2E_GUEST_IMAGE=${config.packages.planner-e2e-guest}/nixos.qcow2
          export PLANNER_E2E_SSH_KEY=${config.packages.planner-e2e-guest.sshPrivateKey}
          ${onPythonPath "$planner_root/tests/e2e"}
          if rookery_env=$(${pytestEnv}/bin/python3 ${./tests/e2e/runner.py} --print-env); then
            eval "$rookery_env"
          else
            echo "planner-cluster: no rookery, so the end-to-end tests will skip themselves" >&2
          fi
          echo "planner-cluster: pytest tests/e2e/<folder>/test_<folder>.py" >&2
        '';
      };
    };
}
