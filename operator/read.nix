# The whole reading of one deployment: which entries are built, which realiser
# builds each, what the result is addressed by, and every way the build is
# refused. Everything here is a pure function of the plan and the realisation
# statement, and it is total - a refusal is a row, and default.nix is what raises
# on one.
#
# The split is the realisers': read.nix is the whole reading, and everything
# beside it is derivations over what this returned. The evaluating layer has no
# `pkgs`, so a unit suite can assert this file and never a built artifact.
{
  planner,
  imageReader ? import ../image/read.nix { inherit planner; },
}:
let
  inherit (builtins)
    attrNames
    concatLists
    elem
    elemAt
    filter
    head
    length
    mapAttrs
    match
    ;

  inherit (planner.util)
    optional
    quote
    quoteList
    sortStrings
    uniqueStrings
    ;

  realisers = [
    "flakelet"
    "image"
  ];

  defaultRealiser = "flakelet";

  # A plan key in a path would be legal and awful: `@` and `:` are the two
  # characters the key grammar splits on, so every consumer would quote them. The
  # projection is one rule and the manifest records the mapping, so nothing
  # reconstructs a name from a key. It is not injective, which is why a collision
  # is a refusal rather than a mangling.
  projected = builtins.replaceStrings [ ":" "@" ] [ "-" "-" ];

  # What a record is, is decided by what it records. `machine` is a legal instance
  # name and `vars/x` a legal member name, so a classification that read the text
  # of a key would answer for a deployment the planner accepts.
  shapeOf =
    record:
    if record ? delivery then
      "value"
    else if record ? placement then
      "entry"
    else if record ? address || record ? tags then
      "machine"
    else
      null;

  machineRecordOf =
    plan: machine:
    let
      record = plan."machine:${machine}" or { };
    in
    if shapeOf record == "machine" then record else { };

  parseKey =
    key:
    let
      m = match "([^:]+):([^@]+)@(.+)" key;
    in
    if m == null then
      null
    else
      {
        instance = elemAt m 0;
        service = elemAt m 1;
        machine = elemAt m 2;
      };

  # A statement is read by plan key, then by the `<instance>:<service>` prefix,
  # then by `default`. A statement that names an entry without naming a realiser
  # still takes the default one: what it carries is the fact the default cannot.
  statementOf =
    realise: key: parts:
    let
      prefix = "${parts.instance}:${parts.service}";
    in
    if realise ? ${key} then
      realise.${key}
    else if realise ? ${prefix} then
      realise.${prefix}
    else
      realise.default or { };

  unitFilesOf =
    name: units:
    sortStrings (
      concatLists (
        map (
          unitName:
          [ (imageReader.unitFileName name unitName) ]
          ++ optional (units.${unitName} ? schedule) (imageReader.timerFileName name unitName)
        ) (attrNames units)
      )
    );

  readEntry =
    {
      plan,
      realise,
    }:
    key:
    let
      parts = parseKey key;
      statement = statementOf realise key parts;
      stated = realise.default.realiser or defaultRealiser;
      realiser = statement.realiser or stated;
      known = elem realiser realisers;
      profile = statement.profile or null;
      record = machineRecordOf plan parts.machine;
      declared = record.address or null;
      address = if declared == "" then null else declared;
      entry = plan.${key};
      name = imageReader.nameOf parts;
      realised = entry.units or { } != { };
      named = realise ? ${key} || realise ? "${parts.instance}:${parts.service}";
    in
    {
      inherit
        key
        realiser
        profile
        address
        name
        ;
      inherit (parts) instance service machine;
      inherit realised;
      projection = projected key;
      artifact = if realised then "entries/${projected key}" else null;
      units = unitFilesOf name (entry.units or { });
      digest = entry.key;
      rows =
        if !realised then
          optional named (
            planner.error {
              id = "operator-entry-realises-nothing";
              subject = key;
              message = "entry ${quote key} is stated to be realised by ${quote realiser} and declares no unit, so there is nothing to realise for it";
              evidence = "an entry whose whole contribution is an export runs nothing, and a realiser of it would produce an artifact with no unit to attach";
              resolution = "remove ${quote key} from the deployment's `realise` argument, or declare a unit for it";
            }
          )
        else
          optional (!known) (
            planner.error {
              id = "operator-realiser-unknown";
              subject = key;
              message = "entry ${quote key} is stated to be realised by ${quote realiser}, and the realisers that exist are ${quoteList realisers}";
              evidence = "the realisation statement is read by plan key, then by the `<instance>:<service>` prefix, then by `default`";
              resolution = "state one of ${quoteList realisers} for ${quote key} in the deployment's `realise` argument";
            }
          )
          ++ optional (known && realiser == "image" && profile == null) (
            planner.error {
              id = "operator-image-profile-missing";
              subject = key;
              message = "entry ${quote key} is stated to be realised as an image and its statement carries no ${quote "profile"}";
              evidence = "a confinement profile is a build input no plan field records, so it is stated rather than chosen by the builder";
              resolution = "add a `profile` to the `realise` statement of ${quote key}: one of ${quoteList imageReader.profileNames}";
            }
          )
          ++ optional (address == null) (
            planner.error {
              id = "operator-entry-machine-no-address";
              subject = key;
              message = "entry ${quote key} is placed on machine ${quote parts.machine}, and the plan's `machine:${parts.machine}` record declares no address";
              evidence = "an artifact is copied to the address the registry declared, and an entry's own target is never consulted for it";
              resolution = "declare an `address` for ${quote parts.machine} in the deployment's machine registry";
            }
          );
    };

  # `program` is recorded only where the plan records one, so the manifest of a
  # deployment whose values are the operator's own is the bytes it always was.
  # The command reads it to know whose bytes a value's are: a value naming a
  # generator is produced and delivered by the external tool, and an apply asks
  # the operator for none of it.
  readValue =
    plan: key:
    let
      entry = plan.${key};
    in
    {
      inherit key;
      inherit (entry) delivery;
      files = mapAttrs (_: file: { inherit (file) path secrecy; }) entry.files;
    }
    // (if entry.program or null == null then { } else { inherit (entry) program; });

  collisionRows =
    entries:
    let
      names = sortStrings (uniqueStrings (map (key: entries.${key}.projection) (attrNames entries)));
      sharing = name: filter (key: entries.${key}.projection == name) (sortStrings (attrNames entries));
    in
    concatLists (
      map (
        name:
        let
          keys = sharing name;
        in
        optional (length keys > 1) (
          planner.error {
            id = "operator-entry-name-collision";
            subject = head keys;
            message = "entries ${quoteList keys} all project onto the artifact name ${quote name}";
            evidence = "an artifact is addressed by the name its plan key projects onto, and one directory cannot hold two entries";
            resolution = "rename one of the instances, services or machines so that the two keys project onto different names";
          }
        )
      ) names
    );
in
{
  inherit projected parseKey realisers;

  # plan is the plan artifact, realise the statement of how each entry is
  # realised, storeDir the store the artifacts are copied out of, and diagnostics
  # the planner's own table. The table is an argument rather than a fact of this
  # file because a plan does not carry the rows that produced it, and refusing an
  # inapplicable deployment is a decision the reading owns.
  read =
    {
      plan,
      realise ? { },
      storeDir ? builtins.storeDir,
      diagnostics ? [ ],
    }:
    let
      keys = sortStrings (attrNames plan);

      placedKeys = filter (key: shapeOf plan.${key} == "entry" && parseKey key != null) keys;

      valueKeys = filter (key: shapeOf plan.${key} == "value") keys;

      unplaceable = filter (key: shapeOf plan.${key} == null) keys;

      shapeRows = map (
        key:
        planner.error {
          id = "operator-plan-record-unclassified";
          subject = key;
          message = "the plan record ${quote key} records no ${quote "delivery"}, no ${quote "placement"} and no address, so it is neither a generated value, a service entry nor a machine record";
          evidence = "a record is classified by what it records and never by the text of its key, so a fourth kind of record is a record this reading cannot place";
          resolution = "teach the reading the shape of ${quote key}, or stop emitting a record no realiser can be chosen for";
        }
      ) unplaceable;

      entries = builtins.listToAttrs (
        map (key: {
          name = key;
          value = readEntry { inherit plan realise; } key;
        }) placedKeys
      );

      values = builtins.listToAttrs (
        map (key: {
          name = key;
          value = readValue plan key;
        }) valueKeys
      );

      rows =
        concatLists (map (key: entries.${key}.rows) placedKeys) ++ shapeRows ++ collisionRows entries;

      table = planner.mkTable (diagnostics ++ rows);

      refused = filter (r: r.severity == "error") table != [ ];

      manifest = {
        version = 1;
        inherit storeDir;
        entries = mapAttrs (_: entry: {
          path = entry.artifact;
          inherit (entry)
            realiser
            profile
            machine
            address
            units
            ;
          key = entry.digest;
        }) entries;
        values = mapAttrs (
          _: value:
          {
            inherit (value) delivery files;
          }
          // (if value ? program then { inherit (value) program; } else { })
        ) values;
      };
    in
    {
      inherit
        entries
        values
        manifest
        rows
        storeDir
        refused
        ;

      diagnostics = table;

      refusal =
        if refused then
          "planner operator: this deployment is not applicable, so no entry of it was realised.\n\n"
          + planner.render table
        else
          null;
    };
}
