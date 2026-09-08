# The flakelet service artifact of one placed plan entry.
#
# The second realiser over one unchanged plan. Where the image realiser wraps the
# same unit files in a squashfs, this one hands the endpoint the directory layout
# it already consumes: a units directory and a meta.json, and nothing else.
# Activating it needs no evaluator, no source and no network on the machine.
#
# Deliberately absent: state.json, which needs a plan field this subset does not
# have, and exports.json, which would resolve wires on the machine while this
# architecture resolves them at evaluation time. Both are optional to the endpoint.
{
  pkgs,
  planner,
  reader ? import ./read.nix { inherit planner; },
}:
let
  inherit (builtins) attrNames concatLists listToAttrs;
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

      rendered = concatLists (
        map (
          unitName:
          let
            u = image.units.${unitName};
          in
          [
            {
              file = u.file;
              text = reader.renderUnit image unitName;
            }
          ]
          ++ (
            if u.timer == null then
              [ ]
            else
              [
                {
                  file = u.timer;
                  text = reader.renderTimer image unitName;
                }
              ]
          )
        ) (attrNames image.units)
      );

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
    )).overrideAttrs
      (old: {
        passthru = (old.passthru or { }) // {
          inherit image meta;
          units = listToAttrs (
            map (u: {
              name = u.file;
              value = u.text;
            }) rendered
          );
        };
      });
}
