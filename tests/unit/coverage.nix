# The specification-to-test cross-walk. A scenario heading names its test by
# construction: test_<snake_case> under pytest, test<CamelCase> under nix-unit.
# A name present in both layers is a failure, not extra coverage.
{
  support,
  openspecRoot,
  unitSuites,
  perfSource,
  repoSource,
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
  inherit (support) filesUnder hasInfix lines;

  letters = alphabet: genList (i: substring i 1 alphabet) 26;
  lowerLetters = letters "abcdefghijklmnopqrstuvwxyz";
  upperLetters = letters "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

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

  # The specification files this repository answers for: one per current capability,
  # plus the delta of an open change whose work has landed. Adding one is one line.
  accountable = [
    "specs/delivery/generated-values/spec.md"
    "specs/delivery/real-cluster/spec.md"
    "specs/operator/apply-command/spec.md"
    "specs/operator/deployment-build/spec.md"
    "specs/operator/machine-report/spec.md"
    "specs/planner/closure-declaration/spec.md"
    "specs/planner/diagnostics/spec.md"
    "specs/planner/interface-fold/spec.md"
    "specs/planner/interface-identity/spec.md"
    "specs/planner/machine-platform/spec.md"
    "specs/planner/plan-artifact/spec.md"
    "specs/planner/secret-delivery/spec.md"
    "specs/planner/typed-edge/spec.md"
    "specs/planner/unit-vocabulary/spec.md"
    "specs/realiser/flakelet-artifact/spec.md"
    "specs/realiser/portable-service-image/spec.md"
    "specs/realiser/secrets-configuration/spec.md"
    "specs/tooling/consumer-surface/spec.md"
    "specs/tooling/evaluation-performance/spec.md"
    "specs/tooling/machine-snapshots/spec.md"
    "specs/tooling/nix-unit-suite/spec.md"
    "specs/tooling/repository-shape/spec.md"
    "specs/tooling/test-layers/spec.md"
    "changes/answer-whether-a-machine-is-current/specs/operator/machine-report/spec.md"
    "changes/enroll-a-friend-machine/specs/operator/machine-enrollment/spec.md"
    "changes/run-an-entry-without-root/specs/operator/apply-command/spec.md"
    "changes/run-an-entry-without-root/specs/operator/deployment-build/spec.md"
    "changes/run-an-entry-without-root/specs/planner/machine-platform/spec.md"
    "changes/run-an-entry-without-root/specs/realiser/flakelet-artifact/spec.md"
    "changes/run-an-entry-without-root/specs/realiser/portable-service-image/spec.md"
    "changes/probe-a-service-before-it-counts-as-live/specs/planner/unit-vocabulary/spec.md"
    "changes/probe-a-service-before-it-counts-as-live/specs/realiser/flakelet-artifact/spec.md"
    "changes/probe-a-service-before-it-counts-as-live/specs/realiser/portable-service-image/spec.md"
    "changes/retire-an-entry-a-build-no-longer-names/specs/operator/apply-command/spec.md"
    "changes/retire-an-entry-a-build-no-longer-names/specs/operator/deployment-build/spec.md"
    "changes/retire-an-entry-a-build-no-longer-names/specs/operator/machine-report/spec.md"
    "changes/unseal-a-value-after-a-reboot/specs/delivery/generated-values/spec.md"
    "changes/unseal-a-value-after-a-reboot/specs/operator/apply-command/spec.md"
    "changes/unseal-a-value-after-a-reboot/specs/operator/deployment-build/spec.md"
    "changes/unseal-a-value-after-a-reboot/specs/operator/machine-report/spec.md"
    "changes/unseal-a-value-after-a-reboot/specs/planner/machine-platform/spec.md"
    "changes/unseal-a-value-after-a-reboot/specs/planner/secret-delivery/spec.md"
  ];

  # Every other spec.md in the repository, with the reason it has no test. Listed
  # rather than ignored, so a new specification fails here instead of passing unseen.
  excused = {
    "changes/account-for-every-counterexample/specs/tooling/test-layers/spec.md" =
      "an unimplemented change: no task of account-for-every-counterexample has been done, so nothing in this package claims to satisfy it yet";
    "changes/hold-the-attach-script-to-its-own-discipline/specs/realiser/portable-service-image/spec.md" =
      "an unimplemented change: no task of hold-the-attach-script-to-its-own-discipline has been done, so nothing in this package claims to satisfy it yet";
    "changes/hold-the-attach-script-to-its-own-discipline/specs/tooling/nix-unit-suite/spec.md" =
      "an unimplemented change: no task of hold-the-attach-script-to-its-own-discipline has been done, so nothing in this package claims to satisfy it yet";
    "changes/hold-the-index-to-the-tree/specs/tooling/repository-shape/spec.md" =
      "an unimplemented change: no task of hold-the-index-to-the-tree has been done, so nothing in this package claims to satisfy it yet";
    "changes/deliver-a-secret-without-exposing-it/specs/delivery/real-cluster/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "changes/deliver-a-secret-without-exposing-it/specs/operator/apply-command/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "changes/deliver-a-secret-without-exposing-it/specs/planner/diagnostics/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "changes/deliver-a-secret-without-exposing-it/specs/planner/plan-artifact/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "changes/deliver-a-secret-without-exposing-it/specs/realiser/portable-service-image/spec.md" =
      "an unimplemented change: no task of deliver-a-secret-without-exposing-it has been done, so nothing in this package claims to satisfy it yet";
    "changes/name-the-machine-a-run-dials/specs/operator/apply-command/spec.md" =
      "an unimplemented change: no task of name-the-machine-a-run-dials has been done, so nothing in this package claims to satisfy it yet";
    "changes/name-the-machine-a-run-dials/specs/planner/machine-platform/spec.md" =
      "an unimplemented change: no task of name-the-machine-a-run-dials has been done, so nothing in this package claims to satisfy it yet";
    "changes/name-the-machine-a-run-dials/specs/planner/secret-delivery/spec.md" =
      "an unimplemented change: no task of name-the-machine-a-run-dials has been done, so nothing in this package claims to satisfy it yet";
    "changes/bind-a-value-an-entry-did-not-generate/specs/delivery/real-cluster/spec.md" =
      "an unimplemented change: no task of bind-a-value-an-entry-did-not-generate has been done, so nothing in this package claims to satisfy it yet";
    "changes/bind-a-value-an-entry-did-not-generate/specs/realiser/portable-service-image/spec.md" =
      "an unimplemented change: no task of bind-a-value-an-entry-did-not-generate has been done, so nothing in this package claims to satisfy it yet";
    "changes/answer-a-machine-question-as-a-record/specs/operator/deployment-build/spec.md" =
      "an unimplemented change: no task of answer-a-machine-question-as-a-record has been done, so nothing in this package claims to satisfy it yet";
    "changes/answer-a-machine-question-as-a-record/specs/operator/machine-report/spec.md" =
      "an unimplemented change: no task of answer-a-machine-question-as-a-record has been done, so nothing in this package claims to satisfy it yet";
    "changes/show-a-deployment-in-a-browser/specs/operator/deployment-view/spec.md" =
      "an unimplemented change: no task of show-a-deployment-in-a-browser has been done, so nothing in this package claims to satisfy it yet";
    "changes/show-a-deployment-in-a-browser/specs/tooling/consumer-surface/spec.md" =
      "an unimplemented change: no task of show-a-deployment-in-a-browser has been done, so nothing in this package claims to satisfy it yet";
    "changes/show-a-deployment-in-a-browser/specs/tooling/repository-shape/spec.md" =
      "an unimplemented change: no task of show-a-deployment-in-a-browser has been done, so nothing in this package claims to satisfy it yet";
    "changes/author-a-deployment-from-outside/specs/operator/deployment-build/spec.md" =
      "an unimplemented change: no task of author-a-deployment-from-outside has been done, so nothing in this package claims to satisfy it yet";
    "changes/author-a-deployment-from-outside/specs/tooling/consumer-surface/spec.md" =
      "an unimplemented change: no task of author-a-deployment-from-outside has been done, so nothing in this package claims to satisfy it yet";
    "changes/enroll-a-friend-outside-the-harness/specs/delivery/real-cluster/spec.md" =
      "an unimplemented change: no task of enroll-a-friend-outside-the-harness has been done, so nothing in this package claims to satisfy it yet";
    "changes/enroll-a-friend-outside-the-harness/specs/operator/enrollment-command/spec.md" =
      "an unimplemented change: no task of enroll-a-friend-outside-the-harness has been done, so nothing in this package claims to satisfy it yet";
    "changes/enroll-a-friend-outside-the-harness/specs/operator/machine-provisioning/spec.md" =
      "an unimplemented change: no task of enroll-a-friend-outside-the-harness has been done, so nothing in this package claims to satisfy it yet";
    "changes/enroll-a-friend-outside-the-harness/specs/tooling/consumer-surface/spec.md" =
      "an unimplemented change: no task of enroll-a-friend-outside-the-harness has been done, so nothing in this package claims to satisfy it yet";
    "changes/enroll-a-friend-outside-the-harness/specs/tooling/repository-shape/spec.md" =
      "an unimplemented change: no task of enroll-a-friend-outside-the-harness has been done, so nothing in this package claims to satisfy it yet";
  };

  isSpecFile = path: match ".*/spec\\.md" path != null;

  # An archived change is a record of work that landed: the delta it carried is in
  # the current spec beside it, and that copy is what the reading answers for.
  discovered = filter (path: isSpecFile path && !(hasInfix "changes/archive/" path)) (
    filesUnder openspecRoot
  );

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
    path: filter (h: h != null) (map scenarioOf (lines (readFile (openspecRoot + "/${path}"))));

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

  # A counted test file that is neither a suite nor a machine folder. The
  # command's own counterexamples are here for the reason the perf check's tests
  # are: a scenario is answered by the test that asserts it, whatever language
  # the thing under test is run in.
  besideFiles = [
    {
      rel = "perf/check_test.py";
      file = perfSource + "/check_test.py";
    }
    {
      rel = "cli/counterexample_test.py";
      file = repoSource + "/cli/counterexample_test.py";
    }
  ];

  besideNamed = concatLists (
    map (
      entry:
      map (d: {
        inherit (d) name;
        file = entry.rel;
      }) (definedIn entry)
    ) besideFiles
  );

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
    "A file referencing a delivered path is still assembled on the machine" =
      "testARenderRecipeIsAssembledOnTheHost";
    "A field the directive table does not carry" = "testAFieldNoBuilderRenders";
    "An image the machine already holds attached is not attached twice" =
      "test_an_unchanged_deployment_applied_twice";
    "A value whose bytes moved" = "test_a_value_whose_bytes_moved_is_written_and_reported_as_changed";
    "A rotated secret restarts its reader" = "test_a_rotated_secret_restarts_the_entry_that_reads_it";
    "A reader that is not running is not started" =
      "test_a_reader_that_is_not_running_is_not_started_by_the_restart";
    "A machine that lost its values" =
      "test_a_machine_that_lost_its_values_is_reported_and_an_apply_restores_them";
    "A machine holding every value" = "test_a_machine_holding_every_value_is_reported_without_a_line";
    "A value delivered to one of two machines" =
      "test_a_value_delivered_to_one_of_two_machines_is_named_where_it_is_missing";
    "An artifact activated twice" = "test_an_unchanged_entry_is_a_no_op";
    "The table, the suite and the fixture's README agree" = "testEveryExcludedConstructIsRefused";
    "The six remaining rows are still refused" = "testEveryExcludedConstructIsRefused";
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
    strandedIn "excused" "spec.md under openspec/" (
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

  # An excuse of the form this repository writes for an unimplemented change
  # names the change. The excuse expires when that change starts landing, and
  # the ground it stands on is its own tasks file.
  excuseNamesChange =
    reason:
    let
      m = match ".*no task of ([a-z0-9-]+) has been done.*" reason;
    in
    if m == null then null else head m;

  # A marker is read at the start of a line, so a tasks file may name `- [x]` in
  # prose without reading as a change that has started landing.
  changeHasLanded =
    name:
    let
      file = openspecRoot + "/changes/${name}/tasks.md";
      ticked = line: match "[[:space:]]*- [[]x[]].*" line != null;
    in
    pathExists file && filter ticked (lines (readFile file)) != [ ];

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
      unreadable = filter (path: !(pathExists (openspecRoot + "/${path}"))) accountable;
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

  testAnExcuseOutlivesTheStateItDescribes = {
    expr = {
      tree = staleExcuses;
      synthetic = changeHasLanded "answer-whether-a-machine-is-current";
    };
    expected = {
      tree = [ ];
      synthetic = true;
    };
  };
}
