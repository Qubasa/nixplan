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
