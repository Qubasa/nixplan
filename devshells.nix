{
  perSystem =
    { config, pkgs, ... }:
    let
      pytestEnv = import ./pytest-env.nix pkgs;
    in
    {
      # One shell. The machine layer's variables are not exported at entry: each names
      # a built artifact, and a store reference in this hook would make entering the
      # checkout build a 3.7 GiB guest image. `planner-e2e-env` prints them, and the
      # rookery environment beside them, when it is called.
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.treefmt.build.devShell ];
        packages = [
          pytestEnv
          config.packages.planner-e2e-env
          pkgs.nix
          pkgs.openssh
        ];
        shellHook = ''
          planner_root="$(git rev-parse --show-toplevel)"
          # A check copies `delivery.py` in beside the tests; here it is a path.
          # Without it the two cluster suites fail to import rather than skip. A shell
          # hook runs again on every nested entry, so a plain prepend would grow
          # PYTHONPATH without bound.
          case ":''${PYTHONPATH-}:" in
            *":$planner_root/tests/e2e:"*) ;;
            *) export PYTHONPATH="$planner_root/tests/e2e''${PYTHONPATH:+:$PYTHONPATH}" ;;
          esac
          echo 'planner: eval "$(planner-e2e-env)" before pytest tests/e2e/<folder>/test_<folder>.py' >&2
        '';
      };
    };
}
