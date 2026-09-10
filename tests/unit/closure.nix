{ planner, support }:
let
  inherit (builtins)
    attrNames
    length
    ;

  inherit (support)
    countById
    evidenceById
    hasInfix
    messageById
    planOf
    publicString
    rowIds
    severityById
    soleRoot
    subjectsById
    ;

  inherit (support.worked) openssh borgbackup;

  inherit (planner.util) storePathsIn;

  elsewhere = "/data/nix/store";

  relocated = "${elsewhere}/1w9k3zc7yq2mb5xj8vdl4rns6fga0h1p-openssh-9.8p1";

  pub = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
  };

  placed =
    args: implementation:
    planOf (
      {
        instances.svc = {
          module = soleRoot {
            module = _: {
              impl = implementation;
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      }
      // args
    );

  entryOf = result: result.plan."svc:only@one";

  pinned = {
    key = "/nixpkgs";
    locked = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      rev = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678";
      narHash = "sha256-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=";
    };
  };

  withPin =
    pin:
    planOf {
      instances.svc = {
        module = soleRoot {
          module = _: {
            inherit pin;
            impl = _: {
              closure = [ openssh ];
              units.only.command = "${openssh}/bin/sshd";
            };
          };
        };
        placement.every.only.machines = [ "one" ];
      };
    };

  generator = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate-token.drv";

  withProgram = planOf {
    instances.svc = {
      module = soleRoot {
        module = _: {
          vars.token = {
            program = generator;
            files."key".secrecy = "secret";
          };
          impl =
            { vars, ... }:
            {
              closure = [ openssh ];
              units.only = {
                command = "${openssh}/bin/sshd";
                env.KEYFILE = vars.token."key".path;
              };
            };
        };
      };
      placement.every.only.machines = [ "one" ];
    };
    varsState."svc:vars/token@one"."key".present = true;
  };
in
{
  # The grammar is Nix's own: the store directory, 32 base-32 characters without e,
  # o, t and u, a hyphen and a name. That is what stops a package name reading as a
  # store path.
  testAStorePathIsRecognisedByItsGrammar =
    let
      recognise = storePathsIn "/nix/store";
    in
    {
      expr = {
        genuine = recognise "run ${openssh}/bin/sshd now";
        outsideTheAlphabet = recognise "/nix/store/etoulk3zc7yq2mb5xj8vdl4rns6fga0h1p-openssh";
        shortHash = recognise "/nix/store/1w9k3zc7yq2mb5xj8vdl4rns6fga0h1-openssh-9.8p1";
        twoInOneString = recognise "${openssh}/bin/ssh -c ${borgbackup}/bin/borg";
        pathInsideARoot = recognise "${openssh}/bin/sshd";
        notAStorePath = recognise "/etc/ssh/sshd_config";
      };
      expected = {
        genuine = [ openssh ];
        outsideTheAlphabet = [ ];
        shortHash = [ ];
        twoInOneString = [
          openssh
          borgbackup
        ];
        pathInsideARoot = [ openssh ];
        notAStorePath = [ ];
      };
    };

  testADeploymentPlannedAgainstARelocatedStore =
    let
      result = placed { storeDir = elsewhere; } (_: {
        closure = [ relocated ];
        units.only = {
          command = "${relocated}/bin/sshd";
          env.DEFAULT_STORE_PATH = "${openssh}/bin/ssh";
        };
      });
      entry = entryOf result;
    in
    {
      expr = {
        storeDir = entry.storeDir;
        closure = entry.closure;
        rows = result.diagnostics;
      };
      expected = {
        storeDir = elsewhere;
        closure = [ relocated ];
        rows = [ ];
      };
    };

  testTheDefaultStoreDirectory =
    let
      result = placed { } (_: {
        closure = [ openssh ];
        units.only.command = "${openssh}/bin/sshd";
      });
    in
    {
      expr = {
        storeDir = (entryOf result).storeDir;
        isBuiltinsStoreDir = (entryOf result).storeDir == builtins.storeDir;
        rows = result.diagnostics;
      };
      expected = {
        storeDir = builtins.storeDir;
        isBuiltinsStoreDir = true;
        rows = [ ];
      };
    };

  testAnAbsolutePathOutsideTheStoreDirectory =
    let
      result = placed { } (_: {
        units.only = {
          command = "/usr/bin/env sshd";
          env.CONF = "/etc/ssh/sshd_config";
        };
      });
    in
    {
      expr = {
        closure = (entryOf result).closure or [ ];
        rows = result.diagnostics;
      };
      expected = {
        closure = [ ];
        rows = [ ];
      };
    };

  testAModuleDeclaresTwoRoots =
    let
      result = placed { } (_: {
        closure = [
          openssh
          borgbackup
        ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          env.BORG_RSH = "${openssh}/bin/ssh";
        };
      });
    in
    {
      expr = {
        closure = (entryOf result).closure;
        rows = result.diagnostics;
      };
      expected = {
        closure = [
          openssh
          borgbackup
        ];
        rows = [ ];
      };
    };

  testTheClosureNamesRootsAndNotPathsInsideThem =
    let
      result = placed { } (_: {
        closure = [ openssh ];
        units.only.command = "${openssh}/bin/sshd -f ${openssh}/etc/sshd_config";
      });
    in
    {
      expr = {
        closure = (entryOf result).closure;
        rows = result.diagnostics;
      };
      expected = {
        closure = [ openssh ];
        rows = [ ];
      };
    };

  testAPackageInACommandIsNotDeclared =
    let
      result = placed { } (_: {
        units.only.command = "${openssh}/bin/sshd";
      });
      message = messageById "closure-path-undeclared" result;
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "closure-path-undeclared" result;
        subjects = subjectsById "closure-path-undeclared" result;
        namesThePath = hasInfix openssh message;
        namesWhere = hasInfix "unit `only`" message;
        entryIsInThePlan = result.plan ? "svc:only@one";
      };
      expected = {
        rows = [ "closure-path-undeclared" ];
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesThePath = true;
        namesWhere = true;
        entryIsInThePlan = true;
      };
    };

  testAPackageNamedOnlyByAConfigurationFileIsNotDeclared =
    let
      result = placed { } (_: {
        units.only.command = "/bin/true";
        configData."/etc/thing.conf" = {
          mode = "0444";
          reload = [ "only" ];
          render = [ { text = "ssh = ${openssh}/bin/ssh\n"; } ];
        };
      });
      message = messageById "closure-path-undeclared" result;
    in
    {
      expr = {
        rows = rowIds result;
        namesThePath = hasInfix openssh message;
        namesTheFile = hasInfix "configuration file `/etc/thing.conf`" message;
        entryIsInThePlan = result.plan ? "svc:only@one";
      };
      expected = {
        rows = [ "closure-path-undeclared" ];
        namesThePath = true;
        namesTheFile = true;
        entryIsInThePlan = true;
      };
    };

  testAPackageNamedOnlyByAnExportValueIsNotDeclared =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              provides.thing.interface = pub;
              impl = _: {
                provides.thing.exports.publicKey = "${openssh}/share/key.pub";
                units.only.command = "/bin/true";
              };
            };
            provides = [ "thing" ];
          };
          placement.every.only.machines = [ "one" ];
          exposes = [ "thing" ];
        };
      };
      message = messageById "closure-path-undeclared" result;
    in
    {
      expr = {
        rows = rowIds result;
        namesThePath = hasInfix openssh message;
        namesTheExport = hasInfix "export `thing.publicKey`" message;
      };
      expected = {
        rows = [ "closure-path-undeclared" ];
        namesThePath = true;
        namesTheExport = true;
      };
    };

  testADeclaredRootNothingMentions =
    let
      result = placed { } (_: {
        closure = [
          openssh
          borgbackup
        ];
        units.only.command = "${openssh}/bin/sshd";
      });
    in
    {
      expr = {
        rows = rowIds result;
        severity = severityById "closure-root-unmentioned" result;
        namesTheRoot = hasInfix borgbackup (messageById "closure-root-unmentioned" result);
        closure = (entryOf result).closure;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "closure-root-unmentioned" ];
        severity = "warning";
        namesTheRoot = true;
        closure = [
          openssh
          borgbackup
        ];
        applicable = true;
      };
    };

  testAConsistentEntry =
    let
      result = placed { } (_: {
        closure = [
          openssh
          borgbackup
        ];
        units.only = {
          command = "${borgbackup}/bin/borg serve";
          env.BORG_RSH = "${openssh}/bin/ssh";
        };
      });
    in
    {
      expr = rowIds result;
      expected = [ ];
    };

  testTwoStorePathsInOneString =
    let
      result = placed { } (_: {
        units.only.command = "${borgbackup}/bin/borg --rsh ${openssh}/bin/ssh";
      });
    in
    {
      expr = {
        rowCount = countById "closure-path-undeclared" result;
        paths = builtins.sort (a: b: a < b) (
          map (r: if hasInfix openssh r.message then "openssh" else "borgbackup") (
            support.rowsById "closure-path-undeclared" result
          )
        );
      };
      expected = {
        rowCount = 2;
        paths = [
          "borgbackup"
          "openssh"
        ];
      };
    };

  testA32CharacterRunOutsideTheAlphabetIsNotAHash =
    let
      result = placed { } (_: {
        units.only.command = "/nix/store/thequickbrownfoxjumpsoverthelazy-name/bin/true";
      });
    in
    {
      expr = rowIds result;
      expected = [ ];
    };

  # The planner records a pin and verifies nothing: it reads no lockfile and builds
  # nothing, so a path the pin did not produce is not a row.
  testAModuleDeclaresAFullySpecifiedPin =
    let
      result = withPin pinned;
      entry = result.plan."svc:only@one";
    in
    {
      expr = {
        pin = entry.pin;
        rows = result.diagnostics;
      };
      expected = {
        pin = pinned;
        rows = [ ];
      };
    };

  testAPinNamesNoRevision =
    let
      result = withPin {
        key = "/nixpkgs";
        locked = removeAttrs pinned.locked [ "rev" ];
      };
      message = messageById "pin-underspecified" result;
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`rev`" message;
        namesTheModule = hasInfix "the pin of" message;
        entryIsInThePlan = result.plan ? "svc:only@one";
        pinRecorded = result.plan."svc:only@one" ? pin;
      };
      expected = {
        rows = [ "pin-underspecified" ];
        namesTheField = true;
        namesTheModule = true;
        entryIsInThePlan = true;
        pinRecorded = false;
      };
    };

  testAPinNamesNoContentHash =
    let
      result = withPin {
        key = "/nixpkgs";
        locked = removeAttrs pinned.locked [ "narHash" ];
      };
    in
    {
      expr = {
        rows = rowIds result;
        namesTheField = hasInfix "`narHash`" (messageById "pin-underspecified" result);
        evidenceNamesTheDeclared = hasInfix "`rev`" (evidenceById "pin-underspecified" result);
      };
      expected = {
        rows = [ "pin-underspecified" ];
        namesTheField = true;
        evidenceNamesTheDeclared = true;
      };
    };

  testEveryServiceResolvedToOneSource =
    let
      shared =
        pin:
        planOf {
          instances = {
            first = {
              module = soleRoot {
                module = _: {
                  inherit pin;
                  impl = _: {
                    units.only.command = "/bin/first";
                  };
                };
              };
              placement.every.only.machines = [ "one" ];
            };
            second = {
              module = soleRoot {
                module = _: {
                  inherit pin;
                  impl = _: {
                    units.only.command = "/bin/second";
                  };
                };
              };
              placement.every.only.machines = [ "two" ];
            };
          };
        };
      result = shared pinned;
    in
    {
      expr = {
        keys = [
          result.plan."first:only@one".pin.key
          result.plan."second:only@two".pin.key
        ];
        equal = result.plan."first:only@one".pin == result.plan."second:only@two".pin;
        rows = result.diagnostics;
      };
      expected = {
        keys = [
          "/nixpkgs"
          "/nixpkgs"
        ];
        equal = true;
        rows = [ ];
      };
    };

  testServicesResolvedToDifferentSources =
    let
      deployment =
        secondPin:
        planOf {
          instances = {
            first = {
              module = soleRoot {
                module = _: {
                  pin = pinned;
                  impl = _: {
                    units.only.command = "/bin/first";
                  };
                };
              };
              placement.every.only.machines = [ "one" ];
            };
            second = {
              module = soleRoot {
                module = _: {
                  pin = secondPin;
                  impl = _: {
                    units.only.command = "/bin/second";
                  };
                };
              };
              placement.every.only.machines = [ "two" ];
            };
          };
        };
      other = {
        key = "/treefmt-nix/nixpkgs";
        locked = pinned.locked // {
          rev = "ffffffffffffffffffffffffffffffffffffffff";
        };
      };
      before = deployment other;
      after = deployment (
        other
        // {
          locked = other.locked // {
            rev = "0000000000000000000000000000000000000000";
          };
        }
      );
    in
    {
      expr = {
        keysDiffer = before.plan."first:only@one".pin.key != before.plan."second:only@two".pin.key;
        unrelatedKeyUnchanged = before.plan."first:only@one".key == after.plan."first:only@one".key;
        repinnedKeyChanged = before.plan."second:only@two".key != after.plan."second:only@two".key;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        keysDiffer = true;
        unrelatedKeyUnchanged = true;
        repinnedKeyChanged = true;
        rows = [ ];
      };
    };

  testAPinChangesAndTheStorePathsMove =
    let
      withPinned =
        { rev, root }:
        planOf {
          instances.svc = {
            module = soleRoot {
              module = _: {
                pin = {
                  key = "/nixpkgs";
                  locked = pinned.locked // {
                    inherit rev;
                  };
                };
                impl = _: {
                  closure = [ root ];
                  units.only.command = "${root}/bin/borg";
                };
              };
            };
            placement.every.only.machines = [ "one" ];
          };
        };
      before = withPinned {
        rev = pinned.locked.rev;
        root = borgbackup;
      };
      after = withPinned {
        rev = "0000000000000000000000000000000000000000";
        root = openssh;
      };
      entryOfPlan = result: result.plan."svc:only@one";
    in
    {
      expr = {
        revisions = [
          (entryOfPlan before).pin.locked.rev
          (entryOfPlan after).pin.locked.rev
        ];
        closures = [
          (entryOfPlan before).closure
          (entryOfPlan after).closure
        ];
        keyMoved = (entryOfPlan before).key != (entryOfPlan after).key;
        rows = before.diagnostics ++ after.diagnostics;
      };
      expected = {
        revisions = [
          pinned.locked.rev
          "0000000000000000000000000000000000000000"
        ];
        closures = [
          [ borgbackup ]
          [ openssh ]
        ];
        keyMoved = true;
        rows = [ ];
      };
    };

  testThePlannerDoesNotVerifyAPin =
    let
      result = planOf {
        instances.svc = {
          module = soleRoot {
            module = _: {
              pin = pinned;
              impl = _: {
                closure = [ borgbackup ];
                units.only.command = "${borgbackup}/bin/borg";
              };
            };
          };
          placement.every.only.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        pin = result.plan."svc:only@one".pin.locked.rev;
        closure = result.plan."svc:only@one".closure;
        rows = rowIds result;
      };
      expected = {
        pin = pinned.locked.rev;
        closure = [ borgbackup ];
        rows = [ ];
      };
    };

  testAPinWithNoLockKey =
    let
      result = withPin { locked = pinned.locked; };
    in
    {
      expr = {
        rows = rowIds result;
        namesTheKey = hasInfix "no lock key" (messageById "pin-malformed" result);
        count = length (attrNames result.plan);
      };
      expected = {
        rows = [ "pin-malformed" ];
        namesTheKey = true;
        count = 2;
      };
    };

  # A generator runs where the plan is read - on the machine holding the values,
  # never on one receiving them - so the program it declares is the one store path
  # in a plan that is not held against a declared closure.
  testTheProgramIsMentionedWithoutEnteringAClosure =
    let
      result = withProgram;
      value = result.plan."svc:vars/token@one";
      entry = entryOf result;
    in
    {
      expr = {
        rows = result.diagnostics;
        mentioned = value.program;
        inTheClosure = builtins.elem generator entry.closure;
        theEntryStillDeclaresItsOwn = entry.closure;
        # The file's path is a mention like any other, and the value's own entry
        # is what carries the program.
        theUnitNamesThePath = entry.units.only.env.KEYFILE;
      };
      expected = {
        rows = [ ];
        mentioned = generator;
        inTheClosure = false;
        theEntryStillDeclaresItsOwn = [ openssh ];
        theUnitNamesThePath = "/run/vars/svc/token/key";
      };
    };

  testAMachineIsGivenNoGenerator =
    let
      closures = builtins.concatLists (
        map (entry: entry.closure or [ ]) (builtins.attrValues withProgram.plan)
      );
    in
    {
      expr = {
        # Every closure of the plan, and the generator is in none of them.
        closures = planner.util.sortStrings (planner.util.uniqueStrings closures);
        theProgramIsInThePlan = hasInfix generator (builtins.toJSON withProgram.plan);
      };
      expected = {
        closures = [ openssh ];
        theProgramIsInThePlan = true;
      };
    };

  testADeclaredClosureRootIsNotAStorePath =
    let
      result = placed { } (_: {
        closure = [ "/opt/vendor/agent" ];
        units.only.command = "/opt/vendor/agent/bin/agent";
      });
    in
    {
      expr = {
        rows = countById "closure-root-outside-store" result;
        severity = severityById "closure-root-outside-store" result;
        subjects = subjectsById "closure-root-outside-store" result;
        namesTheRoot = hasInfix "/opt/vendor/agent" (messageById "closure-root-outside-store" result);
        namesTheStoreDirectory = hasInfix "/nix/store" (messageById "closure-root-outside-store" result);
        theEntryIsStillRead = (entryOf result).closure;
      };
      expected = {
        rows = 1;
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesTheRoot = true;
        namesTheStoreDirectory = true;
        theEntryIsStillRead = [ "/opt/vendor/agent" ];
      };
    };

  testADeclaredClosureRootArrivesByDelivery =
    let
      result = placed { } (_: {
        closure = [ openssh ];
        configData."/etc/svc/known_hosts" = {
          mode = "0444";
          reload = [ ];
          render = [ { ref = openssh; } ];
        };
        units.only.command = "/bin/true";
      });
    in
    {
      expr = {
        rows = countById "closure-root-is-delivered" result;
        severity = severityById "closure-root-is-delivered" result;
        subjects = subjectsById "closure-root-is-delivered" result;
        namesTheRoot = hasInfix openssh (messageById "closure-root-is-delivered" result);
        saysWhereTheBytesComeFrom = hasInfix "reach the units from the machine" (
          evidenceById "closure-root-is-delivered" result
        );
        theEntryIsStillRead = (entryOf result).closure;
      };
      expected = {
        rows = 1;
        severity = "error";
        subjects = [ "svc:only@one" ];
        namesTheRoot = true;
        saysWhereTheBytesComeFrom = true;
        theEntryIsStillRead = [ openssh ];
      };
    };
}
