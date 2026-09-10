{
  planner,
  support,
  libSource,
}:
let
  inherit (builtins)
    all
    any
    attrNames
    filter
    isString
    length
    split
    substring
    ;

  inherit (support)
    countById
    hasInfix
    messageById
    planOf
    publicString
    rowIds
    severityById
    soleRoot
    subjectsById
    ;

  inherit (planner.util) sortStrings uniqueStrings;

  ids = result: uniqueStrings (rowIds result);

  subjectLines =
    rendered: filter (l: substring 0 4 l == "  ! ") (filter isString (split "\n" rendered));

  renderedBlocks = rendered: filter isString (split "\n\n" rendered);

  identity = planner.interface {
    name = "identity";
    exports = {
      publicKey = publicString;
      privateKey = publicString // {
        secrecy = "secret";
      };
    };
  };

  pub = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
  };

  pair = planner.interface {
    name = "pair";
    exports = {
      a = publicString;
      b = publicString;
    };
  };

  theirs = planner.interface {
    name = "theirs";
    exports.publicKey = publicString;
  };

  quiet = _: {
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  identityProvider = _: {
    provides.thing.interface = identity;
    impl = _: {
      provides.thing.exports = {
        publicKey = "ssh-ed25519 AAAA";
        privateKey = "/run/vars/hostKey/key";
      };
      units.only.command = "/bin/true";
    };
  };

  pubProvider = _: {
    provides.thing.interface = pub;
    impl = _: {
      provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  keysetProvider = _: {
    provides.thing.interface = pair;
    impl = _: {
      provides.thing.exports.a = "x";
      units.only.command = "/bin/true";
    };
  };

  reader = slot: _: {
    uses.slot = slot;
    impl = _: {
      units.only.command = "/bin/true";
    };
  };

  placedOn = machine: module: {
    inherit module;
    placement.every.only.machines = [ machine ];
  };

  wiredTo =
    machine: instance: module:
    (placedOn machine module)
    // {
      wire.slot = {
        inherit instance;
        provides = "thing";
      };
    };

  exposedOn = machines: module: {
    inherit module;
    placement.every.only = { inherit machines; };
    exposes = [ "thing" ];
  };

  everyMistakeArgs = {
    inherit (support) machines;

    interfaces."interfaces/default.nix" = {
      inherit
        identity
        pub
        pair
        theirs
        ;
    };

    instances = {
      identityProvider = exposedOn [ "one" ] (soleRoot {
        module = identityProvider;
        provides = [ "thing" ];
      });

      shared = exposedOn [ "one" "two" ] (soleRoot {
        module = pubProvider;
        provides = [ "thing" ];
      });

      keysetProvider = placedOn "one" (soleRoot {
        module = keysetProvider;
        provides = [ "thing" ];
      });

      unwiredReader = placedOn "one" (soleRoot {
        module = reader {
          interface = identity;
          reads = [ "publicKey" ];
        };
      });

      secretReader = wiredTo "one" "identityProvider" (soleRoot {
        module = reader {
          interface = identity;
          reads = [ "privateKey" ];
        };
      });

      arityReader = wiredTo "one" "shared" (soleRoot {
        module = reader {
          interface = pub;
          reach = "one";
          reads = [ "publicKey" ];
        };
      });

      mismatchReader = wiredTo "one" "shared" (soleRoot {
        module = reader {
          interface = theirs;
          reads = [ "publicKey" ];
        };
      });
    };

    sources.leaves = {
      identityProvider.only = "modules/identity-provider.nix";
      shared.only = "modules/pub-provider.nix";
      keysetProvider.only = "modules/keyset-provider.nix";
      unwiredReader.only = "modules/unwired-reader.nix";
      secretReader.only = "modules/secret-reader.nix";
      arityReader.only = "modules/arity-reader.nix";
      mismatchReader.only = "modules/mismatch-reader.nix";
    };
  };

  everyMistake = planner.mkPlan everyMistakeArgs;

  oneBad = planOf {
    instances = {
      good = placedOn "one" (soleRoot {
        module = quiet;
      });
      bad = placedOn "two" (soleRoot {
        module = _: { };
      });
    };
    sources.leaves.bad.only = "modules/bad.nix";
  };

  # Calls that raise. None may appear in library code. Comment lines are dropped
  # before the scan, so prose may name one, but a trailing comment on a line of code
  # counts as code.
  raising = [
    "throw"
    "abort"
    "assert "
    ".check "
    ".check("
    "korora.check"
  ];

  libraryFiles = filter (rel: hasInfix ".nix" rel) (support.filesUnder libSource);

  isComment = line: builtins.match "[[:space:]]*#.*" line != null;

  raises = builtins.concatLists (
    map (
      rel:
      let
        code = filter (line: !isComment line) (support.lines (builtins.readFile (libSource + "/${rel}")));
      in
      builtins.concatLists (
        map (call: map (_: "${rel}: ${call}") (filter (line: hasInfix call line) code)) raising
      )
    ) libraryFiles
  );

  # A fold that refuses: it states why, and the planner decides the row's
  # identifier, its subject and its severity.
  refusing = planner.interface {
    name = "pub";
    exports.publicKey = publicString;
    fold = set: {
      refused = "the set names ${toString (length (attrNames set))} provider and none of them is authoritative";
    };
  };

  refusingProvider = _: {
    provides.thing.interface = refusing;
    impl = _: {
      provides.thing.exports.publicKey = "ssh-ed25519 AAAA";
      units.only.command = "/bin/true";
    };
  };

  setReader = _: {
    uses.slot = {
      interface = refusing;
      reach = "all";
      reads = [ "publicKey" ];
    };
    impl =
      { results, ... }:
      {
        units.only = {
          command = "/bin/true";
          env.SLOTS = builtins.concatStringsSep "," (attrNames results);
        };
      };
  };

  refusedFold =
    readers:
    planOf {
      interfaces."interfaces/folded.nix".refusing = refusing;
      instances = {
        vault = exposedOn [ "one" ] (soleRoot {
          module = refusingProvider;
          provides = [ "thing" ];
        });
      }
      // builtins.listToAttrs (
        map (name: {
          inherit name;
          value = wiredTo "one" "vault" (soleRoot {
            module = setReader;
          });
        }) readers
      );
    };

  twoRefusedFolds = refusedFold [
    "first"
    "second"
  ];
in
{
  testADeploymentWithOneBadInstance = {
    expr = {
      planKeys = attrNames oneBad.plan;
      goodEntryIsWhole = attrNames oneBad.plan."good:only@one".units;
      rows = ids oneBad;
      subjects = subjectsById "impl-missing" oneBad;
      applicable = oneBad.applicable;
    };
    expected = {
      planKeys = [
        "bad:only@two"
        "good:only@one"
        "machine:one"
        "machine:two"
      ];
      goodEntryIsWhole = [ "only" ];
      rows = [ "impl-missing" ];
      subjects = [ "modules/bad.nix" ];
      applicable = false;
    };
  };

  testADeploymentWithNoMistakes =
    let
      result = planOf {
        instances.good = placedOn "one" (soleRoot {
          module = quiet;
        });
      };
    in
    {
      expr = {
        carriesATable = result ? diagnostics;
        isList = builtins.isList result.diagnostics;
        rows = result.diagnostics;
        carriesAPlan = attrNames result.plan;
        applicable = result.applicable;
      };
      expected = {
        carriesATable = true;
        isList = true;
        rows = [ ];
        carriesAPlan = [
          "good:only@one"
          "machine:one"
        ];
        applicable = true;
      };
    };

  testEveryAuthoringMistakeAtOnce =
    let
      forced = builtins.tryEval (builtins.deepSeq everyMistake everyMistake);
    in
    {
      expr = {
        forcingSucceeds = forced.success;
        rows = ids everyMistake;
        rowCount = length everyMistake.diagnostics;
        planIsWhole = length (attrNames everyMistake.plan);
        applicable = everyMistake.applicable;
      };
      expected = {
        forcingSucceeds = true;
        rows = [
          "export-secret-not-a-reference"
          "interface-mismatch"
          "provider-export-missing"
          "reach-one-placement-count"
          "slot-unwired"
        ];
        rowCount = 5;
        planIsWhole = 10;
        applicable = false;
      };
    };

  testAModulesOwnCodeRaisesACatchableError =
    let
      raising = _: {
        impl = _: {
          units.only.command = throw "the module author's own mistake";
        };
      };
      result = planOf {
        instances = {
          broken = placedOn "one" (soleRoot {
            module = raising;
          });
          quiet = placedOn "two" (soleRoot {
            module = quiet;
          });
        };
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "module-raised" result;
        namesTheModule = hasInfix "broken:only@one" (messageById "module-raised" result);
        subjects = subjectsById "module-raised" result;
        restOfThePlan = attrNames result.plan;
        otherEntryIsWhole = attrNames result.plan."quiet:only@two".units;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "module-raised" ];
        severity = "error";
        namesTheModule = true;
        subjects = [ "broken:only@one" ];
        restOfThePlan = [
          "broken:only@one"
          "machine:one"
          "machine:two"
          "quiet:only@two"
        ];
        otherEntryIsWhole = [ "only" ];
        applicable = false;
      };
    };

  testTwoRunsOverOneInput =
    let
      first = planner.mkPlan everyMistakeArgs;
      second = planner.mkPlan everyMistakeArgs;
    in
    {
      expr = {
        tablesEqual = first.diagnostics == second.diagnostics;
        idsEqual = rowIds first == rowIds second;
        orderIsById = rowIds first == sortStrings (rowIds first);
        rowCount = length first.diagnostics;
      };
      expected = {
        tablesEqual = true;
        idsEqual = true;
        orderIsById = true;
        rowCount = 5;
      };
    };

  testARowCarriesItsResolution =
    let
      rows = everyMistake.diagnostics;
      namesAFileOrACommand = r: hasInfix ".nix" r.resolution || hasInfix "`" r.resolution;
    in
    {
      expr = {
        rowCount = length rows;
        everyResolutionIsNonEmpty = all (r: r.resolution != "") rows;
        noneRestatesTheMessage = all (r: r.resolution != r.message) rows;
        everyResolutionNamesAFileOrACommand = all namesAFileOrACommand rows;
      };
      expected = {
        rowCount = 5;
        everyResolutionIsNonEmpty = true;
        noneRestatesTheMessage = true;
        everyResolutionNamesAFileOrACommand = true;
      };
    };

  testAnErrorBlocksTheApply = {
    expr = {
      applicable = oneBad.applicable;
      hasAnError = any (r: r.severity == "error") oneBad.diagnostics;
      entryCount = length (attrNames oneBad.plan);
      badEntryStillThere = oneBad.plan ? "bad:only@two";
    };
    expected = {
      applicable = false;
      hasAnError = true;
      entryCount = 4;
      badEntryStillThere = true;
    };
  };

  testAWarningDoesNotBlockTheApply =
    let
      result = planOf {
        instances = {
          provider = exposedOn [ "one" ] (soleRoot {
            module = pubProvider;
            provides = [ "thing" ];
          });
          setReader = wiredTo "two" "provider" (soleRoot {
            module = reader {
              interface = pub;
              reach = "all";
              reads = [ "publicKey" ];
            };
          });
        };
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "set-read-in-key" result;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "set-read-in-key" ];
        severity = "warning";
        applicable = true;
      };
    };

  testAModuleAuthorCannotSetASeverity =
    let
      result = planOf {
        instances.retagging = placedOn "one" (soleRoot {
          module = reader {
            interface = pub;
            reads = [ "publicKey" ];
            severity = "warning";
          };
        });
        sources.leaves.retagging.only = "modules/retagging.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        attemptRows = countById "module-declared-severity" result;
        attemptSeverity = severityById "module-declared-severity" result;
        namesTheModule = hasInfix "modules/retagging.nix" (messageById "module-declared-severity" result);
        retaggedRowSeverity = severityById "slot-unwired" result;
      };
      expected = {
        rows = [
          "module-declared-severity"
          "slot-unwired"
        ];
        attemptRows = 1;
        attemptSeverity = "warning";
        namesTheModule = true;
        retaggedRowSeverity = "error";
      };
    };

  testRenderingTheFoldersOwnRows =
    let
      table = support.workedResult.diagnostics;
      rendered = planner.render table;
      blocks = renderedBlocks rendered;
      renderedAs =
        r:
        any (
          b: hasInfix "  ! ${r.subject}  ${r.message}" b && hasInfix "      severity: ${r.severity}" b
        ) blocks;
    in
    {
      expr = {
        rowCount = length table;
        oneBlockPerRow = length blocks == length table;
        everyRowRendered = all renderedAs table;
        readsTheDeploymentAgain = hasInfix "fixtures/minimal-typed-edge" rendered;
      };
      expected = {
        rowCount = 2;
        oneBlockPerRow = true;
        everyRowRendered = true;
        readsTheDeploymentAgain = false;
      };
    };

  testRenderingIsStableUnderUnrelatedChange =
    let
      extended = planner.mkPlan (
        support.worked.args
        // {
          instances = support.worked.args.instances // {
            quiet = {
              module = soleRoot { module = quiet; };
              placement.every.only.machines = [ "vault" ];
            };
          };
        }
      );
    in
    {
      expr = {
        renderedUnchanged =
          planner.render extended.diagnostics == planner.render support.workedResult.diagnostics;
        tableUnchanged = extended.diagnostics == support.workedResult.diagnostics;
        theInstanceLanded = extended.plan ? "quiet:only@vault";
        entriesGained = length (attrNames extended.plan) - length (attrNames support.workedResult.plan);
      };
      expected = {
        renderedUnchanged = true;
        tableUnchanged = true;
        theInstanceLanded = true;
        entriesGained = 1;
      };
    };

  testARowWhoseSubjectIsAnAbsolutePath =
    let
      absolute = "/home/someone/checkout/deployment/machines.nix";
      result = planner.mkPlan {
        machines.one = {
          address = "one.example:22";
          tags = [ ];
          system = "x86_64-linux";
          serviceManager = "systemd";
          region = "eu-west";
        };
        instances.i = placedOn "one" (soleRoot {
          module = quiet;
        });
        sources.machines = absolute;
      };
      rendered = planner.render result.diagnostics;
    in
    {
      expr = {
        rows = ids result;
        invalidRows = countById "diagnostic-subject-invalid" result;
        severity = severityById "diagnostic-subject-invalid" result;
        namesTheRowThatCarriedIt = hasInfix "`declaration-unknown-key`" (
          messageById "diagnostic-subject-invalid" result
        );
        subjects = uniqueStrings (map (r: r.subject) result.diagnostics);
        noSubjectLineCarriesTheAbsolutePath = !any (l: hasInfix absolute l) (subjectLines rendered);
        subjectLineCount = length (subjectLines rendered);
      };
      expected = {
        rows = [
          "declaration-unknown-key"
          "diagnostic-subject-invalid"
        ];
        invalidRows = 1;
        severity = "error";
        namesTheRowThatCarriedIt = true;
        subjects = [ "machines.nix" ];
        noSubjectLineCarriesTheAbsolutePath = true;
        subjectLineCount = 2;
      };
    };

  testARaisingHelperIsIntroduced = {
    expr = {
      calls = raises;
      readAtLeastOneFile = libraryFiles != [ ];
    };
    expected = {
      calls = [ ];
      readAtLeastOneFile = true;
    };
  };

  testAModuleDeclaresASeverity =
    let
      result = planOf {
        instances.tagging = placedOn "one" (soleRoot {
          module = _: {
            provides.thing = {
              interface = pub;
              severity = "warning";
            };
            impl = _: {
              units.only.command = "/bin/true";
            };
          };
          provides = [ "thing" ];
        });
        sources.leaves.tagging.only = "modules/tagging.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        readAndDiscarded = countById "module-declared-severity" result;
        itsOwnSeverity = severityById "module-declared-severity" result;
        namesTheModule = hasInfix "modules/tagging.nix" (messageById "module-declared-severity" result);
        theOtherRowKeepsThePlannersSeverity = severityById "provider-export-missing" result;
      };
      expected = {
        rows = [
          "module-declared-severity"
          "provider-export-missing"
        ];
        readAndDiscarded = 1;
        itsOwnSeverity = "warning";
        namesTheModule = true;
        theOtherRowKeepsThePlannersSeverity = "error";
      };
    };

  testAnImplementationReturnsARefusalsField =
    let
      result = planOf {
        instances.refusing = placedOn "one" (soleRoot {
          module = _: {
            impl = _: {
              units.only.command = "/bin/true";
              refusals = [ "the far end is wrong" ];
            };
          };
        });
        sources.leaves.refusing.only = "modules/refusing.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "implementation-unknown-key" result;
        namesTheKey = hasInfix "`refusals`" (messageById "implementation-unknown-key" result);
        namesTheFold = hasInfix "belongs in the fold of the interface that carries it" (
          support.resolutionById "implementation-unknown-key" result
        );
        applicable = result.applicable;
      };
      expected = {
        rows = [ "implementation-unknown-key" ];
        severity = "error";
        namesTheKey = true;
        namesTheFold = true;
        applicable = false;
      };
    };

  testAFoldRefusesAProvider =
    let
      result = refusedFold [ "reader" ];
      row = builtins.head (support.rowsById "interface-fold-refused" result);
    in
    {
      expr = {
        rows = ids result;
        inherit (row) subject severity message;
        namesTheEntries = hasInfix "`vault:only@one`" row.evidence;
        theSlotIsUndelivered = result.plan."reader:only@one".units.only.env.SLOTS;
        applicable = result.applicable;
      };
      expected = {
        rows = [ "interface-fold-refused" ];
        subject = "reader:only";
        severity = "error";
        message = "the set names 1 provider and none of them is authoritative";
        namesTheEntries = true;
        theSlotIsUndelivered = "";
        applicable = false;
      };
    };

  testOneBadProviderReadByTwoConsumers =
    let
      result = twoRefusedFolds;
      rows = support.rowsById "interface-fold-refused" result;
    in
    {
      expr = {
        rows = length rows;
        subjects = sortStrings (map (r: r.subject) rows);
        messages = uniqueStrings (map (r: r.message) rows);
        neitherWasDropped = all (r: r.severity == "error") rows;
      };
      expected = {
        rows = 2;
        subjects = [
          "first:only"
          "second:only"
        ];
        messages = [ "the set names 1 provider and none of them is authoritative" ];
        neitherWasDropped = true;
      };
    };

  testAModuleRaisesOutsideAFold =
    let
      result = planOf {
        instances.broken = placedOn "one" (soleRoot {
          module = _: {
            impl = _: {
              units.only.command = throw "unknown module 'pam_unix'. Provide a `package` field";
            };
          };
        });
        sources.leaves.broken.only = "modules/broken.nix";
      };
    in
    {
      expr = {
        rows = ids result;
        severity = severityById "module-raised" result;
        namesWhatWasForced = hasInfix "broken:only@one" (messageById "module-raised" result);
        carriesTheModulesOwnText = hasInfix "pam_unix" (messageById "module-raised" result);
        applicable = result.applicable;
      };
      expected = {
        rows = [ "module-raised" ];
        severity = "error";
        namesWhatWasForced = true;
        carriesTheModulesOwnText = false;
        applicable = false;
      };
    };
}
