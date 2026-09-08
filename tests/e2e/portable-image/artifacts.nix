{
  pkgs,
  planner,
  imageBuilder,
}:
let
  paths = {
    shown = "/var/lib/planner-portable/upstream.txt";
    assembled = "/etc/planner-portable/report.conf";
  };

  report = pkgs.writeShellScript "planner-portable-report" ''
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
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';

  worked =
    planner.mkPlan
      (import ./deployment {
        inherit planner paths;
        packages = {
          coreutils = "${pkgs.coreutils}";
          report = "${report}";
        };
      }).args;

  confinedKey = "watch:file@alpha";
  foreignKey = "mirror:copy@elsewhere";

  images = {
    confined = imageBuilder.build {
      plan = worked.plan;
      key = confinedKey;
      # Stated strict because the enforcement is the claim under test. The image that is
      # never attached uses default.
      profile = "strict";
    };
    foreign = imageBuilder.build {
      plan = worked.plan;
      key = foreignKey;
      profile = "default";
    };
  };
in
(pkgs.linkFarm "planner-e2e-portable-image" (
  [
    {
      name = "plan.json";
      path = pkgs.writeText "planner-portable-plan.json" (builtins.toJSON worked.plan);
    }
  ]
  ++ map (name: {
    inherit name;
    path = images.${name};
  }) (builtins.attrNames images)
)).overrideAttrs
  (old: {
    passthru = (old.passthru or { }) // {
      inherit images paths;
      plan = worked;
      keys = {
        confined = confinedKey;
        foreign = foreignKey;
      };
    };
  })
