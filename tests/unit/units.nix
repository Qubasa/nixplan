{ planner, support }:
let
  inherit (builtins)
    attrNames
    toJSON
    ;

  inherit (support)
    countById
    evidenceById
    hasInfix
    korora
    messageById
    planOf
    rowIds
    severityById
    soleRoot
    systemdService
    ;

  inherit (support.worked) openssh borgbackup;

  laptopMachines = support.machines // {
    laptop = support.laptop;
  };

  otherSystemdService = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      privateTmp = {
        type = korora.bool;
      };
    };
  };

  launchdService = planner.unitExtension {
    backend = "launchd";
    name = "launchd-service";
    fields = {
      keepAlive = {
        type = korora.bool;
      };
    };
  };

  placed =
    machines: implementation:
    planOf {
      instances.svc = {
        module = soleRoot {
          module = _: {
            impl = implementation;
          };
        };
        placement.every.only = { inherit machines; };
      };
    };

  entryOf = result: machine: result.plan."svc:only@${machine}";

  verifies = type: value: type.verify value == null;
in
{
  testTheVocabularyAtomTypesVerify = {
    expr = {
      unitRef = [
        (verifies korora.unitRef "borgRepo")
        (verifies korora.unitRef "not a unit")
        (verifies korora.unitRef "")
      ];
      duration = [
        (verifies korora.duration "30m")
        (verifies korora.duration "1h30m")
        (verifies korora.duration "90")
        (verifies korora.duration "soon")
        (verifies korora.duration "-5s")
      ];
      schedule = [
        (verifies korora.schedule "daily")
        (verifies korora.schedule "*-*-* 04:00:00")
        (verifies korora.schedule "Mon 04:00")
        (verifies korora.schedule "whenever")
      ];
      userName = [
        (verifies korora.userName "myapp")
        (verifies korora.userName "_borg")
        (verifies korora.userName "Root Admin")
        (verifies korora.userName "1000")
      ];
    };
    expected = {
      unitRef = [
        true
        false
        false
      ];
      duration = [
        true
        true
        true
        false
        false
      ];
      schedule = [
        true
        true
        true
        false
      ];
      userName = [
        true
        true
        false
        false
      ];
    };
  };

  testALongRunningUnit =
    let
      result = placed [ "one" ] (_: {
        closure = [ openssh ];
        units.web = {
          command = "${openssh}/bin/sshd";
          env.PORT = "8080";
        };
      });
      unit = (entryOf result "one").units.web;
    in
    {
      expr = {
        fields = attrNames unit;
        env = unit.env;
        rows = result.diagnostics;
      };
      expected = {
        fields = [
          "command"
          "env"
        ];
        env.PORT = "8080";
        rows = [ ];
      };
    };

  testAUnitThatAppliesAndExits =
    let
      result = placed [ "one" ] (_: {
        closure = [ borgbackup ];
        units.dump = {
          command = "${borgbackup}/bin/borg init";
          oneShot = true;
          remainAfterExit = true;
          timeout = "30m";
        };
      });
      unit = (entryOf result "one").units.dump;
    in
    {
      expr = {
        fields = attrNames unit;
        oneShot = unit.oneShot;
        remainAfterExit = unit.remainAfterExit;
        timeout = unit.timeout;
        rows = result.diagnostics;
      };
      expected = {
        fields = [
          "command"
          "oneShot"
          "remainAfterExit"
          "timeout"
        ];
        oneShot = true;
        remainAfterExit = true;
        timeout = "30m";
        rows = [ ];
      };
    };

  testAMistypedFieldValue =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/true";
          oneShot = "yes";
          timeout = "soon";
        };
      });
      unit = (entryOf result "one").units.web;
    in
    {
      expr = {
        rows = rowIds result;
        namesTheUnit = hasInfix "`web`" (messageById "unit-field-type-mismatch" result);
        namesAType = hasInfix "duration" (toJSON result.diagnostics);
        recordedFields = attrNames unit;
      };
      expected = {
        rows = [
          "unit-field-type-mismatch"
          "unit-field-type-mismatch"
        ];
        namesTheUnit = true;
        namesAType = true;
        recordedFields = [ "command" ];
      };
    };

  testAUnitReferenceToAUnitTheModuleDoesNotOwn =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/true";
          after = [ "postgres" ];
          requires = [ "postgres" ];
        };
      });
      unit = (entryOf result "one").units.web;
    in
    {
      expr = {
        rows = rowIds result;
        namesTheReference = hasInfix "`postgres`" (messageById "unit-reference-unknown" result);
        recordedFields = attrNames unit;
      };
      expected = {
        rows = [
          "unit-reference-unknown"
          "unit-reference-unknown"
        ];
        namesTheReference = true;
        recordedFields = [ "command" ];
      };
    };

  testAnOrderingAndARequirementAreDistinct =
    let
      result = placed [ "one" ] (_: {
        units.db.command = "/bin/db";
        units.web = {
          command = "/bin/web";
          after = [ "db" ];
        };
        units.worker = {
          command = "/bin/worker";
          requires = [ "db" ];
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        web = attrNames entry.units.web;
        worker = attrNames entry.units.worker;
        after = entry.units.web.after;
        requires = entry.units.worker.requires;
        rows = result.diagnostics;
      };
      expected = {
        web = [
          "after"
          "command"
        ];
        worker = [
          "command"
          "requires"
        ];
        after = [ "db" ];
        requires = [ "db" ];
        rows = [ ];
      };
    };

  testAUnitFieldIsInTheEntryKey =
    let
      deployment =
        timeout:
        planOf {
          instances = {
            tuned = {
              module = soleRoot {
                module = _: {
                  impl = _: {
                    units.only = {
                      command = "/bin/true";
                      inherit timeout;
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
                    units.only.command = "/bin/true";
                  };
                };
              };
              placement.every.only.machines = [ "two" ];
            };
          };
        };
      before = deployment "30m";
      after = deployment "45m";
    in
    {
      expr = {
        tunedKeyChanged = before.plan."tuned:only@one".key != after.plan."tuned:only@one".key;
        otherKeyUnchanged = before.plan."other:only@two".key == after.plan."other:only@two".key;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        tunedKeyChanged = true;
        otherKeyUnchanged = true;
        rows = [ ];
      };
    };

  testTwoUnitsDisagreeAboutAVariable =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          env.PGDATA = "/var/lib/web";
        };
        units.db = {
          command = "/bin/db";
          env.PGDATA = "/var/lib/db";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        web = entry.units.web.env.PGDATA;
        db = entry.units.db.env.PGDATA;
        agreed = entry.env or { };
        rows = result.diagnostics;
      };
      expected = {
        web = "/var/lib/web";
        db = "/var/lib/db";
        agreed = { };
        rows = [ ];
      };
    };

  testTwoUnitsAgreeAboutAVariable =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          env = {
            TZ = "UTC";
            ROLE = "web";
          };
        };
        units.db = {
          command = "/bin/db";
          env = {
            TZ = "UTC";
            ROLE = "db";
          };
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        onBothUnits = [
          entry.units.web.env.TZ
          entry.units.db.env.TZ
        ];
        agreed = entry.env;
        rows = result.diagnostics;
      };
      expected = {
        onBothUnits = [
          "UTC"
          "UTC"
        ];
        agreed.TZ = "UTC";
        rows = [ ];
      };
    };

  testOneUnitsEnvironmentChanges =
    let
      deployment =
        level:
        placed [ "one" ] (_: {
          closure = [ openssh ];
          units.web = {
            command = "${openssh}/bin/sshd";
            env.LOG_LEVEL = level;
          };
          units.db.command = "/bin/db";
        });
      before = (deployment "info").plan."svc:only@one";
      after = (deployment "debug").plan."svc:only@one";
    in
    {
      expr = {
        keyChanged = before.key != after.key;
        closureUnchanged = before.closure == after.closure;
        env = [
          before.units.web.env.LOG_LEVEL
          after.units.web.env.LOG_LEVEL
        ];
      };
      expected = {
        keyChanged = true;
        closureUnchanged = true;
        env = [
          "info"
          "debug"
        ];
      };
    };

  testASystemdExtensionOnASystemdTarget =
    let
      result = placed [ "one" ] (
        { target, ... }:
        {
          units.web = {
            command = "/bin/web";
            extends = [
              {
                extension = systemdService;
                values.protectSystem = "strict";
              }
            ];
          }
          // (if target.serviceManager == "systemd" then { } else { });
        }
      );
      unit = (entryOf result "one").units.web;
    in
    {
      expr = {
        extends = unit.extends;
        rows = result.diagnostics;
      };
      expected = {
        extends.systemd.protectSystem = "strict";
        rows = [ ];
      };
    };

  testAPartialExtensionApplication =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          extends = [
            {
              extension = systemdService;
              values.stateDirectory = "myapp";
            }
          ];
        };
      });
      unit = (entryOf result "one").units.web;
    in
    {
      expr = {
        fields = attrNames unit.extends.systemd;
        value = unit.extends.systemd.stateDirectory;
        rows = result.diagnostics;
      };
      expected = {
        fields = [ "stateDirectory" ];
        value = "myapp";
        rows = [ ];
      };
    };

  testAnUnknownKeyInsideAnExtensionApplication =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          extends = [
            {
              extension = systemdService;
              values.protectHome = "yes";
            }
          ];
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "`protectHome`" (messageById "unit-extension-unknown-field" result);
        namesTheUnit = hasInfix "`web`" (messageById "unit-extension-unknown-field" result);
        namesTheExtension = hasInfix "systemd-service" (messageById "unit-extension-unknown-field" result);
        recordedFields = attrNames entry.units.web.extends.systemd;
      };
      expected = {
        rows = [ "unit-extension-unknown-field" ];
        namesTheKey = true;
        namesTheUnit = true;
        namesTheExtension = true;
        recordedFields = [ ];
      };
    };

  testAMistypedExtensionValue =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          extends = [
            {
              extension = systemdService;
              values.protectSystem = "sometimes";
            }
          ];
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`protectSystem`" (messageById "unit-extension-type-mismatch" result);
        namesTheType = hasInfix "protectSystem as" (evidenceById "unit-extension-type-mismatch" result);
        recordedFields = attrNames entry.units.web.extends.systemd;
      };
      expected = {
        rows = [ "unit-extension-type-mismatch" ];
        namesTheField = true;
        namesTheType = true;
        recordedFields = [ ];
      };
    };

  testTwoExtensionsSharingAName =
    let
      result = planOf {
        interfaces = {
          "extensions/systemd.nix" = {
            inherit systemdService;
          };
          "extensions/other.nix" = {
            systemdService = otherSystemdService;
          };
        };
        instances = {
          first = {
            module = soleRoot {
              module = _: {
                impl = _: {
                  units.only = {
                    command = "/bin/first";
                    extends = [
                      {
                        extension = systemdService;
                        values.stateDirectory = "first";
                      }
                    ];
                  };
                };
              };
            };
            placement.every.only.machines = [ "one" ];
          };
          second = {
            module = soleRoot {
              module = _: {
                impl = _: {
                  units.only = {
                    command = "/bin/second";
                    extends = [
                      {
                        extension = otherSystemdService;
                        values.privateTmp = true;
                      }
                    ];
                  };
                };
              };
            };
            placement.every.only.machines = [ "two" ];
          };
        };
      };
    in
    {
      expr = {
        first = result.plan."first:only@one".units.only.extends;
        second = result.plan."second:only@two".units.only.extends;
        rows = result.diagnostics;
      };
      expected = {
        first.systemd.stateDirectory = "first";
        second.systemd.privateTmp = true;
        rows = [ ];
      };
    };

  testAnExtensionFieldDeclaresAnUnknownKey =
    let
      malformed = planner.unitExtension {
        backend = "systemd";
        name = "malformed";
        fields = {
          protectSystem = {
            type = korora.string;
            secrecy = "public";
          };
          locality = {
            type = korora.string;
          };
        };
      };
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          extends = [ { extension = malformed; } ];
        };
      });
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "`secrecy`" (messageById "unit-extension-unknown-key" result);
      };
      expected = {
        rows = [ "unit-extension-unknown-key" ];
        namesTheKey = true;
      };
    };

  testOneModulePlacedOnTwoServiceManagers =
    let
      result = planOf {
        machines = laptopMachines;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl =
                { target, ... }:
                {
                  units.web = {
                    command = "/bin/web";
                    env.PORT = "8080";
                  }
                  // (
                    if target.serviceManager == "systemd" then
                      {
                        extends = [
                          {
                            extension = systemdService;
                            values.protectSystem = "strict";
                          }
                        ];
                      }
                    else
                      { }
                  );
                };
            };
          };
          placement.every.only.machines = [
            "one"
            "laptop"
          ];
        };
      };
      systemd = result.plan."svc:only@one".units.web;
      launchd = result.plan."svc:only@laptop".units.web;
    in
    {
      expr = {
        portableFieldsAgree = removeAttrs systemd [ "extends" ] == launchd;
        systemdExtends = systemd.extends;
        launchdExtends = launchd ? extends;
        serviceManagers = [
          result.plan."svc:only@one".target.serviceManager
          result.plan."svc:only@laptop".target.serviceManager
        ];
        rows = result.diagnostics;
      };
      expected = {
        portableFieldsAgree = true;
        systemdExtends.systemd.protectSystem = "strict";
        launchdExtends = false;
        serviceManagers = [
          "systemd"
          "launchd"
        ];
        rows = [ ];
      };
    };

  # An unplaced entry records no units, so a missing target is observed through the
  # module raising when the argument is there.
  testAnUnplacedMember =
    let
      deployment =
        placement:
        planOf {
          instances.svc = {
            module = soleRoot {
              module = _: {
                impl = args: {
                  units.only.command = if args ? target then throw "the planner handed a target" else "/bin/true";
                };
              };
            };
          }
          // placement;
        };
      unplaced = deployment { };
      placedSomewhere = deployment { placement.every.only.machines = [ "one" ]; };
      entry = unplaced.plan."svc:only";
    in
    {
      expr = {
        entryFields = attrNames entry;
        unplacedRows = rowIds unplaced;
        placedRows = rowIds placedSomewhere;
      };
      expected = {
        entryFields = [
          "key"
          "placement"
          "settings"
        ];
        unplacedRows = [ "member-not-placed" ];
        placedRows = [ "module-raised" ];
      };
    };

  testTheSameExtensionOnALaunchdTarget =
    let
      result = planOf {
        machines = laptopMachines;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = _: {
                units.web = {
                  command = "/bin/web";
                  extends = [
                    {
                      extension = systemdService;
                      values.protectSystem = "strict";
                    }
                  ];
                };
              };
            };
          };
          placement.every.only.machines = [ "laptop" ];
        };
      };
      entry = result.plan."svc:only@laptop";
    in
    {
      expr = {
        rows = rowIds result;
        namesBothBackends = [
          (hasInfix "`systemd`" (messageById "unit-extension-backend-mismatch" result))
          (hasInfix "`launchd`" (messageById "unit-extension-backend-mismatch" result))
        ];
        recordedUnderItsOwnBackend = entry.units.web.extends;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "unit-extension-backend-mismatch" ];
        namesBothBackends = [
          true
          true
        ];
        recordedUnderItsOwnBackend.systemd.protectSystem = "strict";
        applicable = false;
      };
    };

  testALaunchdExtensionOnALaunchdTarget =
    let
      result = planOf {
        machines = laptopMachines;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = _: {
                units.web = {
                  command = "/bin/web";
                  extends = [
                    {
                      extension = launchdService;
                      values.keepAlive = true;
                    }
                  ];
                };
              };
            };
          };
          placement.every.only.machines = [ "laptop" ];
        };
      };
    in
    {
      expr = {
        extends = result.plan."svc:only@laptop".units.web.extends;
        rows = result.diagnostics;
      };
      expected = {
        extends.launchd.keepAlive = true;
        rows = [ ];
      };
    };

  testARawServiceManagerStanzaWrittenOnAUnit =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          serviceConfig.ProtectSystem = "strict";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "`serviceConfig`" (messageById "implementation-unknown-key" result);
        namesTheUnit = hasInfix "unit `web`" (messageById "implementation-unknown-key" result);
        namesTheVocabulary = hasInfix "`remainAfterExit`" (messageById "implementation-unknown-key" result);
        recordedFields = attrNames entry.units.web;
      };
      expected = {
        rows = [ "implementation-unknown-key" ];
        namesTheKey = true;
        namesTheUnit = true;
        namesTheVocabulary = true;
        recordedFields = [ "command" ];
      };
    };

  testAMisspelledVocabularyField =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          remainsAfterExit = true;
        };
      });
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "`remainsAfterExit`" (messageById "implementation-unknown-key" result);
      };
      expected = {
        rows = [ "implementation-unknown-key" ];
        namesTheKey = true;
      };
    };

  testAnUnknownImplementationKey =
    let
      result = placed [ "one" ] (_: {
        units.web.command = "/bin/web";
        systemd.services.web = { };
      });
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "`systemd`" (messageById "implementation-unknown-key" result);
      };
      expected = {
        rows = [ "implementation-unknown-key" ];
        namesTheKey = true;
      };
    };

  testOneMalformedUnitBesideOneWellFormedUnit =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          restartSec = 5;
        };
        units.db = {
          command = "/bin/db";
          user = "postgres";
          env.PGDATA = "/var/lib/db";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rowCount = countById "implementation-unknown-key" result;
        rows = rowIds result;
        wellFormed = entry.units.db;
        entryIsInThePlan = result.plan ? "svc:only@one";
      };
      expected = {
        rowCount = 1;
        rows = [ "implementation-unknown-key" ];
        wellFormed = {
          command = "/bin/db";
          env.PGDATA = "/var/lib/db";
          user = "postgres";
        };
        entryIsInThePlan = true;
      };
    };

  # A key colliding with an excluded construct gets that construct's row and its
  # trigger, in preference to the unknown-key row.
  testAKeyNamingAnExcludedConstruct =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          lifecycle = "static";
        };
      });
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "declaration-excluded-key" result;
        namesTheTrigger = hasInfix (planner.excluded.constructs.lifecycle.trigger) (
          evidenceById "declaration-excluded-key" result
        );
      };
      expected = {
        rows = [ "declaration-excluded-key" ];
        severity = "error";
        namesTheTrigger = true;
      };
    };

  testAFileCopiedFromAStorePath =
    let
      result = placed [ "one" ] (_: {
        closure = [ openssh ];
        units.web.command = "/bin/web";
        configData."/etc/ssh/sshd_config" = {
          mode = "0644";
          reload = [ "web" ];
          source = "${openssh}/etc/sshd_config";
        };
      });
      file = (entryOf result "one").configData."/etc/ssh/sshd_config";
    in
    {
      expr = {
        fields = attrNames file;
        source = file.source;
        rows = result.diagnostics;
      };
      expected = {
        fields = [
          "computed"
          "mode"
          "reload"
          "source"
        ];
        source = "${openssh}/etc/sshd_config";
        rows = [ ];
      };
    };

  testAFileAssembledFromPublicLiterals =
    let
      deployment =
        text:
        placed [ "one" ] (_: {
          units.web.command = "/bin/web";
          configData."/etc/thing.conf" = {
            mode = "0444";
            reload = [ "web" ];
            render = [
              { text = "# generated\n"; }
              { text = "value = ${text}\n"; }
            ];
          };
        });
      before = (deployment "before").plan."svc:only@one".configData."/etc/thing.conf";
      after = (deployment "after").plan."svc:only@one".configData."/etc/thing.conf";
    in
    {
      expr = {
        fields = attrNames before;
        render = before.render;
        hashIsAHash = hasInfix "sha256-" before.contentHash;
        hashMoved = before.contentHash != after.contentHash;
      };
      expected = {
        fields = [
          "computed"
          "contentHash"
          "mode"
          "reload"
          "render"
        ];
        render = [
          { text = "# generated\n"; }
          { text = "value = before\n"; }
        ];
        hashIsAHash = true;
        hashMoved = true;
      };
    };

  testARecipeThatReferencesASecretPath =
    let
      bytes = "PRIVATE-KEY-BYTES-b7f3c1d9";
      result = planOf {
        instances.holder = {
          module = soleRoot {
            module = _: {
              vars.hostKey.files."key".secrecy = "secret";
              impl =
                { vars, ... }:
                {
                  units.web.command = "/bin/web";
                  configData."/etc/agent.conf" = {
                    mode = "0400";
                    reload = [ "web" ];
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
        varsState."holder:vars/hostKey@one"."key" = {
          present = true;
          content = bytes;
        };
      };
      file = result.plan."holder:only@one".configData."/etc/agent.conf";
    in
    {
      expr = {
        fields = attrNames file;
        render = file.render;
        structureHashIsAHash = hasInfix "sha256-" file.structureHash;
        bytesAnywhereInThePlan = hasInfix bytes (toJSON result.plan);
        rows = result.diagnostics;
      };
      expected = {
        fields = [
          "computed"
          "mode"
          "reload"
          "render"
          "structureHash"
        ];
        render = [
          { text = "key_file = "; }
          { ref = "/run/vars/holder/hostKey/key"; }
        ];
        structureHashIsAHash = true;
        bytesAnywhereInThePlan = false;
        rows = [ ];
      };
    };

  testAFileReloadingOneOfTwoUnits =
    let
      result = placed [ "one" ] (_: {
        units.web.command = "/bin/web";
        units.db.command = "/bin/db";
        configData."/etc/web.conf" = {
          mode = "0444";
          reload = [ "web" ];
          render = [ { text = "web\n"; } ];
        };
        configData."/etc/static.conf" = {
          mode = "0444";
          reload = [ ];
          render = [ { text = "static\n"; } ];
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        named = entry.configData."/etc/web.conf".reload;
        none = entry.configData."/etc/static.conf".reload;
        rows = result.diagnostics;
      };
      expected = {
        named = [ "web" ];
        none = [ ];
        rows = [ ];
      };
    };

  testBothDispositionsOnOneFile =
    let
      result = placed [ "one" ] (_: {
        units.web.command = "/bin/web";
        configData."/etc/thing.conf" = {
          mode = "0444";
          reload = [ ];
          source = "/etc/skel/thing.conf";
          render = [ { text = "value\n"; } ];
        };
      });
      file = (entryOf result "one").configData."/etc/thing.conf";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheFile = hasInfix "`/etc/thing.conf`" (messageById "config-file-disposition" result);
        identity = removeAttrs file [
          "computed"
          "mode"
          "reload"
        ];
        entryIsInThePlan = result.plan ? "svc:only@one";
      };
      expected = {
        rows = [ "config-file-disposition" ];
        namesTheFile = true;
        identity = { };
        entryIsInThePlan = true;
      };
    };

  testNeitherDispositionOnOneFile =
    let
      result = placed [ "one" ] (_: {
        units.web.command = "/bin/web";
        configData."/etc/thing.conf" = {
          mode = "0444";
          reload = [ "web" ];
        };
      });
    in
    {
      expr = {
        rows = rowIds result;
        namesNeither = hasInfix "neither" (messageById "config-file-disposition" result);
      };
      expected = {
        rows = [ "config-file-disposition" ];
        namesNeither = true;
      };
    };
}
