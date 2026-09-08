{
  planner,
  support,
  imageSource,
}:
let
  inherit (builtins)
    attrNames
    length
    tryEval
    ;

  inherit (support)
    hasInfix
    korora
    planOf
    soleRoot
    systemdService
    ;

  inherit (support.worked) openssh borgbackup;

  reader = import (imageSource + "/read.nix") { inherit planner; };

  laptopMachines = support.machines // {
    laptop = support.laptop;
  };

  planned =
    {
      machines ? support.machines,
      machine ? "one",
    }:
    implementation:
    let
      result = planOf {
        inherit machines;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = implementation;
            };
          };
          placement.every.only.machines = [ machine ];
        };
      };
    in
    {
      inherit result;
      key = "svc:only@${machine}";
      plan = result.plan;
    };

  readOf =
    {
      profile ? "trusted",
      machines ? support.machines,
      machine ? "one",
    }:
    implementation:
    let
      p = planned { inherit machines machine; } implementation;
    in
    reader.read {
      inherit (p) plan key;
      inherit profile;
    };

  # deepSeq, because a refusal guards fields a lazy read would never force. Without
  # it every refusal test passes without testing anything.
  raises = value: !(tryEval (builtins.deepSeq value value)).success;

  simple = _: {
    closure = [ borgbackup ];
    units.only.command = "${borgbackup}/bin/borg serve";
  };

  rebuilt =
    let
      deployment =
        { text, timeout }:
        planOf {
          instances = {
            svc = {
              module = soleRoot {
                module = _: {
                  impl = _: {
                    closure = [ borgbackup ];
                    units.only = {
                      command = "${borgbackup}/bin/borg serve";
                      inherit timeout;
                    };
                    configData."/etc/thing.conf" = {
                      mode = "0444";
                      reload = [ "only" ];
                      render = [ { text = "value = ${text}\n"; } ];
                    };
                  };
                };
              };
              placement.every.only.machines = [ "one" ];
            };
            other = {
              module = soleRoot {
                module = _: {
                  impl = _: {
                    closure = [ openssh ];
                    units.only.command = "${openssh}/bin/sshd";
                  };
                };
              };
              placement.every.only.machines = [ "two" ];
            };
          };
        };
      imageOf =
        args: key:
        reader.read {
          plan = (deployment args).plan;
          inherit key;
          profile = "trusted";
        };
      base = {
        text = "before";
        timeout = "30m";
      };
    in
    {
      inherit imageOf base;
      key = "svc:only@one";
      otherKey = "other:only@two";
      unitOf = image: reader.renderUnit image "only";
    };
in
{
  testAPlanEntryBecomesAnImage =
    let
      image = readOf { } simple;
    in
    {
      expr = {
        inherit (image)
          name
          instance
          service
          machine
          storeDir
          closure
          serviceManager
          ;
        version = builtins.stringLength image.version;
        units = attrNames image.units;
        unitFiles = map (u: image.units.${u}.file) (attrNames image.units);
        system = image.system.system;
      };
      expected = {
        name = "svc-only";
        instance = "svc";
        service = "only";
        machine = "one";
        storeDir = "/nix/store";
        closure = [ borgbackup ];
        serviceManager = "systemd";
        version = 16;
        units = [ "only" ];
        unitFiles = [ "svc-only-only.service" ];
        system = "x86_64-linux";
      };
    };

  testThePlannerStaysDerivationFree =
    let
      p = planned { } simple;
      walk =
        value:
        if builtins.isAttrs value then
          (if (value.type or null) == "derivation" then [ "derivation" ] else [ ])
          ++ builtins.concatLists (map walk (builtins.attrValues value))
        else if builtins.isList value then
          builtins.concatLists (map walk value)
        else if builtins.isFunction value then
          [ "function" ]
        else
          [ ];
    in
    {
      expr = {
        neither = walk p.plan;
        isJson = builtins.fromJSON (builtins.toJSON p.plan) == p.plan;
      };
      expected = {
        neither = [ ];
        isJson = true;
      };
    };

  testOneServiceOnTwoArchitectures =
    let
      machines = support.machines // {
        two = support.machines.two // {
          system = "aarch64-linux";
        };
      };
      result = planOf {
        inherit machines;
        instances.svc = {
          module = soleRoot { module = _: { impl = simple; }; };
          placement.every.only.machines = [
            "one"
            "two"
          ];
        };
      };
      imageOf =
        machine:
        reader.read {
          plan = result.plan;
          key = "svc:only@${machine}";
          profile = "trusted";
        };
      first = imageOf "one";
      second = imageOf "two";
    in
    {
      expr = {
        systems = [
          first.system.system
          second.system.system
        ];
        sameName = first.name == second.name;
        sameVersion = first.version == second.version;
      };
      expected = {
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        sameName = true;
        sameVersion = false;
      };
    };

  testAnImageMeetsADifferentServiceManager = {
    expr = raises (
      readOf {
        machines = laptopMachines;
        machine = "laptop";
      } simple
    );
    expected = true;
  };

  testAFactThePlanDoesNotCarry =
    let
      result = planOf {
        instances.svc.module = soleRoot {
          module = _: {
            impl = _: {
              units.only.command = "/bin/true";
            };
          };
        };
      };
      read = reader.read {
        plan = result.plan;
        key = "svc:only";
        profile = "trusted";
      };
      unknownKey = reader.read {
        plan = result.plan;
        key = "svc:only@nowhere";
        profile = "trusted";
      };
    in
    {
      expr = {
        unplacedRaises = raises read;
        unknownEntryRaises = raises unknownKey;
        entryFields = attrNames result.plan."svc:only";
      };
      expected = {
        unplacedRaises = true;
        unknownEntryRaises = true;
        entryFields = [
          "key"
          "placement"
          "settings"
        ];
      };
    };

  testAStorePathNamedButNotDeclared = {
    expr = {
      undeclaredRaises = raises (
        readOf { } (_: {
          closure = [ borgbackup ];
          units.only.command = "${openssh}/bin/sshd";
        })
      );
      declaredDoesNot = raises (
        readOf { } (_: {
          closure = [
            borgbackup
            openssh
          ];
          units.only = {
            command = "${openssh}/bin/sshd";
            env.BORG = "${borgbackup}/bin/borg";
          };
        })
      );
    };
    expected = {
      undeclaredRaises = true;
      declaredDoesNot = false;
    };
  };

  testAMachineWhoseStoreDirectoryIsRelocated =
    let
      elsewhere = "/mnt/nix/store";
      relocated = "${elsewhere}/1w9k3zc7yq2mb5xj8vdl4rns6fga0h1p-openssh-9.8p1";
      result = planOf {
        storeDir = elsewhere;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = _: {
                closure = [ relocated ];
                units.only.command = "${relocated}/bin/sshd";
              };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      };
      image = reader.read {
        plan = result.plan;
        key = "svc:only@one";
        profile = "trusted";
      };
      underTheDefault = planOf {
        storeDir = elsewhere;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = _: {
                closure = [ openssh ];
                units.only.command = "${openssh}/bin/sshd";
              };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        inherit (image) storeDir closure;
        rootUnderTheDefaultRaises = raises (
          reader.read {
            plan = underTheDefault.plan;
            key = "svc:only@one";
            profile = "trusted";
          }
        );
      };
      expected = {
        storeDir = elsewhere;
        closure = [ relocated ];
        rootUnderTheDefaultRaises = true;
      };
    };

  testTwoServicesOfOneInstanceOnOneMachine =
    let
      result = planOf {
        instances.svc = {
          module =
            { service, ... }:
            {
              services.first = service "first" {
                module = _: {
                  impl = _: {
                    closure = [ borgbackup ];
                    units.daemon.command = "${borgbackup}/bin/borg serve";
                  };
                };
              };
              services.second = service "second" {
                module = _: {
                  impl = _: {
                    closure = [ borgbackup ];
                    units.daemon.command = "${borgbackup}/bin/borg init";
                  };
                };
              };
            };
          placement.every = {
            first.machines = [ "one" ];
            second.machines = [ "one" ];
          };
        };
      };
      imageOf =
        key:
        reader.read {
          plan = result.plan;
          inherit key;
          profile = "trusted";
        };
      first = imageOf "svc:first@one";
      second = imageOf "svc:second@one";
    in
    {
      expr = {
        names = [
          first.name
          second.name
        ];
        files = [
          first.units.daemon.file
          second.units.daemon.file
        ];
        collide = first.units.daemon.file == second.units.daemon.file;
        prefixed = [
          (hasInfix first.name first.units.daemon.file)
          (hasInfix second.name second.units.daemon.file)
        ];
      };
      expected = {
        names = [
          "svc-first"
          "svc-second"
        ];
        files = [
          "svc-first-daemon.service"
          "svc-second-daemon.service"
        ];
        collide = false;
        prefixed = [
          true
          true
        ];
      };
    };

  testAnApplyAndExitUnit =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.dump = {
          command = "${borgbackup}/bin/borg create";
          oneShot = true;
          remainAfterExit = true;
          timeout = "30m";
        };
      });
      text = reader.renderUnit image "dump";
    in
    {
      expr = {
        oneShot = hasInfix "Type=oneshot" text;
        remain = hasInfix "RemainAfterExit=yes" text;
        timeout = hasInfix "TimeoutStartSec=30m" text;
        restart = hasInfix "Restart=" text;
        wantedBy = hasInfix "WantedBy=" text;
      };
      expected = {
        oneShot = true;
        remain = true;
        timeout = true;
        restart = false;
        wantedBy = false;
      };
    };

  testTwoUnitsWithDifferentEnvironments =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.web = {
          command = "${borgbackup}/bin/borg serve";
          env.ROLE = "web";
        };
        units.db = {
          command = "${borgbackup}/bin/borg init";
          env.ROLE = "db";
        };
      });
      web = reader.renderUnit image "web";
      db = reader.renderUnit image "db";
    in
    {
      expr = {
        webCarriesItsOwn = hasInfix "Environment=ROLE=web" web;
        webCarriesTheOther = hasInfix "Environment=ROLE=db" web;
        dbCarriesItsOwn = hasInfix "Environment=ROLE=db" db;
        dbCarriesTheOther = hasInfix "Environment=ROLE=web" db;
      };
      expected = {
        webCarriesItsOwn = true;
        webCarriesTheOther = false;
        dbCarriesItsOwn = true;
        dbCarriesTheOther = false;
      };
    };

  testAnOrderingIsNotARequirement =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.first.command = "${borgbackup}/bin/borg init";
        units.second = {
          command = "${borgbackup}/bin/borg serve";
          after = [ "first" ];
        };
        units.third = {
          command = "${borgbackup}/bin/borg check";
          requires = [ "first" ];
        };
      });
      ordered = reader.renderUnit image "second";
      required = reader.renderUnit image "third";
    in
    {
      expr = {
        orderedAfter = hasInfix "After=svc-only-first.service" ordered;
        orderedRequires = hasInfix "Requires=" ordered;
        requiredRequires = hasInfix "Requires=svc-only-first.service" required;
        requiredAfter = hasInfix "After=" required;
      };
      expected = {
        orderedAfter = true;
        orderedRequires = false;
        requiredRequires = true;
        requiredAfter = false;
      };
    };

  testAScheduledUnit =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.nightly = {
          command = "${borgbackup}/bin/borg create";
          oneShot = true;
          schedule = "daily";
        };
      });
      timer = reader.renderTimer image "nightly";
      attachment = reader.attachment image;
    in
    {
      expr = {
        file = image.units.nightly.file;
        timerFile = image.units.nightly.timer;
        onCalendar = hasInfix "OnCalendar=daily" timer;
        namesItsService = hasInfix "Unit=svc-only-nightly.service" timer;
        attachmentUnits = attachment.units;
      };
      expected = {
        file = "svc-only-nightly.service";
        timerFile = "svc-only-nightly.timer";
        onCalendar = true;
        namesItsService = true;
        attachmentUnits = [
          "svc-only-nightly.service"
          "svc-only-nightly.timer"
        ];
      };
    };

  testASystemdExtensionIsRendered =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          extends = [
            {
              extension = systemdService;
              values = {
                protectSystem = "strict";
                stateDirectory = "borg";
              };
            }
          ];
        };
      });
      text = reader.renderUnit image "only";
    in
    {
      expr = {
        protectSystem = hasInfix "ProtectSystem=strict" text;
        stateDirectory = hasInfix "StateDirectory=borg" text;
        directives = attrNames image.units.only.directives;
      };
      expected = {
        protectSystem = true;
        stateDirectory = true;
        directives = [
          "protectSystem"
          "stateDirectory"
        ];
      };
    };

  testAnExtensionForAnotherBackend =
    let
      launchdService = planner.unitExtension {
        backend = "launchd";
        name = "launchd-service";
        fields.keepAlive = {
          type = korora.bool;
        };
      };
      image =
        readOf
          {
            machines = laptopMachines;
            machine = "laptop";
          }
          (_: {
            closure = [ borgbackup ];
            units.only = {
              command = "${borgbackup}/bin/borg serve";
              extends = [
                {
                  extension = launchdService;
                  values.keepAlive = true;
                }
              ];
            };
          });
    in
    {
      expr = raises image;
      expected = true;
    };

  testAnUnknownExtensionField =
    let
      exotic = planner.unitExtension {
        backend = "systemd";
        name = "exotic";
        fields.blockIODeviceWeight = {
          type = korora.string;
        };
      };
      unknown = readOf { } (_: {
        closure = [ borgbackup ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          extends = [
            {
              extension = exotic;
              values.blockIODeviceWeight = "/dev/sda 500";
            }
          ];
        };
      });
    in
    {
      expr = {
        unknownRaises = raises unknown;
        knownDoesNot = raises (
          readOf { } (_: {
            closure = [ borgbackup ];
            units.only = {
              command = "${borgbackup}/bin/borg serve";
              extends = [
                {
                  extension = systemdService;
                  values.stateDirectory = "borg";
                }
              ];
            };
          })
        );
        directiveNames = length (attrNames reader.systemdDirectives);
      };
      expected = {
        unknownRaises = true;
        knownDoesNot = false;
        directiveNames = 16;
      };
    };

  testASecretIsReferencedNotCarried =
    let
      withSecret =
        closure:
        planOf {
          instances.holder = {
            module = soleRoot {
              module = _: {
                vars.hostKey.files."key".secrecy = "secret";
                impl =
                  { vars, ... }:
                  {
                    inherit closure;
                    units.only = {
                      command = "${borgbackup}/bin/borg serve";
                      env.KEYFILE = vars.hostKey."key".path;
                    };
                  };
              };
            };
            placement.every.only.machines = [ "one" ];
          };
          varsState.one.hostKey."key" = {
            present = true;
            content = "PRIVATE-KEY-BYTES";
          };
        };
      result = withSecret [ borgbackup ];
      image = reader.read {
        plan = result.plan;
        key = "holder:only@one";
        profile = "trusted";
      };
      attachment = reader.attachment image;
      baked = withSecret [
        borgbackup
        "/run/vars/hostKey/key"
      ];
    in
    {
      expr = {
        closure = image.closure;
        hostPaths = map (p: p.path) attachment.hostPaths;
        kinds = map (p: p.kind) attachment.hostPaths;
        bytesAnywhere = hasInfix "PRIVATE-KEY-BYTES" (builtins.toJSON attachment);
        bakingItInRaises = raises (
          reader.read {
            plan = baked.plan;
            key = "holder:only@one";
            profile = "trusted";
          }
        );
      };
      expected = {
        closure = [ borgbackup ];
        hostPaths = [ "/run/vars/hostKey/key" ];
        kinds = [ "generated-file" ];
        bytesAnywhere = false;
        bakingItInRaises = true;
      };
    };

  testARenderRecipeIsAssembledOnTheHost =
    let
      result = planOf {
        instances.holder = {
          module = soleRoot {
            module = _: {
              vars.hostKey.files."key".secrecy = "secret";
              impl =
                { vars, ... }:
                {
                  closure = [ borgbackup ];
                  units.only.command = "${borgbackup}/bin/borg serve";
                  configData."/etc/agent.conf" = {
                    mode = "0400";
                    reload = [ "only" ];
                    render = [
                      { text = "key_file = "; }
                      { ref = vars.hostKey."key".path; }
                    ];
                  };
                };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
        varsState.one.hostKey."key" = {
          present = true;
          content = "PRIVATE-KEY-BYTES";
        };
      };
      image = reader.read {
        plan = result.plan;
        key = "holder:only@one";
        profile = "trusted";
      };
      attachment = reader.attachment image;
      unit = reader.renderUnit image "only";
    in
    {
      expr = {
        paths = map (p: p.path) attachment.hostPaths;
        staged = map (p: p.from) attachment.hostPaths;
        dispositions = map (p: p.disposition) attachment.hostPaths;
        boundInTheUnit = hasInfix "BindReadOnlyPaths=/run/portable-planner/holder-only/files/etc/agent.conf:/etc/agent.conf" unit;
        bytesAnywhere = hasInfix "PRIVATE-KEY-BYTES" (builtins.toJSON attachment);
      };
      expected = {
        paths = [
          "/etc/agent.conf"
          "/run/vars/hostKey/key"
        ];
        staged = [
          "/run/portable-planner/holder-only/files/etc/agent.conf"
          "/run/vars/hostKey/key"
        ];
        dispositions = [
          "render"
          "reference"
        ];
        boundInTheUnit = true;
        bytesAnywhere = false;
      };
    };

  testTheDescriptionIsReviewable =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.only.command = "${borgbackup}/bin/borg serve";
        configData."/etc/thing.conf" = {
          mode = "0444";
          reload = [ "only" ];
          render = [ { text = "value\n"; } ];
        };
      });
      attachment = reader.attachment image;
    in
    {
      expr = {
        fields = attrNames attachment;
        entry = attachment.entry;
        units = attachment.units;
        profile = attachment.profile;
        target = attachment.target;
        paths = map (p: p.path) attachment.hostPaths;
        image = attachment.image;
      };
      expected = {
        fields = [
          "closure"
          "entry"
          "generated"
          "hostPaths"
          "image"
          "name"
          "profile"
          "staging"
          "storeDir"
          "target"
          "units"
          "version"
        ];
        entry = "svc:only@one";
        units = [ "svc-only-only.service" ];
        profile = "trusted";
        target = {
          system = "x86_64-linux";
          serviceManager = "systemd";
        };
        paths = [ "/etc/thing.conf" ];
        image = "svc-only_${image.version}.raw";
      };
    };

  # Every profile but trusted carries DynamicUser=yes and PrivateUsers=yes.
  testAProfileDeniesWhatAUnitNeeds =
    let
      withUser =
        profile:
        readOf { inherit profile; } (_: {
          closure = [ borgbackup ];
          units.only = {
            command = "${borgbackup}/bin/borg serve";
            user = "borg";
          };
        });
    in
    {
      expr = {
        underDefault = raises (withUser "default");
        underStrict = raises (withUser "strict");
        underNonetwork = raises (withUser "nonetwork");
        underTrusted = raises (withUser "trusted");
        unknownProfile = raises (withUser "permissive");
        profiles = reader.profileNames;
      };
      expected = {
        underDefault = true;
        underStrict = true;
        underNonetwork = true;
        underTrusted = false;
        unknownProfile = true;
        profiles = [
          "default"
          "nonetwork"
          "strict"
          "trusted"
        ];
      };
    };

  testAProfileDeniesAHostFileOnlyRootMayRead =
    let
      withSecret =
        profile:
        let
          result = planOf {
            instances.holder = {
              module = soleRoot {
                module = _: {
                  vars.hostKey.files."key".secrecy = "secret";
                  impl =
                    { vars, ... }:
                    {
                      closure = [ borgbackup ];
                      units.only = {
                        command = "${borgbackup}/bin/borg serve";
                        env.KEYFILE = vars.hostKey."key".path;
                      };
                    };
                };
              };
              placement.every.only.machines = [ "one" ];
            };
            varsState.one.hostKey."key" = {
              present = true;
              content = "PRIVATE-KEY-BYTES";
            };
          };
        in
        reader.read {
          plan = result.plan;
          key = "holder:only@one";
          inherit profile;
        };
    in
    {
      expr = {
        underDefault = raises (withSecret "default");
        underTrusted = raises (withSecret "trusted");
        deniedByStrict = reader.profiles.strict.denies;
        deniedByTrusted = reader.profiles.trusted.denies;
      };
      expected = {
        underDefault = true;
        underTrusted = false;
        deniedByStrict = [
          "a static host user"
          "a host file only root may read"
        ];
        deniedByTrusted = [ ];
      };
    };

  testARebuildIsIdentical =
    let
      first = rebuilt.imageOf rebuilt.base rebuilt.key;
      again = rebuilt.imageOf rebuilt.base rebuilt.key;
    in
    {
      expr = {
        version = first.version == again.version;
        unit = rebuilt.unitOf first == rebuilt.unitOf again;
      };
      expected = {
        version = true;
        unit = true;
      };
    };

  # A configuration file's content never enters the image, so the version stays put
  # while the entry key moves.
  testAConfigurationChangeLeavesTheImageByteIdentical =
    let
      first = rebuilt.imageOf rebuilt.base rebuilt.key;
      changed = rebuilt.imageOf (rebuilt.base // { text = "after"; }) rebuilt.key;
    in
    {
      expr = {
        version = first.version == changed.version;
        unit = rebuilt.unitOf first == rebuilt.unitOf changed;
        key = first.entry.key != changed.entry.key;
        reload = changed.entry.configData."/etc/thing.conf".reload;
      };
      expected = {
        version = true;
        unit = true;
        key = true;
        reload = [ "only" ];
      };
    };

  testAUnitFieldChanges =
    let
      edited = rebuilt.base // {
        timeout = "45m";
      };
      first = rebuilt.imageOf rebuilt.base rebuilt.key;
      changed = rebuilt.imageOf edited rebuilt.key;
      otherBefore = rebuilt.imageOf rebuilt.base rebuilt.otherKey;
      otherAfter = rebuilt.imageOf edited rebuilt.otherKey;
    in
    {
      expr = {
        key = first.entry.key != changed.entry.key;
        version = first.version != changed.version;
        unit = rebuilt.unitOf first != rebuilt.unitOf changed;
        otherVersion = otherBefore.version == otherAfter.version;
        otherUnit = rebuilt.unitOf otherBefore == rebuilt.unitOf otherAfter;
      };
      expected = {
        key = true;
        version = true;
        unit = true;
        otherVersion = true;
        otherUnit = true;
      };
    };

  testAnUnrelatedEdit =
    let
      deployment =
        level:
        planOf {
          instances = {
            tuned = {
              module = soleRoot {
                module = _: {
                  impl =
                    { settings, ... }:
                    {
                      closure = [ borgbackup ];
                      units.only = {
                        command = "${borgbackup}/bin/borg serve";
                        env.LOG_LEVEL = settings.level;
                      };
                    };
                };
                defaults.level = "info";
              };
              placement.every.only.machines = [ "one" ];
              settings.only.level = level;
            };
            other = {
              module = soleRoot {
                module = _: {
                  impl = _: {
                    closure = [ openssh ];
                    units.only.command = "${openssh}/bin/sshd";
                  };
                };
              };
              placement.every.only.machines = [ "two" ];
            };
          };
        };
      imageOf =
        level: key:
        reader.read {
          plan = (deployment level).plan;
          inherit key;
          profile = "trusted";
        };
      beforeOther = imageOf "info" "other:only@two";
      afterOther = imageOf "debug" "other:only@two";
      beforeTuned = imageOf "info" "tuned:only@one";
      afterTuned = imageOf "debug" "tuned:only@one";
    in
    {
      expr = {
        otherVersionUnchanged = beforeOther.version == afterOther.version;
        otherUnitUnchanged = reader.renderUnit beforeOther "only" == reader.renderUnit afterOther "only";
        tunedVersionMoved = beforeTuned.version != afterTuned.version;
        tunedUnitMoved = reader.renderUnit beforeTuned "only" != reader.renderUnit afterTuned "only";
      };
      expected = {
        otherVersionUnchanged = true;
        otherUnitUnchanged = true;
        tunedVersionMoved = true;
        tunedUnitMoved = true;
      };
    };

  testAnEntryWithNoUnit = {
    expr = raises (
      readOf { } (_: {
        closure = [ ];
      })
    );
    expected = true;
  };
}
