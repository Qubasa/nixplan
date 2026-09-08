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
          "interface-mismatch"
          "provider-export-missing"
          "reach-one-placement-count"
          "slot-reads-secret-export"
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
}
