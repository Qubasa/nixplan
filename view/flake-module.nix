# The read-only view of a built deployment, wired on its own. Deleting the view
# is deleting this directory and one import line in flake.nix, which is the
# property the command's own module states for the same reason.
#
# `planner-view-src` is the same source root the wrapper runs, published so the
# view's own tests import its pure half with no wrapper, the `planner-src`
# precedent. The fileset is the view's own files rather than python alone,
# because what the page serves is part of what the program is.
#
# The check that runs those tests takes a name of its own: a name that names a
# program a reader runs must not also name a check, or `nix run .#planner-view`
# and `nix build .#checks.<system>.planner-view` answer one name with a server
# and a test result.
{
  perSystem =
    { pkgs, config, ... }:
    let
      source = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.fileFilter (
          file: file.hasExt "py" || file.hasExt "css" || file.hasExt "html"
        ) ./.;
      };

      src = pkgs.runCommandLocal "planner-view-src" { } "cp -r ${source} $out";

      # The command's own source root, read off its published attribute rather
      # than constructed here: the view reads a build with the command's reader,
      # and a second copy of that path is a second answer.
      command = config.packages.planner-src;

      pytestEnv = import ../pytest-env.nix pkgs;

      view = pkgs.writeShellApplication {
        name = "planner-view";
        runtimeInputs = [
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          export PYTHONPATH=${src}:${command}
          exec ${pkgs.python3}/bin/python3 ${src}/server.py "$@"
        '';
      };
    in
    {
      packages.planner-view = view;
      packages.planner-view-src = src;

      apps.planner-view = {
        type = "app";
        program = pkgs.lib.getExe view;
        meta.description = "Show a built deployment and what its machines hold in a browser";
      };

      # No nix and no machine: the tests fabricate built deployments on disk and
      # hand the live half a recorder, so this runs in a build sandbox.
      checks.planner-view-tests =
        pkgs.runCommand "planner-view-tests"
          {
            nativeBuildInputs = [ pytestEnv ];
          }
          ''
            export PYTHONPATH=${src}:${command}
            python3 -m pytest -q -rs --no-header -p no:cacheprovider ${src}/test_view.py
            touch "$out"
          '';
    };
}
