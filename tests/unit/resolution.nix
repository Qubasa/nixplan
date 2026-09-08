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
    rowIds
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
      privateKey = publicString // {
        secrecy = "secret";
      };
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
      wire ? {
        instance = "provider";
        provides = "identity";
      },
    }:
    planOf {
      inherit sources;
      interfaces = registry;
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

  testAConsumerAsksForThePrivateHalf =
    let
      pairProvider = _: {
        provides.identity.interface = pair;
        impl = _: {
          provides.identity.exports = {
            publicKey = "ssh-ed25519 AAAA";
            privateKey = "PRIVATE";
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
        };
      together = askFor [ "one" ];
      apart = askFor [ "two" ];
    in
    {
      expr = {
        togetherIds = rowIds together;
        apartIds = rowIds apart;
        severity = severityById "slot-reads-secret-export" apart;
        namesSlot = hasInfix "`far`" (messageById "slot-reads-secret-export" apart);
        namesExport = hasInfix "`privateKey`" (messageById "slot-reads-secret-export" apart);
        namesDeclaringFile = hasInfix "interfaces/default.nix" (
          messageById "slot-reads-secret-export" apart
        );
        togetherDelivered = together.plan."consumer:only@one".reads.far.delivered;
        apartDelivered = apart.plan."consumer:only@one".reads.far.delivered;
      };
      expected = {
        togetherIds = [ "slot-reads-secret-export" ];
        apartIds = [ "slot-reads-secret-export" ];
        severity = "error";
        namesSlot = true;
        namesExport = true;
        namesDeclaringFile = true;
        togetherDelivered = false;
        apartDelivered = false;
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
        usedByItsOwnUnit = hasInfix "/run/vars/hostKey/ssh_host_ed25519_key" client.env.BORG_RSH;
      };
      expected = {
        rowsAtProducer = [ ];
        plane = "reference";
        secrecy = "secret";
        value = "/run/vars/hostKey/ssh_host_ed25519_key";
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
}
