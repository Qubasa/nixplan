{ planner, support }:
let
  inherit (support)
    countById
    evidenceById
    hasInfix
    messageById
    planOf
    publicString
    publicUrl
    resolutionById
    rowIds
    rowsById
    severityById
    soleRoot
    subjectsById
    ;

  identity = planner.interface {
    name = "identity";
    exports.publicKey = publicString;
  };

  pair = planner.interface {
    name = "host-identity";
    exports = {
      publicKey = publicString;
      privateKey = support.secretFile;
    };
  };

  sources = {
    deployment = "deployment/instances.nix";
    machines = "deployment/machines.nix";
    modules = {
      consumer = "modules/consumer/default.nix";
      provider = "modules/provider/default.nix";
    };
    leaves = {
      consumer.only = "modules/consumer/leaf.nix";
      provider.only = "modules/provider/leaf.nix";
    };
  };

  registry."interfaces/default.nix" = { inherit identity pair; };

  provider = _: {
    provides.identity.interface = identity;
    impl = _: {
      provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  endpoint = planner.interface {
    name = "endpoint";
    exports.url = publicUrl;
  };

  publisher = _: {
    provides.endpoint.interface = endpoint;
    impl =
      { target, ... }:
      {
        provides.endpoint.exports.url = "ssh://${target.address}/srv";
        units.only.command = "/bin/true";
      };
  };

  withoutAnAddress = support.machines // {
    bare = {
      tags = [ "everywhere" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };

  # The consumer records the names of what it received, so a refused slot is
  # observable without the test touching it and aborting the suite.
  consumer =
    {
      interface ? identity,
      reach ? null,
      reads ? null,
    }:
    _: {
      uses.far = {
        inherit interface;
      }
      // (if reach == null then { } else { inherit reach; })
      // (if reads == null then { } else { inherit reads; });
      impl =
        { results, ... }:
        {
          units.only = {
            command = "/bin/true";
            env = {
              SLOTS = builtins.concatStringsSep "," (builtins.attrNames results);
              FAR = if results ? far then builtins.concatStringsSep "," (builtins.attrNames results.far) else "";
            };
          };
        };
    };

  edge =
    {
      consumerModule,
      providerModule ? provider,
      providerMachines ? [ "one" ],
      varsState ? { },
      interfaces ? registry,
      wire ? {
        instance = "provider";
        provides = "identity";
      },
    }:
    planOf {
      inherit sources varsState interfaces;
      instances = {
        consumer = {
          module = soleRoot { module = consumerModule; };
          placement.every.only.machines = [ "one" ];
        }
        // (if wire == null then { } else { wire.far = wire; });
        provider = {
          module = soleRoot {
            module = providerModule;
            provides = [ "identity" ];
          };
          placement.every.only.machines = providerMachines;
          exposes = [ "identity" ];
        };
      };
    };

  publishes =
    module:
    planOf {
      inherit sources;
      interfaces = registry;
      instances.provider = {
        module = soleRoot {
          inherit module;
          provides = [ "identity" ];
        };
        placement.every.only.machines = [ "one" ];
        exposes = [ "identity" ];
      };
    };

  # A fold is a fact about the interface, so a test binds one interface value and
  # hands it to both halves: identity is the value, never the name.
  joined =
    set:
    builtins.concatStringsSep " " (
      map (key: "${key}=${set.${key}.publicKey}") (builtins.attrNames set)
    );

  folding =
    fold:
    planner.interface {
      name = "identity";
      exports.publicKey = publicString;
      inherit fold;
    };

  namedFolding =
    name: apply:
    planner.interface {
      name = "identity";
      exports.publicKey = publicString;
      fold = planner.fold name apply;
    };

  claiming =
    args:
    planner.interface (
      {
        name = "identity";
        id = "example.com/identity";
      }
      // args
    );

  folderRegistry = iface: registry // { "interfaces/folded.nix".folded = iface; };

  providerOf = iface: _: {
    provides.identity.interface = iface;
    impl = _: {
      provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  # The folded value is what the consumer received, so it is recorded verbatim
  # rather than walked: not walking it is the point of the fold.
  folds =
    {
      iface,
      reach ? "all",
      reads ? [ "publicKey" ],
    }:
    _: {
      uses.far = {
        interface = iface;
        inherit reach reads;
      };
      impl =
        { results, ... }:
        {
          units.only = {
            command = "/bin/true";
            env = {
              SLOTS = builtins.concatStringsSep "," (builtins.attrNames results);
              FAR = if results ? far then results.far else "";
            };
          };
        };
    };

  reading =
    {
      iface,
      reach ? "all",
      reads ? [ "publicKey" ],
      providerMachines ? [ "one" ],
    }:
    edge {
      inherit providerMachines;
      interfaces = folderRegistry iface;
      providerModule = providerOf iface;
      consumerModule = folds { inherit iface reach reads; };
    };

  worked = support.workedResult;
  client = worked.plan."nightly:client@alpha";
  server = worked.plan."vault-repo:server@vault";
in
{
  testAProviderOmitsAnExport =
    let
      halfProvider = _: {
        provides.identity.interface = pair;
        impl = _: {
          provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
          units.only.command = "/bin/true";
        };
      };
      result = publishes halfProvider;
    in
    {
      expr = {
        rows = countById "provider-export-missing" result;
        subjects = subjectsById "provider-export-missing" result;
        severity = severityById "provider-export-missing" result;
        namesMissing = hasInfix "`privateKey`" (messageById "provider-export-missing" result);
        namesDeclaringFile = hasInfix "interfaces/default.nix" (
          messageById "provider-export-missing" result
        );
        namesPublishingFile = hasInfix "modules/provider/leaf.nix" (
          evidenceById "provider-export-missing" result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        subjects = [ "provider:only@one" ];
        severity = "error";
        namesMissing = true;
        namesDeclaringFile = true;
        namesPublishingFile = true;
        applicable = false;
      };
    };

  testAProviderPublishesAnExtraExport =
    let
      extraProvider = _: {
        provides.identity.interface = identity;
        impl = _: {
          provides.identity.exports = {
            publicKey = "ssh-ed25519 AAAA";
            hostName = "one.example";
          };
          units.only.command = "/bin/true";
        };
      };
      result = edge {
        consumerModule = consumer { reads = [ "publicKey" ]; };
        providerModule = extraProvider;
      };
    in
    {
      expr = {
        rows = countById "provider-export-extra" result;
        subjects = subjectsById "provider-export-extra" result;
        severity = severityById "provider-export-extra" result;
        namesExtra = hasInfix "`hostName`" (messageById "provider-export-extra" result);
        recorded = builtins.attrNames result.plan."provider:only@one".provides.identity.exports;
        keysetEqualsInterface = result.plan."provider:only@one".provides.identity.keysetEqualsInterface;
        deliveredValues = builtins.attrNames result.plan."consumer:only@one".reads.far.values;
        receivedNames = result.plan."consumer:only@one".env.FAR;
      };
      expected = {
        rows = 1;
        subjects = [ "provider:only@one" ];
        severity = "error";
        namesExtra = true;
        recorded = [ "publicKey" ];
        keysetEqualsInterface = false;
        deliveredValues = [ "publicKey" ];
        receivedNames = "publicKey";
      };
    };

  testASlotIsNeverWired =
    let
      result = edge {
        consumerModule = consumer { };
        wire = null;
      };
      env = result.plan."consumer:only@one".env;
    in
    {
      expr = {
        ids = rowIds result;
        subjects = subjectsById "slot-unwired" result;
        severity = severityById "slot-unwired" result;
        namesSlot = hasInfix "`far`" (messageById "slot-unwired" result);
        namesDeclaringFile = hasInfix "interfaces/default.nix" (evidenceById "slot-unwired" result);
        delivered = result.plan."consumer:only@one".reads.far.delivered;
        receivedSlots = env.SLOTS;
        mentionsSlot = hasInfix "far" env.SLOTS;
      };
      expected = {
        ids = [ "slot-unwired" ];
        subjects = [ "consumer:only" ];
        severity = "error";
        namesSlot = true;
        namesDeclaringFile = true;
        delivered = false;
        receivedSlots = "";
        mentionsSlot = false;
      };
    };

  testASlotDeclaresReachLocal =
    let
      result = edge {
        consumerModule = consumer { reach = "local"; };
      };
    in
    {
      expr = {
        rows = countById "slot-reach-local" result;
        severity = severityById "slot-reach-local" result;
        statesDerivation = hasInfix "`local` derives from a locality this subset does not declare" (
          messageById "slot-reach-local" result
        );
        namesTrigger = hasInfix "unix socket path or a loopback port" (
          evidenceById "slot-reach-local" result
        );
        delivered = result.plan."consumer:only@one".reads.far.delivered;
      };
      expected = {
        rows = 1;
        severity = "error";
        statesDerivation = true;
        namesTrigger = true;
        delivered = false;
      };
    };

  testReadsNamesAnExportThatDoesNotExist =
    let
      result = edge {
        consumerModule = consumer { reads = [ "hostName" ]; };
      };
    in
    {
      expr = {
        rows = countById "slot-reads-unknown-export" result;
        subjects = subjectsById "slot-reads-unknown-export" result;
        severity = severityById "slot-reads-unknown-export" result;
        namesSlot = hasInfix "`far`" (messageById "slot-reads-unknown-export" result);
        namesEntry = hasInfix "`hostName`" (messageById "slot-reads-unknown-export" result);
        namesInterface = hasInfix "`identity` (interfaces/default.nix)" (
          messageById "slot-reads-unknown-export" result
        );
        declaredListed = hasInfix "`publicKey`" (evidenceById "slot-reads-unknown-export" result);
      };
      expected = {
        rows = 1;
        subjects = [ "modules/consumer/leaf.nix" ];
        severity = "error";
        namesSlot = true;
        namesEntry = true;
        namesInterface = true;
        declaredListed = true;
      };
    };

  # The refusal this used to assert is gone: a slot may read a secret export, and
  # the read is what puts the reader's machine in the value's delivery set.
  # Nothing in this subset caps an export at machine-local, so co-placement does
  # not enter it either.
  testAConsumerAsksForThePrivateHalf =
    let
      pairProvider = _: {
        vars.identity.files."key".secrecy = "secret";
        provides.identity.interface = pair;
        impl =
          { vars, ... }:
          {
            provides.identity.exports = {
              publicKey = "ssh-ed25519 AAAA";
              privateKey = vars.identity."key";
            };
            units.only.command = "/bin/true";
          };
      };
      askFor =
        machines:
        edge {
          consumerModule = consumer {
            interface = pair;
            reads = [
              "publicKey"
              "privateKey"
            ];
          };
          providerModule = pairProvider;
          providerMachines = machines;
          varsState."provider:vars/identity@${builtins.head machines}"."key".present = true;
        };
      together = askFor [ "one" ];
      apart = askFor [ "two" ];
    in
    {
      expr = {
        togetherIds = rowIds together;
        apartIds = rowIds apart;
        togetherDelivered = together.plan."consumer:only@one".reads.far.delivered;
        apartDelivered = apart.plan."consumer:only@one".reads.far.delivered;
        readAsAReference = apart.plan."consumer:only@one".reads.far.values.privateKey;
        deliveredApart = apart.plan."provider:vars/identity@two".delivery;
        derivedApart = apart.plan."provider:vars/identity@two".deliveryDerivedFrom;
        deliveredTogether = together.plan."provider:vars/identity@one".delivery;
      };
      expected = {
        togetherIds = [ ];
        apartIds = [ ];
        togetherDelivered = true;
        apartDelivered = true;
        readAsAReference = {
          path = "/run/vars/provider/identity/key";
          secrecy = "secret";
        };
        deliveredApart = [
          "one"
          "two"
        ];
        derivedApart = [
          "consumer:only@one named privateKey in uses.far.reads"
          "provider:only@two owns it"
        ];
        deliveredTogether = [ "one" ];
      };
    };

  testAProducerUsesItsOwnSecret =
    let
      privateKey = client.provides.identity.exports.privateKey;
    in
    {
      expr = {
        rowsAtProducer = builtins.filter (row: row.subject == "nightly:client@alpha") worked.diagnostics;
        plane = privateKey.plane;
        secrecy = privateKey.secrecy;
        value = privateKey.value;
        varsInPlan = client.vars.hostKey.files."ssh_host_ed25519_key".inPlan;
        usedByItsOwnUnit = hasInfix "/run/vars/nightly/hostKey/ssh_host_ed25519_key" client.env.BORG_RSH;
      };
      expected = {
        rowsAtProducer = [ ];
        plane = "reference";
        secrecy = "secret";
        value = "/run/vars/nightly/hostKey/ssh_host_ed25519_key";
        varsInPlan = "reference";
        usedByItsOwnUnit = true;
      };
    };

  testASecretExportWithNoReader = {
    expr = {
      exports = builtins.attrNames client.provides.identity.exports;
      keysetEqualsInterface = client.provides.identity.keysetEqualsInterface;
      readBy = client.provides.identity.exports.privateKey.readBy;
      publicHalfReadBy = client.provides.identity.exports.publicKey.readBy;
      errorsAtProducer = builtins.filter (
        row: row.severity == "error" && row.subject == "nightly:client@alpha"
      ) worked.diagnostics;
    };
    expected = {
      exports = [
        "privateKey"
        "publicKey"
      ];
      keysetEqualsInterface = true;
      readBy = [ ];
      publicHalfReadBy = [ "vault-repo:server@vault" ];
      errorsAtProducer = [ ];
    };
  };

  testAWireNamesAnUnknownInstance =
    let
      result = edge {
        consumerModule = consumer { };
        wire = {
          instance = "vault";
          provides = "identity";
        };
      };
    in
    {
      expr = {
        ids = rowIds result;
        subjects = subjectsById "wire-unknown-instance" result;
        severity = severityById "wire-unknown-instance" result;
        namesSlot = hasInfix "`far`" (messageById "wire-unknown-instance" result);
        namesTarget = hasInfix "`vault`" (messageById "wire-unknown-instance" result);
        listsInstances = hasInfix "`consumer`, `provider`" (evidenceById "wire-unknown-instance" result);
        delivered = result.plan."consumer:only@one".reads.far.delivered;
      };
      expected = {
        ids = [ "wire-unknown-instance" ];
        subjects = [ "consumer:only" ];
        severity = "error";
        namesSlot = true;
        namesTarget = true;
        listsInstances = true;
        delivered = false;
      };
    };

  # Two instances wiring each other is not a cycle: a capability's exports are a
  # function of module and settings, never of a wire.
  testTwoInstancesWireEachOther = {
    expr = {
      clientRead = client.reads.repo.delivered;
      serverRead = server.reads.clients.delivered;
      clientDependsOn = client.dependsOn;
      serverDependsOn = server.dependsOn;
      clientNamesServer = builtins.any (d: hasInfix "vault-repo" d) client.dependsOn;
      serverNamesClient = builtins.any (d: hasInfix "nightly" d) server.dependsOn;
      cycleRows = builtins.filter (row: hasInfix "cycle" row.id) worked.diagnostics;
    };
    expected = {
      clientRead = true;
      serverRead = true;
      clientDependsOn = [ "machine:alpha@${worked.plan."machine:alpha".key}" ];
      serverDependsOn = [ "machine:vault@${worked.plan."machine:vault".key}" ];
      clientNamesServer = false;
      serverNamesClient = false;
      cycleRows = [ ];
    };
  };

  testASingleValuedReadOfASet =
    let
      result = edge {
        consumerModule = consumer { reads = [ "publicKey" ]; };
        providerMachines = [
          "one"
          "two"
        ];
      };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        rows = countById "reach-one-placement-count" result;
        subjects = subjectsById "reach-one-placement-count" result;
        severity = severityById "reach-one-placement-count" result;
        namesSlot = hasInfix "`far`" (messageById "reach-one-placement-count" result);
        namesBothPlacements = hasInfix "`one`, `two`" (evidenceById "reach-one-placement-count" result);
        readKeys = builtins.attrNames read;
        delivered = read.delivered;
        receivedSlots = result.plan."consumer:only@one".env.SLOTS;
      };
      expected = {
        rows = 1;
        subjects = [ "consumer:only" ];
        severity = "error";
        namesSlot = true;
        namesBothPlacements = true;
        readKeys = [
          "delivered"
          "reach"
          "reads"
          "wire"
        ];
        delivered = false;
        receivedSlots = "";
      };
    };

  testASetValuedReadOfOnePlacement =
    let
      result = edge {
        consumerModule = consumer {
          reach = "all";
          reads = [ "publicKey" ];
        };
      };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        ids = rowIds result;
        applicable = result.applicable;
        reach = read.reach;
        entryKeys = builtins.attrNames read.entries;
        entry = read.entries."provider:only@one";
        collapsed = read ? values;
        receivedNames = result.plan."consumer:only@one".env.FAR;
      };
      expected = {
        ids = [ "set-read-in-key" ];
        applicable = true;
        reach = "all";
        entryKeys = [ "provider:only@one" ];
        entry.publicKey = "ssh-ed25519 AAAA";
        collapsed = false;
        receivedNames = "provider:only@one";
      };
    };

  testAnEntryOfASetHasNoValue =
    let
      read = server.reads.clients;
    in
    {
      expr = {
        entryKeys = builtins.attrNames read.entries;
        gamma = read.entries."nightly:client@gamma";
        rows = countById "set-entry-absent" worked;
        subjects = subjectsById "set-entry-absent" worked;
        severity = severityById "set-entry-absent" worked;
        namesEntry = hasInfix "`nightly:client@gamma`" (messageById "set-entry-absent" worked);
      };
      expected = {
        entryKeys = [
          "nightly:client@alpha"
          "nightly:client@beta"
          "nightly:client@gamma"
        ];
        gamma = {
          bytes = "absent";
          publicKey = null;
          row = {
            id = "set-entry-absent";
            subject = "vault-repo:server@vault";
          };
        };
        rows = 1;
        subjects = [ "vault-repo:server@vault" ];
        severity = "error";
        namesEntry = true;
      };
    };

  testAnOmittedReachBehavesAsOne =
    let
      written = edge {
        consumerModule = consumer {
          reach = "one";
          reads = [ "publicKey" ];
        };
      };
      omitted = edge {
        consumerModule = consumer { reads = [ "publicKey" ]; };
      };
    in
    {
      expr = {
        samePlan = written.plan == omitted.plan;
        sameRows = written.diagnostics == omitted.diagnostics;
        writtenReach = written.plan."consumer:only@one".reads.far.reach;
        omittedReach = omitted.plan."consumer:only@one".reads.far.reach;
        rows = omitted.diagnostics;
      };
      expected = {
        samePlan = true;
        sameRows = true;
        writtenReach = "one";
        omittedReach = "one";
        rows = [ ];
      };
    };

  testAServicePublishesItsOwnEndpoint =
    let
      vault = worked.plan."machine:vault";
    in
    {
      expr = {
        published = server.provides.repo.exports.url.value;
        handedTheAddress = server.target.address;
        namesTheRegistryAddress = hasInfix vault.address server.provides.repo.exports.url.value;
        settingsKeys = builtins.attrNames server.settings.server;
        restatedInSettings = server.settings.server ? host;
      };
      expected = {
        published = "ssh://borg@vault.example:22/srv/borg";
        handedTheAddress = "vault.example";
        namesTheRegistryAddress = true;
        settingsKeys = [
          "port"
          "quota"
        ];
        restatedInSettings = false;
      };
    };

  testAMachineWithNoAddress =
    let
      reader = _: {
        impl =
          { machine, target, ... }:
          {
            units.only.command =
              if target ? address then
                "/bin/serve ${target.address}"
              else
                throw "machine ${machine} carries no address";
          };
      };
      result = planOf {
        machines = withoutAnAddress;
        instances.svc = {
          module = soleRoot { module = reader; };
          placement.every.only.machines = [
            "one"
            "bare"
          ];
        };
      };
      declared = result.plan."svc:only@one";
      undeclared = result.plan."svc:only@bare";
    in
    {
      expr = {
        presentWhenDeclared = declared.target.address;
        absentWhenNotDeclared = undeclared.target ? address;
        targetFields = builtins.attrNames undeclared.target;
        command = declared.units.only.command;
        rows = rowIds result;
        subjects = subjectsById "module-raised" result;
        namesTheEntryAndTheMachine = hasInfix "svc:only@bare" (messageById "module-raised" result);
        severity = severityById "module-raised" result;
      };
      expected = {
        presentWhenDeclared = "one.example:22";
        absentWhenNotDeclared = false;
        targetFields = [
          "serviceManager"
          "system"
        ];
        command = "/bin/serve one.example:22";
        rows = [ "module-raised" ];
        subjects = [ "svc:only@bare" ];
        namesTheEntryAndTheMachine = true;
        severity = "error";
      };
    };

  testTheAddressAConsumerReadsIsTheProducersNotItsOwn =
    let
      result = planOf {
        inherit sources;
        interfaces = registry;
        instances = {
          provider = {
            module = soleRoot {
              module = publisher;
              provides = [ "endpoint" ];
            };
            placement.every.only.machines = [ "one" ];
            exposes = [ "endpoint" ];
          };
          consumer = {
            module = soleRoot {
              module = _: {
                uses.far = {
                  interface = endpoint;
                  reach = "one";
                  reads = [ "url" ];
                };
                impl =
                  { results, ... }:
                  {
                    units.only = {
                      command = "/bin/true";
                      env.FAR = results.far.url;
                    };
                  };
              };
            };
            placement.every.only.machines = [ "two" ];
            wire.far = {
              instance = "provider";
              provides = "endpoint";
            };
          };
        };
      };
      consuming = result.plan."consumer:only@two";
    in
    {
      expr = {
        read = consuming.reads.far.values.url;
        inTheUnit = consuming.units.only.env.FAR;
        theProducers = result.plan."machine:one".address;
        itsOwn = hasInfix result.plan."machine:two".address consuming.reads.far.values.url;
        rows = result.diagnostics;
      };
      expected = {
        read = "ssh://one.example:22/srv";
        inTheUnit = "ssh://one.example:22/srv";
        theProducers = "one.example:22";
        itsOwn = false;
        rows = [ ];
      };
    };

  testAFoldReplacesTheProviderKeyedSet =
    let
      iface = folding joined;
      result = reading { inherit iface; };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        ids = rowIds result;
        received = result.plan."consumer:only@one".units.only.env.FAR;
        entryKeys = builtins.attrNames read.entries;
        entry = read.entries."provider:only@one";
      };
      expected = {
        ids = [ "set-read-in-key" ];
        received = "provider:only@one=ssh-ed25519 AAAA";
        entryKeys = [ "provider:only@one" ];
        entry.publicKey = "ssh-ed25519 AAAA";
      };
    };

  testAnInterfaceWithoutAFoldIsUnchanged =
    let
      result = edge {
        consumerModule = consumer {
          reach = "all";
          reads = [ "publicKey" ];
        };
      };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        ids = rowIds result;
        receivedNames = result.plan."consumer:only@one".units.only.env.FAR;
        entries = read.entries;
      };
      expected = {
        ids = [ "set-read-in-key" ];
        receivedNames = "provider:only@one";
        entries."provider:only@one".publicKey = "ssh-ed25519 AAAA";
      };
    };

  testASingleValuedReadDoesNotApplyAFold =
    let
      iface = folding joined;
      result = edge {
        interfaces = folderRegistry iface;
        providerModule = providerOf iface;
        consumerModule = consumer {
          interface = iface;
          reach = "one";
          reads = [ "publicKey" ];
        };
      };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        ids = rowIds result;
        receivedNames = result.plan."consumer:only@one".units.only.env.FAR;
        values = read.values;
        entry = read.entry;
      };
      expected = {
        ids = [ "interface-fold-unapplied" ];
        receivedNames = "publicKey";
        values.publicKey = "ssh-ed25519 AAAA";
        entry = "provider:only@one";
      };
    };

  testAFoldSeesNoExportTheSlotDidNotRead =
    let
      iface = planner.interface {
        name = "identity";
        exports = {
          publicKey = publicString;
          comment = publicString;
        };
        fold =
          set:
          builtins.concatStringsSep "," (
            builtins.concatLists (map (key: builtins.attrNames set.${key}) (builtins.attrNames set))
          );
      };
      both = _: {
        provides.identity.interface = iface;
        impl = _: {
          provides.identity.exports = {
            publicKey = "ssh-ed25519 AAAA";
            comment = "a comment";
          };
          units.only.command = "/bin/true";
        };
      };
      result = edge {
        interfaces = folderRegistry iface;
        providerModule = both;
        consumerModule = folds {
          inherit iface;
          reads = [ "publicKey" ];
        };
      };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        ids = rowIds result;
        theFoldSaw = result.plan."consumer:only@one".units.only.env.FAR;
        absentRatherThanNull = read.entries."provider:only@one" ? comment;
      };
      expected = {
        ids = [ "set-read-in-key" ];
        theFoldSaw = "publicKey";
        absentRatherThanNull = false;
      };
    };

  testAFoldDoesNotWidenADeliverySet =
    let
      exports.key = {
        type = planner.korora.secretRef;
        secrecy = "secret";
      };
      plain = planner.interface {
        name = "held-identity";
        inherit exports;
      };
      folded = planner.interface {
        name = "held-identity";
        inherit exports;
        fold = set: builtins.concatStringsSep "," (builtins.attrNames set);
      };
      holder = iface: _: {
        vars.app.files."key".secrecy = "secret";
        provides.identity.interface = iface;
        impl =
          { vars, ... }:
          {
            provides.identity.exports.key = vars.app."key";
            units.only.env.KEYFILE = vars.app."key".path;
            units.only.command = "/bin/true";
          };
      };
      run =
        iface:
        planOf {
          inherit sources;
          interfaces."interfaces/folded.nix".held = iface;
          varsState."holder:vars/app@one"."key".present = true;
          instances = {
            holder = {
              module = soleRoot {
                module = holder iface;
                provides = [ "identity" ];
              };
              placement.every.only.machines = [ "one" ];
              exposes = [ "identity" ];
            };
            consumer = {
              module = soleRoot {
                module = folds {
                  inherit iface;
                  reads = [ "key" ];
                };
              };
              placement.every.only.machines = [ "two" ];
              wire.far = {
                instance = "holder";
                provides = "identity";
              };
            };
          };
        };
      unfolded = run plain;
      applied = run folded;
      value = applied.plan."holder:vars/app@one";
      baseline = unfolded.plan."holder:vars/app@one";
    in
    {
      expr = {
        delivery = value.delivery;
        reasons = value.deliveryDerivedFrom;
        sameAsUnfolded =
          value.delivery == baseline.delivery && value.deliveryDerivedFrom == baseline.deliveryDerivedFrom;
        theFoldRan = applied.plan."consumer:only@two".units.only.env.FAR;
      };
      expected = {
        delivery = [
          "one"
          "two"
        ];
        reasons = [
          "consumer:only@two named key in uses.far.reads"
          "holder:only@one owns it"
        ];
        sameAsUnfolded = true;
        theFoldRan = "holder:only@one";
      };
    };

  testTheFoldsInputIsKeyedByProviderEntry =
    let
      iface = folding (set: builtins.concatStringsSep "," (builtins.attrNames set));
      run = reading {
        inherit iface;
        providerMachines = [
          "one"
          "two"
        ];
      };
      again = reading {
        inherit iface;
        providerMachines = [
          "one"
          "two"
        ];
      };
    in
    {
      expr = {
        keys = run.plan."consumer:only@one".units.only.env.FAR;
        stable = run.plan == again.plan;
      };
      expected = {
        keys = "provider:only@one,provider:only@two";
        stable = true;
      };
    };

  testAFoldRaises =
    let
      iface = folding (
        set: throw "two providers export ${toString (builtins.length (builtins.attrNames set))} of one key"
      );
      result = reading { inherit iface; };
    in
    {
      expr = {
        ids = rowIds result;
        subjects = subjectsById "interface-fold-raised" result;
        severity = severityById "interface-fold-raised" result;
        namesTheInterface = hasInfix "identity" (messageById "interface-fold-raised" result);
        namesTheSlot = hasInfix "`far`" (messageById "interface-fold-raised" result);
        applicable = result.applicable;
        theProviderIsStillPlanned =
          result.plan."provider:only@one".provides.identity.exports.publicKey.value;
      };
      expected = {
        ids = [ "interface-fold-raised" ];
        subjects = [ "consumer:only" ];
        severity = "error";
        namesTheInterface = true;
        namesTheSlot = true;
        applicable = false;
        theProviderIsStillPlanned = "ssh-ed25519 AAAA";
      };
    };

  testARefusedFoldLeavesTheSlotAbsent =
    let
      iface = folding (_: throw "no");
      result = reading { inherit iface; };
      read = result.plan."consumer:only@one".reads.far;
    in
    {
      expr = {
        receivedSlots = result.plan."consumer:only@one".units.only.env.SLOTS;
        delivered = read.delivered;
        noEntries = read ? entries;
        readKeys = builtins.attrNames read;
      };
      expected = {
        receivedSlots = "";
        delivered = false;
        noEntries = false;
        readKeys = [
          "delivered"
          "reach"
          "reads"
          "wire"
        ];
      };
    };

  testAGuardedConsumerStillReportsARefusedFold =
    let
      why = "no provider of this set publishes a rotatable key";
      iface = folding (_: {
        refused = why;
      });
      guarded = _: {
        uses.far = {
          interface = iface;
          reach = "all";
          reads = [ "publicKey" ];
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              env.FAR = if results ? far then results.far else "<undelivered>";
            };
          };
      };
      consuming = {
        module = soleRoot { module = guarded; };
        placement.every.only.machines = [ "one" ];
        wire.far = {
          instance = "provider";
          provides = "identity";
        };
      };
      result = planOf {
        sources = sources // {
          modules = sources.modules // {
            authz = "modules/authz/default.nix";
            hosts = "modules/hosts/default.nix";
          };
          leaves = sources.leaves // {
            authz.only = "modules/authz/leaf.nix";
            hosts.only = "modules/hosts/leaf.nix";
          };
        };
        interfaces = folderRegistry iface;
        instances = {
          provider = {
            module = soleRoot {
              module = providerOf iface;
              provides = [ "identity" ];
            };
            placement.every.only.machines = [
              "one"
              "two"
            ];
            exposes = [ "identity" ];
          };
          authz = consuming;
          hosts = consuming;
        };
      };
    in
    {
      expr = {
        ids = rowIds result;
        subjects = subjectsById "interface-fold-refused" result;
        messages = map (r: r.message) result.diagnostics;
        delivered = [
          result.plan."authz:only@one".reads.far.delivered
          result.plan."hosts:only@one".reads.far.delivered
        ];
        rendered = result.plan."authz:only@one".units.only.env.FAR;
        applicable = result.applicable;
        planKeys = builtins.attrNames result.plan;
      };
      expected = {
        ids = [
          "interface-fold-refused"
          "interface-fold-refused"
        ];
        subjects = [
          "authz:only"
          "hosts:only"
        ];
        messages = [
          why
          why
        ];
        delivered = [
          false
          false
        ];
        rendered = "<undelivered>";
        applicable = false;
        planKeys = [
          "authz:only@one"
          "hosts:only@one"
          "machine:one"
          "machine:two"
          "provider:only@one"
          "provider:only@two"
        ];
      };
    };

  testTwoConsumersOfOneFoldReceiveOneValue =
    let
      iface = folding (
        set:
        map (key: {
          entry = key;
          inherit (set.${key}) publicKey;
        }) (builtins.attrNames set)
      );
      authorizedKeys =
        records: builtins.concatStringsSep "\n" (map (r: "# ${r.entry}\n${r.publicKey}") records);
      knownHosts = records: builtins.concatStringsSep "," (map (r: "${r.entry}=${r.publicKey}") records);
      rendering = render: _: {
        uses.far = {
          interface = iface;
          reach = "all";
          reads = [ "publicKey" ];
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              env.FOLDED = builtins.toJSON results.far;
            };
            configData."/etc/identity" = {
              mode = "0444";
              reload = [ "only" ];
              render = [ { text = render results.far; } ];
            };
          };
      };
      consuming = module: {
        module = soleRoot { inherit module; };
        placement.every.only.machines = [ "one" ];
        wire.far = {
          instance = "provider";
          provides = "identity";
        };
      };
      result = planOf {
        sources = sources // {
          modules = sources.modules // {
            authz = "modules/authz/default.nix";
            hosts = "modules/hosts/default.nix";
          };
          leaves = sources.leaves // {
            authz.only = "modules/authz/leaf.nix";
            hosts.only = "modules/hosts/leaf.nix";
          };
        };
        interfaces = folderRegistry iface;
        instances = {
          provider = {
            module = soleRoot {
              module = providerOf iface;
              provides = [ "identity" ];
            };
            placement.every.only.machines = [
              "one"
              "two"
            ];
            exposes = [ "identity" ];
          };
          authz = consuming (rendering authorizedKeys);
          hosts = consuming (rendering knownHosts);
        };
      };
      authzUnit = result.plan."authz:only@one".units.only;
      hostsUnit = result.plan."hosts:only@one".units.only;
      authzFile = result.plan."authz:only@one".configData."/etc/identity";
      hostsFile = result.plan."hosts:only@one".configData."/etc/identity";
    in
    {
      expr = {
        ids = rowIds result;
        onePolicyOneValue = authzUnit.env.FOLDED == hostsUnit.env.FOLDED;
        folded = authzUnit.env.FOLDED;
        authorized = (builtins.head authzFile.render).text;
        known = (builtins.head hostsFile.render).text;
        twoOutputs = authzFile.contentHash != hostsFile.contentHash;
        applicable = result.applicable;
      };
      expected = {
        ids = [
          "set-read-in-key"
          "set-read-in-key"
        ];
        onePolicyOneValue = true;
        folded = ''[{"entry":"provider:only@one","publicKey":"ssh-ed25519 AAAA"},{"entry":"provider:only@two","publicKey":"ssh-ed25519 AAAA"}]'';
        authorized = "# provider:only@one\nssh-ed25519 AAAA\n# provider:only@two\nssh-ed25519 AAAA";
        known = "provider:only@one=ssh-ed25519 AAAA,provider:only@two=ssh-ed25519 AAAA";
        twoOutputs = true;
        applicable = true;
      };
    };

  testTwoConsumersReadingDifferentExportsFoldDifferentSets =
    let
      iface = planner.interface {
        name = "identity";
        exports = {
          publicKey = publicString;
          comment = publicString;
        };
        fold =
          set:
          builtins.concatStringsSep ";" (
            map (key: "${key}=${builtins.concatStringsSep "," (builtins.attrNames set.${key})}") (
              builtins.attrNames set
            )
          );
      };
      both = _: {
        provides.identity.interface = iface;
        impl = _: {
          provides.identity.exports = {
            publicKey = "ssh-ed25519 AAAA";
            comment = "a comment";
          };
          units.only.command = "/bin/true";
        };
      };
      consuming = reads: {
        module = soleRoot { module = folds { inherit iface reads; }; };
        placement.every.only.machines = [ "one" ];
        wire.far = {
          instance = "provider";
          provides = "identity";
        };
      };
      result = planOf {
        sources = sources // {
          modules = sources.modules // {
            authz = "modules/authz/default.nix";
            hosts = "modules/hosts/default.nix";
          };
          leaves = sources.leaves // {
            authz.only = "modules/authz/leaf.nix";
            hosts.only = "modules/hosts/leaf.nix";
          };
        };
        interfaces = folderRegistry iface;
        instances = {
          provider = {
            module = soleRoot {
              module = both;
              provides = [ "identity" ];
            };
            placement.every.only.machines = [
              "one"
              "two"
            ];
            exposes = [ "identity" ];
          };
          authz = consuming [ "publicKey" ];
          hosts = consuming [
            "publicKey"
            "comment"
          ];
        };
      };
    in
    {
      expr = {
        ids = rowIds result;
        authzFolded = result.plan."authz:only@one".units.only.env.FAR;
        hostsFolded = result.plan."hosts:only@one".units.only.env.FAR;
        absentRatherThanNull = result.plan."authz:only@one".reads.far.entries."provider:only@one" ? comment;
        hostsSawBoth =
          builtins.attrNames
            result.plan."hosts:only@one".reads.far.entries."provider:only@one";
        applicable = result.applicable;
      };
      expected = {
        ids = [
          "set-read-in-key"
          "set-read-in-key"
        ];
        authzFolded = "provider:only@one=publicKey;provider:only@two=publicKey";
        hostsFolded = "provider:only@one=comment,publicKey;provider:only@two=comment,publicKey";
        absentRatherThanNull = false;
        hostsSawBoth = [
          "comment"
          "publicKey"
        ];
        applicable = true;
      };
    };

  testAFoldNobodyReaches =
    let
      iface = folding joined;
      result = edge {
        interfaces = folderRegistry iface;
        providerModule = providerOf iface;
        consumerModule = consumer {
          interface = iface;
          reach = "one";
          reads = [ "publicKey" ];
        };
      };
    in
    {
      expr = {
        ids = rowIds result;
        subjects = subjectsById "interface-fold-unapplied" result;
        severity = severityById "interface-fold-unapplied" result;
        namesTheInterface = hasInfix "identity" (messageById "interface-fold-unapplied" result);
        applicable = result.applicable;
      };
      expected = {
        ids = [ "interface-fold-unapplied" ];
        subjects = [ "interfaces/folded.nix" ];
        severity = "warning";
        namesTheInterface = true;
        applicable = true;
      };
    };

  testAFoldAppliedAtLeastOnce =
    let
      iface = folding joined;
      twoSlots = _: {
        uses = {
          far = {
            interface = iface;
            reach = "all";
            reads = [ "publicKey" ];
          };
          near = {
            interface = iface;
            reach = "one";
            reads = [ "publicKey" ];
          };
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              env.FAR = results.far;
            };
          };
      };
      result = planOf {
        inherit sources;
        interfaces = folderRegistry iface;
        instances = {
          provider = {
            module = soleRoot {
              module = providerOf iface;
              provides = [ "identity" ];
            };
            placement.every.only.machines = [ "one" ];
            exposes = [ "identity" ];
          };
          consumer = {
            module = soleRoot { module = twoSlots; };
            placement.every.only.machines = [ "one" ];
            wire = {
              far = {
                instance = "provider";
                provides = "identity";
              };
              near = {
                instance = "provider";
                provides = "identity";
              };
            };
          };
        };
      };
    in
    {
      expr = {
        unapplied = countById "interface-fold-unapplied" result;
        ids = rowIds result;
        theSetReadWasFolded = result.plan."consumer:only@one".units.only.env.FAR;
      };
      expected = {
        unapplied = 0;
        ids = [ "set-read-in-key" ];
        theSetReadWasFolded = "provider:only@one=ssh-ed25519 AAAA";
      };
    };

  testAFoldNameThatIsNotAName =
    let
      iface = namedFolding "" joined;
      result = edge {
        consumerModule = consumer {
          interface = iface;
          reach = "all";
          reads = [ "publicKey" ];
        };
        providerModule = providerOf iface;
        interfaces = folderRegistry iface;
        providerMachines = [
          "one"
          "two"
        ];
      };
      row = builtins.head (rowsById "interface-fold-name-malformed" result);
    in
    {
      expr = {
        rows = countById "interface-fold-name-malformed" result;
        inherit (row) subject severity;
        namesWhatWasWritten = hasInfix "names its fold ``" row.message;
        statesTheConsequence = hasInfix "the fold is not applied" row.evidence;
        unfolded = result.plan."consumer:only@one".units.only.env.FAR;
        delivered = result.plan."consumer:only@one".reads.far.delivered;
      };
      expected = {
        rows = 1;
        subject = "interfaces/folded.nix";
        severity = "error";
        namesWhatWasWritten = true;
        statesTheConsequence = true;
        unfolded = "provider:only@one,provider:only@two";
        delivered = true;
      };
    };

  # Only the provider's interface is attributed, so the registry pass sees one
  # claim and the row can only have come from the wire.
  testOneClaimAndTwoExportKeysets =
    let
      mine = claiming {
        exports = {
          publicKey = publicString;
          hostName = publicString;
        };
      };
      theirs = claiming { exports.publicKey = publicString; };
      result = edge {
        consumerModule = consumer {
          interface = mine;
          reads = [ "publicKey" ];
        };
        providerModule = providerOf theirs;
        interfaces."interfaces/theirs.nix".identity = theirs;
      };
      row = builtins.head (rowsById "interface-id-conflict" result);
    in
    {
      expr = {
        ids = rowIds result;
        inherit (row) subject severity;
        namesTheId = hasInfix "`example.com/identity`" row.message;
        namesTheAttributedFile = hasInfix "interfaces/theirs.nix" row.message;
        namesTheDifference = hasInfix "the first declares `hostName` and the second does not" row.evidence;
        delivered = result.plan."consumer:only@one".reads.far.delivered;
        receivedSlots = result.plan."consumer:only@one".units.only.env.SLOTS;
        everyOtherEntry = builtins.attrNames result.plan;
        applicable = result.applicable;
      };
      expected = {
        ids = [
          "interface-id-conflict"
          "interface-mismatch"
        ];
        subject = "interface:identity";
        severity = "error";
        namesTheId = true;
        namesTheAttributedFile = true;
        namesTheDifference = true;
        delivered = false;
        receivedSlots = "";
        everyOtherEntry = [
          "consumer:only@one"
          "machine:one"
          "provider:only@one"
        ];
        applicable = false;
      };
    };

  testOneConflictObservedTwiceIsOneRow =
    let
      mine = claiming {
        exports = {
          publicKey = publicString;
          hostName = publicString;
        };
      };
      theirs = claiming { exports.publicKey = publicString; };
      interfaces = {
        "interfaces/mine.nix".identity = mine;
        "interfaces/theirs.nix".identity = theirs;
      };
      wired = edge {
        consumerModule = consumer {
          interface = mine;
          reads = [ "publicKey" ];
        };
        providerModule = providerOf theirs;
        inherit interfaces;
      };
      attributed = planOf {
        inherit sources interfaces;
        instances = { };
      };
    in
    {
      expr = {
        wiredRows = countById "interface-id-conflict" wired;
        attributedRows = countById "interface-id-conflict" attributed;
        oneAndTheSameRow =
          rowsById "interface-id-conflict" wired == rowsById "interface-id-conflict" attributed;
      };
      expected = {
        wiredRows = 1;
        attributedRows = 1;
        oneAndTheSameRow = true;
      };
    };

  testARefusedEdgeNamesTheRuleThatRefusedIt =
    let
      publishing = iface: ename: _: {
        provides.identity.interface = iface;
        impl = _: {
          provides.identity.exports.${ename} = "k";
          units.only.command = "/bin/true";
        };
      };
      refusing =
        {
          mine,
          theirs,
          publishes ? "publicKey",
        }:
        planOf {
          inherit sources;
          interfaces = {
            "interfaces/mine.nix".identity = mine;
            "interfaces/theirs.nix".identity = theirs;
          };
          instances = {
            consumer = {
              module = soleRoot {
                module = consumer {
                  interface = mine;
                  reads = [ "publicKey" ];
                };
              };
              placement.every.only.machines = [ "one" ];
              wire.far = {
                instance = "provider";
                provides = "identity";
              };
            };
            provider = {
              module = soleRoot {
                module = publishing theirs publishes;
                provides = [ "identity" ];
              };
              placement.every.only.machines = [ "one" ];
              exposes = [ "identity" ];
            };
          };
        };
      byClaim = refusing {
        mine = claiming { exports.publicKey = publicString; };
        theirs = claiming {
          exports.publicKey = publicString;
          id = "example.com/other-identity";
        };
      };
      byName = refusing {
        mine = planner.interface {
          name = "identity";
          exports.publicKey = publicString;
        };
        theirs = planner.interface {
          name = "identity";
          exports.hostKey = publicString;
        };
        publishes = "hostKey";
      };
      byValue = refusing {
        mine = claiming { exports.publicKey = publicString; };
        theirs = planner.interface {
          name = "host-identity";
          exports.hostKey = publicString;
        };
        publishes = "hostKey";
      };
    in
    {
      expr = {
        counts = map (countById "interface-mismatch") [
          byClaim
          byName
          byValue
        ];
        severities = map (severityById "interface-mismatch") [
          byClaim
          byName
          byValue
        ];
        evidence = map (evidenceById "interface-mismatch") [
          byClaim
          byName
          byValue
        ];
        claimResolution = hasInfix "make the two claims one identity" (
          resolutionById "interface-mismatch" byClaim
        );
        valueResolution = hasInfix "import the interface the far end declares" (
          resolutionById "interface-mismatch" byValue
        );
      };
      expected = {
        counts = [
          1
          1
          1
        ];
        severities = [
          "error"
          "error"
          "error"
        ];
        evidence = [
          "both ends claim an identity and the two claims differ, so the values were never compared"
          "the two interfaces carry one name and are different values, which is why a row renders the declaring file beside the name"
          "the two are different values and at most one of them claims an identity, so an interface is identified by the value an author imported, never by its name"
        ];
        claimResolution = true;
        valueResolution = true;
      };
    };

  # Two interface values differing only in the label an identity ignores, so an
  # edge between them can only have matched by claim.
  testOneClaimAndOneShapeMatch =
    let
      mine = claiming { exports.publicKey = publicString; };
      theirs = claiming {
        name = "host-identity";
        exports.publicKey = publicString;
      };
      run =
        slotInterface:
        edge {
          consumerModule = consumer {
            interface = slotInterface;
            reads = [ "publicKey" ];
          };
          providerModule = providerOf theirs;
          interfaces = {
            "interfaces/mine.nix".identity = mine;
            "interfaces/theirs.nix".identity = theirs;
          };
        };
      claimed = run mine;
      byValue = run theirs;
    in
    {
      expr = {
        distinctValues = mine != theirs;
        ids = rowIds claimed;
        delivered = claimed.plan."consumer:only@one".reads.far.delivered;
        received = claimed.plan."consumer:only@one".units.only.env.FAR;
        sameReadAsOneValue =
          claimed.plan."consumer:only@one".reads.far == byValue.plan."consumer:only@one".reads.far;
      };
      expected = {
        distinctValues = true;
        ids = [ ];
        delivered = true;
        received = "publicKey";
        sameReadAsOneValue = true;
      };
    };

  testAClaimDoesNotWidenARead =
    let
      exports = {
        publicKey = publicString;
        key = {
          type = planner.korora.secretRef;
          secrecy = "secret";
        };
      };
      mine = claiming { inherit exports; };
      theirs = claiming {
        name = "host-identity";
        inherit exports;
      };
      holder = _: {
        vars.app.files."key".secrecy = "secret";
        provides.identity.interface = theirs;
        impl =
          { vars, ... }:
          {
            provides.identity.exports = {
              publicKey = "ssh-ed25519 AAAA";
              key = vars.app."key";
            };
            units.only.command = "/bin/true";
          };
      };
      run =
        slotInterface:
        planOf {
          inherit sources;
          interfaces = {
            "interfaces/mine.nix".identity = mine;
            "interfaces/theirs.nix".identity = theirs;
          };
          varsState."holder:vars/app@one"."key".present = true;
          instances = {
            holder = {
              module = soleRoot {
                module = holder;
                provides = [ "identity" ];
              };
              placement.every.only.machines = [ "one" ];
              exposes = [ "identity" ];
            };
            consumer = {
              module = soleRoot {
                module = consumer {
                  interface = slotInterface;
                  reads = [ "publicKey" ];
                };
              };
              placement.every.only.machines = [ "two" ];
              wire.far = {
                instance = "holder";
                provides = "identity";
              };
            };
          };
        };
      claimed = run mine;
      byValue = run theirs;
      value = claimed.plan."holder:vars/app@one";
    in
    {
      expr = {
        ids = rowIds claimed;
        received = claimed.plan."consumer:only@two".units.only.env.FAR;
        delivery = value.delivery;
        reasons = value.deliveryDerivedFrom;
        sameAsOneValue =
          value.delivery == byValue.plan."holder:vars/app@one".delivery
          && value.deliveryDerivedFrom == byValue.plan."holder:vars/app@one".deliveryDerivedFrom;
      };
      expected = {
        ids = [ ];
        received = "publicKey";
        delivery = [ "one" ];
        reasons = [ "holder:only@one owns it" ];
        sameAsOneValue = true;
      };
    };

  testEachSideVerifiesAgainstItsOwnValue =
    let
      exports.endpoint = publicUrl;
      mine = claiming { inherit exports; };
      theirs = claiming {
        name = "host-endpoint";
        inherit exports;
      };
      publisher = _: {
        provides.identity.interface = theirs;
        impl = _: {
          provides.identity.exports.endpoint = "not-a-url";
          units.only.command = "/bin/true";
        };
      };
      result = edge {
        consumerModule = consumer {
          interface = mine;
          reads = [ "endpoint" ];
        };
        providerModule = publisher;
        interfaces = {
          "interfaces/mine.nix".identity = mine;
          "interfaces/theirs.nix".identity = theirs;
        };
      };
      row = builtins.head (rowsById "export-type-mismatch" result);
    in
    {
      expr = {
        rows = countById "export-type-mismatch" result;
        mismatches = countById "interface-mismatch" result;
        inherit (row) subject;
        namesThePublishersOwnInterface = hasInfix "interfaces/theirs.nix" row.evidence;
        quotesTheVerification = hasInfix "declares endpoint as `url`, and korora reports:" row.evidence;
      };
      expected = {
        rows = 1;
        mismatches = 0;
        subject = "provider:only@one";
        namesThePublishersOwnInterface = true;
        quotesTheVerification = true;
      };
    };

  testTwoTypeNamesAgreeAndTwoPredicatesDoNot =
    let
      strict = planner.korora.typedef "hostKey" (
        v: builtins.isString v && builtins.match "ssh-.*" v != null
      );
      loose = planner.korora.typedef "hostKey" (v: builtins.isString v);
      mine = claiming { exports.publicKey.type = strict; };
      theirs = claiming {
        name = "host-identity";
        exports.publicKey.type = loose;
      };
      publisher = _: {
        provides.identity.interface = theirs;
        impl = _: {
          provides.identity.exports.publicKey = "k";
          units.only.command = "/bin/true";
        };
      };
      result = edge {
        consumerModule = consumer {
          interface = mine;
          reads = [ "publicKey" ];
        };
        providerModule = publisher;
        interfaces = {
          "interfaces/mine.nix".identity = mine;
          "interfaces/theirs.nix".identity = theirs;
        };
      };
    in
    {
      expr = {
        oneIdentity = planner.identityOf mine == planner.identityOf theirs;
        thePredicatesDisagree = strict.verify "k" != null && loose.verify "k" == null;
        ids = rowIds result;
        delivered = result.plan."consumer:only@one".reads.far.delivered;
        received = result.plan."consumer:only@one".reads.far.values.publicKey;
      };
      expected = {
        oneIdentity = true;
        thePredicatesDisagree = true;
        ids = [ ];
        delivered = true;
        received = "k";
      };
    };

  testANamedFoldIsPartOfTheClaim =
    let
      folded =
        label:
        planner.fold "union" (set: "${label}:${builtins.concatStringsSep "," (builtins.attrNames set)}");
      mine = claiming {
        exports.publicKey = publicString;
        fold = folded "mine";
      };
      theirs = claiming {
        name = "host-identity";
        exports.publicKey = publicString;
        fold = folded "theirs";
      };
      result = edge {
        consumerModule = folds {
          iface = mine;
          reads = [ "publicKey" ];
        };
        providerModule = providerOf theirs;
        interfaces = {
          "interfaces/mine.nix".identity = mine;
          "interfaces/theirs.nix".identity = theirs;
        };
      };
    in
    {
      expr = {
        distinctValues = mine != theirs;
        oneIdentity = planner.identityOf mine == planner.identityOf theirs;
        ids = rowIds result;
        delivered = result.plan."consumer:only@one".reads.far.delivered;
        theConsumersOwnFoldRan = result.plan."consumer:only@one".units.only.env.FAR;
      };
      expected = {
        distinctValues = true;
        oneIdentity = true;
        ids = [ "set-read-in-key" ];
        delivered = true;
        theConsumersOwnFoldRan = "mine:provider:only@one";
      };
    };

  testANamedFoldFolds =
    let
      run =
        iface:
        reading {
          inherit iface;
          providerMachines = [
            "one"
            "two"
          ];
        };
      named = run (namedFolding "union" joined);
      bare = run (folding joined);
    in
    {
      expr = {
        ids = rowIds named;
        received = named.plan."consumer:only@one".units.only.env.FAR;
        sameAsTheBareSpelling =
          named.plan."consumer:only@one".units.only.env.FAR
          == bare.plan."consumer:only@one".units.only.env.FAR;
      };
      expected = {
        ids = [ "set-read-in-key" ];
        received = "provider:only@one=ssh-ed25519 AAAA provider:only@two=ssh-ed25519 AAAA";
        sameAsTheBareSpelling = true;
      };
    };

  testARaisingNamedFold =
    let
      raising = _: throw "no provider of this set can be folded";
      named = reading { iface = namedFolding "union" raising; };
      bare = reading { iface = folding raising; };
    in
    {
      expr = {
        ids = rowIds named;
        theSameRowAsABareFold =
          rowsById "interface-fold-raised" named == rowsById "interface-fold-raised" bare;
        receivedSlots = named.plan."consumer:only@one".units.only.env.SLOTS;
        delivered = named.plan."consumer:only@one".reads.far.delivered;
      };
      expected = {
        ids = [ "interface-fold-raised" ];
        theSameRowAsABareFold = true;
        receivedSlots = "";
        delivered = false;
      };
    };

  testABareFoldStaysLegal =
    let
      iface = folding joined;
      result = reading { inherit iface; };
    in
    {
      expr = {
        ids = rowIds result;
        theFoldRan = result.plan."consumer:only@one".units.only.env.FAR;
        claimed = planner.identityOf iface;
      };
      expected = {
        ids = [ "set-read-in-key" ];
        theFoldRan = "provider:only@one=ssh-ed25519 AAAA";
        claimed = null;
      };
    };

  testTwoInterfacesShareANameAndOneIdentity =
    let
      mine = claiming { exports.publicKey = publicString; };
      theirs = claiming { exports.hostName = publicString; };
      sharing = claiming {
        id = "example.com/shared-identity";
        exports.publicKey = publicString;
      };
      alsoSharing = claiming {
        id = "example.com/shared-identity";
        exports.publicKey = {
          type = planner.korora.string;
          secrecy = "public";
        };
      };
      run =
        slot: far:
        edge {
          consumerModule = consumer {
            interface = slot;
            reads = [ "publicKey" ];
          };
          providerModule = providerOf far;
          interfaces = {
            "interfaces/mine.nix".identity = slot;
            "interfaces/theirs.nix".identity = far;
          };
        };
      claimed = run sharing alsoSharing;
      unclaimed = run mine theirs;
    in
    {
      expr = {
        oneName = sharing.name == alsoSharing.name && mine.name == theirs.name;
        distinctValues = sharing != alsoSharing;
        claimedMismatches = countById "interface-mismatch" claimed;
        claimedDelivered = claimed.plan."consumer:only@one".reads.far.delivered;
        unclaimedMismatches = countById "interface-mismatch" unclaimed;
      };
      expected = {
        oneName = true;
        distinctValues = true;
        claimedMismatches = 0;
        claimedDelivered = true;
        unclaimedMismatches = 1;
      };
    };
}
