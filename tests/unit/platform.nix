# What a machine declares about itself and the form the plan records it in.
#
# One test per scenario of specs/planner/machine-platform/spec.md, named after
# that scenario, plus the two guards that keep the projection from being
# replaced by upstream's own filter.
{
  planner,
  support,
  systems,
}:
let
  inherit (builtins)
    all
    attrNames
    concatLists
    filter
    isAttrs
    isFunction
    isList
    match
    toJSON
    tryEval
    ;

  inherit (support)
    countById
    hasInfix
    messageById
    planOf
    rowIds
    severityById
    soleRoot
    ;

  quiet = _: {
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  on =
    machines: selector:
    planOf {
      inherit machines;
      instances.svc = {
        module = soleRoot {
          module = quiet;
        };
        placement.every.only = selector;
      };
    };

  # Every path in a value at which a function sits, so "no function at any
  # depth" is asserted rather than "no function at the top level".
  functionsIn =
    prefix: value:
    if isFunction value then
      [ prefix ]
    else if isList value then
      concatLists (
        builtins.genList (i: functionsIn "${prefix}[${toString i}]" (builtins.elemAt value i)) (
          builtins.length value
        )
      )
    else if isAttrs value then
      concatLists (map (n: functionsIn "${prefix}.${n}" value.${n}) (attrNames value))
    else
      [ ];

  machinesWith = extra: {
    host = {
      address = "host.example:22";
      tags = [ "everywhere" ];
    }
    // extra;
  };
in
{
  # A machine declares an address, a tag, a system and a service manager, and
  # its plan entry records all four.
  testAFullyDeclaredMachine =
    let
      result = on (machinesWith {
        system = "x86_64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
    in
    {
      expr = {
        entry = result.plan."machine:host" // {
          key = "<hash>";
        };
        rows = result.diagnostics;
      };
      expected = {
        entry = {
          address = "host.example:22";
          key = "<hash>";
          serviceManager = "systemd";
          system = "x86_64-linux";
          tags = [ "everywhere" ];
        };
        rows = [ ];
      };
    };

  # A machine a placement selects and which declares no system has no derivable
  # target: the row names it and the registry file, and the plan still carries
  # the machine's entry and the entry placed on it.
  testAMachineOmitsItsSystem =
    let
      result = on (machinesWith { serviceManager = "systemd"; }) { machines = [ "host" ]; };
    in
    {
      expr = {
        rows = rowIds result;
        namesTheMachine = hasInfix "`host`" (messageById "machine-target-incomplete" result);
        namesTheKey = hasInfix "`system`" (messageById "machine-target-incomplete" result);
        subjects = support.subjectsById "machine-target-incomplete" result;
        planKeys = attrNames result.plan;
        target = result.plan."svc:only@host".target;
      };
      expected = {
        rows = [ "machine-target-incomplete" ];
        namesTheMachine = true;
        namesTheKey = true;
        subjects = [ "deployment/machines.nix" ];
        planKeys = [
          "machine:host"
          "svc:only@host"
        ];
        target = {
          address = "host.example:22";
          serviceManager = "systemd";
        };
      };
    };

  # The same for a machine that declares no service manager.
  testAMachineOmitsItsServiceManager =
    let
      result = on (machinesWith { system = "x86_64-linux"; }) { machines = [ "host" ]; };
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "`serviceManager`" (messageById "machine-target-incomplete" result);
        planKeys = attrNames result.plan;
        recordedTargetFields = attrNames result.plan."svc:only@host".target;
      };
      expected = {
        rows = [ "machine-target-incomplete" ];
        namesTheKey = true;
        planKeys = [
          "machine:host"
          "svc:only@host"
        ];
        recordedTargetFields = [
          "address"
          "system"
        ];
      };
    };

  # A machine that changes architecture re-keys itself and every entry placed
  # on it, because adding a key to the registry widens the machine record and
  # the machine record is what a dependency names.
  testAMachineChangesArchitecture =
    let
      deployment =
        system:
        on (machinesWith {
          inherit system;
          serviceManager = "systemd";
        }) { machines = [ "host" ]; };
      before = deployment "x86_64-linux";
      after = deployment "aarch64-linux";
    in
    {
      expr = {
        machineKeyChanged = before.plan."machine:host".key != after.plan."machine:host".key;
        entryKeyChanged = before.plan."svc:only@host".key != after.plan."svc:only@host".key;
        dependsOnChanged = before.plan."svc:only@host".dependsOn != after.plan."svc:only@host".dependsOn;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        machineKeyChanged = true;
        entryKeyChanged = true;
        dependsOnChanged = true;
        rows = [ ];
      };
    };

  # A platform record serialises without loss and carries no function at any
  # depth, including inside a nested attribute set or a list.
  testAPlatformRecordIsSerialisable =
    let
      result = on (machinesWith {
        system = "aarch64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
      record = result.plan."svc:only@host".target.system;
      serialised = tryEval (toJSON result.plan);
    in
    {
      expr = {
        serialises = serialised.success;
        roundTrips = builtins.fromJSON (toJSON record) == record;
        functions = functionsIn "target.system" record;
      };
      expected = {
        serialises = true;
        roundTrips = true;
        functions = [ ];
      };
    };

  # The elaboration this record is projected from carries a function nested
  # below its top level: the projection excludes it and the plan still
  # serialises.
  testTheUpstreamElaborationCarriesANestedFunction =
    let
      elaborated = systems.elaborate "aarch64-linux";
      nested = functionsIn "parsed" elaborated.parsed;
      record = planner.platform.record {
        system = "aarch64-linux";
        microarchitecture = null;
      };
    in
    {
      expr = {
        upstreamHasNestedFunctions = nested != [ ];
        whereUpstreamHasThem = nested;
        projectionHasNone = functionsIn "record" record == [ ];
        projectionSerialises = (tryEval (toJSON record)).success;
      };
      expected = {
        upstreamHasNestedFunctions = true;
        whereUpstreamHasThem = [
          "parsed.abi.assertions[0].assertion"
          "parsed.abi.assertions[1].assertion"
        ];
        projectionHasNone = true;
        projectionSerialises = true;
      };
    };

  # Task 7.3, the guard. Upstream's own filter is a deny-list of four top-level
  # names, so it is not function-free and cannot be a plan value. If this test
  # starts failing, upstream fixed it and the first measurement of D7 needs
  # rewriting rather than this guard deleting.
  #
  # The evidence is the surviving functions rather than a failed `toJSON`:
  # `builtins.toJSON` of a function is not an error `tryEval` catches, so
  # asking whether it serialises would abort the suite instead of failing a
  # test.
  testUpstreamsOwnFilterIsNotAPlanValue =
    let
      elaborated = systems.elaborate "aarch64-linux";
      surviving = functionsIn "_withoutFunctions" (
        removeAttrs elaborated._withoutFunctions [ "_withoutFunctions" ]
      );
    in
    {
      expr = {
        survivingFunctions = surviving;
        denyListedNames = systems.functionNames;
      };
      expected = {
        survivingFunctions = [
          "_withoutFunctions.parsed.abi.assertions[0].assertion"
          "_withoutFunctions.parsed.abi.assertions[1].assertion"
        ];
        denyListedNames = [
          "canExecute"
          "emulator"
          "emulatorAvailable"
          "staticEmulatorAvailable"
        ];
      };
    };

  # Task 7.3, the second guard. The projection's own field set names nothing
  # upstream keeps in sync with the record's function attributes, and the
  # codegen list this library writes out names every `gcc` field the pinned
  # nixpkgs sets on any platform it exposes, so a codegen field upstream adds
  # fails here rather than being dropped from every record.
  testTheProjectionsFieldSetNamesNoFunction =
    let
      elaborated = systems.elaborate "x86_64-linux";
      gccFieldsUpstreamSets = builtins.foldl' (
        seen: double: seen ++ filter (n: !builtins.elem n seen) (attrNames (systems.elaborate double).gcc)
      ) [ ] systems.flakeExposed;
    in
    {
      expr = {
        namedFunctions = filter (n: builtins.elem n systems.functionNames) planner.platform.fieldNames;
        unnamedCodegenFields = filter (n: !builtins.elem n planner.platform.gccNames) gccFieldsUpstreamSets;
        everyNamedFieldExists = all (n: elaborated ? ${n}) planner.platform.scalarNames;
      };
      expected = {
        namedFunctions = [ ];
        unnamedCodegenFields = [ ];
        everyNamedFieldExists = true;
      };
    };

  # An aarch64 machine's record names the facts a cross build spends: the
  # triple it is configured with, the libc, the kernel's own architecture name
  # and the parsed cpu and kernel.
  testAnAarch64MachinesPlatformRecord =
    let
      result = on (machinesWith {
        system = "aarch64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
      record = result.plan."svc:only@host".target.system;
    in
    {
      expr = {
        fields = attrNames record;
        cpu = {
          inherit (record.parsed.cpu)
            name
            bits
            family
            ;
          endianness = record.parsed.cpu.significantByte.name;
        };
        kernel = {
          inherit (record.parsed.kernel) name;
          execFormat = record.parsed.kernel.execFormat.name;
        };
        abi = record.parsed.abi.name;
        inherit (record)
          config
          libc
          linuxArch
          useLLVM
          ;
      };
      expected = {
        fields = [
          "config"
          "gcc"
          "libc"
          "linuxArch"
          "parsed"
          "system"
          "useLLVM"
        ];
        cpu = {
          name = "aarch64";
          bits = 64;
          family = "arm";
          endianness = "littleEndian";
        };
        kernel = {
          name = "linux";
          execFormat = "elf";
        };
        abi = "gnu";
        config = "aarch64-unknown-linux-gnu";
        libc = "glibc";
        linuxArch = "arm64";
        useLLVM = false;
      };
    };

  # A field the projection does not name is absent even though the elaboration
  # carries it, so an upstream addition is a decision rather than a silent
  # re-key. The `is*` predicates are the largest such family and every one of
  # them is a function of `parsed`, so the record carries none of them.
  testAFieldOutsideTheAllowListIsAbsent =
    let
      result = on (machinesWith {
        system = "x86_64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
      record = result.plan."svc:only@host".target.system;
      elaborated = systems.elaborate "x86_64-linux";
      outside = [
        "darwinSdkVersion"
        "avx512Support"
        "uname"
        "extensions"
        "linker"
        "rust"
        "isLinux"
        "isx86_64"
        "is64bit"
        "isStatic"
      ];
      predicatesUpstream = filter (n: match "is.*" n != null) (attrNames elaborated);
    in
    {
      expr = {
        upstreamCarriesThem = all (n: elaborated ? ${n}) outside;
        recordCarriesNone = filter (n: record ? ${n}) outside;
        upstreamPredicateCount = builtins.length predicatesUpstream > 50;
        predicatesInTheRecord = filter (n: match "is.*" n != null) (attrNames record);
        derivableFromParsed = {
          isLinux = record.parsed.kernel.name == "linux";
          is64bit = record.parsed.cpu.bits == 64;
        };
        assertionsExcluded = record.parsed.abi ? assertions;
      };
      expected = {
        upstreamCarriesThem = true;
        recordCarriesNone = [ ];
        upstreamPredicateCount = true;
        predicatesInTheRecord = [ ];
        derivableFromParsed = {
          isLinux = true;
          is64bit = true;
        };
        assertionsExcluded = false;
      };
    };

  # Two machines declaring one system and no microarchitecture produce equal
  # records, which is what makes the elaboration memoisable per system string.
  testTwoMachinesOfOneSystem =
    let
      result = planOf {
        machines = {
          first = {
            address = "first.example:22";
            tags = [ "pair" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
          second = {
            address = "second.example:22";
            tags = [ "pair" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
        };
        instances.svc = {
          module = soleRoot {
            module = quiet;
          };
          placement.every.only.tags = [ "pair" ];
        };
      };
    in
    {
      expr = {
        equal = result.plan."svc:only@first".target.system == result.plan."svc:only@second".target.system;
        rows = result.diagnostics;
      };
      expected = {
        equal = true;
        rows = [ ];
      };
    };

  # A machine that declares a microarchitecture has it in the record, and
  # nothing the planner describes is specialised for it.
  testAMachineDeclaresAMicroarchitecture =
    let
      result = on (machinesWith {
        system = "x86_64-linux";
        serviceManager = "systemd";
        microarchitecture = "znver4";
      }) { machines = [ "host" ]; };
      entry = result.plan."svc:only@host";
      plain = on (machinesWith {
        system = "x86_64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
    in
    {
      expr = {
        gcc = entry.target.system.gcc;
        recordedOnTheMachine = result.plan."machine:host".microarchitecture;
        absentWithoutOne = plain.plan."svc:only@host".target.system ? gcc;
        commandUnchanged = entry.units.only.command == plain.plan."svc:only@host".units.only.command;
        rows = result.diagnostics;
      };
      expected = {
        gcc = {
          arch = "znver4";
          tune = "znver4";
        };
        recordedOnTheMachine = "znver4";
        absentWithoutOne = false;
        commandUnchanged = true;
        rows = [ ];
      };
    };

  # A platform whose own defaults name codegen fields records them for a
  # machine that declared no microarchitecture, and a declared
  # microarchitecture replaces that group rather than merging into it —
  # `elaborate` applies its arguments over `platforms.select`, so armv7l's
  # `fpu` default is gone the moment an arch is declared, exactly as it would
  # be for the same `crossSystem`.
  testAPlatformCarriesItsOwnCodegenDefaults =
    let
      arm = on (machinesWith {
        system = "armv7l-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
      overridden = on (machinesWith {
        system = "armv7l-linux";
        serviceManager = "systemd";
        microarchitecture = "znver4";
      }) { machines = [ "host" ]; };
      loong = on (machinesWith {
        system = "loongarch64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
    in
    {
      expr = {
        withoutAMicroarchitecture = arm.plan."svc:only@host".target.system.gcc;
        aDeclaredOneReplacesTheGroup = overridden.plan."svc:only@host".target.system.gcc;
        beyondArchAndTune = loong.plan."svc:only@host".target.system.gcc;
        rows = arm.diagnostics ++ overridden.diagnostics ++ loong.diagnostics;
      };
      expected = {
        withoutAMicroarchitecture = {
          arch = "armv7-a";
          fpu = "vfpv3-d16";
        };
        aDeclaredOneReplacesTheGroup = {
          arch = "znver4";
          tune = "znver4";
        };
        beyondArchAndTune = {
          arch = "la64v1.0";
          cmodel = "medium";
          strict-align = false;
        };
        rows = [ ];
      };
    };

  # A module declaring a platform it is placed on produces no row.
  testAModuleIsPlacedOnASystemItSupports =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              platforms = [ "x86_64-linux" ];
              impl = _: {
                units.only.command = "/bin/true";
              };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      };
    in
    {
      expr = rowIds result;
      expected = [ ];
    };

  # A module placed on a system it does not declare is a refusal and not a
  # filter: the row names both sides and the entry is still in the plan.
  testAModuleIsPlacedOnASystemItDoesNotSupport =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              platforms = [ "aarch64-darwin" ];
              impl = _: {
                units.only.command = "/bin/true";
              };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      };
      message = messageById "placement-platform-mismatch" result;
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "placement-platform-mismatch" result;
        namesTheMember = hasInfix "`svc:only`" message;
        namesTheMachine = hasInfix "`one`" message;
        namesTheMachinesSystem = hasInfix "`x86_64-linux`" message;
        namesTheModulesSystems = hasInfix "`aarch64-darwin`" message;
        entryIsInThePlan = result.plan ? "svc:only@one";
      };
      expected = {
        rows = [ "placement-platform-mismatch" ];
        severity = "error";
        namesTheMember = true;
        namesTheMachine = true;
        namesTheMachinesSystem = true;
        namesTheModulesSystems = true;
        entryIsInThePlan = true;
      };
    };

  # A module that never had to care about platforms is not made to: an empty
  # `platforms` is every system.
  testAModuleDeclaresNoPlatforms =
    let
      result = on (machinesWith {
        system = "riscv64-linux";
        serviceManager = "systemd";
      }) { machines = [ "host" ]; };
    in
    {
      expr = rowIds result;
      expected = [ ];
    };

  # Task 7.4. One tag selects two machines of different systems and the module
  # declares one of them: exactly one row, naming the machine whose system the
  # module does not declare.
  testOneTagSelectsTwoSystems =
    let
      result = planOf {
        machines = {
          amd = {
            address = "amd.example:22";
            tags = [ "fleet" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
          arm = {
            address = "arm.example:22";
            tags = [ "fleet" ];
            system = "aarch64-linux";
            serviceManager = "systemd";
          };
        };
        instances.svc = {
          module = soleRoot {
            module = _: {
              platforms = [ "x86_64-linux" ];
              impl = _: {
                units.only.command = "/bin/true";
              };
            };
          };
          placement.every.only.tags = [ "fleet" ];
        };
      };
    in
    {
      expr = {
        rowCount = countById "placement-platform-mismatch" result;
        namesTheUnsupportedMachine = hasInfix "`arm`" (messageById "placement-platform-mismatch" result);
        bothEntriesInThePlan = [
          (result.plan ? "svc:only@amd")
          (result.plan ? "svc:only@arm")
        ];
      };
      expected = {
        rowCount = 1;
        namesTheUnsupportedMachine = true;
        bothEntriesInThePlan = [
          true
          true
        ];
      };
    };

  # Task 7.5. One service on two systems: two entries, each recording its own
  # machine's platform record, and two different keys.
  testOneServicePlacedOnTwoSystems =
    let
      result = planOf {
        machines = {
          amd = {
            address = "amd.example:22";
            tags = [ "fleet" ];
            system = "x86_64-linux";
            serviceManager = "systemd";
          };
          arm = {
            address = "arm.example:22";
            tags = [ "fleet" ];
            system = "aarch64-linux";
            serviceManager = "systemd";
          };
        };
        instances.svc = {
          module = soleRoot {
            module = quiet;
          };
          placement.every.only.tags = [ "fleet" ];
        };
      };
      amd = result.plan."svc:only@amd";
      arm = result.plan."svc:only@arm";
    in
    {
      expr = {
        systems = [
          amd.target.system.system
          arm.target.system.system
        ];
        recordsDiffer = amd.target != arm.target;
        keysDiffer = amd.key != arm.key;
        unitsAgree = amd.units == arm.units;
        rows = result.diagnostics;
      };
      expected = {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        recordsDiffer = true;
        keysDiffer = true;
        unitsAgree = true;
        rows = [ ];
      };
    };

  # An unplaced member records neither a platform record nor a service manager
  # nor a machine.
  testAnUnplacedMemberRecordsNoTarget =
    let
      result = planOf {
        instances.svc.module = soleRoot {
          module = quiet;
        };
      };
      entry = result.plan."svc:only";
    in
    {
      expr = {
        fields = attrNames entry;
        rows = rowIds result;
      };
      expected = {
        fields = [
          "key"
          "placement"
          "settings"
        ];
        rows = [ "member-not-placed" ];
      };
    };
}
