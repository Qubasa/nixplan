{ planner }:
let
  inherit (builtins)
    all
    attrNames
    concatLists
    elem
    filter
    isAttrs
    isBool
    isInt
    isList
    isString
    match
    sort
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
  };

  backend = "systemd";

  fail = message: throw "planner image: ${message}";

  parseKey =
    key:
    let
      m = match "([^:]+):([^@]+)@(.+)" key;
    in
    if m == null then
      fail "${quote key} is not a placed entry key of the form `<instance>:<service>@<machine>`"
    else
      {
        instance = builtins.elemAt m 0;
        service = builtins.elemAt m 1;
        machine = builtins.elemAt m 2;
      };

  nameOf = parts: "${parts.instance}-${parts.service}";

  versionOf =
    record:
    let
      m = match "sha256-([0-9a-f]+)" (shortHash (builtins.toJSON record));
    in
    if m == null then
      fail "the digest of ${quote record.name} is not a `sha256-<hex>` value"
    else
      builtins.head m;

  required =
    key: entry: field:
    if entry ? ${field} then
      entry.${field}
    else
      fail "entry ${quote key} records no ${quote field}, and it is not inferable from anything else the plan carries";

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

  stagingOf = name: "/run/portable-planner/${name}";

  stagedPath = name: path: "${stagingOf name}/files${path}";

  reference = "reference";
in
rec {
  inherit
    profiles
    profileNames
    systemdDirectives
    backend
    unitFileName
    timerFileName
    stagingOf
    stagedPath
    ;

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
          fail "the plan has no entry ${quote key}; it has ${quoteList (sortStrings (attrNames plan))}";

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
          fail "entry ${quote key} records a `target` with no platform record, so there is no platform to build for";

      serviceManager =
        if target ? serviceManager && isString target.serviceManager then
          target.serviceManager
        else
          fail "entry ${quote key} records a `target` with no `serviceManager`";

      profileRecord =
        if profiles ? ${profile} then
          profiles.${profile}
        else
          fail "confinement profile ${quote profile} is not one of ${quoteList profileNames}; the profile is stated rather than inferred";

      generated = concatLists (
        mapAttrsToList (
          gen: g:
          mapAttrsToList (fname: file: {
            inherit gen fname;
            inherit (file) path secrecy;
            inPlan = file.inPlan;
            present = !(file ? bytes);
          }) g.files
        ) (entry.vars or { })
      );

      configFiles = mapAttrsToList (path: file: {
        inherit path;
        inherit (file) mode reload computed;
        source = file.source or null;
        render = file.render or null;
        staged = stagedPath name path;
      }) (entry.configData or { });

      referencePaths = uniqueStrings (
        map (g: g.path) (filter (g: g.inPlan == reference) generated)
        ++ concatLists (
          map (f: if f.render == null then [ ] else map (i: i.ref) (filter (i: i ? ref) f.render)) configFiles
        )
      );

      hostPaths =
        map (f: {
          path = f.path;
          from = f.staged;
          kind = "configuration-file";
          inherit (f) mode;
          disposition = if f.source != null then "source" else "render";
        }) configFiles
        ++ map (g: {
          path = g.path;
          from = g.path;
          kind = "generated-file";
          inherit (g) secrecy;
          disposition = g.inPlan;
        }) (filter (g: g.inPlan == reference) generated);

      version = versionOf {
        inherit
          name
          units
          closure
          storeDir
          serviceManager
          hostPaths
          ;
        inherit (parts) instance service machine;
        platform = system;
      };

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

          references = filter (r: elem r (attrNames unit)) [
            "after"
            "requires"
          ];
        in
        if missing != [ ] then
          fail "entry ${quote key} unit ${quote unitName} names ${quote (builtins.head (sortStrings missing))} and the entry's declared closure roots do not contain it"
        else if foreignBackends != [ ] then
          fail "entry ${quote key} unit ${quote unitName} records extension fields for backend ${quote (builtins.head (sortStrings foreignBackends))}, and this builder renders ${quote backend}"
        else if unknownFields != [ ] then
          fail "entry ${quote key} unit ${quote unitName} records extension field ${quote (builtins.head (sortStrings unknownFields))}, which this builder has no rendering for"
        else if unspellable != [ ] then
          fail "entry ${quote key} unit ${quote unitName} records extension field ${quote (builtins.head (sortStrings unspellable))} with a value this builder cannot spell as a directive"
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

      needsStaticUser = filter (u: units.${u} ? user) (attrNames units);
      needsRootOnlyFile = filter (g: g.secrecy == "secret") (filter (g: g.inPlan == reference) generated);

      denied =
        map (u: {
          unit = u;
          access = "a static host user";
        }) (if elem "a static host user" profileRecord.denies then needsStaticUser else [ ])
        ++ concatLists (
          map (
            g:
            map (u: {
              unit = u;
              access = "a host file only root may read";
              inherit (g) path;
            }) (attrNames units)
          ) (if elem "a host file only root may read" profileRecord.denies then needsRootOnlyFile else [ ])
        );
    in
    if !(isAttrs units) || units == { } then
      fail "entry ${quote key} records no unit, so there is nothing to attach"
    else if serviceManager != backend then
      fail "entry ${quote key} is planned for a machine running ${quote serviceManager}, and this builder emits images for ${quote backend}"
    else if rootsOutsideTheStore != [ ] then
      fail "entry ${quote key} declares closure root ${quote (builtins.head rootsOutsideTheStore)}, which is not a path under the store directory ${quote storeDir} the plan records"
    else if rootsThatAreReferences != [ ] then
      fail "entry ${quote key} declares closure root ${quote (builtins.head rootsThatAreReferences)}, which the plan records as a reference: its bytes reach the units from the host and never through an image"
    else if denied != [ ] then
      let
        first = builtins.head denied;
      in
      fail "entry ${quote key} unit ${quote first.unit} needs ${first.access}, and the stated confinement profile ${quote profile} denies it; the profile is not widened on the entry's behalf"
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

      environment = map (k: "Environment=${k}=${unit.env.${k}}") (
        sortStrings (attrNames (unit.env or { }))
      );

      binds = map (p: "BindReadOnlyPaths=${p.from}:${p.path}") (
        sort (a: b: a.path < b.path) image.hostPaths
      );

      extensionLines = map (f: "${u.directives.${f}.directive}=${u.directives.${f}.value}") (
        sortStrings (attrNames u.directives)
      );
    in
    builtins.concatStringsSep "\n" (
      [
        "[Unit]"
        "Description=${image.instance}:${image.service} ${unitName}"
      ]
      ++ optional (unit ? after) (map (r: "After=${prefixed r}") unit.after)
      ++ optional (unit ? requires) (map (r: "Requires=${prefixed r}") unit.requires)
      ++ [
        ""
        "[Service]"
        "ExecStart=${unit.command}"
      ]
      ++ optional (unit ? stopCommand) [ "ExecStop=${unit.stopCommand}" ]
      ++ optional (unit ? reloadCommand) [ "ExecReload=${unit.reloadCommand}" ]
      ++ optional (unit.oneShot or false) [ "Type=oneshot" ]
      ++ optional (unit ? remainAfterExit) [ "RemainAfterExit=${spell unit.remainAfterExit}" ]
      ++ optional (unit ? timeout) [ "TimeoutStartSec=${unit.timeout}" ]
      ++ optional (unit ? user) [ "User=${unit.user}" ]
      ++ environment
      ++ binds
      ++ extensionLines
    )
    + "\n";

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
