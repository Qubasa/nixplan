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
    rowsById
    severityById
    soleRoot
    subjectsById
    ;

  inherit (builtins)
    attrNames
    attrValues
    concatLists
    elem
    filter
    mapAttrs
    ;

  compositionIds = [
    "settings-fixed-path"
    "settings-undeclared-knob"
    "settings-not-member-keyed"
    "placement-unknown-member"
    "placement-unknown-machine"
    "member-not-placed"
    "exposes-unknown-capability"
    "port-claim-not-fixed"
    "wire-capability-not-exposed"
    "wire-unknown-capability"
    "wire-unknown-instance"
  ];

  settingsLeaf = _: {
    impl =
      { settings, ... }:
      {
        units.main.command = "/bin/run --quota ${toString (settings.quota or "-")} --port ${
          toString (settings.port or "-")
        }";
      };
  };

  portLeaf = fixed: _: {
    claims.ports.ssh = {
      proto = "tcp";
      count = 1;
    }
    // (if fixed == null then { } else { inherit fixed; });
    impl =
      { alloc, ... }:
      {
        units.main.command = "/bin/sshd -p ${toString (alloc.ports.ssh or "-")}";
      };
  };

  twoCapProvider = _: {
    provides.identity.interface = identity;
    provides.repo.interface = repository;
    impl = _: {
      provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
      provides.repo.exports.url = "ssh://borg@vault.example:22/srv/borg";
      units.only.command = "/bin/true";
    };
  };

  consumer = _: {
    uses.far = {
      interface = identity;
      reads = [ "publicKey" ];
    };
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  identity = planner.interface {
    name = "ssh-host-identity";
    exports.publicKey = publicString;
  };

  repository = planner.interface {
    name = "borg-repository";
    exports.url = publicUrl;
  };

  database = planner.interface {
    name = "postgres-database";
    exports.dsn = publicString;
  };

  perDatabaseLeaf =
    { settings, ... }:
    let
      names = settings.databases or [ "builtin" ];
      each =
        f:
        builtins.listToAttrs (
          map (db: {
            name = db;
            value = f db;
          }) names
        );
    in
    {
      provides = each (_: {
        interface = database;
      });
      impl = _: {
        provides = each (db: {
          exports.dsn = "postgresql:///${db}";
        });
        units.main.command = "/bin/postgres";
      };
    };

  databaseReader = _: {
    uses.db = {
      interface = database;
      reads = [ "dsn" ];
    };
    impl =
      { results, ... }:
      {
        units.main = {
          command = "/bin/app";
          env.DATABASE_URL = results.db.dsn;
        };
      };
  };

  forwardingRoot =
    spec:
    { service, ... }:
    let
      main = service "main" spec;
    in
    {
      services.main = main;
      provides = main.provides;
    };

  taggedMachines = {
    a = {
      address = "a.example:22";
      tags = [ "backed-up" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    b = {
      address = "b.example:22";
      tags = [
        "always-on"
        "backed-up"
      ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    c = {
      address = "c.example:22";
      tags = [ "backed-up" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    d = {
      address = "d.example:22";
      tags = [ "always-on" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };

  serviceKeys = result: filter (n: !hasInfix "machine:" n) (attrNames result.plan);

  bothFiles = {
    deployment = "deployment/instances.nix";
    machines = "deployment/machines.nix";
    modules.i = "borg-repo/default.nix";
  };

  # The probe from the proposal: a slot that exists only when a knob says so.
  cutLeaf =
    { settings, ... }:
    {
      uses =
        if settings.offsite then
          {
            repo = {
              interface = repository;
              reads = [ "url" ];
            };
          }
        else
          { };
      impl =
        { results, ... }:
        {
          units.main = {
            command = "/bin/run";
            env.REPO = if results ? repo then results.repo.url else "";
          };
        };
    };

  portFromSetting =
    { settings, ... }:
    {
      claims.ports.ssh = {
        proto = "tcp";
        count = 1;
        fixed = settings.port;
      };
      impl =
        { alloc, ... }:
        {
          units.main.command = "/bin/sshd -p ${toString alloc.ports.ssh}";
        };
    };

  cutFiles = bothFiles // {
    modules.i = "borg-push/default.nix";
    leaves.i.only = "borg-push/leaf.nix";
  };

  cut =
    {
      defaults,
      settings ? { },
      instances ? { },
      wire ? { },
    }:
    planOf {
      sources = cutFiles;
      instances = {
        i = {
          inherit settings;
          module = soleRoot {
            inherit defaults;
            module = cutLeaf;
          };
          placement.every.only.machines = [ "one" ];
        }
        // (if wire == { } then { } else { inherit wire; });
      }
      // instances;
    };

  slotConsumer = _: {
    uses.far = {
      interface = identity;
      reads = [ "publicKey" ];
    };
    impl =
      { results, ... }:
      {
        units.main = {
          command = "/bin/app";
          env.KEY = if results ? far then results.far.publicKey else "";
        };
      };
  };

  # A root filling one member's slot from inside the module: the capability value
  # off the sibling's own handle, never a name.
  boundPair =
    capability:
    { service, ... }:
    let
      backend = service "backend" { module = twoCapProvider; };
      app = service "app" {
        module = slotConsumer;
        wire.far = backend.provides.${capability};
      };
    in
    {
      services = { inherit backend app; };
    };

  pairFiles = {
    deployment = "deployment/instances.nix";
    machines = "deployment/machines.nix";
    modules.pair = "pair/default.nix";
    leaves.pair.app = "pair/app.nix";
    leaves.pair.backend = "pair/backend.nix";
  };

  interfaceFiles = {
    "interfaces/identity.nix".identity = identity;
    "interfaces/repository.nix".repository = repository;
  };

  farProvider = machine: {
    module = soleRoot {
      module = twoCapProvider;
      provides = [ "identity" ];
    };
    exposes = [ "identity" ];
    placement.every.only.machines = [ machine ];
  };

  keeperMember = _: {
    impl = _: {
      units.main.command = "/bin/keep";
    };
  };

  extraRoot = "/nix/store/9qf2j5x3k8mz1cvb7ras4dpn6yhw0gl5-extra-member";

  # The member a cut removes: a generator, a closure root and a unit of its own,
  # so its absence is observable three ways rather than one.
  extraMember = _: {
    vars.evidence = {
      per = "instance";
      files.token.secrecy = "public";
    };
    impl = _: {
      closure = [ extraRoot ];
      units.main.command = "${extraRoot}/bin/extra";
    };
  };

  cutProbe =
    { service, ... }:
    {
      services = {
        keeper = service "keeper" { module = keeperMember; };
        extra = service "extra" { module = extraMember; };
      };
    };

  cutProbeFiles = {
    deployment = "deployment/instances.nix";
    machines = "deployment/machines.nix";
    modules.probe = "probe/default.nix";
    leaves.probe.keeper = "probe/keeper.nix";
    leaves.probe.extra = "probe/extra.nix";
  };

  closureRoots = result: concatLists (map (entry: entry.closure or [ ]) (attrValues result.plan));
in
{
  testADeploymentOverwritesADefault =
    let
      result = planOf {
        instances.i = {
          module = soleRoot {
            module = settingsLeaf;
            defaults.quota = 250;
          };
          settings.only.quota = 500;
          placement.every.only.machines = [ "one" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        value = entry.settings.only.quota.value;
        source = entry.settings.only.quota.source;
        received = entry.units.main.command;
        rows = result.diagnostics;
        applicable = result.applicable;
      };
      expected = {
        value = 500;
        source = "deployment";
        received = "/bin/run --quota 500 --port -";
        rows = [ ];
        applicable = true;
      };
    };

  testADeploymentWritesToAFixedPath =
    let
      result = planOf {
        sources = bothFiles;
        instances.i = {
          module = soleRoot {
            module = settingsLeaf;
            defaults.quota = 250;
            fixed.port = 22;
          };
          settings.only.port = 2222;
          placement.every.only.machines = [ "one" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        rows = countById "settings-fixed-path" result;
        severity = severityById "settings-fixed-path" result;
        namesDeploymentFile = hasInfix "deployment/instances.nix" (
          messageById "settings-fixed-path" result
        );
        namesModuleFile = hasInfix "borg-repo/default.nix" (messageById "settings-fixed-path" result);
        namesKnob = hasInfix "`only.port`" (messageById "settings-fixed-path" result);
        resolved = entry.settings.only.port.value;
        source = entry.settings.only.port.source;
        received = entry.units.main.command;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        severity = "error";
        namesDeploymentFile = true;
        namesModuleFile = true;
        namesKnob = true;
        resolved = 22;
        source = "fixed";
        received = "/bin/run --quota 250 --port 22";
        applicable = false;
      };
    };

  # A root owning one member keys that member's namespace too: settings.server.quota
  # resolves and a bare settings.quota is a row.
  testASingleMemberRootStillKeysItsNamespace =
    let
      root = support.root {
        members.server = {
          module = settingsLeaf;
          defaults.quota = 250;
        };
      };
      deploy =
        settings:
        planOf {
          sources = bothFiles;
          instances.i = {
            inherit settings;
            module = root;
            placement.every.server.machines = [ "one" ];
          };
        };
      keyed = deploy { server.quota = 500; };
      unkeyed = deploy { quota = 500; };
    in
    {
      expr = {
        keyedValue = keyed.plan."i:server@one".settings.server.quota.value;
        keyedSource = keyed.plan."i:server@one".settings.server.quota.source;
        keyedRows = keyed.diagnostics;
        unkeyedRows = rowIds unkeyed;
        unkeyedSeverity = severityById "settings-not-member-keyed" unkeyed;
        namesMember = hasInfix "`server`" (evidenceById "settings-not-member-keyed" unkeyed);
        unkeyedValue = unkeyed.plan."i:server@one".settings.server.quota.value;
      };
      expected = {
        keyedValue = 500;
        keyedSource = "deployment";
        keyedRows = [ ];
        unkeyedRows = [ "settings-not-member-keyed" ];
        unkeyedSeverity = "error";
        namesMember = true;
        unkeyedValue = 250;
      };
    };

  testAWireNamesACapabilityThatIsNotExposed =
    let
      result = planOf {
        instances = {
          reader = {
            module = soleRoot { module = consumer; };
            placement.every.only.machines = [ "one" ];
            wire.far = {
              instance = "writer";
              provides = "identity";
            };
          };
          writer = {
            module = soleRoot {
              module = twoCapProvider;
              provides = [
                "identity"
                "repo"
              ];
            };
            placement.every.only.machines = [ "two" ];
            exposes = [ "repo" ];
          };
        };
      };
      row = builtins.head (rowsById "wire-capability-not-exposed" result);
    in
    {
      expr = {
        rows = countById "wire-capability-not-exposed" result;
        subject = row.subject;
        severity = row.severity;
        namesCapability = hasInfix "`writer.identity`" row.message;
        listsExposed = hasInfix "`repo`" row.evidence;
        delivered = result.plan."reader:only@one".reads.far.delivered;
        hasValues = result.plan."reader:only@one".reads.far ? values;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        subject = "reader:only";
        severity = "error";
        namesCapability = true;
        listsExposed = true;
        delivered = false;
        hasValues = false;
        applicable = false;
      };
    };

  testTheFoldersRootsEvaluateUnmodified =
    let
      result = support.workedResult;
      server = result.plan."vault-repo:server@vault";
    in
    {
      expr = {
        placedServer = result.plan ? "vault-repo:server@vault";
        placedClient = result.plan ? "nightly:client@alpha";
        sources = mapAttrs (_: knob: knob.source) server.settings.server;
        quota = server.settings.server.quota.value;
        compositionRows = map (r: r.id) (filter (r: elem r.id compositionIds) result.diagnostics);
      };
      expected = {
        placedServer = true;
        placedClient = true;
        sources = {
          port = "fixed";
          quota = "deployment";
        };
        quota = 500;
        compositionRows = [ ];
      };
    };

  testADeploymentWritesAnUndeclaredKnob =
    let
      result = planOf {
        sources = bothFiles;
        instances.i = {
          module = soleRoot {
            module = settingsLeaf;
            defaults.quota = 250;
          };
          settings.only.retention = 7;
          placement.every.only.machines = [ "one" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        rows = countById "settings-undeclared-knob" result;
        severity = severityById "settings-undeclared-knob" result;
        namesKnob = hasInfix "`only.retention`" (messageById "settings-undeclared-knob" result);
        listsDeclared = hasInfix "`quota`" (evidenceById "settings-undeclared-knob" result);
        inPlan = entry.settings.only ? retention;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        severity = "error";
        namesKnob = true;
        listsDeclared = true;
        inPlan = false;
        applicable = false;
      };
    };

  testExposesNamesACapabilityTheRootDoesNotProvide =
    let
      result = planOf {
        instances.i = {
          module = soleRoot {
            module = twoCapProvider;
            provides = [ "identity" ];
          };
          placement.every.only.machines = [ "one" ];
          exposes = [
            "identity"
            "ghost"
          ];
        };
      };
      row = builtins.head (rowsById "exposes-unknown-capability" result);
    in
    {
      expr = {
        rows = countById "exposes-unknown-capability" result;
        subject = row.subject;
        severity = row.severity;
        namesCapability = hasInfix "`ghost`" row.message;
        listsProvided = hasInfix "`identity`" row.evidence;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        subject = "i:instance";
        severity = "error";
        namesCapability = true;
        listsProvided = true;
        applicable = false;
      };
    };

  testATagPlacesEveryMachineThatCarriesIt =
    let
      result = planOf {
        machines = taggedMachines;
        instances.i = {
          module = soleRoot { module = settingsLeaf; };
          placement.every.only.tags = [ "backed-up" ];
        };
      };
    in
    {
      expr = {
        keys = serviceKeys result;
        machineEntries = filter (n: hasInfix "machine:" n) (attrNames result.plan);
        placement = result.plan."i:only@a".placement;
        dependsOn =
          result.plan."i:only@a".dependsOn == [
            "machine:a@${result.plan."machine:a".key}"
          ];
        rows = result.diagnostics;
      };
      expected = {
        keys = [
          "i:only@a"
          "i:only@b"
          "i:only@c"
        ];
        machineEntries = [
          "machine:a"
          "machine:b"
          "machine:c"
        ];
        placement = {
          reason = "every";
          tags = [ "backed-up" ];
        };
        dependsOn = true;
        rows = [ ];
      };
    };

  testANamedMachineListPlaces =
    let
      result = planOf {
        instances.i = {
          module = soleRoot { module = settingsLeaf; };
          placement.every.only.machines = [
            "two"
            "one"
          ];
        };
      };
    in
    {
      expr = {
        keys = serviceKeys result;
        placement = result.plan."i:only@one".placement;
        addresses = {
          one = result.plan."machine:one".address;
          two = result.plan."machine:two".address;
        };
        rows = result.diagnostics;
      };
      expected = {
        keys = [
          "i:only@one"
          "i:only@two"
        ];
        placement = {
          reason = "every";
          machines = [
            "two"
            "one"
          ];
        };
        addresses = {
          one = "one.example:22";
          two = "two.example:22";
        };
        rows = [ ];
      };
    };

  testANamedMachineIsAbsentFromTheRegistry =
    let
      result = planOf {
        sources = bothFiles;
        instances.i = {
          module = soleRoot { module = settingsLeaf; };
          placement.every.only.machines = [
            "one"
            "ghost"
          ];
        };
      };
      row = builtins.head (rowsById "placement-unknown-machine" result);
    in
    {
      expr = {
        rows = countById "placement-unknown-machine" result;
        subject = row.subject;
        severity = row.severity;
        namesMachine = hasInfix "`ghost`" row.message;
        listsRegistered = {
          file = hasInfix "deployment/machines.nix" row.evidence;
          one = hasInfix "`one`" row.evidence;
          two = hasInfix "`two`" row.evidence;
          ghost = hasInfix "`ghost`" row.evidence;
        };
        keys = serviceKeys result;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        subject = "i:only";
        severity = "error";
        namesMachine = true;
        listsRegistered = {
          file = true;
          one = true;
          two = true;
          ghost = false;
        };
        keys = [ "i:only@one" ];
        applicable = false;
      };
    };

  testAMemberNoPlacementSelected =
    let
      result = planOf {
        sources = bothFiles;
        instances.i = {
          module = soleRoot {
            module = settingsLeaf;
            defaults.quota = 250;
          };
        };
      };
      entry = result.plan."i:only";
    in
    {
      expr = {
        rows = countById "member-not-placed" result;
        severity = severityById "member-not-placed" result;
        namesMember = hasInfix "`i:only`" (messageById "member-not-placed" result);
        namesMissingSelector = hasInfix "`placement.every.only`" (evidenceById "member-not-placed" result);
        keys = attrNames result.plan;
        entryKeys = attrNames entry;
        settings = entry.settings.only.quota;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        severity = "error";
        namesMember = true;
        namesMissingSelector = true;
        keys = [ "i:only" ];
        entryKeys = [
          "key"
          "placement"
          "settings"
        ];
        settings = {
          value = 250;
          source = "defaults";
        };
        applicable = false;
      };
    };

  testAFixedPortClaimAllocatesThatPort =
    let
      result = planOf {
        instances.i = {
          module = soleRoot { module = portLeaf 2222; };
          placement.every.only.machines = [ "one" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        alloc = entry.alloc.ports;
        received = entry.units.main.command;
        rows = result.diagnostics;
      };
      expected = {
        alloc.ssh = 2222;
        received = "/bin/sshd -p 2222";
        rows = [ ];
      };
    };

  testAPortClaimWithoutFixed =
    let
      result = planOf {
        sources = bothFiles;
        instances.i = {
          module = soleRoot { module = portLeaf null; };
          placement.every.only.machines = [ "one" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        rows = countById "port-claim-not-fixed" result;
        severity = severityById "port-claim-not-fixed" result;
        namesClaim = hasInfix "`ssh`" (messageById "port-claim-not-fixed" result);
        namesTrigger = hasInfix "a persisted allocation table" (evidenceById "port-claim-not-fixed" result);
        allocated = entry ? alloc;
        received = entry.units.main.command;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        severity = "error";
        namesClaim = true;
        namesTrigger = true;
        allocated = false;
        received = "/bin/sshd -p -";
        applicable = false;
      };
    };

  testADeploymentDecidesTheCapabilitySet =
    let
      result = planOf {
        instances.pg = {
          module = forwardingRoot {
            module = perDatabaseLeaf;
            defaults.databases = [ "billing" ];
          };
          settings.main.databases = [
            "billing"
            "analytics"
          ];
          exposes = [
            "billing"
            "analytics"
          ];
          placement.every.main.machines = [ "one" ];
        };
      };
      entry = result.plan."pg:main@one";
    in
    {
      expr = {
        published = attrNames entry.provides;
        added = entry.provides.analytics.exports.dsn.value;
        keysetEqualsInterface = entry.provides.analytics.keysetEqualsInterface;
        source = entry.settings.main.databases.source;
        rows = rowIds result;
        applicable = result.applicable;
      };
      expected = {
        published = [
          "analytics"
          "billing"
        ];
        added = "postgresql:///analytics";
        keysetEqualsInterface = true;
        source = "deployment";
        rows = [ ];
        applicable = true;
      };
    };

  testAWireNamesACapabilityTheDeploymentAdded =
    let
      result = planOf {
        instances = {
          pg = {
            module = forwardingRoot {
              module = perDatabaseLeaf;
              defaults.databases = [ "billing" ];
            };
            settings.main.databases = [
              "billing"
              "analytics"
            ];
            exposes = [
              "billing"
              "analytics"
            ];
            placement.every.main.machines = [ "one" ];
          };
          app = {
            module = soleRoot { module = databaseReader; };
            wire.db = {
              instance = "pg";
              provides = "analytics";
            };
            placement.every.only.machines = [ "two" ];
          };
        };
      };
      reader = result.plan."app:only@two";
    in
    {
      expr = {
        delivered = reader.reads.db.delivered;
        received = reader.env.DATABASE_URL;
        readBy = result.plan."pg:main@one".provides.analytics.exports.dsn.readBy;
        rows = rowIds result;
        applicable = result.applicable;
      };
      expected = {
        delivered = true;
        received = "postgresql:///analytics";
        readBy = [ "app:only@two" ];
        rows = [ ];
        applicable = true;
      };
    };

  testACapabilitySetDerivedFromAKnobNobodyDeclared =
    let
      result = planOf {
        sources = bothFiles // {
          modules.pg = "postgresql/default.nix";
        };
        instances.pg = {
          module = forwardingRoot { module = perDatabaseLeaf; };
          settings.main.databases = [
            "billing"
            "analytics"
          ];
          placement.every.main.machines = [ "one" ];
        };
      };
      entry = result.plan."pg:main@one";
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "settings-undeclared-knob" result;
        namesKnob = hasInfix "`main.databases`" (messageById "settings-undeclared-knob" result);
        namesModuleFile = hasInfix "postgresql/default.nix" (messageById "settings-undeclared-knob" result);
        published = attrNames entry.provides;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "settings-undeclared-knob" ];
        severity = "error";
        namesKnob = true;
        namesModuleFile = true;
        published = [ "builtin" ];
        applicable = false;
      };
    };

  testAKnobRemovesASlot =
    let
      result = cut {
        defaults.offsite = true;
        settings.only.offsite = false;
      };
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "slot-set-settings-derived" result;
        subjects = subjectsById "slot-set-settings-derived" result;
        namesMember = hasInfix "`only`" (messageById "slot-set-settings-derived" result);
        namesSlot = hasInfix "`repo`" (messageById "slot-set-settings-derived" result);
        namesTheCut = hasInfix "`members.only.enable = false`" (
          evidenceById "slot-set-settings-derived" result
        );
        namesTheAlternative = hasInfix "branch on the setting inside `impl`" (
          support.resolutionById "slot-set-settings-derived" result
        );
        asksForNothing = result.plan."i:only@one" ? reads;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "slot-set-settings-derived" ];
        severity = "warning";
        subjects = [ "borg-push/leaf.nix" ];
        namesMember = true;
        namesSlot = true;
        namesTheCut = true;
        namesTheAlternative = true;
        asksForNothing = false;
        applicable = true;
      };
    };

  testAKnobAddsASlot =
    let
      result = cut {
        defaults.offsite = false;
        settings.only.offsite = true;
        wire.repo = {
          instance = "vault";
          provides = "repo";
        };
        instances.vault = {
          module = soleRoot {
            module = twoCapProvider;
            provides = [
              "identity"
              "repo"
            ];
          };
          exposes = [ "repo" ];
          placement.every.only.machines = [ "two" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "slot-set-settings-derived" result;
        namesSlot = hasInfix "`repo`" (messageById "slot-set-settings-derived" result);
        delivered = entry.reads.repo.delivered;
        received = entry.units.main.env.REPO;
        readBy = result.plan."vault:only@two".provides.repo.exports.url.readBy;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "slot-set-settings-derived" ];
        severity = "warning";
        namesSlot = true;
        delivered = true;
        received = "ssh://borg@vault.example:22/srv/borg";
        readBy = [ "i:only@one" ];
        applicable = true;
      };
    };

  testAMemberNobodyConfiguredIsNotReported =
    let
      unconfigured = cut { defaults.offsite = false; };
      fixedInstead = planOf {
        sources = cutFiles;
        instances.i = {
          module = soleRoot {
            module = cutLeaf;
            fixed.offsite = false;
          };
          placement.every.only.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        fromItsOwnDefaults = rowIds unconfigured;
        fromItsOwnFixedValues = rowIds fixedInstead;
        theSlotSetIsUnobserved = unconfigured.plan."i:only@one".units.main.env.REPO;
      };
      expected = {
        fromItsOwnDefaults = [ ];
        fromItsOwnFixedValues = [ ];
        theSlotSetIsUnobserved = "";
      };
    };

  testAClaimDerivedFromASettingValueIsNotAShapeDifference =
    let
      result = planOf {
        sources = cutFiles;
        instances.i = {
          module = soleRoot {
            module = portFromSetting;
            defaults.port = 22;
          };
          settings.only.port = 2222;
          placement.every.only.machines = [ "one" ];
        };
      };
      entry = result.plan."i:only@one";
    in
    {
      expr = {
        rows = rowIds result;
        allocated = entry.alloc.ports.ssh;
        received = entry.units.main.command;
        source = entry.settings.only.port.source;
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        allocated = 2222;
        received = "/bin/sshd -p 2222";
        source = "deployment";
        applicable = true;
      };
    };

  testACapabilitySetDerivedFromSettingsIsNotReportedHere =
    let
      result = planOf {
        instances = {
          pg = {
            module = forwardingRoot {
              module = perDatabaseLeaf;
              defaults.databases = [ "billing" ];
            };
            settings.main.databases = [
              "billing"
              "analytics"
            ];
            exposes = [
              "billing"
              "analytics"
            ];
            placement.every.main.machines = [ "one" ];
          };
          app = {
            module = soleRoot { module = databaseReader; };
            wire.db = {
              instance = "pg";
              provides = "analytics";
            };
            placement.every.only.machines = [ "two" ];
          };
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        published = attrNames result.plan."pg:main@one".provides;
        theAddedOneIsNamable = result.plan."app:only@two".env.DATABASE_URL;
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        published = [
          "analytics"
          "billing"
        ];
        theAddedOneIsNamable = "postgresql:///analytics";
        applicable = true;
      };
    };

  testARootBindingAConsumerToItsOwnProvider =
    let
      result = planOf {
        sources = pairFiles;
        instances.pair = {
          module = boundPair "identity";
          placement.every.backend.machines = [ "one" ];
          placement.every.app.machines = [ "two" ];
        };
      };
      entry = result.plan."pair:app@two";
    in
    {
      expr = {
        rows = rowIds result;
        entryRead = entry.reads.far.entry;
        delivered = entry.reads.far.delivered;
        far = entry.reads.far.wire;
        received = entry.units.main.env.KEY;
        readBy = result.plan."pair:backend@one".provides.identity.exports.publicKey.readBy;
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        entryRead = "pair:backend@one";
        delivered = true;
        far = {
          instance = "pair";
          provides = "identity";
        };
        received = "ssh-ed25519 AAAA";
        readBy = [ "pair:app@two" ];
        applicable = true;
      };
    };

  # The same mistake twice: once bound inside the root, once wired by the
  # deployment. A binding is exempt from no check a wire is subject to.
  testABindingWhoseInterfacesDoNotMatch =
    let
      bound = planOf {
        sources = pairFiles;
        interfaces = interfaceFiles;
        instances.pair = {
          module = boundPair "repo";
          placement.every.backend.machines = [ "one" ];
          placement.every.app.machines = [ "two" ];
        };
      };
      wired = planOf {
        sources = {
          deployment = "deployment/instances.nix";
          machines = "deployment/machines.nix";
          modules.app = "pair/default.nix";
          modules.store = "pair/default.nix";
          leaves.app.only = "pair/app.nix";
          leaves.store.only = "pair/backend.nix";
        };
        interfaces = interfaceFiles;
        instances = {
          store = {
            module = soleRoot {
              module = twoCapProvider;
              provides = [ "repo" ];
            };
            exposes = [ "repo" ];
            placement.every.only.machines = [ "one" ];
          };
          app = {
            module = soleRoot { module = slotConsumer; };
            wire.far = {
              instance = "store";
              provides = "repo";
            };
            placement.every.only.machines = [ "two" ];
          };
        };
      };
      names = result: {
        slotFile = hasInfix "interfaces/identity.nix" (messageById "interface-mismatch" result);
        capabilityFile = hasInfix "interfaces/repository.nix" (messageById "interface-mismatch" result);
      };
    in
    {
      expr = {
        boundRows = rowIds bound;
        wiredRows = rowIds wired;
        boundNamesBothFiles = names bound;
        wiredNamesBothFiles = names wired;
        boundSubjects = subjectsById "interface-mismatch" bound;
        wiredSubjects = subjectsById "interface-mismatch" wired;
        boundDelivered = bound.plan."pair:app@two".reads.far.delivered;
        applicable = {
          bound = bound.applicable;
          wired = wired.applicable;
        };
      };
      expected = {
        boundRows = [ "interface-mismatch" ];
        wiredRows = [ "interface-mismatch" ];
        boundNamesBothFiles = {
          slotFile = true;
          capabilityFile = true;
        };
        wiredNamesBothFiles = {
          slotFile = true;
          capabilityFile = true;
        };
        boundSubjects = [ "pair:app" ];
        wiredSubjects = [ "app:only" ];
        boundDelivered = false;
        applicable = {
          bound = false;
          wired = false;
        };
      };
    };

  # A record naming a member and a capability is not a capability off a sibling's
  # handle, and the interface is what a wire compares.
  testARootBindsASlotToARecordCarryingNoInterface =
    let
      result = planOf {
        sources = pairFiles;
        interfaces = interfaceFiles;
        instances.pair = {
          module =
            { service, ... }:
            {
              services = {
                backend = service "backend" { module = twoCapProvider; };
                app = service "app" {
                  module = slotConsumer;
                  wire.far = {
                    member = "backend";
                    capability = "identity";
                  };
                };
              };
            };
          placement.every.backend.machines = [ "one" ];
          placement.every.app.machines = [ "two" ];
        };
      };
      entry = result.plan."pair:app@two";
      row = builtins.head (rowsById "binding-malformed" result);
      unwired = builtins.head (rowsById "slot-unwired" result);
    in
    {
      expr = {
        rows = rowIds result;
        inherit (row) subject severity;
        namesTheRootTheMemberAndTheSlot = hasInfix "the root of instance `pair` binds slot `far` of member `app`" row.message;
        namesTheHandle = hasInfix "off a sibling's handle" row.evidence;
        theDeploymentsToFill = hasInfix "write `wire.far = { instance = <instance>;" unwired.resolution;
        delivered = entry.reads.far.delivered;
        received = entry.units.main.env.KEY;
        everyOtherEntry = attrNames result.plan;
        applicable = result.applicable;
      };
      expected = {
        rows = [
          "binding-malformed"
          "slot-unwired"
        ];
        subject = "pair:app";
        severity = "error";
        namesTheRootTheMemberAndTheSlot = true;
        namesTheHandle = true;
        theDeploymentsToFill = true;
        delivered = false;
        received = "";
        everyOtherEntry = [
          "machine:one"
          "machine:two"
          "pair:app@two"
          "pair:backend@one"
        ];
        applicable = false;
      };
    };

  testABindingToACapabilityPlacedTwiceAgainstASingleValuedSlot =
    let
      result = planOf {
        sources = pairFiles;
        instances.pair = {
          module = boundPair "identity";
          placement.every.backend.machines = [
            "one"
            "two"
          ];
          placement.every.app.machines = [ "one" ];
        };
      };
      entry = result.plan."pair:app@one";
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "reach-one-placement-count" result;
        severity = severityById "reach-one-placement-count" result;
        namesTheBoundCapability = hasInfix "`pair:backend.identity`" (
          messageById "reach-one-placement-count" result
        );
        namesBothPlacements = hasInfix "`one`, `two`" (evidenceById "reach-one-placement-count" result);
        delivered = entry.reads.far.delivered;
        hasValues = entry.reads.far ? values;
        received = entry.units.main.env.KEY;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "reach-one-placement-count" ];
        subjects = [ "pair:app" ];
        severity = "error";
        namesTheBoundCapability = true;
        namesBothPlacements = true;
        delivered = false;
        hasValues = false;
        received = "";
        applicable = false;
      };
    };

  # A member the deployment does not mention is kept, so the block is a cut and
  # never a selection: writing every member out changes nothing.
  testAnInstanceThatKeepsEveryMember =
    let
      deploy =
        members:
        planOf {
          sources = pairFiles;
          instances.pair = {
            inherit members;
            module = boundPair "identity";
            placement.every.backend.machines = [ "one" ];
            placement.every.app.machines = [ "two" ];
          };
        };
      silent = deploy { };
      stated = deploy {
        backend.enable = true;
        app.enable = true;
      };
    in
    {
      expr = {
        silentRows = rowIds silent;
        statedRows = rowIds stated;
        keys = serviceKeys silent;
        samePlan = silent.plan == stated.plan;
        applicable = silent.applicable;
      };
      expected = {
        silentRows = [ ];
        statedRows = [ ];
        keys = [
          "pair:app@two"
          "pair:backend@one"
        ];
        samePlan = true;
        applicable = true;
      };
    };

  testAMemberTheDeploymentCuts =
    let
      deploy =
        extra:
        planOf {
          sources = cutProbeFiles;
          instances.probe = {
            module = cutProbe;
            placement.every.keeper.machines = [ "one" ];
          }
          // extra;
        };
      whole = deploy {
        placement.every.keeper.machines = [ "one" ];
        placement.every.extra.machines = [ "one" ];
      };
      result = deploy { members.extra.enable = false; };
    in
    {
      expr = {
        rows = rowIds result;
        keys = attrNames result.plan;
        theWholeOneHasAllThree = {
          entry = whole.plan ? "probe:extra@one";
          value = whole.plan ? "probe:vars/evidence";
          closure = elem extraRoot (closureRoots whole);
        };
        theCutOneHasNone = {
          entry = result.plan ? "probe:extra@one";
          value = result.plan ? "probe:vars/evidence";
          closure = elem extraRoot (closureRoots result);
        };
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        keys = [
          "machine:one"
          "probe:keeper@one"
        ];
        theWholeOneHasAllThree = {
          entry = true;
          value = true;
          closure = true;
        };
        theCutOneHasNone = {
          entry = false;
          value = false;
          closure = false;
        };
        applicable = true;
      };
    };

  testAPlacementForACutMember =
    let
      result = planOf {
        sources = cutProbeFiles;
        instances.probe = {
          module = cutProbe;
          members.extra.enable = false;
          placement.every.keeper.machines = [ "one" ];
          placement.every.extra.machines = [ "one" ];
        };
      };
      row = builtins.head (rowsById "cut-member-named" result);
    in
    {
      expr = {
        rows = rowIds result;
        subject = row.subject;
        severity = row.severity;
        namesMember = hasInfix "places `extra`" row.message;
        namesTheCut = hasInfix "`members.extra.enable = false`" row.evidence;
        placed = result.plan ? "probe:extra@one";
        unplaced = result.plan ? "probe:extra";
        applicable = result.applicable;
      };
      expected = {
        rows = [ "cut-member-named" ];
        subject = "probe:instance";
        severity = "error";
        namesMember = true;
        namesTheCut = true;
        placed = false;
        unplaced = false;
        applicable = false;
      };
    };

  # A cut member is still a member, so its namespace is not an unkeyed knob: the
  # cut is the one thing reported.
  testSettingsForACutMember =
    let
      result = planOf {
        sources = cutProbeFiles;
        instances.probe = {
          module = cutProbe;
          members.extra.enable = false;
          settings.extra.quota = 500;
          placement.every.keeper.machines = [ "one" ];
        };
      };
      row = builtins.head (rowsById "cut-member-named" result);
    in
    {
      expr = {
        rows = rowIds result;
        notMisreadAsAnUnkeyedKnob = countById "settings-not-member-keyed" result;
        subject = row.subject;
        severity = row.severity;
        namesMember = hasInfix "writes settings for `extra`" row.message;
        namesTheCut = hasInfix "`members.extra.enable = false`" row.evidence;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "cut-member-named" ];
        notMisreadAsAnUnkeyedKnob = 0;
        subject = "probe:instance";
        severity = "error";
        namesMember = true;
        namesTheCut = true;
        applicable = false;
      };
    };

  testAWireForASlotBoundToAKeptSibling =
    let
      result = planOf {
        sources = pairFiles // {
          modules.far = "far/default.nix";
        };
        instances = {
          pair = {
            module = boundPair "identity";
            placement.every.backend.machines = [ "one" ];
            placement.every.app.machines = [ "two" ];
            wire.app.far = {
              instance = "far";
              provides = "identity";
            };
          };
          far = farProvider "two";
        };
      };
      row = builtins.head (rowsById "wire-names-bound-slot" result);
      entry = result.plan."pair:app@two";
    in
    {
      expr = {
        rows = rowIds result;
        subject = row.subject;
        severity = row.severity;
        namesSlot = hasInfix "slot `far`" row.message;
        namesBoundMember = hasInfix "member `backend`" row.message;
        namesDeploymentFile = hasInfix "deployment/instances.nix" row.message;
        theBindingStillResolves = entry.reads.far.entry;
        delivered = entry.reads.far.delivered;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "wire-names-bound-slot" ];
        subject = "pair:app";
        severity = "error";
        namesSlot = true;
        namesBoundMember = true;
        namesDeploymentFile = true;
        theBindingStillResolves = "pair:backend@one";
        delivered = true;
        applicable = false;
      };
    };

  testASlotOpenedByACutAndWired =
    let
      result = planOf {
        sources = pairFiles // {
          modules.far = "far/default.nix";
        };
        instances = {
          pair = {
            module = boundPair "identity";
            members.backend.enable = false;
            placement.every.app.machines = [ "one" ];
            wire.app.far = {
              instance = "far";
              provides = "identity";
            };
          };
          far = farProvider "two";
        };
      };
      entry = result.plan."pair:app@one";
    in
    {
      expr = {
        rows = rowIds result;
        entryRead = entry.reads.far.entry;
        wire = entry.reads.far.wire;
        delivered = entry.reads.far.delivered;
        received = entry.units.main.env.KEY;
        theCutMemberIsGone = result.plan ? "pair:backend";
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        entryRead = "far:only@two";
        wire = {
          instance = "far";
          provides = "identity";
        };
        delivered = true;
        received = "ssh-ed25519 AAAA";
        theCutMemberIsGone = false;
        applicable = true;
      };
    };

  testASlotOpenedByACutAndLeftUnwired =
    let
      result = planOf {
        sources = pairFiles;
        instances.pair = {
          module = boundPair "identity";
          members.backend.enable = false;
          placement.every.app.machines = [ "one" ];
        };
      };
      row = builtins.head (rowsById "slot-unwired" result);
      entry = result.plan."pair:app@one";
    in
    {
      expr = {
        rows = rowIds result;
        subject = row.subject;
        severity = row.severity;
        namesTheBoundMember = hasInfix "binds it to member `backend`" row.evidence;
        namesTheCut = hasInfix "which deployment/instances.nix cuts" row.evidence;
        namesTheMemberScopedForm = hasInfix "`wire.app.far = {" row.resolution;
        namesKeepingTheMember = hasInfix "keep member `backend`" row.resolution;
        delivered = entry.reads.far.delivered;
        theImplementationSeesNoSlot = entry.units.main.env.KEY;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "slot-unwired" ];
        subject = "pair:app";
        severity = "error";
        namesTheBoundMember = true;
        namesTheCut = true;
        namesTheMemberScopedForm = true;
        namesKeepingTheMember = true;
        delivered = false;
        theImplementationSeesNoSlot = "";
        applicable = false;
      };
    };

  # One module value, bound once in this `let` and named by both instances, so the
  # two shapes are a difference the deployment made and not a second module.
  testOneModuleTwoInstancesTwoShapes =
    let
      module = boundPair "identity";
      result = planOf {
        sources = {
          deployment = "deployment/instances.nix";
          machines = "deployment/machines.nix";
          modules.whole = "pair/default.nix";
          modules.reshaped = "pair/default.nix";
          modules.far = "far/default.nix";
        };
        instances = {
          whole = {
            inherit module;
            placement.every.backend.machines = [ "one" ];
            placement.every.app.machines = [ "one" ];
          };
          reshaped = {
            inherit module;
            members.backend.enable = false;
            placement.every.app.machines = [ "one" ];
            wire.app.far = {
              instance = "far";
              provides = "identity";
            };
          };
          far = farProvider "two";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        keys = serviceKeys result;
        theFirstReadsItsSibling = result.plan."whole:app@one".reads.far.entry;
        theSecondReadsTheWiredProvider = result.plan."reshaped:app@one".reads.far.entry;
        bothReceive = {
          whole = result.plan."whole:app@one".units.main.env.KEY;
          reshaped = result.plan."reshaped:app@one".units.main.env.KEY;
        };
        applicable = result.applicable;
      };
      expected = {
        rows = [ ];
        keys = [
          "far:only@two"
          "reshaped:app@one"
          "whole:app@one"
          "whole:backend@one"
        ];
        theFirstReadsItsSibling = "whole:backend@one";
        theSecondReadsTheWiredProvider = "far:only@two";
        bothReceive = {
          whole = "ssh-ed25519 AAAA";
          reshaped = "ssh-ed25519 AAAA";
        };
        applicable = true;
      };
    };
}
