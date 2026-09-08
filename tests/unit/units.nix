# The typed unit vocabulary, the typed extensions a backend adds to it, the
# target a module learns its service manager from, and the record a
# configuration file gets.
#
# One test per scenario of specs/planner/unit-vocabulary/spec.md, named after
# that scenario.
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

  # A second extension declared in a second place with the same `name`, which
  # is what makes the identity rule assertable rather than described.
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

  # One member, placed on the machines given, whose implementation is the
  # attribute set the caller wrote.
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

  # The vocabulary's atom types, checked through korora's non-raising entry
  # point rather than through a plan.
  verifies = type: value: type.verify value == null;
in
{
  # Task 2.1. Four atom types the vocabulary needs and korora has no name for:
  # each accepts a well-formed value and rejects a malformed one.
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

  # A unit declaring a command and an environment records exactly those two
  # fields: a field it did not declare is absent rather than recorded as a null
  # or as a service manager's default.
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

  # An apply-and-exit unit: three fields a renderer can tell from a
  # long-running unit without reading its command.
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

  # A value failing its field's type is a row naming the module, the unit, the
  # field and the type, and the failing value is not recorded.
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
        # Two rows, one per field: the evidence read here is the table's, so
        # the type named is `timeout`'s and not the first row's.
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

  # Task 3.2. A reference is producible only by the module that declared the
  # unit it names, so a reference to a stranger's unit is a row and the
  # ordering is absent from the plan.
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

  # `requires` is a requirement and `after` is an ordering, so they are two
  # recorded fields and not one relation.
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

  # Task 3.3. A unit field is a key input: changing one unit's timeout moves
  # that entry's key and no other entry's.
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

  # Task 3.4 and the probe of task 1.1. Two units of one entry declaring
  # different values for one variable is two records and no row.
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

  # A variable both units agree on is recorded on both units and in the entry's
  # agreed environment, so one environment per service and one per unit are
  # both served by one plan.
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

  # One unit's environment changes and nothing else does: the entry is re-keyed
  # and its closure is untouched.
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

  # Task 2.3 and 4.1. A systemd extension applied on a systemd target records
  # its fields under that backend and produces no row.
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

  # A partial application is the ordinary case: an extension exists to set two
  # of thirty knobs, so the fields left unset are absent rather than defaulted.
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

  # A key the extension does not declare is a row naming the module, the unit,
  # the extension and the key, and it is not recorded.
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

  # A value failing its field's type is a row naming the field and the type.
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

  # Task 2.2. Two extensions declared in two files with one `name` are two
  # values: each unit's fields are checked against the extension its module
  # imported and neither against the other's.
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

  # Task 2.2. An extension whose field declares a key outside `{ type }` is a
  # row, and the excluded half of the dispatch keeps its own identifier.
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

  # Task 4.1. One module on two service managers: the portable fields agree and
  # the extension is recorded on the systemd entry only.
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

  # A member no placement selected has no target, consistently with its entry
  # carrying no machine and no closure.
  #
  # The absence is observed the way a module would notice it: the module raises
  # when the argument is there, so the unplaced member's own rows say whether
  # it was handed one. An unplaced entry records no units and no configuration
  # data, so there is nowhere else to read the answer from.
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

  # Task 4.2. The module forgets the conditional: the row fires naming both
  # backends and the fields are still recorded under the extension's own
  # backend, so a renderer refuses knowingly rather than dropping them.
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

  # A launchd extension on a launchd target is not a row, which is what makes
  # the row above about the backend rather than about systemd.
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

  # Task 5.1. A service manager's own stanza written directly on a unit is a
  # row naming the module, the unit, the key and the vocabulary.
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

  # A misspelling is a row rather than a silence, which is the failure mode the
  # declaration half already refuses.
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

  # An unrecognised key at the implementation's top level is the same row.
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

  # Task 5.2. Reading stays total: one unrecognised key produces exactly one
  # row, the second unit is recorded in full, and the entry is still in the
  # plan.
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

  # Task 5.3. A key colliding with a construct this subset excludes produces
  # that construct's exclusion row with its trigger, in preference to the
  # unknown-key row.
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

  # Task 6.1. A file copied out of the store records its path, its mode and its
  # reload set, and no digest over bytes the plan does not hold.
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

  # A recipe of public literals only: the plan records the list in order and a
  # content hash over the literals it holds.
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

  # Task 6.2. A recipe naming a generated secret's path records the fragments,
  # the reference and a hash over them, and no digest over assembled bytes.
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
        varsState.one.hostKey."key" = {
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
          { ref = "/run/vars/hostKey/key"; }
        ];
        structureHashIsAHash = true;
        bytesAnywhereInThePlan = false;
        rows = [ ];
      };
    };

  # Task 6.1. `reload` is what the module named and not every unit of the
  # entry, and a file naming no unit reloads none.
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

  # Both dispositions at once is a row naming the module and the file, and the
  # entry is still in the plan.
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

  # Neither disposition is the same row: a file that names no bytes at all is
  # not a file the plan can hand to a consumer.
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
