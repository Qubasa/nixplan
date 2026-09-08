# The flakelet service artifact of one placed plan entry.
#
# The second realiser over one unchanged plan. Where the portable-service
# realiser wraps the same unit files in a squashfs an image is attached from,
# this one hands the endpoint the directory layout it already consumes: a
# `units/` directory and a `meta.json`, and nothing else. Activating it needs
# no evaluator, no service-flake source and no network on the machine - the
# endpoint reads the directory, links the units and starts what carries an
# `[Install]` section (manager.rs:1349-1392, systemd.rs:166-170).
#
# What is deliberately absent: `state.json`, which needs the entry field
# `declare-service-state` adds, and `exports.json`, which would resolve wires
# on the machine while this architecture resolves them at evaluation time. Both
# are optional to the endpoint (manager.rs:1378-1391).
{
  pkgs,
  planner,
  # This realiser's reading, as an argument for the same reason it takes one:
  # a caller holding the sources as store paths hands it over.
  reader ? import ./read.nix { inherit planner; },
}:
let
  inherit (builtins) attrNames concatLists listToAttrs;
in
{
  inherit reader;

  # `plan` is the whole plan and `key` the placed entry to build. There is no
  # third argument: a profile, a compression and a delivery target are the
  # image realiser's build inputs, and this artifact has none of them.
  artifact =
    { plan, key }:
    let
      image = reader.read { inherit plan key; };

      # One record per file the artifact carries, so the text is written once
      # and the same strings are what a check asserts against.
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
