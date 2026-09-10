{
  perSystem =
    { config, pkgs, ... }:
    let
      pytestEnv = import ./pytest-env.nix pkgs;
    in
    {
      # One shell, and a shell of this checkout: it carries `planner`, the command
      # its own documentation is about. The machine layer's variables are not
      # exported at entry, because each names a built artifact and a reference to one
      # here would make entering the checkout build a 3.7 GiB guest image.
      # `planner-e2e-env` prints them, and the rookery environment beside them, when
      # it is called. The flake's own source is not such an artifact.
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.treefmt.build.devShell ];
        packages = [
          pytestEnv
          config.packages.planner
          config.packages.planner-e2e-env
          pkgs.nix
          pkgs.openssh
        ];
        shellHook = ''
          # The checkout this shell was built from, which is the checkout it is a
          # shell of. `git rev-parse --show-toplevel` answers about the directory the
          # caller happened to be in, so entering this shell from an unrelated
          # repository configured that repository and entering it from no repository
          # at all exported `/tests/e2e:/cli`.
          planner_flake=${./.}
          planner_root="$planner_flake"

          # A check copies `delivery.py` in beside the tests and names the command by
          # store path; here both are paths in the checkout, which is what an edit
          # means. Without them the cluster suites fail to import rather than skip.
          # The working tree is what an edit is in, so it is preferred where it is
          # this repository's, and named beside the store copy where it is not.
          if planner_tree="$(git rev-parse --show-toplevel 2> /dev/null)" &&
            cmp -s "$planner_tree/flake.nix" "$planner_flake/flake.nix"; then
            planner_root="$planner_tree"
          elif [ -n "''${planner_tree-}" ]; then
            echo "planner: $planner_tree is not the checkout this shell was built from ($planner_flake), so the store copy is what is configured: an edit in that tree is read by nothing here" >&2
          else
            echo "planner: no git checkout here, so the store copy is what is configured ($planner_flake): an edit is read by nothing until you enter this shell from a checkout of nixplan" >&2
          fi

          # A shell hook runs again on every nested entry, so a plain prepend would
          # grow PYTHONPATH without bound.
          case ":''${PYTHONPATH-}:" in
            *":$planner_root/tests/e2e:"*) ;;
            *)
              export PYTHONPATH="$planner_root/tests/e2e:$planner_root/cli''${PYTHONPATH:+:$PYTHONPATH}"
              ;;
          esac
          echo 'planner: eval "$(planner-e2e-env)" before pytest tests/e2e/<folder>/test_<folder>.py' >&2
        '';
      };
    };
}
