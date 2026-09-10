# Reading one placed plan entry as an image. Everything here is a pure function of
# the plan, and a fact the entry does not record is a refusal naming the entry and
# the field, never a default.
#
# These refusals raise, unlike the planner's rows. The planner must produce a plan
# for a deployment that has mistakes in it, while an image built from a fact nobody
# wrote is worse than no image. Every refusal here is a condition mkPlan reports
# too, so a caller that wants the row already has it.
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
    replaceStrings
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
  };

  backend = "systemd";

  fail = message: throw "planner image: ${message}";

  # <instance>:<service>@<machine>, split the way a plan key is read everywhere else.
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
          inherit (file) path secrecy deploy;
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
    }) (entry.configData or { });

  hostPathsOf =
    { name, entry }:
    map (f: {
      path = f.path;
      from = f.staged;
      kind = "configuration-file";
      inherit (f) mode;
      disposition = if f.source != null then "source" else "render";
    }) (configFilesOf name entry)
    ++ map (g: {
      path = g.path;
      from = g.path;
      kind = "generated-file";
      inherit (g) secrecy;
      disposition = g.inPlan;
    }) (filter (g: g.deploy && g.inPlan == reference) (generatedOf entry));

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
          }) (attrNames units)
        )
        (
          if elem "a host file only root may read" denies then
            filter (g: g.deploy && g.secrecy == "secret" && g.inPlan == reference) generated
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
    backend
    nameOf
    unitFileName
    timerFileName
    stagingOf
    stagedPath
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
    else if unprintable != [ ] then
      let
        first = builtins.head unprintable;
      in
      fail "entry ${quote key} unit ${quote first.unit} sets ${quote first.name} to a value containing a newline, which a unit file has no line to put"
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
