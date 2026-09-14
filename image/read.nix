# Reading one placed plan entry as an image. Everything here is a pure function of
# the plan, and a fact the entry does not record is a refusal naming the entry and
# the field, never a default.
#
# These refusals raise, unlike the planner's rows. The planner must produce a plan
# for a deployment that has mistakes in it, while an image built from a fact nobody
# wrote is worse than no image. Every refusal here is a condition an error row
# already reported: one from `mkPlan` where the fact is the plan's, and one from
# `operator/read.nix` where the fact is the realisation statement's, which no plan
# field carries and this file is never handed whole. A raise here is therefore the
# answer a caller reaching this file directly receives, and no path through the
# deployment build reaches one without the row having been produced first.
{
  planner,
  # How the caller turns bytes the plan already holds into a store object. This
  # reading realises nothing, so a configuration file assembled from literals is
  # written by whoever is building: the image puts it in its own closure and
  # flakelet puts it beside `units/`. A reading handed none answers about the
  # dispositions and renders nothing.
  assemble ? null,
}:
let
  inherit (builtins)
    all
    attrNames
    attrValues
    concatLists
    elem
    filter
    isAttrs
    isBool
    isInt
    isList
    isString
    match
    replaceStrings
    sort
    substring
    ;
  inherit (planner.util)
    mapAttrsToList
    quote
    quoteList
    shortHash
    sortStrings
    storePathsDeep
    storePathsIn
    subtractList
    uniqueStrings
    ;

  # systemd's portable profiles, by what each one denies an entry, read out of
  # systemd's own profile drop-ins. default, nonetwork and strict all carry
  # DynamicUser and PrivateUsers, trusted carries neither.
  profiles = {
    default.denies = [
      "a static host user"
      "a host file only root may read"
    ];
    nonetwork.denies = [
      "a static host user"
      "a host file only root may read"
    ];
    strict.denies = [
      "a static host user"
      "a host file only root may read"
    ];
    trusted.denies = [ ];
  };

  profileNames = attrNames profiles;

  # The systemd directive each extension field renders as. A field absent from this
  # table fails the build: an extension exists to add a field, so dropping one
  # silently would make the extension a comment.
  systemdDirectives = {
    protectSystem = "ProtectSystem";
    protectHome = "ProtectHome";
    privateTmp = "PrivateTmp";
    privateDevices = "PrivateDevices";
    noNewPrivileges = "NoNewPrivileges";
    stateDirectory = "StateDirectory";
    runtimeDirectory = "RuntimeDirectory";
    cacheDirectory = "CacheDirectory";
    readWritePaths = "ReadWritePaths";
    readOnlyPaths = "ReadOnlyPaths";
    ambientCapabilities = "AmbientCapabilities";
    capabilityBoundingSet = "CapabilityBoundingSet";
    systemCallFilter = "SystemCallFilter";
    memoryMax = "MemoryMax";
    tasksMax = "TasksMax";
    nice = "Nice";
    supplementaryGroups = "SupplementaryGroups";
  };

  # How every unit field this realiser renders reaches a unit file. A field the
  # plan can carry and this table does not name fails the build the way an
  # unknown extension field does: a vocabulary that grew and a realiser that did
  # not is the realiser's defect rather than the deployment's. `extends` is the
  # extension namespace and reaches a unit file through the table above.
  unitDirectives = {
    command = "ExecStart";
    stopCommand = "ExecStop";
    reloadCommand = "ExecReload";
    oneShot = "Type";
    remainAfterExit = "RemainAfterExit";
    timeout = "TimeoutStartSec";
    restart = "Restart";
    restartSec = "RestartSec";
    user = "User";
    env = "Environment";
    after = "After";
    requires = "Requires";
    schedule = "OnCalendar";
    extends = null;
  };

  backend = "systemd";

  # Every refusal this reading can make, and the row that reports the same
  # condition first. A refusal carries its account rather than its account
  # carrying a fragment of its message, so rewording one moves nothing.
  # `tests/unit/diagnostics.nix` crosses these against the rows the producing
  # layers build.
  accounts = {
    keyNotPlaced.id = "operator-plan-record-unclassified";
    digestMalformed = {
      id = null;
      because = "`util.shortHash` answers a `sha256-<hex>` value for every input, so no deployment reaches this";
    };
    fieldMissing.id = "machine-target-incomplete";
    entryAbsent = {
      id = null;
      because = "the reading enumerates the plan and asks for no key the plan does not carry";
    };
    targetNoPlatform.id = "machine-target-incomplete";
    targetNoServiceManager.id = "machine-target-incomplete";
    profileUnknown.id = "operator-image-profile-unknown";
    closureRootUndeclared.id = "closure-path-undeclared";
    extensionForeignBackend.id = "unit-extension-backend-mismatch";
    extensionFieldUnknown.id = "operator-entry-extension-field-unrendered";
    unitFieldUnrendered = {
      id = null;
      because = "the field is one the unit vocabulary carries and this builder's own directive table is missing it, which is a defect of the builder rather than of the deployment";
    };
    extensionValueUnspellable = {
      id = null;
      because = "the value passed the extension's own type and this builder renders no directive for its shape, which is again the builder's own table";
    };
    entryRealisesNothing.id = "operator-entry-realises-nothing";
    serviceManagerMismatch.id = "operator-entry-service-manager-mismatch";
    closureRootOutsideStore.id = "closure-root-outside-store";
    closureRootIsReference.id = "closure-root-is-delivered";
    accessDenied.id = "operator-entry-access-denied";
    unitEnvNewline.id = "unit-env-value-newline";
    hostPathUnassembled = {
      id = null;
      because = "a configuration file whose bytes the plan holds is written by whoever is building, and both builders hand this reading an assembly; a reading asked only about the plan answers about its dispositions and renders nothing";
    };
  };

  fail = _account: message: throw "planner image: ${message}";

  # <instance>:<service>@<machine>, split the way a plan key is read everywhere else.
  parseKey =
    key:
    let
      m = match "([^:]+):([^@]+)@(.+)" key;
    in
    if m == null then
      fail accounts.keyNotPlaced "${quote key} is not a placed entry key of the form `<instance>:<service>@<machine>`"
    else
      {
        instance = builtins.elemAt m 0;
        service = builtins.elemAt m 1;
        machine = builtins.elemAt m 2;
      };

  # The image's name, and so every unit file's prefix. Two entries of one instance
  # on one machine differ in their service, which makes the prefix collision-free
  # by construction rather than by convention.
  nameOf = parts: "${parts.instance}-${parts.service}";

  # A digest of what the image contains, deliberately not the entry key. A key moves
  # when a configuration file's content hash moves, and that content never enters
  # the image, so keying on it would rename and rebuild equal bytes.
  versionOf =
    record:
    let
      m = match "sha256-([0-9a-f]+)" (shortHash (builtins.toJSON record));
    in
    if m == null then
      fail accounts.digestMalformed "the digest of ${quote record.name} is not a `sha256-<hex>` value"
    else
      builtins.head m;

  required =
    key: entry: field:
    if entry ? ${field} then
      entry.${field}
    else
      fail accounts.fieldMissing "entry ${quote key} records no ${quote field}, and it is not inferable from anything else the plan carries";

  spell =
    value:
    if isString value then
      value
    else if isBool value then
      (if value then "yes" else "no")
    else if isInt value then
      toString value
    else if isList value && all isString value then
      builtins.concatStringsSep " " value
    else
      null;

  unitFileName = name: unit: "${name}-${unit}.service";
  timerFileName = name: unit: "${name}-${unit}.timer";

  # Where the host holds what it shows one image. One directory per image, so
  # detaching removes what attaching created and nothing else.
  stagingOf = name: "/run/portable-planner/${name}";

  stagedPath = name: path: "${stagingOf name}/files${path}";

  reference = "reference";

  # What an entry records about its own files, and what a profile denies of it.
  # Read here rather than inside the reading below, so a caller that must not
  # raise can ask the same functions the refusals are written over.
  generatedOf =
    entry:
    concatLists (
      mapAttrsToList (
        gen: g:
        mapAttrsToList (fname: file: {
          inherit gen fname;
          inherit (file)
            path
            secrecy
            deploy
            owner
            group
            mode
            ;
          inPlan = file.inPlan;
          present = !(file ? bytes);
        }) g.files
      ) (entry.vars or { })
    );

  configFilesOf =
    name: entry:
    mapAttrsToList (path: file: {
      inherit path;
      inherit (file) mode reload computed;
      source = file.source or null;
      render = file.render or null;
      staged = stagedPath name path;
      disposition = dispositionOf file;
    }) (entry.configData or { });

  # A projected file record carries `render = null` where the plan recorded a
  # source, so every reader of a recipe goes through this rather than `or [ ]`.
  renderOf = file: if (file.render or null) == null then [ ] else file.render;

  # When a configuration file's bytes exist. A source file is already a store
  # object and a render of nothing but literals is bytes the plan itself holds,
  # so both exist before a machine is dialled. A render carrying a reference
  # names a path on a machine, so its bytes exist only once that path is written,
  # and a file the planner recorded as not computed carries no recipe at all.
  dispositionOf =
    file:
    if !(file.computed or false) then
      reference
    else if (file.source or null) != null then
      "source"
    else if all (i: i ? text) (renderOf file) then
      "literal"
    else
      reference;

  literalsOf = file: builtins.concatStringsSep "" (map (i: i.text) (renderOf file));

  firstRefOf =
    file:
    let
      refs = filter (i: i ? ref) (renderOf file);
    in
    if refs == [ ] then null else (builtins.head refs).ref;

  assembledName =
    name: path:
    "${name}-config-${
      replaceStrings [ "/" "." " " ] [ "-" "-" "-" ] (
        builtins.substring 1 (builtins.stringLength path) path
      )
    }";

  # Where the bytes the bind reads come from. A store path arrives with the
  # entry's closure, a delivered file arrives at its own path, and only a recipe
  # naming a reference is staged by a step on the machine.
  fromOf =
    name: f:
    if f.disposition == "source" then
      f.source
    else if f.disposition == "literal" then
      (if assemble == null then null else assemble (assembledName name f.path) (literalsOf f))
    else
      f.staged;

  hostPathsOf =
    { name, entry }:
    map (
      f:
      {
        path = f.path;
        from = fromOf name f;
        kind = "configuration-file";
        inherit (f) mode disposition;
      }
      // (
        let
          needs = firstRefOf f;
        in
        if needs == null then { } else { inherit needs; }
      )
    ) (configFilesOf name entry)
    ++ map (g: {
      path = g.path;
      from = g.path;
      kind = "generated-file";
      inherit (g) secrecy;
      disposition = g.inPlan;
    }) (filter (g: g.deploy && g.inPlan == reference) (generatedOf entry));

  # Whether a confined unit may open a delivered file, from the record alone. A
  # read bit is the octal digit carrying 4, and a confined unit is never root, so
  # a unit declaring no account is admitted by nothing but the world bit.
  opens =
    digit:
    elem digit [
      "4"
      "5"
      "6"
      "7"
    ];

  groupsOf =
    unit:
    concatLists (
      map (
        fields:
        let
          declared = fields.supplementaryGroups or null;
        in
        if isList declared then
          filter isString declared
        else if isString declared then
          [ declared ]
        else
          [ ]
      ) (attrValues (unit.extends or { }))
    );

  admits =
    unit: g:
    let
      account = unit.user or null;
    in
    (account != null && account == g.owner && opens (substring 1 1 g.mode))
    || (elem g.group (groupsOf unit) && opens (substring 2 1 g.mode))
    || opens (substring 3 1 g.mode);

  denialsOf =
    {
      denies,
      units,
      generated,
    }:
    map
      (u: {
        unit = u;
        access = "a static host user";
      })
      (if elem "a static host user" denies then filter (u: units.${u} ? user) (attrNames units) else [ ])
    ++ concatLists (
      map
        (
          g:
          map (u: {
            unit = u;
            access = "a host file only root may read";
            inherit (g) path;
            # The record and the account, so the row and the refusal name the
            # facts a deployment can change rather than the file's secrecy.
            record = "${g.owner}:${g.group} at mode ${g.mode}";
            account = if units.${u} ? user then units.${u}.user else "a transient account";
          }) (filter (u: !(admits units.${u} g)) (attrNames units))
        )
        (
          if elem "a host file only root may read" denies then
            filter (g: g.deploy && g.inPlan == reference) generated
          else
            [ ]
        )
    );
in
rec {
  inherit
    profiles
    profileNames
    systemdDirectives
    unitDirectives
    dispositionOf
    literalsOf
    backend
    nameOf
    unitFileName
    timerFileName
    stagingOf
    stagedPath
    accounts
    ;

  # A caller that holds an entry and a stated profile, and may not raise, asks
  # these. An unknown profile answers no denial, because the statement that named
  # it is refused by the layer that read it.
  hostPaths =
    { key, entry }:
    hostPathsOf {
      name = nameOf (parseKey key);
      inherit entry;
    };

  denials =
    { entry, profile }:
    if !(profiles ? ${profile}) then
      [ ]
    else
      denialsOf {
        inherit (profiles.${profile}) denies;
        units = entry.units or { };
        generated = generatedOf entry;
      };

  # The digest the endpoint stores for an artifact, over the artifact's own
  # content and never over the plan key: a fact that moves a key without moving a
  # byte leaves this where it was.
  #
  # A shown path enters the digest by what its bytes are rather than by where a
  # builder put them: a file assembled from literals is described by the
  # literals, so two readings of one entry - one handed an assembly and one not -
  # answer the same digest, which is what lets `operator/read.nix` publish it.
  versionFor =
    { key, entry }:
    let
      parts = parseKey key;
      name = nameOf parts;
      target = entry.target or { };
      byPath = path: builtins.head (filter (f: f.path == path) (configFilesOf name entry));
    in
    versionOf {
      inherit name;
      units = entry.units or { };
      closure = entry.closure or [ ];
      storeDir = entry.storeDir or "";
      serviceManager = target.serviceManager or "";
      hostPaths =
        map
          (
            p:
            removeAttrs p [ "from" ]
            // (
              if p.kind == "configuration-file" && p.disposition == "literal" then
                { bytes = literalsOf (byPath p.path); }
              else
                { inherit (p) from; }
            )
          )
          (hostPathsOf {
            inherit name entry;
          });
      inherit (parts) instance service machine;
      platform = target.system or null;
    };

  read =
    {
      plan,
      key,
      profile,
    }:
    let
      entry =
        if plan ? ${key} then
          plan.${key}
        else
          fail accounts.entryAbsent "the plan has no entry ${quote key}; it has ${quoteList (sortStrings (attrNames plan))}";

      parts = parseKey key;
      name = nameOf parts;

      target = required key entry "target";
      storeDir = required key entry "storeDir";
      units = required key entry "units";
      closure = required key entry "closure";

      system =
        if target ? system && target.system ? system then
          target.system
        else
          fail accounts.targetNoPlatform "entry ${quote key} records a `target` with no platform record, so there is no platform to build for";

      serviceManager =
        if target ? serviceManager && isString target.serviceManager then
          target.serviceManager
        else
          fail accounts.targetNoServiceManager "entry ${quote key} records a `target` with no `serviceManager`";

      profileRecord =
        if profiles ? ${profile} then
          profiles.${profile}
        else
          fail accounts.profileUnknown "confinement profile ${quote profile} is not one of ${quoteList profileNames}; the profile is stated rather than inferred";

      generated = generatedOf entry;

      configFiles = configFilesOf name entry;

      referencePaths = uniqueStrings (
        map (g: g.path) (filter (g: g.inPlan == reference) generated)
        ++ concatLists (
          map (f: if f.render == null then [ ] else map (i: i.ref) (filter (i: i ? ref) f.render)) configFiles
        )
      );

      # A path is shown only where bytes arrive at it. An undeployed value is on
      # no machine, so a mount of its path would be a mount of nothing: the unit
      # then fails at NAMESPACE rather than at anything an operator can read.
      hostPaths = hostPathsOf { inherit name entry; };

      version = versionFor { inherit key entry; };

      mentions = unit: uniqueStrings (storePathsDeep storeDir (removeAttrs unit [ "extends" ]));

      undeclared = unit: subtractList (mentions unit) closure;

      rootsOutsideTheStore = filter (root: storePathsIn storeDir root != [ root ]) closure;

      rootsThatAreReferences = filter (root: elem root referencePaths) closure;

      readUnit =
        unitName: unit:
        let
          missing = undeclared unit;

          extends = unit.extends or { };
          foreignBackends = subtractList (attrNames extends) [ backend ];
          fields = extends.${backend} or { };
          unknownFields = subtractList (attrNames fields) (attrNames systemdDirectives);
          unspellable = filter (f: spell fields.${f} == null) (subtractList (attrNames fields) unknownFields);

          unrenderable = subtractList (attrNames unit) (attrNames unitDirectives);

          references = filter (r: elem r (attrNames unit)) [
            "after"
            "requires"
          ];
        in
        if missing != [ ] then
          fail accounts.closureRootUndeclared "entry ${quote key} unit ${quote unitName} names ${quote (builtins.head (sortStrings missing))} and the entry's declared closure roots do not contain it"
        else if foreignBackends != [ ] then
          fail accounts.extensionForeignBackend "entry ${quote key} unit ${quote unitName} records extension fields for backend ${quote (builtins.head (sortStrings foreignBackends))}, and this builder renders ${quote backend}"
        else if unknownFields != [ ] then
          fail accounts.extensionFieldUnknown "entry ${quote key} unit ${quote unitName} records extension field ${quote (builtins.head (sortStrings unknownFields))}, which this builder has no rendering for"
        else if unrenderable != [ ] then
          fail accounts.unitFieldUnrendered "entry ${quote key} unit ${quote unitName} records ${quote (builtins.head (sortStrings unrenderable))}, which the unit vocabulary carries and this builder's directive table does not name"
        else if unspellable != [ ] then
          fail accounts.extensionValueUnspellable "entry ${quote key} unit ${quote unitName} records extension field ${quote (builtins.head (sortStrings unspellable))} with a value this builder cannot spell as a directive"
        else
          {
            inherit unitName references;
            file = unitFileName name unitName;
            timer = if unit ? schedule then timerFileName name unitName else null;
            directives = builtins.mapAttrs (f: v: {
              directive = systemdDirectives.${f};
              value = spell v;
            }) fields;
            record = unit;
          };

      denied = denialsOf {
        inherit (profileRecord) denies;
        inherit units generated;
      };

      # A unit file is line-oriented, so a newline in a value is a fact the file
      # cannot carry. Spaces and quotes can be: they are escaped at render.
      unprintable = concatLists (
        map (
          u:
          map
            (k: {
              unit = u;
              name = k;
            })
            (
              filter (k: match ".*[\n\r].*" (units.${u}.env.${k} or "") != null) (
                attrNames (units.${u}.env or { })
              )
            )
        ) (attrNames units)
      );
    in
    if !(isAttrs units) || units == { } then
      fail accounts.entryRealisesNothing "entry ${quote key} records no unit, so there is nothing to attach"
    else if serviceManager != backend then
      fail accounts.serviceManagerMismatch "entry ${quote key} is planned for a machine running ${quote serviceManager}, and this builder emits images for ${quote backend}"
    else if rootsOutsideTheStore != [ ] then
      fail accounts.closureRootOutsideStore "entry ${quote key} declares closure root ${quote (builtins.head rootsOutsideTheStore)}, which is not a path under the store directory ${quote storeDir} the plan records"
    else if rootsThatAreReferences != [ ] then
      fail accounts.closureRootIsReference "entry ${quote key} declares closure root ${quote (builtins.head rootsThatAreReferences)}, which the plan records as a reference: its bytes reach the units from the host and never through an image"
    else if denied != [ ] then
      let
        first = builtins.head denied;
      in
      fail accounts.accessDenied "entry ${quote key} unit ${quote first.unit} needs ${first.access}${
        if first ? path then
          " at ${quote first.path}, recorded ${quote first.record} and read by ${quote first.account},"
        else
          ","
      } and the stated confinement profile ${quote profile} denies it; the profile is not widened on the entry's behalf"
    else if unprintable != [ ] then
      let
        first = builtins.head unprintable;
      in
      fail accounts.unitEnvNewline "entry ${quote key} unit ${quote first.unit} sets ${quote first.name} to a value containing a newline, which a unit file has no line to put"
    else
      {
        inherit
          key
          entry
          name
          version
          profile
          storeDir
          closure
          system
          serviceManager
          generated
          configFiles
          hostPaths
          referencePaths
          ;
        inherit (parts) instance service machine;
        staging = stagingOf name;
        units = builtins.mapAttrs readUnit units;
      };

  renderUnit =
    image: unitName:
    let
      u = image.units.${unitName};
      unit = u.record;
      prefixed = ref: "${image.name}-${ref}.service";

      optional = cond: lines: if cond then lines else [ ];

      # systemd splits an unquoted Environment= on whitespace, so a value with a
      # space in it becomes two assignments and the second is garbage.
      environment = map (
        k: "Environment=\"${k}=${replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ] unit.env.${k}}\""
      ) (sortStrings (attrNames (unit.env or { })));

      # Every shown path has to name bytes the machine holds. A literal recipe's
      # bytes are the builder's to write, so a reading handed no assembly cannot
      # render one at all.
      unassembled = filter (p: p.from == null) image.hostPaths;

      binds = map (p: "BindReadOnlyPaths=${p.from}:${p.path}") (
        sort (a: b: a.path < b.path) image.hostPaths
      );

      extensionLines = map (f: "${u.directives.${f}.directive}=${u.directives.${f}.value}") (
        sortStrings (attrNames u.directives)
      );
    in
    if unassembled != [ ] then
      fail accounts.hostPathUnassembled "entry ${quote image.key} is shown the host path ${quote (builtins.head unassembled).path} whose bytes this reading was handed no way to assemble"
    else
      builtins.concatStringsSep "\n" (
        [
          "[Unit]"
          "Description=${image.instance}:${image.service} ${unitName}"
        ]
        ++ optional (unit ? after) (map (r: "${unitDirectives.after}=${prefixed r}") unit.after)
        ++ optional (unit ? requires) (map (r: "${unitDirectives.requires}=${prefixed r}") unit.requires)
        ++ [
          ""
          "[Service]"
          "${unitDirectives.command}=${unit.command}"
        ]
        ++ optional (unit ? stopCommand) [ "${unitDirectives.stopCommand}=${unit.stopCommand}" ]
        ++ optional (unit ? reloadCommand) [ "${unitDirectives.reloadCommand}=${unit.reloadCommand}" ]
        ++ optional (unit.oneShot or false) [ "${unitDirectives.oneShot}=oneshot" ]
        ++ optional (unit ? remainAfterExit) [
          "${unitDirectives.remainAfterExit}=${spell unit.remainAfterExit}"
        ]
        ++ optional (unit ? timeout) [ "${unitDirectives.timeout}=${unit.timeout}" ]
        ++ optional (unit ? restart) [ "${unitDirectives.restart}=${unit.restart}" ]
        ++ optional (unit ? restartSec) [ "${unitDirectives.restartSec}=${unit.restartSec}" ]
        ++ optional (unit ? user) [ "${unitDirectives.user}=${unit.user}" ]
        ++ environment
        ++ binds
        ++ extensionLines
      )
      + "\n";

  # A scheduled unit becomes a timer beside the service, both carrying the image's
  # prefix, because a schedule is a trigger and not a property of the service.
  renderTimer =
    image: unitName:
    let
      unit = image.units.${unitName}.record;
    in
    builtins.concatStringsSep "\n" [
      "[Unit]"
      "Description=${image.instance}:${image.service} ${unitName} schedule"
      ""
      "[Timer]"
      "OnCalendar=${unit.schedule}"
      "Unit=${unitFileName image.name unitName}"
      ""
    ];

  attachment = image: {
    entry = image.key;
    image = "${image.name}_${image.version}.raw";
    inherit (image)
      name
      version
      profile
      storeDir
      closure
      staging
      ;
    target = {
      system = image.system.system;
      inherit (image) serviceManager;
    };
    units = sortStrings (
      map (u: u.file) (builtins.attrValues image.units)
      ++ map (u: u.timer) (filter (u: u.timer != null) (builtins.attrValues image.units))
    );
    hostPaths = sort (a: b: a.path < b.path) image.hostPaths;
    generated = sort (a: b: a.path < b.path) (
      map (g: {
        inherit (g) path secrecy;
        expected = if g.present then "present" else "absent";
      }) image.generated
    );
  };
}
