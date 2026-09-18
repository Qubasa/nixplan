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
  inherit (builtins) filter unsafeDiscardStringContext;

  inherit (planner.util) indexBy uniqueStrings;
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

      # The roots the entry declares, linked so the artifact references them
      # and `nix copy` of it puts them on the machine. Without this an
      # unmentioned root is dropped: a path a unit names is copied because the
      # unit file names it, and a path nothing names is carried by nothing -
      # which makes a program the operator's own verbs run, and no unit does,
      # unreachable on the machine the entry is on. The image realiser roots
      # the same list into its own image root.
      #
      # The name is the base name with its context discarded and the link is
      # the path with its context kept, which is the split `util.shortHash`
      # already makes: a farm entry's name is a string the derivation writes,
      # and a string that roots a store path is a string no build can write.
      # The list is deduplicated first, two declarations of one path being one
      # link name rather than a collision `linkFarm` refuses.
      declared = map (root: {
        name = "closure/${unsafeDiscardStringContext (baseNameOf root)}";
        path = root;
      }) (uniqueStrings image.closure);
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
      ++ declared
    )).overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          inherit image meta;
          units = indexBy (u: u.file) (u: u.text) rendered;
        };
      });
}
