# One test per excluded construct. Each trigger fragment is written out rather
# than read off lib/excluded.nix, so a row wired to the wrong trigger fails.
{ planner, support }:
let
  inherit (support)
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

  inherit (planner.util) uniqueStrings;

  ids = result: uniqueStrings (rowIds result);

  unit = _: {
    units.only.command = "/bin/true";
  };

  quiet = _: {
    impl = unit;
  };

  placedOn = machine: module: {
    inherit module;
    placement.every.only.machines = [ machine ];
  };

  oneInstance =
    instance:
    planOf {
      instances.svc = instance;
      sources.leaves.svc.only = "modules/svc.nix";
    };

  declaringModule =
    key:
    oneInstance (
      placedOn "one" (soleRoot {
        module = _: {
          ${key} = { };
          impl = unit;
        };
      })
    );

  declaringPlacement =
    key:
    oneInstance {
      module = soleRoot { module = quiet; };
      placement = {
        every.only.machines = [ "one" ];
        ${key} = { };
      };
    };

  # An interface's rows are reached from the module that imported it, so the atom
  # is declared on a placed member and the attribution beside it decides only
  # which file the row names.
  declaringAtom =
    key: value:
    let
      iface = planner.interface {
        name = "identity";
        exports.publicKey = publicString // {
          ${key} = value;
        };
      };
    in
    planOf {
      instances.svc = placedOn "one" (soleRoot {
        module = _: {
          provides.identity.interface = iface;
          impl = _: {
            provides.identity.exports.publicKey = "ssh-ed25519 AAAA";
            units.only.command = "/bin/true";
          };
        };
        provides = [ "identity" ];
      });
      interfaces."interfaces/default.nix".identity = iface;
    };

  excludedKeyFacts =
    {
      result,
      key,
      subject,
      trigger,
      also ? { },
    }:
    {
      expr = {
        rows = ids result;
        severity = severityById "declaration-excluded-key" result;
        subjects = subjectsById "declaration-excluded-key" result;
        namesKey = hasInfix "`${key}`" (messageById "declaration-excluded-key" result);
        namesTrigger = hasInfix trigger (evidenceById "declaration-excluded-key" result);
        applicable = result.applicable;
      }
      // also;
      expected = {
        rows = [ "declaration-excluded-key" ];
        severity = "error";
        subjects = [ subject ];
        namesKey = true;
        namesTrigger = true;
        applicable = false;
      }
      // builtins.mapAttrs (_: _: true) also;
    };

  moduleKeyFacts =
    key: trigger:
    excludedKeyFacts {
      result = declaringModule key;
      inherit key trigger;
      subject = "modules/svc.nix";
    };
in
{
  testLocalityIsRefused =
    let
      result = declaringAtom "locality" "machine-local";
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "export-atom-excluded-key" result;
        subjects = subjectsById "export-atom-excluded-key" result;
        namesKey = hasInfix "`locality`" (messageById "export-atom-excluded-key" result);
        namesAtom = hasInfix "identity.publicKey" (messageById "export-atom-excluded-key" result);
        namesTrigger = hasInfix "unix socket path or a loopback port" (
          evidenceById "export-atom-excluded-key" result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = [ "export-atom-excluded-key" ];
        severity = "error";
        subjects = [ "interfaces/default.nix" ];
        namesKey = true;
        namesAtom = true;
        namesTrigger = true;
        applicable = false;
      };
    };

  testLifecycleIsRefused =
    let
      result = declaringAtom "lifecycle" "at-most-probed";
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "export-atom-excluded-key" result;
        subjects = subjectsById "export-atom-excluded-key" result;
        namesKey = hasInfix "`lifecycle`" (messageById "export-atom-excluded-key" result);
        namesTrigger = hasInfix "assign an address only after the daemon authenticates" (
          evidenceById "export-atom-excluded-key" result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = [ "export-atom-excluded-key" ];
        severity = "error";
        subjects = [ "interfaces/default.nix" ];
        namesKey = true;
        namesTrigger = true;
        applicable = false;
      };
    };

  testPickIsRefused = excludedKeyFacts {
    result = declaringPlacement "pick";
    key = "pick";
    subject = "svc:instance";
    trigger = "the first service whose machine the operator is willing to let the planner choose";
  };

  testStrategyIsRefused = excludedKeyFacts {
    result = declaringPlacement "strategy";
    key = "strategy";
    subject = "svc:instance";
    trigger = "the first service whose machine the operator is willing to let the planner choose";
  };

  testDynamicPortIsRefused =
    let
      result = oneInstance (
        placedOn "one" (soleRoot {
          module = _: {
            claims.ports.api.proto = "tcp";
            impl = unit;
          };
        })
      );
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "port-claim-not-fixed" result;
        subjects = subjectsById "port-claim-not-fixed" result;
        namesClaim = hasInfix "port claim `api`" (messageById "port-claim-not-fixed" result);
        namesTrigger = hasInfix "a persisted allocation table" (evidenceById "port-claim-not-fixed" result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ "port-claim-not-fixed" ];
        severity = "error";
        subjects = [ "modules/svc.nix" ];
        namesClaim = true;
        namesTrigger = true;
        applicable = false;
      };
    };

  testExternalsIsRefused = moduleKeyFacts "externals" "U3 and U4";

  testCollectsIsRefused = moduleKeyFacts "collects" "clanServices/pki";

  testContributesIsRefused = moduleKeyFacts "contributes" "and nothing smaller";

  testAnswersIsRefused = moduleKeyFacts "answers" "clanServices/pki";

  testProbesIsRefused = moduleKeyFacts "probes" "not this change";

  testRegisterIsRefused = moduleKeyFacts "register" "not this change";

  testFrontierIsRefused = moduleKeyFacts "frontier" "not this change";

  testOrchestratorIsRefused = moduleKeyFacts "orchestrator" "not this change";
}
