# Reading one placed plan entry as a flakelet service artifact.
#
# The image realiser's reading is the whole reading: the units, the closure, the
# identity digest and every refusal about the plan are shared rather than restated
# here. This file adds only what the endpoint imposes and the plan does not say:
# flakelet's two naming rules, the install section, and the metadata it reads back.
#
# reader is an argument so a caller holding the two files as store paths can hand
# it over instead of relying on their relative positions.
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

  # flakelet links a unit into the runtime directory and starts it there, attaching
  # no portable confinement profile, so nothing is denied on the entry's behalf.
  # trusted is the shared reading's name for a profile that denies nothing.
  confinement = "trusted";

  # flakelet's own name rule, written as the sentence a refusal prints so the rule
  # and the message cannot drift apart.
  nameRule =
    "a service name is at most 128 characters, starts with an ASCII alphanumeric "
    + "and carries only ASCII alphanumerics, `-` and `_` after it - a dot is not one of them";

  acceptsName = name: stringLength name <= 128 && match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null;

  # flakelet's unit rule: a unit file's base is the service name or begins with it
  # followed by a hyphen, and an instance is one @ at most.
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

  # The install section is the binding's decision, not a plan field. The plan says
  # when a unit runs, and "enabled" means something different to every backend:
  # flakelet starts a unit that carries one and leaves the rest to systemd, to be
  # pulled in on demand by a socket or a timer.
  #
  # So a long-running unit is wanted by multi-user.target, while a scheduled unit's
  # timer is wanted by timers.target and its service is wanted by nothing. An
  # install section on that service would run the job once at deploy time and then
  # again on its schedule, which is the mistake this rule prevents.
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

      # A host path reaches a unit through an assemble step, and this realiser has
      # none: the endpoint reads the directory, links and starts. An entry shown a
      # host file is refused rather than rendered into a unit whose bind mount
      # names a path nothing on the machine creates.
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

  # What the endpoint reads back. The plan key goes in the field whose only
  # consumer is display and provenance, and settings_hash is the entry's version
  # digest, so an entry whose bytes are unchanged has an unchanged value here.
  meta = image: {
    version = 1;
    inherit (image) name;
    flake_url = "plan:${image.key}";
    flake_rev = "";
    settings_hash = image.version;
  };
}
