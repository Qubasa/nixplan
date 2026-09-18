# Plan emission: entries, keys and the rows an entry produces. A plan is flat,
# keyed and free of expressions. Nothing here is a derivation and every store path
# is a literal string.
{
  util,
  diag,
  module,
}:
let
  inherit (builtins)
    all
    any
    attrValues
    concatLists
    concatMap
    concatStringsSep
    elem
    filter
    head
    isAttrs
    isList
    isString
    length
    mapAttrs
    tail
    ;

  pruned = entry: util.filterAttrs (_: v: !((isAttrs v && v == { }) || (isList v && v == [ ]))) entry;
in
rec {
  machineKey = record: util.shortHash (builtins.toJSON record);

  # Every delivered read of the deployment, flat: the edge it came from, one
  # provider entry it names, and the consuming entries that named it. Walked once
  # because the two indexes below are two `groupBy` projections of it, and a walk
  # of its own for each is a second traversal of the whole deployment per plan.
  deliveredReads =
    resolved:
    util.eachMember resolved (
      iname: mname: member:
      let
        consumers = entryKeysOf iname mname member;
      in
      util.concatMapAttrsToList (
        slotName: edge:
        if !edge.delivered then
          [ ]
        else
          map (providerKey: {
            inherit
              slotName
              edge
              providerKey
              consumers
              ;
          }) edge.entryKeys
      ) member.edges
    );

  # Every reader of every export, as a flat index, so a capability can record who
  # reads it without walking the deployment again.
  readerIndex =
    reads:
    let
      rows = concatMap (
        r:
        let
          absent = r.edge.entryAbsences.${r.providerKey} or [ ];
        in
        map (ename: {
          key = "${r.providerKey}|${r.edge.capability}|${ename}";
          inherit (r) consumers;
          rows = map (subject: {
            id = "set-entry-absent";
            inherit subject;
          }) (if elem ename absent then r.consumers else [ ]);
        }) r.edge.reads
      ) reads;
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
  # the value differs from the one the field resolves to unstated: a plan written
  # before the fields existed keys as it did, stating a default states nothing,
  # and a deployment that states a mode delivers a different artifact and says so.
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

  # The ownership a record resolves to unstated, and the projection that removes
  # every field sitting at it. One rule for the two file records this library
  # carries; a configuration file's mode has no default, so it is always keyed.
  ownershipKeys = [
    "owner"
    "group"
    "mode"
  ];

  ownershipDefaults = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  withoutDefaults =
    defaults: record:
    removeAttrs record (filter (k: defaults ? ${k} && record.${k} == defaults.${k}) ownershipKeys);

  fileKeyInput = file: withoutDefaults ownershipDefaults (fileRecord file);

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
    reads:
    let
      rows = concatMap (
        r:
        util.concatMapAttrsToList (
          ename: varsFile:
          map (consumer: {
            key = varsFile.entry;
            reason = "${consumer} named ${ename} in uses.${r.slotName}.reads";
            machine = machineOf consumer;
          }) r.consumers
        ) (r.edge.entryVarsFiles.${r.providerKey} or { })
      ) reads;
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

  # A unit the plan reads runs unconfined as the account it declares, and one
  # declaring none is root, so both spellings of root open anything. The image
  # reader asks the same rule with the other answer, because a confining profile
  # imposes an account and never imposes root.
  admits = util.admits { rootAdmitted = true; };

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

  # A unit that cannot open a configuration file its own entry shows it. The same
  # predicate as the row above and a second identifier, because the subject and
  # the resolution differ: one names a slot and a provider's generator, this one
  # names the entry's own declaration. A file the reading recorded no mode for is
  # `config-file-mode-missing` already, and there is no record to compare.
  configUnreadableRows =
    {
      subject,
      units,
      configData,
    }:
    util.concatMapAttrsToList (
      path: file:
      if !isString file.mode then
        [ ]
      else
        util.concatMapAttrsToList (
          unitName: unit:
          util.optional (!(admits unit file)) (
            diag.error {
              inherit subject;
              id = "entry-config-file-unreadable-by-user";
              message = "unit ${util.quote unitName} of ${util.quote subject} runs as ${util.quote unit.user} and is shown ${util.quote path}, whose record is ${util.quote "${file.owner}:${file.group}"} at mode ${util.quote file.mode}";
              evidence = "the mode admits its owner, a member of its group where the unit declares that group, and nobody else, so the unit starts and fails with `EACCES` on ${util.quote path}";
              resolution = "declare `owner`, `group` or `mode` on that configuration file so ${util.quote unit.user} may open it, or run the unit as ${util.quote file.owner}";
            }
          )
        ) units
    ) configData;

  # The third site the one readability predicate is asked at: a file of the
  # entry's own generator that one of the entry's own units names. A unit that
  # cannot open a file the plan told it to read starts under no realiser, so the
  # row belongs to the layer holding the plan, and a confinement profile
  # imposing an account stays a second condition about that imposed account.
  ownValueUnreadableRows =
    {
      subject,
      units,
      placement,
    }:
    let
      # One scan per unit rather than one per unit and file: the unit is read for
      # the value paths it names and each of the entry's own files is a lookup.
      namedBy = mapAttrs (_: unit: util.stringSet (util.varsPathsDeep unit)) units;
    in
    util.concatMapAttrsToList (
      gen: files:
      util.concatMapAttrsToList (
        fname: file:
        if !file.deploy then
          [ ]
        else
          util.concatMapAttrsToList (
            unitName: unit:
            if !(util.inStringSet namedBy.${unitName} file.path) || admits unit file then
              [ ]
            else
              [
                (diag.error {
                  inherit subject;
                  id = "entry-value-unreadable-by-user";
                  message = "unit ${util.quote unitName} of ${util.quote subject} runs as ${util.quote unit.user} and names ${util.quote file.path}, the file ${util.quote "${gen}/${fname}"} of its own generator, delivered as ${util.quote "${file.owner}:${file.group}"} at mode ${util.quote file.mode}";
                  evidence = "the mode admits its owner, a member of its group where the unit declares that group, and nobody else, so the unit starts and fails with `EACCES` on ${util.quote file.path}";
                  resolution = "declare `owner`, `group` or `mode` on that generated file so ${util.quote unit.user} may open it, or run the unit as ${util.quote file.owner}";
                })
              ]
          ) units
      ) files
    ) placement.vars;

  # A configuration file names its bytes and never carries them. A digest covers
  # only material the plan itself holds, and a file rendered over a set with an
  # absent entry is recorded as not computed rather than hashed over the rest.
  #
  # A fragment's own value is read for its kind here rather than in the reading
  # of the declaration, because this is where it is coerced and because the
  # reading runs before the reads a fragment may be built from are resolved.
  malformedFragments =
    file:
    if file.disposition == "render" then
      filter (item: !isString (item.text or item.ref)) file.render
    else
      [ ];

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
        fallback = {
          record = { };
          malformed = { };
        };
        value =
          let
            malformed = mapAttrs (_: malformedFragments) placement.configData;
          in
          {
            inherit malformed;
            record = mapAttrs (
              path: file:
              {
                inherit (file)
                  mode
                  owner
                  group
                  reload
                  ;
                computed = true;
              }
              // (if malformed.${path} == [ ] then fileIdentity file else { })
            ) placement.configData;
          };
      };

      record =
        if complete then
          guarded.value.record
        else
          mapAttrs (_: file: {
            inherit (file)
              mode
              owner
              group
              reload
              ;
            computed = false;
            row = {
              id = "set-entry-absent";
              inherit subject;
            };
          }) placement.configData;

      fragmentRows = util.concatMapAttrsToList (
        path: items:
        util.optional (items != [ ]) (
          diag.error {
            inherit subject;
            id = "config-file-render-item";
            message = "configuration file ${util.quote path} of ${util.quote subject} declares a recipe with ${
              util.countNoun (builtins.length items) "fragment" "fragments"
            } whose value is not a string";
            evidence = "a recipe's fragments are concatenated into the bytes, so a value of another kind is a coercion no recovery catches; the file's bytes are not recorded";
            resolution = "write a string for every `text` and every `ref` of that recipe in the module that declares it";
          }
        )
      ) guarded.value.malformed;
    in
    {
      inherit record;
      rows = if complete then guarded.rows ++ fragmentRows else [ ];
      keyInput = mapAttrs (_: withoutDefaults (removeAttrs ownershipDefaults [ "mode" ])) record;
    };

  # A knob the settings reading refused is in no record and in no key: its value
  # cannot be serialised, and the module that was handed it is the only reader
  # left.
  keyableSettings = member: removeAttrs member.settings.values member.settings.unkeyable;

  settingsRecord =
    member:
    mapAttrs (k: v: {
      value = v;
      source = member.settings.sources.${k};
    }) (keyableSettings member);

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

  # Every path a scan finds in the strings of an entry's own sites, beside the
  # site that named it. Two scans ask it, one for value paths and one for store
  # paths, and both read the entry's own strings rather than the fleet's values.
  pathsNamedIn =
    scan: sites:
    concatMap (
      site:
      map (path: {
        inherit path;
        inherit (site) where;
      }) (scan site.value)
    ) sites;

  # A path a machine does not hold. A value reaches a machine through the owner's
  # placements and the declared reads and through nothing else, so a site of a
  # placed entry that names the path of a value its machine does not receive
  # names a path that resolves to nothing: what the machine reports when the unit
  # fails to start names neither the value nor the declaration, which is the
  # whole reason the row exists.
  #
  # A value no machine receives is the instance of this rule where the delivery
  # set is empty, and keeps the identifier it had: there the resolution is to
  # deploy the generator, and here it is to declare the read. The rule widens no
  # delivery set - naming a path never puts a machine in one, or a routable
  # secret would be bounded by nobody.
  misdeliveredRows =
    {
      subject,
      machine,
      values,
      sites,
    }:
    let
      # The scan reads the paths a site names and looks each up, so the cost is
      # the entry's own strings rather than the entry against every value of the
      # fleet. A per-placement value's path carries the instance and not the
      # machine, so one path names one value per machine and the question a
      # lookup answers is whether any value at that path reaches this one.
      named = pathsNamedIn util.varsPathsDeep sites;

      opened = filter (
        m: values ? ${m.path} && !(any (v: elem machine v.delivery) values.${m.path})
      ) named;
    in
    map (
      m:
      let
        group = values.${m.path};
        value = head group;
        delivered = util.sortStrings (util.uniqueStrings (concatMap (v: v.delivery) group));
      in
      if delivered == [ ] then
        diag.error {
          inherit subject;
          id = "vars-not-deployed-opened";
          message = "${subject} names ${util.quote m.path} in ${m.where}, and no machine receives that value";
          evidence = "generator ${util.quote value.gen} of ${value.module} declares `deploy = false`, so one value exists and the path it is read at holds nothing";
          resolution = "declare that generator deployed in ${value.module}, or stop naming ${util.quote "${value.gen}/${value.fname}"} in ${m.where}";
        }
      else
        diag.error {
          inherit subject;
          id = "vars-path-off-delivery-set";
          message = "${subject} names ${util.quote m.path} in ${m.where}, and machine ${util.quote machine} does not receive ${util.quote value.valueKey}";
          evidence = "that value is delivered to ${util.quoteList delivered}, and a delivery set is what the owner's placements and the declared reads make it, so a mention resolves to nothing rather than widening it";
          resolution = "declare a read of the export backed by ${util.quote "${value.gen}/${value.fname}"} in this member, or stop naming that path in ${m.where}";
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
      mentioned = pathsNamedIn scan sites;

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

  # The three host resources the plan already records, and the row two claimants
  # of one machine claiming one of them earn. A claimant is a placed entry or the
  # machine's own reservation. Two writers of one file and two listeners on one
  # port are contradictions, while a shared directory is destructive for
  # `runtimeDirectory` and a handoff a deployment may intend for
  # `stateDirectory`, so the third is a warning and the build still happens.
  hostResources = {
    paths = {
      id = "entry-host-path-claimed-twice";
      row = diag.error;
      what = claim: "declare a configuration file at ${util.quote claim}";
      evidence = "a host path holds one file, so the entry applied last is the one whose rendering survives and the others are overwritten with nothing saying so";
      resolution =
        {
          claim,
          machine,
          reserved,
        }:
        if reserved then
          "derive ${util.quote claim} from the entry's own identity, which an implementation is handed as `instance` and `member`, or delete it from `reserves.paths` of machine ${util.quote machine} in the registry, which is where the machine states it holds the file"
        else
          "derive ${util.quote claim} from the entry's own identity, which an implementation is handed as `instance` and `member`, or place the entries on different machines";
    };
    ports = {
      id = "entry-port-claimed-twice";
      row = diag.error;
      what =
        claim:
        "claim the port ${util.quote (toString claim.fixed)} on ${protoText claim} and ${addressText claim}";
      evidence = "one machine carries one listener per protocol, port and address, and a claim stating no protocol or no address claims every one of them, so every entry after the first cannot bind and the failure names neither declaration";
      resolution =
        {
          claim,
          machine,
          reserved,
        }:
        if reserved then
          "claim a `fixed` port other than ${util.quote (toString claim.fixed)}, derived from the entry's own identity an implementation is handed as `instance` and `member`, state an `address` so it binds another address, or delete it from `reserves.ports` of machine ${util.quote machine} in the registry, which is where the machine states it listens there"
        else
          "claim a `fixed` port other than ${util.quote (toString claim.fixed)} in one of them, derived from the entry's own identity an implementation is handed as `instance` and `member`, state an `address` in each so the two bind different addresses, or place the entries on different machines";
    };
    directories = {
      id = "entry-unit-directory-shared";
      row = diag.warning;
      what = claim: "record the unit directory ${util.quote claim}";
      evidence = "the service manager deletes a runtime directory when its unit restarts, so two entries sharing one lose each other's files, and a shared state directory is a handoff only where both declarations intend one";
      resolution =
        { claim, ... }:
        "derive ${util.quote claim} from the entry's own identity, which an implementation is handed as `instance` and `member`, or leave it shared where both entries intend the handoff";
    };
  };

  hostResourceKinds = builtins.attrNames hostResources;

  # A unit directory is a claim however it was declared: the three fields the unit
  # vocabulary carries, and whatever an extension application records under the
  # same names, under any backend, read the way a unit's declared groups are. The
  # claim carries the field it was recorded under, because a state directory and
  # a runtime directory of one name are two paths on the machine.
  directoryFields = util.sortStrings (builtins.attrNames module.directoryKinds);

  claimedUnder =
    fields: field:
    let
      declared = fields.${field} or null;
    in
    if isList declared then
      map (name: "${field}/${name}") (filter isString declared)
    else if isString declared then
      [ "${field}/${declared}" ]
    else
      [ ];

  directoriesOf =
    unit:
    concatMap (claimedUnder unit) directoryFields
    ++ util.concatMapAttrsToList (_: fields: concatMap (claimedUnder fields) directoryFields) (
      unit.extends or { }
    );

  # How a port claim reads in a row. A field the claim leaves unstated is every
  # value of it, which is what the claim means and what the comparison made of
  # it, so the row says so rather than naming an absence.
  protoText =
    claim:
    if claim.proto == null then
      "every protocol of the domain"
    else
      "protocol ${util.quote claim.proto}";

  addressText =
    claim:
    if claim.address == null then
      "every address of the machine"
    else
      "address ${util.quote claim.address}";

  # A port claim compares as the record the reading normalised: the number, the
  # protocol and the address, each already held to its domain, so the index
  # compares no value the vocabulary refused and repairs none.
  portsOf = member: attrValues member.declaration.claims.ports;

  # One entry's claims, flat, each naming the claimant. Deduplication is per
  # entry and happens here rather than after the collision test: two units of one
  # entry recording one directory is one claim, the claimant being the entry. A
  # path and a directory are their own group, and a port claim is a record whose
  # group is its number, the rest of it being compared inside the group.
  claimsOf =
    entry:
    if !(entry ? claims) then
      [ ]
    else
      concatMap (
        kind:
        let
          ports = kind == "ports";
          claimed = entry.claims.${kind};
        in
        map (claim: {
          key = entry.name;
          inherit (entry.claims) machine;
          inherit kind claim;
          group = if ports then toString claim.fixed else claim;
        }) (if ports then util.distinct claimed else util.uniqueStrings claimed)
      ) hostResourceKinds;

  # Two claims of one machine and one number contend when their protocols
  # overlap and their addresses do, an unstated field being every value of it.
  overlap =
    field: a: b:
    a.${field} == null || b.${field} == null || a.${field} == b.${field};

  contends = a: b: overlap "proto" a b && overlap "address" a b;

  # What two overlapping claims contend over: the stated side of each field,
  # since an unstated one is every value and so never the narrower.
  contention = a: b: {
    inherit (a) fixed;
    proto = if a.proto == null then b.proto else a.proto;
    address = if a.address == null then b.address else a.address;
  };

  # An address is non-empty wherever it is stated, so the empty half of this key
  # is the absence and nothing else.
  spelling = claim: "${toString claim.proto} ${toString claim.address}";

  unorderedPairs =
    xs:
    if xs == [ ] then
      [ ]
    else
      map (other: {
        a = head xs;
        b = other;
      }) (tail xs)
      ++ unorderedPairs (tail xs);

  # One row for one collision, subjected to the first claimant in plan key
  # order. A claim an entry makes twice is the entry's own, so the row is owed
  # only where two claimants claim, and a claimant is a placed entry or the
  # machine's own reservation.
  collisionRow =
    {
      machine,
      kind,
      claim,
      claimants,
    }:
    let
      keys = util.sortStrings (util.uniqueStrings claimants);
      resource = hostResources.${kind};
    in
    util.optional (builtins.length keys > 1) (
      resource.row {
        inherit (resource) id evidence;
        subject = head keys;
        message = "${util.quoteList keys} all ${resource.what claim} on machine ${util.quote machine}";
        resolution = resource.resolution {
          inherit claim machine;
          reserved = elem "machine:${machine}" keys;
        };
      }
    );

  # One number's claims on one machine, compared inside the group: identical
  # spellings are one bucket and one collision however many claimants they have,
  # and two buckets whose spellings overlap are another, each row naming its own
  # protocol and address. A healthy group holds one claim, so the pairwise step
  # does no work.
  portCollisions =
    machine: claimants:
    let
      buckets = builtins.groupBy (c: spelling c.claim) claimants;
      each = map (name: buckets.${name}) (builtins.attrNames buckets);
      keysOf = bucket: map (c: c.key) bucket;
      port =
        claim: bucket:
        collisionRow {
          inherit machine claim;
          kind = "ports";
          claimants = bucket;
        };
    in
    concatMap (bucket: port (head bucket).claim (keysOf bucket)) each
    ++ concatMap (
      pair:
      let
        a = (head pair.a).claim;
        b = (head pair.b).claim;
      in
      if contends a b then port (contention a b) (keysOf pair.a ++ keysOf pair.b) else [ ]
    ) (unorderedPairs each);

  # A machine's own claims: the host resources it states its image already holds.
  # The key is the machine record's, which is a plan key and no entry's, so the
  # reservation enters the same ordering without a rule of its own. A reserved
  # port is the claim record an entry's claim is, so one comparison reads both.
  reservedBy =
    machine: reserved:
    let
      claimed = kind: claim: group: {
        key = "machine:${machine}";
        inherit
          machine
          kind
          claim
          group
          ;
      };
      port =
        p:
        claimed "ports" {
          fixed = p.number;
          inherit (p) proto address;
        } (toString p.number);
    in
    map port (attrValues reserved.ports) ++ map (path: claimed "paths" path path) reserved.paths;

  # Every proper ancestor directory of a host path, so nesting is read by looking
  # a path's own ancestors up in the set of claimed paths: that costs the claims
  # and their depth rather than their square, which is the shape the rest of this
  # index already has.
  ancestorsOf =
    path:
    let
      walked =
        builtins.foldl'
          (acc: seg: {
            prefix = "${acc.prefix}/${seg}";
            out = acc.out ++ [ "${acc.prefix}/${seg}" ];
          })
          {
            prefix = "";
            out = [ ];
          }
          (filter (s: isString s && s != "") (builtins.split "/" path));
    in
    filter (p: p != path) walked.out;

  # Two shown paths of one machine where one is a parent directory of the other
  # cannot both exist: one declaration asks for a file where the other asks for
  # the directory holding it. Nesting is the contradiction equality is, observed
  # one directory up, so it is refused beside it and here rather than in a
  # builder, which meets it while creating a store object and can name a store
  # path and no declaration.
  nestingRows =
    machine: onMachine:
    let
      paths = filter (c: c.kind == "paths") onMachine;
      claimed = util.stringSet (map (c: c.claim) paths);
      claimantsOf =
        path: util.sortStrings (util.uniqueStrings (map (c: c.key) (filter (c: c.claim == path) paths)));
    in
    concatMap (
      c:
      map (
        parent:
        let
          inner = claimantsOf c.claim;
          outer = claimantsOf parent;
        in
        diag.error {
          subject = head (util.sortStrings (util.uniqueStrings (inner ++ outer)));
          id = "entry-host-path-nested";
          message = "${util.quoteList inner} shows ${util.quote c.claim} on machine ${util.quote machine}, inside ${util.quote parent}, which ${util.quoteList outer} shows as a file";
          evidence = "a realiser carries a file at every host path it is shown, so one of the two asks for a file where the other asks for the directory holding it, and the builder that meets it names a store path and no declaration";
          resolution = "show one of the two at a path outside the other, or show the directory's own files instead of the directory";
        }
      ) (filter (p: util.inStringSet claimed p) (ancestorsOf c.claim))
    ) paths;

  # A host resource two claimants of one machine both claim. The claims are one
  # flat list grouped twice, by machine and then by resource, so the check costs
  # the claims rather than their square, and one member placed on two machines
  # claims under two machines rather than against itself.
  collisionRows =
    claims:
    util.concatMapAttrsToList (
      machine: onMachine:
      nestingRows machine onMachine
      ++ util.concatMapAttrsToList (
        _: claimants:
        let
          claimed = head claimants;
        in
        if claimed.kind == "ports" then
          portCollisions machine claimants
        else
          collisionRow {
            inherit machine;
            inherit (claimed) kind claim;
            claimants = map (c: c.key) claimants;
          }
      ) (builtins.groupBy (c: "${c.kind} ${c.group}") onMachine)
    ) (builtins.groupBy (c: c.machine) claims);

  # The key hashes the instance, the service, the machine, the target, the pin, the
  # units, the store paths the entry declares, the values it was handed and the
  # keys it depends on.
  placedEntry =
    {
      readers,
      values,
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
        configData = configData.keyInput;
        settings = keyableSettings member;
        alloc = member.alloc.ports;
      };
    in
    {
      name = subject;
      family = "service";
      claimant = "the entry of member ${util.quote mname} of instance ${util.quote iname} on machine ${util.quote machine}";
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
        ++ misdeliveredRows {
          inherit subject machine values;
          # The module's own vars and exports are declarations rather than sites
          # that open a path, so only the units and the files are scanned.
          sites = filter (site: site.kind != "declaration") sites;
        }
        ++ entryRows {
          inherit subject member;
        }
        ++ unreadableRows {
          inherit subject member units;
        }
        ++ ownValueUnreadableRows {
          inherit subject units placement;
        }
        ++ configUnreadableRows {
          inherit subject units;
          configData = configData.record;
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
        settings = keyableSettings member;
      };
    in
    {
      name = subject;
      family = "service";
      claimant = "the unplaced entry of member ${util.quote mname} of instance ${util.quote iname}";
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

  # A delivered ownership a user scope cannot honor. Read off the record rather
  # than off the declaration, which is the same comparison the value's key
  # already makes: a field sitting at the default it resolves to unstated states
  # nothing, and a field off it is what the delivery would have to chown. A
  # stated `mode` earns nothing, the account being free to chmod what it owns.
  ownershipInUserScopeRows =
    {
      scopeOf,
      varsEntries,
    }:
    concatMap (
      e:
      concatMap (
        machine:
        if scopeOf machine != "user" then
          [ ]
        else
          util.concatMapAttrsToList (
            fname: file:
            map (
              field:
              diag.error {
                subject = e.name;
                id = "value-ownership-in-user-scope";
                message = "the generated file ${util.quote fname} of ${util.quote e.name} states ${field} ${util.quote file.${field}}, and it is delivered to ${util.quote machine}, which is deployed as an account rather than as root";
                evidence = "a delivery writes the file as the account it connects as and cannot chown it to another, so a stated ownership is a fact the scope cannot honor; a stated `mode` is honoured, the account being free to chmod what it owns";
                resolution = "drop ${util.quote field} from that generated file in ${e.owner.module}, or deliver the value to machines whose scope is ${util.quote "system"}";
              }
            ) (filter (field: file.${field} != ownershipDefaults.${field}) ownedFields)
          ) e.value.files
      ) e.value.delivery
    ) varsEntries;

  ownedFields = [
    "owner"
    "group"
  ];

  # A machine a delivered value reaches whose registry record states no seal
  # recipient. Produced here because the delivery set is the fact the row is
  # about - the machines the owning member is placed on plus the machine of
  # every entry that declares a read - and one row per machine however many
  # values reach it, the same fact produced twice being one row.
  #
  # A warning and not an error: the deployment is realisable, the delivery
  # works, and what that machine lacks is only the ability to put its own values
  # back after a reboot, which is a property no deployment had before the
  # recipient existed. It is delivered to exactly as it was: plaintext only.
  unsealedDeliveryRows =
    {
      sealRecipientOf,
      varsEntries,
    }:
    util.mapAttrsToList
      (
        machine: delivered:
        diag.warning {
          subject = "machine:${machine}";
          id = "machine-receives-a-value-unsealed";
          message = "machine ${util.quote machine} receives ${
            util.quoteList (util.sortStrings (util.uniqueStrings (map (d: d.valueKey) delivered)))
          } and declares no `sealRecipient`";
          evidence = "a delivered value lands under a root a reboot empties, and a machine declaring no recipient is handed no sealed copy to put it back from, so every value it holds is gone until an operator applies again";
          resolution = "mint an identity on ${util.quote machine} and paste the public line at `sealRecipient` in its registry record, or accept that its values are restored by an apply";
        }
      )
      (
        builtins.groupBy (d: d.machine) (
          concatMap (
            e:
            map (machine: {
              inherit machine;
              valueKey = e.name;
            }) (filter (machine: sealRecipientOf machine == null) e.value.delivery)
          ) varsEntries
        )
      );

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

      # One projection of a placement's values per machine rather than one per
      # generated value: every generator of one placement indexes the same two.
      varsRecords = mapAttrs (_: varsRecord) member.placed;
      keyFiles = mapAttrs (_: varsKeyFiles) member.placed;

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
          files = varsRecords.${owner}.${gen}.files;
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
            files = keyFiles.${owner}.${gen};
            inherit dependsOn;
            machine = if g.per == "instance" then null else owner;
          }
          // (if g.program == null then { } else { inherit (g) program; });
        in
        {
          name = subject;
          family = "value";
          claimant = "the generated value of generator ${util.quote gen} of instance ${util.quote iname}";
          # Who declared it, for the row a mention of its path off the delivery
          # set earns: the plan record carries neither the generator's name nor
          # the module that declared it.
          owner = {
            inherit gen;
            module = member.moduleLabel;
          };
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
      reads = deliveredReads resolved;
      readers = readerIndex reads;
      valueReaders = valueReaderIndex reads;

      machineKeys = mapAttrs (_: machineKey) resolved.machines;

      varsEntries = util.eachMember resolved (
        iname: mname: member:
        varsEntriesOf {
          inherit
            valueReaders
            machineKeys
            iname
            mname
            member
            ;
        }
      );

      # Every file of every value the plan carries, with the delivery set it was
      # given: the one index the mention scan asks its machine question of.
      values = builtins.groupBy (v: v.path) (
        concatMap (
          e:
          util.mapAttrsToList (fname: file: {
            inherit fname;
            inherit (file) path;
            inherit (e.owner) gen module;
            valueKey = e.name;
            inherit (e.value) delivery;
          }) e.value.files
        ) varsEntries
      );

      serviceEntries = util.eachMember resolved (
        iname: mname: member:
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
                values
                resolved
                machineKeys
                iname
                mname
                member
                machine
                ;
            }
          ) member.placements
      );
      usedMachines = resolved.usedMachines;

      machineRecords = map (machine: {
        name = "machine:${machine}";
        family = "machine";
        claimant = "the record of machine ${util.quote machine}";
        value = pruned (
          {
            key = machineKeys.${machine};
            inherit (resolved.machines.${machine}) address tags;
            # An explicit absence, beside the address and outside the key: the
            # recipient is read in the projection no key hashes, and `pruned`
            # keeps a null the way it keeps a placed entry's `closure`, because
            # an absent field means the plan does not know. A reader has to be
            # able to tell a machine that seals nothing from a record written
            # before the field existed. It rides the literal rather than an
            # update of its own, one `//` per machine record being a counter the
            # gate measures.
            sealRecipient = resolved.sealRecipients.${machine} or null;
          }
          // util.pickAttrs [
            "system"
            "serviceManager"
            "microarchitecture"
            "scope"
          ] (util.filterAttrs (_: v: v != null) resolved.machines.${machine})
        );
      }) usedMachines;

      # The three families live under one keyspace, and a key two of them claim
      # is refused here rather than resolved by the merge that used to build the
      # plan: `//` let the last family silently replace the first, which left a
      # placed entry's provenance edge naming a key that was no longer a
      # machine. The families are told apart by what a record holds and never by
      # the text of a key, `machine` being a legal instance name and `vars/x` a
      # legal member name, so the collision is refused where the keyspace is
      # built.
      #
      # The order below is the precedence a collision is resolved with, and the
      # first claimant keeps the key: a machine's record is what every placed
      # entry's `dependsOn` already names.
      claimants = machineRecords ++ varsEntries ++ serviceEntries;

      byKey = builtins.groupBy (c: c.name) claimants;

      # Two records of one family under one key are the fact a row of that
      # family already reports - two members claiming one generator name, two
      # members of one name - so the row owed here is the one nobody else can
      # make: two families claiming one key.
      keyCollisionRows = util.concatMapAttrsToList (
        key: claiming:
        if length (util.uniqueStrings (map (c: c.family) claiming)) < 2 then
          [ ]
        else
          [
            (diag.error {
              subject = key;
              id = "plan-key-claimed-twice";
              message = "the plan key ${util.quote key} is claimed by ${
                concatStringsSep " and " (map (c: c.claimant) claiming)
              }";
              evidence = "a plan key names one record, and a reader takes a key apart to recover what an entry is: ${(head claiming).claimant} is the record the key names and every other claimant of it is in no plan";
              resolution = "rename one of them so each names a key of its own";
            })
          ]
      ) byKey;
    in
    {
      plan = mapAttrs (_: claiming: (head claiming).value) byKey;
      rows =
        concatLists (map (e: e.rows) serviceEntries)
        ++ keyCollisionRows
        ++ ownershipInUserScopeRows {
          inherit varsEntries;
          scopeOf = machine: (resolved.machines.${machine} or { }).scope or "system";
        }
        ++ unsealedDeliveryRows {
          inherit varsEntries;
          sealRecipientOf = machine: resolved.sealRecipients.${machine} or null;
        }
        ++ collisionRows (
          concatMap claimsOf serviceEntries
          ++ concatMap (machine: reservedBy machine resolved.reservations.${machine}) usedMachines
        );
    };
}
