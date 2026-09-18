# The whole reading of one deployment: which entries are built, which realiser
# builds each, what the result is addressed by, and every way the build is
# refused. Everything here is a pure function of the plan and the realisation
# statement, and it is total - a refusal is a row, and default.nix is what raises
# on one. The evaluating layer has no `pkgs`, so a unit suite can assert this
# file and never a built artifact.
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
    all
    attrNames
    concatLists
    elem
    filter
    groupBy
    head
    isAttrs
    isList
    isString
    length
    mapAttrs
    stringLength
    substring
    typeOf
    ;

  inherit (planner.util)
    indexBy
    optional
    quote
    quoteList
    sealedPathOf
    sortStrings
    subtractList
    uniqueStrings
    ;

  # The realisers there are, each under the name a statement spells. A reading
  # asks the one it resolves for the rules only that realiser knows, so a third
  # entry here is asked by existing and an unlisted name resolves to nothing.
  readers = {
    image = imageReader;
    flakelet = flakeletReader;
  };

  realisers = attrNames readers;

  defaultRealiser = "flakelet";

  # A plan key in a path would be legal and awful: `@` and `:` are the two
  # characters the key grammar splits on, so every consumer would quote them.
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

  # A member no placement kept records its settings and nothing a realisation
  # reads, and a placed entry records all three of these. The two are told apart
  # by that rather than by the text of the key, which is the one question an
  # unreadable key cannot answer.
  placedRecord = record: record ? target || record ? units || record ? closure;

  machineRecordOf =
    plan: machine:
    let
      record = plan."machine:${machine}" or { };
    in
    if shapeOf record == "machine" then record else { };

  # The key grammar is the shared reading's, read here rather than restated: the
  # total half of it is what a layer that may not raise asks.
  parseKey = imageReader.keyParts;

  prefixOf = parts: "${parts.instance}:${parts.service}";

  shown = value: if isString value then quote value else "a ${typeOf value}";

  # Every field is resolved down the same three steps: the plan key, then the
  # `<instance>:<service>` prefix, then `default`. Resolving per statement rather
  # than per field would leave a reader having to know which fields inherit.
  statementSteps =
    realise: key: parts:
    let
      stepOf = from: {
        inherit from;
        value = realise.${from} or null;
      };
    in
    filter (s: s.value != null) (
      map stepOf [
        key
        (prefixOf parts)
        "default"
      ]
    );

  fieldOf =
    steps: field:
    let
      carrying = filter (s: isAttrs s.value && s.value ? ${field}) steps;
    in
    if carrying == [ ] then null else (head carrying).value.${field};

  # The names are the shared reading's own derivation, read here rather than
  # derived a second time: a row about a unit file name and the refusal over the
  # same name ask one function. One entry spelling one name twice claims it once
  # here, because the per-machine index below is the question about two entries
  # and the same-entry case has a row and a sentence of its own.
  unitFilesOf = name: units: sortStrings (uniqueStrings (imageReader.unitFilesOf name units));

  readEntry =
    {
      plan,
      realise,
      index,
    }:
    key:
    let
      # Every row below is about this entry, so the subject is the reading's and
      # what a site states is the identifier and the sentences.
      row = said: planner.error (said // { subject = key; });

      parts = parseKey key;
      steps = statementSteps realise key parts;
      statedRealiser = fieldOf steps "realiser";
      realiser = if statedRealiser == null then defaultRealiser else statedRealiser;
      known = endpoint != null;
      profile = fieldOf steps "profile";
      inDomain = elem profile imageReader.profileNames;
      record = machineRecordOf plan parts.machine;
      declared = record.address or null;
      address = if declared == "" then null else declared;
      # The machine's own scope, read off the record the plan carries: a
      # system-scope machine states none, the field entering the record only
      # where it is `user`.
      scope = record.scope or "system";
      entry = plan.${key};
      name = imageReader.nameOf parts;
      realised = entry.units or { } != { };
      named = realise ? ${key} || realise ? ${prefixOf parts};
      malformed = filter (s: !isAttrs s.value) steps;
      found = head malformed;

      # Each realiser is asked what it accepts rather than restated here, so the
      # sentence a row states and the sentence its raise states are one string.
      # A statement that resolved to no realiser, or to an image and no profile
      # of the domain, produces no confinement, so nothing a realiser holds
      # about a profile is indexed with what the statement carried.
      confinement =
        if !known then
          null
        else if realiser == "image" then
          (if inDomain then profile else null)
        else
          flakeletReader.confinement;
      imposed = if confinement == null then "" else confinement;
      emits = if known then endpoint.backend else readers.${defaultRealiser}.backend;
      runs = (entry.target or { }).serviceManager or null;
      # The values this entry is shown, which is its own declaration's and the
      # ones its declared reads name, computed once here and handed to each of
      # the three entry points rather than walked again inside them.
      values = imageReader.valuesOf { inherit index key entry; };
      inherit (values) generated unaccounted;
      hostPaths = imageReader.hostPaths { inherit key entry generated; };
      recordFields = [
        "owner"
        "group"
        "mode"
      ];
      statesARecord = p: p.kind != "configuration-file" || all (f: isString p.${f}) recordFields;
      # A configuration file the planner refused for its mode is recorded with
      # none, and both comparisons below interpolate the record, so a path whose
      # record is not three strings is named here and reaches neither.
      unrecorded = concatLists (
        map (
          p:
          map (field: {
            inherit (p) path;
            inherit field;
            value = p.${field};
          }) (filter (f: !(isString p.${f})) recordFields)
        ) (filter (p: !(statesARecord p)) hostPaths)
      );
      recorded = filter statesARecord hostPaths;
      # A realiser that runs no step on the machine states which paths it can be
      # shown, and is recognised by publishing the two predicates rather than by
      # its name.
      statesShownPaths = known && endpoint ? acceptsHostPath;
      unassemblable =
        if statesShownPaths then filter (p: !(endpoint.acceptsHostPath p)) recorded else [ ];
      uninstallable =
        if statesShownPaths then
          filter (p: endpoint.acceptsHostPath p && !(endpoint.acceptsRecord p)) recorded
        else
          [ ];

      endpoint = if isString realiser then readers.${realiser} or null else null;
      refusedNames =
        if endpoint != null && !(endpoint.acceptsName name) then
          [
            {
              named = name;
              what = "the service name";
              rule = endpoint.nameRule;
            }
          ]
        else
          [ ];
      refusedUnits =
        if endpoint == null then
          [ ]
        else
          map (file: {
            named = file;
            what = "the unit file";
            rule = endpoint.unitRule name;
          }) (filter (file: !(endpoint.acceptsUnit name file)) (unitFilesOf name (entry.units or { })));
      # The entry's own probe file, against the files its own declared units
      # spell. Two entries deriving one file is the per-machine namespace's
      # question below; this one is one entry claiming one name twice, which
      # that row's sentence is not about.
      probeFile = imageReader.probeFileName name;
      probeTaken =
        if imageReader.probedUnits (entry.units or { }) == [ ] then
          [ ]
        else
          filter (unit: imageReader.unitFileName name unit == probeFile) (
            sortStrings (attrNames (entry.units or { }))
          );
      denials =
        if confinement == null then
          [ ]
        else
          imageReader.denials {
            inherit entry generated;
            profile = confinement;
          };

      # The directive table is the stated realiser's own, asked of it rather than
      # restated here, so a directive added to a builder is a field this row
      # stops naming with no edit in this file.
      directives = if known then endpoint.systemdDirectives else { };
      unrendered =
        if !known then
          [ ]
        else
          concatLists (
            map (
              unit:
              map (field: { inherit unit field; }) (
                subtractList (attrNames ((entry.units.${unit}.extends or { }).${emits} or { })) (
                  attrNames directives
                )
              )
            ) (attrNames (entry.units or { }))
          );
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
      digest = imageReader.versionFor {
        inherit key entry generated;
        profile = imposed;
      };
      rows =
        optional (malformed != [ ]) (row {
          id = "operator-statement-not-a-record";
          message = "the realisation statement ${quote found.from} that entry ${quote key} is read by is ${
            if isString found.value then "the string ${quote found.value}" else "a ${typeOf found.value}"
          } rather than a record";
          evidence = "a statement is a record of the facts a realisation needs that no plan field carries, and a bare value carries none of them";
          resolution = "write `${found.from} = { realiser = <realiser>; };` in the deployment's `realise` argument";
        })
        ++ map (
          r:
          row {
            id = "operator-plan-field-malformed";
            message = "the plan record ${quote key} records ${quote r.field} on configuration file ${quote r.path} as ${shown r.value}, and the reading of it needs a string";
            evidence = "a record the planner already refused is recorded incompletely, and every comparison this reading makes against it interpolates the three fields it states";
            resolution = "state ${quote r.field} on ${quote r.path} in the module, which is what the planner's own row about that file asks for";
          }
        ) unrecorded
        ++ (
          if !realised then
            optional named (row {
              id = "operator-entry-realises-nothing";
              message = "entry ${quote key} is stated to be realised by ${shown realiser} and declares no unit, so there is nothing to realise for it";
              evidence = "an entry whose whole contribution is an export runs nothing, and a realiser of it would produce an artifact with no unit to attach";
              resolution = "remove ${quote key} from the deployment's `realise` argument, or declare a unit for it";
            })
          else
            optional (!known) (row {
              id = "operator-realiser-unknown";
              message = "entry ${quote key} is stated to be realised by ${shown realiser}, and the realisers that exist are ${quoteList realisers}";
              evidence = "the realisation statement is read by plan key, then by the `<instance>:<service>` prefix, then by `default`";
              resolution = "state one of ${quoteList realisers} for ${quote key} in the deployment's `realise` argument";
            })
            ++ optional (known && realiser == "image" && profile == null) (row {
              id = "operator-image-profile-missing";
              message = "entry ${quote key} is stated to be realised as an image and its statement carries no ${quote "profile"}";
              evidence = "a confinement profile is a build input no plan field records, so it is stated rather than chosen by the builder";
              resolution = "add a `profile` to the `realise` statement of ${quote key}: one of ${quoteList imageReader.profileNames}";
            })
            ++ optional (known && realiser == "image" && profile != null && !inDomain) (row {
              id = "operator-image-profile-unknown";
              message = "entry ${quote key} is stated to be realised as an image under the confinement profile ${shown profile}, and the profiles the realiser implements are ${quoteList imageReader.profileNames}";
              evidence = "a confinement profile is a build input no plan field records, so it is stated rather than chosen by the builder";
              resolution = "state one of ${quoteList imageReader.profileNames} as the `profile` of ${quote key}";
            })
            ++ map (
              p:
              row {
                id = "operator-entry-path-not-assembled";
                message = "entry ${quote key} is stated to be realised by ${quote realiser} and is shown the host path ${quote p.path}, whose recipe reads ${quote (p.needs or p.from)}, and ${endpoint.pathRule}";
                evidence = "a realisation statement decides which realiser meets the entry, and this one runs no step on the machine";
                resolution = "state ${quote "image"} for ${quote key}, or stop declaring the ${p.kind} the path is assembled from";
              }
            ) unassemblable
            ++ map (
              p:
              row {
                id = "operator-entry-path-not-installable";
                message = "entry ${quote key} is stated to be realised by ${quote realiser} and is shown the host path ${quote p.path}, whose declaration states ${quote (imageReader.recordOf p)}, and ${endpoint.recordRule}";
                evidence = "a realisation statement decides which realiser meets the entry, and this one binds a store object rather than installing a file on the machine";
                resolution = "state ${quote (imageReader.recordOf imageReader.storeRecord)} on ${quote p.path} in the module, or state ${quote "image"} for ${quote key}";
              }
            ) uninstallable
            ++ map (
              f:
              row {
                id = "operator-entry-extension-field-unrendered";
                message = "entry ${quote key} unit ${quote f.unit} records the ${quote emits} extension field ${quote f.field}, and the stated realiser ${quote realiser} renders no directive for it";
                evidence = "an extension declares the fields it accepts and the library accepts them, and which of them reach a unit file is the realiser's own directive table, asked of it rather than restated here";
                resolution = "drop ${quote f.field} from the extension the unit applies in the module, or state a realiser whose table carries it";
              }
            ) unrendered
            ++ optional (known && runs != null && runs != emits) (row {
              id = "operator-entry-service-manager-mismatch";
              message = "entry ${quote key} is planned for machine ${quote parts.machine}, which runs ${shown runs}, and the stated realiser ${quote realiser} emits for ${quote emits}";
              evidence = "which service manager an artifact is emitted for is the realiser's, and which one a machine runs is the registry's";
              resolution = "place ${quote key} on a machine running ${quote emits}, or state a realiser that emits for ${shown runs}";
            })
            ++ optional (known && !(elem scope endpoint.scopes)) (row {
              id = "operator-entry-scope-unsupported";
              message = "entry ${quote key} is planned for machine ${quote parts.machine}, which is deployed in the ${quote scope} scope, and the stated realiser ${quote realiser} realises ${quoteList endpoint.scopes}";
              evidence = "which scopes a realiser can realise is the realiser's own statement, asked of it rather than restated here, so a scope it does not publish is an artifact the machine would never run";
              resolution = "state a realiser whose scopes carry ${quote scope} for ${quote key}, or place it on a machine whose ${quote "scope"} is one of ${quoteList endpoint.scopes}";
            })
            ++ map (
              refused:
              row {
                id = "operator-entry-name-refused";
                message = "entry ${quote key} is stated to be realised by ${quote realiser}, whose endpoint refuses ${refused.what} ${quote refused.named}: ${refused.rule}";
                evidence = "the rule is the realiser's own, asked of it rather than restated, so this row and the realiser's refusal say one thing";
                resolution = "rename the instance or the service of ${quote key} so that ${refused.what} it derives is one the endpoint accepts";
              }
            ) (refusedNames ++ refusedUnits)
            ++ map (
              unit:
              row {
                id = "operator-entry-probe-unit-file-taken";
                message = "entry ${quote key} declares a probe and declares unit ${quote unit}, whose unit file is the ${quote probeFile} the probe itself derives";
                evidence = "a probed entry derives one unit file off its own service name, and a declared unit spelling it would have the two render into one file";
                resolution = "rename unit ${quote unit} of ${quote key}, or move the probe off ${quote key}";
              }
            ) probeTaken
            ++ map (
              denial:
              row {
                id = "operator-entry-access-denied";
                message = "entry ${quote key} unit ${quote denial.unit} needs ${denial.access}${
                  if denial ? path then
                    " at ${quote denial.path}, recorded ${quote denial.record} and read by ${quote denial.account},"
                  else
                    ","
                } and the confinement profile ${quote confinement} the statement produced denies it";
                evidence = "a profile is stated and the accesses a unit needs are recorded in the plan, and the profile is not widened on the entry's behalf";
                resolution = "state a profile that allows ${denial.access} for ${quote key}, or stop needing it in unit ${quote denial.unit}";
              }
            ) denials
            ++ map (
              claim:
              row {
                id = "operator-entry-value-unaccounted";
                message = "entry ${quote key} declares a read at ${quote claim.slot} naming the generated value ${quote claim.path}, and no value record of this plan accounts for bytes delivered to machine ${quote parts.machine} at it";
                evidence = "a value's delivery set is derived from the reads that name it, so a read naming a value this plan delivers nowhere near the reading entry is a plan whose records disagree with each other";
                resolution = "inspect the value entry that declares ${quote claim.path} and the placements of ${quote key}, and replan: a path a unit is shown with no bytes behind it is a unit that fails naming neither the value nor the declaration";
              }
            ) unaccounted
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

  # The fields a delivered file's record owes the command, in the order a row
  # about one is printed: the secrecy the report reads and the four the write
  # reads.
  fileFields = [
    "path"
    "secrecy"
    "owner"
    "group"
    "mode"
  ];

  readFile =
    key: name: file:
    let
      at = " on file ${quote name}";
      read = map (field: { inherit field; } // planned key at file field "") fileFields;
      record = indexBy (f: f.field) (f: f.value) read;
    in
    {
      value = record // {
        # The sealed copy's path, derived here rather than read off the plan: it
        # is a function of the runtime path, and a field on `fileRecord` would
        # re-key every generated value in every deployment for a path the
        # record already carries. A file whose `path` is not one is refused by
        # the command that reads this record, so none is published for it.
        sealed = if isString record.path && record.path != "" then sealedPathOf record.path else "";
      };
      rows = concatLists (map (f: f.rows) read);
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

  # The unit the machine-scoped oneshot is installed as, one hyphen wide. That
  # width is what keeps it outside the namespace an entry can spell: every unit
  # file a realiser derives is `<instance>-<service>-<unit>.service`, which
  # carries at least two hyphens outside its components. The disjointness is a
  # property of those derivations rather than a row, because a collision nobody
  # can earn is a row nobody can test.
  unsealUnit = "planner-unseal.service";

  # Whether an entry's own record names a generated value's path at any depth of
  # its units or its configuration files. The library's own recogniser, asked of
  # the two records `imageReader.hostPaths` is asked of, so a declared read and
  # an owner naming its own generator's file are covered by one rule, and an
  # entry that opens no value is ordered behind nothing.
  opensAValue =
    entry:
    planner.util.varsPathsDeep {
      units = entry.units or { };
      configData = entry.configData or { };
    } != [ ];

  # The per-machine half of the reading, beside the per-entry one: what a
  # machine's own boot-time restore needs, which is the files delivered there,
  # the scope whose manager runs it and the units it has to precede. A value's
  # machine need run no entry, so the machines are the delivery sets' and never
  # the placements'; the recipient and the scope are read with `machineRecordOf`
  # the way an entry's address is. A machine in a delivery set that states no
  # recipient is a warning the planner already produced, so this states the fact
  # and adds no row of its own - and the record carries the recipient nowhere,
  # so a rotation leaves every field of it equal.
  readMachine =
    {
      plan,
      values,
      entries,
    }:
    machine:
    let
      record = machineRecordOf plan machine;
      declared = record.sealRecipient or null;
      seals = isString declared && declared != "";

      # A file whose record is not five non-empty strings is left out: every
      # step of a restore interpolates the record, and the command that reads
      # this record refuses such a file before any of it runs.
      stated = f: all (field: isString f.${field} && f.${field} != "") fileFields;

      receives =
        key: elem machine (if isList values.${key}.delivery then values.${key}.delivery else [ ]);

      # In plan key order and then by file name, which is the order a restore
      # walks them in.
      files = filter stated (
        concatLists (
          map (key: map (name: values.${key}.files.${name}) (sortStrings (attrNames values.${key}.files))) (
            filter receives (sortStrings (attrNames values))
          )
        )
      );

      before = sortStrings (
        uniqueStrings (
          concatLists (
            map (key: entries.${key}.units) (
              filter (key: entries.${key}.machine == machine && opensAValue plan.${key}) (
                sortStrings (attrNames entries)
              )
            )
          )
        )
      );
    in
    {
      inherit machine files before;
      # The machine's own scope, read off the record the plan carries: a
      # system-scope machine states none.
      scope = record.scope or "system";
      sealed = seals;
      unit = unsealUnit;
      artifact = if seals then "machines/${machine}" else null;
    };

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

  # Every unit file name the realisers derive, indexed per machine: two members
  # whose names and unit names differ can spell one file, and both realisers
  # spend these names, which is why the index is here and not in either of them.
  unitFileRows =
    entries:
    let
      claims = concatLists (
        map (
          key:
          map (file: {
            inherit key file;
            inherit (entries.${key}) machine;
          }) entries.${key}.units
        ) (sortStrings (attrNames entries))
      );
      buckets =
        of: claimants:
        let
          grouped = groupBy of claimants;
        in
        map (name: grouped.${name}) (attrNames grouped);
    in
    concatLists (
      map (
        onMachine:
        concatLists (
          map (
            spending:
            optional (length spending > 1) (
              planner.error {
                id = "operator-entry-unit-file-collision";
                subject = (head spending).key;
                message = "entries ${
                  quoteList (map (c: c.key) spending)
                } all derive the unit file ${quote (head spending).file} on machine ${quote (head spending).machine}";
                evidence = "a realiser derives a unit file name from the instance, the member and the unit name, so the second entry's file replaces the first on the machine and one entry runs the other's unit";
                resolution = "rename one of the members, or the unit inside it, so that the unit files of machine ${quote (head spending).machine} name one entry each";
              }
            )
          ) (buckets (c: c.file) onMachine)
        )
      ) (buckets (c: c.machine) claims)
    );

  # The statement of which entry coordinates a mesh, read the way the
  # realisation statement is: a fact stated beside the deployment and inferred
  # from nothing at all. Recognising a coordination server by a module's
  # identity, by a package in a closure or by the text of a plan key would be
  # the first name-matching reading in this tree.
  #
  # Four fields, each naming something the plan already carries: the entry that
  # runs the server, the generated value that is its join credential, and the
  # two store objects a verb spends - the program and the configuration it is
  # handed - each by the name the module that rendered it publishes. The names
  # are resolved here against that entry's own closure, so what the record
  # publishes is a path, a command reproduces no rule of a module's, and a
  # statement naming an object the entry does not carry is a row rather than a
  # step that fails on the machine.
  storeRootName =
    storeDir: path:
    let
      hashed = "${storeDir}/";
      prefix = stringLength hashed + 33;
    in
    if planner.util.storePathsIn storeDir path == [ path ] && stringLength path > prefix then
      substring prefix (stringLength path) path
    else
      null;

  coordinationOf =
    {
      plan,
      coordinate,
      storeDir,
      placedKeys,
      valueKeys,
    }:
    let
      statedRecord = if isAttrs coordinate then coordinate else { };
      stated =
        field:
        let
          value = statedRecord.${field} or null;
        in
        if isString value && value != "" then value else null;

      entry = stated "entry";
      credential = stated "credential";

      # A statement naming an entry names the key that row is about. One whose
      # entry is not a name at all has no key to name, so the subject is the
      # statement itself, spelled the way a subject is spelled.
      subject = if entry == null then "coordinate:statement" else entry;

      namesNothing =
        {
          field,
          candidates,
          kind,
        }:
        optional (stated field == null || !(elem (stated field) candidates)) (
          planner.error {
            id = "operator-coordination-names-nothing";
            inherit subject;
            message = "the coordination statement names ${
              shown (statedRecord.${field} or null)
            } as its ${field}, and the ${kind} the plan carries are ${quoteList (sortStrings candidates)}";
            evidence = "a coordination statement is read by plan key the way a realisation statement is, so a field naming no record of the kind it is about is a decision about nothing";
            resolution = "state one of ${quoteList (sortStrings candidates)} as ${quote field} in the `coordinate` argument of the deployment, or delete the statement";
          }
        );

      closure = if entry == null then [ ] else (plan.${entry}.closure or [ ]);

      resolved =
        field:
        let
          name = stated field;
          held = filter (path: storeRootName storeDir path == name) (filter isString closure);
        in
        if name == null || length held != 1 then null else head held;

      unresolved =
        field:
        optional (resolved field == null) (
          planner.error {
            id = "operator-coordination-object-unheld";
            inherit subject;
            message = "the coordination statement names ${
              shown (statedRecord.${field} or null)
            } as its ${field}, and the closure of ${quote subject} carries ${
              quoteList (
                sortStrings (filter (n: n != null) (map (storeRootName storeDir) (filter isString closure)))
              )
            }";
            evidence = "a verb runs a program out of the entry's own closure, so an object the entry does not carry is one the copy never put on the machine";
            resolution = "declare the object named ${quote field} among the `closure` roots of the entry ${quote subject} declares, and state the name its module publishes";
          }
        );

      entryRows = namesNothing {
        field = "entry";
        candidates = placedKeys;
        kind = "placed entries";
      };

      credentialRows = namesNothing {
        field = "credential";
        candidates = valueKeys;
        kind = "generated values";
      };

      # The objects are resolved against the entry the statement named, so a
      # statement whose entry names nothing earns that row alone: two rows about
      # one mistake would name the closure of no entry.
      objectRows = if entryRows != [ ] then [ ] else unresolved "program" ++ unresolved "configuration";

      # A deployment that places no coordination server states nothing, and an
      # unstated statement is no statement: it earns no row here and no record
      # below, and every verb refuses on that absence naming what to add.
      rows = if statedRecord == { } then [ ] else entryRows ++ credentialRows ++ objectRows;

      # A field the reading could not resolve is published as the name that was
      # stated: the record stays the shape a reader decodes, and the rows above
      # have already made the deployment inapplicable.
      publish = field: if resolved field == null then orEmpty (stated field) else resolved field;

      orEmpty = value: if value == null then "" else value;
    in
    {
      inherit rows;
      # A statement nobody made is no record, and the verbs refuse on the
      # absence naming the statement to add. A statement that earned a row
      # publishes what it stated, the build being refused before a verb reads it.
      record =
        if statedRecord == { } then
          null
        else
          {
            entry = orEmpty entry;
            credential = orEmpty credential;
            program = publish "program";
            configuration = publish "configuration";
          };
    };
in
{
  inherit projected parseKey realisers;

  # plan is the plan artifact, realise the statement of how each entry is
  # realised, coordinate the statement of which entry coordinates a mesh,
  # storeDir the store the artifacts are copied out of, and diagnostics the
  # planner's own table. The table is an argument rather than a fact of this
  # file because a plan does not carry the rows that produced it, and refusing an
  # inapplicable deployment is a decision the reading owns.
  read =
    {
      plan,
      realise ? { },
      coordinate ? { },
      storeDir ? builtins.storeDir,
      diagnostics ? [ ],
    }:
    let
      keys = sortStrings (attrNames plan);

      placedKeys = filter (key: shapeOf plan.${key} == "entry" && parseKey key != null) keys;

      # A name the key grammar refuses is still planned, so a key this reading
      # cannot split is named rather than left out of the reading: every placed
      # entry of the plan is read or is the subject of a row.
      unreadableKeys = filter (
        key: shapeOf plan.${key} == "entry" && parseKey key == null && placedRecord plan.${key}
      ) keys;

      keyRows = map (
        key:
        planner.error {
          id = "operator-plan-key-unreadable";
          subject = key;
          message = "the plan record ${quote key} is a placed entry whose key does not split into an instance, a member and a machine, so no artifact of it can be named and no realiser chosen for it";
          evidence = "a plan key is `<instance>:<member>@<machine>`, and a name the key grammar refuses is recorded rather than dropped, so the record reaches this reading";
          resolution = "give the instance, the member and the machine of ${quote key} a name each in the deployment";
        }
      ) unreadableKeys;

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

      coordination = coordinationOf {
        inherit
          plan
          coordinate
          storeDir
          placedKeys
          valueKeys
          ;
      };

      # One index over the plan's value records, built once for the whole
      # reading: every entry's shown values are looked up in it, and a
      # `groupBy` inside each entry would walk the fleet's values per entry for
      # one relation.
      index = imageReader.valueIndex plan;

      entries = builtins.listToAttrs (
        map (key: {
          name = key;
          value = readEntry { inherit plan realise index; } key;
        }) placedKeys
      );

      values = builtins.listToAttrs (
        map (key: {
          name = key;
          value = readValue plan key;
        }) valueKeys
      );

      # The machines a delivered value reaches: the union of the delivery sets
      # and never the placements', because a value's machine need run no entry.
      receiving = sortStrings (
        uniqueStrings (
          concatLists (
            map (
              key: if isList values.${key}.delivery then filter isString values.${key}.delivery else [ ]
            ) valueKeys
          )
        )
      );

      machines = builtins.listToAttrs (
        map (machine: {
          name = machine;
          value = readMachine { inherit plan values entries; } machine;
        }) receiving
      );

      rows =
        concatLists (map (key: entries.${key}.rows) placedKeys)
        ++ concatLists (map (key: values.${key}.rows) valueKeys)
        ++ shapeRows
        ++ statementRows
        ++ coordination.rows
        ++ collisionRows entries
        ++ unitFileRows entries
        ++ keyRows;

      table = planner.mkTable (diagnostics ++ rows);

      refused = filter (r: r.severity == "error") table != [ ];

      manifest = {
        version = 3;
        inherit storeDir;
        # Each realiser's own statement of the scopes it can realise and of what
        # a machine's own answer names its holdings by, published rather than
        # restated: a reader of the record alone knows which scope a realiser's
        # steps may be addressed to, and which of the things a machine answers
        # with came from a deployment this planner applied. Every realiser the
        # reading was handed is in the table and not only the ones this
        # deployment's entries state, because the entry a build dropped may have
        # been the last one of its realiser and a table of the stated ones would
        # make exactly that holding unfindable.
        realisers = mapAttrs (_: endpoint: { inherit (endpoint) scopes holdings; }) readers;
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
        # The machines a delivered value reaches, one record each, whether or
        # not any of them seals: a reader of the old shape would have read a
        # missing table as a fleet whose machines seal nothing, which is the
        # silent failure the table exists to prevent, and that is why it is the
        # record's version that moved rather than an optional addition to the
        # old one. The recipient the seal is made to is not restated here - the
        # plan's own `machine:<name>` record carries it, and a second copy is a
        # second answer a stale build could disagree with. A machine that seals
        # nothing carries no path at all, the way an entry realised into
        # nothing does.
        machines = mapAttrs (
          _: m:
          {
            inherit (m) sealed scope;
          }
          // (if m.artifact == null then { } else { path = m.artifact; })
        ) machines;
      }
      # What a verb needs about the entry that coordinates a mesh, published the
      # way each realiser's own statements are: which entry it is, the value
      # that is its join credential, and the two objects a verb spends, resolved
      # to paths of that entry's own closure. A deployment that states no
      # coordination entry carries no key at all, and the verbs refuse on that
      # absence naming the statement to add.
      // (if coordination.record == null then { } else { coordination = coordination.record; });
    in
    {
      inherit
        entries
        values
        machines
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
