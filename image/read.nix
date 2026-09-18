# Reading one placed plan entry as an image. Everything here is a pure function of
# the plan, and a fact the entry does not record is a refusal naming the entry and
# the field, never a default. Those refusals raise, unlike the planner's rows, and
# each is a condition an error row already reported.
{
  planner,
  # How the caller turns bytes the plan already holds into a store object: this
  # reading realises nothing, so a file assembled from literals is written by
  # whoever is building. A reading handed none renders nothing.
  assemble ? null,
}:
let
  inherit (builtins)
    all
    any
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
    carriesLineBreak
    envNameAdmits
    escapeRegex
    mapAttrsToList
    oneLine
    quote
    quoteList
    shortHash
    sortStrings
    storePathsDeep
    storePathsIn
    stringsDeep
    subtractList
    unassignable
    uniqueStrings
    ;

  # systemd's portable profiles, by the statements of each drop-in this reading
  # reasons about. `DynamicUser=yes` is what imposes an account on a unit that
  # declares none, `ProtectHome=yes` closes a home the account owns, and
  # `PrivateUsers=yes` needs no privilege at all: default, nonetwork and strict
  # carry the three, trusted carries none.
  profileStatements = {
    default = [
      "DynamicUser=yes"
      "PrivateUsers=yes"
      "ProtectHome=yes"
    ];
    nonetwork = [
      "DynamicUser=yes"
      "PrivateUsers=yes"
      "ProtectHome=yes"
    ];
    strict = [
      "DynamicUser=yes"
      "PrivateUsers=yes"
      "ProtectHome=yes"
    ];
    trusted = [ ];
  };

  # The two statements upstream's user profiles drop, because neither is a thing
  # an account can be granted: a transient user and a home only root may close.
  droppedInUserScope = [
    "DynamicUser=yes"
    "ProtectHome=yes"
  ];

  # What a statement denies an entry. The denials are derived from the profile
  # the scope selects rather than stated per scope, so the table a user-scope
  # reading asks is this one read once more and never a second table beside it.
  deniedBy = {
    "DynamicUser=yes" = [
      "a static host user"
      "a host file only root may read"
    ];
    "PrivateUsers=yes" = [ ];
    "ProtectHome=yes" = [ ];
  };

  profilesFor =
    scope:
    builtins.mapAttrs (
      _: stated:
      let
        statements = if scope == "user" then subtractList stated droppedInUserScope else stated;
      in
      {
        inherit statements;
        denies = concatLists (map (s: deniedBy.${s}) statements);
      }
    ) profileStatements;

  profiles = profilesFor "system";

  scopeOf = entry: (entry.target or { }).scope or "system";

  profileNames = attrNames profileStatements;

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
  # plan can carry and this table does not name fails the build. `extends` is the
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
    stateDirectory = "StateDirectory";
    runtimeDirectory = "RuntimeDirectory";
    cacheDirectory = "CacheDirectory";
    stateDirectoryMode = "StateDirectoryMode";
    runtimeDirectoryMode = "RuntimeDirectoryMode";
    cacheDirectoryMode = "CacheDirectoryMode";
    # One directive with the polarity in the value, which is systemd's own
    # spelling of the negative: the planner states which condition holds.
    startIfPathPresent = "ConditionPathExists";
    startIfPathAbsent = "ConditionPathExists";
    # The two fields of a probe, which reach the derived probe unit's file and
    # never the probed unit's own: a probe is a job of its own, so its command
    # and its bound are that job's start command and start timeout.
    probe = "ExecStart";
    probeTimeout = "TimeoutStartSec";
    extends = null;
  };

  # The six directory fields, each rendered the same way, in the order the unit
  # file carries them. The table above is what fails the build for a vocabulary
  # field no directive names; this is the order the named ones are emitted in.
  directoryFields = [
    "cacheDirectory"
    "cacheDirectoryMode"
    "runtimeDirectory"
    "runtimeDirectoryMode"
    "stateDirectory"
    "stateDirectoryMode"
  ];

  backend = "systemd";

  # Every refusal this reading can make, and the row that reports the same
  # condition first, paired by the account a refusal carries.
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
    unitValueNewline.id = "unit-value-newline";
    envNameRefused.id = "unit-env-name-malformed";
    nameRefused.id = "operator-entry-name-refused";
    unitRefused.id = "operator-entry-name-refused";
    # The four ways a probe can be recorded that no honest rendering exists for,
    # each carrying the row the planner earns for the same condition: a bound
    # this builder invented, a bound with nothing to bound, a bound spelling
    # systemd's own absence of one, and two commands for one file.
    probeWithoutTimeout.id = "unit-probe-without-timeout";
    probeTimeoutWithoutProbe.id = "unit-probe-timeout-without-probe";
    probeTimeoutUnbounded.id = "unit-probe-timeout-unbounded";
    probeDeclaredTwice.id = "unit-probe-declared-twice";
    hostPathUnassembled = {
      id = null;
      because = "a configuration file whose bytes the plan holds is written by whoever is building, and both builders hand this reading an assembly; a reading asked only about the plan answers about its dispositions and renders nothing";
    };
    signingUnstated = {
      id = null;
      because = "the signing key of a user-scope image is an argument of the build and no plan records it, so nothing above a build invoked without one can have rowed about it";
    };
  };

  fail = _account: message: throw "planner image: ${message}";

  # <instance>:<service>@<machine>, split the way a plan key is read everywhere
  # else. The reading is total, so a layer that may not raise reads the same one
  # grammar rather than a second copy of it.
  keyParts =
    key:
    let
      m = match "([^:]+):([^@]+)@(.+)" key;
    in
    if m == null then
      null
    else
      {
        instance = builtins.elemAt m 0;
        service = builtins.elemAt m 1;
        machine = builtins.elemAt m 2;
      };

  parseKey =
    key:
    let
      parts = keyParts key;
    in
    if parts == null then
      fail accounts.keyNotPlaced "${quote key} is not a placed entry key of the form `<instance>:<service>@<machine>`"
    else
      parts;

  # The image's name, and so every unit file's prefix. Two entries of one instance
  # on one machine differ in their service, which makes the prefix collision-free
  # by construction rather than by convention.
  nameOf = parts: "${parts.instance}-${parts.service}";

  # What a machine's own listing names an image this realiser built by. The file
  # `attachment` composes is `<name><separator><digest>.raw`, so the separator
  # is bound here and spent there, and the digest's shape is read back off the
  # digest itself rather than written down a second time. Data and no pattern: a
  # nix pattern and a python one are two dialects of one rule, and the reader of
  # the record is python.
  nameSeparator = "_";

  digestAlphabet = "0123456789abcdef";

  holdings = {
    separator = nameSeparator;
    inherit digestAlphabet;
    digestLength = builtins.stringLength (versionOf {
      name = "the length a digest has";
    });
  };

  # A digest of what the image contains, deliberately not the entry key. A key moves
  # when a configuration file's content hash moves, and that content never enters
  # the image, so keying on it would rename and rebuild equal bytes.
  versionOf =
    record:
    let
      m = match "sha256-([${digestAlphabet}]+)" (shortHash (builtins.toJSON record));
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

  # The one file the endpoint's activation starts, named off the entry's own
  # prefix rather than off the probed unit: an entry is activated as one, so
  # whether it is serving is one question and one file.
  probeFileName = name: "${name}-health.service";

  probedUnits = units: filter (u: units.${u} ? probe) (attrNames units);

  # Every file one entry's units render to: a unit file each, a timer for every
  # scheduled one, and the derived probe unit where any unit records a probe.
  # `read` refuses a name outside the realiser's rule off this list and
  # `operator/read.nix` rows about the same names, so the two ask one derivation
  # rather than deriving the names twice. The probe half is one `any` over the
  # unit names, asked whether the entry is probed or not.
  unitFilesOf =
    name: units:
    map (unitFileName name) (attrNames units)
    ++ map (timerFileName name) (filter (u: units.${u} ? schedule) (attrNames units))
    ++ planner.util.optional (any (u: units.${u} ? probe) (attrNames units)) (probeFileName name);

  # The scopes this realiser realises, published beside the name and unit rules
  # so the reading crosses a stated realiser against a machine rather than
  # inferring from a name. The second one is realisable because a per-account
  # portabled exists and mountfsd mounts a signed image for it.
  scopes = [
    "system"
    "user"
  ];

  # This builder's own name rule, written as the sentence its refusal prints so
  # the rule and the message cannot drift apart.
  nameRule = "a derived name starts with an ASCII alphanumeric and carries only ASCII alphanumerics, `_`, `-` and `.` after it";

  acceptsName = name: match "[A-Za-z0-9][A-Za-z0-9_.-]*" name != null;

  # The unit half takes the prefix as given, because `acceptsName` is what
  # answers for it: a name outside the rule is then one sentence about one
  # declaration rather than one per file it would have been rendered into.
  unitRule =
    unitsOf:
    "a unit file name is ${quote "${unitsOf}-<unit>.service"} or ${quote "${unitsOf}-<unit>.timer"}, where the unit carries only ASCII alphanumerics, `_`, `-` and `.`";

  acceptsUnit =
    name: unit: match "${escapeRegex name}-[A-Za-z0-9_.-]+\\.(service|timer)" unit != null;

  # The two rules belong to the realiser that meets the entry and not to this
  # reading, which flakelet forces for the units and the digest too: a refusal
  # made under the image's grammar would name this builder for an entry nobody
  # stated as an image, and would state a rule its row does not.
  imageRules = {
    inherit
      nameRule
      acceptsName
      unitRule
      acceptsUnit
      ;
    nameRefused =
      { key, name }:
      fail accounts.nameRefused "entry ${quote key} derives the service name ${quote name}, which this builder refuses: ${nameRule}";
    unitRefused =
      {
        key,
        name,
        file,
      }:
      fail accounts.unitRefused "entry ${quote key} renders the unit file ${quote file}, which this builder refuses: ${unitRule name}";
  };

  # Where a manager of each scope reads an image's unit files. Extraction in
  # user mode reads the user unit directories alone, so a system-unit image
  # yields an account no matching unit at all rather than a refusal.
  unitDirectories = {
    system = "/etc/systemd/system";
    user = "/usr/lib/systemd/user";
  };

  # The three files a dissection reads beside an image to verify it, named off
  # the image's own name with the `.raw` suffix dropped, which is the rule
  # `RootHash=` and `RootHashSignature=` stand on: a hash tree, the root hash
  # of it, and a PKCS7 signature over that hash. Derived here so the builder
  # writing them and a reader looking for them cannot disagree.
  sidecarsOf =
    image:
    let
      base = if match "(.*)\\.raw" image != null then builtins.head (match "(.*)\\.raw" image) else image;
    in
    {
      verity = "${base}.verity";
      roothash = "${base}.roothash";
      signature = "${base}.roothash.p7s";
    };

  # What signs a user-scope image. The key is an argument of the build and a
  # fact of no plan, so the builder holds the condition and this reading states
  # the sentence, which is where every other refusal about an image lives.
  signatureOf =
    { key, signing }:
    if signing == null then
      fail accounts.signingUnstated "entry ${quote key} is placed on a user-scope machine, whose image is mounted under `image_policy_untrusted` and has to carry a dm-verity root hash signed by a certificate the machine holds, and this build was handed no `signing`: pass `signing = { privateKey = <pem>; certificate = <x509>; }`, which is an argument of the build and a fact of no plan"
    else
      { inherit (signing) privateKey certificate; };

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

  # The one record a store object carries. A bind shows the source's ownership and
  # mode, so a configuration file stating anything else is a file this realiser
  # installs on the host rather than binds.
  storeRecord = {
    owner = "root";
    group = "root";
    mode = "0444";
  };

  recordOf = f: "${f.owner}:${f.group} at mode ${f.mode}";

  carriedByStore =
    file:
    file.owner == storeRecord.owner && file.group == storeRecord.group && file.mode == storeRecord.mode;

  configRecordsOf =
    entry:
    mapAttrsToList (
      path: file:
      let
        disposition = dispositionOf file;
      in
      {
        inherit path disposition;
        inherit (file)
          mode
          owner
          group
          reload
          computed
          ;
        source = file.source or null;
        render = file.render or null;
        # Who puts the bytes at the path, beside the disposition, which says
        # where they come from. A store object carries one record, so a file
        # stating another is installed here, and a recipe naming a reference is
        # installed whatever its record: its bytes are a path the machine holds.
        install = disposition == reference || !(carriedByStore file);
      }
    ) (entry.configData or { });

  # Every path a byte of one configuration file can be at, all three under the
  # entry's own staging directory, which detaching removes. `staged` is the path
  # the unit is shown, and the other two are what the move onto it comes from.
  configFilesOf =
    name: entry:
    map (
      f:
      f
      // {
        staged = stagedPath name f.path;
        assembling = "${stagedPath name f.path}.assembling";
        installing = "${stagedPath name f.path}.installing";
      }
    ) (configRecordsOf entry);

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

  # Where the bytes the bind reads come from. A file this realiser installs is
  # read from the path it installed it at, whatever the recipe; a file the store
  # can carry as declared is read from the store object itself, which arrives
  # with the entry's closure. A delivered file arrives at its own path.
  fromOf =
    name: f:
    if f.install then
      f.staged
    else if f.disposition == "source" then
      f.source
    else
      (if assemble == null then null else assemble (assembledName name f.path) (literalsOf f));

  hostPathsOf =
    { name, entry }:
    map (
      f:
      {
        path = f.path;
        from = fromOf name f;
        kind = "configuration-file";
        inherit (f)
          mode
          owner
          group
          disposition
          install
          ;
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

  # The same rule the planner asks, with the other answer to its one policy: a
  # confining profile imposes the account and never imposes root, so a unit
  # declaring none is admitted by nothing but the world bit.
  admits = planner.util.admits { rootAdmitted = false; };

  # The files whose record a profile compares against the account it imposes: a
  # delivered generated file, and every configuration file the entry declares.
  # Both reach a unit at a host path, so a profile denying a host file only root
  # may read denies either one whose record admits no other account.
  denialsOf =
    {
      denies,
      units,
      generated,
      configFiles,
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
            record = recordOf g;
            account = if units.${u} ? user then units.${u}.user else "a transient account";
          }) (filter (u: !(admits units.${u} g)) (attrNames units))
        )
        (
          if elem "a host file only root may read" denies then
            filter (g: g.deploy && g.inPlan == reference) generated ++ filter (f: isString f.mode) configFiles
          else
            [ ]
        )
    );

  # The entry's host-path binds, identical on every unit of it, which is what
  # lets the derived probe unit reach a delivered value or a configuration file
  # with no bind of its own.
  bindsOf =
    image:
    map (p: "BindReadOnlyPaths=${p.from}:${p.path}") (sort (a: b: a.path < b.path) image.hostPaths);

  # Every shown path has to name bytes the machine holds. A literal recipe's
  # bytes are the builder's to write, so a reading handed no assembly cannot
  # render one at all.
  unassembledOf = image: filter (p: p.from == null) image.hostPaths;

in
rec {
  inherit
    profiles
    profilesFor
    profileNames
    unitDirectories
    sidecarsOf
    signatureOf
    systemdDirectives
    unitDirectives
    dispositionOf
    literalsOf
    storeRecord
    recordOf
    backend
    keyParts
    nameOf
    unitFileName
    timerFileName
    unitFilesOf
    probeFileName
    probedUnits
    stagingOf
    stagedPath
    nameRule
    acceptsName
    unitRule
    acceptsUnit
    scopes
    holdings
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
    let
      scoped = profilesFor (scopeOf entry);
    in
    if !(scoped ? ${profile}) then
      [ ]
    else
      denialsOf {
        inherit (scoped.${profile}) denies;
        units = entry.units or { };
        generated = generatedOf entry;
        configFiles = configRecordsOf entry;
      };

  # The digest the endpoint stores for an artifact, over the artifact's own
  # content and never over the plan key. A shown path enters it by what its bytes
  # are rather than by where a builder put them, so a reading handed an assembly
  # and one handed none answer alike, which is what lets `operator/read.nix`
  # publish it.
  versionFor =
    {
      key,
      entry,
      profile,
    }:
    let
      parts = parseKey key;
      name = nameOf parts;
      target = entry.target or { };
      scope = scopeOf entry;
      byPath = path: builtins.head (filter (f: f.path == path) (configFilesOf name entry));
    in
    versionOf (
      {
        inherit name profile;
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
      }
      # The scope enters the digest where it moves off its default and nowhere
      # else, the way it enters the machine record and the target: the unit
      # directory, the identity file and the attach argv are all another image,
      # and a system-scope image is the one this realiser already built.
      // (if scope == "system" then { } else { inherit scope; })
    );

  read =
    {
      plan,
      key,
      profile,
      rules ? imageRules,
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

      # The scope the entry's machine offers, which decides where the unit files
      # of this image sit, what its identity file states and which manager the
      # attach addresses. A target that records none offers `system`.
      scope = scopeOf entry;

      scopedProfiles = profilesFor scope;

      profileRecord =
        if scopedProfiles ? ${profile} then
          scopedProfiles.${profile}
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

      version = versionFor { inherit key entry profile; };

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

          # One question per unit, asked before any of the three refusals the
          # pair can make, so a unit recording neither field costs two
          # membership tests and no further thunk.
          probeStated = unit ? probe || unit ? probeTimeout;
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
        else if probeStated && !(unit ? probeTimeout) then
          fail accounts.probeWithoutTimeout "entry ${quote key} unit ${quote unitName} records a `probe` and no `probeTimeout`, and a bound this builder invented for it would be a default the plan does not state"
        else if probeStated && !(unit ? probe) then
          fail accounts.probeTimeoutWithoutProbe "entry ${quote key} unit ${quote unitName} records a `probeTimeout` and no `probe`, so there is no command for the bound to bound"
        else if probeStated && planner.atoms.domains.isZeroDuration unit.probeTimeout then
          fail accounts.probeTimeoutUnbounded "entry ${quote key} unit ${quote unitName} records a `probeTimeout` of ${quote unit.probeTimeout}, which is systemd's own spelling of no bound at all"
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
        configFiles = configRecordsOf entry;
      };

      # A unit file is line-oriented, so a newline in a value is a fact the file
      # cannot carry. Spaces and quotes can be: they are escaped at render. The
      # record is what both this and the row above it read, so a field added to
      # the vocabulary or to an extension is covered by existing.
      unprintable = concatLists (
        map (
          u:
          map (found: { unit = u; } // found) (
            filter (found: carriesLineBreak found.value) (stringsDeep units.${u})
          )
        ) (attrNames units)
      );

      # Every name the realiser meeting this entry derives, before a store name
      # is built from one. A name outside its rule is refused here rather than
      # left to whatever the build system makes of it, which names neither the
      # entry nor the declaration.
      unitFiles = unitFilesOf name units;

      refusedUnits = filter (file: !(rules.acceptsUnit name file)) unitFiles;

      # One question per entry, asked once: the entry derives one probe file, so
      # two units recording a probe are one file and two candidate commands.
      probedNames = sortStrings (probedUnits units);
    in
    if !(rules.acceptsName name) then
      rules.nameRefused { inherit key name; }
    else if !(isAttrs units) || units == { } then
      fail accounts.entryRealisesNothing "entry ${quote key} records no unit, so there is nothing to attach"
    else if refusedUnits != [ ] then
      rules.unitRefused {
        inherit key name;
        file = builtins.head (sortStrings refusedUnits);
      }
    else if builtins.length probedNames > 1 then
      fail accounts.probeDeclaredTwice "entry ${quote key} records a `probe` on units ${quoteList probedNames}, and the entry derives one probe file ${quote (probeFileName name)}, so there is one file and two candidate commands"
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
      fail accounts.unitValueNewline "entry ${quote key} unit ${quote first.unit} sets ${quote (oneLine first.path)} to a value containing a newline, which a unit file has no line to put"
    else
      {
        inherit
          key
          entry
          name
          version
          profile
          scope
          storeDir
          closure
          system
          serviceManager
          generated
          configFiles
          hostPaths
          referencePaths
          ;
        # Which unit the one derived probe unit is built from, answered once
        # here: the rendering, the attachment and the file list all read this
        # rather than walking the unit set again.
        probed = if probedNames == [ ] then null else builtins.head probedNames;
        unitDirectory = unitDirectories.${scope};
        inherit (profileRecord) statements;
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
      # space in it becomes two assignments and the second is garbage. Both halves
      # of the assignment go through the one escape: a name that closed the quoting
      # would leave the rest of the line to whoever wrote the name.
      escaped = replaceStrings [ "\\" "\"" ] [ "\\\\" "\\\"" ];

      envNames = sortStrings (attrNames (unit.env or { }));

      environment = map (k: "Environment=\"${escaped k}=${escaped unit.env.${k}}\"") envNames;

      # The name is the left half of the assignment, written with no escape of
      # its own, so it is held to the grammar the library states for one. The
      # value's one uncarriable part is a line break, a unit file being
      # line-oriented.
      envRefused = filter unassignable envNames;

      uncarried = filter (p: carriesLineBreak p.value) (
        map (k: {
          name = k;
          value = unit.env.${k};
        }) envNames
      );

      unassembled = unassembledOf image;

      binds = bindsOf image;

      extensionLines = map (f: "${u.directives.${f}.directive}=${u.directives.${f}.value}") (
        sortStrings (attrNames u.directives)
      );

      # A condition goes in [Unit], and the negative polarity is the directive's
      # own `!` prefix rather than a second directive name.
      conditions =
        optional (unit ? startIfPathPresent) [
          "${unitDirectives.startIfPathPresent}=${unit.startIfPathPresent}"
        ]
        ++ optional (unit ? startIfPathAbsent) [
          "${unitDirectives.startIfPathAbsent}=!${unit.startIfPathAbsent}"
        ];

      directoryLines = concatLists (
        map (f: optional (unit ? ${f}) [ "${unitDirectives.${f}}=${spell unit.${f}}" ]) directoryFields
      );
    in
    if envRefused != [ ] then
      fail accounts.envNameRefused "entry ${quote image.key} unit ${quote unitName} sets the environment variable ${quote (oneLine (builtins.head envRefused))}, and this renderer writes a name as the left half of an assignment with no escape of its own: a name is ${envNameAdmits}"
    else if uncarried != [ ] then
      fail accounts.unitValueNewline "entry ${quote image.key} unit ${quote unitName} sets the environment variable ${quote (oneLine (builtins.head uncarried).name)} to a value containing a newline, which a unit file has no line to put"
    else if unassembled != [ ] then
      fail accounts.hostPathUnassembled "entry ${quote image.key} is shown the host path ${quote (builtins.head unassembled).path} whose bytes this reading was handed no way to assemble"
    else
      builtins.concatStringsSep "\n" (
        [
          "[Unit]"
          "Description=${image.instance}:${image.service} ${unitName}"
        ]
        ++ optional (unit ? after) (map (r: "${unitDirectives.after}=${prefixed r}") unit.after)
        ++ optional (unit ? requires) (map (r: "${unitDirectives.requires}=${prefixed r}") unit.requires)
        ++ conditions
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
        ++ directoryLines
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

  # The probe unit, rendered here and by neither realiser's wrapper: the one
  # thing the two realisers differ about for a unit file is the install section,
  # and this file carries none - the endpoint starts it by name after switching
  # and an `[Install]` would queue it at every boot as well. `Requires=` beside
  # `After=` is what makes starting it on a machine whose service is not active
  # fail rather than succeed, which is the gate. It takes the probed unit's
  # account, so it is denied exactly what the unit it probes is denied, and it
  # claims no directory of any kind: a runtime directory is deleted when the
  # unit declaring it exits, and this one exits.
  renderProbe =
    image:
    let
      unitName = image.probed;
      unit = image.units.${unitName}.record;
      probed = unitFileName image.name unitName;
      unassembled = unassembledOf image;
    in
    if unassembled != [ ] then
      fail accounts.hostPathUnassembled "entry ${quote image.key} is shown the host path ${quote (builtins.head unassembled).path} whose bytes this reading was handed no way to assemble"
    else
      builtins.concatStringsSep "\n" (
        [
          "[Unit]"
          "Description=${image.instance}:${image.service} ${unitName} probe"
          "${unitDirectives.after}=${probed}"
          "${unitDirectives.requires}=${probed}"
          ""
          "[Service]"
          "${unitDirectives.probe}=${unit.probe}"
          "${unitDirectives.oneShot}=oneshot"
          "${unitDirectives.probeTimeout}=${unit.probeTimeout}"
        ]
        ++ planner.util.optional (unit ? user) "${unitDirectives.user}=${unit.user}"
        ++ bindsOf image
      )
      + "\n";

  # Every file a realiser writes for one entry's units: one per unit, one per
  # scheduled unit's timer, and the derived probe unit where the entry records a
  # probe. A realiser hands its own two renderers over, because flakelet wraps
  # both of them; the probe is rendered by this reading itself, so the two
  # realisers cannot drift about the file that decides an activation.
  renderedUnitsBy =
    renderers: image:
    concatLists (
      mapAttrsToList (
        unitName: u:
        [
          {
            file = u.file;
            text = renderers.renderUnit image unitName;
          }
        ]
        ++ planner.util.optional (u.timer != null) {
          file = u.timer;
          text = renderers.renderTimer image unitName;
        }
      ) image.units
    )
    ++ planner.util.optional (image.probed != null) {
      file = probeFileName image.name;
      text = renderProbe image;
    };

  renderedUnits = renderedUnitsBy { inherit renderUnit renderTimer; };

  attachment = image: {
    entry = image.key;
    image = "${image.name}${nameSeparator}${image.version}.raw";
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
      inherit (image) serviceManager scope;
    };
    units = sortStrings (
      map (u: u.file) (builtins.attrValues image.units)
      ++ map (u: u.timer) (filter (u: u.timer != null) (builtins.attrValues image.units))
      ++ planner.util.optional (image.probed != null) (probeFileName image.name)
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
