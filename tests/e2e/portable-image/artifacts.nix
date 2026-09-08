# The two entries of the portable-image deployment, built by the image realiser.
#
# One is planned for the machine the run boots and is attached there; the other
# is planned for a machine of another architecture and is carried to the same
# machine so its own attach script can refuse it. Both are real images: a
# squashfs with the entry's closure in it, the unit files the plan implies, and
# the two scripts the machine runs.
{
  pkgs,
  planner,
  imageBuilder,
}:
let
  # The machine's own paths. `shown` is the operator's file, which the image
  # never carries and the confined unit cannot reach; `assembled` is where the
  # entry's own copy of it is shown to that unit.
  paths = {
    shown = "/var/lib/planner-portable/upstream.txt";
    assembled = "/etc/planner-portable/report.conf";
  };

  # What the confined unit runs. It prints the file it was shown, the identity
  # the profile gave it, and what happens when it reaches for the operator's own
  # copy of that file - which is on the machine and outside anything the image
  # was shown. All three reach the journal before it settles into a long-running
  # unit, so a reader asks the service manager rather than the test.
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

  # The profile each entry is stated to attach under. `strict` is stated for the
  # entry a machine really attaches because the claim under test is that the
  # machine enforces it; the other is `default` and never attaches.
  images = {
    confined = imageBuilder.build {
      plan = worked.plan;
      key = confinedKey;
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
