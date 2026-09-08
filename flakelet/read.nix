# Reading one placed plan entry as a flakelet service artifact.
#
# `image/read.nix` is the whole reading: the units, the closure, the identity
# digest and every refusal about what the plan does carry are shared with the
# portable-service realiser rather than restated here. This file adds only what
# the endpoint imposes and the plan does not say:
#
#   - the two naming rules flakelet enforces before it activates anything
#     (`validate_name`, `validate_units`), as refusals rather than a mapping,
#   - the `[Install]` section, which no plan field expresses,
#   - the three metadata fields the endpoint reads back.
#
# A second reader exists because these grew past the handful of lines
# design.md allowed for them, and because a rule the pure suite can assert has
# to live outside the file that needs `pkgs` to build a link farm.
#
# `reader` is the shared reading, taken as an argument so a caller that has the
# two files as store paths rather than as a checkout - a refusal expression
# inside a check - can hand it over instead of relying on their relative
# positions surviving the trip.
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

  # flakelet links a unit into `/run/systemd/system` and starts it there. It
  # attaches nothing under a portable confinement profile, so no access is
  # denied on the entry's behalf, and `trusted` is the reading's name for a
  # profile that denies nothing. The field is the shared reading's, not this
  # backend's; a store-backed unit runs as the entry wrote it.
  confinement = "trusted";

  # `validate_name` (manager.rs:1301-1312). Named as the sentence a refusal
  # prints, so the rule and the message cannot drift apart.
  nameRule =
    "a service name is at most 128 characters, starts with an ASCII alphanumeric "
    + "and carries only ASCII alphanumerics, `-` and `_` after it - a dot is not one of them";

  acceptsName = name: stringLength name <= 128 && match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null;

  # `validate_units` (manager.rs:1314-1326): a unit file's base is the service
  # name or begins with it followed by `-`, and an instance is one `@` at most.
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

  # `[Install]` is the binding's decision, not a plan field. The plan says
  # *when* a unit runs - a `schedule` or nothing - and this file says what the
  # endpoint should do about it, because "enabled" means something different to
  # every backend: flakelet enables and starts a unit that carries an
  # `[Install]` section and leaves one that does not to systemd, to be pulled
  # in on demand by a socket or a timer (systemd.rs:166-170), while the
  # portable-service realiser wants no `[Install]` at all and attaches instead.
  #
  # So a long-running unit is wanted by `multi-user.target`; a scheduled unit's
  # *timer* is wanted by `timers.target` and its service is wanted by nothing.
  # An `[Install]` on the service of a scheduled unit would run the job once at
  # deploy time and then again on its schedule, which is the mistake this rule
  # exists to prevent.
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

  # One placed entry, read as an artifact. Every refusal is a raise on this
  # value, so it fires while the artifact is being evaluated and before any
  # file is produced.
  read =
    { plan, key }:
    let
      image = reader.read {
        inherit plan key;
        profile = confinement;
      };

      refusedUnits = filter (file: !(acceptsUnit image.name file)) (filesOf image);

      # A host path reaches a unit through a step: the image realiser's attach
      # script assembles a configuration file into its staging directory and
      # checks that a referenced generated file is on the machine before
      # anything starts. This realiser has no such step - the endpoint reads
      # `units/` and `meta.json`, links and starts (manager.rs:1349-1392) - so
      # an entry shown a host file is refused rather than rendered into a unit
      # whose `BindReadOnlyPaths` names a path nothing on the machine creates.
      # The step is the missing dependency, the way `state.json` is.
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

  # A long-running unit's text, plus the section that makes the endpoint start
  # it. A scheduled unit's service carries none: its timer is what is enabled.
  renderUnit =
    image: unitName:
    reader.renderUnit image unitName
    + (if image.units.${unitName}.timer == null then installSection "multi-user.target" else "");

  renderTimer = image: unitName: reader.renderTimer image unitName + installSection "timers.target";

  # What the endpoint reads back out of the artifact. `flake_url` is the plan
  # key, in the field whose only consumer is display and provenance - the same
  # spirit as flakelet's own `prebuilt:<name>`. `settings_hash` is the entry's
  # version digest, which is the field the endpoint carries into the generation
  # it records; the digest is over what the artifact is made of, so an entry
  # whose bytes are unchanged has an unchanged value here.
  meta = image: {
    version = 1;
    inherit (image) name;
    flake_url = "plan:${image.key}";
    flake_rev = "";
    settings_hash = image.version;
  };
}
