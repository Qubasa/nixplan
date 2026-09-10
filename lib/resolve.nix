# Resolution: settings, placement, allocation, wires and exports.
#
# A wire resolves per member rather than per placement. A slot's value is a
# function of the wired capability's placements and of nothing about the reader's
# machine, so resolving it once per reader keeps a set-valued read linear in the
# fleet instead of square in it.
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

  machineTargetKeys = [
    "system"
    "serviceManager"
  ];

  safe = diag.guard;

  # The half of a declaration a deployment writes, read with the shape it has to
  # have. The module half routes every read through a check that rows, and this
  # is that check for the other half: an absent key the reading needs and a value
  # of the wrong kind are each a row and a fallback, so one malformed declaration
  # is reported and the rest of the deployment is still read. `builtins.tryEval`
  # catches neither an abort nor a missing attribute, so a bare read here would
  # end the evaluation instead of filling a row.
  shapes = {
    root = {
      what = "a module function or a record";
      is = v: builtins.isFunction v || builtins.isAttrs v;
    };
    record = {
      what = "a record";
      is = builtins.isAttrs;
    };
    names = {
      what = "a list of names";
      is = v: builtins.isList v && all builtins.isString v;
    };
    name = {
      what = "a name";
      is = builtins.isString;
    };
  };

  shownValue =
    v: if builtins.isString v then util.quote v else "a value of type ${builtins.typeOf v}";

  declaredField =
    {
      subject,
      file,
      where,
      record,
      field,
      shape,
      fallback,
      required ? false,
    }:
    let
      present = record ? ${field};
      wrong = present && !(shape.is record.${field});
    in
    {
      value = if present && !wrong then record.${field} else fallback;
      rows =
        if wrong then
          [
            (diag.error {
              inherit subject;
              id = "declaration-field-malformed";
              message = "${where} declares ${util.quote field} as ${shownValue record.${field}}, and the reading needs ${shape.what}";
              evidence = "the half of a declaration a deployment writes is read with the tolerance the half a module writes is read with, so a value of the wrong kind is a row and the rest of the deployment is still read";
              resolution = "write ${shape.what} for ${util.quote field} in ${file}, or omit the key";
            })
          ]
        else if !present && required then
          [
            (diag.error {
              inherit subject;
              id = "declaration-field-missing";
              message = "${where} declares no ${util.quote field}, and the reading needs ${shape.what} there";
              evidence = "a key the reading needs is not one it can default, so its absence is reported rather than read as an empty value";
              resolution = "write `${field} = …;` for ${where} in ${file}";
            })
          ]
        else
          [ ];
    };

  # The root of an instance that declares none: it owns no member and provides
  # nothing, so the rest of the deployment reads it as an instance with no
  # services rather than as an evaluation that ended.
  emptyRoot = _: { };
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

      # A name is held to the grammar the key it enters can carry, in the reading
      # of each and before any key is built from it. The thing named is then left
      # out of everything a key is derived from, so no delivery set and no entry
      # key can name something the deployment never declared.
      fileSubject = file: if diag.isValidSubject file then file else deploymentFile;

      nameRow =
        {
          file,
          what,
          named,
        }:
        diag.error {
          subject = fileSubject file;
          id = "name-carries-key-separator";
          message = "${what} is named ${util.quote named}, and a name a plan key is built from carries none of ${util.quoteList util.keySeparators}";
          evidence = "a plan key is `<instance>:<member>@<machine>` and a generated value's is `<instance>:vars/<generator>@<machine>`, so a name carrying one of them produces a key that takes apart into parts nothing declared, or a service entry under a value entry's key";
          resolution = "rename ${util.quote named} in ${file} to a name carrying none of ${util.quoteList util.keySeparators}";
        };

      badMachineNames = filter util.carriesKeySeparator machineNames;
      badInstanceNames = filter util.carriesKeySeparator instanceNames;

      placeable = machine: machines ? ${machine} && !(util.carriesKeySeparator machine);

      nameRows =
        map (
          name:
          nameRow {
            file = machinesFile;
            what = "a machine of the registry";
            named = name;
          }
        ) badMachineNames
        ++ map (
          name:
          nameRow {
            file = deploymentFile;
            what = "an instance of the deployment";
            named = name;
          }
        ) badInstanceNames
        ++ concatLists (
          util.mapAttrsToList (
            iname: inst:
            map (
              name:
              nameRow {
                file = moduleFileOf iname;
                what = "a member of the root of instance ${util.quote iname}";
                named = name;
              }
            ) inst.badMemberNames
          ) resolved.instances
        );

      # Every field of the machine registry, read once with its shape. A machine
      # is the deployment's own declaration, so a value of the wrong kind is a
      # row here rather than a type error deep inside an elaboration.
      machineFieldOf =
        name: field: shape: fallback:
        declaredField {
          subject = machinesFile;
          file = machinesFile;
          where = "machine ${util.quote name}";
          record = machines.${name};
          inherit field shape fallback;
        };

      machineFields = mapAttrs (name: _: {
        address = machineFieldOf name "address" shapes.name null;
        tags = machineFieldOf name "tags" shapes.names [ ];
        system = machineFieldOf name "system" shapes.name null;
        serviceManager = machineFieldOf name "serviceManager" shapes.name null;
        microarchitecture = machineFieldOf name "microarchitecture" shapes.name null;
      }) machines;

      machineFieldRows = concatLists (
        util.mapAttrsToList (
          _: fields: concatLists (util.mapAttrsToList (_: f: f.rows) fields)
        ) machineFields
      );

      # Machines by tag, indexed once for the whole deployment, so a selector asks
      # for a tag instead of scanning the registry per member per tag.
      machinesByTag = builtins.groupBy (p: p.tag) (
        concatLists (
          util.mapAttrsToList (
            machine: _:
            if placeable machine then
              map (tag: { inherit tag machine; }) machineFields.${machine}.tags.value
            else
              [ ]
          ) machines
        )
      );

      tagged = tag: map (p: p.machine) (machinesByTag.${tag} or [ ]);

      # One elaboration per distinct system and microarchitecture rather than one
      # per machine. The elaboration is nixpkgs' own and raises on a system string
      # it cannot parse, so it is forced inside a guard like a module's own value.
      targeted = util.filterAttrs (name: _: machineFields.${name}.system.value != null) machines;

      microOf =
        name:
        let
          declared = machineFields.${name}.microarchitecture.value;
        in
        if declared == null then "" else declared;

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
          }) (util.uniqueStrings (map microOf names))
        )
      ) (builtins.groupBy (m: machineFields.${m}.system.value) (attrNames targeted));

      platformOf =
        name:
        let
          system = machineFields.${name}.system.value;
        in
        if system == null then null else platformGuards.${system}.${microOf name}.value;

      platformRows = concatLists (
        util.mapAttrsToList (
          _: byMicro: concatLists (util.mapAttrsToList (_: g: g.rows) byMicro)
        ) platformGuards
      );

      # One walk of the deployment, indexed by machine, because which machines
      # carry a placement and which entries one machine carries would otherwise be
      # the same walk twice.
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
        ++ platformRows
        ++ machineFieldRows;

      incompleteMachines = filter (m: m.missing != [ ]) (
        map (name: {
          inherit name;
          missing = filter (k: !(machines.${name} ? ${k})) machineTargetKeys;
        }) selectedMachines
      );

      placementsOn = machine: map (p: p.entry) (placementsByMachine.${machine} or [ ]);

      machineRecords = mapAttrs (
        name: _:
        let
          fields = machineFields.${name};
        in
        {
          address = fields.address.value;
          tags = util.sortStrings fields.tags.value;
          system = fields.system.value;
          serviceManager = fields.serviceManager.value;
        }
        // (
          if fields.microarchitecture.value == null then
            { }
          else
            { microarchitecture = fields.microarchitecture.value; }
        )
      ) machines;

      # The target a placement was planned for. The address sits inside it because
      # a unit may be rendered from the address, and an entry's key hashes the
      # target: a field a module can render from and the key does not cover would
      # be a key that does not describe the entry.
      targetOf =
        machine:
        let
          fields = machineFields.${machine} or null;
          platformRecord = if fields == null then null else platformOf machine;
          serviceManager = if fields == null then null else fields.serviceManager.value;
          address = if fields == null then null else fields.address.value;
        in
        if platformRecord == null && serviceManager == null then
          null
        else
          (if platformRecord == null then { } else { system = platformRecord; })
          // (if serviceManager == null then { } else { inherit serviceManager; })
          // (if address == null then { } else { inherit address; });

      targets = mapAttrs (name: _: targetOf name) machines;

      # The placement table of each instance, read once with its shape: the
      # instance's own rows and every member's selector come off one reading.
      placementOf = mapAttrs (
        iname: idecl:
        let
          subject = "${iname}:instance";
          placement = declaredField {
            inherit subject;
            file = deploymentFile;
            where = "instance ${util.quote iname}";
            record = idecl;
            field = "placement";
            shape = shapes.record;
            fallback = { };
          };
          every = declaredField {
            inherit subject;
            file = deploymentFile;
            where = "the placement of instance ${util.quote iname}";
            record = placement.value;
            field = "every";
            shape = shapes.record;
            fallback = { };
          };
        in
        {
          placement = placement.value;
          every = every.value;
          rows = placement.rows ++ every.rows;
        }
      ) instances;

      mkInstance =
        iname: idecl:
        let
          instanceField =
            field: shape: fallback: required:
            declaredField {
              subject = "${iname}:instance";
              file = deploymentFile;
              where = "instance ${util.quote iname}";
              record = idecl;
              inherit
                field
                shape
                fallback
                required
                ;
            };

          declaredRoot = instanceField "module" shapes.root emptyRoot true;
          declaredExposes = instanceField "exposes" shapes.names [ ] false;
          declaredWire = instanceField "wire" shapes.record { } false;
          placed = placementOf.${iname};

          root = compose.mkRoot declaredRoot.value (
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
          declaredMembers = root.services or { };
          badMemberNames = filter util.carriesKeySeparator (attrNames declaredMembers);
          members = util.filterAttrs (name: _: !(util.carriesKeySeparator name)) declaredMembers;
          memberNames = attrNames members;

          # A member's identity is the attribute key it is declared under, and
          # `service`'s name argument is row text. A capability records the name
          # its member passed, so it is read back to the key here: placement,
          # settings and every plan key are then one spelling.
          keyOfDeclaredName = builtins.listToAttrs (
            map (key: {
              name = members.${key}.name;
              value = key;
            }) memberNames
          );
          rootProvides = mapAttrs (_: p: p // { member = keyOfDeclaredName.${p.member} or p.member; }) (
            root.provides or { }
          );

          misnamedMembers = filter (key: members.${key}.name != key) memberNames;
          nameDisagreementRows = map (
            key:
            diag.error {
              inherit subject;
              id = "member-name-disagrees";
              message = "the root of instance ${util.quote iname} declares a member under ${util.quote key} that names itself ${
                util.quote (toString members.${key}.name)
              }";
              evidence = "a member has one identity and it is the attribute key: placement, the settings namespace and every plan key are read from it, so a second spelling is a member nothing else can address";
              resolution = "write `${key} = service ${util.quote key} { … };` in ${moduleFile}, or declare the member under ${
                util.quote (toString members.${key}.name)
              }";
            }
          ) misnamedMembers;
          exposes = declaredExposes.value;
          subject = "${iname}:instance";

          placement = placed.placement;
          every = placed.every;

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

          resolvedMembers = mapAttrs (mname: member: mkMember iname idecl mname member) members;

          generatorOwners = util.concatMapAttrsToList (
            mname: m: map (gen: { inherit gen mname; }) (attrNames m.declaration.vars.generators)
          ) resolvedMembers;

          claimedTwice = filter (gen: length (filter (o: o.gen == gen) generatorOwners) > 1) (
            util.uniqueStrings (map (o: o.gen) generatorOwners)
          );

          collisionRows = map (
            gen:
            let
              owners = util.sortStrings (map (o: o.mname) (filter (o: o.gen == gen) generatorOwners));
            in
            diag.error {
              inherit subject;
              id = "vars-generator-claimed-twice";
              message = "instance ${util.quote iname} declares generator ${util.quote gen} in ${util.quoteList owners}";
              evidence = "a generator is addressed by instance and name, so two declarations of ${util.quote gen} are one address for two values";
              resolution = "rename one of them in ${moduleFile}, or declare ${util.quote gen} in one member and let the other read it";
            }
          ) (util.sortStrings claimedTwice);

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
            ++ declaredRoot.rows
            ++ declaredExposes.rows
            ++ declaredWire.rows
            ++ placed.rows
            ++ placementRows
            ++ exposeRows
            ++ nameDisagreementRows
            ++ collisionRows;
        in
        {
          inherit
            iname
            root
            moduleFile
            rootProvides
            memberNames
            badMemberNames
            ;
          exposed = util.filterAttrs (n: _: elem n exposes) rootProvides;
          exposedNames = filter (n: rootProvides ? ${n}) exposes;
          wire = declaredWire.value;
          rows = instanceRows;
          members = resolvedMembers;
        };

      # `mname` is the attribute key the member is declared under, which is its
      # identity: `service`'s own name argument is row text and nothing reads it.
      mkMember =
        iname: _idecl: mname: member:
        let
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
            inherit reg storeDir;
            subject = moduleSubject;
            module = moduleLabel;
            declaration = member.declaration;
          };

          capabilityFacts = mapAttrs (
            _: declared:
            let
              iface = declared.interface;
              claim = if iface == null then null else interface.identityOf iface;
              file = if iface == null then null else interface.fileOf reg iface;
            in
            {
              declaredNames = if iface == null then [ ] else interface.exportNames iface;
              declaringFile = file;
              interfaceName = if iface == null then null else iface.name;
              interfaceId = if claim == null then null else claim.id;
              label = interface.labelFor iface file;
            }
          ) declaration.provides;

          every = placementOf.${iname}.every;
          selectorRead = declaredField {
            inherit subject;
            file = deploymentFile;
            where = "the placement of ${util.quote mname} in instance ${util.quote iname}";
            record = every;
            field = mname;
            shape = shapes.record;
            fallback = { };
          };
          selector = if every ? ${mname} then selectorRead.value else null;
          selectorField =
            field:
            declaredField {
              inherit subject;
              file = deploymentFile;
              where = "the placement of ${util.quote mname} in instance ${util.quote iname}";
              record = selectorRead.value;
              inherit field;
              shape = shapes.names;
              fallback = [ ];
            };
          namedField = selectorField "machines";
          taggedField = selectorField "tags";
          named = namedField.value;
          tags = taggedField.value;
          unknownMachines = filter (m: !(machines ? ${m})) named;
          placements = util.uniqueStrings (filter placeable (named ++ concatLists (map tagged tags)));

          placementRecord = {
            reason = "every";
          }
          // (if named == [ ] then { } else { machines = named; })
          // (if tags == [ ] then { } else { inherit tags; });

          placementRows =
            selectorRead.rows
            ++ namedField.rows
            ++ taggedField.rows
            ++ (
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
                  util.quote (toString machineFields.${m}.system.value)
                } and the module declares ${util.quoteList declaration.platforms}";
                evidence = "a module states the platforms it runs on and the machine registry states what a machine runs, and the two are crossed after placement is decided rather than believed from either side";
                resolution = "place ${util.quote mname} on a machine running one of ${util.quoteList declaration.platforms} in ${deploymentFile}, or declare ${
                  util.quote (toString machineFields.${m}.system.value)
                } in ${moduleSubject}";
              }
            ) mismatchedPlacements;

          # An empty platforms list means every system, so a module that never had
          # to care is not made to. A machine with no declared system is the
          # registry's row rather than this one.
          mismatchedPlacements =
            if declaration.platforms == [ ] then
              [ ]
            else
              filter (
                m:
                machineFields.${m}.system.value != null
                && !elem machineFields.${m}.system.value declaration.platforms
              ) placements;

          alloc = {
            ports = mapAttrs (_: claim: claim.fixed) declaration.claims.ports;
          };

          instanceWire = resolved.instances.${iname}.wire;

          wireOf =
            slotName:
            declaredField {
              inherit subject;
              file = deploymentFile;
              where = "the wire of instance ${util.quote iname}";
              record = instanceWire;
              field = slotName;
              shape = shapes.record;
              fallback = null;
            };

          wires = mapAttrs (slotName: _: wireOf slotName) declaration.uses;

          edges = mapAttrs (
            slotName: slot:
            mkEdge {
              inherit
                iname
                mname
                slotName
                slot
                ;
              wire = if instanceWire ? ${slotName} then wires.${slotName}.value else null;
            }
          ) declaration.uses;

          results = mapAttrs (_: edge: edge.implValue) (util.filterAttrs (_: edge: edge.delivered) edges);

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
            ++ compose.slotSetRows {
              subject = moduleSubject;
              name = mname;
              inherit deploymentFile;
              observation = member.slotSet;
            }
            ++ settings.rows
            ++ declaration.rows
            ++ placementRows
            ++ util.concatMapAttrsToList (_: w: w.rows) wires
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

      mkPlacement =
        {
          iname,
          mname,
          machine,
        }:
        let
          member = resolved.instances.${iname}.members.${mname};
          entryKey = if machine == null then "${iname}:${mname}" else "${iname}:${mname}@${machine}";

          generators = member.declaration.vars.generators;

          # The identity of a generated value, and the key its state is read under:
          # one value for the instance, or one per machine it is placed on.
          varsEntryKeyOf =
            gen:
            if machine == null || generators.${gen}.per == "instance" then
              "${iname}:vars/${gen}"
            else
              "${iname}:vars/${gen}@${machine}";

          # A module reads vars.<generator>.<file>. The declaration writes
          # vars.<generator>.files.<file>, because a generator has more to declare
          # than its files and a reader only ever wants the files.
          #
          # The path names the instance: a machine may hold values it does not own,
          # and two instances of one module would otherwise name one file.
          vars = mapAttrs (
            gen: g:
            let
              valueKey = varsEntryKeyOf gen;
              state = varsState.${valueKey} or { };
            in
            mapAttrs (
              fname: fdecl:
              let
                fileState = state.${fname} or { };
                present = fileState.present or false;
                secrecy = interface.secrecyOf fdecl;
              in
              {
                __varsFile = true;
                inherit present secrecy;
                generator = gen;
                file = fname;
                entry = valueKey;
                inherit (g) deploy;
                path = "/run/vars/${iname}/${gen}/${fname}";
                content = if present && secrecy != "secret" then fileState.content or null else null;
              }
            ) g.files
          ) generators;

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

          # The implementation half is read like the declaration half: an
          # unrecognised key becomes a row rather than a value quietly dropped, and
          # one malformed unit does not stop the rest. Only the shape is forced
          # here, because a recipe rendered over an incomplete set has no bytes to
          # force at all.
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

          # An extension for another service manager is refused here and still
          # recorded under its own backend, so a binding for that backend refuses
          # knowingly instead of dropping fields.
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
          varsEntries = mapAttrs (gen: _: varsEntryKeyOf gen) generators;
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
                note = "a refusal of a value another module produced belongs in the fold of the interface that carries it, where the fold states the message and the planner states the row's identifier, subject and severity";
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
              atomType = interface.atomTypeOf atom;
              secrecy = interface.secrecyOf atom;
              value = raw.${ename};
              fromVars = util.isVarsFile value;
              absent = value == null || (fromVars && !value.present);
              # An export whose atom carries no korora type is a row of the
              # interface itself, and the value it publishes is left untyped
              # here rather than verified against a type that is not one.
              typeError = if absent || atomType == null then null else atomType.verify value;
            in
            {
              inherit
                ename
                secrecy
                absent
                ;
              value = if fromVars then value.path else value;
              plane = if secrecy == "secret" then "reference" else "env";

              # What a consumer of this export is handed. A secret is the reference
              # record its atom's type describes, so a module writes
              # `results.<slot>.<export>.path` and interpolating the export itself
              # raises rather than yielding a path under the name of a value.
              read = if fromVars && secrecy == "secret" then { inherit (value) path secrecy; } else value;

              # The generated value behind this export, so an edge can name it and a
              # delivery set can be derived from who read it.
              varsFile =
                if fromVars then
                  {
                    inherit (value)
                      generator
                      file
                      entry
                      deploy
                      ;
                  }
                else
                  null;
              rows =
                util.optional (typeError != null) (
                  diag.error {
                    subject = entryKey;
                    id = "export-type-mismatch";
                    message = "${entryKey} publishes ${util.quote "${cap}.${ename}"} with a value that fails its atom's type";
                    evidence = "${facts.label} declares ${ename} as ${util.quote atomType.name}, and korora reports: ${toString typeError}";
                    resolution = "publish a value of that type in ${publishingFile}, or change the atom on the interface";
                  }
                )
                ++ util.optional (secrecy == "secret" && !absent && !fromVars) (
                  diag.error {
                    subject = entryKey;
                    id = "export-secret-not-a-reference";
                    message = "${entryKey} publishes ${util.quote "${cap}.${ename}"}, which ${facts.label} declares secret, as a value rather than as a generated file";
                    evidence = "a secret is delivered to the machines that read it, and what is delivered is bytes a generator produced; a value published here would instead be carried by the plan, which every reader of the plan can read";
                    resolution = "publish `vars.<generator>.<file>` in ${publishingFile}, or declare ${util.quote ename} public on the interface";
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
          inherit (facts) declaringFile interfaceName interfaceId;
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

          slotClaim = if slot.interface == null then null else interface.identityOf slot.interface;
          capabilityClaim = if capability == null then null else interface.identityOf capability.interface;

          # Both ends must claim, or taking one side's word would capture a far
          # end that never agreed to be captured. The value comparison is named
          # so it is made once and neither claim is forced where it succeeds.
          sameValue = capability != null && slot.interface != null && slot.interface == capability.interface;

          claimsMatch = slotClaim != null && slotClaim == capabilityClaim;

          # One conflict is one row wherever it was seen, so the wire builds the
          # same row the registry pass does and `dedup` keeps one.
          claimsConflict =
            !sameValue
            && slotClaim != null
            && capabilityClaim != null
            && slotClaim.id == capabilityClaim.id
            && slotClaim != capabilityClaim;

          interfaceMatches = sameValue || claimsMatch;

          readsAt =
            machine:
            let
              record = providerMember.placed.${machine}.capabilities.${capability.capability};
              picked = builtins.listToAttrs (
                map (r: {
                  name = r;
                  value = if record.exports ? ${r} then record.exports.${r}.read else null;
                }) slot.reads
              );
              absentReads = filter (r: !(record.exports ? ${r}) || record.exports.${r}.absent) slot.reads;
              undeployed = filter (
                r:
                record.exports ? ${r}
                && record.exports.${r}.varsFile != null
                && !record.exports.${r}.varsFile.deploy
              ) slot.reads;
            in
            {
              inherit absentReads undeployed;
              key = "${capability.member}@${machine}";
              entryKey = "${target}:${capability.member}@${machine}";
              values = picked;
              # Which generated value each read names, for the delivery set.
              varsFiles = builtins.listToAttrs (
                map (r: {
                  name = r;
                  value = record.exports.${r}.varsFile;
                }) (filter (r: record.exports ? ${r} && record.exports.${r}.varsFile != null) slot.reads)
              );
            };

          collected = map readsAt placements;
          absentEntries = filter (c: c.absentReads != [ ]) collected;
          undeployedEntries = filter (c: c.undeployed != [ ]) collected;

          arityOk =
            interfaceMatches && (if slot.reach == "all" then placements != [ ] else length placements == 1);

          deliverable = slot.resolvable && wire != null && !isMemberCut && capability != null && arityOk;

          entryKeyed = builtins.listToAttrs (
            map (c: {
              name = c.entryKey;
              value = c.values;
            }) collected
          );

          declaredFold = if slot.interface == null then null else interface.foldOf slot.interface;

          # A fold is the interface's policy for the set, so it is applied to the
          # value the read already built and only where that read would deliver.
          foldApplies = deliverable && slot.reach == "all" && interface.foldApplicable declaredFold;

          folded = safe {
            inherit subject;
            id = "interface-fold-raised";
            what = "the fold of ${ifaceLabel} for slot ${util.quote slotName} of ${util.quote subject}";
            fallback = null;
            value = (interface.foldApply declaredFold) entryKeyed;
          };

          foldRaised = foldApplies && folded.rows != [ ];

          # The one channel through which a module refuses another module's value:
          # a fold states why, and the planner decides the row's id, subject and
          # severity. A raise cannot carry text, so a refusal is a returned value,
          # and the channel accepts only text: a refusal the planner cannot render
          # is a row of its own rather than a coercion or an empty message.
          refuses = foldApplies && !foldRaised && builtins.isAttrs folded.value && folded.value ? refused;
          stated = if refuses then folded.value.refused else null;
          refusalIsText = builtins.isString stated && stated != "";
          refusal = if refuses && refusalIsText then stated else null;

          delivered = deliverable && !foldRaised && !refuses;

          # The plan records the set the read collected; the fold decides only what
          # the consuming implementation receives.
          value = if slot.reach == "all" then entryKeyed else (head collected).values;

          implValue = if foldApplies then folded.value else value;

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
            ++ util.optional claimsConflict (interface.conflictRow reg slot.interface capability.interface)
            ++ util.optional (capability != null && slot.interface != null && !interfaceMatches) (
              diag.error {
                inherit subject;
                id = "interface-mismatch";
                message = "slot ${util.quote slotName} of ${util.quote subject} declares ${ifaceLabel} and ${util.quote "${target}.${capName}"} declares ${interface.label reg capability.interface}";
                evidence =
                  if slotClaim != null && capabilityClaim != null then
                    "both ends claim an identity and the two claims differ, so the values were never compared"
                  else if capability.interface.name == slot.interface.name then
                    "the two interfaces carry one name and are different values, which is why a row renders the declaring file beside the name"
                  else
                    "the two are different values and at most one of them claims an identity, so an interface is identified by the value an author imported, never by its name";
                resolution =
                  if slotClaim != null && capabilityClaim != null then
                    "make the two claims one identity, or import the interface the far end declares into ${consumerFile}"
                  else
                    "import the interface the far end declares into ${consumerFile}, or wire a capability that declares this one";
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
            )
            ++ concatLists (
              map (
                c:
                map (
                  r:
                  diag.error {
                    inherit subject;
                    id = "slot-reads-undeployed-value";
                    message = "slot ${util.quote slotName} of ${util.quote subject} reads ${util.quote r} of ${util.quote "${target}.${capName}"}, whose value no machine receives";
                    evidence = "${util.quote c.entryKey} publishes it from generator ${
                      util.quote c.varsFiles.${r}.generator
                    }, which declares `deploy = false`, so the path it names resolves to nothing at run time";
                    resolution = "declare that generator deployed in the module that owns it, or stop reading ${util.quote r} in ${consumerFile}";
                  }
                ) c.undeployed
              ) undeployedEntries
            )
            ++ (if foldApplies then folded.rows else [ ])
            ++ util.optional (refusal != null) (
              diag.error {
                inherit subject;
                id = "interface-fold-refused";
                message = refusal;
                evidence = "the fold of ${ifaceLabel} refused the set slot ${util.quote slotName} collected over ${
                  util.quoteList (map (c: c.entryKey) collected)
                }, and the fold states the message while the planner states this row's identifier, subject and severity";
                resolution = "act on the message above in the module or the deployment it names, or wire ${util.quote slotName} of ${util.quote subject} to a capability whose values the fold accepts";
              }
            )
            ++ util.optional (refuses && !refusalIsText) (
              diag.error {
                inherit subject;
                id = "interface-fold-refusal-malformed";
                message = "the fold of ${ifaceLabel} refused slot ${util.quote slotName} of ${util.quote subject} with ${
                  if builtins.isString stated then "an empty string" else shownValue stated
                } rather than with a reason";
                evidence = "a refusal travels to the table as the row's whole message, so the channel accepts text and nothing else: a value of another kind would be coerced and an empty one would print a row with nothing in it";
                resolution = "return `{ refused = \"<why>\"; }` from the fold of ${ifaceLabel}, with the sentence an operator should read";
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
          wire =
            if wire == null || isMemberCut then
              null
            else
              {
                instance = target;
                provides = capName;
              };
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

          # Which generated value each read of each provider entry names, so the
          # delivery set can be derived from the reads and from nothing else.
          entryVarsFiles = builtins.listToAttrs (
            map (c: {
              name = c.entryKey;
              value = c.varsFiles;
            }) collected
          );
          value = if delivered then value else null;
          implValue = if delivered then implValue else null;
        };

      # An interface's fold is a policy, so one no read applies is one nobody is
      # held to. Derived from the slots the deployment resolved rather than from a
      # second traversal, and the same interface named twice is one row.
      declaredSlots = concatLists (
        util.mapAttrsToList (
          _: inst:
          concatLists (
            util.mapAttrsToList (
              _: member: util.mapAttrsToList (_: slot: slot) member.declaration.uses
            ) inst.members
          )
        ) resolved.instances
      );

      setReachInterfaces = map (slot: slot.interface) (
        filter (slot: slot.interface != null && slot.reach == "all") declaredSlots
      );

      # Applied by the same rule a wire matches by, so an interface whose
      # claim-equal twin is read with set reach is not reported as unread.
      appliedSomewhere =
        iface:
        let
          claim = interface.identityOf iface;
        in
        builtins.any (
          applied: applied == iface || (claim != null && interface.identityOf applied == claim)
        ) setReachInterfaces;

      foldDeclared = filter (iface: interface.foldOf iface != null) (
        map (r: r.value) (filter (r: interface.isInterface r.value) reg)
        ++ filter (iface: iface != null) (map (slot: slot.interface) declaredSlots)
      );

      # Which interfaces the deployment reaches: every slot's and every
      # capability's. Attribution is never a registry, so an interface absent
      # from the `interfaces` argument still earns every row it can earn.
      reachedInterfaces = util.distinct (
        filter interface.isInterface (
          map (slot: slot.interface) declaredSlots
          ++ concatLists (
            util.mapAttrsToList (
              _: inst:
              concatLists (
                util.mapAttrsToList (
                  _: member: util.mapAttrsToList (_: cap: cap.interface) member.declaration.provides
                ) inst.members
              )
            ) resolved.instances
          )
        )
      );

      foldRows = map (
        iface:
        let
          subject = interface.subjectOf reg iface;
        in
        diag.warning {
          inherit subject;
          id = "interface-fold-unapplied";
          message = "interface ${interface.label reg iface} declares a fold and no slot of this deployment reads it with reach ${util.quote "all"}";
          evidence = "a fold combines the set a read collects, so a deployment resolving only single-valued reads of this interface never applies it and never observes what it does";
          resolution = "declare `reach = \"all\"` on a slot reading this interface, or delete the fold from ${subject}";
        }
      ) (filter (iface: !(appliedSomewhere iface)) foldDeclared);

      resolved = {
        instances = mapAttrs mkInstance (
          util.filterAttrs (name: _: !(util.carriesKeySeparator name)) instances
        );
        machines = machineRecords;
        interfaces = reachedInterfaces;
        usedMachines = selectedMachines;
        inherit storeDir;
        rows =
          machineRows
          ++ nameRows
          ++ foldRows
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
