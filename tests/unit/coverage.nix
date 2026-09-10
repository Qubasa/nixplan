# The specification-to-test cross-walk. A scenario heading names its test by
# construction: test_<snake_case> under pytest, test<CamelCase> under nix-unit.
# A name present in both layers is a failure, not extra coverage.
{
  support,
  changesRoot,
  unitSuites,
  perfSource,
  repoSource,
}:
let
  inherit (builtins)
    attrNames
    attrValues
    concatLists
    concatStringsSep
    elem
    elemAt
    filter
    foldl'
    fromJSON
    genList
    head
    isString
    length
    listToAttrs
    match
    pathExists
    readDir
    readFile
    replaceStrings
    sort
    split
    stringLength
    substring
    ;
  inherit (support) filesUnder hasInfix lines;

  lowerLetters = [
    "a"
    "b"
    "c"
    "d"
    "e"
    "f"
    "g"
    "h"
    "i"
    "j"
    "k"
    "l"
    "m"
    "n"
    "o"
    "p"
    "q"
    "r"
    "s"
    "t"
    "u"
    "v"
    "w"
    "x"
    "y"
    "z"
  ];
  upperLetters = [
    "A"
    "B"
    "C"
    "D"
    "E"
    "F"
    "G"
    "H"
    "I"
    "J"
    "K"
    "L"
    "M"
    "N"
    "O"
    "P"
    "Q"
    "R"
    "S"
    "T"
    "U"
    "V"
    "W"
    "X"
    "Y"
    "Z"
  ];

  toLower = replaceStrings upperLetters lowerLetters;
  capitalise =
    word:
    replaceStrings lowerLetters upperLetters (substring 0 1 word)
    + substring 1 (stringLength word) word;

  words =
    title:
    filter (word: word != "") (
      filter isString (split "[^a-z0-9]+" (toLower (replaceStrings [ "'" "’" ] [ "" "" ] title)))
    );

  snakeName = title: "test_" + concatStringsSep "_" (words title);
  camelName = title: "test" + concatStringsSep "" (map capitalise (words title));

  # The specification files this change answers for. Adding one is one line here.
  accountable = [
    "implement-minimal-typed-edge/specs/planner/typed-edge/spec.md"
    "implement-minimal-typed-edge/specs/planner/diagnostics/spec.md"
    "implement-minimal-typed-edge/specs/planner/plan-artifact/spec.md"
    "implement-minimal-typed-edge/specs/tooling/nix-unit-suite/spec.md"
    "implement-minimal-typed-edge/specs/tooling/evaluation-performance/spec.md"
    "unify-declaration-and-implementation-readings/specs/planner/typed-edge/spec.md"
    "emit-systemd-portable-service-images/specs/planner/unit-vocabulary/spec.md"
    "emit-systemd-portable-service-images/specs/planner/machine-platform/spec.md"
    "emit-systemd-portable-service-images/specs/planner/closure-declaration/spec.md"
    "emit-systemd-portable-service-images/specs/planner/plan-artifact/spec.md"
    "emit-systemd-portable-service-images/specs/realiser/portable-service-image/spec.md"
    "emit-flakelet-service-artifacts/specs/realiser/flakelet-artifact/spec.md"
    "prove-plan-on-real-machines/specs/delivery/real-cluster/spec.md"
    "prove-plan-on-real-machines/specs/planner/plan-artifact/spec.md"
    "strip-planner-tests-to-unit-and-e2e/specs/delivery/real-cluster/spec.md"
    "strip-planner-tests-to-unit-and-e2e/specs/tooling/nix-unit-suite/spec.md"
    "strip-planner-tests-to-unit-and-e2e/specs/tooling/scenario-suite/spec.md"
    "strip-planner-tests-to-unit-and-e2e/specs/tooling/test-layers/spec.md"
    "resume-e2e-machines-from-snapshots/specs/tooling/machine-snapshots/spec.md"
    "resume-e2e-machines-from-snapshots/specs/delivery/real-cluster/spec.md"
    "clean-up-transplant-residue/specs/tooling/repository-shape/spec.md"
    "clean-up-transplant-residue/specs/tooling/nix-unit-suite/spec.md"
    "clean-up-transplant-residue/specs/tooling/evaluation-performance/spec.md"
    "deliver-secrets-across-machines/specs/planner/secret-delivery/spec.md"
    "deliver-secrets-across-machines/specs/planner/diagnostics/spec.md"
    "deliver-secrets-across-machines/specs/planner/typed-edge/spec.md"
    "deliver-secrets-across-machines/specs/planner/plan-artifact/spec.md"
    "deliver-secrets-across-machines/specs/realiser/flakelet-artifact/spec.md"
    "deliver-secrets-across-machines/specs/realiser/portable-service-image/spec.md"
    "deliver-secrets-across-machines/specs/delivery/real-cluster/spec.md"
    "apply-deployments-with-an-operator-command/specs/operator/deployment-build/spec.md"
    "apply-deployments-with-an-operator-command/specs/operator/apply-command/spec.md"
    "apply-deployments-with-an-operator-command/specs/delivery/real-cluster/spec.md"
    "apply-deployments-with-an-operator-command/specs/tooling/test-layers/spec.md"
    "hold-declaration-shape-and-fold-set-reads/specs/planner/interface-fold/spec.md"
    "hold-declaration-shape-and-fold-set-reads/specs/planner/typed-edge/spec.md"
    "hold-declaration-shape-and-fold-set-reads/specs/planner/diagnostics/spec.md"
    "open-the-repository-to-a-consumer/specs/tooling/test-layers/spec.md"
    "generate-values-with-nixos-secrets/specs/planner/secret-delivery/spec.md"
    "generate-values-with-nixos-secrets/specs/planner/plan-artifact/spec.md"
    "generate-values-with-nixos-secrets/specs/realiser/secrets-configuration/spec.md"
    "generate-values-with-nixos-secrets/specs/realiser/portable-service-image/spec.md"
    "generate-values-with-nixos-secrets/specs/delivery/generated-values/spec.md"
    "generate-values-with-nixos-secrets/specs/delivery/real-cluster/spec.md"
    "report-every-refusal-as-a-row/specs/operator/deployment-build/spec.md"
    "report-every-refusal-as-a-row/specs/planner/diagnostics/spec.md"
    "report-every-refusal-as-a-row/specs/planner/plan-artifact/spec.md"
    "report-every-refusal-as-a-row/specs/realiser/flakelet-artifact/spec.md"
    "report-every-refusal-as-a-row/specs/realiser/portable-service-image/spec.md"
    "make-an-apply-observable/specs/operator/apply-command/spec.md"
    "make-an-apply-observable/specs/operator/deployment-build/spec.md"
    "make-an-apply-observable/specs/operator/machine-report/spec.md"
    "make-an-apply-observable/specs/delivery/real-cluster/spec.md"
    "normalise-folds-and-report-refused-reads/specs/planner/interface-fold/spec.md"
    "identify-interfaces-by-declared-id/specs/planner/interface-identity/spec.md"
    "identify-interfaces-by-declared-id/specs/planner/interface-fold/spec.md"
    "identify-interfaces-by-declared-id/specs/planner/typed-edge/spec.md"
    "identify-interfaces-by-declared-id/specs/planner/plan-artifact/spec.md"
    "open-the-repository-to-a-consumer/specs/operator/apply-command/spec.md"
    "open-the-repository-to-a-consumer/specs/tooling/consumer-surface/spec.md"
    "open-the-repository-to-a-consumer/specs/tooling/repository-shape/spec.md"
    "hold-every-stated-guarantee/specs/operator/apply-command/spec.md"
    "hold-every-stated-guarantee/specs/operator/deployment-build/spec.md"
    "hold-every-stated-guarantee/specs/planner/diagnostics/spec.md"
    "hold-every-stated-guarantee/specs/planner/plan-artifact/spec.md"
    "hold-every-stated-guarantee/specs/realiser/portable-service-image/spec.md"
    "hold-every-stated-guarantee/specs/tooling/test-layers/spec.md"
    "hold-every-stated-guarantee/specs/tooling/repository-shape/spec.md"
    "order-a-cycle-by-its-strong-components/specs/operator/apply-command/spec.md"
    "answer-whether-a-machine-is-current/specs/operator/machine-report/spec.md"
  ];

  # Every other spec.md in the repository, with the reason it has no test. Listed
  # rather than ignored, so a new specification fails here instead of passing unseen.
  excused = {
    "add-collect-slot-chain-rules/specs/planner/collect-slots/spec.md" =
      "collect slots are an excluded construct in this implementation: lib/excluded.nix carries the `collect family` row, and tests/unit/exclusions.nix asserts every deployment naming one is refused";
    "add-scenario-test-harness/specs/tooling/scenario-suite/spec.md" =
      "removed by this change's own delta: the committed scenario corpus it specifies no longer exists, and tooling/test-layers replaces it";
    "declare-service-state/specs/planner/plan-artifact/spec.md" =
      "an unimplemented change: no task of declare-service-state has been done, so nothing in this package claims to satisfy it yet";
    "declare-service-state/specs/planner/state-declaration/spec.md" =
      "an unimplemented change: no task of declare-service-state has been done, so nothing in this package claims to satisfy it yet";
    "declare-service-state/specs/realiser/portable-service-image/spec.md" =
      "an unimplemented change: no task of declare-service-state has been done, so nothing in this package claims to satisfy it yet";
    "deliver-a-secret-without-exposing-it/specs/delivery/real-cluster/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "deliver-a-secret-without-exposing-it/specs/operator/apply-command/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "deliver-a-secret-without-exposing-it/specs/operator/machine-identity/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "deliver-a-secret-without-exposing-it/specs/planner/diagnostics/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "deliver-a-secret-without-exposing-it/specs/planner/plan-artifact/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "deliver-a-secret-without-exposing-it/specs/realiser/portable-service-image/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "report-a-secrets-refusal-as-a-row/specs/realiser/secrets-configuration/spec.md" =
      "an unimplemented change: no task of report-a-secrets-refusal-as-a-row has been done, so nothing in this package claims to satisfy it yet";
    "report-a-secrets-refusal-as-a-row/specs/tooling/test-layers/spec.md" =
      "an unimplemented change: no task of report-a-secrets-refusal-as-a-row has been done, so nothing in this package claims to satisfy it yet";
  };

  isSpecFile = path: match ".*/spec\\.md" path != null;
  discovered = filter isSpecFile (filesUnder changesRoot);

  unclassified = sort (a: b: a < b) (
    filter (path: !(elem path accountable) && !(excused ? ${path})) discovered
  );
  vanished = sort (a: b: a < b) (filter (path: !(elem path discovered)) accountable);
  doubled = sort (a: b: a < b) (filter (path: excused ? ${path}) accountable);

  scenarioOf =
    line:
    let
      m = match "#### Scenario: *(.*[^ ]) *" line;
    in
    if m == null then null else head m;

  headingsOf =
    path: filter (h: h != null) (map scenarioOf (lines (readFile (changesRoot + "/${path}"))));

  scenarios = concatLists (
    map (path: map (title: { inherit path title; }) (headingsOf path)) accountable
  );

  located = scenario: "${scenario.path} :: ${scenario.title}";

  unitNamed = concatLists (
    map (
      suite:
      map (name: {
        inherit name;
        file = "tests/unit/${suite}.nix";
      }) unitSuites.${suite}
    ) (attrNames unitSuites)
  );

  e2eRoot = ../e2e;

  isTestFile = name: match "test_[a-z0-9_]*\\.py" name != null;

  testFilesIn =
    dir: prefix:
    map (name: {
      rel = "${prefix}${name}";
      file = dir + "/${name}";
    }) (filter isTestFile (attrNames (readDir dir)));

  e2eDirectories = filter (name: (readDir e2eRoot).${name} == "directory") (
    attrNames (readDir e2eRoot)
  );

  e2eTestFiles =
    testFilesIn e2eRoot "tests/e2e/"
    ++ concatLists (map (name: testFilesIn (e2eRoot + "/${name}") "tests/e2e/${name}/") e2eDirectories);

  defOf =
    line:
    let
      m = match " *def (test_[a-z0-9_]*)\\(.*" line;
    in
    if m == null then null else head m;

  definedIn =
    entry:
    map (name: {
      inherit name;
      inherit (entry) rel;
    }) (filter (n: n != null) (map defOf (lines (readFile entry.file))));

  e2eNamed = concatLists (
    map (
      entry:
      map (d: {
        inherit (d) name;
        file = entry.rel;
      }) (definedIn entry)
    ) e2eTestFiles
  );

  besideNamed =
    map
      (d: {
        inherit (d) name;
        file = "perf/check_test.py";
      })
      (definedIn {
        rel = "perf/check_test.py";
        file = perfSource + "/check_test.py";
      });

  filesByName =
    named:
    listToAttrs (
      map
        (name: {
          inherit name;
          value = sort (a: b: a < b) (map (n: n.file) (filter (n: n.name == name) named));
        })
        (
          attrNames (
            listToAttrs (
              map (n: {
                inherit (n) name;
                value = null;
              }) named
            )
          )
        )
    );

  unitFiles = filesByName unitNamed;
  e2eFiles = filesByName e2eNamed;
  existing = filesByName (unitNamed ++ e2eNamed ++ besideNamed);

  # omitted and aliased are the only two escape hatches. Do not add a third.
  omitted = {
    "A module's own code raises an uncatchable error" =
      "an abort and a missing attribute are what `builtins.tryEval` does not catch, so a test asserting the propagation would abort this suite rather than fail it; `testAModulesOwnCodeRaisesACatchableError` asserts the half that is containable and `docs/diagnostics.md` names the class.";
    "A misspelled capability reference" =
      "the same class: a re-export naming an attribute the member does not provide is a missing attribute, which `builtins.tryEval` does not catch, so the raise cannot be asserted without ending the evaluation that would report it.";
    "An unguarded consumer of a refused fold ends the evaluation" =
      "the same class once more: a refused read leaves the slot absent, so an implementation that reads it unconditionally raises a missing attribute, which `builtins.tryEval` does not catch, and a test of the propagation would abort this suite rather than fail it; `testAGuardedConsumerStillReportsARefusedFold` in tests/unit/resolution.nix asserts the half that is containable, and task 3.2 of normalise-folds-and-report-refused-reads records the measurement that stands in for this one.";
    "A developer runs the suite" =
      "the documented command is what evaluates this suite, so a test of it would be the suite asserting that it had been started; the exit status the scenario is about is `nix build .#checks.x86_64-linux.planner-tests`'s own.";
    "A test fails" =
      "the report a failing comparison prints is nix-unit's, so asserting its shape here would test the runner rather than this project.";
    "The suite is part of the checks" =
      "the check is what evaluates the suite, and reading the flake's checks from inside it is a cycle; `nix flake check` is where the scenario is observed.";
    "A fixture is regenerated" =
      "regeneration writes to the working tree and evaluation cannot, so the command is run by a person; what the suite can assert - that the committed fixture is what the planner produces - is `testTheGoldenPlanMatches`.";
    "Regeneration is not automatic" =
      "for the same reason, in reverse: nothing in the evaluating layer can write to the working tree, so a failing golden comparison has no way to rewrite its own fixture.";
    "A measurement on a clean checkout" =
      "the measurement runs in a build sandbox whose evaluation caches are empty by construction; comparing it against a warm one is a property of two invocations rather than of a value this layer can hold.";
    "A file the measurement does not read is edited" =
      "the observation is a derivation's input set: what a measurement is a measurement of is decided by the four store paths `flake-module.nix` hands `perf/measure.sh`, and this layer cannot read them without reading the flake that runs it. The evidence is recorded instead, in task 4.3 of clean-up-transplant-residue: appending a line to `docs/plan.md` leaves `planner-perf-results.drvPath` equal where it previously moved.";
    "No end-to-end test appears among the checks" =
      "the same cycle as `The suite is part of the checks`: the checks are attributes of the flake that evaluates this suite. It is observed by `nix flake check` completing on a host with no `/dev/kvm`, which is what the machine layer needs.";
  };

  aliased = {
    "A new check raises" = "testEveryAuthoringMistakeAtOnce";
    "The assertion entry point is used" = "testARaisingHelperIsIntroduced";
    "A file rendered over an incomplete set" = "testARenderedFileOverAnIncompleteSet";
    "One service placed on two service managers" = "testOneModulePlacedOnTwoServiceManagers";
    "A consumer populates a filesystem from the closure" = "test_a_command_resolves_inside_the_image";
    "A genuine store path is recognised" = "testAStorePathIsRecognisedByItsGrammar";
    "A short hash is not a store path" = "testAStorePathIsRecognisedByItsGrammar";
    "Two units read different values for one variable" = "testTwoUnitsDisagreeAboutAVariable";
    "A file whose recipe names a secret" = "testAPrivateKeyInThePlan";
    "A store path only a configuration file names" =
      "testAPackageNamedOnlyByAConfigurationFileIsNotDeclared";
    "A secret would be baked in" = "testASecretIsReferencedNotCarried";
    "An image meets the wrong architecture" = "test_an_image_built_for_another_architecture_is_refused";
    "Detaching leaves nothing behind" = "test_detaching_removes_the_units_and_the_staging_directory";
    "A long-running unit is started" = "test_the_unit_runs_from_the_delivered_directory";
    "A long-running unit returns after a reboot" = "test_a_reboot_brings_the_entries_back";
    "The service is reachable" = "test_the_consumer_reaches_the_producer";
    "No test double is involved" = "test_every_participant_is_the_real_one";
    "Nothing else changes with it" = "testAnAddressChanges";
    "An assertion holds for every input" = "testAGeneratorNamesItsProgram";
    "A claimed property needs another observation" = "testTwoAttributedInterfacesConflictWithNoWire";
    "A specification is both accounted for and excused" = "testEverySpecificationIsClassified";
  };

  hasTest = title: existing ? ${snakeName title} || existing ? ${camelName title};

  commonPrefix =
    a: b:
    let
      limit = if stringLength a < stringLength b then stringLength a else stringLength b;
      go = i: if i >= limit || substring i 1 a != substring i 1 b then i else go (i + 1);
    in
    go 0;

  near =
    names: required:
    let
      matched = sort (a: b: a < b) (filter (name: commonPrefix required name >= 12) names);
      shown = if length matched < 4 then length matched else 4;
    in
    genList (i: elemAt matched i) shown;

  unaccountedEntry =
    names: where: title:
    let
      required = "${snakeName title} or ${camelName title}";
      found = near names (snakeName title) ++ near names (camelName title);
    in
    "${where}: needs ${required}"
    + (if found == [ ] then "" else "; the names that exist are ${concatStringsSep ", " found}");

  untested = map (s: unaccountedEntry (attrNames existing) (located s) s.title) (
    filter (s: !(hasTest s.title) && !(omitted ? ${s.title}) && !(aliased ? ${s.title})) scenarios
  );

  titles = map (s: s.title) scenarios;

  omittedTitles = attrNames omitted;
  aliasedTitles = attrNames aliased;

  strandedIn =
    list: referent: names:
    map (name: "${list}: ${name} names no ${referent}") (sort (a: b: a < b) names);

  stranded =
    strandedIn "excused" "spec.md under openspec/changes" (
      filter (path: !(elem path discovered)) (attrNames excused)
    )
    ++ strandedIn "omitted" "scenario heading" (filter (t: !(elem t titles)) omittedTitles)
    ++ strandedIn "aliased" "scenario heading" (filter (t: !(elem t titles)) aliasedTitles);

  collisionsIn =
    unit: e2e:
    sort (a: b: a < b) (
      map (name: "${name}: ${concatStringsSep ", " (unit.${name} ++ e2e.${name})}") (
        filter (name: e2e ? ${name}) (attrNames unit)
      )
    );

  syntheticUnit = {
    testTheWireIsCut = [ "tests/unit/plan.nix" ];
    testTheStoreIsReachable = [ "tests/unit/closure.nix" ];
  };
  syntheticE2e = {
    testTheWireIsCut = [ "tests/e2e/wired-pair/test_wired_pair.py" ];
  };

  # Every figure `docs/tooling.md` records about this layer, against the tree it
  # records them about. The table rows and the two prose totals are read out of
  # the document rather than restated here, so the check is the comparison and
  # not a second copy of the numbers.
  toolingLines = lines (readFile (repoSource + "/docs/tooling.md"));

  figureRows = listToAttrs (
    concatLists (
      map (
        line:
        let
          m = match "[|] `([a-z0-9-]+)` [|] ([0-9]+) [|].*" line;
        in
        if m == null then
          [ ]
        else
          [
            {
              name = head m;
              value = fromJSON (elemAt m 1);
            }
          ]
      ) toolingLines
    )
  );

  # The figure is the number immediately before the words, whether or not the
  # line begins with it and whatever digits a store path or a system name put
  # earlier on it.
  proseFigure =
    words:
    let
      hits = concatLists (
        map (
          line:
          let
            m =
              let
                initial = match "([0-9]+)${words}" line;
              in
              if initial != null then initial else match ".*[^0-9]([0-9]+)${words}" line;
          in
          if m == null then [ ] else [ (fromJSON (head m)) ]
        ) toolingLines
      );
    in
    if hits == [ ] then null else head hits;

  residueNames = [
    "omitted"
    "aliased"
  ];

  keptKeys =
    keep: set:
    listToAttrs (
      map (name: {
        inherit name;
        value = set.${name};
      }) (filter keep (attrNames set))
    );

  suiteFigures = keptKeys (name: !(elem name residueNames)) figureRows;

  countedSuites = builtins.mapAttrs (_: tests: length tests) unitSuites;

  harnessTests = length (
    filter (line: match "def test_.*" line != null) (
      lines (readFile (repoSource + "/tests/e2e/test_harness.py"))
    )
  );

  documentFigures = {
    perSuite = suiteFigures;
    total = proseFigure " tests, counted as the test attributes.*";
    harness = proseFigure " tests over.*";
    harnessAgain = proseFigure " against.*";
    residue = keptKeys (name: elem name residueNames) figureRows;
  };

  treeFigures = {
    perSuite = countedSuites;
    total = foldl' (a: b: a + b) 0 (attrValues countedSuites);
    harness = harnessTests;
    harnessAgain = harnessTests;
    residue = {
      omitted = length omittedTitles;
      aliased = length aliasedTitles;
    };
  };

  # An excuse of the form this repository writes for an unimplemented change
  # names the change. The excuse expires when that change starts landing, and
  # the ground it stands on is its own tasks file.
  excuseNamesChange =
    reason:
    let
      m = match ".*no task of ([a-z0-9-]+) has been done.*" reason;
    in
    if m == null then null else head m;

  changeHasLanded =
    name:
    let
      file = changesRoot + "/${name}/tasks.md";
    in
    pathExists file && filter (line: hasInfix "- [x]" line) (lines (readFile file)) != [ ];

  staleExcuses = sort (a: b: a < b) (
    map (path: "excused: ${path} rests on ${excuseNamesChange excused.${path}} being unimplemented") (
      filter (
        path:
        let
          change = excuseNamesChange excused.${path};
        in
        change != null && changeHasLanded change
      ) (attrNames excused)
    )
  );
in
{
  testATestNameIsDerivedFromAHeading =
    let
      heading = "An end-to-end test carries its own fixture";
    in
    {
      expr = {
        snake = snakeName heading;
        camel = camelName heading;
        again = {
          snake = snakeName heading;
          camel = camelName heading;
        };
        apostrophe = camelName "A module's own code raises";
        digits = camelName "A 32-character run is not a hash";
      };
      expected = {
        snake = "test_an_end_to_end_test_carries_its_own_fixture";
        camel = "testAnEndToEndTestCarriesItsOwnFixture";
        again = {
          snake = "test_an_end_to_end_test_carries_its_own_fixture";
          camel = "testAnEndToEndTestCarriesItsOwnFixture";
        };
        apostrophe = "testAModulesOwnCodeRaises";
        digits = "testA32CharacterRunIsNotAHash";
      };
    };

  testAScenarioGainsNoTest = {
    expr = {
      unaccounted = untested;
      excused = omitted;
    };
    expected = {
      unaccounted = [ ];
      excused = omitted;
    };
  };

  testAScenarioIsDeliberatelyNotTested = {
    expr = {
      unknown = filter (title: !(elem title titles)) omittedTitles;
      reasonless = filter (title: omitted.${title} == "") omittedTitles;
      observed = filter (title: hasTest title) omittedTitles;
    };
    expected = {
      unknown = [ ];
      reasonless = [ ];
      observed = [ ];
    };
  };

  testAScenarioIsObservedUnderAnotherHeading = {
    expr = {
      unknown = filter (title: !(elem title titles)) aliasedTitles;
      missing = filter (title: !(existing ? ${aliased.${title}})) aliasedTitles;
      redundant = filter (title: hasTest title) aliasedTitles;
    };
    expected = {
      unknown = [ ];
      missing = [ ];
      redundant = [ ];
    };
  };

  testAScenarioHeadingIsReworded =
    let
      names = [
        "test_the_consumer_reaches_the_producer"
        "testTheConsumerReachesTheProducer"
        "testSomethingElseEntirely"
      ];
    in
    {
      expr = unaccountedEntry names "spec.md :: x" "The consumer reaches the provider";
      expected =
        "spec.md :: x: needs test_the_consumer_reaches_the_provider or "
        + "testTheConsumerReachesTheProvider; the names that exist are "
        + "test_the_consumer_reaches_the_producer, testTheConsumerReachesTheProducer";
    };

  testOneBehaviourIsAssertedInBothLayers = {
    expr = {
      tree = collisionsIn unitFiles e2eFiles;
      synthetic = collisionsIn syntheticUnit syntheticE2e;
    };
    expected = {
      tree = [ ];
      synthetic = [
        "testTheWireIsCut: tests/unit/plan.nix, tests/e2e/wired-pair/test_wired_pair.py"
      ];
    };
  };

  testEverySpecificationIsClassified = {
    expr = {
      inherit unclassified vanished doubled;
      unreadable = filter (path: !(pathExists (changesRoot + "/${path}"))) accountable;
    };
    expected = {
      unclassified = [ ];
      vanished = [ ];
      doubled = [ ];
      unreadable = [ ];
    };
  };

  testAnExcuseOutlivesItsSpecification = {
    expr = stranded;
    expected = [ ];
  };

  # Both sides are named under the document, so a failure prints the file to
  # edit beside the two numbers.
  testASuiteGainsATest = {
    expr = {
      "docs/tooling.md" = documentFigures;
    };
    expected = {
      "docs/tooling.md" = treeFigures;
    };
  };

  testAnExcuseOutlivesTheStateItDescribes = {
    expr = {
      tree = staleExcuses;
      synthetic = changeHasLanded "hold-every-stated-guarantee";
    };
    expected = {
      tree = [ ];
      synthetic = true;
    };
  };
}
