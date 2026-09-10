# The operator's command, wired on its own. The root module is where the test
# suites, the performance harness and the end-to-end layer are registered, and a
# package an operator installs does not belong in that file: deleting the command
# is deleting this directory and one import line in flake.nix.
#
# `planner-src` is the same source root the wrapper runs, published so the
# harness can import the command's pure half and assert its ordering and its
# refusals with no machine. The root module reads both attributes off this one
# rather than constructing either, so a rename cannot leave the app and the
# machine layer's environment disagreeing.
{
  perSystem =
    { pkgs, ... }:
    let
      source = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.fileFilter (file: file.hasExt "py") ./.;
      };

      src = pkgs.runCommandLocal "planner-src" { } "cp -r ${source} $out";

      cli = pkgs.writeShellApplication {
        name = "planner";
        runtimeInputs = [
          pkgs.nix
          pkgs.openssh
        ];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${src}/planner.py "$@"
        '';
      };
    in
    {
      # The command is `planner` in every namespace that answers for it: a reader
      # who types `nix build .#planner` and one who types `nix run .#planner` are
      # asking for the same program.
      packages.planner = cli;
      packages.planner-src = src;

      apps.planner = {
        type = "app";
        program = pkgs.lib.getExe cli;
        meta.description = "Build and apply a deployment plan on the machines it names";
      };

      # `nix run .` is the first thing a reader types, and the command is the one
      # thing this flake is for running.
      apps.default = {
        type = "app";
        program = pkgs.lib.getExe cli;
        meta.description = "Build and apply a deployment plan on the machines it names";
      };
    };
}
