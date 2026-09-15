# Reading one placed plan entry as a flakelet service artifact.
#
# The image realiser's reading is the whole reading: the units, the closure, the
# identity digest and every refusal about the plan are shared rather than restated
# here. This file adds only what the endpoint imposes and the plan does not say:
# flakelet's two naming rules, the install section, and the metadata it reads back.
#
# The three refusals here raise, and each is a condition the deployment build
# reports as an error row first: it asks this file's own predicates, because which
# realiser meets an entry is a fact of the realisation statement and no plan field
# carries it. A raise here is the answer a caller reaching this file directly
# receives.
#
# reader is an argument so a caller holding the two files as store paths can hand
# it over instead of relying on their relative positions.
{
  planner,
  reader ? import ../image/read.nix { inherit planner; },
}:
let
  inherit (builtins)
    filter
    head
    length
    match
    sort
    split
    stringLength
    ;

  inherit (planner.util) escapeRegex quote;

  # Every refusal this reading can make, and the row that reports the same
  # condition first. The pairing is data the refusal carries, so rewording a
  # message moves nothing, and `tests/unit/diagnostics.nix` fails for an account
  # naming a row no producing layer produces.
  accounts = {
    nameRefused.id = "operator-entry-name-refused";
    unitRefused.id = "operator-entry-name-refused";
    pathNotAssembled.id = "operator-entry-path-not-assembled";
    pathNotInstallable.id = "operator-entry-path-not-installable";
  };

  fail = _account: message: throw "planner flakelet: ${message}";

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

  # The two rules above, as the shared reading is handed them: it renders the
  # units of either realiser, so the refusal it makes is the endpoint's own
  # rather than the image builder's.
  rules = {
    inherit
      nameRule
      acceptsName
      unitRule
      acceptsUnit
      ;
    nameRefused =
      { key, name }:
      fail accounts.nameRefused "entry ${quote key} derives the service name ${quote name}, which the endpoint refuses: ${nameRule}";
    unitRefused =
      {
        key,
        name,
        file,
      }:
      fail accounts.unitRefused "entry ${quote key} renders the unit file ${quote file}, which the endpoint refuses: ${unitRule name}";
  };

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

  # A host path this realiser shows has to name bytes the machine already holds,
  # because it runs no step there: the endpoint reads the directory, links and
  # starts. A delivered generated file arrives at its own path before the entry is
  # activated; a configuration file that is a store path, or one assembled from
  # literals at build time, arrives with the artifact's closure. Only a recipe
  # naming a reference is bytes that exist on no machine until that path is
  # written, and that one is refused.
  pathRule = "a host path this realiser shows is a path whose bytes exist before the entry is activated, because it runs no step on the machine that could assemble one";

  acceptsHostPath =
    p:
    if p.kind == "configuration-file" then
      p.disposition == "source" || p.disposition == "literal"
    else
      p.from == p.path;

  # The second half, over the record rather than the bytes. A unit binds a store
  # object here, and a store object carries one ownership and one mode, so a file
  # whose declaration asks for another is a file only a realiser that installs on
  # the machine can show. A generated file's record is the delivery's and not
  # this realiser's, which is why only a configuration file is asked.
  recordRule = "a configuration file this realiser shows carries the record a store object carries, ${reader.recordOf reader.storeRecord}, because it binds store objects and runs no step on the machine to install another";

  acceptsRecord = p: p.kind != "configuration-file" || !p.install;
in
{
  inherit
    reader
    confinement
    nameRule
    unitRule
    pathRule
    recordRule
    acceptsName
    acceptsUnit
    acceptsHostPath
    acceptsRecord
    accounts
    ;

  inherit (reader) backend;

  read =
    { plan, key }:
    let
      image = reader.read {
        inherit plan key rules;
        profile = confinement;
      };

      shownPaths = sort (a: b: a.path < b.path) (filter (p: !(acceptsHostPath p)) image.hostPaths);

      shownRecords = sort (a: b: a.path < b.path) (
        filter (p: acceptsHostPath p && !(acceptsRecord p)) image.hostPaths
      );
    in
    if shownPaths != [ ] then
      let
        first = head shownPaths;
      in
      fail accounts.pathNotAssembled "entry ${quote key} is shown the host path ${quote first.path}, whose recipe reads ${
        quote (first.needs or first.from)
      }: ${pathRule}"
    else if shownRecords != [ ] then
      let
        first = head shownRecords;
      in
      fail accounts.pathNotInstallable "entry ${quote key} is shown the host path ${quote first.path}, whose declaration states ${quote (reader.recordOf first)}: ${recordRule}"
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
