# One attribute per verified break of an invariant this tree states about itself.
{
  planner,
  operatorSource,
  imageSource,
  flakeletSource,
  secretsSource,
}:
let
  machines.one = {
    address = "one.example:22";
    system = "x86_64-linux";
    serviceManager = "systemd";
    tags = [ "all" ];
  };

  greeting = planner.interface {
    name = "greeting";
    exports.text = {
      type = planner.korora.string;
    };
  };

  identity = planner.interface {
    name = "identity";
    exports.key = {
      type = planner.korora.secretRef;
      secrecy = "secret";
    };
  };

  # One member called `only`, placed on the one machine.
  onOne = module: {
    module =
      { service, ... }:
      {
        services.only = service "only" { inherit module; };
      };
    placement.every.only = {
      tags = [ "all" ];
    };
  };

  # The same, with the member's capability re-exported by the root.
  exposing = capability: module: {
    module =
      { service, ... }:
      let
        services.only = service "only" { inherit module; };
      in
      {
        inherit services;
        provides.${capability} = services.only.provides.${capability};
      };
    placement.every.only = {
      tags = [ "all" ];
    };
    exposes = [ capability ];
  };

  planOf = instances: planner.mkPlan { inherit machines instances; };

  # Each directory is its own store path here, so a relative import out of one
  # would resolve outside the store: the two readings the operator's own takes
  # are handed over rather than defaulted.
  imageReader = import (imageSource + "/read.nix") { inherit planner; };

  flakeletReader = import (flakeletSource + "/read.nix") {
    inherit planner;
    reader = imageReader;
  };

  reader = import (operatorSource + "/read.nix") {
    inherit planner imageReader flakeletReader;
  };

  secretsReader = import (secretsSource + "/read.nix") { inherit planner; };

  # The operator's reading of one plan under a realisation statement, as rows.
  readingOf =
    result: realise:
    (reader.read {
      inherit (result) plan diagnostics;
      inherit realise;
      storeDir = builtins.storeDir;
    }).diagnostics;
in
{
  # CLAUDE.md, Purity and totality: "every value a declaration wrote is read for
  # its kind before the reading indexes into it".
  # `lib/module.nix:1431` computes `impl-missing` for a non-function `impl` and
  # `lib/module.nix:1457` records the value anyway, so `lib/resolve.nix:1445`
  # calls it: `attempt to call something which is not a function but a set`.
  anImplementationThatIsNotAFunctionIsARow = builtins.deepSeq (planOf {
    app = onOne (_: {
      provides.greeting = {
        interface = greeting;
      };
      impl = {
        provides.greeting.exports.text = "hi";
        units.main.command = "/bin/true";
      };
    });
  }) "ok";

  # CLAUDE.md, Purity and totality: "A guard is not a check"; the implementation
  # half is forced under `diag.guard` at `lib/resolve.nix:1452`.
  # `lib/resolve.nix:1461` reads `impl == null` as the first operand of its
  # disjunction, which forces the application again outside that guard, so the
  # row the guard produced is never reached and the raise propagates.
  anImplementationThatRaisesIsAGuardedRow = builtins.deepSeq (planOf {
    app = onOne (_: {
      impl = _: throw "the module author's own mistake";
    });
  }) "ok";

  # CLAUDE.md, Purity and totality: "a function called without an argument its
  # pattern requires" is uncatchable, which `lib/compose.nix:44-58` answers
  # before applying a module.
  # `lib/resolve.nix:1445` applies `impl` with no such answer and `implArgs`
  # carries eight names, so a pattern without `...` ends the evaluation:
  # `function 'impl' called with unexpected argument`.
  anImplementationWithStrictFormalsIsARow = builtins.deepSeq (planOf {
    app = onOne (_: {
      impl =
        { settings }:
        {
          units.main = {
            command = "/bin/true";
            env.KNOBS = builtins.toJSON settings;
          };
        };
    });
  }) "ok";

  # CLAUDE.md, Purity and totality: a generated file's record and every value a
  # declaration wrote "pass through" a kind check before the reading indexes.
  # `lib/module.nix:1193-1207` checks a recipe item's keyset and never the kind
  # of the value inside it, and `lib/plan.nix:410` concatenates the fragments:
  # `cannot coerce an integer to a string: 5`.
  aRecipeFragmentHoldingANonStringIsARow = builtins.deepSeq (planOf {
    app = onOne (_: {
      impl = _: {
        units.main.command = "/bin/true";
        configData."/etc/app.conf" = {
          mode = "0444";
          render = [ { text = 5; } ];
        };
      };
    });
  }) "ok";

  # `lib/resolve.nix:720-723`: "A root may return anything under
  # `services.<name>`, and the readings below index it. Dropped rather than
  # reported and then handed over".
  # The member is guarded and the container is not: `lib/resolve.nix:717` is
  # `root.services or { }`, and `:718` calls `attrNames` on it, so a `services`
  # of another kind is `expected a set but found a string`.
  aRootReturningServicesOfAnotherKindIsARow = builtins.deepSeq (planOf {
    app = {
      module = _: { services = "only"; };
      placement.every.only = {
        tags = [ "all" ];
      };
    };
  }) "ok";

  # CLAUDE.md, Purity and totality: "`lib/` never raises"; and Diagnostics: "the
  # row, `applicable = false` and the realiser's own refusal are the three things
  # that stop the bytes".
  # A settings value is never read for its kind and `lib/plan.nix:939-1004` keys
  # the entry with `toJSON` of it, so this deployment answers `applicable = true`
  # with an empty table and a plan whose key raises `cannot convert a function to
  # JSON`.
  aSettingsKnobHoldingAFunctionIsARow = builtins.deepSeq (planner.mkPlan {
    inherit machines;
    instances.app = {
      module =
        { service, ... }:
        {
          services.only = service "only" {
            module = _: {
              impl = _: {
                units.main.command = "/bin/true";
              };
            };
            defaults.format = null;
          };
        };
      placement.every.only = {
        tags = [ "all" ];
      };
      settings.only.format = value: "${value}!";
    };
  }) "ok";

  # CLAUDE.md, Interfaces, composition, reads: "no other refused read is guarded:
  # an unwired slot is `slot-unwired` before any implementation runs".
  # The row does fire, and producing it does not stop the implementation from
  # being read: `attribute 'peer' missing`, so `applicable` cannot be computed
  # and the table that explains the mistake cannot be printed.
  anUnwiredSlotStillLeavesATableToPrint = builtins.deepSeq (planOf {
    app = onOne (_: {
      uses.peer = {
        interface = greeting;
      };
      impl =
        { results, ... }:
        {
          units.main.command = "/bin/echo ${results.peer.text}";
        };
    });
  }) "ok";

  # `lib/resolve.nix:144`: "the half of a declaration a deployment writes is read
  # with the tolerance the half a module writes is read with, so a value of the
  # wrong kind is a row and the rest of the deployment is still read".
  # `lib/default.nix:102-124` hands `machines` to the resolver with neither
  # `declaredField` nor `declaredRecord` above it: `expected a set but found a
  # list`.
  aMachineRegistryOfAnotherKindIsARow = builtins.deepSeq (planner.mkPlan {
    machines = [
      {
        name = "one";
        address = "one.example:22";
        system = "x86_64-linux";
        serviceManager = "systemd";
        tags = [ "all" ];
      }
    ];
    instances = { };
  }) "ok";

  # The same reading, for the other half of the deployment: `instances` of
  # another kind reaches `util.filterAttrs` at `lib/resolve.nix:2260` and answers
  # `expected a set but found a string`.
  anInstanceTableOfAnotherKindIsARow = builtins.deepSeq (planner.mkPlan {
    inherit machines;
    instances = "deployment/instances.nix";
  }) "ok";

  # CLAUDE.md, Interfaces, composition, reads: "The `interfaces` argument is
  # attribution, never a registry", so a malformed one decides nothing.
  # `lib/default.nix:113` hands it to `interface.registry` unread, and forcing
  # the table answers `expected a set but found a string`.
  anInterfaceAttributionOfAnotherKindIsARow = builtins.deepSeq (planner.mkPlan {
    inherit machines;
    instances.app = onOne (_: {
      impl = _: {
        units.main.command = "/bin/true";
      };
    });
    interfaces = "interfaces.nix";
  }) "ok";

  # CLAUDE.md, Purity and totality: "`storeDir` is an argument. Never write
  # `/nix/store` into `lib/`."
  # It is read for no kind either: a number reaches `util.escapeRegex` through
  # `util.storePathsIn` and answers `expected a string but found an integer`.
  aStoreDirectoryOfAnotherKindIsARow = builtins.deepSeq (planner.mkPlan {
    inherit machines;
    instances.app = onOne (_: {
      impl = _: {
        units.main.command = "/bin/true";
      };
    });
    storeDir = 42;
  }) "ok";

  # CLAUDE.md, Keys and identity: "`varsState` is keyed by the value's entry ...
  # one value has one answer about whether it exists".
  # That answer is read as `fileState.present or false` at `lib/resolve.nix:1411`
  # - the `or` covers an absence and not a kind - and `lib/plan.nix:115` branches
  # on it: `expected a Boolean but found a string`. The table is empty and
  # `applicable` is true, so the raise is in the plan alone.
  aVarsStateAnswerOfAnotherKindIsARow = builtins.deepSeq (planner.mkPlan {
    inherit machines;
    instances.app = onOne (_: {
      vars.token = {
        files.value = {
          secrecy = "public";
        };
      };
      impl = _: {
        units.main.command = "/bin/true";
      };
    });
    varsState."app:vars/token@one".value = {
      present = "true";
      content = "s3cret";
    };
  }) "ok";

  # CLAUDE.md, Interfaces, composition, reads: "A secret export must publish a
  # generated file, never a bare value: `export-secret-not-a-reference`."
  # `lib/resolve.nix:1692` reads the marker `util.isVarsFile` answers yes to and
  # then indexes the record, so an export carrying `__varsFile` and not the rest
  # of the fields is `attribute 'deploy' missing` rather than that row.
  anExportCarryingTheVarsFileMarkerIsARow = builtins.deepSeq (planOf {
    owner = exposing "identity" (_: {
      provides.identity.interface = identity;
      impl = _: {
        provides.identity.exports.key = {
          __varsFile = true;
          path = "/run/vars/owner/only/key";
          secrecy = "secret";
          present = true;
        };
        units.only.command = "/bin/true";
      };
    });
    consumer =
      (onOne (_: {
        uses.far = {
          interface = identity;
          reads = [ "key" ];
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              env.P = results.far.key.path;
            };
          };
      }))
      // {
        wire.far = {
          instance = "owner";
          provides = "identity";
        };
      };
  }) "ok";

  # CLAUDE.md, Realisers: "`operator/read.nix` is on `lib/`'s side ... The
  # reading is total and every refusal it makes is a row".
  # A configuration file the planner refused for its missing `mode` is recorded
  # with `mode = null` (`lib/module.nix:1315`), and the reading the operator asks
  # for its denials interpolates that field (`operator/read.nix:313` reaching
  # `image/read.nix:329`): `cannot coerce null to a string`.
  aConfigurationFileWithNoModeIsARowInTheOperatorReading = builtins.deepSeq (readingOf (planOf {
    app = onOne (_: {
      impl =
        { instance, member, ... }:
        {
          units.main.command = "/bin/true";
          configData."/etc/${instance}-${member}.conf" = {
            render = [ { text = "hello"; } ];
          };
        };
    });
  }) { default.realiser = "flakelet"; }) "ok";

  # CLAUDE.md, Realisers: "Which realiser realises an entry is stated beside the
  # deployment", and the reading of that statement "is total and every refusal it
  # makes is a row" - an unknown name is `operator-entry-realiser-unknown`.
  # The statement is read for no kind, so a `realiser` that is not a string ends
  # the reading instead of earning that row.
  aRealiserStatementOfAnotherKindIsARow = builtins.deepSeq (readingOf (planOf {
    app = onOne (_: {
      impl = _: {
        units.main.command = "/bin/true";
      };
    });
  }) { default.realiser = 3; }) "ok";

  # CLAUDE.md, Realisers: "An `image` entry with no `profile` is
  # `operator-image-profile-missing`, never a profile the builder chose."
  # A `profile` of another kind is neither, and the image reader indexes its
  # profile table with it.
  aProfileStatementOfAnotherKindIsARow = builtins.deepSeq (readingOf
    (planOf {
      app = onOne (_: {
        impl = _: {
          units.main.command = "/bin/true";
        };
      });
    })
    {
      default = {
        realiser = "image";
        profile = 3;
      };
    }
  ) "ok";

  # CLAUDE.md, Realisers: the secrets reading's halves are "`rows` and
  # `generation` answer a table and raise nothing, `store`, `configuration` and
  # `deliveriesOf` refuse with the sentence that row states".
  # This one holds today: a value recording no `program` is one of the three
  # conditions reachable from an applicable plan, and the total half still
  # answers a table for it. Kept as the pin on that split.
  aSecretsReadingOfARefusedPlanStillAnswersATable = builtins.deepSeq (secretsReader.generation {
    plan =
      (planOf {
        app = onOne (_: {
          vars.token = {
            files.value = {
              secrecy = "secret";
            };
          };
          impl = _: {
            units.main.command = "/bin/true";
          };
        });
      }).plan;
  }) "ok";

  # CLAUDE.md, Purity and totality: "`lib/` never raises: every check returns a
  # row and evaluation stays total."
  # A row's message may name a store path - a closure root nothing mentions is
  # one - and `dedup` keys a row by its own text, where an attribute name may
  # carry no string context: `the string '…' is not allowed to refer to a store
  # path`, raised inside the table that exists to report it. Fixed by the
  # discard at that key; kept as the pin. The path is one this file was handed
  # rather than one written here, because interpolating it is what gives the
  # string the context the defect was about.
  aRowNamingAStorePathIsStillARow = builtins.deepSeq (planner.mkPlan {
    inherit machines;
    instances.app = onOne (_: {
      impl = _: {
        closure = [ "${imageSource}" ];
        units.main.command = "/bin/true";
      };
    });
  }) "ok";
}
