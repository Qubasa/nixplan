{
  planner,
  reader ? import ../image/read.nix { inherit planner; },
}:
let
  inherit (builtins)
    attrNames
    concatLists
    filter
    head
    length
    match
    sort
    split
    stringLength
    ;

  inherit (planner.util) escapeRegex quote sortStrings;

  fail = message: throw "planner flakelet: ${message}";

  confinement = "trusted";

  nameRule =
    "a service name is at most 128 characters, starts with an ASCII alphanumeric "
    + "and carries only ASCII alphanumerics, `-` and `_` after it - a dot is not one of them";

  acceptsName = name: stringLength name <= 128 && match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null;

  unitRule =
    unitsOf:
    "a unit file's base is ${quote unitsOf} or begins with ${quote "${unitsOf}-"}, and carries at most one `@`";

  baseOf =
    unit:
    let
      m = match "(.*)\\.[a-z]+" unit;
    in
    if m == null then null else head m;

  instanceOf =
    base:
    let
      m = match "([^@]*)@.*" base;
    in
    if m == null then base else head m;

  atCount = base: (length (split "@" base) - 1) / 2;

  acceptsUnit =
    name: unit:
    let
      base = baseOf unit;
    in
    base != null
    && atCount base <= 1
    && (
      let
        prefix = instanceOf base;
      in
      prefix == name || match "${escapeRegex name}-.*" prefix != null
    );

  filesOf =
    image:
    concatLists (
      map (
        unitName:
        let
          u = image.units.${unitName};
        in
        [ u.file ] ++ (if u.timer == null then [ ] else [ u.timer ])
      ) (attrNames image.units)
    );

  installSection = target: "\n[Install]\nWantedBy=${target}\n";
in
{
  inherit
    reader
    confinement
    nameRule
    unitRule
    acceptsName
    acceptsUnit
    ;

  read =
    { plan, key }:
    let
      image = reader.read {
        inherit plan key;
        profile = confinement;
      };

      refusedUnits = filter (file: !(acceptsUnit image.name file)) (filesOf image);

      shownPaths = sort (a: b: a.path < b.path) image.hostPaths;
    in
    if !(acceptsName image.name) then
      fail "entry ${quote key} derives the service name ${quote image.name}, which the endpoint refuses: ${nameRule}"
    else if refusedUnits != [ ] then
      fail "entry ${quote key} renders the unit file ${quote (head (sortStrings refusedUnits))}, which the endpoint refuses: ${unitRule image.name}"
    else if shownPaths != [ ] then
      let
        first = head shownPaths;
      in
      fail "entry ${quote key} is shown the host path ${quote first.path} as a ${first.kind}, and this realiser ships unit files and metadata only: it runs no step on the machine that could assemble or check that path"
    else
      image;

  renderUnit =
    image: unitName:
    reader.renderUnit image unitName
    + (if image.units.${unitName}.timer == null then installSection "multi-user.target" else "");

  renderTimer = image: unitName: reader.renderTimer image unitName + installSection "timers.target";

  meta = image: {
    version = 1;
    inherit (image) name;
    flake_url = "plan:${image.key}";
    flake_rev = "";
    settings_hash = image.version;
  };
}
