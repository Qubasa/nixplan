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
    ;

  inherit (support)
    assemble
    hasInfix
    korora
    laptopMachines
    planOf
    raises
    soleRoot
    systemdService
    ;

  inherit (support.worked) openssh borgbackup;

  realiser = support.realiser {
    inherit imageSource assemble;
  };

  inherit (realiser) planned;

  reader = realiser.imageReader;

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
    cryptsetup = fakeDrv "cryptsetup" "";
    openssl = fakeDrv "openssl" "";
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
      result = support.valuePlan {
        unitArgs.reloadCommand = "${borgbackup}/bin/borg reload";
        extraUnits.sweep = {
          command = "${borgbackup}/bin/borg prune";
          schedule = "daily";
        };
        extra = vars: {
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
      built = builtFrom { } result;
    in
    {
      inherit (built) attach detach check;
      inherit (built.image) staging;
      units = built.attachment.units;
      path = "/etc/thing.conf";
    };

  # The values an entry is shown, which is what every reading about one is
  # handed: the entry's own generated files and the ones its declared reads
  # name, one record per path.
  shownValues =
    plan: key:
    (reader.valuesOf {
      index = reader.valueIndex plan;
      inherit key;
      entry = plan.${key};
    }).generated;

  denialsFor =
    {
      plan,
      profile,
      key ? "svc:only@one",
    }:
    reader.denials {
      entry = plan.${key};
      inherit profile;
      generated = shownValues plan key;
    };

  # The cross-entry read the shared harness builds, read as an image: one entry
  # generates the value and publishes it, the other declares a read of that
  # export and names the value's path in its own unit.
  inherit (support)
    credential
    credentials
    peerHolder
    ;

  peerRead = support.peerValuePlan;

  peerPath = support.peerValuePath;

  peerImage =
    {
      key ? "app:only@one",
      profile ? "trusted",
    }:
    result:
    reader.read {
      inherit (result) plan;
      inherit key profile;
    };

  peerBuild =
    {
      key ? "app:only@one",
      profile ? "trusted",
    }:
    result:
    builder.build {
      inherit (result) plan;
      inherit key profile;
    };

  # A deployed value of a third instance, hand-written: the reading is handed a
  # plan, so a value no statement of the entry reaches is a record it meets and
  # has to answer nothing about.
  strayValue = {
    delivery = [ "one" ];
    files."key" = {
      path = "/run/vars/other/spare/key";
      secrecy = "secret";
      deploy = true;
      inPlan = "reference";
      owner = "root";
      group = "root";
      mode = "0400";
    };
  };

  readOf = args: realiser.readOf ({ profile = "trusted"; } // args);

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
      result = support.valuePlan {
        instance = "holder";
        openIt = true;
        inherit fileArgs unitArgs;
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

  simple = support.serving "only";

  # One unit that says how it is probed, which is the entry every test of the
  # derived unit reads. `extra` is what the probed unit declares beside the
  # pair, so a test asking what the probe inherits states only that.
  probing =
    {
      command ? "${borgbackup}/bin/borg check",
      timeout ? "30s",
      extra ? { },
    }:
    _: {
      closure = [ borgbackup ];
      units.only = {
        command = "${borgbackup}/bin/borg serve";
        probe = command;
        probeTimeout = timeout;
      }
      // extra;
    };

  # The text of the derived file among the ones a realiser publishes, read off
  # the published set rather than off `renderProbe`: what a test asserts is what
  # a builder writes.
  probeTextOf =
    rendered: image:
    builtins.head (map (f: f.text) (filter (f: f.file == reader.probeFileName image.name) rendered));

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
        support.valuePlan {
          unitArgs = { inherit timeout; };
          # A recipe naming a delivered path, so its bytes are assembled on the
          # machine and never enter the image.
          extra = vars: {
            configData."/etc/thing.conf" = {
              mode = "0400";
              reload = [ "only" ];
              render = [
                { text = "value = ${text}\n"; }
                { ref = vars.hostKey."key".path; }
              ];
            };
          };
          instances.other = {
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

  # One machine offering the account's scope, stated where the registry states
  # it. Nothing else about the machine moves, so what a comparison below shows
  # is the scope and never a second edit.
  userMachines = support.machines // {
    one = support.machines.one // {
      scope = "user";
    };
  };

  # The operator's signing key, which is an argument of the build: two paths
  # the build spends and neither the plan nor the artifact carries.
  signing = {
    privateKey = "/nix/store/0000000000000000000000000000000a-verity-key.pem";
    certificate = "/nix/store/0000000000000000000000000000000b-verity-cert.pem";
  };

  otherSigning = {
    privateKey = "/nix/store/0000000000000000000000000000000c-rotated-key.pem";
    certificate = "/nix/store/0000000000000000000000000000000d-rotated-cert.pem";
  };

  # One entry on a machine of the stated scope, read under the stated profile.
  readScoped =
    args: implementation:
    let
      p = planned { inherit (args) registry; } implementation;
    in
    reader.read {
      inherit (p) plan key;
      profile = args.profile or "trusted";
    };

  builtScoped =
    args: implementation:
    let
      p = planned { inherit (args) registry; } implementation;
    in
    builder.build (
      {
        inherit (p) plan key;
        profile = args.profile or "trusted";
      }
      // (if args ? signing then { inherit (args) signing; } else { })
    );

  # The same builder over a pkgs whose every derivation is its own text, so a
  # test can read the tree a build writes rather than a path keyed by it: an
  # inner script is what an outer one interpolates, so the identity file and
  # every unit file placement are inside the string this answers.
  inlinePkgs = builderPkgs // {
    writeText = _name: text: { outPath = text; };
    writeTextFile = { name, text }: {
      inherit name;
      outPath = text;
    };
    runCommand =
      name: attrs: text:
      {
        inherit name;
        outPath = text;
      }
      // attrs
      // (attrs.passthru or { });
  };

  inlineBuilder = import imageSource {
    inherit planner;
    inherit (builderPkgs) lib;
    pkgs = inlinePkgs;
  };

  inlineOf =
    args: implementation:
    let
      p = planned { inherit (args) registry; } implementation;
    in
    inlineBuilder.build (
      {
        inherit (p) plan key;
        profile = args.profile or "trusted";
      }
      // (if args ? signing then { inherit (args) signing; } else { })
    );

  treeOf = args: implementation: "${(inlineOf args implementation).raw}";

  # A unit needing a static host account, which is what the `DynamicUser`
  # profiles deny and what a user scope's own profile does not.
  needsAnAccount = _: {
    closure = [ borgbackup ];
    units.only = {
      command = "${borgbackup}/bin/borg serve";
      user = "borg";
    };
  };

  # One entry with a staged configuration file and a reloading unit, on a
  # machine of the stated scope, built: the deployment the attach script's own
  # steps are read off.
  stagedOn =
    registry:
    let
      result = planOf {
        machines = registry;
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = _: {
                closure = [ borgbackup ];
                configData."/etc/thing.conf" = {
                  mode = "0400";
                  reload = [ "only" ];
                  render = [ { text = "value = one\n"; } ];
                };
                units.only.command = "${borgbackup}/bin/borg serve";
                units.sweep = {
                  command = "${borgbackup}/bin/borg prune";
                  schedule = "daily";
                };
              };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      };
      built = builder.build (
        {
          inherit (result) plan;
          key = "svc:only@one";
          profile = "trusted";
        }
        // (if registry == userMachines then { inherit signing; } else { })
      );
    in
    {
      inherit (built) attach detach check;
      inherit (built.image)
        staging
        version
        name
        scope
        ;
      units = built.attachment.units;
      image = built.attachment.image;
      sidecars = reader.sidecarsOf built.attachment.image;
      raw = "${built.raw}";
    };

  systemStaged = stagedOn support.machines;

  userStaged = stagedOn userMachines;
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
        registry = laptopMachines;
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
        # An environment key is the left half of one quoted assignment, so a
        # break in it is a directive line of its own the moment it is rendered.
        # The planner refuses the name by its grammar and records neither it nor
        # its value, so what reaches the renderer has no such half to render.
        theRecordCarriesTheName = (withKey smuggled).units.say.record ? env;
        noSecondDirective = hasInfix "\nExecStartPost" (reader.renderUnit (withKey smuggled) "say");
        oneKeyBuilds = raises (withKey "TOKEN");
        theRowAboveTheRaise = support.rowIds broken;
      };
      expected = {
        theRecordCarriesTheName = false;
        noSecondDirective = false;
        oneKeyBuilds = false;
        theRowAboveTheRaise = [ "unit-env-name-malformed" ];
      };
    };

  testARenderedDirectiveReadsBackAsTheNameAndTheValueThePlanRecords =
    let
      name = "CERT_CHAIN";
      value = "say \"hi\" c:\\path here";
      image = readOf { } (_: {
        closure = [ borgbackup ];
        units.web = {
          command = "${borgbackup}/bin/borg serve";
          env.${name} = value;
        };
      });
      envLines = filter (l: hasInfix "Environment=" l) (support.lines (reader.renderUnit image "web"));
      # What the service manager is left with: the quoting comes off and one
      # escape is undone, over the whole assignment rather than over half of it.
      assignment = builtins.head (builtins.match "Environment=\"(.*)\"" (builtins.head envLines));
      readBack = builtins.replaceStrings [ "\\\"" "\\\\" ] [ "\"" "\\" ] assignment;
    in
    {
      expr = {
        assignments = length envLines;
        line = builtins.head envLines;
        roundTrip = readBack;
        bothHalves = readBack == "${name}=${value}";
      };
      expected = {
        assignments = 1;
        line = "Environment=\"CERT_CHAIN=say \\\"hi\\\" c:\\\\path here\"";
        roundTrip = "CERT_CHAIN=say \"hi\" c:\\path here";
        bothHalves = true;
      };
    };

  testAnEnvironmentNameTheRendererCannotCarryIsRefused =
    let
      smuggled = "A\nExecStartPost=/bin/sh -c evil\n#";
      p = planned { } (_: {
        closure = [ borgbackup ];
        units.say = {
          command = "${borgbackup}/bin/borg serve";
          env.${smuggled} = "x";
        };
      });
      built = builder.build {
        inherit (p) plan key;
        profile = "trusted";
      };
      # The renderer's own half, handed the record directly: the reading refuses
      # first, so nothing else reaches the line this name would be rendered into.
      forged =
        let
          whole = readOf { } (_: {
            closure = [ borgbackup ];
            units.say.command = "${borgbackup}/bin/borg serve";
          });
        in
        whole
        // {
          units = whole.units // {
            say = whole.units.say // {
              record = whole.units.say.record // {
                env.${smuggled} = "x";
              };
            };
          };
        };
    in
    {
      expr = {
        # The name is in no record the plan carries, so nothing of this build is
        # stopped: the row is the report and the forged half never exists.
        theBuildIsStopped = raises built;
        theRendererRefusesTheRecord = raises (reader.renderUnit forged "say");
        accountedAs = reader.accounts.envNameRefused.id;
        theRowAboveTheRaise = support.rowIds p.result;
        namesTheUnit = hasInfix "`say`" (support.messageById "unit-env-name-malformed" p.result);
        namesTheName = hasInfix "A ExecStartPost" (support.messageById "unit-env-name-malformed" p.result);
      };
      expected = {
        theBuildIsStopped = false;
        theRendererRefusesTheRecord = true;
        accountedAs = "unit-env-name-malformed";
        theRowAboveTheRaise = [ "unit-env-name-malformed" ];
        namesTheUnit = true;
        namesTheName = true;
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
            registry = laptopMachines;
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
        support.valuePlan {
          instance = "holder";
          openIt = true;
          extra = _: { inherit closure; };
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

  # The index is keyed by the path a value record declares, because that path is
  # the whole of what a read record carries: a record of another shape is in no
  # index, and a value record whose file states none of what the reading indexes
  # contributes nothing rather than raising inside a reading that may not raise.
  testTheValueIndexAnswersForADeclaredFileAlone =
    let
      result = peerRead { };
      index = reader.valueIndex result.plan;
      answered = index.${peerPath};
      fabricated = reader.valueIndex (
        result.plan
        // {
          "holder:vars/half@one" = {
            delivery = [ "one" ];
            files."key".path = "/run/vars/holder/half/key";
          };
        }
      );
    in
    {
      expr = {
        paths = attrNames index;
        entry = answered.key;
        file = answered.fname;
        record = reader.recordOf answered.file;
        delivery = answered.delivery;
        # A machine record and a service entry record no `delivery` beside
        # `files`, so a plan holding only those two is indexed as nothing.
        withoutTheValueRecord = attrNames (reader.valueIndex (removeAttrs result.plan [ answered.key ]));
        malformed = attrNames fabricated;
      };
      expected = {
        paths = [ peerPath ];
        entry = "holder:vars/token@one";
        file = "secret";
        record = "root:root at mode 0400";
        delivery = [ "one" ];
        withoutTheValueRecord = [ ];
        malformed = [ peerPath ];
      };
    };

  # Every reader of the shown list may index any field of it, so a read-derived
  # record carries the field set the entry's own walk carries, and the two
  # differ only in the provenance a refusal names.
  testAReadDerivedValueRecordCarriesTheSameFieldSet =
    let
      result = peerRead { };
      own = builtins.head (peerImage { key = "holder:only@one"; } result).generated;
      read = builtins.head (peerImage { } result).generated;
      provenance = [
        "gen"
        "fname"
        "slot"
        "valueEntry"
      ];
    in
    {
      expr = {
        fields = attrNames read;
        sameFields = attrNames own == attrNames read;
        ownProvenance = {
          inherit (own)
            gen
            fname
            slot
            valueEntry
            ;
        };
        readProvenance = {
          inherit (read)
            gen
            fname
            slot
            valueEntry
            ;
        };
        oneFile = removeAttrs own provenance == removeAttrs read provenance;
      };
      expected = {
        fields = [
          "deploy"
          "fname"
          "gen"
          "group"
          "inPlan"
          "mode"
          "owner"
          "path"
          "present"
          "secrecy"
          "slot"
          "valueEntry"
        ];
        sameFields = true;
        ownProvenance = {
          gen = "token";
          fname = "secret";
          slot = null;
          valueEntry = null;
        };
        readProvenance = {
          gen = null;
          fname = null;
          slot = "cred";
          valueEntry = "holder:vars/token@one";
        };
        oneFile = true;
      };
    };

  testAValueAnotherEntryGeneratedIsShownAtItsPath =
    let
      result = peerRead { };
      image = peerImage { } result;
      built = peerBuild { } result;
    in
    {
      expr = {
        rows = map (row: row.id) result.diagnostics;
        delivery = result.plan."holder:vars/token@one".delivery;
        # The consumer's own declaration generates nothing: every path below is
        # one a declared read named.
        ownVars = attrNames (result.plan."app:only@one".vars or { });
        shown = map (p: p.path) image.hostPaths;
        kinds = map (p: p.kind) image.hostPaths;
        record = map reader.recordOf image.generated;
        binds = occurrences "BindReadOnlyPaths=${peerPath}:${peerPath}" built.units."app-only-only.service";
        # The image root creates one empty file per shown path, so one record is
        # one mount point.
        mountPoints = length (filter (p: p.path == peerPath) built.image.hostPaths);
      };
      expected = {
        rows = [ ];
        delivery = [ "one" ];
        ownVars = [ ];
        shown = [ peerPath ];
        kinds = [ "generated-file" ];
        record = [ "root:root at mode 0400" ];
        binds = 1;
        mountPoints = 1;
      };
    };

  testAReadOfAnUndeployedValueIsShownAtNoPath =
    let
      result = peerRead {
        deploy = false;
        extra.configData."/etc/app.conf" = {
          mode = "0444";
          reload = [ ];
          render = [ { text = "value\n"; } ];
        };
      };
      image = peerImage { } result;
    in
    {
      expr = {
        # The planner's own row for declaring a read of a value no machine
        # receives, which is what an operator acts on.
        namesTheUndeployedRead = elem "slot-reads-undeployed-value" (map (row: row.id) result.diagnostics);
        shown = map (p: p.path) image.hostPaths;
        stillInThePlan = result.plan."app:only@one".reads.cred.values.secret.path;
      };
      expected = {
        namesTheUndeployedRead = true;
        shown = [ "/etc/app.conf" ];
        stillInThePlan = peerPath;
      };
    };

  testAValueTheEntryNeitherGeneratedNorReadIsShownAtNoPath =
    let
      result = peerRead { };
      withStray = result.plan // {
        "other:vars/spare@one" = strayValue;
      };
      shownOf =
        plan:
        map (p: p.path)
          (reader.read {
            inherit plan;
            key = "app:only@one";
            profile = "trusted";
          }).hostPaths;
    in
    {
      expr = {
        withoutIt = shownOf result.plan;
        withIt = shownOf withStray;
        # The index answers for it, so the entry is shown nothing for it because
        # no statement of the entry reaches it and not because it is unknown.
        indexed = elem "/run/vars/other/spare/key" (attrNames (reader.valueIndex withStray));
      };
      expected = {
        withoutIt = [ peerPath ];
        withIt = [ peerPath ];
        indexed = true;
      };
    };

  testAValueTwoReadsNameIsShownOnce =
    let
      result = peerRead {
        interface = credentials;
        exports = vars: {
          first = vars.token."secret";
          second = vars.token."secret";
        };
        reads = [
          "first"
          "second"
        ];
      };
      image = peerImage { } result;
      built = peerBuild { } result;
    in
    {
      expr = {
        rows = map (row: row.id) result.diagnostics;
        namedTwice = attrNames result.plan."app:only@one".reads.cred.values;
        shown = map (p: p.path) image.hostPaths;
        described = map (g: g.path) (reader.attachment image).generated;
        binds = occurrences "BindReadOnlyPaths=${peerPath}:${peerPath}" built.units."app-only-only.service";
        mountPoints = length (filter (p: p.path == peerPath) built.image.hostPaths);
      };
      expected = {
        rows = [ ];
        namedTwice = [
          "first"
          "second"
        ];
        shown = [ peerPath ];
        described = [ peerPath ];
        binds = 1;
        mountPoints = 1;
      };
    };

  # The owner of a value declaring a read of its own export: two statements of
  # one entry reach one file, and the record shown is the one the value's own
  # entry states either way.
  testAValueAnEntryBothGeneratedAndReadIsShownOnce =
    let
      result = planOf {
        instances.holder = {
          module = peerHolder {
            interface = credential;
            exports = vars: { secret = vars.token."secret"; };
            fileArgs = { };
            deploy = true;
            uses.cred = {
              interface = credential;
              reads = [ "secret" ];
            };
          };
          placement.every.only.machines = [ "one" ];
          exposes = [ "cred" ];
          wire.cred = {
            instance = "holder";
            provides = "cred";
          };
        };
        varsState."holder:vars/token@one"."secret".present = true;
      };
      image = peerImage { key = "holder:only@one"; } result;
      record = builtins.head image.generated;
    in
    {
      expr = {
        rows = map (row: row.id) result.diagnostics;
        readsItsOwn = attrNames result.plan."holder:only@one".reads.cred.values;
        shown = map (p: p.path) image.hostPaths;
        count = length image.generated;
        record = reader.recordOf record;
        reachedByItsOwnDeclaration = record.gen;
      };
      expected = {
        rows = [ ];
        readsItsOwn = [ "secret" ];
        shown = [ peerPath ];
        count = 1;
        record = "root:root at mode 0400";
        reachedByItsOwnDeclaration = "token";
      };
    };

  testEveryReadingOfAShownValueAsksOneList =
    let
      result = peerRead { };
      image = peerImage { } result;
      withStray = reader.read {
        plan = result.plan // {
          "other:vars/spare@one" = strayValue;
        };
        key = "app:only@one";
        profile = "trusted";
      };
    in
    {
      expr = {
        shown = map (p: p.path) image.hostPaths;
        denied = map (d: d.path or null) (denialsFor {
          inherit (result) plan;
          key = "app:only@one";
          profile = "strict";
        });
        references = image.referencePaths;
        described = map (g: g.path) (reader.attachment image).generated;
        theStrayValueIsInNoneOfThem = hasInfix "/run/vars/other/spare/key" (
          builtins.toJSON (reader.attachment withStray)
        );
      };
      expected = {
        shown = [ peerPath ];
        denied = [ peerPath ];
        references = [ peerPath ];
        described = [ peerPath ];
        theStrayValueIsInNoneOfThem = false;
      };
    };

  # A value path is a reference whichever statement of the entry reached it, so
  # declaring one as a closure root is refused: its bytes reach the units from
  # the machine and never through an image.
  testAPeersValuePathIsAReferenceRatherThanAClosureRoot =
    let
      result = peerRead { };
      entry = result.plan."app:only@one";
    in
    {
      expr = {
        references = (peerImage { } result).referencePaths;
        declaringItRaises = raises (
          reader.read {
            plan = result.plan // {
              "app:only@one" = entry // {
                closure = entry.closure ++ [ peerPath ];
              };
            };
            key = "app:only@one";
            profile = "trusted";
          }
        );
      };
      expected = {
        references = [ peerPath ];
        declaringItRaises = true;
      };
    };

  # The three published entry points and the whole reading answer about one
  # list, which is why each takes it rather than walking the entry again.
  testThePublishedReadingsAgreeAboutTheShownPaths =
    let
      result = peerRead { };
      entry = result.plan."app:only@one";
      generated = shownValues result.plan "app:only@one";
      image = peerImage { } result;
    in
    {
      expr = {
        throughTheEntryPoint = map (p: p.path) (
          reader.hostPaths {
            key = "app:only@one";
            inherit entry generated;
          }
        );
        throughTheReading = map (p: p.path) image.hostPaths;
        digestsAgree =
          reader.versionFor {
            key = "app:only@one";
            inherit entry generated;
            profile = "trusted";
          } == image.version;
        denials = reader.denials {
          inherit entry generated;
          profile = "trusted";
        };
      };
      expected = {
        throughTheEntryPoint = [ peerPath ];
        throughTheReading = [ peerPath ];
        digestsAgree = true;
        denials = [ ];
      };
    };

  # The attach refuses before it writes anything where a shown generated path is
  # not on the machine yet, and that guard is one per shown path.
  testAPeersValueIsGuardedBeforeTheAttachWritesAnything =
    let
      built = peerBuild { } (peerRead { });
    in
    {
      expr = {
        # `lib.escapeShellArg` leaves a word of safe characters bare, which a
        # value's path is, so the guard reads the path with no quoting of its own.
        guards = occurrences "-e \"$root\"${peerPath} ]" built.attach;
        namesTheValue = hasInfix "is not on this machine yet" built.attach;
      };
      expected = {
        guards = 1;
        namesTheValue = true;
      };
    };

  # The digest is taken over the host paths the entry is shown, so widening the
  # shown set widens the digest with no edit to the digest: one apply replaces
  # those artifacts and the next reports nothing changed.
  testAReadOfAPeersValueMovesTheEntrysVersionDigest =
    let
      withTheRead = peerRead { unitArgs.env.CONST = "x"; };
      withoutIt = peerRead {
        reads = [ ];
        unitArgs.env.CONST = "x";
      };
      imageOf = result: peerImage { } result;
      fileOf = result: (reader.attachment (imageOf result)).image;
    in
    {
      expr = {
        # The two units are byte-identical, so what moves the digest is the
        # shown path and nothing else.
        oneUnitText =
          reader.renderUnit (imageOf withTheRead) "only" == reader.renderUnit (imageOf withoutIt) "only";
        shownWithTheRead = map (p: p.path) (imageOf withTheRead).hostPaths;
        shownWithoutIt = map (p: p.path) (imageOf withoutIt).hostPaths;
        digestsDiffer = (imageOf withTheRead).version != (imageOf withoutIt).version;
        fileNamesDiffer = fileOf withTheRead != fileOf withoutIt;
        # And a second reading of the same deployment answers the first's
        # digest, which is what makes the next apply a no-op.
        twiceIsOneDigest = (imageOf withTheRead).version == (peerImage { } withTheRead).version;
      };
      expected = {
        oneUnitText = false;
        shownWithTheRead = [ peerPath ];
        shownWithoutIt = [ ];
        digestsDiffer = true;
        fileNamesDiffer = true;
        twiceIsOneDigest = true;
      };
    };

  testAPeersValueOnlyItsOwnerMayReadIsDeniedToItsReader =
    let
      result = peerRead { };
      denialsOn =
        key:
        denialsFor {
          inherit (result) plan;
          inherit key;
          profile = "strict";
        };
      denied = builtins.head (denialsOn "app:only@one");
    in
    {
      expr = {
        count = length (denialsOn "app:only@one");
        inherit (denied)
          unit
          path
          record
          account
          access
          ;
        # The reader earns the denial the owner earns for that file: one record,
        # one comparison, one answer.
        theOwnersOwnDenial = denialsOn "holder:only@one" == denialsOn "app:only@one";
        refused = raises (peerImage { profile = "strict"; } result);
      };
      expected = {
        count = 1;
        unit = "only";
        path = peerPath;
        record = "root:root at mode 0400";
        account = "a transient account";
        access = "a host file only root may read";
        theOwnersOwnDenial = true;
        refused = true;
      };
    };

  testAPeersValueAReadersGroupMayReadIsNotDenied =
    let
      result = peerRead {
        fileArgs = {
          owner = "nobody";
          group = "app";
          mode = "0440";
        };
        unitArgs.extends = [
          {
            extension = groupedUnit;
            values.supplementaryGroups = [ "app" ];
          }
        ];
      };
      image = peerImage { profile = "strict"; } result;
    in
    {
      expr = {
        denials = denialsFor {
          inherit (result) plan;
          key = "app:only@one";
          profile = "strict";
        };
        shown = map (p: p.path) image.hostPaths;
        record = map reader.recordOf image.generated;
      };
      expected = {
        denials = [ ];
        shown = [ peerPath ];
        record = [ "nobody:app at mode 0440" ];
      };
    };

  # A read naming a path the plan's value records account for no delivered bytes
  # of is a refusal carrying the identifier of the row the layer holding the
  # whole plan produces, and never a path omitted without a word.
  testTheUnaccountedRefusalIsPrecededByItsRow =
    let
      result = peerRead { };
      value = result.plan."holder:vars/token@one";
      readOfPlan =
        plan:
        reader.read {
          inherit plan;
          key = "app:only@one";
          profile = "trusted";
        };
    in
    {
      expr = {
        accounted = reader.accounts.valueUnaccounted.id;
        excused = reader.accounts.valueUnaccounted ? because;
        deliveredElsewhere = raises (
          readOfPlan (
            result.plan
            // {
              "holder:vars/token@one" = value // {
                delivery = [ "two" ];
              };
            }
          )
        );
        noValueRecord = raises (readOfPlan (removeAttrs result.plan [ "holder:vars/token@one" ]));
        andTheUnedittedPlanIsRead = map (p: p.path) (readOfPlan result.plan).hostPaths;
      };
      expected = {
        accounted = "operator-entry-value-unaccounted";
        excused = false;
        deliveredElsewhere = true;
        noValueRecord = true;
        andTheUnedittedPlanIsRead = [ peerPath ];
      };
    };

  testARenderRecipeIsAssembledOnTheHost =
    let
      result = support.valuePlan {
        instance = "holder";
        extra = vars: {
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
          scope = "system";
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
      withSecret = profile: shownTo { inherit profile; };
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

  # Two statements of one entry differing in nothing but the confinement: the
  # profile decides directives the rendered units carry, so the identity the
  # machine is compared against has to move with it.
  testATightenedProfileIsABuildTheMachineDoesNotHold =
    let
      result = (planned { } simple).result;
      loose = builtFrom { profile = "default"; } result;
      tightened = builtFrom { profile = "strict"; } result;
      thisBuild = "${tightened.raw}/${tightened.attachment.image}";
      units = concatStringsSep " " (map (unit: "'${unit}'") tightened.attachment.units);
    in
    {
      expr = {
        digestMoved = loose.image.version != tightened.image.version;
        imageNameMoved = loose.attachment.image != tightened.attachment.image;
        namesTheOtherBuild = hasInfix loose.attachment.image tightened.attach;
        asksWhatTheMachineHolds = hasInfix "held=\"$(systemctl show -P RootImage" tightened.attach;
        comparedAgainstThisBuild = hasInfix "[ \"$held\" != ${thisBuild} ]" tightened.attach;
        stopped = hasInfix "systemctl stop ${units}" tightened.attach;
        detached = hasInfix "portablectl detach \"$held\"" tightened.attach;
        attachedUnderTheStatement = hasInfix "portablectl attach --profile=strict ${thisBuild}" tightened.attach;
        # The second apply: both branches are guarded by what the machine holds,
        # and the run says so when neither of them ran.
        attachedOnlyWhenDetached = hasInfix "\"$(portablectl is-attached ${thisBuild} 2> /dev/null || echo detached)\" = detached" tightened.attach;
        nothingChanged = hasInfix "[ \"$changed\" = 1 ] || echo \"nothing changed\"" tightened.attach;
      };
      expected = {
        digestMoved = true;
        imageNameMoved = true;
        namesTheOtherBuild = false;
        asksWhatTheMachineHolds = true;
        comparedAgainstThisBuild = true;
        stopped = true;
        detached = true;
        attachedUnderTheStatement = true;
        attachedOnlyWhenDetached = true;
        nothingChanged = true;
      };
    };

  # An edit the entry is not in, under the same statement: the digest, the bytes
  # and the path an apply compares are all where they were.
  testAnEntryWhoseStatementDidNotChangeKeepsItsDigest =
    let
      deployment =
        command:
        planOf {
          instances = {
            svc = {
              module = soleRoot {
                module = _: {
                  impl = _: {
                    closure = [ borgbackup ];
                    units.only.command = "${borgbackup}/bin/borg serve";
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
                    units.only.command = command;
                  };
                };
              };
              placement.every.only.machines = [ "two" ];
            };
          };
        };
      builtWith =
        key: command:
        builtFrom {
          inherit key;
          profile = "strict";
        } (deployment command);
      before = builtWith "svc:only@one" "${openssh}/bin/sshd";
      after = builtWith "svc:only@one" "${openssh}/bin/sshd -D";
    in
    {
      expr = {
        version = before.image.version == after.image.version;
        unitFiles = before.units == after.units;
        # The fake store path of this layer is keyed by the bytes it is handed,
        # so one path on both sides is one artifact.
        artifact = before.raw.outPath == after.raw.outPath;
        image = before.attachment.image == after.attachment.image;
        # What an apply compares, so the held image is this one and neither the
        # detach branch nor the attach branch runs.
        attachStep = before.attach == after.attach;
        theEditedEntryMoved =
          (builtWith "other:only@two" "${openssh}/bin/sshd").image.version
          != (builtWith "other:only@two" "${openssh}/bin/sshd -D").image.version;
      };
      expected = {
        version = true;
        unitFiles = true;
        artifact = true;
        image = true;
        attachStep = true;
        theEditedEntryMoved = true;
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
        directiveNames = 24;
        accounted = null;
        because = true;
      };
    };

  testAConfigurationFileOnlyRootMayReadUnderAConfiningProfile =
    let
      denials =
        profile:
        filter (d: d ? path) (denialsFor {
          plan = (planned { } (shownAt { })).plan;
          inherit profile;
        });
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
        denials = denialsFor {
          plan = (planned { } grouped).plan;
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
      denials = denialsFor {
        plan = (planned { } (shownAt { })).plan;
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

  # User-mode extraction reads the user unit directories alone, so a system-unit
  # image yields an account no unit at all, and `PORTABLE_SCOPE=` is what gates
  # the attachment. Both are bytes the artifact carries, so the digest moves.
  testAUserScopeImagePlacesItsUnitsWhereAUserManagerReads =
    let
      userTree = treeOf {
        registry = userMachines;
        inherit signing;
      } simple;
      systemTree = treeOf { registry = support.machines; } simple;
      userReading = readScoped { registry = userMachines; } simple;
      systemReading = readScoped { registry = support.machines; } simple;
    in
    {
      expr = {
        userDirectory = userReading.unitDirectory;
        systemDirectory = systemReading.unitDirectory;
        theUnitFileIsUnderIt = hasInfix "$out/usr/lib/systemd/user/svc-only-only.service" userTree;
        andTheImageCarriesNoSystemUnitDirectory = hasInfix "/etc/systemd/system" userTree;
        theSystemImageIsWhereItWas = hasInfix "$out/etc/systemd/system/svc-only-only.service" systemTree;
        theIdentityStatesTheScope = hasInfix "PORTABLE_SCOPE=user" userTree;
        # Unset means the system scope, so a system-scope image states it no
        # more than it states any other default.
        theSystemIdentityStatesNone = hasInfix "PORTABLE_SCOPE" systemTree;
        scopes = [
          systemReading.scope
          userReading.scope
        ];
        digestMovedWithTheScope = userReading.version != systemReading.version;
      };
      expected = {
        userDirectory = "/usr/lib/systemd/user";
        systemDirectory = "/etc/systemd/system";
        theUnitFileIsUnderIt = true;
        andTheImageCarriesNoSystemUnitDirectory = false;
        theSystemImageIsWhereItWas = true;
        theIdentityStatesTheScope = true;
        theSystemIdentityStatesNone = false;
        scopes = [
          "system"
          "user"
        ];
        digestMovedWithTheScope = true;
      };
    };

  # `systemd-mountfsd` applies `image_policy_untrusted` to an image outside the
  # system trusted directories, and an unsigned one escalates to an interactive
  # polkit action a non-interactive run cannot answer. What it verifies is the
  # three files beside the image, named off the image with `.raw` dropped.
  testAUserScopeImageCarriesASignedVerityRoothash =
    let
      inline = inlineOf {
        registry = userMachines;
        inherit signing;
      } simple;
      artifact = "${inline}";
      systemArtifact = "${inlineOf { registry = support.machines; } simple}";
      sidecars = reader.sidecarsOf inline.attachment.image;
      version = inline.image.version;
    in
    {
      expr = {
        # A hash tree over the squashfs this realiser already builds, and the
        # root hash of it written out beside it.
        aHashTreeOverTheImage = hasInfix "veritysetup format " artifact;
        writingTheRootHash = hasInfix ''--root-hash-file="$out"/${sidecars.roothash}'' artifact;
        besideTheImage = hasInfix ''"$out"/${sidecars.verity}'' artifact;
        # Signed here, so no machine is asked to grant anything at attach time.
        signedOverThatHash = hasInfix "openssl smime -sign -nocerts -noattr -binary -outform der" artifact;
        byTheOperatorsKey = hasInfix "-inkey ${signing.privateKey}" artifact;
        underItsCertificate = hasInfix "-signer ${signing.certificate}" artifact;
        intoTheSignatureFile = hasInfix ''-out "$out"/${sidecars.signature}'' artifact;
        # Both are drawn from the machine's randomness unless they are stated,
        # and the root hash is over both, so two builds would sign two hashes.
        statesItsSalt = hasInfix "--salt=" artifact;
        statesItsUuid = hasInfix "--uuid=" artifact;
        # The names a dissection derives: the image's own, `.raw` dropped.
        names = sidecars;
        # And the artifact carries them beside the image it verifies.
        carriedBesideTheImage = map (name: hasInfix ''"$out/${name}"'' artifact) [
          sidecars.verity
          sidecars.roothash
          sidecars.signature
        ];
        # The system-scope image is the one this capability already describes.
        theSystemArtifactCarriesNoVerity = hasInfix "veritysetup" systemArtifact;
        theSystemImageIsStillTheSquashfs = hasInfix "mksquashfs" systemArtifact;
        # Handed no key, the build refuses rather than writing an image no
        # account can mount.
        refusedWithNoKey = raises (builtScoped { registry = userMachines; } simple);
      };
      expected = {
        aHashTreeOverTheImage = true;
        writingTheRootHash = true;
        besideTheImage = true;
        signedOverThatHash = true;
        byTheOperatorsKey = true;
        underItsCertificate = true;
        intoTheSignatureFile = true;
        statesItsSalt = true;
        statesItsUuid = true;
        names = {
          verity = "svc-only_${version}.verity";
          roothash = "svc-only_${version}.roothash";
          signature = "svc-only_${version}.roothash.p7s";
        };
        carriedBesideTheImage = [
          true
          true
          true
        ];
        theSystemArtifactCarriesNoVerity = false;
        theSystemImageIsStillTheSquashfs = true;
        refusedWithNoKey = true;
      };
    };

  # The key reaches the build and nothing else, so rotating it re-keys nothing
  # and no plan, no machine and no artifact ever holds it.
  testTheSigningKeyIsAnOperatorArgumentAndNeverAPlanFact =
    let
      p = planned { registry = userMachines; } simple;
      built = builtScoped {
        registry = userMachines;
        inherit signing;
      } simple;
      rotated = builtScoped {
        registry = userMachines;
        signing = otherSigning;
      } simple;
      material = [
        signing.privateKey
        signing.certificate
      ];
      mentions = text: filter (path: hasInfix path text) material;
    in
    {
      expr = {
        inThePlan = mentions (builtins.toJSON p.plan);
        inTheEntry = mentions (builtins.toJSON p.plan.${p.key});
        inTheAttachmentDescription = mentions (builtins.toJSON built.attachment);
        inTheAttachScript = mentions built.attach;
        inTheDetachScript = mentions built.detach;
        inTheCheckScript = mentions built.check;
        inAUnitFile = mentions (concatStringsSep "\n" (builtins.attrValues built.units));
        # The one place it is spent.
        inTheBuild = mentions "${inlineOf {
          registry = userMachines;
          inherit signing;
        } simple}";
        rotatingItKeysNothing = built.image.version == rotated.image.version;
        andNamesTheSameImage = built.attachment.image == rotated.attachment.image;
      };
      expected = {
        inThePlan = [ ];
        inTheEntry = [ ];
        inTheAttachmentDescription = [ ];
        inTheAttachScript = [ ];
        inTheDetachScript = [ ];
        inTheCheckScript = [ ];
        inAUnitFile = [ ];
        inTheBuild = material;
        rotatingItKeysNothing = true;
        andNamesTheSameImage = true;
      };
    };

  # Upstream's user profiles drop the two statements an account cannot be
  # granted and keep the one that needs no privilege, and it is one table read
  # per scope rather than a second table beside the first.
  testAUserProfileDropsWhatAUserManagerCannotGrant =
    let
      userProfiles = reader.profilesFor "user";
      systemProfiles = reader.profilesFor "system";
      confining = [
        "default"
        "nonetwork"
        "strict"
      ];
      reading = readScoped {
        registry = userMachines;
        profile = "default";
      } simple;
    in
    {
      expr = {
        inSystemScope = systemProfiles.default.statements;
        inUserScope = userProfiles.default.statements;
        everyConfiningProfileKeepsPrivateUsers = map (
          n: elem "PrivateUsers=yes" userProfiles.${n}.statements
        ) confining;
        noneImposesAnAccount = filter (
          n: elem "DynamicUser=yes" userProfiles.${n}.statements
        ) reader.profileNames;
        noneClosesTheHome = filter (
          n: elem "ProtectHome=yes" userProfiles.${n}.statements
        ) reader.profileNames;
        theReadingPublishesWhatApplies = reading.statements;
        oneTableInBothScopes = attrNames userProfiles == attrNames systemProfiles;
      };
      expected = {
        inSystemScope = [
          "DynamicUser=yes"
          "PrivateUsers=yes"
          "ProtectHome=yes"
        ];
        inUserScope = [ "PrivateUsers=yes" ];
        everyConfiningProfileKeepsPrivateUsers = [
          true
          true
          true
        ];
        noneImposesAnAccount = [ ];
        noneClosesTheHome = [ ];
        theReadingPublishesWhatApplies = [ "PrivateUsers=yes" ];
        oneTableInBothScopes = true;
      };
    };

  testTheTrustedProfileIsOneProfileInBothScopes =
    let
      userProfiles = reader.profilesFor "user";
      systemProfiles = reader.profilesFor "system";
      denialsUnderTrusted =
        registry:
        let
          p = planned { inherit registry; } needsAnAccount;
        in
        denialsFor {
          inherit (p) plan key;
          profile = "trusted";
        };
    in
    {
      expr = {
        identical = userProfiles.trusted == systemProfiles.trusted;
        statements = userProfiles.trusted.statements;
        denies = userProfiles.trusted.denies;
        theSameDenialsForOneEntry =
          denialsUnderTrusted userMachines == denialsUnderTrusted support.machines;
        andNeitherReadingRefuses = [
          (raises (readScoped { registry = userMachines; } needsAnAccount))
          (raises (readScoped { registry = support.machines; } needsAnAccount))
        ];
      };
      expected = {
        identical = true;
        statements = [ ];
        denies = [ ];
        theSameDenialsForOneEntry = true;
        andNeitherReadingRefuses = [
          false
          false
        ];
      };
    };

  # The denial table follows the profile the scope selects, so a statement the
  # `DynamicUser` profiles refuse is read for an account and refused for a
  # machine, by one table and not by a rule per scope.
  testADenialAbsentInUserScopeEarnsNoRow =
    let
      denialsOf =
        registry:
        let
          p = planned { inherit registry; } needsAnAccount;
        in
        denialsFor {
          inherit (p) plan key;
          profile = "default";
        };
      readUnder =
        registry:
        readScoped {
          inherit registry;
          profile = "default";
        } needsAnAccount;
    in
    {
      expr = {
        inUserScope = denialsOf userMachines;
        inSystemScope = map (d: d.access) (denialsOf support.machines);
        theUserScopeReadingStands = raises (readUnder userMachines);
        theSystemScopeReadingIsRefused = raises (readUnder support.machines);
      };
      expected = {
        inUserScope = [ ];
        inSystemScope = [ "a static host user" ];
        theUserScopeReadingStands = false;
        theSystemScopeReadingIsRefused = true;
      };
    };

  # One unprivileged portabled and one manager per account, and no `chown`
  # anywhere: the staging is the account's own, and a delivered ownership a user
  # scope cannot honor is a planner refusal before this script exists.
  testTheAttachInUserScopeAddressesTheUserManager =
    let
      attach = userStaged.attach;
      staged = "\"$root\"${userStaged.staging}/files/etc/thing.conf";
      installing = "\"$root\"${userStaged.staging}/files/etc/thing.conf.installing";
    in
    {
      expr = {
        asksTheAccountsManager = hasInfix "held=\"$(systemctl --user show -P RootImage" attach;
        stopsThroughIt = hasInfix "systemctl --user stop " attach;
        startsThroughIt = hasInfix "systemctl --user start " attach;
        reloadsThroughIt = hasInfix "systemctl --user is-active --quiet \"$1\"" attach;
        attachesThroughItsPortabled = hasInfix "portablectl --user attach --profile=trusted " attach;
        asksThatPortabled = hasInfix "portablectl --user is-attached " attach;
        detachesThroughIt = hasInfix "portablectl --user detach " userStaged.detach;
        # The one bare `systemctl` left is the guard asking whether this machine
        # runs a service manager at all.
        bareManagerCalls = occurrences "systemctl" attach - occurrences "systemctl --user" attach;
        barePortabledCalls = occurrences "portablectl" attach - occurrences "portablectl --user" attach;
        chowns = occurrences "chown" attach;
        andTheSystemScopeStillOwnsWhatItStages = occurrences "chown" systemStaged.attach;
        # The staging discipline is the one it always was: one line for the
        # entry's whole tree under the run's root. The pool chain is its own
        # statement and is asserted where the pool is.
        oneDirectoryTree = length (
          filter (line: hasInfix "install -d -m 0711 " line && hasInfix ''"$root"'' line) (
            support.lines attach
          )
        );
        createdOwnerOnly = hasInfix "install -m 0600 " attach;
        setToTheRecordsMode = hasInfix "chmod 0400 ${installing}" attach;
        movedOntoItsPath = hasInfix "mv ${installing} ${staged}" attach;
        theRootIsStillTheEnvironments = hasInfix ''root="''${PORTABLE_PLANNER_ROOT:-}"'' attach;
      };
      expected = {
        asksTheAccountsManager = true;
        stopsThroughIt = true;
        startsThroughIt = true;
        reloadsThroughIt = true;
        attachesThroughItsPortabled = true;
        asksThatPortabled = true;
        detachesThroughIt = true;
        bareManagerCalls = 1;
        barePortabledCalls = 0;
        chowns = 0;
        andTheSystemScopeStillOwnsWhatItStages = 2;
        oneDirectoryTree = 1;
        createdOwnerOnly = true;
        setToTheRecordsMode = true;
        movedOntoItsPath = true;
        theRootIsStillTheEnvironments = true;
      };
    };

  # A persistent user attach of an out-of-tree path copies the image to a
  # directory the user image search path never scans, so the image is placed in
  # the pool that path does scan and attached by the name it resolves.
  testTheImageIsPlacedWhereTheUserSearchPathScans =
    let
      attach = userStaged.attach;
      named = "${userStaged.name}_${userStaged.version}";
      poolImage = "\"$pool\"/${userStaged.image}";
      poolOf = name: "\"$pool\"/${name}";
      # Every file the pool is handed, in the order the script hands it over.
      placed =
        let
          destinationOf =
            line: builtins.head (filter (w: hasInfix "$pool" w) (nixpkgsLib.splitString " " line));
        in
        map destinationOf (filter (l: hasInfix "install -m 0444 " l) (support.lines attach));
    in
    {
      expr = {
        thePoolIsTheAccountsStatePool = hasInfix ''pool="''${XDG_STATE_HOME:-$HOME/.local/state}/portables"'' attach;
        # Traversable by an account that owns none of it and listable by none:
        # the extraction child opens the image path as a foreign uid, and a
        # listable pool publishes one entry's image names to every account.
        eachComponentNamedAtTheTraversableMode = hasInfix ''install -d -m 0711 "$HOME/.local" "$HOME/.local/state" "$pool"'' attach;
        andTheStatedStateHomeInsteadOfThatChain = hasInfix ''install -d -m 0711 "$XDG_STATE_HOME" "$pool"'' attach;
        noComponentLeftToInstallToCreate = hasInfix "install -d -m 0700" attach;
        # The verity data arrives first and the image lands on the name a
        # resolution finds last, so a name that resolves is verifiable.
        inThatOrder = placed;
        fromTheStoreObjectTheBuildWrote = hasInfix "install -m 0444 ${userStaged.raw}/${userStaged.image} ${poolImage}.installing" attach;
        movedOntoTheNameAResolutionFinds = hasInfix "mv ${poolImage}.installing ${poolImage}" attach;
        attachedByName = hasInfix "portablectl --user attach --profile=trusted ${named} > /dev/null" attach;
        askedByName = hasInfix "portablectl --user is-attached ${named} " attach;
        detachedByName = hasInfix "portablectl --user detach ${named}" userStaged.detach;
        # Never by the store path it was copied from.
        attachedByPath = hasInfix "attach --profile=trusted ${userStaged.raw}" attach;
        comparedAgainstThePoolCopy = hasInfix ''[ "$held" != ${poolImage} ]'' attach;
        removedWithTheAttachment = hasInfix "rm -f ${poolImage} ${poolOf userStaged.sidecars.verity}" userStaged.detach;
        # A system-scope attach is the one it was: the store path itself, and no
        # pool at all.
        theSystemAttachNamesItsStorePath = hasInfix "portablectl attach --profile=trusted ${systemStaged.raw}/${systemStaged.image}" systemStaged.attach;
        theSystemAttachHasNoPool = hasInfix "pool" systemStaged.attach;
      };
      expected = {
        thePoolIsTheAccountsStatePool = true;
        eachComponentNamedAtTheTraversableMode = true;
        andTheStatedStateHomeInsteadOfThatChain = true;
        noComponentLeftToInstallToCreate = false;
        inThatOrder = [
          "\"$pool\"/${userStaged.sidecars.verity}"
          "\"$pool\"/${userStaged.sidecars.roothash}"
          "\"$pool\"/${userStaged.sidecars.signature}"
          "\"$pool\"/${userStaged.image}.installing"
        ];
        fromTheStoreObjectTheBuildWrote = true;
        movedOntoTheNameAResolutionFinds = true;
        attachedByName = true;
        askedByName = true;
        detachedByName = true;
        attachedByPath = false;
        comparedAgainstThePoolCopy = true;
        removedWithTheAttachment = true;
        theSystemAttachNamesItsStorePath = true;
        theSystemAttachHasNoPool = false;
      };
    };

  # What a machine's own listing names an image this realiser built by, crossed
  # against a file name this build composed. The three values are data and no
  # pattern, because the reader of the record is python and one published
  # pattern would be one rule with two readings; the pattern here is this
  # suite's own, built out of them.
  testTheImageFileNameSplitsAtThePublishedHoldings =
    let
      holdings = reader.holdings;
      split =
        file:
        builtins.match "(.*)${holdings.separator}([${holdings.digestAlphabet}]{${toString holdings.digestLength}})\\.raw" file;
      parts = split systemStaged.image;
      name = elemAt parts 0;
      digest = elemAt parts 1;
      chars = genList (i: builtins.substring i 1 digest) (builtins.stringLength digest);
    in
    {
      expr = {
        inherit holdings;
        splits = parts != null;
        theNameTheRuleAdmits = reader.acceptsName name;
        theNameIsTheEntrysOwn = name == systemStaged.name;
        theDigestLength = builtins.stringLength digest;
        overThePublishedAlphabet = builtins.all (c: hasInfix c holdings.digestAlphabet) chars;
        theDigestIsTheEntrysVersion = digest == systemStaged.version;
        # The same composition under the other scope: the file name is the
        # realiser's and the scope is the machine's.
        theOtherScope = split userStaged.image != null;
        # And a listing row of some other tool's image does not split at all.
        somethingElsesImage = split "debian_bookworm.raw" != null;
      };
      expected = {
        holdings = {
          separator = "_";
          digestAlphabet = "0123456789abcdef";
          digestLength = 16;
        };
        splits = true;
        theNameTheRuleAdmits = true;
        theNameIsTheEntrysOwn = true;
        theDigestLength = 16;
        overThePublishedAlphabet = true;
        theDigestIsTheEntrysVersion = true;
        theOtherScope = true;
        somethingElsesImage = false;
      };
    };

  testAnImageOfAProbedEntryCarriesTheProbeUnit =
    let
      image = readOf { } (probing { });
      bare = readOf { } simple;
      derived = reader.probeFileName image.name;
    in
    {
      expr = {
        files = map (f: f.file) (reader.renderedUnits image);
        inherit derived;
        theImagesOwnPrefix = builtins.substring 0 (builtins.stringLength image.name) derived;
        whichUnitItProbes = image.probed;
        # An entry recording no probe carries no such file, and the reading
        # answers that with the same field the rendering gates on.
        unprobed = map (f: f.file) (reader.renderedUnits bare);
        unprobedProbed = bare.probed;
      };
      expected = {
        files = [
          "svc-only-only.service"
          "svc-only-health.service"
        ];
        derived = "svc-only-health.service";
        theImagesOwnPrefix = "svc-only";
        whichUnitItProbes = "only";
        unprobed = [ "svc-only-only.service" ];
        unprobedProbed = null;
      };
    };

  # The probe pair is a vocabulary field like any other, so a table not naming
  # it would fail the build for a deployment the vocabulary accepts. What the
  # two fields render into is the derived file and never the probed unit's own.
  testAProbeFieldTheDirectiveTableDoesNotName =
    let
      image = readOf { } (probing { });
      probedUnit = reader.renderUnit image "only";
      probe = probeTextOf (reader.renderedUnits image) image;
    in
    {
      expr = {
        built = raises image;
        inTheTable = {
          probe = reader.unitDirectives.probe;
          probeTimeout = reader.unitDirectives.probeTimeout;
        };
        theProbedUnitsOwnFile = map (needle: hasInfix needle probedUnit) [
          "${borgbackup}/bin/borg check"
          "TimeoutStartSec"
        ];
        theDerivedFile = map (needle: hasInfix needle probe) [
          "ExecStart=${borgbackup}/bin/borg check"
          "TimeoutStartSec=30s"
        ];
      };
      expected = {
        built = false;
        inTheTable = {
          probe = "ExecStart";
          probeTimeout = "TimeoutStartSec";
        };
        theProbedUnitsOwnFile = [
          false
          false
        ];
        theDerivedFile = [
          true
          true
        ];
      };
    };

  # The binds are the entry's and identical on every unit of it, so a probe
  # reading a delivered value or a configuration file reaches it inside the same
  # namespace without a bind of its own - and it claims no directory, because a
  # job that exits takes a runtime directory it declared with it.
  testAnImagesProbeIsShownWhatTheEntryIsShown =
    let
      result = support.valuePlan {
        instance = "holder";
        openIt = true;
        unitArgs = {
          probe = "${borgbackup}/bin/borg check";
          probeTimeout = "30s";
          runtimeDirectory = [ "holder" ];
          stateDirectory = [ "holder" ];
          cacheDirectory = [ "holder" ];
        };
        extra = _: {
          configData."/etc/thing.conf" = {
            mode = "0444";
            reload = [ "only" ];
            render = [ { text = "value\n"; } ];
          };
        };
      };
      image = reader.read {
        plan = result.plan;
        key = "holder:only@one";
        profile = "trusted";
      };
      probe = probeTextOf (reader.renderedUnits image) image;
      unit = reader.renderUnit image "only";
      bindsIn = text: filter (line: hasInfix "BindReadOnlyPaths=" line) (support.lines text);
      directoriesIn =
        text:
        filter (needle: hasInfix needle text) [
          "CacheDirectory"
          "RuntimeDirectory"
          "StateDirectory"
        ];
    in
    {
      expr = {
        shown = map (p: p.path) image.hostPaths;
        shownToTheProbe = bindsIn probe;
        theSameAsTheUnitIsShown = bindsIn probe == bindsIn unit;
        directories = directoriesIn probe;
        theUnitItProbesDeclaresThem = directoriesIn unit;
      };
      expected = {
        shown = [
          "/etc/thing.conf"
          "/run/vars/holder/hostKey/key"
        ];
        shownToTheProbe = [
          "BindReadOnlyPaths=${assemble "holder-only-config-etc-thing-conf" "value\n"}:/etc/thing.conf"
          "BindReadOnlyPaths=/run/vars/holder/hostKey/key:/run/vars/holder/hostKey/key"
        ];
        theSameAsTheUnitIsShown = true;
        directories = [ ];
        theUnitItProbesDeclaresThem = [
          "CacheDirectory"
          "RuntimeDirectory"
          "StateDirectory"
        ];
      };
    };

  # A probe and its bound are unit fields, so they are in the entry's key and in
  # the digest taken over what the artifact holds: a changed probe is a new
  # image and is replaced at the next apply rather than compared equal.
  testAChangedProbeIsADifferentImage =
    let
      versionOf = implementation: (readOf { } implementation).version;
      imageOf = implementation: (reader.attachment (readOf { } implementation)).image;
      keyOf = implementation: (planned { } implementation).plan."svc:only@one".key;
      changedCommand = probing { command = "${borgbackup}/bin/borg check --repository-only"; };
      changedBound = probing { timeout = "45s"; };
    in
    {
      expr = {
        commandMovesTheDigest = versionOf (probing { }) != versionOf changedCommand;
        boundMovesTheDigest = versionOf (probing { }) != versionOf changedBound;
        andTheImageFileWithIt = imageOf (probing { }) != imageOf changedCommand;
        rebuiltIsEqual = versionOf (probing { }) == versionOf (probing { });
        unprobedDiffers = versionOf simple != versionOf (probing { });
        # The key moves too, the fields being the unit's, which is what makes a
        # changed probe a new generation before it is a new image.
        commandMovesTheKey = keyOf (probing { }) != keyOf changedCommand;
        boundMovesTheKey = keyOf (probing { }) != keyOf changedBound;
      };
      expected = {
        commandMovesTheDigest = true;
        boundMovesTheDigest = true;
        andTheImageFileWithIt = true;
        rebuiltIsEqual = true;
        unprobedDiffers = true;
        commandMovesTheKey = true;
        boundMovesTheKey = true;
      };
    };

  # The attachment's unit list is what the attach script starts, so the probe
  # runs at attach time and a probe that fails fails the step. Nothing rolls
  # back: there is no generation to return to, and the machine keeps running
  # what it holds.
  testTheProbeIsAttachedAndStartedWithTheEntrysUnits =
    let
      result = (planned { } (probing { })).result;
      built = builtFrom { } result;
      attachment = built.attachment;
      words = concatStringsSep " " (map (unit: "'${unit}'") attachment.units);
    in
    {
      expr = {
        inherit (attachment) units;
        unprobed = (reader.attachment (readOf { } simple)).units;
        # The file list the artifact writes and the list the attachment starts
        # are one list, which is the point of deriving the name once.
        carriedByTheImage = planner.util.sortStrings (map (f: f.file) (reader.renderedUnits built.image));
        started = hasInfix "systemctl start ${words}" built.attach;
        theProbeIsOneOfTheStartedWords = hasInfix "'svc-only-health.service'" words;
        # And no rollback: nothing in the step that starts them detaches on a
        # failure, because an image has no previous generation.
        detachesOnFailure = hasInfix "portablectl detach" (
          builtins.concatStringsSep "\n" (
            filter (line: hasInfix "systemctl start" line) (support.lines built.attach)
          )
        );
      };
      expected = {
        units = [
          "svc-only-health.service"
          "svc-only-only.service"
        ];
        unprobed = [ "svc-only-only.service" ];
        carriedByTheImage = [
          "svc-only-health.service"
          "svc-only-only.service"
        ];
        started = true;
        theProbeIsOneOfTheStartedWords = true;
        detachesOnFailure = false;
      };
    };

  # The four conditions this builder refuses a probe under, each reachable only
  # from a hand-written plan: every refusal the planner rows about withholds
  # both fields, so no plan a deployment produced can carry one of these. A
  # record is written rather than declared for that reason, the way the
  # directive table's own refusal is.
  testAProbeNoRenderingIsHonestAbout =
    let
      recording =
        record:
        let
          p = planned { } simple;
          entry = p.plan.${p.key};
        in
        p.plan
        // {
          ${p.key} = entry // {
            units.only = entry.units.only // record;
          };
        };
      twoProbes =
        let
          p = planned { } (probing { });
          entry = p.plan.${p.key};
        in
        p.plan
        // {
          ${p.key} = entry // {
            units = entry.units // {
              second = entry.units.only;
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
        withoutTimeout = raises (
          readAs (recording {
            probe = "${borgbackup}/bin/borg check";
          })
        );
        withoutProbe = raises (
          readAs (recording {
            probeTimeout = "30s";
          })
        );
        unbounded = raises (
          readAs (recording {
            probe = "${borgbackup}/bin/borg check";
            probeTimeout = "0s";
          })
        );
        declaredTwice = raises (readAs twoProbes);
        # The same two units with one probe between them is the ordinary case,
        # so the refusal above is about the second statement and not about the
        # second unit.
        oneOfTwo = raises (
          readAs (
            let
              p = planned { } (probing { });
              entry = p.plan.${p.key};
            in
            p.plan
            // {
              ${p.key} = entry // {
                units = entry.units // {
                  second = removeAttrs entry.units.only [
                    "probe"
                    "probeTimeout"
                  ];
                };
              };
            }
          )
        );
        # A bound the spelling of zero does not reach is rendered, so the
        # refusal is over the spelling and not over the pair.
        bounded = raises (
          readAs (recording {
            probe = "${borgbackup}/bin/borg check";
            probeTimeout = "30s";
          })
        );
        accounted = map (account: account.id) [
          reader.accounts.probeWithoutTimeout
          reader.accounts.probeTimeoutWithoutProbe
          reader.accounts.probeTimeoutUnbounded
          reader.accounts.probeDeclaredTwice
        ];
      };
      expected = {
        withoutTimeout = true;
        withoutProbe = true;
        unbounded = true;
        declaredTwice = true;
        oneOfTwo = false;
        bounded = false;
        accounted = [
          "unit-probe-without-timeout"
          "unit-probe-timeout-without-probe"
          "unit-probe-timeout-unbounded"
          "unit-probe-declared-twice"
        ];
      };
    };
}
