# One test per excluded construct. Each trigger is quoted from the fixture README
# rather than from lib/excluded.nix, so a row wired to the wrong trigger fails.
{ planner, support }:
let
  inherit (builtins)
    all
    attrNames
    filter
    foldl'
    genList
    isString
    length
    split
    stringLength
    substring
    ;

  inherit (support)
    evidenceById
    hasInfix
    messageById
    planOf
    publicString
    root
    rowIds
    severityById
    soleRoot
    subjectsById
    ;

  inherit (planner.util) subtractList uniqueStrings;

  excluded = planner.excluded;

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

  declaringAtom =
    key: value:
    planOf {
      instances = { };
      interfaces."interfaces/default.nix".identity = planner.interface {
        name = "identity";
        exports.publicKey = publicString // {
          ${key} = value;
        };
      };
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

  identity = planner.interface {
    name = "identity";
    exports.publicKey = publicString;
  };

  exclusionHeader = "| Out | Why not now | Trigger to add it |";

  readmeLines = filter isString (split "\n" (builtins.readFile "${support.folder}/README.md"));

  chars = s: genList (i: substring i 1 s) (stringLength s);
  isTableLine = l: substring 0 1 l == "|";
  isRule = l: all (c: c == "|" || c == "-" || c == " ") (chars l);

  scanLine =
    st: line:
    if st.closed then
      st
    else if !st.open then
      st // { open = line == exclusionHeader; }
    else if !(isTableLine line) then
      st // { closed = true; }
    else if isRule line then
      st
    else
      st // { rows = st.rows + 1; };

  table = foldl' scanLine {
    open = false;
    closed = false;
    rows = 0;
  } readmeLines;

  covered = [
    "answers"
    "collects"
    "contributes"
    "dynamicPort"
    "enable"
    "externals"
    "frontier"
    "lifecycle"
    "locality"
    "memberWire"
    "orchestrator"
    "pick"
    "probes"
    "register"
    "strategy"
  ];

  coveredRows = uniqueStrings (map (c: excluded.constructs.${c}.row) covered);
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

  testEnableIsRefused =
    let
      result = oneInstance (
        placedOn "one" (root {
          members.only = {
            module = quiet;
            enable = true;
          };
        })
      );
    in
    excludedKeyFacts {
      inherit result;
      key = "enable";
      subject = "svc:only";
      trigger = "a module publishing a composition whose coherent cuts an operator wants";
      also.namesMember = hasInfix "member `only` of instance `svc`" (
        messageById "declaration-excluded-key" result
      );
    };

  testMemberWireIsRefused =
    let
      result = oneInstance {
        module = soleRoot {
          module = _: {
            uses.far = {
              interface = identity;
              reads = [ "publicKey" ];
            };
            impl = unit;
          };
        };
        placement.every.only.machines = [ "one" ];
        wire.far.only = {
          instance = "provider";
          provides = "thing";
        };
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "declaration-excluded-key" result;
        subjects = subjectsById "declaration-excluded-key" result;
        namesTheCut = hasInfix "wires `far` of instance `svc` per member" (
          messageById "declaration-excluded-key" result
        );
        namesTrigger = hasInfix "a module publishing a composition whose coherent cuts an operator wants" (
          evidenceById "declaration-excluded-key" result
        );
        delivered = result.plan."svc:only@one".reads.far.delivered;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "declaration-excluded-key" ];
        severity = "error";
        subjects = [ "svc:only" ];
        namesTheCut = true;
        namesTrigger = true;
        delivered = false;
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

  # The number is the README table's row count. Another table row, or a new key in
  # excluded.constructs, has to be given a test above.
  testEveryExclusionTableRowIsCovered = {
    expr = {
      headerFound = table.open;
      readmeRowCount = table.rows;
      coveredRowCount = length coveredRows;
      inherit coveredRows;
      libraryRows = uniqueStrings excluded.rows;
      constructsWithoutATest = subtractList (attrNames excluded.constructs) covered;
      testsWithoutAConstruct = subtractList covered (attrNames excluded.constructs);
    };
    expected = {
      headerFound = true;
      readmeRowCount = 7;
      coveredRowCount = 7;
      coveredRows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "member cuts"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      libraryRows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "member cuts"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      constructsWithoutATest = [ ];
      testsWithoutAConstruct = [ ];
    };
  };
}
