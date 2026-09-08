# Evaluation as total: a plan and a table of rows come out together, no check
# aborts the pass, and every refusal is a record a user interface can draw.
#
# One test per scenario of specs/planner/diagnostics/spec.md that is observable
# from outside the library, named after that scenario. `A raising helper is
# introduced` is a property of the library's own source rather than of any one
# evaluation - one convenient call is all it takes to delete totality - so it is
# a text scan over every library file, here, next to the `tryEval (deepSeq …)`
# property it defends. `A module's own code raises an uncatchable error` is
# recorded as a deliberate omission in the cross-walk, because an abort and a
# missing attribute are exactly what `builtins.tryEval` does not catch, so a
# test asserting the propagation would abort the suite instead of failing it.
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

  # `uniqueStrings` returns its input sorted, which is the order a table is
  # already in: by identifier first.
  ids = result: uniqueStrings (rowIds result);

  # The subject column of a rendered table: the `  ! <subject>  <message>` line
  # of every row and nothing else. A row's message, evidence and resolution name
  # the file an author has to edit, so those lines carry whatever the deployment
  # handed the planner in `sources`; the subject is the one field the library
  # disciplines, and it is what a rendered table is compared across checkouts by.
  subjectLines =
    rendered: filter (l: substring 0 4 l == "  ! ") (filter isString (split "\n" rendered));

  renderedBlocks = rendered: filter isString (split "\n\n" rendered);

  # Interfaces. Two same-shaped-and-different values for the mismatch, a pair
  # for the keyset violation, and one carrying a secret half for the read a slot
  # may not name.
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

  # Leaf modules. Each one asks for exactly the mistake its instance is about
  # and is otherwise complete, so that a scenario's expected row set is the row
  # set the deployment produces.
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

  # Publishes `a` and not `b`: a provider's keyset equals its interface's.
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

  # One deployment carrying five different authoring mistakes at once: an
  # unwired slot, a secret read, a keyset violation, an arity violation and an
  # interface mismatch. `shared` serves the last two ends at once — it is placed
  # twice, which is the arity violation for a slot declaring reach `one`, and it
  # declares `pub` where the mismatching reader declares `theirs`.
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

    # Leaf files, so that the rows about a module name a file rather than
    # reporting that the deployment never recorded one.
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

  # Two instances, one of which forgot its `impl`.
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

  # korora's `check` raises, and so do `throw`, `abort` and `assert`. None of
  # them may appear in library code; a comment naming one is prose.
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
  # More than one instance and one mistake: the plan holds the entries of the
  # instance that is correct and the table holds the row of the one that is not.
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

  # No mistakes: the table is present and empty rather than absent, so a caller
  # never has to distinguish "no rows" from "no table".
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

  # The total-evaluation property. Five different mistakes in one deployment:
  # deeply forcing the whole result succeeds inside the catch, and the table
  # carries one row per mistake rather than the first one found.
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

  # A module raising inside its receiving half: an error row naming that
  # module's entry, and every other entry of the plan still produced.
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

  # Two evaluations of one input: the tables are equal including order, and the
  # order is the one the library commits to, identifier then subject.
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

  # Every row of a table carrying several rows: a resolution that is not the
  # message restated, naming the file to edit or the construct to write.
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

  # An error blocks the apply and removes nothing: the plan is readable in full
  # beside the refusal.
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

  # A warning does not block the apply. The one row this deployment produces is
  # the set-valued read's re-keying warning, and the plan is applicable with it.
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

  # A module declaring a severity: a warning row naming the module, and the row
  # the declaration would have retagged keeps the severity the planner gave it.
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

  # Rendering the worked deployment's own table: one rendered block per row,
  # each carrying that row's subject, message and severity. Asserted against the
  # records rather than against a hand-copied string, so the test states the
  # relation the format has to the table and not the format's bytes.
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

  # An instance that produces no rows leaves the rendered table byte for byte
  # what it was, while the plan grows the entry that instance describes.
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

  # Task 5.3. A row whose subject is a path the deployment wrote absolutely: the
  # subject is reduced to its last component, a second row names the identifier
  # that carried it, and no rendered subject line differs between checkouts.
  # The message and the resolution of the offending row do name the absolute
  # path, because they name the file its author has to edit; the subject is the
  # field the library disciplines and the one a rendered table is compared by.
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

  # Totality is a promise about every path, so it is asserted over the library's
  # own text rather than over one evaluation: a `throw` added to any file of
  # `lib/` is a failure naming the file and the call.
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
