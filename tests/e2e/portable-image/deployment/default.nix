# One deployment, two images: the entry this host attaches and the entry it
# cannot, because no machine here runs its architecture.
#
# The two host paths and the report script are facts about this fixture and stay
# here. So does the realisation statement: nothing in a plan says whether an
# entry wants an image or a flakelet artifact, and this folder wants images.
{
  pkgs,
  planner,
  operator,
}:
let
  paths = {
    shown = "/var/lib/planner-portable/upstream.txt";
    assembled = "/etc/planner-portable/report.conf";
  };

  reportOf =
    delivery:
    pkgs.writeShellScript "planner-portable-report" ''
      set -u
      printf 'assembled-begin\n'
      ${pkgs.coreutils}/bin/cat "$ASSEMBLED"
      printf 'assembled-end\n'
      printf 'identity: uid=%s\n' "$(${pkgs.coreutils}/bin/id -u)"
      if original=$(${pkgs.coreutils}/bin/cat "$ORIGINAL" 2>&1); then
        printf 'original-read: succeeded with %s\n' "$original"
      else
        printf 'original-read: %s\n' "$original"
      fi
      printf 'delivery: %s\n' ${delivery}
      exec ${pkgs.coreutils}/bin/sleep infinity
    '';

  interfaces = import ./interfaces/default.nix { korora = planner.korora; };
  inherit (interfaces) reportFile;

  reportModuleOf = delivery: {
    services.default = import ./modules/report/default.nix {
      report = "${reportOf delivery}";
      inherit reportFile paths;
    };
  };

  mirrorModule = {
    services.default = import ./modules/mirror/default.nix {
      coreutils = "${pkgs.coreutils}";
      inherit reportFile;
    };
  };

  registry = import ./machines.nix;

  buildOf =
    delivery:
    operator.mkDeployment {
      inherit pkgs planner;

      # `watch:file` is stated strict because the enforcement is the claim under
      # test. `mirror:copy` is never attached, so it takes the default profile.
      realise = {
        "watch:file" = {
          realiser = "image";
          profile = "strict";
        };
        "mirror:copy" = {
          realiser = "image";
          profile = "default";
        };
      };

      args =
        let
          deployment = import ./instances.nix {
            report = reportModuleOf delivery;
            mirror = mirrorModule;
          };
        in
        {
          inherit (deployment) instances;
          inherit (registry) machines;

          interfaces = {
            "interfaces/default.nix" = interfaces;
          };

          sources = {
            deployment = "instances.nix";
            machines = "machines.nix";
            modules = {
              watch = "report/default.nix";
              mirror = "mirror/default.nix";
            };
            leaves = {
              watch.file = "report/watch.nix";
              mirror.copy = "mirror/copy.nix";
            };
          };
        };
    };
in
{
  default = buildOf "first";

  # A second build of the same deployment, whose unit runs another script and so
  # carries another identity. Nothing attaches it: what a report says about a
  # machine holding an earlier build needs two identities and one machine.
  changed = buildOf "second";
}
