# The flakelet service artifact of one placed plan entry.
#
# Where the image realiser wraps the same unit files in a squashfs, this one hands
# the endpoint the directory layout it already consumes: a units directory and a
# meta.json, and nothing else.
#
# Deliberately absent: state.json, which needs a plan field this subset does not
# have, and exports.json, which would resolve wires on the machine while this
# architecture resolves them at evaluation time. Both are optional to the endpoint.
{
  pkgs,
  planner,
  # The shared reading, handed the same assembly the image builder hands it: a
  # configuration file whose bytes the plan holds is written at build time and
  # carried in this artifact, so the path the unit binds is a path the machine
  # holds once the artifact's closure has been copied.
  reader ? import ./read.nix {
    inherit planner;
    reader = import ../image/read.nix {
      inherit planner;
      assemble = name: text: "${pkgs.writeText name text}";
    };
  },
}:
let
  inherit (builtins) filter;

  inherit (planner.util) indexBy;
in
{
  inherit reader;

  # plan is the whole plan and key the placed entry to build. There is no third
  # argument: a profile, a compression and a delivery target belong to the image
  # realiser, and this artifact has none of them.
  artifact =
    { plan, key }:
    let
      image = reader.read { inherit plan key; };

      rendered = reader.renderedUnits image;

      # A configuration file the reading assembled at build time, carried beside
      # the units so the artifact holds every byte its units bind. A `source`
      # file is already someone else's store object and needs no copy; a `ref`
      # recipe is refused by the reading above.
      assembled = map (p: {
        name = "files${p.path}";
        path = p.from;
      }) (filter (p: p.kind == "configuration-file" && p.disposition == "literal") image.hostPaths);

      meta = reader.meta image;
    in
    (pkgs.linkFarm "flakelet-${image.name}" (
      [
        {
          name = "meta.json";
          path = pkgs.writeText "flakelet-${image.name}-meta.json" (builtins.toJSON meta);
        }
      ]
      ++ map (u: {
        name = "units/${u.file}";
        path = pkgs.writeText u.file u.text;
      }) rendered
      ++ assembled
    )).overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          inherit image meta;
          units = indexBy (u: u.file) (u: u.text) rendered;
        };
      });
}
