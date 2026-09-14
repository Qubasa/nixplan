# Plan emission: entries, keys and the rows an entry produces. A plan is flat,
# keyed and free of expressions. Nothing here is a derivation and every store path
# is a literal string.
{
  util,
  diag,
}:
let
  inherit (builtins)
    all
    attrValues
    concatLists
    concatMap
    elem
    filter
    head
    isAttrs
    isList
    isString
    listToAttrs
    mapAttrs
    substring
    ;

  pruned = entry: util.filterAttrs (_: v: !((isAttrs v && v == { }) || (isList v && v == [ ]))) entry;
in
rec {
  machineKey = record: util.shortHash (builtins.toJSON record);

  # Every reader of every export, as a flat index, so a capability can record who
  # reads it without walking the deployment again.
  readerIndex =
    resolved:
    let
      rows = util.concatMapAttrsToList (
        iname: inst:
        util.concatMapAttrsToList (
          mname: member:
          let
            consumers = entryKeysOf iname mname member;
          in
          util.concatMapAttrsToList (
            _: edge:
            if !edge.delivered then
              [ ]
            else
              concatLists (
                map (
                  providerKey:
                  let
                    absent = edge.entryAbsences.${providerKey} or [ ];
                  in
                  map (ename: {
                    key = "${providerKey}|${edge.capability}|${ename}";
                    inherit consumers;
                    rows = map (subject: {
                      id = "set-entry-absent";
                      inherit subject;
                    }) (if elem ename absent then consumers else [ ]);
                  }) edge.reads
                ) edge.entryKeys
              )
          ) member.edges
        ) inst.members
      ) resolved.instances;
    in
    mapAttrs (_: group: {
      readBy = util.uniqueStrings (concatLists (map (r: r.consumers) group));
      rows = concatLists (map (r: r.rows) group);
    }) (builtins.groupBy (r: r.key) rows);

  # A key is structural: placement alone decides it. It cannot depend on whether a
  # member produced units, because two instances that wire each other would then
  # each need the other's units to know its own key.
  entryKeysOf =
    iname: mname: member:
    if member.placements == [ ] then
      [ "${iname}:${mname}" ]
    else
      map (machine: "${iname}:${mname}@${machine}") member.placements;

  agreedEnv =
    units:
    let
      envs = util.mapAttrsToList (_: unit: unit.env or { }) units;
    in
    if envs == [ ] then
      { }
    else
      util.filterAttrs (k: v: all (e: (e.${k} or null) == v) envs) (head envs);

  # `deploy` is on every file rather than on the group: a realiser reads one file
  # at a time, and whether bytes arrive at a path decides whether it may show that
  # path to a unit at all. An undeployed file still has a path, because a site that
  # opens it is a row this plan also reports.
  #
  # `owner`, `group` and `mode` are always recorded and enter the key only where
  # the declaration stated them, which is the rule `program` already follows: a
  # plan written before the fields existed keys as it did, and a deployment that
  # states a mode delivers a different artifact and says so.
  fileRecord =
    file:
    {
      inherit (file)
        path
        secrecy
        deploy
        owner
        group
        mode
        ;
      inPlan = if file.secrecy == "secret" then "reference" else "value";
    }
    // (if file.present then { } else { bytes = "absent"; });

  fileKeyInput = file: removeAttrs (fileRecord file) (util.subtractList ownershipKeys file.stated);

  ownershipKeys = [
    "owner"
    "group"
    "mode"
  ];

  varsRecord =
    placement: mapAttrs (_: files: { files = mapAttrs (_: fileRecord) files; }) placement.vars;

  varsKeyFiles = placement: mapAttrs (_: files: mapAttrs (_: fileKeyInput) files) placement.vars;

  referencePathsOf =
    { vars, configData }:
    util.concatMapAttrsToList (
      _: g: util.concatMapAttrsToList (_: f: if f.inPlan == "reference" then [ f.path ] else [ ]) g.files
    ) vars
    ++ util.concatMapAttrsToList (
      _: file:
      if file ? render then concatMap (i: if i ? ref then [ i.ref ] else [ ]) file.render else [ ]
    ) configData;

  # Every read of a generated value, as a flat index from the value's entry key to
  # the entries that named it and what they named. The delivery set comes from
  # this and from the owner's placements: a routable secret is bounded by nobody,
  # so who declared a read is the only thing that can narrow it.
  valueReaderIndex =
    resolved:
    let
      rows = util.concatMapAttrsToList (
        iname: inst:
        util.concatMapAttrsToList (
          mname: member:
          let
            consumers = entryKeysOf iname mname member;
          in
          util.concatMapAttrsToList (
            slotName: edge:
            if !edge.delivered then
              [ ]
            else
              concatLists (
                map (
                  providerKey:
                  concatLists (
                    util.mapAttrsToList (
                      ename: varsFile:
                      map (consumer: {
                        key = varsFile.entry;
                        reason = "${consumer} named ${ename} in uses.${slotName}.reads";
                        machine = machineOf consumer;
                      }) consumers
                    ) (edge.entryVarsFiles.${providerKey} or { })
                  )
                ) edge.entryKeys
              )
          ) member.edges
        ) inst.members
      ) resolved.instances;
    in
    mapAttrs (_: group: {
      machines = util.uniqueStrings (filter (m: m != null) (map (r: r.machine) group));
      reasons = util.sortStrings (util.uniqueStrings (map (r: r.reason) group));
    }) (builtins.groupBy (r: r.key) rows);

  machineOf =
    key:
    let
      parts = builtins.split "@" key;
    in
    if builtins.length parts == 1 then null else builtins.elemAt parts (builtins.length parts - 1);

  providesRecord =
    {
      readers,
      placement,
    }:
    mapAttrs (
      cap: record:
      let
        published = {
          interface = record.interfaceName;
          declaringFile = record.declaringFile;
          inherit (record) keysetEqualsInterface;
          exports = mapAttrs (
            ename: e:
            let
              read =
                readers."${placement.entryKey}|${cap}|${ename}" or {
                  readBy = [ ];
                  rows = [ ];
                };
            in
            {
              inherit (e) plane secrecy;
              value = e.value;
              inherit (read) readBy;
            }
            // (
              if e.absent then
                {
                  bytes = "absent";
                  inherit (read) rows;
                }
              else
                { }
            )
          ) record.exports;
        };
      in
      if record.interfaceId == null then published else published // { interfaceId = record.interfaceId; }
    ) placement.capabilities;

  # An absent entry of a set-valued read is named with a null value and a marker
  # rather than dropped, so a consumer cannot mistake absence for a value.
  readsRecord =
    { subject, member }:
    mapAttrs (
      _slotName: edge:
      let
        absencesOf = key: edge.entryAbsences.${key} or [ ];
        base = {
          inherit (edge) reach reads delivered;
        }
        // (if edge.wire == null then { } else { inherit (edge) wire; });
      in
      base
      // (
        if !edge.delivered then
          { }
        else if edge.reach == "all" then
          {
            entries =
              if edge.absentEntries == [ ] then
                edge.value
              else
                mapAttrs (
                  key: values:
                  values
                  // (
                    if absencesOf key == [ ] then
                      { }
                    else
                      {
                        bytes = "absent";
                        row = {
                          id = "set-entry-absent";
                          inherit subject;
                        };
                      }
                  )
                ) edge.value;
          }
        else
          {
            entry = head edge.entryKeys;
            values = edge.value;
          }
      )
    ) member.edges;

  readsComplete =
    member: all (edge: !edge.delivered || edge.absentEntries == [ ]) (attrValues member.edges);

  entryRows =
    { subject, member }:
    util.concatMapAttrsToList (
      slotName: edge:
      if !edge.delivered then
        [ ]
      else
        map (
          absent:
          diag.error {
            inherit subject;
            id = "set-entry-absent";
            message = "${slotName} names ${
              util.countNoun (builtins.length edge.entryKeys) "entry" "entries"
            } and ${util.quote absent.entryKey} has no bytes";
            evidence = "the slot declares reach ${util.quote edge.reach} over ${util.quote "${edge.providerInstance}.${edge.capability}"}, and ${util.quoteList absent.absentReads} of that entry is declared and not generated";
            resolution = "generate the missing value for that placement and replan; a set-valued read names its entries, so the set cannot be shortened by dropping it";
          }
        ) edge.absentEntries
        ++ util.optional (edge.reach == "all") (
          diag.warning {
            inherit subject;
            id = "set-read-in-key";
            message = "the ${slotName} set is in this entry's key";
            evidence = "the entry's key is a function of its resolved reads, and ${slotName} resolves to ${
              util.countNoun (builtins.length edge.entryKeys) "entry" "entries"
            } chosen by the placement of ${util.quote "${edge.providerInstance}.${edge.capability}"}";
            resolution = "expect this entry to be re-keyed when another machine joins or leaves that set; what re-keys an entry and what restarts a process are decided separately";
          }
        )
    ) member.edges;

  # Whether an account may open a delivered file, from the plan alone: the file's
  # recorded ownership and mode, and the unit's own account. A read bit is the
  # octal digit carrying 4.
  opens =
    digit:
    elem digit [
      "4"
      "5"
      "6"
      "7"
    ];

  # A unit's declared groups are whatever its extension applications record under
  # `supplementaryGroups`, under any backend: this layer names no realiser, and
  # the key is the one a realiser's directive table and this rule both read.
  groupsOf =
    unit:
    concatLists (
      util.mapAttrsToList (
        _: fields:
        let
          declared = fields.supplementaryGroups or null;
        in
        if isList declared then
          filter isString declared
        else if isString declared then
          [ declared ]
        else
          [ ]
      ) (unit.extends or { })
    );

  admits =
    unit: file:
    let
      account = unit.user or null;
    in
    account == null
    || (account == file.owner && opens (substring 1 1 file.mode))
    || (elem file.group (groupsOf unit) && opens (substring 2 1 file.mode))
    || opens (substring 3 1 file.mode);

  # A unit that cannot open a value its entry reads. Produced here rather than
  # beside the wire, because the comparison needs the units and a unit set is a
  # later stratum than the reads an entry's key is built from.
  unreadableRows =
    {
      subject,
      member,
      units,
    }:
    util.concatMapAttrsToList (
      slotName: edge:
      if !edge.delivered then
        [ ]
      else
        util.concatMapAttrsToList (
          _providerKey: files:
          util.concatMapAttrsToList (
            readName: file:
            if !file.deploy then
              [ ]
            else
              util.concatMapAttrsToList (
                unitName: unit:
                util.optional (!(admits unit file)) (
                  diag.error {
                    inherit subject;
                    id = "slot-reads-value-unreadable-by-user";
                    message = "unit ${util.quote unitName} of ${util.quote subject} runs as ${util.quote unit.user} and reads ${util.quote readName} of slot ${util.quote slotName}, whose file is delivered as ${util.quote "${file.owner}:${file.group}"} at mode ${util.quote file.mode}";
                    evidence = "the mode admits its owner, a member of its group where the unit declares that group, and nobody else, so the unit starts and fails with `EACCES` on ${util.quote file.path}";
                    resolution = "declare `owner`, `group` or `mode` on that generated file so ${util.quote unit.user} may open it, or run the unit as ${util.quote file.owner}";
                  }
                )
              ) units
          ) files
        ) edge.entryVarsFiles
    ) member.edges;

  # A configuration file names its bytes and never carries them. A digest covers
  # only material the plan itself holds, and a file rendered over a set with an
  # absent entry is recorded as not computed rather than hashed over the rest.
  fileIdentity =
    file:
    if file.disposition == "source" then
      { inherit (file) source; }
    else if file.disposition == "render" then
      let
        hasReference = builtins.any (item: item ? ref) file.render;
      in
      {
        inherit (file) render;
      }
      // (
        if hasReference then
          { structureHash = util.shortHash (builtins.toJSON file.render); }
        else
          { contentHash = util.shortHash (builtins.concatStringsSep "" (map (item: item.text) file.render)); }
      )
    else
      { };

  configDataRecord =
    {
      subject,
      member,
      placement,
    }:
    let
      complete = readsComplete member;

      guarded = diag.guard {
        inherit subject;
        what = "the configuration data of ${subject}";
        fallback = { };
        value = mapAttrs (
          _: file:
          {
            inherit (file) mode reload;
            computed = true;
          }
          // fileIdentity file
        ) placement.configData;
      };
    in
    if complete then
      {
        record = guarded.value;
        rows = guarded.rows;
      }
    else
      {
        record = mapAttrs (_: file: {
          inherit (file) mode reload;
          computed = false;
          row = {
            id = "set-entry-absent";
            inherit subject;
          };
        }) placement.configData;
        rows = [ ];
      };

  settingsRecord =
    member:
    mapAttrs (k: v: {
      value = v;
      source = member.settings.sources.${k};
    }) member.settings.values;

  # Every place an entry names a string, for the two checks that scan them: the
  # closure check, which scans all of them, and the undeployed-value check, which
  # scans only the sites that open a path rather than declare one.
  mentionSites =
    {
      units,
      configData,
      placement,
    }:
    util.mapAttrsToList (name: unit: {
      kind = "unit";
      where = "unit ${util.quote name}";
      value = removeAttrs unit [
        "env"
        "extends"
      ];
    }) units
    ++ util.mapAttrsToList (name: unit: {
      kind = "unit";
      where = "the environment of unit ${util.quote name}";
      value = unit.env or { };
    }) units
    ++ util.mapAttrsToList (name: unit: {
      kind = "unit";
      where = "an extension of unit ${util.quote name}";
      value = unit.extends or { };
    }) units
    ++ util.mapAttrsToList (path: file: {
      kind = "file";
      where = "configuration file ${util.quote path}";
      value = removeAttrs file [
        "mode"
        "reload"
        "computed"
      ];
    }) configData
    ++ util.concatMapAttrsToList (
      gen: files:
      util.mapAttrsToList (fname: file: {
        kind = "declaration";
        where = "generated file ${util.quote "${gen}/${fname}"}";
        value = file.path;
      }) files
    ) placement.vars
    ++ util.concatMapAttrsToList (
      cap: record:
      util.mapAttrsToList (ename: e: {
        kind = "declaration";
        where = "export ${util.quote "${cap}.${ename}"}";
        value = e.value;
      }) record.exports
    ) placement.capabilities;

  # A `deploy = false` generator's file exists as a value and never as bytes on a
  # machine, so a site that opens its path is a path that resolves to nothing at
  # run time. The walk is the one the closure check already does.
  undeployedRows =
    {
      subject,
      module,
      placement,
      sites,
    }:
    let
      undeployed = concatLists (
        util.mapAttrsToList (
          gen: files:
          util.mapAttrsToList (fname: file: {
            inherit gen fname;
            inherit (file) path;
          }) (util.filterAttrs (_: file: !file.deploy) files)
        ) placement.vars
      );
      paths = map (f: f.path) undeployed;
      opened = concatLists (
        map (
          site:
          map (path: {
            inherit path;
            inherit (site) where;
          }) (util.mentionsDeep paths site.value)
        ) sites
      );
      fileOf = path: head (filter (f: f.path == path) undeployed);
    in
    map (
      m:
      let
        file = fileOf m.path;
      in
      diag.error {
        inherit subject;
        id = "vars-not-deployed-opened";
        message = "${subject} names ${util.quote m.path} in ${m.where}, and no machine receives that value";
        evidence = "generator ${util.quote file.gen} of ${module} declares `deploy = false`, so one value exists and the path it is read at holds nothing";
        resolution = "declare that generator deployed in ${module}, or stop naming ${util.quote "${file.gen}/${file.fname}"} in ${m.where}";
      }
    ) opened;

  # An undeclared mention is an error, because the closure is the list a consumer
  # populates a filesystem from. A declared root nothing mentions is a warning: it
  # is either dead weight or a path assembled at run time worth writing down.
  closureRows =
    {
      subject,
      storeDir,
      declared,
      references,
      sites,
    }:
    let
      scan = util.storePathsDeep storeDir;
      mentioned = concatLists (
        map (
          site:
          map (path: {
            inherit path;
            inherit (site) where;
          }) (scan site.value)
        ) sites
      );

      declaredSet = util.stringSet declared;
      mentionedSet = util.stringSet (map (m: m.path) mentioned);
      undeclared = filter (m: !util.inStringSet declaredSet m.path) mentioned;
      unmentioned = filter (root: !util.inStringSet mentionedSet root) declared;
      outsideTheStore = filter (root: scan root != [ root ]) declared;
      delivered = filter (root: elem root references) declared;
    in
    map (
      m:
      diag.error {
        inherit subject;
        id = "closure-path-undeclared";
        message = "${subject} mentions ${util.quote m.path} in ${m.where} and does not declare it among its closure roots";
        evidence = "the closure is the list a consumer populates a filesystem from, and inference over an entry's strings cannot be complete, so a mention the declaration does not carry is a contradiction rather than an addition";
        resolution = "add ${util.quote m.path} to `closure` in the module's implementation, or stop naming it in ${m.where}";
      }
    ) undeclared
    ++ map (
      root:
      diag.warning {
        inherit subject;
        id = "closure-root-unmentioned";
        message = "${subject} declares the closure root ${util.quote root} and mentions it nowhere";
        evidence = "a root nothing names is either dead weight or a path assembled at runtime, and the second is worth having written down";
        resolution = "delete ${util.quote root} from `closure`, or leave it and expect the image to carry it";
      }
    ) unmentioned
    ++ map (
      root:
      diag.error {
        inherit subject;
        id = "closure-root-outside-store";
        message = "${subject} declares the closure root ${util.quote root}, which is not a path under the store directory ${util.quote storeDir} the plan is read against";
        evidence = "a closure root is a literal path under the store the plan is read against, and a consumer populates a filesystem from those roots";
        resolution = "declare a path under ${util.quote storeDir} in `closure`, or plan the deployment against the store ${util.quote root} belongs to";
      }
    ) outsideTheStore
    ++ map (
      root:
      diag.error {
        inherit subject;
        id = "closure-root-is-delivered";
        message = "${subject} declares the closure root ${util.quote root}, which the plan records as a delivered reference";
        evidence = "the bytes of a reference reach the units from the machine that received them and never through a closure";
        resolution = "delete ${util.quote root} from `closure`: the bytes arrive at ${util.quote root} by delivery";
      }
    ) delivered;

  # The three host resources the plan already records, and the row two entries of
  # one machine claiming one of them earn. Two writers of one file and two
  # listeners on one port are contradictions, while a shared directory is
  # destructive for `runtimeDirectory` and a handoff a deployment may intend for
  # `stateDirectory`, so the third is a warning and the build still happens.
  hostResources = {
    paths = {
      id = "entry-host-path-claimed-twice";
      row = diag.error;
      what = name: "declare a configuration file at ${util.quote name}";
      evidence = "a host path holds one file, so the entry applied last is the one whose rendering survives and the others are overwritten with nothing saying so";
      resolution =
        name:
        "derive ${util.quote name} from the entry's own identity, which an implementation is handed as `instance` and `member`, or place the entries on different machines";
    };
    ports = {
      id = "entry-port-claimed-twice";
      row = diag.error;
      what = name: "claim the port ${util.quote name}";
      evidence = "one machine carries one listener per protocol and port, so every entry after the first cannot bind and the failure names neither declaration";
      resolution =
        name:
        "claim a `fixed` port other than ${util.quote name} in one of them, derived from the entry's own identity an implementation is handed as `instance` and `member`, or place the entries on different machines";
    };
    directories = {
      id = "entry-unit-directory-shared";
      row = diag.warning;
      what = name: "record the unit directory ${util.quote name}";
      evidence = "the service manager deletes a runtime directory when its unit restarts, so two entries sharing one lose each other's files, and a shared state directory is a handoff only where both declarations intend one";
      resolution =
        name:
        "derive ${util.quote name} from the entry's own identity, which an implementation is handed as `instance` and `member`, or leave it shared where both entries intend the handoff";
    };
  };

  # A unit directory is whatever an extension application records under these
  # three keys, under any backend, read the way a unit's declared groups are. The
  # claim carries the field it was recorded under, because a state directory and
  # a runtime directory of one name are two paths on the machine.
  directoryFields = [
    "cacheDirectory"
    "runtimeDirectory"
    "stateDirectory"
  ];

  directoriesOf =
    unit:
    concatLists (
      util.mapAttrsToList (
        _: fields:
        concatMap (
          field:
          let
            declared = fields.${field} or null;
          in
          if isList declared then
            map (name: "${field}/${name}") (filter isString declared)
          else if isString declared then
            [ "${field}/${declared}" ]
          else
            [ ]
        ) directoryFields
      ) (unit.extends or { })
    );

  # A port claim compares the protocol beside the number, so a TCP listener and a
  # UDP listener on one number are two claims. `count` is recorded and not
  # expanded: one claim still states one number in this subset.
  portsOf =
    member:
    util.mapAttrsToList (
      name: fixed:
      let
        proto = member.declaration.claims.ports.${name}.proto or null;
      in
      "${if isString proto then proto else "unstated"}/${builtins.toJSON fixed}"
    ) member.alloc.ports;

  # One entry's claims, flat, each naming the claimant. Deduplication is per
  # entry and happens here rather than after the collision test: two units of one
  # entry recording one directory is one claim, the claimant being the entry.
  claimsOf =
    entry:
    if !(entry ? claims) then
      [ ]
    else
      concatMap (
        kind:
        map (name: {
          key = entry.name;
          inherit (entry.claims) machine;
          inherit kind name;
        }) (util.uniqueStrings entry.claims.${kind})
      ) (builtins.attrNames hostResources);

  # A host resource two entries of one machine both claim. The claims are one
  # flat list grouped twice, by machine and then by resource, so the check costs
  # the claims rather than their square, and one member placed on two machines
  # claims under two machines rather than against itself. The row is one row for
  # one collision, subjected to the first claimant in plan key order.
  collisionRows =
    claims:
    concatLists (
      util.mapAttrsToList (
        machine: onMachine:
        concatLists (
          util.mapAttrsToList (
            _: claimants:
            let
              keys = util.sortStrings (util.uniqueStrings (map (c: c.key) claimants));
              resource = hostResources.${(head claimants).kind};
              name = (head claimants).name;
            in
            util.optional (builtins.length keys > 1) (
              resource.row {
                inherit (resource) id evidence;
                subject = head keys;
                message = "entries ${util.quoteList keys} placed on ${util.quote machine} all ${resource.what name}";
                resolution = resource.resolution name;
              }
            )
          ) (builtins.groupBy (c: "${c.kind} ${c.name}") onMachine)
        )
      ) (builtins.groupBy (c: c.machine) claims)
    );

  # The key hashes the instance, the service, the machine, the target, the pin, the
  # units, the store paths the entry declares, the values it was handed and the
  # keys it depends on.
  placedEntry =
    {
      readers,
      resolved,
      machineKeys,
      iname,
      mname,
      member,
      machine,
    }:
    let
      placement = member.placed.${machine};
      subject = placement.entryKey;
      units = placement.units;
      env = agreedEnv units;
      closure = placement.closure;
      dependsOn = [ "machine:${machine}@${machineKeys.${machine}}" ];
      reads = readsRecord { inherit subject member; };
      vars = varsRecord placement;
      configData = configDataRecord {
        inherit subject member placement;
      };
      target = placement.target;
      pin = member.declaration.pin;
      keyInput = {
        instance = iname;
        service = mname;
        inherit
          machine
          closure
          dependsOn
          reads
          units
          env
          target
          pin
          ;
        storeDir = resolved.storeDir;
        configData = configData.record;
        settings = member.settings.values;
        alloc = member.alloc.ports;
      };
    in
    {
      name = subject;
      # The records the entry claims on its machine, taken from the pre-pruned
      # values rather than from the plan, which drops an empty one.
      claims = {
        inherit machine;
        paths = builtins.attrNames configData.record;
        ports = portsOf member;
        directories = concatMap directoriesOf (attrValues units);
      };
      rows =
        let
          sites = mentionSites {
            inherit units placement;
            configData = configData.record;
          };
        in
        configData.rows
        ++ closureRows {
          inherit subject sites;
          storeDir = resolved.storeDir;
          declared = closure;
          references = referencePathsOf {
            inherit vars;
            configData = configData.record;
          };
        }
        ++ undeployedRows {
          inherit subject placement;
          module = member.moduleLabel;
          # The module's own vars and exports are declarations rather than sites
          # that open a path, so only the units and the files are scanned.
          sites = filter (site: site.kind != "declaration") sites;
        }
        ++ entryRows {
          inherit subject member;
        }
        ++ unreadableRows {
          inherit subject member units;
        };
      value =
        pruned {
          key = util.shortHash (builtins.toJSON keyInput);
          inherit
            dependsOn
            reads
            env
            ;
          storeDir = resolved.storeDir;
          placement = member.placementRecord;
          alloc = if member.alloc.ports == { } then { } else { inherit (member.alloc) ports; };
          inherit vars;
          configData = configData.record;
          provides = providesRecord {
            inherit readers placement;
          };
          settings = {
            ${mname} = settingsRecord member;
          };
        }
        # Always present, empty or not: a realisation reads both, and an entry
        # depending on no store path or running no unit is an answer rather than
        # a fact the plan is missing.
        // {
          inherit closure units;
        }
        // (if target == null then { } else { inherit target; })
        // (if pin == null then { } else { inherit pin; });
    };

  unplacedEntry =
    {
      readers,
      iname,
      mname,
      member,
    }:
    let
      subject = "${iname}:${mname}";
      placement = member.unplaced;
      reads = readsRecord { inherit subject member; };
      keyInput = {
        instance = iname;
        service = mname;
        machine = null;
        inherit reads;
        settings = member.settings.values;
      };
    in
    {
      name = subject;
      rows = entryRows {
        inherit subject member;
      };
      value = pruned {
        key = util.shortHash (builtins.toJSON keyInput);
        inherit reads;
        placement = member.placementRecord;
        provides = providesRecord {
          inherit readers placement;
        };
        settings = {
          ${mname} = settingsRecord member;
        };
      };
    };

  # One entry per generated value. A value delivered to a machine that runs none
  # of the services reading it has no unit entry to live in, and a value that
  # exists once for an instance has no single placement to live in either, so it
  # is an entry of its own.
  #
  # The delivery set is not in the key: a machine joining it because a new
  # consumer declared a read does not change the value, and re-keying it would
  # ask for a regeneration of bytes that are still correct.
  varsEntriesOf =
    {
      valueReaders,
      machineKeys,
      iname,
      mname,
      member,
    }:
    let
      generators = member.declaration.vars.generators;

      # A shared value is recorded once, against the first machine its owner is
      # placed on. Nothing of that machine enters the entry.
      canonical =
        gen: machine: if generators.${gen}.per == "instance" then head member.placements else machine;

      # Terminates because a generator that transitively reads itself is refused
      # by `readVars`, which drops the reads it recorded.
      recordOf =
        gen: machine:
        let
          g = generators.${gen};
          owner = canonical gen machine;
          placement = member.placed.${owner};
          subject = placement.varsEntries.${gen};
          read =
            valueReaders.${subject} or {
              machines = [ ];
              reasons = [ ];
            };
          owners = if g.per == "instance" then member.placements else [ owner ];
          siblings = map (s: recordOf s owner) g.reads;
          files = (varsRecord placement).${gen}.files;
          dependsOn =
            map (r: "${r.name}#${r.value.key}") siblings
            ++ (if g.per == "instance" then [ ] else [ "machine:${owner}@${machineKeys.${owner}}" ]);
          # The program is part of the declaration, so it is part of the identity:
          # a value generated by another program is another value. It enters the
          # key only where one was declared, which is what leaves every plan
          # written before this field existed keyed as it was.
          keyInput = {
            instance = iname;
            generator = gen;
            inherit (g) per deploy;
            files = (varsKeyFiles placement).${gen};
            inherit dependsOn;
            machine = if g.per == "instance" then null else owner;
          }
          // (if g.program == null then { } else { inherit (g) program; });
        in
        {
          name = subject;
          value =
            pruned (
              {
                key = util.shortHash (builtins.toJSON keyInput);
                inherit (g) per deploy;
                inherit dependsOn;
                reads = map (r: r.name) siblings;
              }
              # Recorded, never run, and never a closure root: a generator runs
              # where the plan is read, so `mentionSites` does not scan it and no
              # machine is given it.
              // (if g.program == null then { } else { inherit (g) program; })
            )
            # Always present, empty or not: the file set, the delivery set and
            # the reason each machine is in it are the fields a reader must not
            # be able to mistake for an absence.
            // {
              inherit files;
              delivery =
                if !g.deploy then [ ] else util.sortStrings (util.uniqueStrings (owners ++ read.machines));
              deliveryDerivedFrom =
                if !g.deploy then
                  [ ]
                else
                  util.sortStrings (
                    util.uniqueStrings (map (m: "${iname}:${mname}@${m} owns it") owners ++ read.reasons)
                  );
            };
        };

      ownersOf =
        gen:
        if generators.${gen}.per == "instance" then [ (head member.placements) ] else member.placements;
    in
    if member.placements == [ ] then
      [ ]
    else
      concatLists (util.mapAttrsToList (gen: _: map (recordOf gen) (ownersOf gen)) generators);

  entries =
    resolved:
    let
      readers = readerIndex resolved;
      valueReaders = valueReaderIndex resolved;

      machineKeys = mapAttrs (_: machineKey) resolved.machines;

      varsEntries = concatLists (
        util.mapAttrsToList (
          iname: inst:
          concatLists (
            util.mapAttrsToList (
              mname: member:
              varsEntriesOf {
                inherit
                  valueReaders
                  machineKeys
                  iname
                  mname
                  member
                  ;
              }
            ) inst.members
          )
        ) resolved.instances
      );

      serviceEntries = concatLists (
        util.mapAttrsToList (
          iname: inst:
          concatLists (
            util.mapAttrsToList (
              mname: member:
              if member.placements == [ ] then
                [
                  (unplacedEntry {
                    inherit
                      readers
                      iname
                      mname
                      member
                      ;
                  })
                ]
              else
                map (
                  machine:
                  placedEntry {
                    inherit
                      readers
                      resolved
                      machineKeys
                      iname
                      mname
                      member
                      machine
                      ;
                  }
                ) member.placements
            ) inst.members
          )
        ) resolved.instances
      );

      usedMachines = resolved.usedMachines;

      machineEntries = listToAttrs (
        map (machine: {
          name = "machine:${machine}";
          value = pruned (
            {
              key = machineKeys.${machine};
              inherit (resolved.machines.${machine}) address tags;
            }
            // util.pickAttrs [
              "system"
              "serviceManager"
              "microarchitecture"
            ] (util.filterAttrs (_: v: v != null) resolved.machines.${machine})
          );
        }) usedMachines
      );
    in
    {
      plan = machineEntries // listToAttrs varsEntries // listToAttrs serviceEntries;
      rows =
        concatLists (map (e: e.rows) serviceEntries) ++ collisionRows (concatMap claimsOf serviceEntries);
    };
}
