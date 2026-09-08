# Plan emission: entries, keys, planes and the rows an entry produces.
#
# A plan is flat, keyed and free of expressions. A placed service's key is its
# instance, its service and its machine; a service with no units carries an
# entry with no machine. Nothing in here is a derivation and every store path is
# a literal string.
{
  util,
  diag,
}:
let
  inherit (builtins)
    all
    attrValues
    concatLists
    elem
    filter
    head
    isAttrs
    isList
    listToAttrs
    mapAttrs
    ;

  # An empty attribute set or list is an absence rather than a fact, and a plan
  # a person reads is better without it.
  pruned = entry: util.filterAttrs (_: v: !((isAttrs v && v == { }) || (isList v && v == [ ]))) entry;
in
rec {
  machineKey = record: util.shortHash (builtins.toJSON record);

  # Every reader of every export, as a flat index so that a capability's
  # exports can record who reads them without walking the deployment again.
  # An absent export also records the row each reader's absence produced, so a
  # null value in the plan names the refusal instead of standing alone.
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
    # Grouped rather than folded with `//`: an update per row copies the whole
    # index each time, which is the square of the fleet on a set-valued read.
    mapAttrs (_: group: {
      readBy = util.uniqueStrings (concatLists (map (r: r.consumers) group));
      rows = concatLists (map (r: r.rows) group);
    }) (builtins.groupBy (r: r.key) rows);

  # A key is structural: it is decided by placement alone. It cannot depend on
  # whether a member produced units, because two instances that wire each other
  # would then each need the other's units to know its own key.
  entryKeysOf =
    iname: mname: member:
    if member.placements == [ ] then
      [ "${iname}:${mname}" ]
    else
      map (machine: "${iname}:${mname}@${machine}") member.placements;

  # Each unit of an entry runs with its own environment, and the entry records
  # the variables every unit agrees on. Two units of one service needing
  # different values for one variable is the ordinary case for a portable
  # service, so it is two records and no row.
  agreedEnv =
    units:
    let
      envs = util.mapAttrsToList (_: unit: unit.env or { }) units;
    in
    if envs == [ ] then
      { }
    else
      util.filterAttrs (k: v: all (e: (e.${k} or null) == v) envs) (head envs);

  # A generated file the entry expects, by the path the resolver already fixed
  # it at. The path is recorded rather than left to be reconstructed from the
  # generator and file names, because a consumer showing the file to a service
  # needs the path the plan means and not a convention it reinvents.
  varsRecord =
    placement:
    mapAttrs (_: files: {
      files = mapAttrs (
        _: file:
        {
          inherit (file) path secrecy;
          inPlan = if file.secrecy == "secret" then "reference" else "value";
        }
        // (if file.present then { } else { bytes = "absent"; })
      ) files;
    }) placement.vars;

  # What a capability publishes, with a secret recorded as a path reference, a
  # declared export delivered to nobody recorded with an empty reader list, and
  # an absent export naming the rows its absence produced.
  providesRecord =
    {
      readers,
      placement,
    }:
    mapAttrs (cap: record: {
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
    }) placement.capabilities;

  # A read as the plan records it: the wire, the arity, the entries it names and
  # the value of each. An absent entry is named with a null value and a marker
  # rather than dropped from the set.
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
            # Nothing absent is the ordinary case, and the set the resolver
            # already built is then the record: rebuilding it per placement
            # copies one attribute per member of the fleet for nothing.
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

  # Rows an entry produces: an absent entry of a set, and the warning that the
  # membership of that set is in this entry's key.
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

  # A configuration file names its bytes and never carries them: the mode, the
  # units the module named for reloading, and one disposition. A digest is
  # recorded only over material the plan itself holds, so a recipe carrying a
  # reference gets a hash over its fragments and reference paths and no digest
  # over assembled bytes.
  #
  # A file rendered over a set with an absent entry is recorded as not computed
  # rather than hashed over the entries that do have values.
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

      # The guard covers the identity too, because a hash is where a fragment
      # is forced and a module's own expression is what raises.
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
        # The recipe is not read at all: a file rendered over a set with an
        # absent entry has no bytes to hash, and hashing the entries that do
        # have values is the fold this folder exists to refuse.
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

  # Every string of one entry, with where in the entry it was written. The
  # closure is declared, and this is what stops the declaration from drifting
  # away from what the entry actually mentions.
  mentionSites =
    {
      units,
      configData,
      placement,
    }:
    util.mapAttrsToList (name: unit: {
      where = "unit ${util.quote name}";
      value = removeAttrs unit [
        "env"
        "extends"
      ];
    }) units
    ++ util.mapAttrsToList (name: unit: {
      where = "the environment of unit ${util.quote name}";
      value = unit.env or { };
    }) units
    ++ util.mapAttrsToList (name: unit: {
      where = "an extension of unit ${util.quote name}";
      value = unit.extends or { };
    }) units
    ++ util.mapAttrsToList (path: file: {
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
        where = "generated file ${util.quote "${gen}/${fname}"}";
        value = file.path;
      }) files
    ) placement.vars
    ++ util.concatMapAttrsToList (
      cap: record:
      util.mapAttrsToList (ename: e: {
        where = "export ${util.quote "${cap}.${ename}"}";
        value = e.value;
      }) record.exports
    ) placement.capabilities;

  # The declared roots against what the entry mentions. An undeclared mention
  # is an error, because the closure is the list a consumer populates a
  # filesystem from; a root nothing mentions is a warning, because it is either
  # dead weight or a path assembled at runtime worth having written down.
  closureRows =
    {
      subject,
      storeDir,
      declared,
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

      # Both directions are a lookup rather than a scan. An entry that renders
      # one path per member of a set-valued read mentions as many paths as it
      # declares roots, and crossing those two lists with `elem` is the square
      # of the fleet for a plan that stayed linear in it.
      declaredSet = util.stringSet declared;
      mentionedSet = util.stringSet (map (m: m.path) mentioned);
      undeclared = filter (m: !util.inStringSet declaredSet m.path) mentioned;
      unmentioned = filter (root: !util.inStringSet mentionedSet root) declared;
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
    ) unmentioned;

  # One placement of one member. The key is a hash of the instance, the
  # service, the machine, the target it was planned for, the pin its roots were
  # built from, its units, the store paths it declares, the values it was
  # handed and the keys it depends on.
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
      rows =
        configData.rows
        ++ closureRows {
          inherit subject;
          storeDir = resolved.storeDir;
          declared = closure;
          sites = mentionSites {
            inherit units placement;
            configData = configData.record;
          };
        }
        ++ entryRows {
          inherit subject member;
        };
      value =
        pruned {
          key = util.shortHash (builtins.toJSON keyInput);
          inherit
            closure
            dependsOn
            reads
            units
            env
            ;
          storeDir = resolved.storeDir;
          placement = member.placementRecord;
          alloc = if member.alloc.ports == { } then { } else { inherit (member.alloc) ports; };
          vars = varsRecord placement;
          configData = configData.record;
          provides = providesRecord {
            inherit readers placement;
          };
          settings = {
            ${mname} = settingsRecord member;
          };
        }
        // (if target == null then { } else { inherit target; })
        // (if pin == null then { } else { inherit pin; });
    };

  # A member no placement selected. It runs nowhere, so its entry carries no
  # machine, no closure and nothing it depends on.
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

  # The whole plan: one entry per placement, one entry per machine that carries
  # a placement, and a dependency written as a key that appears in the plan
  # beside the depended-on entry's own key hash.
  entries =
    resolved:
    let
      readers = readerIndex resolved;

      # One hash per machine record rather than one per entry placed on it.
      machineKeys = mapAttrs (_: machineKey) resolved.machines;

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
      plan = machineEntries // listToAttrs serviceEntries;
      rows = concatLists (map (e: e.rows) serviceEntries);
    };
}
