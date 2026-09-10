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
  flakeletReader ? import ../flakelet/read.nix {
    inherit planner;
    reader = imageReader;
  },
}:
let
  inherit (builtins)
    attrNames
    concatLists
    elem
    elemAt
    filter
    head
    isAttrs
    isString
    length
    mapAttrs
    match
    typeOf
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

  prefixOf = parts: "${parts.instance}:${parts.service}";

  shown = value: if isString value then quote value else "a ${typeOf value}";

  # Every field is resolved down the same three steps: the plan key, then the
  # `<instance>:<service>` prefix, then `default`. Resolving per statement rather
  # than per field would leave a reader having to know which fields inherit.
  statementSteps =
    realise: key: parts:
    filter (s: s.value != null) [
      {
        from = key;
        value = realise.${key} or null;
      }
      {
        from = prefixOf parts;
        value = realise.${prefixOf parts} or null;
      }
      {
        from = "default";
        value = realise.default or null;
      }
    ];

  fieldOf =
    steps: field:
    let
      carrying = filter (s: isAttrs s.value && s.value ? ${field}) steps;
    in
    if carrying == [ ] then null else (head carrying).value.${field};

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
      steps = statementSteps realise key parts;
      statedRealiser = fieldOf steps "realiser";
      realiser = if statedRealiser == null then defaultRealiser else statedRealiser;
      known = elem realiser realisers;
      profile = fieldOf steps "profile";
      inDomain = elem profile imageReader.profileNames;
      record = machineRecordOf plan parts.machine;
      declared = record.address or null;
      address = if declared == "" then null else declared;
      entry = plan.${key};
      name = imageReader.nameOf parts;
      realised = entry.units or { } != { };
      named = realise ? ${key} || realise ? ${prefixOf parts};
      malformed = filter (s: !isAttrs s.value) steps;
      found = head malformed;

      # Each realiser is asked what it accepts rather than restated here, so the
      # sentence a row states and the sentence its raise states are one string.
      confinement = if realiser == "image" then profile else flakeletReader.confinement;
      emits = if realiser == "image" then imageReader.backend else flakeletReader.backend;
      runs = (entry.target or { }).serviceManager or null;
      hostPaths = imageReader.hostPaths { inherit key entry; };
      unassemblable =
        if realiser == "flakelet" then filter (p: !(flakeletReader.acceptsHostPath p)) hostPaths else [ ];
      refusedNames =
        if realiser == "flakelet" && !(flakeletReader.acceptsName name) then
          [
            {
              named = name;
              what = "the service name";
              rule = flakeletReader.nameRule;
            }
          ]
        else
          [ ];
      refusedUnits =
        if realiser == "flakelet" then
          map (file: {
            named = file;
            what = "the unit file";
            rule = flakeletReader.unitRule name;
          }) (filter (file: !(flakeletReader.acceptsUnit name file)) (unitFilesOf name (entry.units or { })))
        else
          [ ];
      denials =
        if confinement == null then
          [ ]
        else
          imageReader.denials {
            inherit entry;
            profile = confinement;
          };
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
      # The identity the endpoint records for the artifact, so a report can
      # compare a machine against a build. The plan entry key stays in the plan.
      digest = imageReader.versionFor { inherit key entry; };
      rows =
        optional (malformed != [ ]) (
          planner.error {
            id = "operator-statement-not-a-record";
            subject = key;
            message = "the realisation statement ${quote found.from} that entry ${quote key} is read by is ${
              if isString found.value then "the string ${quote found.value}" else "a ${typeOf found.value}"
            } rather than a record";
            evidence = "a statement is a record of the facts a realisation needs that no plan field carries, and a bare value carries none of them";
            resolution = "write `${found.from} = { realiser = <realiser>; };` in the deployment's `realise` argument";
          }
        )
        ++ (
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
            ++ optional (known && realiser == "image" && profile != null && !inDomain) (
              planner.error {
                id = "operator-image-profile-unknown";
                subject = key;
                message = "entry ${quote key} is stated to be realised as an image under the confinement profile ${shown profile}, and the profiles the realiser implements are ${quoteList imageReader.profileNames}";
                evidence = "a confinement profile is a build input no plan field records, so it is stated rather than chosen by the builder";
                resolution = "state one of ${quoteList imageReader.profileNames} as the `profile` of ${quote key}";
              }
            )
            ++ optional (address == null) (
              planner.warning {
                id = "operator-entry-machine-no-address";
                subject = key;
                message = "entry ${quote key} is placed on machine ${quote parts.machine}, and the plan's `machine:${parts.machine}` record declares no address";
                evidence = "an address is read by the step that dials a machine and by no step that builds one, so the record carries the absence and the artifact is built";
                resolution = "declare an `address` for ${quote parts.machine} in the deployment's machine registry before applying this entry";
              }
            )
            ++ map (
              p:
              planner.error {
                id = "operator-entry-path-not-assembled";
                subject = key;
                message = "entry ${quote key} is stated to be realised by ${quote realiser} and is shown the host path ${quote p.path} as a ${p.kind} assembled from ${quote p.from}, and ${flakeletReader.pathRule}";
                evidence = "a realisation statement decides which realiser meets the entry, and this one runs no step on the machine";
                resolution = "state ${quote "image"} for ${quote key}, or stop declaring the ${p.kind} the path is assembled from";
              }
            ) unassemblable
            ++ optional (known && runs != null && runs != emits) (
              planner.error {
                id = "operator-entry-service-manager-mismatch";
                subject = key;
                message = "entry ${quote key} is planned for machine ${quote parts.machine}, which runs ${shown runs}, and the stated realiser ${quote realiser} emits for ${quote emits}";
                evidence = "which service manager an artifact is emitted for is the realiser's, and which one a machine runs is the registry's";
                resolution = "place ${quote key} on a machine running ${quote emits}, or state a realiser that emits for ${shown runs}";
              }
            )
            ++ map (
              refused:
              planner.error {
                id = "operator-entry-name-refused";
                subject = key;
                message = "entry ${quote key} is stated to be realised by ${quote realiser}, whose endpoint refuses ${refused.what} ${quote refused.named}: ${refused.rule}";
                evidence = "the rule is the realiser's own, asked of it rather than restated, so this row and the realiser's refusal say one thing";
                resolution = "rename the instance or the service of ${quote key} so that ${refused.what} it derives is one the endpoint accepts";
              }
            ) (refusedNames ++ refusedUnits)
            ++ map (
              denial:
              planner.error {
                id = "operator-entry-access-denied";
                subject = key;
                message = "entry ${quote key} unit ${quote denial.unit} needs ${denial.access}, and the confinement profile ${quote confinement} the statement produced denies it";
                evidence = "a profile is stated and the accesses a unit needs are recorded in the plan, and the profile is not widened on the entry's behalf";
                resolution = "state a profile that allows ${denial.access} for ${quote key}, or stop needing it in unit ${quote denial.unit}";
              }
            ) denials
        );
    };

  # The plan omits a field whose value carries nothing, so a reading that indexes
  # one says what it did not find rather than ending the evaluation. `tryEval`
  # catches neither an abort nor a missing attribute, so a bare read here would
  # show an evaluation error where the table belongs.
  fieldRow =
    {
      key,
      field,
      at,
    }:
    planner.error {
      id = "operator-plan-field-missing";
      subject = key;
      message = "the plan record ${quote key} carries no ${quote field}${at}, and the reading of it needs one";
      evidence = "a field the plan prunes because its value was empty is an absence a reader cannot tell from a field the entry never had";
      resolution = "record ${quote field} on ${quote key} whether or not it carries anything, the way `delivery` and `files` are recorded";
    };

  planned =
    key: at: record: field: fallback:
    if record ? ${field} then
      {
        value = record.${field};
        rows = [ ];
      }
    else
      {
        value = fallback;
        rows = [ (fieldRow { inherit key field at; }) ];
      };

  readFile =
    key: name: file:
    let
      at = " on file ${quote name}";
      path = planned key at file "path" "";
      secrecy = planned key at file "secrecy" "";
    in
    {
      value = {
        path = path.value;
        secrecy = secrecy.value;
      };
      rows = path.rows ++ secrecy.rows;
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
      delivery = planned key "" entry "delivery" [ ];
      files = planned key "" entry "files" { };
      read = mapAttrs (readFile key) files.value;
    in
    {
      inherit key;
      delivery = delivery.value;
      files = mapAttrs (_: f: f.value) read;
      rows = delivery.rows ++ files.rows ++ concatLists (planner.util.mapAttrsToList (_: f: f.rows) read);
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

      addressable = uniqueStrings (placedKeys ++ map (key: prefixOf (parseKey key)) placedKeys);

      statementRows =
        map
          (
            stated:
            planner.error {
              id = "operator-statement-names-nothing";
              subject = stated;
              message = "the realisation statement names ${quote stated}, and the keys the plan carries are ${quoteList (sortStrings addressable)}";
              evidence = "a statement is read by plan key, then by the `<instance>:<service>` prefix, then by `default`, so a key naming neither is a decision about no entry";
              resolution = "state ${quote stated} as one of ${quoteList (sortStrings addressable)}, or delete it from the deployment's `realise` argument";
            }
          )
          (
            filter (stated: stated != "default" && !(elem stated addressable)) (sortStrings (attrNames realise))
          );

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
        concatLists (map (key: entries.${key}.rows) placedKeys)
        ++ concatLists (map (key: values.${key}.rows) valueKeys)
        ++ shapeRows
        ++ statementRows
        ++ collisionRows entries;

      table = planner.mkTable (diagnostics ++ rows);

      refused = filter (r: r.severity == "error") table != [ ];

      manifest = {
        version = 1;
        inherit storeDir;
        entries = mapAttrs (
          _: entry:
          {
            inherit (entry)
              realiser
              profile
              machine
              address
              units
              ;
            key = entry.digest;
          }
          # An entry that declares no unit is realised into nothing, so its
          # record carries no path at all. A null path is a value the reading
          # side has to refuse; an absent one is the absence it means.
          // (if entry.artifact == null then { } else { path = entry.artifact; })
        ) entries;
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
