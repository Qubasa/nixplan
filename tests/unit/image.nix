{
  planner,
  support,
  imageSource,
  nixpkgsLib,
}:
let
  inherit (builtins)
    attrNames
    concatStringsSep
    elem
    elemAt
    filter
    genList
    isString
    length
    split
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

  # This layer realises nothing, so a configuration file the realiser assembles at
  # build time stands in as a store path keyed by its own bytes: two readings of
  # one recipe answer one path, and an edited recipe answers another, which is what
  # a real `writeText` does.
  assemble = name: text: "/nix/store/${planner.util.shortHash text}-${name}";

  reader = import (imageSource + "/read.nix") { inherit planner assemble; };

  # The builder over that reading, so a suite can read the shell scripts it
  # renders. Every derivation is answered by the same keyed fake path
  # `assemble` answers with, except a script, which is answered by its own text:
  # a script is a string this evaluation already holds and the derivation over
  # it carries nothing else. `nixpkgsLib` is the real one the build spends, so
  # what a test reads is what a machine runs.
  fakeDrv =
    name: text:
    let
      path = "/nix/store/${planner.util.shortHash text}-${name}";
    in
    {
      inherit name;
      outPath = path;
    };

  builderPkgs = {
    lib = nixpkgsLib;
    writeText = name: text: fakeDrv name text;
    writeTextFile = { name, text }: fakeDrv name text;
    writeShellScript = _name: text: text;
    runCommand =
      name: attrs: text:
      fakeDrv name text // attrs // (attrs.passthru or { });
    closureInfo = { rootPaths }: fakeDrv "closure-info" (toString rootPaths);
    squashfsTools = fakeDrv "squashfs-tools" "";
  };

  builder = import imageSource {
    inherit planner;
    inherit (builderPkgs) lib;
    pkgs = builderPkgs;
  };

  builtFrom =
    {
      profile ? "trusted",
      key ? "svc:only@one",
    }:
    result:
    builder.build {
      plan = result.plan;
      inherit key profile;
    };

  # The pieces of a script that sit between an odd and an even double quote,
  # which is where a value the renderer interpolated bare would be a `$(…)` the
  # machine runs.
  insideDoubleQuotes =
    text:
    let
      pieces = filter isString (split "\"" text);
    in
    map (i: elemAt pieces i) (filter (i: i - (i / 2) * 2 == 1) (genList (i: i) (length pieces)));

  namedInsideQuotes = needle: text: filter (piece: hasInfix needle piece) (insideDoubleQuotes text);

  occurrences = needle: text: length (nixpkgsLib.splitString needle text) - 1;

  # One entry with a staged configuration file, a reloading unit and a scheduled
  # one, built, so what these tests read is the script text a machine runs.
  staged =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              vars.hostKey.files."key".secrecy = "secret";
              impl =
                { vars, ... }:
                {
                  closure = [ borgbackup ];
                  units.only = {
                    command = "${borgbackup}/bin/borg serve";
                    reloadCommand = "${borgbackup}/bin/borg reload";
                  };
                  units.sweep = {
                    command = "${borgbackup}/bin/borg prune";
                    schedule = "daily";
                  };
                  configData."/etc/thing.conf" = {
                    mode = "0400";
                    reload = [ "only" ];
                    render = [
                      { text = "value = one\n"; }
                      { ref = vars.hostKey."key".path; }
                    ];
                  };
                };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
        varsState."svc:vars/hostKey@one"."key" = {
          present = true;
          content = "PRIVATE-KEY-BYTES";
        };
      };
      built = builtFrom { } result;
    in
    {
      inherit (built) attach detach check;
      inherit (built.image) staging;
      units = built.attachment.units;
      path = "/etc/thing.conf";
    };

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

  # A platform string no rule has reached: `image/read.nix` accepts
  # `target.system` on the sole condition that the record carries a `system`, so
  # a hand-written plan is where these bytes reach the attach script's own
  # messages. Inside double quotes a substitution needs no quote of its own,
  # which is why the closing one here is spare rather than load-bearing.
  hostileSystem = "x86_64-linux\"; $(id > /tmp/pwned); echo \"";

  hostile =
    let
      p = planned { } (_: {
        closure = [ borgbackup ];
        units.only.command = "${borgbackup}/bin/borg serve";
      });
      entry = p.plan.${p.key};
    in
    builder.build {
      inherit (p) key;
      profile = "trusted";
      plan = p.plan // {
        ${p.key} = entry // {
          target = entry.target // {
            system = entry.target.system // {
              system = hostileSystem;
            };
          };
        };
      };
    };

  # The denial reads the record rather than the secrecy, so a value the
  # deployment opened to an account is not refused for having been generated.

  shownTo =
    {
      profile,
      fileArgs ? { },
      unitArgs ? { },
    }:
    let
      result = planOf {
        instances.holder = {
          module = soleRoot {
            module = _: {
              vars.hostKey.files."key" = {
                secrecy = "secret";
              }
              // fileArgs;
              impl =
                { vars, ... }:
                {
                  closure = [ borgbackup ];
                  units.only = {
                    command = "${borgbackup}/bin/borg serve";
                    env.KEYFILE = vars.hostKey."key".path;
                  }
                  // unitArgs;
                };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
        varsState."holder:vars/hostKey@one"."key" = {
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

  groupedUnit = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      supplementaryGroups = {
        type = korora.listOf korora.string;
      };
    };
  };

  simple = _: {
    closure = [ borgbackup ];
    units.only.command = "${borgbackup}/bin/borg serve";
  };

  # One configuration file whose record the store cannot carry, shown to a unit
  # the caller gives an account, a group, or neither: a confining profile puts a
  # unit that declares no account on a transient one.
  shownAt =
    {
      owner ? null,
      group ? null,
      mode ? "0400",
      groups ? [ ],
      asUser ? "app",
    }:
    _: {
      closure = [ borgbackup ];
      configData."/etc/thing.conf" = {
        inherit mode;
        reload = [ "only" ];
        render = [ { text = "value\n"; } ];
      }
      // (if owner == null then { } else { inherit owner; })
      // (if group == null then { } else { inherit group; });
      units.only = {
        command = "${borgbackup}/bin/borg serve";
      }
      // (if asUser == null then { } else { user = asUser; })
      // (
        if groups == [ ] then
          { }
        else
          {
            extends = [
              {
                extension = groupedUnit;
                values.supplementaryGroups = groups;
              }
            ];
          }
      );
    };

  # The same file whose record defaults to the one a store object carries, so a
  # caller states only the field it wants to move off it.
  carriedFile =
    {
      owner ? null,
      group ? null,
      mode ? "0444",
      source ? null,
    }:
    _: {
      closure = [ borgbackup ];
      configData."/etc/thing.conf" = {
        inherit mode;
        reload = [ "only" ];
      }
      // (if source == null then { render = [ { text = "value\n"; } ]; } else { inherit source; })
      // (if owner == null then { } else { inherit owner; })
      // (if group == null then { } else { inherit group; });
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
                  vars.hostKey.files."key".secrecy = "secret";
                  impl =
                    { vars, ... }:
                    {
                      closure = [ borgbackup ];
                      units.only = {
                        command = "${borgbackup}/bin/borg serve";
                        inherit timeout;
                      };
                      # A recipe naming a delivered path, so its bytes are
                      # assembled on the machine and never enter the image.
                      configData."/etc/thing.conf" = {
                        mode = "0400";
                        reload = [ "only" ];
                        render = [
                          { text = "value = ${text}\n"; }
                          { ref = vars.hostKey."key".path; }
                        ];
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
          varsState."svc:vars/hostKey@one"."key" = {
            present = true;
            content = "PRIVATE-KEY-BYTES";
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
      incomplete = planOf {
        machines.bare = {
          address = "bare.example";
          tags = [ ];
        };
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = _: {
                units.only.command = "/bin/true";
              };
            };
          };
          placement.every.only.machines = [ "bare" ];
        };
      };
    in
    {
      expr = {
        unplacedRaises = raises read;
        unknownEntryRaises = raises unknownKey;
        entryFields = attrNames result.plan."svc:only";
        # The fact the entry does not carry is a row of the planner's first: a
        # target with no platform and no service manager is reported there, and
        # the raise below it is what a direct caller of this file receives.
        theRowAboveTheRaise = support.rowIds incomplete;
        rowSeverity = support.severityById "machine-target-incomplete" incomplete;
      };
      expected = {
        unplacedRaises = true;
        unknownEntryRaises = true;
        theRowAboveTheRaise = [ "machine-target-incomplete" ];
        rowSeverity = "error";
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
        webCarriesItsOwn = hasInfix "Environment=\"ROLE=web\"" web;
        webCarriesTheOther = hasInfix "Environment=\"ROLE=db\"" web;
        dbCarriesItsOwn = hasInfix "Environment=\"ROLE=db\"" db;
        dbCarriesTheOther = hasInfix "Environment=\"ROLE=web\"" db;
      };
      expected = {
        webCarriesItsOwn = true;
        webCarriesTheOther = false;
        dbCarriesItsOwn = true;
        dbCarriesTheOther = false;
      };
    };

  # The e2e run that found this: a public export whose value is
  # `PLANNER-E2E-CA <hex>` reached the unit as two assignments, and the consumer
  # read back the first word.
  testAnEnvironmentValueCarriesASpace =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.web = {
          command = "${borgbackup}/bin/borg serve";
          env = {
            CERT = "PLANNER-E2E-CA 03dc21046074f1";
            QUOTED = "say \"hi\" c:\\path";
          };
        };
      });
      text = reader.renderUnit image "web";
      envLines = builtins.filter (l: support.hasInfix "Environment=" l) (support.lines text);
    in
    {
      expr = envLines;
      expected = [
        "Environment=\"CERT=PLANNER-E2E-CA 03dc21046074f1\""
        "Environment=\"QUOTED=say \\\"hi\\\" c:\\\\path\""
      ];
    };

  testAnEnvironmentValueCarriesANewline =
    let
      withValue =
        value:
        readOf { } (_: {
          closure = [ borgbackup ];
          units.web = {
            command = "${borgbackup}/bin/borg serve";
            env.PEM = value;
          };
        });
      plannedWith =
        value:
        planned { } (_: {
          closure = [ borgbackup ];
          units.web = {
            command = "${borgbackup}/bin/borg serve";
            env.PEM = value;
          };
        });
      broken = (plannedWith "-----BEGIN-----\nbytes\n-----END-----").result;
      whole = (plannedWith "-----BEGIN----- bytes -----END-----").result;
    in
    {
      expr = {
        refused = raises (withValue "-----BEGIN-----\nbytes\n-----END-----");
        oneLineOfTheSameBytesBuilds = raises (withValue "-----BEGIN----- bytes -----END-----");
        # The planner reports the same condition first, and says which field.
        theRowAboveTheRaise = support.rowIds broken;
        namesTheVariable = hasInfix "`env.PEM`" (support.messageById "unit-value-newline" broken);
        oneLineIsNoRow = support.rowIds whole;
      };
      expected = {
        refused = true;
        oneLineOfTheSameBytesBuilds = false;
        theRowAboveTheRaise = [ "unit-value-newline" ];
        namesTheVariable = true;
        oneLineIsNoRow = [ ];
      };
    };

  testACommandCarriesANewline =
    let
      withCommand =
        value:
        readOf { } (_: {
          closure = [ borgbackup ];
          units.web.command = value;
        });
      plannedWith =
        value:
        planned { } (_: {
          closure = [ borgbackup ];
          units.web.command = value;
        });
      smuggled = "${borgbackup}/bin/borg serve\nUser=root";
      broken = (plannedWith smuggled).result;
    in
    {
      expr = {
        refused = raises (withCommand smuggled);
        # The refusal is what stops the directive the module wrote from being a
        # line of the file, so the rendering is the thing that has to raise.
        noSecondDirective = raises (reader.renderUnit (withCommand smuggled) "web");
        oneLineBuilds = raises (withCommand "${borgbackup}/bin/borg serve --foo");
        theRowAboveTheRaise = support.rowIds broken;
        namesTheUnit = hasInfix "`web`" (support.messageById "unit-value-newline" broken);
        namesTheField = hasInfix "`command`" (support.messageById "unit-value-newline" broken);
      };
      expected = {
        refused = true;
        noSecondDirective = true;
        oneLineBuilds = false;
        theRowAboveTheRaise = [ "unit-value-newline" ];
        namesTheUnit = true;
        namesTheField = true;
      };
    };

  testAnEnvironmentKeyCarriesANewline =
    let
      withKey =
        key:
        readOf { } (_: {
          closure = [ borgbackup ];
          units.say = {
            command = "${borgbackup}/bin/borg serve";
            env.${key} = "x";
          };
        });
      plannedWith =
        key:
        planned { } (_: {
          closure = [ borgbackup ];
          units.say = {
            command = "${borgbackup}/bin/borg serve";
            env.${key} = "x";
          };
        });
      smuggled = "A\nExecStartPost=/bin/sh -c evil\n#";
      broken = (plannedWith smuggled).result;
    in
    {
      expr = {
        refused = raises (withKey smuggled);
        # An environment key is the left half of one quoted assignment, so a
        # break in it is a directive line of its own the moment it is rendered.
        noSecondDirective = raises (reader.renderUnit (withKey smuggled) "say");
        oneKeyBuilds = raises (withKey "TOKEN");
        theRowAboveTheRaise = support.rowIds broken;
      };
      expected = {
        refused = true;
        noSecondDirective = true;
        oneKeyBuilds = false;
        theRowAboveTheRaise = [ "unit-value-newline" ];
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
        directiveNames = 17;
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
          varsState."holder:vars/hostKey@one"."key" = {
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
        "/run/vars/holder/hostKey/key"
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
        hostPaths = [ "/run/vars/holder/hostKey/key" ];
        kinds = [ "generated-file" ];
        bytesAnywhere = false;
        bakingItInRaises = true;
      };
    };

  testAnUndeployedValueIsShownAtNoPath =
    let
      result = planOf {
        instances.holder = {
          module = soleRoot {
            module = _: {
              vars = {
                root = {
                  deploy = false;
                  files."key".secrecy = "secret";
                };
                token = {
                  reads = [ "root" ];
                  files."secret".secrecy = "secret";
                };
              };
              impl =
                { vars, ... }:
                {
                  closure = [ borgbackup ];
                  units.only = {
                    command = "${borgbackup}/bin/borg serve";
                    env.KEYFILE = vars.token."secret".path;
                  };
                };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
        varsState = {
          "holder:vars/root@one"."key".present = true;
          "holder:vars/token@one"."secret".present = true;
        };
      };
      image = reader.read {
        plan = result.plan;
        key = "holder:only@one";
        profile = "trusted";
      };
      unit = reader.renderUnit image "only";
    in
    {
      expr = {
        rows = map (row: row.id) result.diagnostics;
        # The undeployed value is on no machine, so the entry that owns it is shown
        # no path for it: a bind mount of a path nothing delivers fails the unit at
        # NAMESPACE, which names neither the value nor the declaration.
        hostPaths = map (p: p.path) (reader.attachment image).hostPaths;
        boundInTheUnit = hasInfix "/run/vars/holder/token/secret" unit;
        undeployedBound = hasInfix "/run/vars/holder/root/key" unit;
        # The plan still records the path, which is what lets a site that opens it
        # be reported rather than silently mounted.
        stillInThePlan = result.plan."holder:only@one".vars.root.files."key".path;
      };
      expected = {
        rows = [ ];
        hostPaths = [ "/run/vars/holder/token/secret" ];
        boundInTheUnit = true;
        undeployedBound = false;
        stillInThePlan = "/run/vars/holder/root/key";
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
        varsState."holder:vars/hostKey@one"."key" = {
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
          "/run/vars/holder/hostKey/key"
        ];
        staged = [
          "/run/portable-planner/holder-only/files/etc/agent.conf"
          "/run/vars/holder/hostKey/key"
        ];
        dispositions = [
          "reference"
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
            varsState."holder:vars/hostKey@one"."key" = {
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

  testAUnitThatIsRestartedOnFailure =
    let
      withPolicy = readOf { } (_: {
        closure = [ borgbackup ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          restart = "on-failure";
          restartSec = "5s";
        };
      });
      text = reader.renderUnit withPolicy "only";
    in
    {
      expr = {
        policy = hasInfix "Restart=on-failure" text;
        delay = hasInfix "RestartSec=5s" text;
        digestMoved = withPolicy.version != (readOf { } simple).version;
      };
      expected = {
        policy = true;
        delay = true;
        digestMoved = true;
      };
    };

  testAUnitThatDeclaredNoPolicy =
    let
      text = reader.renderUnit (readOf { } simple) "only";
    in
    {
      expr = {
        policy = hasInfix "Restart=" text;
        delay = hasInfix "RestartSec=" text;
      };
      expected = {
        policy = false;
        delay = false;
      };
    };

  testAFileCopiedFromAStorePathIsNotStaged =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.only.command = "${borgbackup}/bin/borg serve";
        configData."/etc/thing.conf" = {
          mode = "0444";
          reload = [ "only" ];
          source = "${borgbackup}/share/thing.conf";
        };
      });
      shown = builtins.head image.hostPaths;
    in
    {
      expr = {
        disposition = shown.disposition;
        from = shown.from;
        boundInTheUnit = hasInfix "BindReadOnlyPaths=${borgbackup}/share/thing.conf:/etc/thing.conf" (
          reader.renderUnit image "only"
        );
        assembledOnTheMachine = filter (f: f.disposition == "reference") image.configFiles;
        inTheClosure = elem borgbackup image.closure;
      };
      expected = {
        disposition = "source";
        from = "${borgbackup}/share/thing.conf";
        boundInTheUnit = true;
        assembledOnTheMachine = [ ];
        inTheClosure = true;
      };
    };

  testAFileAssembledFromLiteralsIsAssembledAtBuildTime =
    let
      literal = text: _: {
        closure = [ borgbackup ];
        units.only.command = "${borgbackup}/bin/borg serve";
        configData."/etc/thing.conf" = {
          mode = "0444";
          reload = [ "only" ];
          render = [ { text = "value = ${text}\n"; } ];
        };
      };
      image = readOf { } (literal "before");
      edited = readOf { } (literal "after");
      shown = builtins.head image.hostPaths;
    in
    {
      expr = {
        disposition = shown.disposition;
        fromTheStore = hasInfix "/nix/store/" shown.from;
        boundInTheUnit = hasInfix "BindReadOnlyPaths=${shown.from}:/etc/thing.conf" (
          reader.renderUnit image "only"
        );
        assembledOnTheMachine = filter (f: f.disposition == "reference") image.configFiles;
        # The bytes are in the image now, so an edit of them is a new artifact.
        editMovesTheDigest = image.version != edited.version;
      };
      expected = {
        disposition = "literal";
        fromTheStore = true;
        boundInTheUnit = true;
        assembledOnTheMachine = [ ];
        editMovesTheDigest = true;
      };
    };

  testAGroupReadableValueUnderAConfiningProfile = {
    expr =
      map
        (
          profile:
          raises (shownTo {
            inherit profile;
            fileArgs = {
              group = "readers";
              mode = "0640";
            };
            # No `user`: a confining profile denies a static one, and the group is
            # what admits the transient account the profile imposes.
            unitArgs.extends = [
              {
                extension = groupedUnit;
                values.supplementaryGroups = [ "readers" ];
              }
            ];
          })
        )
        [
          "default"
          "nonetwork"
          "strict"
        ];
    expected = [
      false
      false
      false
    ];
  };

  testARootOnlyValueUnderTheUnconfinedProfile = {
    expr = raises (shownTo {
      profile = "trusted";
    });
    expected = false;
  };

  testASecretIsNoLongerDeniedForBeingSecret =
    let
      # Two secret files under one profile, differing only in mode: the denial
      # follows the record and the secrecy decides nothing.
      open = shownTo {
        profile = "default";
        fileArgs.mode = "0444";
      };
      closed = shownTo {
        profile = "default";
        fileArgs.mode = "0400";
      };
    in
    {
      expr = [
        (raises open)
        (raises closed)
      ];
      expected = [
        false
        true
      ];
    };

  testAUnitDeclaringASupplementaryGroup =
    let
      image = shownTo {
        profile = "trusted";
        unitArgs.extends = [
          {
            extension = groupedUnit;
            values.supplementaryGroups = [ "readers" ];
          }
        ];
      };
      rendered = reader.renderUnit image "only";
    in
    {
      expr = {
        directive = hasInfix "SupplementaryGroups=readers" rendered;
        inTheTable = reader.systemdDirectives.supplementaryGroups;
      };
      expected = {
        directive = true;
        inTheTable = "SupplementaryGroups";
      };
    };

  testAUnitDeclaringNone =
    let
      rendered = reader.renderUnit (shownTo { profile = "trusted"; }) "only";
    in
    {
      expr = hasInfix "SupplementaryGroups" rendered;
      expected = false;
    };

  testAUnitDeclaringADirectoryRendersBothDirectives =
    let
      declaring = readOf { } (_: {
        closure = [ borgbackup ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          stateDirectory = [ "myapp" ];
          stateDirectoryMode = "0700";
        };
      });
      bare = readOf { } simple;
    in
    {
      expr = {
        directory = hasInfix "StateDirectory=myapp" (reader.renderUnit declaring "only");
        mode = hasInfix "StateDirectoryMode=0700" (reader.renderUnit declaring "only");
        inTheTable = [
          reader.unitDirectives.stateDirectory
          reader.unitDirectives.stateDirectoryMode
        ];
        digestMoved = declaring.version != bare.version;
      };
      expected = {
        directory = true;
        mode = true;
        inTheTable = [
          "StateDirectory"
          "StateDirectoryMode"
        ];
        digestMoved = true;
      };
    };

  testAConditionRenderedWithThePolarityStated =
    let
      conditioned =
        field:
        reader.renderUnit (readOf { } (_: {
          closure = [ borgbackup ];
          units.only = {
            command = "${borgbackup}/bin/borg serve";
            ${field} = "/var/lib/myapp/VERSION";
          };
        })) "only";
      absent = conditioned "startIfPathAbsent";
      present = conditioned "startIfPathPresent";
    in
    {
      expr = {
        negative = hasInfix "ConditionPathExists=!/var/lib/myapp/VERSION" absent;
        positive = hasInfix "ConditionPathExists=/var/lib/myapp/VERSION" present;
        # A condition is a [Unit] fact, so it is above the [Service] header.
        inTheUnitSection = hasInfix "ConditionPathExists=!/var/lib/myapp/VERSION\n\n[Service]" absent;
        theOtherPolarityIsNotRendered = hasInfix "=!" present;
      };
      expected = {
        negative = true;
        positive = true;
        inTheUnitSection = true;
        theOtherPolarityIsNotRendered = false;
      };
    };

  # A vocabulary field is producible by a deployment and a directive table that
  # does not name it is the builder's own defect, which is why the refusal keeps
  # its recorded account rather than claiming a row above it.
  testAVocabularyFieldWithNoDirectiveFailsTheBuild =
    let
      # A plan is data, so a field no table names is written into a record
      # rather than declared: no deployment can produce one, which is the whole
      # reason the refusal keeps its account instead of claiming a row.
      recordCarrying =
        field:
        let
          p = planned { } (_: {
            closure = [ borgbackup ];
            units.only = {
              command = "${borgbackup}/bin/borg serve";
              stateDirectory = [ "myapp" ];
            };
          });
          entry = p.plan.${p.key};
        in
        p.plan
        // {
          ${p.key} = entry // {
            units.only = removeAttrs entry.units.only [ "stateDirectory" ] // {
              ${field} = [ "myapp" ];
            };
          };
        };
      readAs =
        plan:
        reader.read {
          inherit plan;
          key = "svc:only@one";
          profile = "trusted";
        };
    in
    {
      expr = {
        named = raises (readAs (recordCarrying "stateDirectory"));
        unnamed = raises (readAs (recordCarrying "stateDirectoryQuota"));
        directiveNames = length (attrNames reader.unitDirectives);
        accounted = reader.accounts.unitFieldUnrendered.id;
        because = hasInfix "defect of the builder" reader.accounts.unitFieldUnrendered.because;
      };
      expected = {
        named = false;
        unnamed = true;
        directiveNames = 22;
        accounted = null;
        because = true;
      };
    };

  testAConfigurationFileOnlyRootMayReadUnderAConfiningProfile =
    let
      denials =
        profile:
        filter (d: d ? path) (
          reader.denials {
            entry = (planned { } (shownAt { })).plan."svc:only@one";
            inherit profile;
          }
        );
      denied = builtins.head (denials "strict");
    in
    {
      expr = {
        count = length (denials "strict");
        inherit (denied)
          unit
          path
          record
          account
          access
          ;
        refused = raises (readOf { profile = "strict"; } (shownAt { }));
      };
      expected = {
        count = 1;
        unit = "only";
        path = "/etc/thing.conf";
        record = "root:root at mode 0400";
        account = "app";
        access = "a host file only root may read";
        refused = true;
      };
    };

  testAGroupReadableConfigurationFileUnderAConfiningProfile =
    let
      # The unit declares no account, which a confining profile puts on a
      # transient one, and the group is what admits it.
      grouped = shownAt {
        group = "app";
        mode = "0440";
        groups = [ "app" ];
        asUser = null;
      };
    in
    {
      expr = {
        denials = reader.denials {
          entry = (planned { } grouped).plan."svc:only@one";
          profile = "strict";
        };
        built = raises (readOf { profile = "strict"; } grouped);
      };
      expected = {
        denials = [ ];
        built = false;
      };
    };

  testAConfigurationFileUnderTheUnconfinedProfile = {
    expr = {
      denials = reader.denials {
        entry = (planned { } (shownAt { })).plan."svc:only@one";
        profile = "trusted";
      };
      built = raises (readOf { profile = "trusted"; } (shownAt { }));
    };
    expected = {
      denials = [ ];
      built = false;
    };
  };

  testAFileWhoseRecordTheStoreCarriesIsShownFromTheStore =
    let
      fromLiterals = readOf { } (carriedFile { });
      fromSource = readOf { } (carriedFile {
        source = "${borgbackup}/share/thing.conf";
      });
      shown = image: builtins.head (filter (p: p.kind == "configuration-file") image.hostPaths);
    in
    {
      expr = {
        record = [
          reader.storeRecord.owner
          reader.storeRecord.group
          reader.storeRecord.mode
        ];
        literalIsAStorePath = hasInfix "/nix/store/" (shown fromLiterals).from;
        sourceIsItsOwnPath = (shown fromSource).from;
        neitherIsInstalled = [
          (shown fromLiterals).install
          (shown fromSource).install
        ];
      };
      expected = {
        record = [
          "root"
          "root"
          "0444"
        ];
        literalIsAStorePath = true;
        sourceIsItsOwnPath = "${borgbackup}/share/thing.conf";
        neitherIsInstalled = [
          false
          false
        ];
      };
    };

  testAFileStatingAnOwnershipIsInstalledOnTheHost =
    let
      image = readOf { } (carriedFile {
        owner = "postgres";
        group = "postgres";
      });
      shown = builtins.head (filter (p: p.kind == "configuration-file") image.hostPaths);
      file = builtins.head image.configFiles;
    in
    {
      expr = {
        inherit (shown)
          install
          owner
          group
          mode
          ;
        from = shown.from;
        # The bytes still travel with the artifact: a literal recipe is a store
        # object the closure carries, and the script installs from it.
        recipeIsStillLiteral = file.disposition;
        bound = hasInfix "BindReadOnlyPaths=/run/portable-planner/svc-only/files/etc/thing.conf:/etc/thing.conf" (
          reader.renderUnit image "only"
        );
      };
      expected = {
        install = true;
        owner = "postgres";
        group = "postgres";
        mode = "0444";
        from = "/run/portable-planner/svc-only/files/etc/thing.conf";
        recipeIsStillLiteral = "literal";
        bound = true;
      };
    };

  testAFileStatingAModeTheStoreCannotCarryIsInstalledOnTheHost =
    let
      image = readOf { } (carriedFile {
        mode = "0600";
      });
      shown = builtins.head (filter (p: p.kind == "configuration-file") image.hostPaths);
    in
    {
      expr = {
        inherit (shown) install mode;
        from = shown.from;
        isNotAStorePath = hasInfix "/nix/store/" shown.from;
      };
      expected = {
        install = true;
        mode = "0600";
        from = "/run/portable-planner/svc-only/files/etc/thing.conf";
        isNotAStorePath = false;
      };
    };

  testAReferencedRecipeIsInstalledAtTheRecordItStates =
    let
      image = rebuilt.imageOf rebuilt.base rebuilt.key;
      shown = builtins.head (filter (p: p.kind == "configuration-file") image.hostPaths);
    in
    {
      expr = {
        inherit (shown)
          install
          owner
          group
          mode
          disposition
          ;
        needs = shown.needs;
        from = shown.from;
      };
      expected = {
        install = true;
        owner = "root";
        group = "root";
        mode = "0400";
        disposition = "reference";
        needs = "/run/vars/svc/hostKey/key";
        from = "/run/portable-planner/svc-only/files/etc/thing.conf";
      };
    };

  # Every byte of one installed file passes through paths the unit is not shown,
  # all three inside the staging directory detaching removes, so a run that
  # stopped part way left nothing at the path an account could open.
  testAnInterruptedInstallLeavesNoFileAtAWiderRecord =
    let
      image = readOf { } (carriedFile {
        mode = "0600";
      });
      file = builtins.head image.configFiles;
      shown = builtins.head (filter (p: p.kind == "configuration-file") image.hostPaths);
    in
    {
      expr = {
        shownIsStaged = shown.from == file.staged;
        distinct = length (
          planner.util.uniqueStrings [
            file.staged
            file.assembling
            file.installing
          ]
        );
        underTheStaging = map (p: hasInfix image.staging p) [
          file.staged
          file.assembling
          file.installing
        ];
      };
      expected = {
        shownIsStaged = true;
        distinct = 3;
        underTheStaging = [
          true
          true
          true
        ];
      };
    };

  testANameTheRuleAdmitsBuilds =
    let
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units."borg-repo.v2" = {
          command = "${borgbackup}/bin/borg serve";
          schedule = "daily";
        };
      });
      files = [
        image.units."borg-repo.v2".file
        image.units."borg-repo.v2".timer
      ];
    in
    {
      expr = {
        read = raises image;
        theNameIsAdmitted = reader.acceptsName image.name;
        theFilesAreAdmitted = map (file: reader.acceptsUnit image.name file) files;
        theRenderedNames = files;
        # Every derived name this repository already carries.
        inTheTree = map reader.acceptsName [
          "vault-repo-server"
          "watch-file"
          "mirror-copy"
        ];
      };
      expected = {
        read = false;
        theNameIsAdmitted = true;
        theFilesAreAdmitted = [
          true
          true
        ];
        theRenderedNames = [
          "svc-only-borg-repo.v2.service"
          "svc-only-borg-repo.v2.timer"
        ];
        inTheTree = [
          true
          true
          true
        ];
      };
    };

  testEveryPathAGeneratedScriptNamesIsEscaped = {
    expr = {
      # The scripts do name it, so the scan below is not a scan of nothing.
      theAttachNamesIt = hasInfix staged.path staged.attach;
      theCheckNamesIt = hasInfix staged.path staged.check;
      bareInTheAttach = namedInsideQuotes staged.path staged.attach;
      bareInTheCheck = namedInsideQuotes staged.path staged.check;
      bareInTheDetach = namedInsideQuotes staged.path staged.detach;
    };
    expected = {
      theAttachNamesIt = true;
      theCheckNamesIt = true;
      bareInTheAttach = [ ];
      bareInTheCheck = [ ];
      bareInTheDetach = [ ];
    };
  };

  testAValueNoRuleReachedIsOneWordInAMessage =
    let
      quotes = occurrences "\"" hostile.attach;
    in
    {
      expr = {
        # The comparison's argument and the message's word, so the counts below
        # are counts of something.
        namings = occurrences hostileSystem hostile.attach;
        asOneWord = occurrences "'${hostileSystem}'" hostile.attach;
        # The message closes its double-quoted string around the word, which is
        # what makes the substitution inside it bytes rather than a command.
        closedAroundIt = occurrences "\"'${hostileSystem}'\"" hostile.attach;
        quotesPair = quotes - (quotes / 2) * 2 == 0;
      };
      expected = {
        namings = 2;
        asOneWord = 2;
        closedAroundIt = 1;
        quotesPair = true;
      };
    };

  testAUnitListIsEscapedWordByWord =
    let
      wordByWord = concatStringsSep " " (map (unit: "'${unit}'") staged.units);
      joined = concatStringsSep " " staged.units;
    in
    {
      expr = {
        theListIsMoreThanOneWord = length staged.units > 1;
        stopped = hasInfix "systemctl stop ${wordByWord}" staged.attach;
        started = hasInfix "systemctl start ${wordByWord}" staged.attach;
        detached = hasInfix "systemctl stop ${wordByWord}" staged.detach;
        joinedInTheAttach = hasInfix "systemctl stop ${joined}" staged.attach;
        joinedInTheDetach = hasInfix "systemctl stop ${joined}" staged.detach;
      };
      expected = {
        theListIsMoreThanOneWord = true;
        stopped = true;
        started = true;
        detached = true;
        joinedInTheAttach = false;
        joinedInTheDetach = false;
      };
    };

  testTheStagingDirectoryIsTraversableAndNotListable =
    let
      created = filter (line: hasInfix "install -d " line) (support.lines staged.attach);
    in
    {
      expr = {
        # One line creates the whole tree, so no component is left at the umask
        # of whoever ran the script.
        creating = length created;
        atThatMode = map (line: hasInfix "install -d -m 0711 " line) created;
        theEntrysOwnDirectory = map (line: hasInfix staged.staging line) created;
        theFilesDirectory = map (line: hasInfix "${staged.staging}/files/etc" line) created;
        nothingWidensIt = filter (line: hasInfix "0755" line) (support.lines staged.attach);
        # The file's own mode is still the declaration's, set after the 0600
        # the install creates it at.
        theFileKeepsItsMode = hasInfix "chmod 0400 " staged.attach;
      };
      expected = {
        creating = 1;
        atThatMode = [ true ];
        theEntrysOwnDirectory = [ true ];
        theFilesDirectory = [ true ];
        nothingWidensIt = [ ];
        theFileKeepsItsMode = true;
      };
    };
}
