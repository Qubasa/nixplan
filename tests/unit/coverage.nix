# The cross-walk between this project's specifications and the tests that
# observe them. There is no committed table of pairs: a `#### Scenario:` heading
# names its test by construction, and this suite is the set difference between
# the headings and the test names that exist.
#
# A heading yields two spellings, one per layer - `test_<snake>` for a pytest
# test on a machine and `test<Camel>` for a nix-unit test in evaluation - so a
# name present in both layers is a behaviour asserted twice, which is a failure
# here rather than a matter of an author's judgement.
#
# The residue a derivation cannot produce is the two attrsets below, and nothing
# else: `omitted` maps a heading to the reason it is unobserved, and `aliased`
# maps a heading to the test that observes it under another capability's words.
{
  support,
  changesRoot,
  unitSuites,
  perfSource,
}:
let
  inherit (builtins)
    attrNames
    concatLists
    concatStringsSep
    elem
    elemAt
    filter
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
  inherit (support) filesUnder lines;

  # ---------------------------------------------------------------- naming --

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

  # A heading's words. An apostrophe is dropped rather than split on, so
  # `A module's own code` is `modules` and not `module` `s`; every other run of
  # non-alphanumerics is one separator, so a hyphen, a comma and a space are the
  # same thing and `end-to-end` is three words.
  words =
    title:
    filter (word: word != "") (
      filter isString (split "[^a-z0-9]+" (toLower (replaceStrings [ "'" "’" ] [ "" "" ] title)))
    );

  snakeName = title: "test_" + concatStringsSep "_" (words title);
  camelName = title: "test" + concatStringsSep "" (map capitalise (words title));

  # --------------------------------------------------------- specifications --

  # The `spec.md` files this package's tests are accountable for. Written as
  # paths under `openspec/changes/` rather than as four roots, so adding one is
  # one line and a file that vanishes is a named failure below.
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
    "clean-up-transplant-residue/specs/tooling/repository-shape/spec.md"
    "clean-up-transplant-residue/specs/tooling/nix-unit-suite/spec.md"
    "clean-up-transplant-residue/specs/tooling/evaluation-performance/spec.md"
  ];

  # Every other `spec.md` in the repository, with the reason this package's
  # tests are not accountable for it. Listed rather than ignored, so a new
  # specification is a failure here instead of a silence.
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
  };

  # Every `spec.md` under `openspec/changes/`, so that a path dropped from
  # `accountable` reappears here as an unclassified file rather than as a
  # quietly smaller check.

  isSpecFile = path: match ".*/spec\\.md" path != null;
  discovered = filter isSpecFile (filesUnder changesRoot);

  unclassified = sort (a: b: a < b) (
    filter (path: !(elem path accountable) && !(excused ? ${path})) discovered
  );
  vanished = sort (a: b: a < b) (filter (path: !(elem path discovered)) accountable);

  scenarioOf =
    line:
    let
      m = match "#### Scenario: *(.*[^ ]) *" line;
    in
    if m == null then null else head m;

  headingsOf =
    path: filter (h: h != null) (map scenarioOf (lines (readFile (changesRoot + "/${path}"))));

  # Every scenario of every accountable specification, with the file it is in:
  # the same title appears in more than one capability, and a failure that does
  # not say which file it is in is a failure a reader has to go looking for.
  scenarios = concatLists (
    map (path: map (title: { inherit path title; }) (headingsOf path)) accountable
  );

  located = scenario: "${scenario.path} :: ${scenario.title}";

  # --------------------------------------------------------- the two layers --

  # The evaluating layer: one file per suite, whose attribute names are its
  # test names.
  unitNamed = concatLists (
    map (
      suite:
      map (name: {
        inherit name;
        file = "tests/unit/${suite}.nix";
      }) unitSuites.${suite}
    ) (attrNames unitSuites)
  );

  # The machine layer, discovered rather than enumerated: `tests/e2e/<name>/`
  # holds one test file, and the layer root holds the harness and its own tests.
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

  # The perf checker's own unittest. It is beside the tool it tests rather than
  # in either planner layer - `perf/check.py` is a budget checker, not the
  # planner - but the scenarios of `tooling/evaluation-performance` that it
  # observes are this package's, so its names count as tests that exist. Calling
  # them omissions would be a false sentence in the omissions list.
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

  # name -> the files that define it, per layer and across all of them.
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

  # ------------------------------------------------------------ the residue --

  # A scenario this project deliberately does not observe, and why. A reason is
  # a sentence a reviewer reads, not a marker.
  #
  # Two classes and nothing else: a failure the interpreter does not let a test
  # catch, and a property of running the suite that the suite cannot observe
  # about itself without importing the flake that runs it.
  omitted = {
    "A module's own code raises an uncatchable error" =
      "an abort and a missing attribute are what `builtins.tryEval` does not catch, so a test asserting the propagation would abort this suite rather than fail it; `testAModulesOwnCodeRaisesACatchableError` asserts the half that is containable and `docs/diagnostics.md` names the class.";
    "A misspelled capability reference" =
      "the same class: a re-export naming an attribute the member does not provide is a missing attribute, which `builtins.tryEval` does not catch, so the raise cannot be asserted without ending the evaluation that would report it.";
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

  # A scenario observed by a test named after another heading, because two
  # capabilities describe one behaviour in different words. The value is the
  # name of the one test that observes it.
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
  };

  # ------------------------------------------------------------- the checks --

  hasTest = title: existing ? ${snakeName title} || existing ? ${camelName title};

  # When a heading's derived name is absent, the failure has to say what the
  # heading now requires and what is there instead, or a rewording reads as a
  # test that was never written. `near` is the existing names that share a long
  # prefix with the required one, which is what a rename leaves behind.
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

  # An entry of a list the cross-walk carries that names something the
  # repository no longer has: an excuse for a deleted specification, an
  # omission or an alias for a reworded heading. Such an entry reads as a
  # decision this project has taken about something it does not have, so it
  # fails naming the list, the entry and what the entry referred to.
  strandedIn =
    list: referent: names:
    map (name: "${list}: ${name} names no ${referent}") (sort (a: b: a < b) names);

  stranded =
    strandedIn "excused" "spec.md under openspec/changes" (
      filter (path: !(elem path discovered)) (attrNames excused)
    )
    ++ strandedIn "omitted" "scenario heading" (filter (t: !(elem t titles)) omittedTitles)
    ++ strandedIn "aliased" "scenario heading" (filter (t: !(elem t titles)) aliasedTitles);

  # A collision is one derived name defined in both layers. It names the two
  # files, because "asserted twice" is only actionable when the reader is told
  # where.
  collisionsIn =
    unit: e2e:
    sort (a: b: a < b) (
      map (name: "${name}: ${concatStringsSep ", " (unit.${name} ++ e2e.${name})}") (
        filter (name: e2e ? ${name}) (attrNames unit)
      )
    );

  # A synthetic pair of layers, so the detector itself is asserted rather than
  # only its answer over a tree that happens to be clean.
  syntheticUnit = {
    testTheWireIsCut = [ "tests/unit/plan.nix" ];
    testTheStoreIsReachable = [ "tests/unit/closure.nix" ];
  };
  syntheticE2e = {
    testTheWireIsCut = [ "tests/e2e/wired-pair/test_wired_pair.py" ];
  };
in
{
  # A heading is a function of its own words, in both spellings, and the same
  # heading yields the same pair every time it appears.
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

  # Every scenario is observed, aliased or excused. `excused` is echoed so that
  # a failure prints the reasons this project has already accepted beside the
  # headings it has not accounted for.
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

  # An omission names a heading that exists, carries a reason, and is not also
  # observed: an omission for a scenario that gained a test is stale.
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

  # An alias names a heading that exists and a test that exists, and is not
  # needed for a heading whose own derived name is already a test.
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

  # A reworded heading is a required name nothing answers to. What makes the
  # failure actionable rather than a mystery is that it shows both the name the
  # heading now requires and the name that is still there; the tree's own
  # residue is `testAScenarioGainsNoTest`'s subject, not this one's.
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

  # One behaviour, one layer. A derived name defined in both is reported with
  # the heading's name and both files.
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

  # Every `spec.md` in the repository is either one this package's tests answer
  # for or one with a written reason they do not. A path dropped from the
  # accountable set reappears as `unclassified`, naming the file, rather than
  # reducing the check in silence; a path that no longer exists is `vanished`.
  testEverySpecificationIsClassified = {
    expr = {
      inherit unclassified vanished;
      unreadable = filter (path: !(pathExists (changesRoot + "/${path}"))) accountable;
    };
    expected = {
      unclassified = [ ];
      vanished = [ ];
      unreadable = [ ];
    };
  };

  # The cross-walk's second direction. `testEverySpecificationIsClassified`
  # reads the repository and asks whether every specification is answered for;
  # this one reads the three lists and asks whether everything they name is
  # still here, so a list cannot accumulate entries for files and headings that
  # are gone.
  testAnExcuseOutlivesItsSpecification = {
    expr = stranded;
    expected = [ ];
  };
}
