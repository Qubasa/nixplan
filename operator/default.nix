# One deployment, built. read.nix is the whole reading, and everything here is
# derivations over what that read returned: the plan, the manifest, the
# diagnostics table, and one artifact per placed entry, in one link farm.
#
# This is the first layer allowed to raise. `lib/` never does, the realisers do
# it for a fact an entry does not record, and this file does it for a deployment
# the planner itself called inapplicable - with the planner's own table as the
# message. A table carrying warnings and no error builds; a warning that stopped
# a build would be an error.
{
  mkDeployment =
    {
      pkgs,
      planner,
      args,
      realise ? {
        default.realiser = "flakelet";
      },
    }:
    let
      reader = import ./read.nix { inherit planner; };

      imageBuilder = import ../image {
        inherit (pkgs) lib;
        inherit pkgs planner;
      };

      flakeletBuilder = import ../flakelet { inherit pkgs planner; };

      result = planner.mkPlan args;

      reading = reader.read {
        inherit (result) plan diagnostics;
        inherit realise;
        storeDir = args.storeDir or builtins.storeDir;
      };

      artifactOf =
        key: entry:
        if entry.realiser == "image" then
          imageBuilder.build {
            inherit (result) plan;
            inherit key;
            inherit (entry) profile;
          }
        else
          flakeletBuilder.artifact {
            inherit (result) plan;
            inherit key;
          };

      entries = builtins.mapAttrs artifactOf reading.entries;

      json = name: value: pkgs.writeText "planner-${name}.json" (builtins.toJSON value);

      farm = pkgs.linkFarm "planner-deployment" (
        [
          {
            name = "plan.json";
            path = json "plan" result.plan;
          }
          {
            name = "manifest.json";
            path = json "manifest" reading.manifest;
          }
          {
            name = "diagnostics.json";
            path = json "diagnostics" reading.diagnostics;
          }
          # The rendered table travels beside the rows because the reason a build
          # or an apply gives has to be the planner's own words, and rendering is
          # the planner's.
          {
            name = "diagnostics.txt";
            path = pkgs.writeText "planner-diagnostics.txt" (planner.render reading.diagnostics + "\n");
          }
        ]
        ++ map (key: {
          name = reading.entries.${key}.artifact;
          path = entries.${key};
        }) (builtins.attrNames entries)
      );

      built = farm.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          inherit (result) plan;
          inherit (reading) manifest diagnostics;
          inherit entries;
        };
      });
    in
    if reading.refused then throw reading.refusal else built;
}
