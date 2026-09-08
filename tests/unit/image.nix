# The image builder's reading of a plan entry: what it derives, what it
# renders and what it refuses.
#
# One test per scenario of specs/realiser/portable-service-image/spec.md that a
# pure evaluation can observe. The scenarios about the bytes of a built image,
# and about what attaching one does on a machine, are asserted by
# tests/e2e/portable-image/test_portable_image.py against the artifact
# `.#planner-e2e-portable-image` builds, because a squashfs and a shell script
# are not values.
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

  # One member, placed on one machine, whose implementation is the attribute
  # set the caller wrote. The reading is over the entry that produces.
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

  # A refusal raises: the builder produces bytes, and a fact nobody wrote is
  # worse than no image. `deepSeq` because a refusal guards fields a lazy read
  # would leave unforced.
  #
  # `tryEval` hands back no message, so what the sentence names is asserted by
  # the image check, which runs a refused build and reads its stderr. Here the
  # condition that produces the refusal is what each case asserts.
  raises = value: !(tryEval (builtins.deepSeq value value)).success;

  simple = _: {
    closure = [ borgbackup ];
    units.only.command = "${borgbackup}/bin/borg serve";
  };

  # An image is a function of its entry. The three claims below share one
  # deployment: a rebuild of the same entry, an edit to a configuration file's
  # recipe, and an edit to a unit's own field.
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
  # A placed entry read as an image: the name and version come from the entry,
  # the units from its units, and nothing else is consulted.
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

  # The plan a realiser reads is data. Nothing in it is a function and nothing
  # is a derivation, so reading one builds nothing: an image is a derivation
  # over the plan's values and never a step of evaluating the plan.
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

  # Two placements of one service on machines whose platform records differ are
  # two images: the platform is part of what the version is a digest of, so the
  # names differ without anything else being said.
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

  # A machine running another service manager is refused at build time: this
  # builder emits systemd units, and an image of them is nothing the machine
  # the plan names could attach.
  testAnImageMeetsADifferentServiceManager = {
    expr = raises (
      readOf {
        machines = laptopMachines;
        machine = "laptop";
      } simple
    );
    expected = true;
  };

  # A fact the entry does not record is a refusal, not a default: an unplaced
  # member's entry records no target, no closure and no units.
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

  # A store path a unit names and the declared roots do not contain fails the
  # read, because the roots are the population list and a missing one is a
  # command that cannot run inside the image.
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

  # A plan naming another store directory is read against that directory: a
  # root under it is a root, and a root under the builder's own is not.
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

  # Two entries of one instance on one machine, each with a unit of one name:
  # the prefix is the entry's instance and service, so the two unit files
  # cannot collide.
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

  # An apply-and-exit unit renders the three fields it recorded and no restart
  # policy, because the vocabulary has none and the builder invents nothing.
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

  # Two units of one entry with different values for one variable: each unit
  # file carries its own value and neither carries the other's.
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

  # An ordering renders as an ordering: `After=` without `Requires=`, so
  # starting the ordered unit does not pull in the one it is ordered against.
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

  # A scheduled unit is a service and a timer, both prefixed, and the timer
  # names the service it triggers.
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

  # A systemd extension's recorded fields are rendered as the directives they
  # name, in the same unit file as the portable fields.
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

  # An extension recorded for a backend this builder does not render fails the
  # read rather than being dropped. The plan carries the fields under their own
  # backend, which is what makes the refusal possible at all.
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

  # A field the builder has no directive for fails the read: an extension
  # exists to add a field, so a unit that merely lacks one is worse than none.
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

  # A secret reaches the units from the host: the image carries no bytes of it,
  # the attachment shows it at the path the plan records, and a module
  # declaring that path as a closure root is refused.
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

  # A recipe carrying a reference is assembled on the host: the attachment
  # names the file at its recorded path and its staged source, and no fragment
  # is a value the image carries.
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

  # The description is data derived from the entry: the units, the profile, the
  # target and every host path shown, and nothing the entry does not imply.
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

  # The profile is stated, and an entry needing what it denies fails the build.
  # `default`, `nonetwork` and `strict` all carry `DynamicUser=yes`, so a unit
  # naming a host user is refused under each of them and accepted under
  # `trusted`.
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

  # A secret shown to a unit needs a profile that does not remap its uid:
  # `PrivateUsers=yes` is in the three restricted profiles and not in
  # `trusted`, so an entry reading a root-only file is refused under them.
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

  # The recipe's content never enters the image, so the version - which names
  # the image, and so its bytes - does not move when the recipe does. The key
  # does move, because the entry is what changed.
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

  # A unit's own field is part of the image, so editing one moves that entry's
  # key and its version, and nothing about the entry beside it.
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

  # A setting one service reads and another does not: the second service's
  # image is a function of its own entry, so nothing about it moves.
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

  # An entry with no unit is nothing to attach, and the read says so rather
  # than producing an image of an identity file alone.
  testAnEntryWithNoUnit = {
    expr = raises (
      readOf { } (_: {
        closure = [ ];
      })
    );
    expected = true;
  };
}
