# The exclusion table of fixtures/minimal-typed-edge/README.md, checked
# construct by construct.
#
# The folder states what is deliberately out and what brings each one back, and
# the library carries that table as data in lib/excluded.nix. This suite is the
# guard against the third possibility, which is neither refusing a construct nor
# carrying it: accepting it silently. One test per key of
# `planner.excluded.constructs` writes the smallest deployment that declares
# that construct and asserts the row it produces, the subject the row names and
# that the row's evidence carries the trigger the README's table records — the
# trigger is asserted as a literal from the README's own text rather than from
# `excluded.nix`, so a row wired to the wrong construct's trigger fails here.
#
# `testEveryExclusionTableRowIsCovered` closes the set: it reads the table out
# of the folder at evaluation, counts its rows, and compares that count against
# the README rows the constructs below cover. Adding a row to the table, or a
# key to `excluded.constructs`, without a test fails that test.
#
# Every key in the table is reachable through `mkPlan`. Nothing is recorded as
# unreachable.
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

  # A leaf module that is complete: an excluded key is the only thing wrong
  # with any deployment below, so a test's expected row set is one row.
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

  # One instance, one member, one leaf file, so that a row about the module
  # names a file rather than reporting that the deployment recorded none.
  oneInstance =
    instance:
    planOf {
      instances.svc = instance;
      sources.leaves.svc.only = "modules/svc.nix";
    };

  # A construct written at the top of a leaf module's declaration.
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

  # A construct written on a generated file, which is where a secret that has
  # to reach a consumer would say how it travels.
  declaringVarsFile =
    key: value:
    oneInstance (
      placedOn "one" (soleRoot {
        module = _: {
          vars.hostKey.files.key = {
            secrecy = "secret";
            ${key} = value;
          };
          impl = unit;
        };
      })
    );

  # A construct written on the placement surface of an instance.
  declaringPlacement =
    key:
    oneInstance {
      module = soleRoot { module = quiet; };
      placement = {
        every.only.machines = [ "one" ];
        ${key} = { };
      };
    };

  # An interface whose atom declares one field beyond `type` and `secrecy`.
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

  # The row every excluded key produces, whichever declaration wrote it.
  # `also` carries the facts one scenario has beyond the shared ones, each a
  # predicate the row has to satisfy.
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

  # A module declaring a construct at its top level: the row names the leaf
  # file, because that is the file an author has to edit.
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

  # The README's exclusion table, read out of the folder at evaluation. The
  # header pins which of the README's two tables is counted, a row is a line
  # inside the run that follows it, and the dashes under the header are not a
  # row. A blank line closes the run, so the tables further down are not
  # counted either.
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

  # The constructs the tests in this file write, and the README rows they
  # therefore cover. Written out rather than derived from `excluded.nix`: a
  # construct is covered because a test above declares it, and this list is
  # what the closing test holds that claim to.
  covered = [
    "answers"
    "collects"
    "contributes"
    "deploy"
    "dynamicPort"
    "enable"
    "externals"
    "frontier"
    "lifecycle"
    "locality"
    "memberWire"
    "orchestrator"
    "per"
    "pick"
    "probes"
    "register"
    "strategy"
  ];

  coveredRows = uniqueStrings (map (c: excluded.constructs.${c}.row) covered);
in
{
  # `locality` on an export atom: the field §32.1 adopted and this subset
  # dropped, refused where an interface would declare it.
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

  # `lifecycle`, and with it probes, facts and the register: the same
  # declaration site, its own trigger.
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

  # `per` on a generated secret: this folder can refuse a leak and cannot
  # route a secret, so the field that would say who receives it is refused.
  testPerIsRefused = excludedKeyFacts {
    result = declaringVarsFile "per" "consumer";
    key = "per";
    subject = "modules/svc.nix";
    trigger = "the first value that is secret and has to reach";
  };

  # `deploy` on the same generated secret: the delivery half of the same row.
  testDeployIsRefused = excludedKeyFacts {
    result = declaringVarsFile "deploy" { to = "consumer"; };
    key = "deploy";
    subject = "modules/svc.nix";
    trigger = "a database password being the case";
  };

  # `placement.pick`: the construct that would make an otherwise pure planner
  # stateful, refused on the placement surface that would carry it.
  testPickIsRefused = excludedKeyFacts {
    result = declaringPlacement "pick";
    key = "pick";
    subject = "svc:instance";
    trigger = "the first service whose machine the operator is willing to let the planner choose";
  };

  # `strategy`: how a delegated choice would be made, beside the delegation.
  testStrategyIsRefused = excludedKeyFacts {
    result = declaringPlacement "strategy";
    key = "strategy";
    subject = "svc:instance";
    trigger = "the first service whose machine the operator is willing to let the planner choose";
  };

  # Stable allocation rows are the third construct of that row, and a port
  # claim without a `fixed` value is the only way to ask for one: this subset
  # allocates nothing, so the claim is a row naming the allocation table.
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

  # `members.<name>.enable`: a member cut written where a root declares its
  # members, refused with the member and the instance named.
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
      # The row names the member and the instance as well as the key, which is
      # what makes it actionable in a root with more than one member.
      also.namesMember = hasInfix "member `only` of instance `svc`" (
        messageById "declaration-excluded-key" result
      );
    };

  # `wire.<member>.<use>`: the other half of the member-cut row. A wire whose
  # entries are keyed by member rather than naming an instance is the cut, and
  # it is refused rather than read as a wire to an instance called `only`.
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
        # A refused wire delivers nothing: the slot resolves to no value at all
        # rather than to something the consumer could default against.
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

  # `externals`: a non-fleet resource a deployment has to name.
  testExternalsIsRefused = moduleKeyFacts "externals" "U3 and U4";

  # `collects`: the far end of a slot is every service on the reader's machine.
  testCollectsIsRefused = moduleKeyFacts "collects" "clanServices/pki";

  # `contributes`: the answering half of the collect family.
  testContributesIsRefused = moduleKeyFacts "contributes" "and nothing smaller";

  # `answers`: the third of the family, refused with the same trigger, because
  # the family arrives together or not at all.
  testAnswersIsRefused = moduleKeyFacts "answers" "clanServices/pki";

  # `probes`: the runtime plane's reading half, which presupposes the fact
  # register and the watch contract.
  testProbesIsRefused = moduleKeyFacts "probes" "not this change";

  # `register`: the fact register itself.
  testRegisterIsRefused = moduleKeyFacts "register" "not this change";

  # `frontier`: the runtime plane's ordering half.
  testFrontierIsRefused = moduleKeyFacts "frontier" "not this change";

  # `orchestrator`: the last of the runtime plane. The target deploys by
  # building a toplevel and running switch-to-configuration, so there is no
  # plane for this to name.
  testOrchestratorIsRefused = moduleKeyFacts "orchestrator" "not this change";

  # The closing test, and the reason the others are a set rather than a
  # selection: the README's table is counted where it lives, and the count is
  # compared against the rows the constructs above cover. A ninth row in the
  # table, or a key added to `excluded.constructs`, fails this.
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
      readmeRowCount = 8;
      coveredRowCount = 8;
      coveredRows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "member cuts"
        "per/deploy/delivery"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      libraryRows = [
        "collect family"
        "externals"
        "lifecycle"
        "locality"
        "member cuts"
        "per/deploy/delivery"
        "placement.pick/strategy/allocation"
        "runtime plane"
      ];
      constructsWithoutATest = [ ];
      testsWithoutAConstruct = [ ];
    };
  };
}
