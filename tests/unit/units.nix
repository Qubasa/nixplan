{ planner, support }:
let
  inherit (builtins)
    attrNames
    filter
    toJSON
    ;

  inherit (support)
    countById
    evidenceById
    hasInfix
    korora
    laptopMachines
    messageById
    planOf
    rowIds
    severityById
    soleRoot
    subjectsById
    systemdService
    ;

  inherit (support.worked) openssh borgbackup;

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

  placed = on: support.entryPlan { inherit on; };

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
        support.entryPlan
          {
            instance = "tuned";
            instances.other = {
              module = soleRoot { module = _: { impl = _: { units.only.command = "/bin/true"; }; }; };
              placement.every.only.machines = [ "two" ];
            };
          }
          (_: {
            units.only = {
              command = "/bin/true";
              inherit timeout;
            };
          });
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
          restartLimit = 5;
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
          "group"
          "mode"
          "owner"
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
          "group"
          "mode"
          "owner"
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
      result = support.valuePlan {
        instance = "holder";
        unit = "web";
        content = bytes;
        extra = vars: {
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
          "group"
          "mode"
          "owner"
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
          "group"
          "mode"
          "owner"
          "reload"
        ];
        entryIsInThePlan = result.plan ? "svc:only@one";
      };
      expected = {
        # The file states two dispositions and a `source` that is no store
        # object, which are two facts and two rows.
        rows = [
          "config-file-disposition"
          "config-file-source-refused"
        ];
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

  testAUnitThatIsRestartedWhenItFails =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          restart = "on-failure";
          restartSec = "5s";
        };
        units.db.command = "/bin/db";
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        web = entry.units.web;
        db = entry.units.db;
      };
      expected = {
        rows = [ ];
        web = {
          command = "/bin/web";
          restart = "on-failure";
          restartSec = "5s";
        };
        db.command = "/bin/db";
      };
    };

  testARestartPolicyOutsideItsDomain =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          restart = "sometimes";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheDomain = hasInfix "`on-abnormal`" (evidenceById "unit-field-type-mismatch" result);
        namesTheField = hasInfix "`restart`" (messageById "unit-field-type-mismatch" result);
        recorded = entry.units.web;
      };
      expected = {
        rows = [ "unit-field-type-mismatch" ];
        namesTheDomain = true;
        namesTheField = true;
        recorded.command = "/bin/web";
      };
    };

  testARestartDelayWithNoPolicy =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          restartSec = "5s";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheUnit = hasInfix "unit `web`" (messageById "unit-restart-delay-without-policy" result);
        recorded = entry.units.web;
      };
      expected = {
        rows = [ "unit-restart-delay-without-policy" ];
        namesTheUnit = true;
        recorded.command = "/bin/web";
      };
    };

  # The key is a digest over the record, and the record carries neither field, so
  # a unit that declared neither keys exactly as it did before the vocabulary
  # carried them.
  testAUnitThatDeclaresNoPolicyKeepsItsKey =
    let
      result = placed [ "one" ] (_: {
        units.web.command = "/bin/web";
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        fields = attrNames entry.units.web;
        keyMentionsEither = hasInfix "restart" (toJSON entry.units);
      };
      expected = {
        rows = [ ];
        fields = [ "command" ];
        keyMentionsEither = false;
      };
    };

  testAOneShotUnitAskingToBeRestartedAlways =
    let
      result = placed [ "one" ] (_: {
        units.job = {
          command = "/bin/job";
          oneShot = true;
          restart = "always";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheUnit = hasInfix "unit `job`" (messageById "unit-restart-contradicts-one-shot" result);
        fields = attrNames entry.units.job;
      };
      expected = {
        rows = [ "unit-restart-contradicts-one-shot" ];
        namesTheUnit = true;
        fields = [
          "command"
          "oneShot"
        ];
      };
    };

  testAOneShotUnitRetriedOnFailure =
    let
      result = placed [ "one" ] (_: {
        units.job = {
          command = "/bin/job";
          oneShot = true;
          restart = "on-failure";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        recorded = entry.units.job.restart;
      };
      expected = {
        rows = [ ];
        recorded = "on-failure";
      };
    };

  testAScheduledUnitAskingForARestartPolicy =
    let
      result = placed [ "one" ] (_: {
        units.nightly = {
          command = "/bin/nightly";
          schedule = "daily";
          restart = "on-failure";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesThePolicy = hasInfix "`on-failure`" (messageById "unit-restart-on-scheduled" result);
        fields = attrNames entry.units.nightly;
      };
      expected = {
        rows = [ "unit-restart-on-scheduled" ];
        namesThePolicy = true;
        fields = [
          "command"
          "schedule"
        ];
      };
    };

  testAUnitDeclaringAStateDirectoryAndItsMode =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          stateDirectory = [ "myapp" ];
          stateDirectoryMode = "0700";
        };
        units.plain.command = "/bin/plain";
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        declaring = entry.units.web;
        silent = attrNames entry.units.plain;
      };
      expected = {
        rows = [ ];
        declaring = {
          command = "/bin/web";
          stateDirectory = [ "myapp" ];
          stateDirectoryMode = "0700";
        };
        silent = [ "command" ];
      };
    };

  testADirectoryModeWithNoDirectoryOfItsKind =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          cacheDirectoryMode = "0700";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheUnit = hasInfix "unit `web`" (messageById "unit-directory-mode-without-directory" result);
        namesTheModule = hasInfix "the module of `only`" (
          messageById "unit-directory-mode-without-directory" result
        );
        fields = attrNames entry.units.web;
      };
      expected = {
        rows = [ "unit-directory-mode-without-directory" ];
        namesTheUnit = true;
        namesTheModule = true;
        fields = [ "command" ];
      };
    };

  testADirectoryNameThatIsNotRelative =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          stateDirectory = [ "/var/lib/myapp" ];
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`stateDirectory`" (messageById "unit-field-type-mismatch" result);
        namesTheType = hasInfix "directoryName" (evidenceById "unit-field-type-mismatch" result);
        fields = attrNames entry.units.web;
      };
      expected = {
        rows = [ "unit-field-type-mismatch" ];
        namesTheField = true;
        namesTheType = true;
        fields = [ "command" ];
      };
    };

  # The key is a digest over the record, and a unit declaring none of the six
  # carries none of them, so such an entry keys as it did before the vocabulary
  # grew.
  testAUnitDeclaringNoDirectoryKeepsItsKey =
    let
      bare = placed [ "one" ] (_: {
        units.web.command = "/bin/web";
      });
      declaring = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          runtimeDirectory = [ "records" ];
        };
      });
    in
    {
      expr = {
        rows = rowIds bare;
        fields = attrNames (entryOf bare "one").units.web;
        keyMentionsADirectory = hasInfix "Directory" (toJSON (entryOf bare "one").units);
        key = (entryOf bare "one").key == (entryOf declaring "one").key;
      };
      expected = {
        rows = [ ];
        fields = [ "command" ];
        keyMentionsADirectory = false;
        key = false;
      };
    };

  testOneDirectoryKindDeclaredTwice =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          stateDirectory = [ "myapp" ];
          extends = [
            {
              extension = systemdService;
              values.stateDirectory = "myapp";
            }
          ];
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        names = map (needle: hasInfix needle (messageById "unit-directory-declared-twice" result)) [
          "the module of `only`"
          "unit `web`"
          "`stateDirectory`"
        ];
        fields = attrNames entry.units.web;
        extended = attrNames entry.units.web.extends.systemd;
      };
      expected = {
        rows = [ "unit-directory-declared-twice" ];
        names = [
          true
          true
          true
        ];
        fields = [
          "command"
          "extends"
        ];
        extended = [ ];
      };
    };

  testAUnitThatStartsOnlyWhileAPathIsMissing =
    let
      result = placed [ "one" ] (_: {
        units.bootstrap = {
          command = "/bin/bootstrap";
          startIfPathAbsent = "/var/lib/myapp/VERSION";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        recorded = entry.units.bootstrap;
        recordsNoDirective = hasInfix "Condition" (toJSON entry.units);
      };
      expected = {
        rows = [ ];
        recorded = {
          command = "/bin/bootstrap";
          startIfPathAbsent = "/var/lib/myapp/VERSION";
        };
        recordsNoDirective = false;
      };
    };

  testAUnitThatStartsOnlyOnceAPathExists =
    let
      result = placed [ "one" ] (_: {
        units.report = {
          command = "/bin/report";
          startIfPathPresent = "/var/lib/myapp/VERSION";
        };
        units.plain.command = "/bin/plain";
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        recorded = entry.units.report;
        silent = attrNames entry.units.plain;
      };
      expected = {
        rows = [ ];
        recorded = {
          command = "/bin/report";
          startIfPathPresent = "/var/lib/myapp/VERSION";
        };
        silent = [ "command" ];
      };
    };

  testAConditionThatContradictsItself =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          startIfPathPresent = "/var/lib/myapp/VERSION";
          startIfPathAbsent = "/var/lib/myapp/VERSION";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        names = map (needle: hasInfix needle (messageById "unit-condition-contradicts-itself" result)) [
          "the module of `only`"
          "unit `web`"
          "`/var/lib/myapp/VERSION`"
        ];
        fields = attrNames entry.units.web;
      };
      expected = {
        rows = [ "unit-condition-contradicts-itself" ];
        names = [
          true
          true
          true
        ];
        fields = [ "command" ];
      };
    };

  testAConditionPathThatIsNotAbsolute =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          startIfPathPresent = "var/lib/myapp/VERSION";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`startIfPathPresent`" (messageById "unit-field-type-mismatch" result);
        namesTheType = hasInfix "absolutePath" (evidenceById "unit-field-type-mismatch" result);
        fields = attrNames entry.units.web;
      };
      expected = {
        rows = [ "unit-field-type-mismatch" ];
        namesTheField = true;
        namesTheType = true;
        fields = [ "command" ];
      };
    };

  testAnEnvironmentNameNoUnitFileHasALineFor =
    let
      hostile = "A\nExecStartPost=/bin/sh -c evil\n#";
      result = placed [ "one" ] (_: {
        units.say = {
          command = "/bin/true";
          env = {
            ${hostile} = "x";
            MOTD = "one line";
          };
        };
      });
      table = planner.render result.diagnostics;
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "unit-env-name-malformed" result;
        applicable = result.applicable;
        theTableCarriesNoDirectiveLine = hasInfix "\nExecStartPost" table;
      };
      expected = {
        # One name, one row: the grammar refuses it, so the line-break rule the
        # values are held to says nothing about it a second time.
        rows = [ "unit-env-name-malformed" ];
        severity = "error";
        applicable = false;
        theTableCarriesNoDirectiveLine = false;
      };
    };

  # The same rule for a name the grammar refuses for a reason no other rule
  # looks at: `1st-choice` opens with a digit and carries a hyphen, and neither
  # is a character a service manager carries in the left half of an assignment.
  testAnEnvironmentNameIsHeldToTheEnvironmentNameGrammar =
    let
      id = "unit-env-name-malformed";
      result = placed [ "one" ] (_: {
        units.say = {
          command = "/bin/true";
          env = {
            "1st-choice" = "never rendered";
            MOTD = "one line";
          };
        };
      });
    in
    {
      expr = {
        # One name, one row: the grammar refuses it once, and the character
        # classes it is outside of are not four rows.
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (messageById id result)) [
          "`say`"
          "`1st-choice`"
        ];
        # The name is on no unit and so is the value written under it.
        recorded = (entryOf result "one").units.say.env;
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        names = [
          true
          true
        ];
        recorded = {
          MOTD = "one line";
        };
        applicable = false;
      };
    };

  # The cheap scan gates the walk in `lib/module.nix`, so a record the walk has a
  # row about and the scan answers no for is a row nobody sees.
  testTheCheapScanSeesEveryStringTheWalkReports =
    let
      records = [
        { env.MOTD = "one line"; }
        { env.MOTD = "first\nsecond"; }
        { env."A\nUser=root" = "x"; }
        {
          list = [
            "ok"
            "bad\nUser=root"
          ];
        }
        { nested.deep."A\nUser=root".inner = "x"; }
      ];
      walked = filter (
        record:
        filter (found: planner.util.carriesLineBreak found.value) (planner.util.stringsDeep record) != [ ]
      ) records;
      scanned = filter planner.util.anyLineBreak records;
    in
    {
      expr = {
        agree = walked == scanned;
        found = builtins.length walked;
      };
      expected = {
        agree = true;
        found = 4;
      };
    };

  # The spelling and not the literal: the duration type admits any
  # concatenation, so zero has as many spellings as there are unit suffixes to
  # write it with, and a list of literals is what the next one is left out of.
  testTheZeroDurationPredicateReadsEverySpelling = {
    expr = map korora.domains.isZeroDuration [
      "0"
      "0s"
      "00min"
      "0s0min"
      "1s"
      "0s1s"
    ];
    expected = [
      true
      true
      true
      true
      false
      false
    ];
  };

  # `domains` is looked up by korora type name to say what a value outside an
  # enumeration may take, and the field-type row hands what it finds to
  # `quoteList`. The zero-duration predicate rides that table because a
  # top-level key of its own costs one copied value per plan, so an entry of it
  # that is not a list has to be keyed by a name no atom carries: naming a
  # future atom `isZeroDuration` would make the row quote a function, which is
  # a type error no `tryEval` catches and no row reports.
  testEveryDomainThatIsNotAListIsKeyedByNoAtom = {
    expr = filter (name: !builtins.isList korora.domains.${name} && korora ? ${name}) (
      attrNames korora.domains
    );
    expected = [ ];
  };

  testAUnitThatSaysHowItIsProbed =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
        units.plain.command = "/bin/plain";
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        probed = entry.units.web;
        silent = attrNames entry.units.plain;
      };
      expected = {
        rows = [ ];
        probed = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
        silent = [ "command" ];
      };
    };

  # Half a pair the reading refused is a missing half, so the type row is joined
  # by the pair row and the record keeps neither field: a bound with no command
  # is the one state a realiser cannot render.
  testAProbeWhoseValueIsNotACommand =
    let
      command = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = 5;
          probeTimeout = "30s";
        };
      });
      bound = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "soon";
        };
      });
    in
    {
      expr = {
        commandRows = rowIds command;
        namesProbe = hasInfix "`probe`" (messageById "unit-field-type-mismatch" command);
        namesString = hasInfix "string" (evidenceById "unit-field-type-mismatch" command);
        commandRecorded = attrNames (entryOf command "one").units.web;
        boundRows = rowIds bound;
        namesTheBound = hasInfix "`probeTimeout`" (messageById "unit-field-type-mismatch" bound);
        namesDuration = hasInfix "duration" (evidenceById "unit-field-type-mismatch" bound);
        boundRecorded = attrNames (entryOf bound "one").units.web;
      };
      expected = {
        commandRows = [
          "unit-field-type-mismatch"
          "unit-probe-timeout-without-probe"
        ];
        namesProbe = true;
        namesString = true;
        commandRecorded = [ "command" ];
        boundRows = [
          "unit-field-type-mismatch"
          "unit-probe-without-timeout"
        ];
        namesTheBound = true;
        namesDuration = true;
        boundRecorded = [ "command" ];
      };
    };

  testAProbeWithNoBound =
    let
      id = "unit-probe-without-timeout";
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (messageById id result)) [
          "the module of `only`"
          "unit `web`"
        ];
        saysWhatTheBoundIsFor = hasInfix "holding the activation open" (evidenceById id result);
        fields = attrNames entry.units.web;
      };
      expected = {
        rows = [ id ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        names = [
          true
          true
        ];
        saysWhatTheBoundIsFor = true;
        fields = [ "command" ];
      };
    };

  testABoundWithNoProbe =
    let
      id = "unit-probe-timeout-without-probe";
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probeTimeout = "30s";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById id result;
        names = map (needle: hasInfix needle (messageById id result)) [
          "the module of `only`"
          "unit `web`"
        ];
        fields = attrNames entry.units.web;
      };
      expected = {
        rows = [ id ];
        severity = "error";
        names = [
          true
          true
        ];
        fields = [ "command" ];
      };
    };

  testABoundThatSpellsNoBound =
    let
      id = "unit-probe-timeout-unbounded";
      probed =
        bound:
        placed [ "one" ] (_: {
          units.web = {
            command = "/bin/web";
            probe = "/bin/web-ready";
            probeTimeout = bound;
          };
        });
      zero = probed "0min";
      second = probed "1s";
    in
    {
      expr = {
        rows = rowIds zero;
        names = map (needle: hasInfix needle (messageById id zero)) [
          "the module of `only`"
          "unit `web`"
          "`0min`"
        ];
        fields = attrNames (entryOf zero "one").units.web;
        aSecondIsNoRow = rowIds second;
        aSecondIsRecorded = (entryOf second "one").units.web.probeTimeout;
      };
      expected = {
        rows = [ id ];
        names = [
          true
          true
          true
        ];
        fields = [ "command" ];
        aSecondIsNoRow = [ ];
        aSecondIsRecorded = "1s";
      };
    };

  testAOneShotUnitAskingToBeProbed =
    let
      id = "unit-probe-on-one-shot";
      result = placed [ "one" ] (_: {
        units.job = {
          command = "/bin/job";
          oneShot = true;
          probe = "/bin/job-ready";
          probeTimeout = "30s";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        names = map (needle: hasInfix needle (messageById id result)) [
          "the module of `only`"
          "unit `job`"
        ];
        fields = attrNames entry.units.job;
      };
      expected = {
        rows = [ id ];
        names = [
          true
          true
        ];
        fields = [
          "command"
          "oneShot"
        ];
      };
    };

  testAScheduledUnitAskingToBeProbed =
    let
      id = "unit-probe-on-scheduled";
      result = placed [ "one" ] (_: {
        units.nightly = {
          command = "/bin/nightly";
          schedule = "daily";
          probe = "/bin/nightly-ready";
          probeTimeout = "30s";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        names = map (needle: hasInfix needle (messageById id result)) [
          "the module of `only`"
          "unit `nightly`"
        ];
        fields = attrNames entry.units.nightly;
      };
      expected = {
        rows = [ id ];
        names = [
          true
          true
        ];
        fields = [
          "command"
          "schedule"
        ];
      };
    };

  # One row for the entry and not one per unit: the file a realiser derives to
  # ask whether the entry is serving is the entry's, so the question is asked
  # once over the unit set and the row names both statements.
  testTwoUnitsOfOneEntryDeclaringAProbe =
    let
      id = "unit-probe-declared-twice";
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
        units.api = {
          command = "/bin/api";
          probe = "/bin/api-ready";
          probeTimeout = "30s";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        count = countById id result;
        subjects = subjectsById id result;
        names = map (needle: hasInfix needle (messageById id result)) [
          "the module of `only`"
          "`api`"
          "`web`"
        ];
        units = attrNames entry.units;
        api = attrNames entry.units.api;
        web = attrNames entry.units.web;
      };
      expected = {
        rows = [ id ];
        count = 1;
        subjects = [ "svc:only@one" ];
        names = [
          true
          true
          true
        ];
        units = [
          "api"
          "web"
        ];
        api = [ "command" ];
        web = [ "command" ];
      };
    };

  # The pair this change adds is a probe and a restart policy: one says whether
  # the service is serving while it runs and the other what happens after it
  # stops, so the four fields together are no row at all.
  testAProbedUnitThatIsAlsoRestartedOnFailure =
    let
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          restart = "on-failure";
          restartSec = "5s";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
        };
      });
      entry = entryOf result "one";
    in
    {
      expr = {
        rows = rowIds result;
        recorded = entry.units.web;
      };
      expected = {
        rows = [ ];
        recorded = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
          restart = "on-failure";
          restartSec = "5s";
        };
      };
    };

  # A repeat is a watchdog or a second schedule and a threshold is a retry
  # policy for a check, and the vocabulary carries neither, so each is the rule
  # about an unrecognised key rather than an exclusion of its own.
  testAProbeIntervalIsNotAVocabularyField =
    let
      id = "implementation-unknown-key";
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready";
          probeTimeout = "30s";
          probeInterval = "10s";
          probeFailures = 3;
        };
      });
      messages = map (r: r.message) (support.rowsById id result);
      names = needle: builtins.any (message: hasInfix needle message) messages;
    in
    {
      expr = {
        rows = rowIds result;
        namesBothKeys = [
          (names "`probeInterval`")
          (names "`probeFailures`")
        ];
        namesTheVocabulary = names "`probeTimeout`";
        recorded = attrNames (entryOf result "one").units.web;
      };
      expected = {
        rows = [
          id
          id
        ];
        namesBothKeys = [
          true
          true
        ];
        namesTheVocabulary = true;
        recorded = [
          "command"
          "probe"
          "probeTimeout"
        ];
      };
    };

  # The walk reads every string of the record at any depth, so a probe is
  # scanned by existing and the row names the field it sits at.
  testAProbeCarryingALineBreak =
    let
      id = "unit-value-newline";
      result = placed [ "one" ] (_: {
        units.web = {
          command = "/bin/web";
          probe = "/bin/web-ready\nExecStartPost=/bin/sh -c evil";
          probeTimeout = "30s";
        };
      });
      table = planner.render result.diagnostics;
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById id result;
        namesTheFieldPath = hasInfix "`probe`" (messageById id result);
        entryIsInThePlan = result.plan ? "svc:only@one";
        theTableCarriesNoDirectiveLine = hasInfix "\nExecStartPost" table;
        applicable = result.applicable;
      };
      expected = {
        rows = [ id ];
        subjects = [ "svc:only@one" ];
        namesTheFieldPath = true;
        entryIsInThePlan = true;
        theTableCarriesNoDirectiveLine = false;
        applicable = false;
      };
    };
}
