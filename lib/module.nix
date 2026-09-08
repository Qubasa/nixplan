# A leaf module's two halves: the asking half is what it runs on, what it
# claims, what it generates, what it uses and what it provides; the answering
# half is the units, the configuration files and the closure roots its `impl`
# produced. Reading is total: every malformed or excluded declaration becomes a
# row and the rest is still read.
{
  util,
  diag,
  excluded,
  interface,
  atoms,
}:
let
  inherit (builtins)
    all
    attrNames
    elem
    filter
    isAttrs
    isFunction
    isList
    isString
    listToAttrs
    mapAttrs
    ;

  moduleKeys = [
    "platforms"
    "claims"
    "vars"
    "uses"
    "provides"
    "pin"
    "impl"
    "severity"
  ];

  pinKeys = [
    "key"
    "locked"
  ];

  # The shape a resolver's lockfile already holds. `rev` and `narHash` are the
  # two the priority rests on: a pin that can resolve to different bytes on a
  # later evaluation is what per-service pinning exists to refuse.
  lockedKeys = [
    "type"
    "owner"
    "repo"
    "rev"
    "narHash"
  ];

  lockedRequired = [
    "rev"
    "narHash"
  ];

  # The portable unit vocabulary, typed. Every field is one the design corpus
  # already writes into a committed plan fixture, and a binding renders a unit
  # file from these and from the typed extensions beside them.
  unitVocabulary = {
    command = atoms.string;
    env = atoms.attrsOf atoms.string;
    after = atoms.listOf atoms.unitRef;
    requires = atoms.listOf atoms.unitRef;
    user = atoms.userName;
    oneShot = atoms.bool;
    remainAfterExit = atoms.bool;
    schedule = atoms.schedule;
    timeout = atoms.duration;
    stopCommand = atoms.string;
    reloadCommand = atoms.string;
  };

  unitKeys = attrNames unitVocabulary ++ [ "extends" ];

  # The two fields whose entries name units, checked against the units the
  # module declared itself.
  unitReferenceKeys = [
    "after"
    "requires"
  ];

  # An implementation's top level, and one configuration file.
  implKeys = [
    "units"
    "configData"
    "provides"
    "closure"
  ];

  configFileKeys = [
    "mode"
    "reload"
    "source"
    "render"
  ];

  dispositions = [
    "source"
    "render"
  ];

  slotKeys = [
    "interface"
    "reach"
    "reads"
    "severity"
  ];

  capabilityKeys = [
    "interface"
    "severity"
  ];

  claimKeys = [
    "proto"
    "count"
    "fixed"
  ];

  reaches = [
    "one"
    "all"
  ];

  isInterface = v: isAttrs v && v ? name && v ? exports && isAttrs v.exports;
in
rec {
  inherit
    unitVocabulary
    unitKeys
    unitReferenceKeys
    implKeys
    configFileKeys
    dispositions
    ;

  # A key a module declared that this subset does not carry, or does not know.
  # `id` is the identifier the unknown half carries, so that a key under an
  # implementation is told from a key under a declaration while the excluded
  # half stays one row about one construct.
  keyRow =
    {
      subject,
      where,
      key,
      allowed,
      id ? "declaration-unknown-key",
    }:
    if excluded.constructs ? ${key} then
      diag.error {
        inherit subject;
        id = "declaration-excluded-key";
        message = "${where} declares ${util.quote key}, which this subset does not carry";
        evidence = "the condition that introduces it: ${excluded.constructs.${key}.trigger}";
        resolution = "delete ${util.quote key} from ${subject}, or land the change that adds the construct before writing it";
      }
    else
      diag.error {
        inherit subject;
        inherit id;
        message = "${where} declares ${util.quote key}, and this subset reads ${util.quoteList allowed}";
        evidence = "unknown keys are refused rather than ignored, so a misspelling is a row instead of a silence";
        resolution = "delete or correct ${util.quote key} in ${subject}";
      };

  severityRow =
    { subject, where }:
    diag.warning {
      inherit subject;
      id = "module-declared-severity";
      message = "${where} declares a severity, and a module does not decide the severity of a planner row";
      evidence = "the declaration was read and discarded; the row this would have retagged keeps the severity the planner gave it";
      resolution = "delete `severity` from ${subject} and argue the severity where the check lives, under lib/";
    };

  # `uses.<slot>`: an interface, an arity and the exports it reads. A slot that
  # is refused here resolves to no value at all rather than to something a
  # consumer could default against.
  readSlot =
    {
      reg,
      subject,
      module,
      name,
      slot,
    }:
    let
      where = "slot ${util.quote name} of ${module}";
      reach = slot.reach or "one";
      hasInterface = slot ? interface && isInterface slot.interface;
      declared = if hasInterface then interface.exportNames slot.interface else [ ];
      reads = if slot ? reads then slot.reads else declared;
      unknownReads = if hasInterface then util.subtractList reads declared else [ ];
      secretReads = builtins.filter (
        r: elem r declared && interface.secrecyOf slot.interface.exports.${r} == "secret"
      ) reads;

      rows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = where;
            allowed = slotKeys;
          }
        ) (util.extraKeys slotKeys slot)
        ++ util.optional (slot ? severity) (severityRow {
          inherit subject where;
        })
        ++ util.optional (!hasInterface) (
          diag.error {
            inherit subject;
            id = "slot-interface-missing";
            message = "${where} declares no interface value";
            evidence = "a slot names an interface by the value its module imported, never by a name resolved at composition time";
            resolution = "pass the interface value into ${subject} and write it as `uses.${name}.interface`";
          }
        )
        ++ util.optional (reach == "local") (
          diag.error {
            inherit subject;
            id = "slot-reach-local";
            message = "${where} declares reach ${util.quote "local"}, and `local` derives from a locality this subset does not declare";
            evidence = "the condition that introduces it: ${excluded.constructs.locality.trigger}";
            resolution = "write ${util.quoteList reaches} in ${subject}, or land the locality change that makes co-placement derivable";
          }
        )
        ++ util.optional (reach != "local" && !elem reach reaches) (
          diag.error {
            inherit subject;
            id = "slot-reach-domain";
            message = "${where} declares reach ${util.quote (toString reach)}, and reach takes ${util.quoteList reaches}";
            evidence = "an omitted reach means `one`";
            resolution = "write one of ${util.quoteList reaches} in ${subject}, or omit the key";
          }
        )
        ++ map (
          r:
          diag.error {
            inherit subject;
            id = "slot-reads-unknown-export";
            message = "${where} reads ${util.quote r}, which ${interface.label reg slot.interface} does not declare";
            evidence = "the interface declares ${util.quoteList declared}";
            resolution = "read a declared export in ${subject}, or declare ${util.quote r} on the interface";
          }
        ) unknownReads
        ++ map (
          r:
          diag.error {
            inherit subject;
            id = "slot-reads-secret-export";
            message = "${where} reads ${util.quote r}, which ${interface.label reg slot.interface} declares secret";
            evidence = "a reads entry naming a secret export is refused outright, on every machine and regardless of placement";
            resolution = "read the public half in ${subject}; a secret is readable only by the units of the service that generated it";
          }
        ) secretReads;
    in
    {
      inherit rows reach reads;
      interface = if hasInterface then slot.interface else null;
      resolvable = hasInterface && elem reach reaches && unknownReads == [ ] && secretReads == [ ];
    };

  readCapability =
    {
      subject,
      module,
      name,
      capability,
    }:
    let
      where = "capability ${util.quote name} of ${module}";
      hasInterface = capability ? interface && isInterface capability.interface;
    in
    {
      interface = if hasInterface then capability.interface else null;
      rows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = where;
            allowed = capabilityKeys;
          }
        ) (util.extraKeys capabilityKeys capability)
        ++ util.optional (capability ? severity) (severityRow {
          inherit subject where;
        })
        ++ util.optional (!hasInterface) (
          diag.error {
            inherit subject;
            id = "capability-interface-missing";
            message = "${where} declares no interface value";
            evidence = "a capability publishes exactly the keyset of the interface it declares, so there is nothing to check without one";
            resolution = "pass the interface value into ${subject} and write it as `provides.${name}.interface`";
          }
        );
    };

  readClaims =
    {
      subject,
      module,
      claims,
    }:
    let
      ports = claims.ports or { };
      portRows =
        name: claim:
        map (
          key:
          keyRow {
            inherit subject key;
            where = "port claim ${util.quote name} of ${module}";
            allowed = claimKeys;
          }
        ) (util.extraKeys claimKeys claim)
        ++ util.optional (!(claim ? fixed)) (
          diag.error {
            inherit subject;
            id = "port-claim-not-fixed";
            message = "port claim ${util.quote name} of ${module} declares no `fixed` port, and this subset allocates nothing";
            evidence = "the condition that introduces it: ${excluded.constructs.dynamicPort.trigger}";
            resolution = "write `claims.ports.${name}.fixed` in ${subject}, or land the change that carries the allocation table";
          }
        );
    in
    {
      ports = util.filterAttrs (_: claim: claim ? fixed) ports;
      rows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = "claims of ${module}";
            allowed = [ "ports" ];
          }
        ) (util.extraKeys [ "ports" ] claims)
        ++ util.concatMapAttrsToList portRows ports;
    };

  readVars =
    {
      subject,
      module,
      vars,
    }:
    let
      fileRows =
        gen: name: file:
        map (
          key:
          keyRow {
            inherit subject key;
            where = "generated file ${util.quote "${gen}/${name}"} of ${module}";
            allowed = [ "secrecy" ];
          }
        ) (util.extraKeys [ "secrecy" ] file)
        ++ util.optional (!elem (interface.secrecyOf file) interface.secrecies) (
          diag.error {
            inherit subject;
            id = "vars-file-secrecy-domain";
            message = "generated file ${util.quote "${gen}/${name}"} of ${module} declares secrecy ${util.quote (toString (interface.secrecyOf file))}";
            evidence = "secrecy on a generated file takes ${util.quoteList interface.secrecies}, the same two values it takes on an export";
            resolution = "write one of ${util.quoteList interface.secrecies} in ${subject}, or omit the key";
          }
        );

      genRows =
        gen: g:
        map (
          key:
          keyRow {
            inherit subject key;
            where = "generator ${util.quote gen} of ${module}";
            allowed = [ "files" ];
          }
        ) (util.extraKeys [ "files" ] g)
        ++ util.concatMapAttrsToList (fileRows gen) (g.files or { });
    in
    {
      generators = builtins.mapAttrs (_: g: { files = g.files or { }; }) vars;
      rows = util.concatMapAttrsToList genRows vars;
    };

  # `pin`: the lock key a resolver assigned and the record it resolved to, both
  # literal strings. The planner records it and resolves nothing, so this is a
  # guard over hand-written data rather than over the resolver.
  readPin =
    {
      subject,
      module,
      pin,
    }:
    let
      where = "the pin of ${module}";
      locked = pin.locked or { };
      hasLocked = isAttrs locked;
      declared = if hasLocked then attrNames locked else [ ];
      missing = if hasLocked then util.subtractList lockedRequired declared else lockedRequired;
      nonStrings = filter (n: locked ? ${n} && !isString locked.${n}) lockedKeys;

      rows =
        map (
          key:
          keyRow {
            inherit subject key;
            inherit where;
            allowed = pinKeys;
          }
        ) (util.extraKeys pinKeys pin)
        ++ map (
          key:
          keyRow {
            inherit subject key;
            where = "the locked record of ${module}";
            allowed = lockedKeys;
          }
        ) (if hasLocked then util.extraKeys lockedKeys locked else [ ])
        ++ util.optional (!(pin ? key) || !isString pin.key) (
          diag.error {
            inherit subject;
            id = "pin-malformed";
            message = "${where} declares no lock key";
            evidence = "a pin is ${util.quote "{ key, locked }"}, where `key` is the string the resolver assigned and key equality is what says whether two entries share a dependency";
            resolution = "let the resolver hand the module its pin through its lexical closure rather than writing one in ${subject}";
          }
        )
        ++ util.optional (!hasLocked) (
          diag.error {
            inherit subject;
            id = "pin-malformed";
            message = "${where} declares no locked record";
            evidence = "a locked record names a source, a revision and a content hash, all literal strings";
            resolution = "let the resolver hand the module its pin through its lexical closure rather than writing one in ${subject}";
          }
        )
        ++ map (
          field:
          diag.error {
            inherit subject;
            id = "pin-underspecified";
            message = "${where} declares a locked record with no ${util.quote field}";
            evidence = "a pin that can resolve to different bytes on a later evaluation is the condition this declaration exists to refuse, and the locked record declares ${util.quoteList declared}";
            resolution = "record the ${util.quote field} the resolver locked in ${subject}";
          }
        ) (if hasLocked then missing else [ ])
        ++ map (
          field:
          diag.error {
            inherit subject;
            id = "pin-malformed";
            message = "${where} declares ${util.quote field} that is not a string";
            evidence = "every field of a locked record is a literal string, which is what keeps a plan JSON-safe and derivation-free";
            resolution = "record the string the resolver locked in ${subject}";
          }
        ) nonStrings;
    in
    {
      record =
        if rows == [ ] then
          {
            inherit (pin) key;
            locked = util.pickAttrs lockedKeys locked;
          }
        else
          null;
      inherit rows;
    };

  # One unit of one implementation, read against the vocabulary. A field the
  # unit did not declare is absent from the record rather than recorded as a
  # null or as a service manager's default, so a binding can tell "not asked
  # for" from "asked for and empty".
  readUnit =
    {
      reg,
      subject,
      module,
      unitNames,
      unitSet,
      name,
      unit,
    }:
    let
      where = "unit ${util.quote name} of ${module}";
      declared = filter (k: unitVocabulary ? ${k}) (attrNames unit);

      # One verification per declared field, recorded: the row that reports a
      # failure prints this error rather than running the type again.
      errors = listToAttrs (
        map (k: {
          name = k;
          value = unitVocabulary.${k}.verify unit.${k};
        }) declared
      );
      failures = filter (k: errors.${k} != null) declared;
      typed = filter (k: errors.${k} == null) declared;

      references = filter (k: elem k typed) unitReferenceKeys;

      # The units this module declared and the strangers are complements of one
      # partition, and both halves are wanted: one for the record's ordering,
      # one for the rows. `unitSet` is the entry's own unit names as an index,
      # so a reference costs a lookup rather than a scan of them.
      partitioned = listToAttrs (
        map (k: {
          name = k;
          value = builtins.partition (r: util.inStringSet unitSet r) unit.${k};
        }) references
      );
      strangersIn = k: partitioned.${k}.wrong;
      ownedIn = k: partitioned.${k}.right;

      extends =
        if unit ? extends && isList unit.extends then
          map (
            application:
            interface.readExtension {
              inherit
                reg
                subject
                where
                application
                ;
            }
          ) unit.extends
        else
          [ ];

      applied = filter (e: e.backend != null) extends;

      # Grouped by backend, so a binding for another service manager meets the
      # fields it cannot render and refuses knowingly instead of dropping them.
      grouped = builtins.groupBy (e: e.backend) applied;

      ordering = listToAttrs (
        map (k: {
          name = k;
          value = ownedIn k;
        }) references
      );

      record =
        util.filterAttrs (n: v: !(elem n unitReferenceKeys && v == [ ])) (
          util.pickAttrs typed unit // ordering
        )
        // (
          if grouped == { } then
            { }
          else
            {
              extends = mapAttrs (_: es: builtins.foldl' (acc: e: acc // e.values) { } es) grouped;
            }
        );

      rows =
        map (
          key:
          keyRow {
            inherit subject key where;
            allowed = unitKeys;
            id = "implementation-unknown-key";
          }
        ) (util.extraKeys unitKeys unit)
        ++ map (
          key:
          diag.error {
            inherit subject;
            id = "unit-field-type-mismatch";
            message = "${where} declares ${util.quote key} with a value that fails its field's type";
            evidence = "the vocabulary declares ${key} as ${
              util.quote unitVocabulary.${key}.name
            }, and korora reports: ${toString errors.${key}}";
            resolution = "write a value of that type in ${subject}; the failing value is not recorded";
          }
        ) failures
        ++ util.optional (unit ? extends && !isList unit.extends) (
          diag.error {
            inherit subject;
            id = "unit-extends-malformed";
            message = "${where} declares `extends` that is not a list";
            evidence = "`extends` is an ordered list of ${util.quote "{ extension, values }"} entries, one per extension the unit applies";
            resolution = "write a list in ${subject}";
          }
        )
        ++ builtins.concatLists (
          map (
            k:
            map (
              r:
              diag.error {
                inherit subject;
                id = "unit-reference-unknown";
                message = "${where} names ${util.quote r} in ${util.quote k}, and ${module} declares no such unit";
                evidence = "a unit reference is producible only by the module that declared the unit it names, so no module can order itself against a unit a stranger may rename; ${module} declares ${util.quoteList unitNames}";
                resolution = "name a unit ${subject} declares, or declare ${util.quote r} in it";
              }
            ) (strangersIn k)
          ) references
        )
        ++ builtins.concatLists (map (e: e.rows) extends);
    in
    {
      inherit record rows;
      extensions = applied;
    };

  # One configuration file: a mode, the units the module named for reloading,
  # and exactly one disposition.
  readConfigFile =
    {
      subject,
      module,
      unitNames,
      unitSet,
      path,
      file,
    }:
    let
      where = "configuration file ${util.quote path} of ${module}";
      given = filter (d: file ? ${d}) dispositions;
      reload = if file ? reload then file.reload else [ ];
      reloadSplit = builtins.partition (r: util.inStringSet unitSet r) (
        if isList reload then reload else [ ]
      );
      strangers = reloadSplit.wrong;

      # An item is one public literal or one reference. Read by key rather than
      # by value: a recipe rendered over a set with an absent entry raises when
      # its fragments are forced, and that case is recorded as not computed
      # instead of being read here.
      render = if file ? render then file.render else [ ];
      renderIsList = isList render;
      malformedItems =
        if renderIsList then
          filter (
            item:
            !isAttrs item
            || (
              let
                keys = attrNames item;
              in
              keys != [ "ref" ] && keys != [ "text" ]
            )
          ) render
        else
          [ ];
      renderOk = renderIsList && malformedItems == [ ];

      rows =
        map (
          key:
          keyRow {
            inherit subject key where;
            allowed = configFileKeys;
            id = "implementation-unknown-key";
          }
        ) (util.extraKeys configFileKeys file)
        ++ util.optional (builtins.length given != 1) (
          diag.error {
            inherit subject;
            id = "config-file-disposition";
            message = "${where} declares ${
              if given == [ ] then "neither `source` nor `render`" else "both `source` and `render`"
            }";
            evidence = "a file names its bytes exactly once: `source` is the store path holding the rendered file, `render` is the ordered recipe the machine concatenates";
            resolution = "write one of ${util.quoteList dispositions} in ${subject}";
          }
        )
        ++ util.optional (!(file ? mode) || !isString file.mode) (
          diag.error {
            inherit subject;
            id = "config-file-mode-missing";
            message = "${where} declares no `mode`";
            evidence = "the mode a file is shown to a service with is a fact of the deployment and not of whoever writes the bytes";
            resolution = "write `mode` as a string of octal digits in ${subject}";
          }
        )
        ++ util.optional (!isList reload) (
          diag.error {
            inherit subject;
            id = "config-file-reload-malformed";
            message = "${where} declares `reload` that is not a list of units";
            evidence = "`reload` is the units the module named, and a file that names no unit reloads none";
            resolution = "write a list of this module's unit names in ${subject}";
          }
        )
        ++ util.optional (file ? render && !renderOk) (
          diag.error {
            inherit subject;
            id = "config-file-render-item";
            message = "${where} declares a recipe ${
              if renderIsList then
                "with ${util.countNoun (builtins.length malformedItems) "item" "items"} that is not one fragment"
              else
                "that is not a list"
            }";
            evidence = "a recipe is an ordered list whose items are ${util.quote "{ text = <public literal>; }"} or ${util.quote "{ ref = <path>; }"}, exactly one of the two per item";
            resolution = "write one fragment per item in ${subject}";
          }
        )
        ++ map (
          r:
          diag.error {
            inherit subject;
            id = "unit-reference-unknown";
            message = "${where} reloads ${util.quote r}, and ${module} declares no such unit";
            evidence = "a file reloads units of the service that renders it; ${module} declares ${util.quoteList unitNames}";
            resolution = "name a unit ${subject} declares in ${util.quote "reload"}";
          }
        ) strangers;
    in
    {
      inherit rows;
      record = {
        mode = if file ? mode && isString file.mode then file.mode else null;
        reload = util.sortStrings reloadSplit.right;
        disposition =
          if builtins.length given != 1 then
            null
          else if builtins.head given == "render" && !renderOk then
            null
          else
            builtins.head given;
      }
      // util.pickAttrs dispositions file;
    };

  # The whole asking half of one leaf module.
  read =
    {
      reg,
      subject,
      module,
      declaration,
    }:
    let
      claims = readClaims {
        inherit subject module;
        claims = declaration.claims or { };
      };
      vars = readVars {
        inherit subject module;
        vars = declaration.vars or { };
      };
      uses = builtins.mapAttrs (
        name: slot:
        readSlot {
          inherit
            reg
            subject
            module
            name
            slot
            ;
        }
      ) (declaration.uses or { });
      provides = builtins.mapAttrs (
        name: capability:
        readCapability {
          inherit
            subject
            module
            name
            capability
            ;
        }
      ) (declaration.provides or { });
      platforms = declaration.platforms or [ ];
      pin =
        if declaration ? pin then
          readPin {
            inherit subject module;
            pin = declaration.pin;
          }
        else
          {
            record = null;
            rows = [ ];
          };
    in
    {
      inherit
        claims
        platforms
        provides
        uses
        vars
        ;
      pin = pin.record;
      impl = declaration.impl or null;
      rows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = module;
            allowed = moduleKeys;
          }
        ) (util.extraKeys moduleKeys declaration)
        ++ util.optional (declaration ? severity) (severityRow {
          inherit subject;
          where = module;
        })
        ++ util.optional (!(isList platforms && all isString platforms)) (
          diag.error {
            inherit subject;
            id = "platforms-malformed";
            message = "${module} declares `platforms` that is not a list of strings";
            evidence = "a module states the platforms it runs on as a list of system strings";
            resolution = "write a list of system strings in ${subject}";
          }
        )
        ++ util.optional (!(declaration ? impl) || !isFunction declaration.impl) (
          diag.error {
            inherit subject;
            id = "impl-missing";
            message = "${module} declares no `impl` function";
            evidence = "`impl` is what produces units, configuration data and the exports of every capability the module provides";
            resolution = "add `impl = { results, alloc, vars, settings, ... }: { ... };` to ${subject}";
          }
        )
        ++ claims.rows
        ++ vars.rows
        ++ util.concatMapAttrsToList (_: s: s.rows) uses
        ++ util.concatMapAttrsToList (_: c: c.rows) provides
        ++ pin.rows;
    };
}
