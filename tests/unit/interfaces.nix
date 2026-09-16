{
  planner,
  support,
  libSource,
}:
let
  inherit (support)
    countById
    evidenceById
    hasInfix
    identity
    messageById
    planOf
    provider
    providerOf
    publicInt
    publicString
    rowsById
    severityById
    soleRoot
    ;

  k = planner.korora;

  # An interface's rows are reached from the modules that imported it, never from
  # the attribution, so a scenario about a declaration places a member declaring
  # it and the attribution beside it decides only which file a row names.
  importing =
    interfaceValues:
    builtins.mapAttrs (_: iface: {
      module = soleRoot {
        module = providerOf iface;
        provides = [ "identity" ];
      };
      placement.every.only.machines = [ "one" ];
    }) interfaceValues;

  scenario =
    {
      interfaceValues,
      instances ? importing interfaceValues,
    }:
    planOf {
      inherit instances;
      interfaces."interfaces/default.nix" = interfaceValues;
    };

  # A reader records the names of what it received, so a refused slot is
  # observable without the test touching it and aborting the suite.
  readerOf = iface: _: {
    uses.far = {
      interface = iface;
      reads = [ "publicKey" ];
    };
    impl =
      { results, ... }:
      {
        units.only = {
          command = "/bin/true";
          env.FAR = if results ? far then results.far.publicKey else "";
        };
      };
  };

  wired =
    {
      reads,
      publishes ? reads,
      interfaces,
    }:
    support.edge {
      inherit interfaces;
      consumerName = "reader";
      providerName = "writer";
      consumerModule = readerOf reads;
      providerModule = providerOf publishes;
      providerMachines = [ "two" ];
    };

  # A module that imports an interface and resolves nothing from it. The conflict
  # is the registry pass's own observation, and this deployment is what "with no
  # wire" means: the slot each member declares is unwired on purpose.
  importerOf = iface: _: {
    uses.far = {
      interface = iface;
      reads = [ ];
    };
    impl = _: { units.only.command = "/bin/true"; };
  };

  conflicting =
    { mine, theirs }:
    planOf {
      instances = {
        first = {
          module = soleRoot { module = importerOf mine; };
          placement.every.only.machines = [ "one" ];
        };
        second = {
          module = soleRoot { module = importerOf theirs; };
          placement.every.only.machines = [ "two" ];
        };
      };
      interfaces = {
        "interfaces/mine.nix".identity = mine;
        "interfaces/theirs.nix".identity = theirs;
      };
    };

  claiming =
    args:
    planner.interface (
      {
        name = "identity";
        id = "example.com/identity";
      }
      // args
    );
in
{
  testAnAtomOmitsSecrecy =
    let
      iface = planner.interface {
        name = "i";
        exports.a = publicString;
      };
    in
    {
      expr = {
        declaredKeys = builtins.attrNames iface.exports.a;
        secrecy = planner.secrecyOf iface.exports.a;
      };
      expected = {
        declaredKeys = [ "type" ];
        secrecy = "public";
      };
    };

  testAnAtomOmitsSecrecyProducesNoRow = {
    expr = countById "export-atom-unknown-key" (scenario {
      interfaceValues.identity = identity;
      instances.i = {
        module = soleRoot {
          module = provider;
          provides = [ "identity" ];
        };
        placement.every.only.machines = [ "one" ];
        exposes = [ "identity" ];
      };
    });
    expected = 0;
  };

  testAnAtomDeclaresALocality =
    let
      withLocality = planner.interface {
        name = "identity";
        exports.publicKey = publicString // {
          locality = "machine-local";
        };
      };
      result = scenario {
        interfaceValues.identity = withLocality;
      };
    in
    {
      expr = {
        rows = countById "export-atom-excluded-key" result;
        severity = severityById "export-atom-excluded-key" result;
        namesKey = hasInfix "`locality`" (messageById "export-atom-excluded-key" result);
        namesAtom = hasInfix "identity.publicKey" (messageById "export-atom-excluded-key" result);
        namesTrigger = hasInfix "unix socket path or a loopback port" (
          support.evidenceById "export-atom-excluded-key" result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        severity = "error";
        namesKey = true;
        namesAtom = true;
        namesTrigger = true;
        applicable = false;
      };
    };

  testAnAtomDeclaresALifecycle =
    let
      withLifecycle = planner.interface {
        name = "identity";
        exports.publicKey = publicString // {
          lifecycle = "static";
        };
      };
      result = scenario {
        interfaceValues.identity = withLifecycle;
      };
    in
    {
      expr = {
        rows = countById "export-atom-excluded-key" result;
        namesKey = hasInfix "`lifecycle`" (messageById "export-atom-excluded-key" result);
        namesTrigger = hasInfix "not knowable at evaluation" (
          support.evidenceById "export-atom-excluded-key" result
        );
      };
      expected = {
        rows = 1;
        namesKey = true;
        namesTrigger = true;
      };
    };

  testAnInterfaceNobodyUpstreamed =
    let
      instances.i = {
        module = soleRoot {
          module = provider;
          provides = [ "identity" ];
        };
        placement.every.only.machines = [ "one" ];
        exposes = [ "identity" ];
      };
      registered = scenario {
        interfaceValues.identity = identity;
        inherit instances;
      };
      unregistered = planOf { inherit instances; };
      claimedElsewhere = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        id = "example.com/identity";
      };
      claimedAndUnregistered = planOf {
        instances.i = {
          module = soleRoot {
            module = _: {
              provides.identity.interface = claimedElsewhere;
              impl = _: {
                provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
                units.only.command = "/bin/true";
              };
            };
            provides = [ "identity" ];
          };
          placement.every.only.machines = [ "one" ];
          exposes = [ "identity" ];
        };
      };
    in
    {
      expr = {
        registeredRows = registered.diagnostics;
        unregisteredRows = unregistered.diagnostics;
        claimedRows = claimedAndUnregistered.diagnostics;
        sameKeys = builtins.attrNames registered.plan == builtins.attrNames unregistered.plan;
        theClaimIsStillRecorded = claimedAndUnregistered.plan."i:only@one".provides.identity.interfaceId;
      };
      expected = {
        registeredRows = [ ];
        unregisteredRows = [ ];
        claimedRows = [ ];
        sameKeys = true;
        theClaimIsStillRecorded = "example.com/identity";
      };
    };

  testAValueDoesNotMatchItsDeclaredType =
    let
      badProvider = _: {
        provides.identity.interface = planner.interface {
          name = "identity";
          exports.publicKey = publicInt;
        };
        impl = _: {
          provides.identity.exports.publicKey = "not an int";
          units.only.command = "/bin/true";
        };
      };
      result = planOf {
        instances.i = {
          module = soleRoot {
            module = badProvider;
            provides = [ "identity" ];
          };
          placement.every.only.machines = [ "one" ];
          exposes = [ "identity" ];
        };
      };
    in
    {
      expr = {
        rows = countById "export-type-mismatch" result;
        subjects = support.subjectsById "export-type-mismatch" result;
        severity = severityById "export-type-mismatch" result;
      };
      expected = {
        rows = 1;
        subjects = [ "i:only@one" ];
        severity = "error";
      };
    };

  testUrlAtomVerifies = {
    expr = {
      good = k.url.verify "ssh://x";
      bad = builtins.isString (k.url.verify 3);
      real = k.url.verify "ssh://borg@vault.example:22/srv/borg";
    };
    expected = {
      good = null;
      bad = true;
      real = null;
    };
  };

  testSecretRefAtomVerifies = {
    expr = {
      good = k.secretRef.verify {
        path = "/run/vars/hostKey/key";
        secrecy = "secret";
      };
      public = builtins.isString (
        k.secretRef.verify {
          path = "/run/vars/hostKey/key";
          secrecy = "public";
        }
      );
      notAPath = builtins.isString (k.secretRef.verify "/run/vars/hostKey/key");
    };
    expected = {
      good = null;
      public = true;
      notAPath = true;
    };
  };

  testTheFoldersInterfacesEvaluateUnmodified =
    let
      interfaces = support.worked.interfaces;
    in
    {
      expr = {
        names = builtins.attrNames interfaces;
        exports =
          builtins.attrNames interfaces.sshHostIdentity.exports
          ++ builtins.attrNames interfaces.borgRepository.exports;
        secrecies = {
          publicKey = interfaces.sshHostIdentity.exports.publicKey.secrecy;
          privateKey = interfaces.sshHostIdentity.exports.privateKey.secrecy;
        };
        labels = [
          interfaces.sshHostIdentity.name
          interfaces.borgRepository.name
        ];
      };
      expected = {
        names = [
          "borgRepository"
          "sshHostIdentity"
        ];
        exports = [
          "privateKey"
          "publicKey"
          "quota"
          "url"
        ];
        secrecies = {
          publicKey = "public";
          privateKey = "secret";
        };
        labels = [
          "ssh-host-identity"
          "borg-repository"
        ];
      };
    };

  testAnInterfaceIsAValue = {
    expr = builtins.attrNames (
      planner.interface {
        name = "i";
        exports = { };
      }
    );
    expected = [
      "exports"
      "fold"
      "id"
      "name"
    ];
  };

  testADeclaredFoldIsNotAFunction =
    let
      notAFunction = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        fold = "union";
      };
      result = scenario {
        interfaceValues.identity = notAFunction;
      };
      row = builtins.head (rowsById "interface-fold-not-a-function" result);
    in
    {
      expr = {
        rows = countById "interface-fold-not-a-function" result;
        inherit (row) subject severity;
        namesInterface = hasInfix "identity" row.message;
        statesWhatAFoldIsAppliedTo = hasInfix "keyed by provider entry key" row.evidence;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        subject = "interfaces/default.nix";
        severity = "error";
        namesInterface = true;
        statesWhatAFoldIsAppliedTo = true;
        applicable = false;
      };
    };

  testTwoInterfacesShareAName =
    let
      mine = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
      };
      theirs = planner.interface {
        name = "identity";
        exports.hostKey = publicString;
      };
      consumer = _: {
        uses.far = {
          interface = mine;
          reads = [ "publicKey" ];
        };
        impl = _: {
          units.only.command = "/bin/true";
        };
      };
      farProvider = _: {
        provides.identity.interface = theirs;
        impl = _: {
          provides.identity.exports.hostKey = "k";
          units.only.command = "/bin/true";
        };
      };
      result = support.edge {
        interfaces = {
          "interfaces/mine.nix".identity = mine;
          "interfaces/theirs.nix".identity = theirs;
        };
        consumerName = "reader";
        providerName = "writer";
        consumerModule = consumer;
        providerModule = farProvider;
        providerMachines = [ "two" ];
      };
      row = builtins.head (rowsById "interface-mismatch" result);
    in
    {
      expr = {
        rows = countById "interface-mismatch" result;
        severity = row.severity;
        namesMine = hasInfix "interfaces/mine.nix" row.message;
        namesTheirs = hasInfix "interfaces/theirs.nix" row.message;
        namesTheSharedName = hasInfix "`identity`" row.message;
        sameNameNoted = hasInfix "carry one name" row.evidence;
      };
      expected = {
        rows = 1;
        severity = "error";
        namesMine = true;
        namesTheirs = true;
        namesTheSharedName = true;
        sameNameNoted = true;
      };
    };

  testACapabilityIsReExportedByValue =
    let
      evaluated =
        planner.mkRoot
          (soleRoot {
            module = provider;
            provides = [ "identity" ];
          })
          (_: {
            values = { };
            sources = { };
            rows = [ ];
          });
    in
    {
      expr = {
        exported = evaluated.provides.identity.interface == identity;
        member = evaluated.provides.identity.member;
        capability = evaluated.provides.identity.capability;
      };
      expected = {
        exported = true;
        member = "only";
        capability = "identity";
      };
    };

  testAMalformedClaimIsRefusedAndDisregarded =
    let
      malformed = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        id = "example.com/two words";
      };
      result = wired {
        reads = malformed;
        interfaces."interfaces/default.nix".identity = malformed;
      };
      row = builtins.head (rowsById "interface-id-malformed" result);
    in
    {
      expr = {
        rows = countById "interface-id-malformed" result;
        inherit (row) id subject severity;
        namesTheInterface = hasInfix "interfaces/default.nix" row.message;
        namesWhatWasWritten = hasInfix "`example.com/two words`" row.message;
        identity = planner.identityOf malformed;
        mismatches = countById "interface-mismatch" result;
        stillResolves = result.plan."reader:only@one".reads.far.delivered;
        received = result.plan."reader:only@one".units.only.env.FAR;
      };
      expected = {
        rows = 1;
        id = "interface-id-malformed";
        subject = "interfaces/default.nix";
        severity = "error";
        namesTheInterface = true;
        namesWhatWasWritten = true;
        identity = null;
        mismatches = 0;
        stillResolves = true;
        received = "ssh-ed25519 AAAA";
      };
    };

  testAClaimCarriesAnUnnamedFold =
    let
      unnamed = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        id = "example.com/identity";
        fold = set: builtins.attrNames set;
      };
      result = scenario {
        interfaceValues.identity = unnamed;
      };
      row = builtins.head (rowsById "interface-id-unnamed-fold" result);
    in
    {
      expr = {
        rows = countById "interface-id-unnamed-fold" result;
        inherit (row) subject severity;
        namesTheInterface = hasInfix "interfaces/default.nix" row.message;
        statesAClaimNeedsANamedFold = hasInfix "part of the identity a claim carries" row.evidence;
        identity = planner.identityOf unnamed;
      };
      expected = {
        rows = 1;
        subject = "interfaces/default.nix";
        severity = "error";
        namesTheInterface = true;
        statesAClaimNeedsANamedFold = true;
        identity = null;
      };
    };

  testAnUnqualifiedClaim =
    let
      unqualified = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        id = "identity";
      };
      result = wired {
        reads = unqualified;
        interfaces."interfaces/default.nix".identity = unqualified;
      };
      row = builtins.head (rowsById "interface-id-unnamespaced" result);
    in
    {
      expr = {
        rows = countById "interface-id-unnamespaced" result;
        inherit (row) subject severity;
        namesTheId = hasInfix "`identity`" row.message;
        statesTheSharedNamespace = hasInfix "shared with every other author" row.evidence;
        resolvesToAQualifiedForm = hasInfix "`<domain or repository>/identity`" row.resolution;
        identifies = planner.identityOf unqualified;
        inherit (result) applicable;
        stillResolves = result.plan."reader:only@one".reads.far.delivered;
      };
      expected = {
        rows = 1;
        subject = "interfaces/default.nix";
        severity = "warning";
        namesTheId = true;
        statesTheSharedNamespace = true;
        resolvesToAQualifiedForm = true;
        identifies = {
          id = "identity";
          exports.publicKey = {
            type = "string";
            secrecy = "public";
          };
          fold = null;
        };
        applicable = true;
        stillResolves = true;
      };
    };

  testAQualifiedClaimIsNotReported =
    let
      dotted = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        id = "example.com-identity";
      };
      slashed = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        id = "example/identity";
      };
      result = scenario {
        interfaceValues = { inherit dotted slashed; };
      };
    in
    {
      expr = {
        unnamespaced = countById "interface-id-unnamespaced" result;
        malformed = countById "interface-id-malformed" result;
        identified = [
          (planner.identityOf dotted).id
          (planner.identityOf slashed).id
        ];
      };
      expected = {
        unnamespaced = 0;
        malformed = 0;
        identified = [
          "example.com-identity"
          "example/identity"
        ];
      };
    };

  testTwoAttributedInterfacesConflictWithNoWire =
    let
      # The pair is built twice, once by this library and once by a second,
      # independent evaluation of it, whose atoms are unequal values. Comparing
      # the two tables is then a claim about the row rather than about one pure
      # function applied twice, which is what Nix would answer for free.
      pairFrom = library: {
        mine = library.interface {
          name = "identity";
          id = "example.com/identity";
          exports.publicKey = {
            type = library.korora.url;
          };
        };
        theirs = library.interface {
          name = "identity";
          id = "example.com/identity";
          exports = {
            publicKey = {
              type = library.korora.url;
            };
            hostName = {
              type = library.korora.url;
            };
          };
        };
      };
      here = pairFrom planner;
      there = pairFrom (support.anotherEvaluation libSource);
      result = conflicting here;
      again = conflicting there;
      row = builtins.head (rowsById "interface-id-conflict" result);
    in
    {
      expr = {
        rows = countById "interface-id-conflict" result;
        inherit (row) subject severity;
        namesBothFiles = [
          (hasInfix "interfaces/mine.nix" row.message)
          (hasInfix "interfaces/theirs.nix" row.message)
        ];
        namesTheId = hasInfix "`example.com/identity`" row.message;
        namesTheDifference = hasInfix "the second declares `hostName` and the first does not" row.evidence;
        unequalAsValues = here.mine != there.mine;
        sameTwice = result.diagnostics == again.diagnostics;
        applicable = result.applicable;
      };
      expected = {
        rows = 1;
        subject = "interfaces/mine.nix";
        severity = "error";
        namesBothFiles = [
          true
          true
        ];
        namesTheId = true;
        namesTheDifference = true;
        unequalAsValues = true;
        sameTwice = true;
        applicable = false;
      };
    };

  testOneClaimAndTwoTypesForOneExport =
    let
      mine = claiming { exports.publicKey = publicString; };
      theirs = claiming { exports.publicKey = publicInt; };
      result = conflicting { inherit mine theirs; };
      row = builtins.head (rowsById "interface-id-conflict" result);
    in
    {
      expr = {
        rows = countById "interface-id-conflict" result;
        inherit (row) subject;
        namesTheExport = hasInfix "export `publicKey`" row.evidence;
        namesBothTypes = hasInfix "`string` to the first and `int` to the second" row.evidence;
      };
      expected = {
        rows = 1;
        subject = "interfaces/mine.nix";
        namesTheExport = true;
        namesBothTypes = true;
      };
    };

  testOneClaimAndTwoSecreciesForOneExport =
    let
      mine = claiming {
        exports.key = {
          type = k.secretRef;
        };
      };
      theirs = claiming {
        exports.key = {
          type = k.secretRef;
          secrecy = "secret";
        };
      };
      result = conflicting { inherit mine theirs; };
      row = builtins.head (rowsById "interface-id-conflict" result);
    in
    {
      expr = {
        rows = countById "interface-id-conflict" result;
        inherit (row) subject;
        namesBothSecrecies = hasInfix "export `key` is public to the first and secret to the second" row.evidence;
      };
      expected = {
        rows = 1;
        subject = "interfaces/mine.nix";
        namesBothSecrecies = true;
      };
    };

  testOneClaimAndTwoFolds =
    let
      mine = claiming {
        exports.publicKey = publicString;
        fold = planner.fold "union" (set: builtins.attrNames set);
      };
      theirs = claiming {
        exports.publicKey = publicString;
        fold = planner.fold "sole" (set: builtins.attrNames set);
      };
      result = conflicting { inherit mine theirs; };
      row = builtins.head (rowsById "interface-id-conflict" result);
    in
    {
      expr = {
        rows = countById "interface-id-conflict" result;
        inherit (row) subject;
        namesBothFolds = hasInfix "the first names `union` and the second names `sole`" row.evidence;
      };
      expected = {
        rows = 1;
        subject = "interfaces/mine.nix";
        namesBothFolds = true;
      };
    };

  testARowNamesAThirdPartysDeclaringFile =
    let
      attributed = claiming { exports.publicKey = publicString; };
      elsewhere = claiming {
        name = "host-identity";
        exports.publicKey = publicString;
      };
      result = planOf {
        interfaces."interfaces/theirs.nix".identity = attributed;
        instances.reader = {
          module = soleRoot { module = readerOf elsewhere; };
          placement.every.only.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        distinctValues = elsewhere != attributed;
        oneIdentity = planner.identityOf elsewhere == planner.identityOf attributed;
        namesTheDeclaringFile = hasInfix "`host-identity` (interfaces/theirs.nix)" (
          evidenceById "slot-unwired" result
        );
        foundByClaim = planner.fileOf (planner.registry {
          "interfaces/theirs.nix".identity = attributed;
        }) elsewhere;
      };
      expected = {
        distinctValues = true;
        oneIdentity = true;
        namesTheDeclaringFile = true;
        foundByClaim = "interfaces/theirs.nix";
      };
    };

  testAnUnattributedInterfaceRendersAsItDoesToday =
    let
      claimless = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
      };
      attributed = claiming { exports.publicKey = publicInt; };
      result = planOf {
        interfaces."interfaces/theirs.nix".identity = attributed;
        instances.reader = {
          module = soleRoot { module = readerOf claimless; };
          placement.every.only.machines = [ "one" ];
        };
      };
    in
    {
      expr = {
        rendersNoFile = hasInfix "`identity` (declaring file not recorded in the `interfaces` argument of mkPlan)" (
          evidenceById "slot-unwired" result
        );
        noFile = planner.fileOf (planner.registry {
          "interfaces/theirs.nix".identity = attributed;
        }) claimless;
      };
      expected = {
        rendersNoFile = true;
        noFile = null;
      };
    };

  # One deployment planned twice over the same interface value, listed and not:
  # every condition the table reports is the same condition, and the only thing
  # that moves is the file each row names.
  testAttributionChangesOnlyTheFileARowNames =
    let
      # A slot nobody wired, so the table carries a row whose text names the
      # interface's declaring file.
      planned =
        interfaces:
        support.edge {
          inherit interfaces;
          consumerName = "reader";
          providerName = "writer";
          consumerModule = readerOf identity;
          consumerMachines = [ "two" ];
          wire = null;
        };
      listed = planned { "interfaces/default.nix".identity = identity; };
      bare = planned { };
      labelled = "`identity` (interfaces/default.nix)";
      unlabelled = "`identity` (declaring file not recorded in the `interfaces` argument of mkPlan)";
      conditions = result: map (r: { inherit (r) id subject; }) result.diagnostics;
      # The only value of the plan attribution decides: an interface nothing
      # attributed was declared in a file the plan cannot name.
      withoutTheDeclaringFile =
        result:
        result.plan
        // {
          "writer:only@one" = result.plan."writer:only@one" // {
            provides.identity = removeAttrs result.plan."writer:only@one".provides.identity [
              "declaringFile"
            ];
          };
        };
      substituted =
        row:
        builtins.mapAttrs (
          _: v: if builtins.isString v then builtins.replaceStrings [ unlabelled ] [ labelled ] v else v
        ) row;
    in
    {
      expr = {
        conditions = conditions bare == conditions listed;
        onlyTheFileMoves = map substituted bare.diagnostics == listed.diagnostics;
        namesTheFile = hasInfix labelled (evidenceById "slot-unwired" listed);
        namesNoFile = hasInfix unlabelled (evidenceById "slot-unwired" bare);
        declaringFile = [
          (listed.plan."writer:only@one".provides.identity.declaringFile)
          (bare.plan."writer:only@one".provides.identity.declaringFile)
        ];
        samePlan = withoutTheDeclaringFile bare == withoutTheDeclaringFile listed;
        applicable = [
          bare.applicable
          listed.applicable
        ];
      };
      expected = {
        conditions = true;
        onlyTheFileMoves = true;
        namesTheFile = true;
        namesNoFile = true;
        declaringFile = [
          "interfaces/default.nix"
          null
        ];
        samePlan = true;
        applicable = [
          false
          false
        ];
      };
    };

  # The defect this change exists for: an atom of this library is built by
  # applying a function to korora, so a second evaluation of `lib/` produces an
  # unequal atom and an unequal interface over it, and a wire that is obviously
  # correct was refused.
  testOneClaimSpansTwoEvaluations =
    let
      elsewhere = support.anotherEvaluation libSource;
      shapeOf =
        library:
        library.interface {
          name = "identity";
          exports.endpoint = {
            type = library.korora.url;
          };
          id = "example.com/identity";
        };
      mine = shapeOf planner;
      theirs = shapeOf elsewhere;
      publisher = _: {
        provides.identity.interface = theirs;
        impl = _: {
          provides.identity.exports.endpoint = "ssh://host.example/srv";
          units.only.command = "/bin/true";
        };
      };
      reader = _: {
        uses.far = {
          interface = mine;
          reads = [ "endpoint" ];
        };
        impl =
          { results, ... }:
          {
            units.only = {
              command = "/bin/true";
              env.FAR = if results ? far then results.far.endpoint else "";
            };
          };
      };
      result = support.edge {
        interfaces = {
          "interfaces/mine.nix".identity = mine;
          "interfaces/theirs.nix".identity = theirs;
        };
        consumerName = "reader";
        providerName = "writer";
        consumerModule = reader;
        providerModule = publisher;
        providerMachines = [ "two" ];
      };
    in
    {
      expr = {
        twoEvaluations = planner != elsewhere;
        unequalAsValues = mine != theirs;
        equalAsIdentities = planner.identityOf mine == elsewhere.identityOf theirs;
        mismatches = countById "interface-mismatch" result;
        delivered = result.plan."reader:only@one".reads.far.delivered;
        received = result.plan."reader:only@one".units.only.env.FAR;
        inherit (result) applicable;
      };
      expected = {
        twoEvaluations = true;
        unequalAsValues = true;
        equalAsIdentities = true;
        mismatches = 0;
        delivered = true;
        received = "ssh://host.example/srv";
        applicable = true;
      };
    };

  testAnInterfaceClaimsNoIdentity =
    let
      claimless = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
      };
      result = wired {
        reads = claimless;
        interfaces."interfaces/default.nix".identity = claimless;
      };
    in
    {
      expr = {
        identity = planner.identityOf claimless;
        declared = claimless.id;
        rows = result.diagnostics;
        stillResolves = result.plan."reader:only@one".reads.far.delivered;
      };
      expected = {
        identity = null;
        declared = null;
        rows = [ ];
        stillResolves = true;
      };
    };

  testAnUnclaimedInterfaceKeepsAnUnnamedFold =
    let
      bare = planner.interface {
        name = "identity";
        exports.publicKey = publicString;
        fold = set: builtins.attrNames set;
      };
      result = scenario {
        interfaceValues.identity = bare;
      };
    in
    {
      expr = {
        unnamedFold = countById "interface-id-unnamed-fold" result;
        nameMalformed = countById "interface-fold-name-malformed" result;
        notAFunction = countById "interface-fold-not-a-function" result;
        theFoldHasNoName = planner.foldName (planner.foldOf bare);
      };
      expected = {
        unnamedFold = 0;
        nameMalformed = 0;
        notAFunction = 0;
        theFoldHasNoName = null;
      };
    };
}
