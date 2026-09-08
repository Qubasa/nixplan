# Resolution: settings, placement, allocation, wires and exports.
#
# The rounds this subset runs are 1, 2, 3, 6 and 7 of the adopted eight. Round 4
# needs a fact register, round 5 needs a locality, and round 8's plane
# derivation collapses to one rule because no atom carries a lifecycle.
#
# Wires resolve per member rather than per placement: a slot's value is a
# function of the wired capability's placements and of nothing about the
# reader's machine, so resolving it once per reader is what keeps a set-valued
# read linear in the fleet rather than square in it.
{
  util,
  diag,
  interface,
  module,
  compose,
  excluded,
  platform,
}:
let
  inherit (builtins)
    all
    attrNames
    concatLists
    elem
    filter
    head
    length
    mapAttrs
    ;

  instanceKeys = [
    "module"
    "settings"
    "placement"
    "wire"
    "exposes"
    "severity"
  ];

  everyKeys = [
    "machines"
    "tags"
  ];

  machineRegistryKeys = [
    "address"
    "tags"
    "system"
    "serviceManager"
    "microarchitecture"
  ];

  # The two a placement on a machine needs to have a derivable target at all.
  machineTargetKeys = [
    "system"
    "serviceManager"
  ];

  safe = diag.guard;
in
{
  resolve =
    {
      reg,
      instances,
      machines,
      varsState,
      sources,
      storeDir,
    }:
    let
      deploymentFile = sources.deployment;
      machinesFile = sources.machines;
      instanceNames = attrNames instances;
      machineNames = attrNames machines;

      moduleFileOf =
        iname:
        sources.modules.${iname}
          or "the module file of instance ${util.quote iname} (not recorded in the `sources.modules` argument of mkPlan)";

      leafFileOf = iname: mname: sources.leaves.${iname}.${mname} or null;

      # Machines by tag, indexed once for the whole deployment: a selector then
      # asks for a tag rather than scanning the registry per member per tag.
      machinesByTag = builtins.groupBy (p: p.tag) (
        concatLists (
          util.mapAttrsToList (
            machine: decl:
            map (tag: { inherit tag machine; }) (if builtins.isList (decl.tags or [ ]) then decl.tags else [ ])
          ) machines
        )
      );

      tagged = tag: map (p: p.machine) (machinesByTag.${tag} or [ ]);

      # One elaboration per distinct system and microarchitecture rather than
      # one per machine, so the cost scales with the architectures in the fleet.
      # The elaboration is a module of nixpkgs and a system string it cannot
      # parse raises, so it is forced inside a guard like a module's own value.
      targeted = util.filterAttrs (_: decl: decl ? system && builtins.isString decl.system) machines;

      microOf = decl: if decl ? microarchitecture then toString decl.microarchitecture else "";

      platformGuards = mapAttrs (
        system: names:
        builtins.listToAttrs (
          map (micro: {
            name = micro;
            value = safe {
              subject = machinesFile;
              what = "the platform record of ${util.quote system}";
              fallback = null;
              value = platform.record {
                inherit system;
                microarchitecture = if micro == "" then null else micro;
              };
            };
          }) (util.uniqueStrings (map (m: microOf machines.${m}) names))
        )
      ) (builtins.groupBy (m: machines.${m}.system) (attrNames targeted));

      platformOf = decl: platformGuards.${decl.system}.${microOf decl}.value;

      platformRows = concatLists (
        util.mapAttrsToList (
          _: byMicro: concatLists (util.mapAttrsToList (_: g: g.rows) byMicro)
        ) platformGuards
      );

      # Which machines a placement selected, which is what makes an incomplete
      # registry entry a row rather than a warning about a machine nobody uses.
      #
      # One walk of the deployment, indexed by machine, because the two
      # questions asked of it - which machines carry a placement, and which
      # entries one machine carries - are the same walk twice otherwise.
      placementsByMachine = builtins.groupBy (p: p.machine) (
        concatLists (
          util.mapAttrsToList (
            iname: inst:
            concatLists (
              util.mapAttrsToList (
                mname: m:
                map (machine: {
                  inherit machine;
                  entry = "${iname}:${mname}";
                }) m.placements
              ) inst.members
            )
          ) resolved.instances
        )
      );

      selectedMachines = attrNames placementsByMachine;

      machineRows =
        util.concatMapAttrsToList (
          name: decl:
          map (
            key:
            module.keyRow {
              subject = machinesFile;
              where = "machine ${util.quote name}";
              inherit key;
              allowed = machineRegistryKeys;
            }
          ) (util.extraKeys machineRegistryKeys decl)
        ) machines
        ++ map (
          incomplete:
          diag.error {
            subject = machinesFile;
            id = "machine-target-incomplete";
            message = "machine ${util.quote incomplete.name} declares no ${util.quoteList incomplete.missing}, and a placement on it has no derivable target";
            evidence = "a machine declares the system it runs and the service manager that runs its units, and ${
              util.countNoun (length (placementsOn incomplete.name)) "entry" "entries"
            } are placed on it";
            resolution = "declare ${util.quoteList incomplete.missing} for ${util.quote incomplete.name} in ${machinesFile}";
          }
        ) incompleteMachines
        ++ platformRows;

      # The two keys a target needs are read once per selected machine, rather
      # than once to decide the row and again to write it.
      incompleteMachines = filter (m: m.missing != [ ]) (
        map (name: {
          inherit name;
          missing = filter (k: !(machines.${name} ? ${k})) machineTargetKeys;
        }) selectedMachines
      );

      placementsOn = machine: map (p: p.entry) (placementsByMachine.${machine} or [ ]);

      machineRecords = mapAttrs (
        _: decl:
        {
          address = decl.address or null;
          tags = util.sortStrings (decl.tags or [ ]);
          system = decl.system or null;
          serviceManager = decl.serviceManager or null;
        }
        // (if decl ? microarchitecture then { inherit (decl) microarchitecture; } else { })
      ) machines;

      # The target a placement on this machine was planned for: the reduced
      # platform record, the service manager that runs its units and the
      # address it is reached at. A machine that declares neither a system nor
      # a service manager has none, and a module that dereferences it hits a
      # missing attribute, which is the trade a refused read already makes.
      #
      # The address is here rather than beside `target` because a unit may be
      # rendered from it, and a target is what an entry's key hashes: a field a
      # module can render from and the key does not cover is a key that does
      # not describe the entry.
      targetOf =
        machine:
        let
          decl = machines.${machine} or { };
          hasSystem = decl ? system && platformOf decl != null;
        in
        if !hasSystem && !(decl ? serviceManager) then
          null
        else
          (if hasSystem then { system = platformOf decl; } else { })
          // (if decl ? serviceManager then { inherit (decl) serviceManager; } else { })
          // (if decl ? address then { inherit (decl) address; } else { });

      # One target record per machine rather than one per placement: a target
      # is a function of the machine, and an entry's key hashes it.
      targets = mapAttrs (name: _: targetOf name) machines;

      # One instance: its root, its members, where each member is placed and
      # which of its capabilities are addressable from outside.
      mkInstance =
        iname: idecl:
        let
          # The resolver `service` is closed over: the only place that knows the
          # deployment file and the subject a settings row names.
          root = compose.mkRoot idecl.module (
            {
              name,
              defaults,
              fixed,
            }:
            compose.resolveSettings {
              inherit
                name
                defaults
                fixed
                deploymentFile
                moduleFile
                ;
              subject = "${iname}:${name}";
              settings = idecl.settings or { };
            }
          );
          moduleFile = moduleFileOf iname;
          rootProvides = root.provides or { };
          members = root.services or { };
          memberNames = attrNames members;
          exposes = idecl.exposes or [ ];
          subject = "${iname}:instance";

          placement = idecl.placement or { };
          every = placement.every or { };

          placementRows =
            map (
              key:
              module.keyRow {
                inherit subject key;
                where = "instance ${util.quote iname}";
                allowed = [ "every" ];
              }
            ) (util.extraKeys [ "every" ] placement)
            ++ map (
              m:
              diag.error {
                inherit subject;
                id = "placement-unknown-member";
                message = "${deploymentFile} places ${util.quote m} in instance ${util.quote iname}, which its root does not own";
                evidence = "the root in ${moduleFile} owns ${util.quoteList memberNames}";
                resolution = "place one of ${util.quoteList memberNames} in ${deploymentFile}";
              }
            ) (util.subtractList (attrNames every) memberNames);

          exposeRows = map (
            cap:
            diag.error {
              inherit subject;
              id = "exposes-unknown-capability";
              message = "instance ${util.quote iname} exposes ${util.quote cap}, which its root does not provide";
              evidence = "the root in ${moduleFile} provides ${util.quoteList (attrNames rootProvides)}";
              resolution = "expose one of ${util.quoteList (attrNames rootProvides)} in ${deploymentFile}, or re-export ${util.quote cap} in ${moduleFile}";
            }
          ) (util.subtractList exposes (attrNames rootProvides));

          instanceRows =
            map (
              key:
              module.keyRow {
                inherit subject key;
                where = "instance ${util.quote iname}";
                allowed = instanceKeys;
              }
            ) (util.extraKeys instanceKeys idecl)
            ++ util.optional (idecl ? severity) (
              module.severityRow {
                inherit subject;
                where = "instance ${util.quote iname}";
              }
            )
            ++ compose.namespaceRows {
              inherit subject deploymentFile moduleFile;
              members = memberNames;
              settings = idecl.settings or { };
            }
            ++ placementRows
            ++ exposeRows;
        in
        {
          inherit
            iname
            root
            moduleFile
            rootProvides
            memberNames
            ;
          exposed = util.filterAttrs (n: _: elem n exposes) rootProvides;
          exposedNames = filter (n: rootProvides ? ${n}) exposes;
          wire = idecl.wire or { };
          rows = instanceRows;
          members = mapAttrs (_mname: member: mkMember iname idecl member) members;
        };

      # One member: its declaration read with resolved settings, its placements
      # and its allocation.
      mkMember =
        iname: idecl: member:
        let
          mname = member.name;
          subject = "${iname}:${mname}";
          leafFile = leafFileOf iname mname;
          moduleSubject = if leafFile != null then leafFile else subject;
          moduleLabel =
            if leafFile != null then
              leafFile
            else
              "the module of ${util.quote mname} in instance ${util.quote iname} (not recorded in the `sources.leaves` argument of mkPlan)";

          settings = member.settings;

          declaration = module.read {
            inherit reg;
            subject = moduleSubject;
            module = moduleLabel;
            declaration = member.declaration;
          };

          # What a capability's interface says about itself: a function of the
          # member, so the registry is searched once per capability rather than
          # once per capability per placement. `label` stays a thunk, because a
          # capability that declares no interface has a row of its own and this
          # is only ever forced by row text.
          capabilityFacts = mapAttrs (
            _: declared:
            let
              iface = declared.interface;
            in
            {
              declaredNames = if iface == null then [ ] else interface.exportNames iface;
              declaringFile = if iface == null then null else interface.fileOf reg iface;
              interfaceName = if iface == null then null else iface.name;
              label = interface.label reg iface;
            }
          ) declaration.provides;

          every = (idecl.placement or { }).every or { };
          selector = every.${mname} or null;
          named = if selector == null then [ ] else selector.machines or [ ];
          tags = if selector == null then [ ] else selector.tags or [ ];
          unknownMachines = filter (m: !(machines ? ${m})) named;
          placements = util.uniqueStrings (
            filter (m: machines ? ${m}) (named ++ concatLists (map tagged tags))
          );

          placementRecord = {
            reason = "every";
          }
          // (if named == [ ] then { } else { machines = named; })
          // (if tags == [ ] then { } else { inherit tags; });

          placementRows =
            (
              if selector == null then
                [ ]
              else
                map (
                  key:
                  module.keyRow {
                    inherit subject key;
                    where = "the placement of ${util.quote mname} in instance ${util.quote iname}";
                    allowed = everyKeys;
                  }
                ) (util.extraKeys everyKeys selector)
            )
            ++ map (
              m:
              diag.error {
                inherit subject;
                id = "placement-unknown-machine";
                message = "${deploymentFile} places ${util.quote "${iname}:${mname}"} on ${util.quote m}, which the machine registry does not hold";
                evidence = "${machinesFile} holds ${util.quoteList machineNames}";
                resolution = "add ${util.quote m} to ${machinesFile}, or name a registered machine in ${deploymentFile}";
              }
            ) unknownMachines
            ++ util.optional (placements == [ ] && unplaced.units != { }) (
              diag.error {
                inherit subject;
                id = "member-not-placed";
                message = "${util.quote "${iname}:${mname}"} is placed on no machine, so nothing it declares runs anywhere";
                evidence =
                  if selector == null then
                    "${deploymentFile} writes no `placement.every.${mname}` for instance ${util.quote iname}"
                  else
                    "the selector names machines ${util.quoteList named} and tags ${util.quoteList tags}, and neither matched a registered machine";
                resolution = "write `placement.every.${mname}` in ${deploymentFile} with a machine or a tag that matches";
              }
            )
            ++ map (
              m:
              diag.error {
                inherit subject;
                id = "placement-platform-mismatch";
                message = "${deploymentFile} places ${util.quote "${iname}:${mname}"} on ${util.quote m}, which runs ${
                  util.quote (toString machines.${m}.system)
                } and the module declares ${util.quoteList declaration.platforms}";
                evidence = "a module states the platforms it runs on and the machine registry states what a machine runs, and the two are crossed after placement is decided rather than believed from either side";
                resolution = "place ${util.quote mname} on a machine running one of ${util.quoteList declaration.platforms} in ${deploymentFile}, or declare ${
                  util.quote (toString machines.${m}.system)
                } in ${moduleSubject}";
              }
            ) mismatchedPlacements;

          # An empty `platforms` is every system, so a module that never had to
          # care is not made to. A machine with no declared system is the
          # registry's row rather than this one.
          mismatchedPlacements =
            if declaration.platforms == [ ] then
              [ ]
            else
              filter (m: machines.${m} ? system && !elem machines.${m}.system declaration.platforms) placements;

          alloc = {
            ports = mapAttrs (_: claim: claim.fixed) declaration.claims.ports;
          };

          edges = mapAttrs (
            slotName: slot:
            mkEdge {
              inherit
                iname
                mname
                slotName
                slot
                ;
              wire = (idecl.wire or { }).${slotName} or null;
            }
          ) declaration.uses;

          results = mapAttrs (_: edge: edge.value) (util.filterAttrs (_: edge: edge.delivered) edges);

          unplaced = mkPlacement {
            inherit iname mname;
            machine = null;
          };

          memberRows =
            map (
              key:
              module.keyRow {
                inherit subject key;
                where = "member ${util.quote mname} of instance ${util.quote iname}";
                allowed = [
                  "module"
                  "defaults"
                  "fixed"
                ];
              }
            ) member.unknownKeys
            ++ settings.rows
            ++ declaration.rows
            ++ placementRows
            ++ util.concatMapAttrsToList (_: edge: edge.rows) edges;
        in
        {
          inherit
            mname
            leafFile
            moduleLabel
            declaration
            capabilityFacts
            settings
            alloc
            placements
            placementRecord
            edges
            results
            subject
            unplaced
            ;
          # An unplaced member is the entry the plan carries when nothing
          # matched, so its rows are the table's too: a keyset the module got
          # wrong is a row whether or not the service reached a machine.
          rows = memberRows ++ (if placements == [ ] then unplaced.rows else [ ]);
          placed = builtins.listToAttrs (
            map (machine: {
              name = machine;
              value = mkPlacement {
                inherit
                  iname
                  mname
                  machine
                  ;
              };
            }) placements
          );
        };

      # One placement: the vars the machine holds, the capabilities it
      # publishes, and what its impl produced.
      mkPlacement =
        {
          iname,
          mname,
          machine,
        }:
        let
          member = resolved.instances.${iname}.members.${mname};
          entryKey = if machine == null then "${iname}:${mname}" else "${iname}:${mname}@${machine}";
          state = if machine == null then { } else varsState.${machine} or { };

          # A module reads `vars.<generator>.<file>`. The declaration writes
          # `vars.<generator>.files.<file>`, because a generator has more to
          # declare than its files; a reader only ever wants the files.
          vars = mapAttrs (
            gen: g:
            mapAttrs (
              fname: fdecl:
              let
                fileState = state.${gen}.${fname} or { };
                present = fileState.present or false;
                secrecy = interface.secrecyOf fdecl;
              in
              {
                __varsFile = true;
                inherit present secrecy;
                path = "/run/vars/${gen}/${fname}";
                content = if present && secrecy != "secret" then fileState.content or null else null;
              }
            ) g.files
          ) member.declaration.vars.generators;

          target = if machine == null then null else targets.${machine};

          implArgs = {
            inherit machine vars;
            instance = iname;
            settings = member.settings.values;
            alloc = member.alloc;
            results = member.results;
          }
          // (if target == null then { } else { inherit target; });

          impl = if member.declaration.impl == null then null else member.declaration.impl implArgs;

          # The implementation half is read the way the declaration half is: an
          # unrecognised key is a row rather than a value quietly discarded, and
          # reading stays total, so one malformed unit does not stop the rest.
          #
          # Only the shape is forced here. A configuration file's fragments are
          # forced where its identity is computed, because a recipe rendered
          # over a set with an absent entry has no bytes to force at all.
          implShape = safe {
            subject = entryKey;
            what = "the implementation of ${entryKey}";
            fallback = null;
            value = if impl == null then true else builtins.isAttrs impl;
          };

          implRaised = implShape.rows != [ ];
          implNotAttrs = !implRaised && implShape.value == false;
          implValue = if impl == null || implRaised || implNotAttrs then { } else impl;

          unitsRaw = safe {
            subject = entryKey;
            what = "the units of ${entryKey}";
            fallback = { };
            value = implValue.units or { };
          };

          unitsGiven = util.filterAttrs (_: u: builtins.isAttrs u) unitsRaw.value;
          unitNames = util.sortStrings (attrNames unitsGiven);
          unitSet = util.stringSet unitNames;

          units = mapAttrs (
            name: unit:
            module.readUnit {
              inherit
                reg
                unitNames
                unitSet
                name
                unit
                ;
              subject = entryKey;
              module = member.moduleLabel;
            }
          ) unitsGiven;

          configGiven = util.filterAttrs (_: f: builtins.isAttrs f) (implValue.configData or { });

          configFiles = mapAttrs (
            path: file:
            module.readConfigFile {
              inherit
                unitNames
                unitSet
                path
                file
                ;
              subject = entryKey;
              module = member.moduleLabel;
            }
          ) configGiven;

          closureRaw = safe {
            subject = entryKey;
            what = "the closure of ${entryKey}";
            fallback = [ ];
            value = implValue.closure or [ ];
          };

          closureIsList = builtins.isList closureRaw.value && all builtins.isString closureRaw.value;

          malformed =
            map (name: "unit ${util.quote name}") (
              attrNames (util.filterAttrs (_: u: !builtins.isAttrs u) unitsRaw.value)
            )
            ++ map (path: "configuration file ${util.quote path}") (
              attrNames (util.filterAttrs (_: f: !builtins.isAttrs f) (implValue.configData or { }))
            );

          # An extension whose backend is not the machine's service manager is
          # refused here and still recorded under its own backend, so a binding
          # for that backend refuses knowingly rather than dropping fields.
          backendRows = concatLists (
            util.mapAttrsToList (
              uname: u:
              map (
                e:
                diag.error {
                  subject = entryKey;
                  id = "unit-extension-backend-mismatch";
                  message = "unit ${util.quote uname} of ${entryKey} applies ${e.label}, whose backend is ${util.quote e.backend}, and ${util.quote machine} runs ${util.quote (toString target.serviceManager)}";
                  evidence = "an extension adds the fields of one service manager, and the target of a placement is the machine the placement selected";
                  resolution = "apply the extension only where `target.serviceManager` is ${util.quote e.backend} in ${member.moduleLabel}, or place the member on a machine that runs it";
                }
              ) (filter (e: e.backend != target.serviceManager) u.extensions)
            ) units
          );

          capabilities = mapAttrs (
            cap: declared:
            mkCapability {
              inherit
                iname
                mname
                entryKey
                cap
                declared
                ;
              facts = member.capabilityFacts.${cap};
              published = if impl == null then { } else impl.provides.${cap}.exports or { };
            }
          ) member.declaration.provides;
        in
        {
          inherit
            entryKey
            vars
            capabilities
            target
            ;
          units = mapAttrs (_: u: u.record) units;
          configData = mapAttrs (_: f: f.record) configFiles;
          closure = if closureIsList then util.uniqueStrings closureRaw.value else [ ];
          rows =
            implShape.rows
            ++ unitsRaw.rows
            ++ closureRaw.rows
            ++ map (
              key:
              module.keyRow {
                subject = entryKey;
                where = "the implementation of ${member.moduleLabel}";
                inherit key;
                allowed = module.implKeys;
                id = "implementation-unknown-key";
              }
            ) (util.extraKeys module.implKeys implValue)
            ++ util.optional implNotAttrs (
              diag.error {
                subject = entryKey;
                id = "implementation-malformed";
                message = "the implementation of ${member.moduleLabel} returned a value that is not an attribute set";
                evidence = "an implementation returns ${util.quoteList module.implKeys} and nothing else";
                resolution = "return an attribute set from `impl` in ${member.moduleLabel}";
              }
            )
            ++ map (
              what:
              diag.error {
                subject = entryKey;
                id = "implementation-malformed";
                message = "${what} of ${member.moduleLabel} is not an attribute set";
                evidence = "a unit is a record of the unit vocabulary and a configuration file is a record naming its bytes, so neither is a bare string";
                resolution = "write a record in ${member.moduleLabel}";
              }
            ) malformed
            ++ util.optional (implValue ? closure && !closureIsList) (
              diag.error {
                subject = entryKey;
                id = "closure-malformed";
                message = "the implementation of ${member.moduleLabel} declares a closure that is not a list of strings";
                evidence = "a closure root is a literal store path string, and the roots are what a consumer populates a filesystem from";
                resolution = "declare `closure = [ <root> … ];` in ${member.moduleLabel}";
              }
            )
            ++ (if target == null || !(target ? serviceManager) then [ ] else backendRows)
            ++ util.concatMapAttrsToList (_: u: u.rows) units
            ++ util.concatMapAttrsToList (_: f: f.rows) configFiles
            ++ util.concatMapAttrsToList (_: c: c.rows) capabilities;
        };

      # One capability at one placement: keyset equality against its interface,
      # a type check per export, and absence recorded rather than dropped.
      mkCapability =
        {
          iname,
          mname,
          entryKey,
          cap,
          declared,
          facts,
          published,
        }:
        let
          member = resolved.instances.${iname}.members.${mname};
          iface = declared.interface;
          publishingFile = member.moduleLabel;
          guard = safe {
            subject = entryKey;
            what = "the exports of capability ${util.quote cap} of ${entryKey}";
            fallback = { };
            value = published;
          };
          raw = guard.value;
          inherit (facts) declaredNames;
          publishedNames = attrNames raw;
          missing = util.subtractList declaredNames publishedNames;
          extra = util.subtractList publishedNames declaredNames;

          exportRecord =
            ename:
            let
              atom = iface.exports.${ename};
              secrecy = interface.secrecyOf atom;
              value = raw.${ename};
              absent = value == null || (util.isVarsFile value && !value.present);
              typeError = if absent then null else atom.type.verify value;
            in
            {
              inherit
                ename
                secrecy
                absent
                ;
              value = if util.isVarsFile value then value.path else value;
              plane = if secrecy == "secret" then "reference" else "env";
              rows = util.optional (typeError != null) (
                diag.error {
                  subject = entryKey;
                  id = "export-type-mismatch";
                  message = "${entryKey} publishes ${util.quote "${cap}.${ename}"} with a value that fails its atom's type";
                  evidence = "${facts.label} declares ${ename} as ${util.quote atom.type.name}, and korora reports: ${toString typeError}";
                  resolution = "publish a value of that type in ${publishingFile}, or change the atom on the interface";
                }
              );
            };

          exports = builtins.listToAttrs (
            map (ename: {
              name = ename;
              value = exportRecord ename;
            }) (filter (e: raw ? ${e}) declaredNames)
          );
        in
        {
          inherit
            exports
            missing
            extra
            ;
          interface = iface;
          inherit (facts) declaringFile interfaceName;
          keysetEqualsInterface = missing == [ ] && extra == [ ];
          rows =
            guard.rows
            ++ map (
              ename:
              diag.error {
                subject = entryKey;
                id = "provider-export-missing";
                message = "${entryKey} declares ${facts.label} and publishes no ${util.quote ename}";
                evidence = "the interface declares ${util.quoteList declaredNames} and ${publishingFile} publishes ${util.quoteList publishedNames}";
                resolution = "publish ${util.quote ename} in ${publishingFile}, or declare a different interface";
              }
            ) missing
            ++ map (
              ename:
              diag.error {
                subject = entryKey;
                id = "provider-export-extra";
                message = "${entryKey} publishes ${util.quote ename}, which ${facts.label} does not declare";
                evidence = "the interface declares ${util.quoteList declaredNames}; the extra export is delivered to nobody";
                resolution = "delete ${util.quote ename} from ${publishingFile}, or declare an interface that carries it";
              }
            ) extra
            ++ util.concatMapAttrsToList (_: e: e.rows) exports;
        };

      # One slot: the wire, the far end, the interface identity, the arity and
      # the values the consumer receives.
      mkEdge =
        {
          iname,
          mname,
          slotName,
          slot,
          wire,
        }:
        let
          subject = "${iname}:${mname}";
          consumerFile = resolved.instances.${iname}.members.${mname}.moduleLabel;
          ifaceLabel =
            if slot.interface == null then "the slot's interface" else interface.label reg slot.interface;

          isMemberCut =
            wire != null
            && !(wire ? instance)
            && builtins.any (v: builtins.isAttrs v && v ? instance) (builtins.attrValues wire);

          target = if wire == null then null else wire.instance or null;
          capName = if wire == null then null else wire.provides or null;
          targetInstance =
            if target != null && instances ? ${target} then resolved.instances.${target} else null;
          capability =
            if targetInstance == null || capName == null then
              null
            else
              targetInstance.exposed.${capName} or null;

          providerMember = if capability == null then null else targetInstance.members.${capability.member};
          placements = if providerMember == null then [ ] else providerMember.placements;

          interfaceMatches =
            capability != null && slot.interface != null && slot.interface == capability.interface;

          readsAt =
            machine:
            let
              record = providerMember.placed.${machine}.capabilities.${capability.capability};
              picked = builtins.listToAttrs (
                map (r: {
                  name = r;
                  value = if record.exports ? ${r} then record.exports.${r}.value else null;
                }) slot.reads
              );
              absentReads = filter (r: !(record.exports ? ${r}) || record.exports.${r}.absent) slot.reads;
            in
            {
              inherit absentReads;
              key = "${capability.member}@${machine}";
              entryKey = "${target}:${capability.member}@${machine}";
              values = picked;
            };

          collected = map readsAt placements;
          absentEntries = filter (c: c.absentReads != [ ]) collected;

          arityOk =
            interfaceMatches && (if slot.reach == "all" then placements != [ ] else length placements == 1);

          delivered = slot.resolvable && wire != null && !isMemberCut && capability != null && arityOk;

          value =
            if slot.reach == "all" then
              builtins.listToAttrs (
                map (c: {
                  name = c.entryKey;
                  value = c.values;
                }) collected
              )
            else
              (head collected).values;

          rows =
            util.optional (wire == null) (
              diag.error {
                inherit subject;
                id = "slot-unwired";
                message = "slot ${util.quote slotName} of ${util.quote subject} is wired by no deployment, so it resolves to no value at all";
                evidence = "${consumerFile} declares the slot against ${ifaceLabel}, and ${deploymentFile} writes no `wire.${slotName}` for instance ${util.quote iname}";
                resolution = "write `wire.${slotName} = { instance = <instance>; provides = <capability>; };` in ${deploymentFile}";
              }
            )
            ++ util.optional isMemberCut (
              diag.error {
                inherit subject;
                id = "declaration-excluded-key";
                message = "${deploymentFile} wires ${util.quote slotName} of instance ${util.quote iname} per member, which this subset does not carry";
                evidence = "the condition that introduces it: ${excluded.constructs.memberWire.trigger}";
                resolution = "write one `wire.${slotName}` naming an instance and a capability in ${deploymentFile}";
              }
            )
            ++ util.optional (wire != null && !isMemberCut && targetInstance == null) (
              diag.error {
                inherit subject;
                id = "wire-unknown-instance";
                message = "${deploymentFile} wires ${util.quote slotName} of instance ${util.quote iname} to instance ${util.quote (toString target)}, which the deployment does not declare";
                evidence = "the deployment declares ${util.quoteList instanceNames}";
                resolution = "name one of ${util.quoteList instanceNames} in ${deploymentFile}";
              }
            )
            ++ util.optional (targetInstance != null && capability == null) (
              if targetInstance.rootProvides ? ${capName} then
                diag.error {
                  inherit subject;
                  id = "wire-capability-not-exposed";
                  message = "${deploymentFile} wires ${util.quote slotName} to ${util.quote "${target}.${capName}"}, which instance ${util.quote target} provides and does not expose";
                  evidence = "instance ${util.quote target} exposes ${util.quoteList targetInstance.exposedNames}";
                  resolution = "add ${util.quote capName} to the `exposes` list of instance ${util.quote target} in ${deploymentFile}";
                }
              else
                diag.error {
                  inherit subject;
                  id = "wire-unknown-capability";
                  message = "${deploymentFile} wires ${util.quote slotName} to ${util.quote "${target}.${toString capName}"}, which instance ${util.quote target} does not expose";
                  evidence = "instance ${util.quote target} exposes ${util.quoteList targetInstance.exposedNames} and its root provides ${util.quoteList (attrNames targetInstance.rootProvides)}";
                  resolution = "wire one of ${util.quoteList targetInstance.exposedNames} in ${deploymentFile}";
                }
            )
            ++ util.optional (capability != null && slot.interface != null && !interfaceMatches) (
              diag.error {
                inherit subject;
                id = "interface-mismatch";
                message = "slot ${util.quote slotName} of ${util.quote subject} declares ${ifaceLabel} and ${util.quote "${target}.${capName}"} declares ${interface.label reg capability.interface}";
                evidence =
                  if capability.interface.name == slot.interface.name then
                    "the two interfaces carry one name and are different values, which is why a row renders the declaring file beside the name"
                  else
                    "an interface is identified by the value an author imported, never by its name";
                resolution = "import the interface the far end declares into ${consumerFile}, or wire a capability that declares this one";
              }
            )
            ++ util.optional (interfaceMatches && slot.reach != "all" && length placements != 1) (
              diag.error {
                inherit subject;
                id = "reach-one-placement-count";
                message = "slot ${util.quote slotName} of ${util.quote subject} declares reach ${util.quote "one"} and ${util.quote "${target}.${capName}"} has ${
                  util.countNoun (length placements) "placement" "placements"
                }";
                evidence = "the wired capability is placed on ${util.quoteList placements}, and the count is checked after placement is decided rather than believed from the deployment";
                resolution = "declare `reach = \"all\"` in ${consumerFile} and index by machine, or place the far end once in ${deploymentFile}";
              }
            )
            ++ util.optional (interfaceMatches && slot.reach == "all" && placements == [ ]) (
              diag.error {
                inherit subject;
                id = "reach-all-no-placement";
                message = "slot ${util.quote slotName} of ${util.quote subject} declares reach ${util.quote "all"} and ${util.quote "${target}.${capName}"} is placed nowhere";
                evidence = "a set-valued read names its entries, and there are no placements to name";
                resolution = "place the far end in ${deploymentFile}";
              }
            );
        in
        {
          inherit
            delivered
            rows
            absentEntries
            ;
          reach = slot.reach;
          reads = slot.reads;
          wire = if wire == null || isMemberCut then null else { inherit (wire) instance provides; };
          capability = if capability == null then null else capability.capability;
          providerMember = if capability == null then null else capability.member;
          providerInstance = target;
          entryKeys = map (c: c.entryKey) collected;
          entryAbsences = builtins.listToAttrs (
            map (c: {
              name = c.entryKey;
              value = c.absentReads;
            }) collected
          );
          value = if delivered then value else null;
        };

      resolved = {
        instances = mapAttrs mkInstance instances;
        machines = machineRecords;
        usedMachines = selectedMachines;
        inherit storeDir;
        rows =
          machineRows
          ++ util.concatMapAttrsToList (
            _: inst:
            inst.rows
            ++ util.concatMapAttrsToList (
              _: member: member.rows ++ util.concatMapAttrsToList (_: p: p.rows) member.placed
            ) inst.members
          ) resolved.instances;
      };
    in
    resolved;
}
