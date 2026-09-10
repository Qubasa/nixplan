{ planner, support }:
let
  inherit (support)
    countById
    evidenceById
    hasInfix
    messageById
    planOf
    publicInt
    publicString
    rowsById
    severityById
    soleRoot
    ;

  k = planner.korora;

  identity = planner.interface {
    name = "identity";
    exports.publicKey = publicString;
  };

  provider = _: {
    provides.identity.interface = identity;
    impl = _: {
      provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  scenario =
    {
      interfaceValues,
      instances,
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

  providerOf = iface: _: {
    provides.identity.interface = iface;
    impl = _: {
      provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  wired =
    {
      reads,
      publishes ? reads,
      interfaces,
    }:
    planOf {
      inherit interfaces;
      instances = {
        reader = {
          module = soleRoot { module = readerOf reads; };
          placement.every.only.machines = [ "one" ];
          wire.far = {
            instance = "writer";
            provides = "identity";
          };
        };
        writer = {
          module = soleRoot {
            module = providerOf publishes;
            provides = [ "identity" ];
          };
          placement.every.only.machines = [ "two" ];
          exposes = [ "identity" ];
        };
      };
    };

  conflicting =
    { mine, theirs }:
    planOf {
      instances = { };
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
        instances = { };
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
        instances = { };
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
    in
    {
      expr = {
        registeredRows = registered.diagnostics;
        unregisteredRows = unregistered.diagnostics;
        sameKeys = builtins.attrNames registered.plan == builtins.attrNames unregistered.plan;
      };
      expected = {
        registeredRows = [ ];
        unregisteredRows = [ ];
        sameKeys = true;
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
        instances = { };
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
      result = planOf {
        interfaces = {
          "interfaces/mine.nix".identity = mine;
          "interfaces/theirs.nix".identity = theirs;
        };
        instances = {
          reader = {
            module = soleRoot { module = consumer; };
            placement.every.only.machines = [ "one" ];
            wire.far = {
              instance = "writer";
              provides = "identity";
            };
          };
          writer = {
            module = soleRoot {
              module = farProvider;
              provides = [ "identity" ];
            };
            placement.every.only.machines = [ "two" ];
            exposes = [ "identity" ];
          };
        };
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
        instances = { };
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
        instances = { };
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
      mine = claiming { exports.publicKey = publicString; };
      theirs = claiming {
        exports = {
          publicKey = publicString;
          hostName = publicString;
        };
      };
      result = conflicting { inherit mine theirs; };
      again = conflicting { inherit mine theirs; };
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
      mine = claiming { exports.key = { type = k.secretRef; }; };
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
        foundByClaim =
          planner.fileOf (planner.registry { "interfaces/theirs.nix".identity = attributed; }) elsewhere;
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
        noFile =
          planner.fileOf (planner.registry { "interfaces/theirs.nix".identity = attributed; }) claimless;
      };
      expected = {
        rendersNoFile = true;
        noFile = null;
      };
    };
}
