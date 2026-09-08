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

  # If this goes red, upstream fixed _withoutFunctions. Rewrite the measurement in
  # design.md D7 rather than deleting the guard. The evidence is the surviving
  # function paths: serialising a function aborts the whole suite instead of failing.
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

  # gccNames must name every gcc field the pinned nixpkgs sets on any exposed
  # platform, so a new upstream field fails here instead of vanishing from records.
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

  # A declared microarchitecture replaces the whole gcc group and does not merge
  # into it, because elaborate applies its arguments over the platform defaults.
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
