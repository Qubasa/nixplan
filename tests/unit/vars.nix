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
  # once a member is placed more than once. Each declares a seal recipient, so a
  # delivery to it earns no warning and every row list below is about its own
  # subject; the two cases about that warning state a registry of their own.
  machines = {
    alpha = {
      address = "alpha.example:22";
      tags = [ "fleet" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age1wnkdgm47dsz3w6hvckcgvud675pw0zrc2x7k7pm72zx0865dz5uam96ha4";
    };
    beta = {
      address = "beta.example:22";
      tags = [ "fleet" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age15wy8legfhld65juvgt5j9yevstdp0l8n9ru4wqum9y6cr64540j8t2wdj8";
    };
    idle = {
      address = "idle.example:22";
      tags = [ "spare" ];
      system = "x86_64-linux";
      serviceManager = "systemd";
      sealRecipient = "age10krg9v00adjlyp7a9e3cf3rwtne0et6ydsaj8y3azwdecsrtm8ypwhu3yj";
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
      fileArgs ? { },
      unitArgs ? { },
      openIt ? true,
    }:
    _: {
      vars = {
        app = {
          files."key" = {
            secrecy = "secret";
          }
          // fileArgs;
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
          // (if openIt then { env.KEYFILE = vars.app."key".path; } else { })
          // unitArgs;
        };
    };

  reader =
    {
      reads ? [ "key" ],
      unitArgs ? { },
      extraUnits ? { },
    }:
    _: {
      uses.far = {
        interface = identity;
        inherit reads;
      };
      impl =
        { results, ... }:
        {
          units = {
            only = {
              command = "/bin/true";
              env.SAW = builtins.concatStringsSep "," (attrNames (results.far or { }));
            }
            // unitArgs;
          }
          // extraUnits;
        };
    };

  # The one extension field the readability rule reads. A unit's declared groups
  # are whatever an extension application records under this name, whichever
  # backend declared it, so this layer names no realiser.
  grouped = planner.unitExtension {
    backend = "systemd";
    name = "systemd-service";
    fields = {
      supplementaryGroups = {
        type = planner.korora.listOf planner.korora.string;
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
    support.edge {
      registry = machines;
      consumerName = "client";
      providerName = "holder";
      providerModule = owner ownerArgs;
      providerMachines = ownerMachines;
      consumerModule = consumer;
      inherit consumerMachines;
      interfaces."interfaces/default.nix" = { inherit identity public; };
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

  # The line `alpha` is rotated to, so a rotation is another recipient on one
  # machine rather than another machine.
  rotated = "age1kk6vk62pudgt4gvtegrc035aqqq9ky8yty4exlwzp4cgt44j93jrtlszgd";

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

  # The credential a machine joins a mesh with is a generated secret delivered to
  # nobody: the operator reads it out of the value source and hands it over
  # outside the tree. The plan therefore holds the path and the delivery facts
  # and no byte of the value, and that is asked of every string the plan carries
  # at any depth rather than of the fields this case happens to name: a case
  # reading one field would pass while another leaked.
  testTheCredentialsBytesAreNotInThePlan =
    let
      bytes = "authkey-7be2c1d40f9a";
      result = deployment {
        ownerArgs = {
          per = "instance";
          deploy = false;
          openIt = false;
        };
        varsState."holder:vars/app"."key" = {
          present = true;
          content = bytes;
        };
      };
      entry = result.plan."holder:vars/app";
      strings = planner.util.stringsDeep result.plan;
    in
    {
      expr = {
        rows = rowIds result;
        path = entry.files."key".path;
        inPlan = entry.files."key".inPlan;
        secrecy = entry.files."key".secrecy;
        deploy = entry.files."key".deploy;
        delivery = entry.delivery;
        reasons = entry.deliveryDerivedFrom;
        leakedFields = map (found: found.path) (filter (found: hasInfix bytes found.value) strings);
        theWalkReadsThePlan = builtins.any (found: found.value == "/run/vars/holder/app/key") strings;
      };
      expected = {
        rows = [ ];
        path = "/run/vars/holder/app/key";
        inPlan = "reference";
        secrecy = "secret";
        deploy = false;
        delivery = [ ];
        reasons = [ ];
        leakedFields = [ ];
        theWalkReadsThePlan = true;
      };
    };

  testASharedValueIsOneEntry =
    let
      result = deployment {
        ownerArgs.per = "instance";
        ownerMachines = [
          "alpha"
          "beta"
          "idle"
        ];
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
      result = deployment {
        ownerArgs.per = "placement";
        ownerMachines = [
          "alpha"
          "beta"
          "idle"
        ];
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
          group = "root";
          mode = "0400";
          owner = "root";
          inPlan = "value";
          path = "/run/vars/holder/app/label";
          secrecy = "public";
        };
        exported = "shared-bytes";
        underTheOtherKey."label" = {
          bytes = "absent";
          deploy = true;
          group = "root";
          mode = "0400";
          owner = "root";
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

  # The record a file carries about who may open it. Five scenarios, each varying
  # one field of one declaration.

  testAFileThatDeclaresNothing =
    let
      result = deployment { };
    in
    {
      expr = {
        rows = rowIds result;
        recorded = result.plan."holder:vars/app@alpha".files."key";
        # The key a record that declares nothing produces, recorded from the tree
        # before the three fields existed: a change that folds a defaulted
        # ownership into the key fails here rather than re-keying every value.
        key = result.plan."holder:vars/app@alpha".key;
      };
      expected = {
        rows = [ ];
        recorded = {
          deploy = true;
          owner = "root";
          group = "root";
          mode = "0400";
          inPlan = "reference";
          path = "/run/vars/holder/app/key";
          secrecy = "secret";
        };
        key = "sha256-2d73b17afc75cde1";
      };
    };

  testAFileReadableByAnAccount =
    let
      result = deployment {
        ownerArgs = {
          fileArgs = {
            owner = "app";
            group = "app";
            mode = "0640";
          };
          unitArgs.user = "app";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        recorded = result.plan."holder:vars/app@alpha".files."key";
        # The same value spelling the defaults out is another value, because a
        # record the deployment stated is what the key is built from.
        differsFromTheStatedDefaults =
          result.plan."holder:vars/app@alpha".key != (deployment {
            ownerArgs = {
              fileArgs = {
                owner = "root";
                group = "root";
                mode = "0400";
              };
            };
          }).plan."holder:vars/app@alpha".key;
      };
      expected = {
        rows = [ ];
        recorded = {
          deploy = true;
          owner = "app";
          group = "app";
          mode = "0640";
          inPlan = "reference";
          path = "/run/vars/holder/app/key";
          secrecy = "secret";
        };
        differsFromTheStatedDefaults = true;
      };
    };

  testAModeThatIsNotAMode =
    let
      badMode = deployment { ownerArgs.fileArgs.mode = "0999"; };
      symbolic = deployment { ownerArgs.fileArgs.mode = "rw-r-----"; };
      badOwner = deployment { ownerArgs.fileArgs.owner = "Not An Account"; };
    in
    {
      expr = {
        rows = rowIds badMode;
        subjects = subjectsById "vars-file-ownership-malformed" badMode;
        namesTheField = hasInfix "mode" (messageById "vars-file-ownership-malformed" badMode);
        # The failing value is not recorded, so the default is what travels.
        delivered = badMode.plan."holder:vars/app@alpha".files."key".mode;
        applicable = badMode.applicable;
        symbolicRows = rowIds symbolic;
        ownerRows = rowIds badOwner;
        ownerDelivered = badOwner.plan."holder:vars/app@alpha".files."key".owner;
      };
      expected = {
        rows = [ "vars-file-ownership-malformed" ];
        subjects = [ "holder:only" ];
        namesTheField = true;
        delivered = "0400";
        applicable = false;
        symbolicRows = [ "vars-file-ownership-malformed" ];
        ownerRows = [ "vars-file-ownership-malformed" ];
        ownerDelivered = "root";
      };
    };

  testTwoValuesDifferingOnlyInMode =
    let
      narrow = deployment { ownerArgs.fileArgs.mode = "0400"; };
      wide = deployment { ownerArgs.fileArgs.mode = "0440"; };
      entryOf = result: result.plan."holder:vars/app@alpha";
    in
    {
      expr = {
        # The bytes on a machine differ in a way a reader can observe, so the two
        # are two values rather than one delivered twice.
        keysDiffer = (entryOf narrow).key != (entryOf wide).key;
        modes = [
          (entryOf narrow).files."key".mode
          (entryOf wide).files."key".mode
        ];
        rows = rowIds narrow ++ rowIds wide;
      };
      expected = {
        keysDiffer = true;
        modes = [
          "0400"
          "0440"
        ];
        rows = [ ];
      };
    };

  testOneValueOnTwoMachines =
    let
      result = deployment {
        ownerArgs = {
          per = "instance";
          fileArgs = {
            owner = "app";
            group = "app";
            mode = "0640";
          };
          unitArgs.user = "app";
        };
        ownerMachines = [
          "alpha"
          "beta"
        ];
      };
      recorded = result.plan."holder:vars/app".files."key";
    in
    {
      expr = {
        rows = rowIds result;
        delivery = result.plan."holder:vars/app".delivery;
        # One value, one answer about who may read it, however many machines it
        # reaches: the record is the value's and not a machine's.
        recorded = {
          inherit (recorded) owner group mode;
        };
        entries = builtins.length (
          builtins.filter (k: builtins.match "holder:vars/app.*" k != null) (attrNames result.plan)
        );
      };
      expected = {
        rows = [ ];
        delivery = [
          "alpha"
          "beta"
        ];
        recorded = {
          owner = "app";
          group = "app";
          mode = "0640";
        };
        entries = 1;
      };
    };

  # The row a unit earns for reading a value its account cannot open. One
  # scenario per direction of the comparison.

  testAUnitRunningAsAnAccountReadsARootOnlyValue =
    let
      result = deployment {
        consumer = reader { unitArgs.user = "app"; };
      };
      row = messageById "slot-reads-value-unreadable-by-user" result;
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById "slot-reads-value-unreadable-by-user" result;
        namesTheUnit = hasInfix "unit `only`" row;
        namesTheAccount = hasInfix "`app`" row;
        namesTheSlot = hasInfix "slot `far`" row;
        namesTheExport = hasInfix "`key`" row;
        namesTheRecord = hasInfix "`root:root` at mode `0400`" row;
        applicable = result.applicable;
        # The entry is still recorded: a row is not a refusal to plan.
        theEntryIsPlanned = result.plan ? "client:only@beta";
      };
      expected = {
        rows = [ "slot-reads-value-unreadable-by-user" ];
        subjects = [ "client:only@beta" ];
        namesTheUnit = true;
        namesTheAccount = true;
        namesTheSlot = true;
        namesTheExport = true;
        namesTheRecord = true;
        applicable = false;
        theEntryIsPlanned = true;
      };
    };

  testAUnitRunningAsTheAccountTheFileNames =
    let
      result = deployment {
        ownerArgs = {
          fileArgs.owner = "app";
          unitArgs.user = "app";
        };
        consumer = reader { unitArgs.user = "app"; };
      };
    in
    {
      expr = {
        rows = rowIds result;
        recorded = result.plan."holder:vars/app@alpha".files."key".owner;
        theReadIsRecorded = result.plan."client:only@beta".reads.far ? entry;
      };
      expected = {
        rows = [ ];
        recorded = "app";
        theReadIsRecorded = true;
      };
    };

  testAUnitReadingAGroupReadableValue =
    let
      result = deployment {
        ownerArgs = {
          fileArgs = {
            group = "readers";
            mode = "0640";
          };
        };
        consumer = reader {
          unitArgs = {
            user = "app";
            extends = [
              {
                extension = grouped;
                values.supplementaryGroups = [ "readers" ];
              }
            ];
          };
        };
      };
      # The same declaration without the group is the row, so the group is what
      # the rule read rather than the mode alone.
      without = deployment {
        ownerArgs = {
          fileArgs = {
            group = "readers";
            mode = "0640";
          };
        };
        consumer = reader { unitArgs.user = "app"; };
      };
    in
    {
      expr = {
        rows = rowIds result;
        withoutTheGroup = rowIds without;
      };
      expected = {
        rows = [ ];
        withoutTheGroup = [ "slot-reads-value-unreadable-by-user" ];
      };
    };

  testAPrivilegedUnitReadsARootOnlyValue =
    let
      result = deployment {
        consumer = reader { };
      };
      worldReadable = deployment {
        ownerArgs.fileArgs.mode = "0444";
        consumer = reader { unitArgs.user = "app"; };
      };
    in
    {
      expr = {
        rows = rowIds result;
        # A mode with the world bit admits every account, so the declared user is
        # not compared at all.
        aWorldReadableValue = rowIds worldReadable;
      };
      expected = {
        rows = [ ];
        aWorldReadableValue = [ ];
      };
    };

  testOneUnitOfTwoCannotOpenTheValue =
    let
      result = deployment {
        consumer = reader {
          unitArgs.user = "app";
          extraUnits.privileged.command = "/bin/true";
        };
      };
    in
    {
      expr = {
        rows = rowIds result;
        count = countById "slot-reads-value-unreadable-by-user" result;
        namesTheFirst = hasInfix "unit `only`" (messageById "slot-reads-value-unreadable-by-user" result);
        bothUnitsRecorded = attrNames result.plan."client:only@beta".units;
      };
      expected = {
        rows = [ "slot-reads-value-unreadable-by-user" ];
        count = 1;
        namesTheFirst = true;
        bothUnitsRecorded = [
          "only"
          "privileged"
        ];
      };
    };

  # The negative half of the third readability site: the same record and the same
  # account as the row above, with the group the record grants declared on the
  # unit that names the file.
  testAValueAUnitsDeclaredGroupAdmitsIsNoRow =
    let
      record = {
        group = "readers";
        mode = "0640";
      };
      result = deployment {
        ownerArgs = {
          fileArgs = record;
          unitArgs = {
            user = "app";
            extends = [
              {
                extension = grouped;
                values.supplementaryGroups = [ "readers" ];
              }
            ];
          };
        };
      };
      # The same declaration with the group withdrawn from the unit, so the group
      # is what admitted the file rather than the mode alone.
      without = deployment {
        ownerArgs = {
          fileArgs = record;
          unitArgs.user = "app";
        };
      };
      entry = result.plan."holder:only@alpha";
      value = result.plan."holder:vars/app@alpha";
    in
    {
      expr = {
        rows = rowIds result;
        withoutTheGroup = rowIds without;
        units = attrNames entry.units;
        namedThePath = entry.units.only.env.KEYFILE == value.files."key".path;
        delivery = value.delivery;
        reasons = value.deliveryDerivedFrom;
      };
      expected = {
        rows = [ ];
        withoutTheGroup = [ "entry-value-unreadable-by-user" ];
        units = [ "only" ];
        namedThePath = true;
        delivery = [ "alpha" ];
        reasons = [ "holder:only@alpha owns it" ];
      };
    };

  # The path reaches the consumer as a public string export, so no read widens
  # the delivery set and the only site naming it is the probe. The row therefore
  # proves the mention scan reached inside a probe with no scan naming the field.
  testAProbeNamingAValueTheMachineDoesNotReceive =
    let
      id = "vars-path-off-delivery-set";
      pathAndKey = planner.interface {
        name = "identity";
        exports = {
          key = secretRef;
          keyPath = {
            type = planner.korora.string;
            secrecy = "public";
          };
        };
      };
      holder = _: {
        vars.app.files."key".secrecy = "secret";
        provides.identity.interface = pathAndKey;
        impl =
          { vars, ... }:
          {
            provides.identity.exports = {
              key = vars.app."key";
              keyPath = vars.app."key".path;
            };
            units.only.command = "/bin/true";
          };
      };
      client = _: {
        uses.far = {
          interface = pathAndKey;
          reads = [ "keyPath" ];
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              probe = "/bin/test -r ${results.far.keyPath}";
              probeTimeout = "30s";
            };
          };
      };
      result = support.edge {
        registry = machines;
        providerName = "holder";
        providerModule = holder;
        providerMachines = [ "alpha" ];
        consumerName = "client";
        consumerModule = client;
        consumerMachines = [ "beta" ];
        varsState."holder:vars/app@alpha"."key".present = true;
      };
      valuePath = result.plan."holder:vars/app@alpha".files."key".path;
      message = messageById id result;
      entry = result.plan."client:only@beta";
    in
    {
      expr = {
        rows = rowIds result;
        subjects = subjectsById id result;
        namesThePath = hasInfix valuePath message;
        namesTheMachine = hasInfix "`beta`" message;
        namesWhere = hasInfix "unit `only`" message;
        namesWhoReceivesIt = hasInfix "`alpha`" (evidenceById id result);
        theProbeIsTheOnlySiteNamingIt = hasInfix valuePath entry.units.only.probe;
      };
      expected = {
        rows = [ id ];
        subjects = [ "client:only@beta" ];
        namesThePath = true;
        namesTheMachine = true;
        namesWhere = true;
        namesWhoReceivesIt = true;
        theProbeIsTheOnlySiteNamingIt = true;
      };
    };

  testAPersistentPathIsDerivedFromTheValuesOwnPath =
    let
      once = deployment { };
      twice = deployment { };
      pathOf = result: result.plan."holder:vars/app@alpha".files."key".path;
      sealed = planner.util.sealedPathOf (pathOf once);
    in
    {
      expr = {
        rows = rowIds once;
        theRuntimePath = pathOf once;
        thePersistentPath = sealed;
        # A function of the runtime path and of nothing else, so two evaluations
        # of one deployment answer one string.
        twoEvaluationsAnswerOne = sealed == planner.util.sealedPathOf (pathOf twice);
        underThePersistentRoot = hasInfix planner.util.sealedRoot sealed;
        outsideTheRuntimeRoot = hasInfix planner.util.varsRoot sealed;
      };
      expected = {
        rows = [ ];
        theRuntimePath = "/run/vars/holder/app/key";
        thePersistentPath = "/var/lib/planner/sealed/holder/app/key.age";
        twoEvaluationsAnswerOne = true;
        underThePersistentRoot = true;
        outsideTheRuntimeRoot = false;
      };
    };

  # The check that would catch a persistent root placed under the runtime one:
  # `varsPathsIn` matches the runtime root plus three components, so a copy
  # inside it would be read as a mention of a value no module declared and the
  # two rows below would start firing on it. Each spelling is asserted beside
  # its own control, or a scan that matched nothing at all would read as a pass.
  testAPersistentPathIsNotAValuePathToTheScanThatRecognisesOne =
    let
      runtime = "${planner.util.varsRoot}/holder/app/key";
      sealed = planner.util.sealedPathOf runtime;
      offTheSet =
        mention:
        deployment {
          consumer = reader {
            reads = [ ];
            unitArgs.env.SAW = mention;
          };
        };
      undeployed =
        mention:
        deployment {
          ownerArgs = {
            deploy = false;
            openIt = false;
            unitArgs.env.SAW = mention;
          };
        };
    in
    {
      expr = {
        theScanReadsNoValuePathInIt = planner.util.varsPathsIn "opens ${sealed} at boot";
        andReadsTheRuntimeOneBesideIt = planner.util.varsPathsIn "opens ${runtime} at boot";
        aUnitOffTheDeliverySetNamingIt = rowIds (offTheSet sealed);
        namingTheRuntimePathInstead = rowIds (offTheSet runtime);
        aUnitNamingItOnAnUndeployedValue = rowIds (undeployed sealed);
        namingTheRuntimePathOfOne = rowIds (undeployed runtime);
      };
      expected = {
        theScanReadsNoValuePathInIt = [ ];
        andReadsTheRuntimeOneBesideIt = [ runtime ];
        aUnitOffTheDeliverySetNamingIt = [ ];
        namingTheRuntimePathInstead = [ "vars-path-off-delivery-set" ];
        aUnitNamingItOnAnUndeployedValue = [ ];
        namingTheRuntimePathOfOne = [ "vars-not-deployed-opened" ];
      };
    };

  # The trap this pins is `fileKeyInput`: the whole file record less defaulted
  # ownership is the value entry's key input, so a persistent path recorded as a
  # field of that record would re-key every generated value in every deployment
  # for a path that is a function of the path already there.
  testAPlanIsUnchangedByTheDerivationOfAPersistentPath =
    let
      plan = support.workedResult.plan;
      serialised = builtins.toJSON plan;
      valueEntries = filter (e: e ? files) (builtins.attrValues plan);
      fileFields = builtins.sort (a: b: a < b) (
        planner.util.uniqueStrings (
          builtins.concatMap (
            e: builtins.concatMap (f: attrNames f) (builtins.attrValues e.files)
          ) valueEntries
        )
      );
    in
    {
      expr = {
        readSomeValues = length valueEntries > 1;
        thePersistentRootIsNamedNowhere = hasInfix planner.util.sealedRoot serialised;
        noRecordSaysACopyIsKept = [
          (hasInfix "sealed" serialised)
          (hasInfix ".age" serialised)
        ];
        theFileRecordFields = fileFields;
      };
      expected = {
        readSomeValues = true;
        thePersistentRootIsNamedNowhere = false;
        noRecordSaysACopyIsKept = [
          false
          false
        ];
        theFileRecordFields = [
          "bytes"
          "deploy"
          "group"
          "inPlan"
          "mode"
          "owner"
          "path"
          "secrecy"
        ];
      };
    };

  testARotatedIdentityReKeysNothing =
    let
      planWith =
        line:
        planOf {
          machines = machines // {
            alpha = machines.alpha // {
              sealRecipient = line;
            };
          };
          instances.holder = {
            module = soleRoot { module = bare "app"; };
            placement.every.only.machines = [ "alpha" ];
          };
          varsState."holder:vars/app@alpha"."key".present = true;
        };
      before = planWith machines.alpha.sealRecipient;
      after = planWith rotated;
      keysOf = result: builtins.mapAttrs (_: entry: entry.key) result.plan;
    in
    {
      expr = {
        rows = rowIds before ++ rowIds after;
        theLineReallyMoved = [
          (before.plan."machine:alpha".sealRecipient == machines.alpha.sealRecipient)
          (after.plan."machine:alpha".sealRecipient == rotated)
        ];
        everyKey = keysOf before == keysOf after;
        theValueEntryKey =
          before.plan."holder:vars/app@alpha".key == after.plan."holder:vars/app@alpha".key;
        thePlacedEntryKey = before.plan."holder:only@alpha".key == after.plan."holder:only@alpha".key;
        theMachineKey = before.plan."machine:alpha".key == after.plan."machine:alpha".key;
        andTheFilesAreTheSameValue =
          before.plan."holder:vars/app@alpha".files == after.plan."holder:vars/app@alpha".files;
      };
      expected = {
        rows = [ ];
        theLineReallyMoved = [
          true
          true
        ];
        everyKey = true;
        theValueEntryKey = true;
        thePlacedEntryKey = true;
        theMachineKey = true;
        andTheFilesAreTheSameValue = true;
      };
    };
}
