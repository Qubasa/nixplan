{ planner, support }:
let
  inherit (support)
    hasInfix
    countById
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
}
