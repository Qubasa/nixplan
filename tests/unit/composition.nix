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
    ;

  inherit (builtins)
    attrNames
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
}
