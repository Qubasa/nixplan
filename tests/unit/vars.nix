{ planner, support }:
let
  inherit (builtins)
    attrNames
    filter
    length
    ;

  inherit (support)
    countById
    evidenceById
    hasInfix
    messageById
    resolutionById
    rowIds
    soleRoot
    subjectsById
    ;

  # Three machines, because a shared value and a per-placement one only differ
  # once a member is placed more than once.
  machines = {
    alpha = {
      address = "alpha.example:22";
      tags = [ "fleet" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    beta = {
      address = "beta.example:22";
      tags = [ "fleet" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
    idle = {
      address = "idle.example:22";
      tags = [ "spare" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
    };
  };

  planOf = args: planner.mkPlan ({ inherit machines; } // args);

  secretRef = {
    type = planner.korora.secretRef;
    secrecy = "secret";
  };

  identity = planner.interface {
    name = "identity";
    exports.key = secretRef;
  };

  public = planner.interface {
    name = "label";
    exports.label = {
      type = planner.korora.string;
      secrecy = "public";
    };
  };

  # One owner, one generator, one file, and a unit that names its path. Every
  # test below varies exactly one thing about this.
  owner =
    {
      per ? null,
      deploy ? null,
      reads ? null,
      also ? { },
      openIt ? true,
    }:
    _: {
      vars = {
        app = {
          files."key".secrecy = "secret";
        }
        // (if per == null then { } else { inherit per; })
        // (if deploy == null then { } else { inherit deploy; })
        // (if reads == null then { } else { inherit reads; });
      }
      // also;
      provides.identity.interface = identity;
      impl =
        { vars, ... }:
        {
          provides.identity.exports.key = vars.app."key";
          units.only = {
            command = "/bin/true";
          }
          // (if openIt then { env.KEYFILE = vars.app."key".path; } else { });
        };
    };

  reader =
    {
      reads ? [ "key" ],
    }:
    _: {
      uses.far = {
        interface = identity;
        inherit reads;
      };
      impl =
        { results, ... }:
        {
          units.only = {
            command = "/bin/true";
            env.SAW = builtins.concatStringsSep "," (attrNames (results.far or { }));
          };
        };
    };

  # A generator declared through `vars.<name>` directly, so a test can write two
  # of them in two members of one root.
  bare = gen: _: {
    vars.${gen}.files."key".secrecy = "secret";
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  deployment =
    {
      ownerArgs ? { },
      ownerMachines ? [ "alpha" ],
      consumer ? null,
      consumerMachines ? [ "beta" ],
      varsState ? null,
    }:
    planOf {
      # A declared secret with no bytes is a row of its own, so the default is
      # generated: a test that is not about absence does not have to say so.
      varsState =
        if varsState != null then
          varsState
        else if (ownerArgs.per or "placement") == "instance" then
          { "holder:vars/app"."key".present = true; }
        else
          builtins.listToAttrs (
            map (m: {
              name = "holder:vars/app@${m}";
              value."key".present = true;
            }) ownerMachines
          );
      interfaces."interfaces/default.nix" = { inherit identity public; };
      instances = {
        holder = {
          module = soleRoot {
            module = owner ownerArgs;
            provides = [ "identity" ];
          };
          placement.every.only.machines = ownerMachines;
          exposes = [ "identity" ];
        };
      }
      // (
        if consumer == null then
          { }
        else
          {
            client = {
              module = soleRoot { module = consumer; };
              placement.every.only.machines = consumerMachines;
              wire.far = {
                instance = "holder";
                provides = "identity";
              };
            };
          }
      );
    };

  fleet =
    args:
    deployment (
      {
        ownerMachines = [
          "alpha"
          "beta"
        ];
      }
      // args
    );

  program = "/nix/store/9dm4x2vqk7z1n5bpr3jlfg8ys6cwh0az-generate-gen.drv";

  # A second generator beside `app`, so a test about the program it declares does
  # not have to restate the state of the first one.
  withGenerator =
    declared:
    deployment {
      ownerArgs.also.gen = {
        files."key".secrecy = "secret";
      }
      // declared;
      varsState = {
        "holder:vars/app@alpha"."key".present = true;
        "holder:vars/gen@alpha"."key".present = true;
      };
    };

  varsKeys = result: filter (k: hasInfix ":vars/" k) (attrNames result.plan);
in
{
  testAGeneratorStatesOneValueForTheInstance =
    let
      result = fleet { ownerArgs.per = "instance"; };
      entry = result.plan."holder:vars/app";
    in
    {
      expr = {
        rows = rowIds result;
        keys = varsKeys result;
        per = entry.per;
        path = entry.files."key".path;
        alphaSees = result.plan."holder:only@alpha".vars.app.files."key".path;
        betaSees = result.plan."holder:only@beta".vars.app.files."key".path;
      };
      expected = {
        rows = [ ];
        keys = [ "holder:vars/app" ];
        per = "instance";
        path = "/run/vars/holder/app/key";
        alphaSees = "/run/vars/holder/app/key";
        betaSees = "/run/vars/holder/app/key";
      };
    };

  testAGeneratorStatesOneValuePerPlacement =
    let
      result = fleet { ownerArgs.per = "placement"; };
    in
    {
      expr = {
        rows = rowIds result;
        keys = varsKeys result;
        per = result.plan."holder:vars/app@alpha".per;
        dependsOn = map (
          d: builtins.head (builtins.split "@" d)
        ) result.plan."holder:vars/app@alpha".dependsOn;
        keysDiffer = result.plan."holder:vars/app@alpha".key != result.plan."holder:vars/app@beta".key;
      };
      expected = {
        rows = [ ];
        keys = [
          "holder:vars/app@alpha"
          "holder:vars/app@beta"
        ];
        per = "placement";
        dependsOn = [ "machine:alpha" ];
        keysDiffer = true;
      };
    };

  testACardinalityOutsideTheDomain =
    let
      result = deployment { ownerArgs.per = "everywhere"; };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "vars-per-domain" result;
        namesWritten = hasInfix "`everywhere`" (messageById "vars-per-domain" result);
        namesBoth = hasInfix "`instance`, `placement`" (messageById "vars-per-domain" result);
        theRestIsPlanned = result.plan ? "machine:alpha";
        applicable = result.applicable;
      };
      expected = {
        rows = [ "vars-per-domain" ];
        subjects = [ "holder:only" ];
        namesWritten = true;
        namesBoth = true;
        theRestIsPlanned = true;
        applicable = false;
      };
    };

  testTwoMembersClaimOneGeneratorName =
    let
      result = planOf {
        instances.holder = {
          module = support.root {
            members = {
              first.module = bare "app";
              second.module = bare "app";
            };
          };
          placement.every = {
            first.machines = [
              "alpha"
              "beta"
            ];
            second.machines = [ "alpha" ];
          };
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById "vars-generator-claimed-twice" result;
        subjects = subjectsById "vars-generator-claimed-twice" result;
        namesBothMembers = hasInfix "`first`, `second`" (messageById "vars-generator-claimed-twice" result);
      };
      expected = {
        rows = [ "vars-generator-claimed-twice" ];
        count = 1;
        subjects = [ "holder:instance" ];
        namesBothMembers = true;
      };
    };

  testTheOwnerReceivesItsOwnValue =
    let
      result = fleet { };
    in
    {
      expr = {
        rows = rowIds result;
        alpha = result.plan."holder:vars/app@alpha".delivery;
        beta = result.plan."holder:vars/app@beta".delivery;
        reasons = result.plan."holder:vars/app@alpha".deliveryDerivedFrom;
      };
      expected = {
        rows = [ ];
        alpha = [ "alpha" ];
        beta = [ "beta" ];
        reasons = [ "holder:only@alpha owns it" ];
      };
    };

  testADeclaredReadAddsTheReadersMachine =
    let
      result = deployment { consumer = reader { }; };
      entry = result.plan."holder:vars/app@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        delivery = entry.delivery;
        reasons = entry.deliveryDerivedFrom;
        theConsumerSawIt = result.plan."client:only@beta".units.only.env.SAW;
      };
      expected = {
        rows = [ ];
        delivery = [
          "alpha"
          "beta"
        ];
        reasons = [
          "client:only@beta named key in uses.far.reads"
          "holder:only@alpha owns it"
        ];
        theConsumerSawIt = "key";
      };
    };

  testAnUndeclaredExportDeliversToNobody =
    let
      result = deployment { consumer = reader { reads = [ ]; }; };
      entry = result.plan."holder:vars/app@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        delivery = entry.delivery;
        absentFromResults = result.plan."client:only@beta".units.only.env.SAW;
        readValues = attrNames result.plan."client:only@beta".reads.far.values;
      };
      expected = {
        rows = [ ];
        delivery = [ "alpha" ];
        absentFromResults = "";
        readValues = [ ];
      };
    };

  testAMachineRunningNeitherIsNotInTheSet =
    let
      result = deployment { consumer = reader { }; };
    in
    {
      expr = {
        rows = rowIds result;
        delivery = result.plan."holder:vars/app@alpha".delivery;
        idleRunsSomething = filter (k: hasInfix "@idle" k) (attrNames result.plan);
      };
      expected = {
        rows = [ ];
        delivery = [
          "alpha"
          "beta"
        ];
        idleRunsSomething = [ ];
      };
    };

  testAValueNobodyReceives =
    let
      result = deployment {
        ownerArgs = {
          deploy = false;
          openIt = false;
        };
      };
      entry = result.plan."holder:vars/app@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        delivery = entry.delivery;
        reasons = entry.deliveryDerivedFrom;
        deploy = entry.deploy;
        theValueExists = attrNames entry.files;
      };
      expected = {
        rows = [ ];
        delivery = [ ];
        reasons = [ ];
        deploy = false;
        theValueExists = [ "key" ];
      };
    };

  testAUnitOpensAValueNobodyReceives =
    let
      result = deployment { ownerArgs.deploy = false; };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "vars-not-deployed-opened" result;
        namesTheFile = hasInfix "`app/key`" (resolutionById "vars-not-deployed-opened" result);
        namesTheUnit = hasInfix "unit `only`" (messageById "vars-not-deployed-opened" result);
        resolvesToNothing = hasInfix "holds nothing" (evidenceById "vars-not-deployed-opened" result);
      };
      expected = {
        rows = [ "vars-not-deployed-opened" ];
        subjects = [ "holder:only@alpha" ];
        namesTheFile = true;
        namesTheUnit = true;
        resolvesToNothing = true;
      };
    };

  testAConsumerReadsAValueNobodyReceives =
    let
      result = deployment {
        ownerArgs = {
          deploy = false;
          openIt = false;
        };
        consumer = reader { };
      };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "slot-reads-undeployed-value" result;
        namesTheSlot = hasInfix "`far`" (messageById "slot-reads-undeployed-value" result);
        namesTheExport = hasInfix "`key`" (messageById "slot-reads-undeployed-value" result);
        namesTheGenerator = hasInfix "generator `app`" (evidenceById "slot-reads-undeployed-value" result);
      };
      expected = {
        rows = [ "slot-reads-undeployed-value" ];
        subjects = [ "client:only" ];
        namesTheSlot = true;
        namesTheExport = true;
        namesTheGenerator = true;
      };
    };

  testAPublicFileOfAnUndeployedGeneratorStillTravels =
    let
      labelled = _: {
        vars.app = {
          deploy = false;
          files."label".secrecy = "public";
        };
        provides.label.interface = public;
        impl =
          { vars, ... }:
          {
            provides.label.exports.label = vars.app."label".content;
            units.only.command = "/bin/true";
          };
      };
      result = planOf {
        varsState."holder:vars/app@alpha"."label" = {
          present = true;
          content = "the-label";
        };
        interfaces."interfaces/default.nix" = { inherit identity public; };
        instances.holder = {
          module = soleRoot {
            module = labelled;
            provides = [ "label" ];
          };
          placement.every.only.machines = [ "alpha" ];
          exposes = [ "label" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        exported = result.plan."holder:only@alpha".provides.label.exports.label.value;
        delivery = result.plan."holder:vars/app@alpha".delivery;
      };
      expected = {
        rows = [ ];
        exported = "the-label";
        delivery = [ ];
      };
    };

  testAMachineSpecificValueReadsASharedOne =
    let
      result = fleet {
        ownerArgs = {
          per = "placement";
          reads = [ "ca" ];
          also.ca = {
            per = "instance";
            files."cert".secrecy = "secret";
          };
        };
      };
      shared = result.plan."holder:vars/ca";
    in
    {
      expr = {
        rows = rowIds result;
        reads = result.plan."holder:vars/app@alpha".reads;
        dependsOnTheShared =
          builtins.elem "holder:vars/ca#${shared.key}"
            result.plan."holder:vars/app@alpha".dependsOn;
        theSharedDependsOnNeither = shared.dependsOn or [ ];
      };
      expected = {
        rows = [ ];
        reads = [ "holder:vars/ca" ];
        dependsOnTheShared = true;
        theSharedDependsOnNeither = [ ];
      };
    };

  testASharedValueReadsAMachineSpecificOne =
    let
      result = fleet {
        ownerArgs = {
          per = "instance";
          reads = [ "host" ];
          also.host = {
            per = "placement";
            files."id".secrecy = "secret";
          };
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "vars-reads-arity" result;
        namesBoth =
          hasInfix "`app`" (messageById "vars-reads-arity" result)
          && hasInfix "`host`" (messageById "vars-reads-arity" result);
        namesCardinalities =
          hasInfix "`instance`" (messageById "vars-reads-arity" result)
          && hasInfix "`placement`" (messageById "vars-reads-arity" result);
        reversingWorks = hasInfix "the direction that works" (resolutionById "vars-reads-arity" result);
      };
      expected = {
        rows = [ "vars-reads-arity" ];
        subjects = [ "holder:only" ];
        namesBoth = true;
        namesCardinalities = true;
        reversingWorks = true;
      };
    };

  testAGeneratorReadsASiblingThatIsNotDeclared =
    let
      result = deployment { ownerArgs.reads = [ "nosuch" ]; };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "vars-reads-unknown-generator" result;
        namesTheName = hasInfix "`nosuch`" (messageById "vars-reads-unknown-generator" result);
        listsWhatItDeclares = hasInfix "`app`" (evidenceById "vars-reads-unknown-generator" result);
      };
      expected = {
        rows = [ "vars-reads-unknown-generator" ];
        subjects = [ "holder:only" ];
        namesTheName = true;
        listsWhatItDeclares = true;
      };
    };

  testADeliveredSecretCarriesNoBytes =
    let
      bytes = "PRIVATE-KEY-BYTES-9f2c";
      result = deployment {
        consumer = reader { };
        varsState."holder:vars/app@alpha"."key" = {
          present = true;
          content = bytes;
        };
      };
      entry = result.plan."holder:vars/app@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        path = entry.files."key".path;
        inPlan = entry.files."key".inPlan;
        delivery = entry.delivery;
        reasonCount = length entry.deliveryDerivedFrom;
        providerRecords = result.plan."holder:only@alpha".provides.identity.exports.key.value;
        readerRecords = result.plan."client:only@beta".reads.far.values.key;
        bytesAnywhere = hasInfix bytes (builtins.toJSON result.plan);
      };
      expected = {
        rows = [ ];
        path = "/run/vars/holder/app/key";
        inPlan = "reference";
        delivery = [
          "alpha"
          "beta"
        ];
        reasonCount = 2;
        providerRecords = "/run/vars/holder/app/key";
        readerRecords = {
          path = "/run/vars/holder/app/key";
          secrecy = "secret";
        };
        bytesAnywhere = false;
      };
    };

  testASharedValueIsOneEntry =
    let
      result = planOf {
        interfaces."interfaces/default.nix" = { inherit identity public; };
        instances.holder = {
          module = soleRoot {
            module = owner { per = "instance"; };
            provides = [ "identity" ];
          };
          placement.every.only.machines = [
            "alpha"
            "beta"
            "idle"
          ];
          exposes = [ "identity" ];
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        keys = varsKeys result;
        delivery = result.plan."holder:vars/app".delivery;
      };
      expected = {
        rows = [ ];
        keys = [ "holder:vars/app" ];
        delivery = [
          "alpha"
          "beta"
          "idle"
        ];
      };
    };

  testAMachineSpecificValueIsOneEntryPerMachine =
    let
      result = planOf {
        interfaces."interfaces/default.nix" = { inherit identity public; };
        instances.holder = {
          module = soleRoot {
            module = owner { per = "placement"; };
            provides = [ "identity" ];
          };
          placement.every.only.machines = [
            "alpha"
            "beta"
            "idle"
          ];
          exposes = [ "identity" ];
        };
      };
      keysOf = key: result.plan.${key}.key;
      without =
        key:
        removeAttrs result.plan.${key} [
          "key"
          "delivery"
          "deliveryDerivedFrom"
          "dependsOn"
        ];
    in
    {
      expr = {
        rows = rowIds result;
        keys = varsKeys result;
        allKeysDiffer = length (planner.util.uniqueStrings (map keysOf (varsKeys result))) == 3;
        onlyTheMachineFactDiffers = without "holder:vars/app@alpha" == without "holder:vars/app@beta";
        dependsOnItsOwnMachine = map (
          d: builtins.head (builtins.split "@" d)
        ) result.plan."holder:vars/app@beta".dependsOn;
      };
      expected = {
        rows = [ ];
        keys = [
          "holder:vars/app@alpha"
          "holder:vars/app@beta"
          "holder:vars/app@idle"
        ];
        allKeysDiffer = true;
        onlyTheMachineFactDiffers = true;
        dependsOnItsOwnMachine = [ "machine:beta" ];
      };
    };

  testAGeneratedValueDependsOnWhatItReads =
    let
      result = fleet {
        ownerArgs = {
          per = "placement";
          reads = [ "ca" ];
          also.ca = {
            per = "instance";
            files."cert".secrecy = "secret";
          };
        };
      };
      shared = result.plan."holder:vars/ca";
    in
    {
      expr = {
        rows = rowIds result;
        namesTheSibling = filter (
          d: hasInfix "holder:vars/ca" d
        ) result.plan."holder:vars/app@alpha".dependsOn;
        theSiblingNamesNeither = shared.dependsOn or [ ];
      };
      expected = {
        rows = [ ];
        namesTheSibling = [ "holder:vars/ca#${shared.key}" ];
        theSiblingNamesNeither = [ ];
      };
    };

  testAGeneratedFilesPathNamesItsInstance =
    let
      result = planOf {
        interfaces."interfaces/default.nix" = { inherit identity public; };
        instances = {
          first = {
            module = soleRoot { module = bare "app"; };
            placement.every.only.machines = [ "alpha" ];
          };
          second = {
            module = soleRoot { module = bare "app"; };
            placement.every.only.machines = [ "alpha" ];
          };
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        first = result.plan."first:vars/app@alpha".files."key".path;
        second = result.plan."second:vars/app@alpha".files."key".path;
      };
      expected = {
        rows = [ ];
        first = "/run/vars/first/app/key";
        second = "/run/vars/second/app/key";
      };
    };

  testTheStateOfAValueIsKeyedByItsEntry =
    let
      shared = _: {
        vars.app = {
          per = "instance";
          files."label".secrecy = "public";
        };
        provides.label.interface = public;
        impl =
          { vars, ... }:
          {
            provides.label.exports.label = vars.app."label".content;
            units.only.command = "/bin/true";
          };
      };
      planWith =
        varsState:
        planOf {
          inherit varsState;
          interfaces."interfaces/default.nix" = { inherit identity public; };
          instances.holder = {
            module = soleRoot {
              module = shared;
              provides = [ "label" ];
            };
            placement.every.only.machines = [
              "alpha"
              "beta"
            ];
            exposes = [ "label" ];
          };
        };
      keyed = planWith {
        "holder:vars/app"."label" = {
          present = true;
          content = "shared-bytes";
        };
      };
      # The shape the planner was given before a value had an entry of its own.
      byMachine = planWith {
        alpha.app."label" = {
          present = true;
          content = "shared-bytes";
        };
      };
    in
    {
      expr = {
        rows = rowIds keyed;
        oneRecordForTwoMachines = keyed.plan."holder:vars/app".files;
        exported = keyed.plan."holder:only@beta".provides.label.exports.label.value;
        underTheOtherKey = byMachine.plan."holder:vars/app".files;
        rowsUnderTheOtherKey = rowIds byMachine;
      };
      expected = {
        rows = [ ];
        oneRecordForTwoMachines."label" = {
          deploy = true;
          inPlan = "value";
          path = "/run/vars/holder/app/label";
          secrecy = "public";
        };
        exported = "shared-bytes";
        underTheOtherKey."label" = {
          bytes = "absent";
          deploy = true;
          inPlan = "value";
          path = "/run/vars/holder/app/label";
          secrecy = "public";
        };
        rowsUnderTheOtherKey = [ ];
      };
    };

  testAGeneratorNamesItsProgram =
    let
      result = withGenerator { program = program; };
      entry = result.plan."holder:vars/gen@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        recorded = entry.program;
        # A literal string, like every other store path in a plan: nothing here
        # realises it and nothing reads it. Nix equality ignores context, so the
        # absence is observed rather than compared for.
        literal = builtins.isString entry.program;
        withoutContext = builtins.hasContext entry.program;
      };
      expected = {
        rows = [ ];
        recorded = program;
        literal = true;
        withoutContext = false;
      };
    };

  testAGeneratorNamesNoProgram =
    let
      result = withGenerator { };
      entry = result.plan."holder:vars/gen@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        # Absent rather than null or empty, so a reader that needs one refuses on
        # the key it cannot find.
        recorded = entry ? program;
        # And a value generated by another program is another value.
        anotherProgramIsAnotherValue =
          entry.key != (withGenerator { program = program; }).plan."holder:vars/gen@alpha".key;
      };
      expected = {
        rows = [ ];
        recorded = false;
        anotherProgramIsAnotherValue = true;
      };
    };

  testAProgramThatIsNotAStorePath =
    let
      result = withGenerator { program = "generate.sh"; };
      shortHashed = withGenerator {
        program = "/nix/store/1w9k3zc7yq2mb5xj8vdl4rns6fga0h1-gen.drv";
      };
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "vars-program-malformed" result;
        namesTheGenerator = hasInfix "generator `gen`" (messageById "vars-program-malformed" result);
        theRestIsPlanned = result.plan ? "holder:vars/app@alpha";
        recorded = result.plan."holder:vars/gen@alpha" ? program;
        applicable = result.applicable;
        aShortHashIsNotOne = rowIds shortHashed;
      };
      expected = {
        rows = [ "vars-program-malformed" ];
        subjects = [ "holder:only" ];
        namesTheGenerator = true;
        theRestIsPlanned = true;
        recorded = false;
        applicable = false;
        aShortHashIsNotOne = [ "vars-program-malformed" ];
      };
    };
}
