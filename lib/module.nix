# A leaf module's two halves: the asking half is what it runs on, what it claims,
# what it generates, what it uses and what it provides. The answering half is the
# units, the configuration files and the closure roots its impl produced. Reading
# is total, so a malformed declaration becomes a row and the rest is still read.
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

  # The shape a resolver's lockfile already holds. rev and narHash are the two the
  # priority rests on: a pin that can resolve to different bytes on a later
  # evaluation is what per-service pinning exists to refuse.
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
    restart = atoms.restartPolicy;
    restartSec = atoms.duration;
  };

  unitKeys = attrNames unitVocabulary ++ [ "extends" ];

  # The two fields whose entries name units, checked against the units the module
  # declared itself.
  unitReferenceKeys = [
    "after"
    "requires"
  ];

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
    "consumers"
    "severity"
  ];

  claimKeys = [
    "proto"
    "fixed"
    "address"
  ];

  generatorKeys = [
    "files"
    "per"
    "deploy"
    "reads"
    "program"
  ];

  # How many of a generated value exist. The default is `placement`, because the
  # failure modes are asymmetric: a value wrongly per-machine is a second key
  # nobody shares, and a value wrongly shared is one secret on every machine.
  cardinalities = [
    "instance"
    "placement"
  ];

  # A reader may read a sibling of its own cardinality or a coarser one. The
  # reverse has no single answer: the placements hold one value each.
  coarserThan = {
    instance = [ "instance" ];
    placement = [
      "instance"
      "placement"
    ];
  };

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

  keyRow =
    {
      subject,
      where,
      key,
      allowed,
      id ? "declaration-unknown-key",
      note ? null,
    }:
    let
      also = if note == null then "" else "; ${note}";
    in
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
        resolution = "delete or correct ${util.quote key} in ${subject}${also}";
      };

  # Every value below is read for its kind before the reading indexes into it. A
  # guard is no substitute: the unknown-key scans call `removeAttrs` on the value
  # itself and the walks call `mapAttrs`, and a type error is not something
  # `builtins.tryEval` can catch.
  declaredRecord =
    {
      subject,
      module,
      where,
      value,
    }:
    if isAttrs value then
      {
        inherit value;
        rows = [ ];
      }
    else
      {
        value = { };
        rows = [
          (diag.error {
            inherit subject;
            id = "declaration-malformed";
            message = "${where} is declared as ${util.shownValue value}, and the reading needs a record";
            evidence = "a value of the wrong kind contributes nothing to the plan and the rest of ${module} is still read, which is what keeps one malformed declaration from ending the evaluation";
            resolution = "write a record for ${where}";
          })
        ];
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
      read = declaredRecord {
        inherit subject module where;
        value = slot;
      };
      declared = read.rows == [ ];
      given = read.value;
      reach = given.reach or "one";
      hasInterface = given ? interface && isInterface given.interface;
      exported = if hasInterface then interface.exportNames given.interface else [ ];
      reads = if given ? reads then given.reads else exported;
      unknownReads = if hasInterface then util.subtractList reads exported else [ ];

      slotRows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = where;
            allowed = slotKeys;
          }
        ) (util.extraKeys slotKeys given)
        ++ util.optional (given ? severity) (severityRow {
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
            message = "${where} reads ${util.quote r}, which ${interface.label reg given.interface} does not declare";
            evidence = "the interface declares ${util.quoteList exported}";
            resolution = "read a declared export in ${subject}, or declare ${util.quote r} on the interface";
          }
        ) unknownReads;
    in
    {
      inherit declared reach reads;
      rows = read.rows ++ (if declared then slotRows else [ ]);
      interface = if hasInterface then given.interface else null;
      resolvable = declared && hasInterface && elem reach reaches && unknownReads == [ ];
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
      read = declaredRecord {
        inherit subject module where;
        value = capability;
      };
      declared = read.rows == [ ];
      given = read.value;
      hasInterface = given ? interface && isInterface given.interface;

      # A capability declaring nothing admits any number of consumers, which is
      # what every capability written before this key meant.
      stated = given.consumers or null;
      known = stated == null || elem stated atoms.domains.consumerCardinality;

      capabilityRows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = where;
            allowed = capabilityKeys;
          }
        ) (util.extraKeys capabilityKeys given)
        ++ util.optional (given ? severity) (severityRow {
          inherit subject where;
        })
        ++ util.optional (!known) (
          diag.error {
            inherit subject;
            id = "capability-consumers-malformed";
            message = "${where} declares `consumers` as ${util.quote (toString stated)}";
            evidence = "the values are ${util.quoteList atoms.domains.consumerCardinality}, and a capability declaring nothing is taken by any number of slots";
            resolution = "write one of ${util.quoteList atoms.domains.consumerCardinality} in ${subject}, or omit the key";
          }
        )
        ++ util.optional (!hasInterface) (
          diag.error {
            inherit subject;
            id = "capability-interface-missing";
            message = "${where} declares no interface value";
            evidence = "a capability publishes exactly the keyset of the interface it declares, so there is nothing to check without one";
            resolution = "pass the interface value into ${subject} and write it as `provides.${name}.interface`";
          }
        );
    in
    {
      inherit declared;
      interface = if hasInterface then given.interface else null;
      consumers = if known && stated != null then stated else "many";
      rows = read.rows ++ (if declared then capabilityRows else [ ]);
    };

  readClaims =
    {
      subject,
      module,
      claims,
    }:
    let
      read = declaredRecord {
        inherit subject module;
        where = "claims of ${module}";
        value = claims;
      };
      given = read.value;
      portsRead = declaredRecord {
        inherit subject module;
        where = "the port claims of ${module}";
        value = given.ports or { };
      };
      ports = portsRead.value;

      # The three fields are refused one at a time, because the failure
      # directions differ: a number that is not a port leaves nothing to record
      # and the claim is dropped, while a refused protocol or address leaves a
      # number and is read as unstated, which compares against more rather than
      # against nothing. A claim that is not a record at all is dropped by its
      # own row rather than earning `port-claim-not-fixed` on top of it: a
      # sentence about a mistake nobody made.
      readPort =
        name: value:
        let
          where = "port claim ${util.quote name} of ${module}";
          record = declaredRecord {
            inherit
              subject
              module
              where
              value
              ;
          };
          claim = record.value;
          refuses = field: type: claim ? ${field} && type.verify claim.${field} != null;
          numberRefused = refuses "fixed" atoms.port;
          protoRefused = refuses "proto" atoms.protocol;
          addressRefused = refuses "address" atoms.bindAddress;
        in
        {
          claim =
            if record.rows != [ ] || !(claim ? fixed) || numberRefused then
              null
            else
              {
                inherit (claim) fixed;
                proto = if claim ? proto && !protoRefused then claim.proto else null;
                address = if claim ? address && !addressRefused then claim.address else null;
              };
          rows =
            if record.rows != [ ] then
              record.rows
            else
              map (
                key:
                keyRow {
                  inherit subject key where;
                  allowed = claimKeys;
                }
              ) (util.extraKeys claimKeys claim)
              ++ util.optional (!(claim ? fixed)) (
                diag.error {
                  inherit subject;
                  id = "port-claim-not-fixed";
                  message = "${where} declares no `fixed` port, and this subset allocates nothing";
                  evidence = "the condition that introduces it: ${excluded.constructs.dynamicPort.trigger}";
                  resolution = "write `claims.ports.${name}.fixed` in ${subject}, or land the change that carries the allocation table";
                }
              )
              ++ util.optional numberRefused (
                diag.error {
                  inherit subject;
                  id = "port-claim-not-a-port";
                  message = "${where} declares `fixed` with a value that is not a port, and korora reports: ${toString (atoms.port.verify claim.fixed)}";
                  evidence = "a port is an integer of ${toString atoms.portRange.first} to ${toString atoms.portRange.last}, and a number written as text is not read as the number it spells";
                  resolution = "write an integer of ${toString atoms.portRange.first} to ${toString atoms.portRange.last} at `claims.ports.${name}.fixed` in ${subject}; the claim is recorded nowhere and nothing compares it";
                }
              )
              ++ util.optional protoRefused (
                diag.error {
                  inherit subject;
                  id = "port-claim-protocol-unknown";
                  message = "${where} declares `proto` with a value the domain does not admit, and korora reports: ${toString (atoms.protocol.verify claim.proto)}";
                  evidence = "the protocols are ${util.quoteList atoms.domains.protocol}, and a claim stating none claims its number on every one of them";
                  resolution = "write one of ${util.quoteList atoms.domains.protocol} at `claims.ports.${name}.proto` in ${subject}, or omit the key; the number is recorded either way";
                }
              )
              ++ util.optional addressRefused (
                diag.error {
                  inherit subject;
                  id = "port-claim-address-malformed";
                  message = "${where} declares `address` with a value that is not an address, and korora reports: ${toString (atoms.bindAddress.verify claim.address)}";
                  evidence = "an address is a non-empty string of letters, digits and `:._%-`, and a wildcard has no spelling because the absence of the key is already every address of the machine";
                  resolution = "write the one address the listener binds at `claims.ports.${name}.address` in ${subject}, or omit the key for every address of the machine; the number is recorded either way";
                }
              );
        };

      claimReads = mapAttrs readPort ports;
    in
    {
      ports = util.filterAttrs (_: claim: claim != null) (mapAttrs (_: p: p.claim) claimReads);
      rows =
        read.rows
        ++ portsRead.rows
        ++ map (
          key:
          keyRow {
            inherit subject key;
            where = "claims of ${module}";
            allowed = [ "ports" ];
          }
        ) (util.extraKeys [ "ports" ] given)
        ++ util.concatMapAttrsToList (_: p: p.rows) claimReads;
    };

  readVars =
    {
      subject,
      module,
      storeDir,
      vars,
    }:
    let
      # What a delivered file's record may say. `secrecy` is what the plan routes
      # by; the other three are what the two writers set on the machine, and the
      # defaults are what both wrote before the keys existed, so a record
      # declaring none is the same delivered artifact it was.
      fileKeys = [
        "secrecy"
        "owner"
        "group"
        "mode"
      ];

      fileTypes = {
        owner = atoms.userName;
        group = atoms.groupName;
        mode = atoms.fileMode;
      };

      fileRows =
        gen: name: file:
        let
          where = "generated file ${util.quote "${gen}/${name}"} of ${module}";
          typed = filter (k: file ? ${k}) (attrNames fileTypes);
        in
        map (
          key:
          keyRow {
            inherit subject key where;
            allowed = fileKeys;
          }
        ) (util.extraKeys fileKeys file)
        ++ util.optional (!elem (interface.secrecyOf file) interface.secrecies) (
          diag.error {
            inherit subject;
            id = "vars-file-secrecy-domain";
            message = "${where} declares secrecy ${util.quote (toString (interface.secrecyOf file))}";
            evidence = "secrecy on a generated file takes ${util.quoteList interface.secrecies}, the same two values it takes on an export";
            resolution = "write one of ${util.quoteList interface.secrecies} in ${subject}, or omit the key";
          }
        )
        ++ map (
          key:
          diag.error {
            inherit subject;
            id = "vars-file-ownership-malformed";
            message = "${where} declares ${util.quote key} with a value that fails its field's type";
            evidence = "the record declares ${key} as ${
              util.quote fileTypes.${key}.name
            }, and korora reports: ${toString (fileTypes.${key}.verify file.${key})}";
            resolution = "write a value of that type in ${subject}; the failing value is not recorded and the default is delivered";
          }
        ) (filter (k: fileTypes.${k}.verify file.${k} != null) typed);

      # The record every reader sees, so one function decides the defaults and
      # nothing downstream writes `or "root"`. `stated` names the keys the
      # declaration actually carried, which is what keeps a record declaring none
      # of them out of the value's key.
      fileRecord =
        file:
        let
          stated = filter (k: file ? ${k} && fileTypes.${k}.verify file.${k} == null) (attrNames fileTypes);
          valueOf = k: default: if elem k stated then file.${k} else default;
        in
        {
          secrecy = interface.secrecyOf file;
          owner = valueOf "owner" "root";
          group = valueOf "group" "root";
          mode = valueOf "mode" "0400";
          stated = util.sortStrings stated;
        };

      read = declaredRecord {
        inherit subject module;
        where = "the generators of ${module}";
        value = vars;
      };

      genReads = mapAttrs (
        gen: g:
        declaredRecord {
          inherit subject module;
          where = "generator ${util.quote gen} of ${module}";
          value = g;
        }
      ) read.value;

      # A generator of the wrong kind declares no value: nothing builds a key from
      # it, and a sibling naming it reads a generator this module does not declare.
      given = util.filterAttrs (gen: _: genReads.${gen}.rows == [ ]) read.value;

      filesRead = mapAttrs (
        gen: g:
        declaredRecord {
          inherit subject module;
          where = "the files of generator ${util.quote gen} of ${module}";
          value = g.files or { };
        }
      ) given;

      fileReads = mapAttrs (
        gen: declaredFiles:
        mapAttrs (
          name: file:
          declaredRecord {
            inherit subject module;
            where = "generated file ${util.quote "${gen}/${name}"} of ${module}";
            value = file;
          }
        ) declaredFiles.value
      ) filesRead;

      filesOf =
        gen: util.filterAttrs (name: _: fileReads.${gen}.${name}.rows == [ ]) filesRead.${gen}.value;

      declared = attrNames given;

      perOf = g: if g ? per then toString g.per else "placement";
      deployOf = g: if g ? deploy then g.deploy else true;
      readsOf = g: if g ? reads && isList g.reads then filter isString g.reads else [ ];

      # A read resolves against the generators the reading kept, so a value whose
      # name the reading refused is read by nobody and no key is built from it.
      declaredReadsOf = g: filter (name: given ? ${name} && !(util.carriesKeySeparator name)) (readsOf g);

      # A program is recorded and never run, so the only thing checked is that it
      # is one store path and nothing else: that is what a consumer can hand to a
      # tool that resolves them.
      isProgram = p: isString p && util.storePathsIn storeDir p == [ p ];
      programOf = g: if g ? program && isProgram g.program then g.program else null;

      # Generators reachable from one, so a value that transitively reads itself is
      # a row rather than an infinite recursion when the plan hashes what it reads.
      reachableFrom =
        gen:
        let
          step =
            acc: util.uniqueStrings (acc ++ builtins.concatLists (map (n: declaredReadsOf given.${n}) acc));
          go =
            budget: acc:
            let
              next = step acc;
            in
            if budget == 0 || next == acc then acc else go (budget - 1) next;
        in
        go (builtins.length declared) (declaredReadsOf given.${gen});

      inCycle = gen: elem gen (reachableFrom gen);

      genRows =
        gen: g:
        let
          where = "generator ${util.quote gen} of ${module}";
          per = perOf g;
          unknownReads = filter (name: !(given ? ${name})) (readsOf g);
          coarser = coarserThan.${per} or cardinalities;
          tooNarrow = filter (name: given ? ${name} && !elem (perOf given.${name}) coarser) (readsOf g);
        in
        map (
          key:
          keyRow {
            inherit subject key;
            inherit where;
            allowed = generatorKeys;
          }
        ) (util.extraKeys generatorKeys g)
        ++ util.optional (!elem per cardinalities) (
          diag.error {
            inherit subject;
            id = "vars-per-domain";
            message = "${where} declares per ${util.quote per}, and a cardinality takes ${util.quoteList cardinalities}";
            evidence = "an omitted per means ${util.quote "placement"}: one value per machine the member is placed on, where ${util.quote "instance"} is one value for the instance";
            resolution = "write one of ${util.quoteList cardinalities} in ${subject}, or omit the key";
          }
        )
        ++ util.optional (g ? deploy && !builtins.isBool g.deploy) (
          diag.error {
            inherit subject;
            id = "vars-deploy-malformed";
            message = "${where} declares a deploy that is not a boolean";
            evidence = "`per` says how many values exist and `deploy` says whether any machine receives bytes, so it is one or the other";
            resolution = "write `deploy = false;` in ${subject}, or omit the key";
          }
        )
        ++ util.optional (g ? program && programOf g == null) (
          diag.error {
            inherit subject;
            id = "vars-program-malformed";
            message = "${where} declares a program that is not a store path";
            evidence = "a program is recorded as a literal string and neither run nor read here, and the one thing a consumer does with it is hand it to a tool that resolves store paths";
            resolution = "write the `drvPath` of the package that produces the files in ${subject}, or omit the key";
          }
        )
        ++ util.optional (g ? reads && !(isList g.reads && all isString g.reads)) (
          diag.error {
            inherit subject;
            id = "vars-reads-malformed";
            message = "${where} declares a reads that is not a list of generator names";
            evidence = "a generator reads its siblings by name, and this module declares ${util.quoteList declared}";
            resolution = "write `reads = [ <generator> … ];` in ${subject}";
          }
        )
        ++ map (
          name:
          diag.error {
            inherit subject;
            id = "vars-reads-unknown-generator";
            message = "${where} reads ${util.quote name}, which ${module} does not declare";
            evidence = "the module declares ${util.quoteList declared}";
            resolution = "read one of ${util.quoteList declared} in ${subject}, or declare ${util.quote name} beside it";
          }
        ) unknownReads
        ++ map (
          name:
          diag.error {
            inherit subject;
            id = "vars-reads-arity";
            message = "${where} has per ${util.quote per} and reads ${util.quote name}, which has per ${
              util.quote (perOf given.${name})
            }";
            evidence = "the placements hold one value each and the reader is one value, so the read has no single answer";
            resolution = "reverse it: a per ${util.quote "placement"} generator reads the one per ${util.quote "instance"} value, which is the direction that works";
          }
        ) tooNarrow
        ++ util.optional (inCycle gen) (
          diag.error {
            inherit subject;
            id = "vars-reads-cycle";
            message = "${where} reads itself through ${util.quoteList (util.sortStrings (reachableFrom gen))}";
            evidence = "a value is generated from the values it reads, so a cycle names no value that can be generated first, and the plan hashes what an entry reads";
            resolution = "break the cycle in ${subject}; the reads of a generator in a cycle are dropped, so the plan records none of them";
          }
        )
        ++ filesRead.${gen}.rows
        ++ util.concatMapAttrsToList (_: fileRead: fileRead.rows) fileReads.${gen}
        ++ util.concatMapAttrsToList (fileRows gen) (filesOf gen);
    in
    {
      # A generator's name enters the key of its own value entry, so a name
      # carrying a key separator is refused here and the generator declares no
      # value: nothing downstream builds a key from it.
      generators = builtins.mapAttrs (gen: g: {
        files = builtins.mapAttrs (_: fileRecord) (filesOf gen);
        per = if elem (perOf g) cardinalities then perOf g else "placement";
        deploy = if builtins.isBool (deployOf g) then deployOf g else true;
        reads = if inCycle gen then [ ] else util.sortStrings (declaredReadsOf g);
        program = programOf g;
      }) (util.filterAttrs (gen: _: !(util.carriesKeySeparator gen)) given);
      rows =
        read.rows
        ++ util.concatMapAttrsToList (gen: _: genReads.${gen}.rows) read.value
        ++ util.concatMapAttrsToList genRows given
        ++ map (
          gen:
          diag.error {
            inherit subject;
            id = "name-carries-key-separator";
            message = "generator ${util.quote gen} of ${module} is named with a character a plan key's structure uses, and a name a plan key is built from carries none of ${util.quoteList util.keySeparators}";
            evidence = "a generated value's key is `<instance>:vars/<generator>@<machine>`, so a name carrying one of them produces a key that takes apart into parts nothing declared";
            resolution = "rename the generator in ${subject} to a name carrying none of ${util.quoteList util.keySeparators}";
          }
        ) (filter util.carriesKeySeparator (attrNames read.value));
    };

  # The planner records a pin and resolves nothing, so this guards hand-written
  # data rather than the resolver.
  readPin =
    {
      subject,
      module,
      pin,
    }:
    let
      where = "the pin of ${module}";
      read = declaredRecord {
        inherit subject module where;
        value = pin;
      };
      given = read.value;
      lockedRead = declaredRecord {
        inherit subject module;
        where = "the locked record of ${module}";
        value = given.locked or { };
      };
      locked = lockedRead.value;
      hasLocked = lockedRead.rows == [ ];
      declared = attrNames locked;
      missing = util.subtractList lockedRequired declared;
      nonStrings = filter (n: locked ? ${n} && !isString locked.${n}) lockedKeys;

      pinRows =
        map (
          key:
          keyRow {
            inherit subject key;
            inherit where;
            allowed = pinKeys;
          }
        ) (util.extraKeys pinKeys given)
        ++ map (
          key:
          keyRow {
            inherit subject key;
            where = "the locked record of ${module}";
            allowed = lockedKeys;
          }
        ) (util.extraKeys lockedKeys locked)
        ++ util.optional (!(given ? key) || !isString given.key) (
          diag.error {
            inherit subject;
            id = "pin-malformed";
            message = "${where} declares no lock key";
            evidence = "a pin is ${util.quote "{ key, locked }"}, where `key` is the string the resolver assigned and key equality is what says whether two entries share a dependency";
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

      rows = read.rows ++ lockedRead.rows ++ (if read.rows == [ ] then pinRows else [ ]);
    in
    {
      record =
        if rows == [ ] then
          {
            inherit (given) key;
            locked = util.pickAttrs lockedKeys locked;
          }
        else
          null;
      inherit rows;
    };

  # One unit, read against the vocabulary. A field the unit did not declare is
  # absent from the record rather than stored as a null or a service manager's
  # default, so a binding can tell "not asked for" from "asked for and empty".
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

      errors = listToAttrs (
        map (k: {
          name = k;
          value = unitVocabulary.${k}.verify unit.${k};
        }) declared
      );
      failures = filter (k: errors.${k} != null) declared;
      typed = filter (k: errors.${k} == null) declared;

      references = filter (k: elem k typed) unitReferenceKeys;

      # A restart policy read against the shape the unit already declared. A
      # contradiction is a row and the field is not recorded, so no renderer is
      # handed two statements about when the unit runs.
      policy = if elem "restart" typed then unit.restart else null;
      oneShot = elem "oneShot" typed && unit.oneShot == true;
      scheduled = elem "schedule" typed;

      contradictsOneShot = oneShot && policy == "always";
      onScheduled = scheduled && policy != null && policy != "no";
      delayWithoutPolicy = elem "restartSec" typed && policy == null;

      withheld =
        util.optional (contradictsOneShot || onScheduled) "restart"
        ++ util.optional (contradictsOneShot || onScheduled || delayWithoutPolicy) "restartSec";

      recorded = util.subtractList typed withheld;

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

      grouped = builtins.groupBy (e: e.backend) applied;

      ordering = listToAttrs (
        map (k: {
          name = k;
          value = ownedIn k;
        }) references
      );

      record =
        util.filterAttrs (n: v: !(elem n unitReferenceKeys && v == [ ])) (
          util.pickAttrs recorded unit // ordering
        )
        // (
          if grouped == { } then
            { }
          else
            {
              extends = mapAttrs (_: es: builtins.foldl' (acc: e: acc // e.values) { } es) grouped;
            }
        );

      unprintable = filter (
        key:
        let
          value = record.env.${key};
        in
        builtins.isString value && builtins.match ".*[\n\r].*" value != null
      ) (attrNames (record.env or { }));

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
          let
            typeName = unitVocabulary.${key}.name;
          in
          diag.error {
            inherit subject;
            id = "unit-field-type-mismatch";
            message = "${where} declares ${util.quote key} with a value that fails its field's type";
            evidence = "the vocabulary declares ${key} as ${util.quote typeName}${
              if atoms.domains ? ${typeName} then
                ", whose values are ${util.quoteList atoms.domains.${typeName}}"
              else
                ""
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
        ++ builtins.concatLists (map (e: e.rows) extends)
        ++ map (
          key:
          diag.error {
            inherit subject;
            id = "unit-env-value-newline";
            message = "${where} sets ${util.quote key} to a value containing a line break";
            evidence = "a unit file is line oriented, so an environment assignment has no second line to put the rest on";
            resolution = "write ${util.quote key} as one line in ${module}, or write the bytes to a file the unit reads";
          }
        ) unprintable
        ++ util.optional delayWithoutPolicy (
          diag.error {
            inherit subject;
            id = "unit-restart-delay-without-policy";
            message = "${where} declares `restartSec` and no `restart`";
            evidence = "a delay says how long to wait before restarting, and a unit with no policy is never restarted, so the delay changes nothing";
            resolution = "declare `restart` beside it in ${module}, or drop `restartSec`; the delay is not recorded";
          }
        )
        ++ util.optional contradictsOneShot (
          diag.error {
            inherit subject;
            id = "unit-restart-contradicts-one-shot";
            message = "${where} declares `oneShot` and asks to be restarted always";
            evidence = "a one-shot unit applies and exits, so restarting it whenever it exits restarts it for as long as it keeps succeeding; a job that failed and may be retried declares `on-failure` instead";
            resolution = "drop `oneShot` in ${module} if the unit is long running, or write `restart = \"on-failure\"`; the policy is not recorded";
          }
        )
        ++ util.optional onScheduled (
          diag.error {
            inherit subject;
            id = "unit-restart-on-scheduled";
            message = "${where} declares a `schedule` and a restart policy of ${util.quote (toString policy)}";
            evidence = "the timer is what decides when a scheduled unit runs, so a restart policy beside it is a second schedule nobody declared";
            resolution = "drop the policy in ${module}, or drop the schedule and let the unit run continuously; the policy is not recorded";
          }
        );
    in
    {
      inherit record rows;
      extensions = applied;
    };

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

  read =
    {
      reg,
      subject,
      module,
      storeDir,
      declaration,
    }:
    let
      read = declaredRecord {
        inherit subject module;
        where = module;
        value = declaration;
      };
      given = read.value;
      claims = readClaims {
        inherit subject module;
        claims = given.claims or { };
      };
      vars = readVars {
        inherit subject module storeDir;
        vars = given.vars or { };
      };
      usesRead = declaredRecord {
        inherit subject module;
        where = "the slots of ${module}";
        value = given.uses or { };
      };
      slots = builtins.mapAttrs (
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
      ) usesRead.value;
      providesRead = declaredRecord {
        inherit subject module;
        where = "the capabilities of ${module}";
        value = given.provides or { };
      };
      capabilities = builtins.mapAttrs (
        name: capability:
        readCapability {
          inherit
            subject
            module
            name
            capability
            ;
        }
      ) providesRead.value;

      # A slot or a capability of the wrong kind declares nothing: the member asks
      # for no such slot, so no wire for it is resolved, and the capability is
      # addressable by no wire.
      uses = util.filterAttrs (_: slot: slot.declared) slots;
      provides = util.filterAttrs (_: capability: capability.declared) capabilities;

      stated = given.platforms or [ ];
      platformsOk = isList stated && all isString stated;
      platforms = if platformsOk then stated else [ ];
      pin =
        if given ? pin then
          readPin {
            inherit subject module;
            pin = given.pin;
          }
        else
          {
            record = null;
            rows = [ ];
          };

      declarationRows =
        map (
          key:
          keyRow {
            inherit subject key;
            where = module;
            allowed = moduleKeys;
          }
        ) (util.extraKeys moduleKeys given)
        ++ util.optional (given ? severity) (severityRow {
          inherit subject;
          where = module;
        })
        ++ util.optional (!platformsOk) (
          diag.error {
            inherit subject;
            id = "platforms-malformed";
            message = "${module} declares `platforms` that is not a list of strings";
            evidence = "a module states the platforms it runs on as a list of system strings, and the failing value is not recorded, so the module is read as running everywhere";
            resolution = "write a list of system strings in ${subject}";
          }
        )
        ++ util.optional (!(given ? impl) || !isFunction given.impl) (
          diag.error {
            inherit subject;
            id = "impl-missing";
            message = "${module} declares no `impl` function";
            evidence = "`impl` is what produces units, configuration data and the exports of every capability the module provides";
            resolution = "add `impl = { results, alloc, vars, settings, ... }: { ... };` to ${subject}";
          }
        )
        ++ usesRead.rows
        ++ providesRead.rows
        ++ claims.rows
        ++ vars.rows
        ++ util.concatMapAttrsToList (_: s: s.rows) slots
        ++ util.concatMapAttrsToList (_: c: c.rows) capabilities
        ++ pin.rows;
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
      impl = given.impl or null;
      rows = read.rows ++ declarationRows;
    };
}
