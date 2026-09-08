# Reading one placed plan entry as an image.
#
# Everything here is a pure function of the plan: the units to render, the
# extension fields to render, the closure roots to populate, the store
# directory to populate them under, the target to build for, the configuration
# files to show and the generated files to expect. A fact the entry does not
# record is a refusal naming the entry and the field, never a default.
#
# The refusals raise. That is the difference between this half and the planner:
# the planner returns a row because it must produce a plan for a deployment
# that has mistakes in it, and an image built from a fact nobody wrote is worse
# than no image. A caller wanting the row already has one - every refusal here
# is a condition `mkPlan` also reports.
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

  # The systemd portable profiles, by what each one denies an entry. Read out of
  # systemd's own profile drop-ins (`/usr/lib/systemd/portable/profile/<name>/service.conf`):
  # `default`, `nonetwork` and `strict` all carry `DynamicUser=yes` and
  # `PrivateUsers=yes`; `trusted` carries neither.
  #
  # An access is named by what the entry needs, so a refusal reads as a
  # sentence about the deployment rather than about a directive.
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

  # The systemd directive each extension field renders as, and how its value is
  # spelled. A field absent from this table fails the build: an extension
  # exists to add a field, so dropping one silently would make the extension a
  # comment.
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

  # A backend this builder renders. Everything else is a refusal rather than a
  # dropped field.
  backend = "systemd";

  fail = message: throw "planner image: ${message}";

  # `<instance>:<service>@<machine>` split at the last `@`, the way a plan key
  # is read everywhere else.
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

  # The image's own name, and therefore every unit file's prefix. Two entries
  # of one instance on one machine differ in their service, which is what makes
  # the prefix collision-free by construction rather than by convention.
  nameOf = parts: "${parts.instance}-${parts.service}";

  # The image's version is a digest of what the image contains: the identity it
  # is stamped with, the unit records its files are rendered from, the closure
  # those files resolve inside, the store directory they resolve under, and the
  # host paths they are shown.
  #
  # Deliberately not the entry's key. A key changes when a configuration file's
  # content hash changes, and that content never enters the image, so keying the
  # image on it would rename - and so rebuild - bytes that are equal. Every fact
  # hashed here is a key input, so an entry whose key is unchanged has an
  # unchanged version too.
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

  # A value's systemd spelling. A list is space-joined because every directive
  # in the table above that takes one is space-separated.
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

  # A configuration file is shown from the host: the staging copy is the file
  # the host assembles, and the mount point is the path the entry recorded.
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

  # One placed entry, read. Every field a builder spends is named here, and the
  # reading raises rather than defaulting when the plan does not carry one.
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

      # The generated files the entry expects, at the paths the plan fixed.
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

      # The configuration files the entry records, each with the disposition
      # the host assembles it from.
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

      # Every host path the image is shown, and why. The description names
      # these and nothing else, so it cannot name a path the entry does not
      # imply.
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

      # What the image is made of, and so what its name is a digest of.
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

      # Everything the entry mentions, so the declared roots can be checked
      # against it the way the planner checks them.
      mentions = unit: uniqueStrings (storePathsDeep storeDir (removeAttrs unit [ "extends" ]));

      undeclared = unit: subtractList (mentions unit) closure;

      # A root is a path under the store directory the plan names, by the same
      # grammar the planner recognises one with: the recogniser returns the
      # root itself for a root and nothing for anything else.
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

  # One unit file's text. Only the fields the entry recorded are expressed, so
  # a reader can tell what the deployment asked for from the file alone, and
  # the extension fields are rendered beside them under the same section.
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

  # A scheduled unit is a timer beside the service, both carrying the image's
  # prefix, because a schedule is a trigger and not a property of the service
  # it starts.
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

  # What attaching this image does, as data: the units it contributes, the
  # profile it is attached under, the target it was built for and every host
  # path shown to it.
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
