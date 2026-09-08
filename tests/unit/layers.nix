# The shape of the test tree itself: that there are two layers and no third,
# that an end-to-end test's fixture is inside that test's own directory, and
# that no test of this package stands a program in for the one a machine runs.
#
# It is also the shape of the repository around them: that a path any of their
# files names resolves to something that is here.
#
# Every assertion here is `readDir` and `readFile` over the tree the suite is
# evaluated from, so a tree that has drifted from the rule fails a build rather
# than being noticed by a reader.
{
  support,
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
    sort
    split
    ;
  inherit (support)
    filesUnder
    hasInfix
    lines
    ;

  repoRoot = repoSource;
  testsRoot = repoRoot + "/tests";
  unitRoot = repoRoot + "/tests/unit";
  e2eRoot = repoRoot + "/tests/e2e";
  docsRoot = repoRoot + "/docs";

  sorted = sort (a: b: a < b);

  entriesOf = dir: readDir dir;
  directoriesIn =
    dir: filter (name: (entriesOf dir).${name} == "directory") (attrNames (entriesOf dir));
  filesIn = dir: filter (name: (entriesOf dir).${name} != "directory") (attrNames (entriesOf dir));

  isTestFile = name: match "test_[a-z0-9_]*\\.py" name != null;

  e2eNames = directoriesIn e2eRoot;

  topLevelNames = attrNames (entriesOf repoRoot);

  # ------------------------------------------------- what the tree may hold --

  # One row per top-level entry and the class it belongs to. An entry with no
  # row fails below, so a directory arriving in this repository is a decision
  # taken at review time rather than an addition nobody remembers.
  classOf = {
    "lib" = "the library";
    "image" = "a realiser";
    "flakelet" = "a realiser";
    "tests" = "the tests";
    "pytest.ini" = "the tests";
    "fixtures" = "the fixtures the tests read";
    "perf" = "the performance harness";
    "docs" = "the documentation of the library";
    "README.md" = "the documentation of the library";
    "openspec" = "the specification records";
    "treefmt.nix" = "the formatter's own configuration";
    "styles" = "the formatter's own configuration";
    ".omp" = "the formatter's own configuration";
    "flake.nix" = "the flake";
    "flake.lock" = "the flake";
    "flake-module.nix" = "the flake";
    "ruff.toml" = "the formatter's own configuration";
    ".envrc" = "the checkout's own configuration";
    ".gitignore" = "the checkout's own configuration";
    "LICENSE.md" = "the licence";
  };

  statedClasses = sorted (
    attrNames (
      listToAttrs (
        map (name: {
          name = classOf.${name};
          value = null;
        }) (attrNames classOf)
      )
    )
  );

  unowned = map (name: "${name} belongs to none of ${concatStringsSep ", " statedClasses}") (
    sorted (filter (name: !(classOf ? ${name})) topLevelNames)
  );

  # Read defensively, so that a repository with no root document fails the test
  # below naming what the document has to say rather than aborting the suite on
  # a missing path.
  hasRootDocument = pathExists (repoRoot + "/README.md");
  rootDocument = if hasRootDocument then readFile (repoRoot + "/README.md") else "";

  # --------------------------------------------------- what a file may name --

  # A token as written, with a sentence's full stop taken off the end. The
  # separator class is everything a path cannot hold, which is also what takes a
  # trailing citation off a token: `lib/resolve.nix:377` splits at the colon, so
  # what is left is a reference to that file.
  tokensIn =
    text:
    map (
      token:
      let
        m = match "(.*[^.])\\.*" token;
      in
      if m == null then token else head m
    ) (filter isString (split "[^a-zA-Z0-9_./-]+" text));

  # Every `./…` or `../…` path literal a file names, as written.
  pathTokens = text: filter (token: match "\\.\\.?/.*" token != null) (tokensIn text);

  firstSegment =
    token:
    let
      m = match "([^/]+)/.*" token;
    in
    if m == null then null else head m;

  # Every path a file names from the repository root, recognised by its first
  # segment being a top-level entry that exists. That test is the whole of what
  # keeps the scan off `/run/vars/hostKey/x` (a path on a machine),
  # `ssh://borg@vault.example:22/srv` (a URL), `manager.rs:1349-1392` (a
  # citation into another project's source) and `pkgs/planner/lib` (a directory
  # of the repository this code came out of).
  repoTokens = text: filter (token: elem (firstSegment token) topLevelNames) (tokensIn text);

  numberedLines =
    text:
    let
      ls = lines text;
    in
    genList (i: {
      line = i + 1;
      text = elemAt ls i;
    }) (length ls);

  dirnameOf =
    rel:
    let
      m = match "(.*)/[^/]*" rel;
    in
    if m == null then "" else head m;

  # Each file of `files` under `root`, with the paths it names on each line
  # resolved: `tokensOf` picks the tokens out of a line and `rootOf` says what
  # the file writing them points from.
  namedPathsIn =
    {
      root,
      files,
      tokensOf,
      rootOf,
    }:
    concatLists (
      map (
        rel:
        let
          from = rootOf rel;
        in
        concatLists (
          map (
            numbered:
            map (token: {
              inherit rel token;
              inherit (numbered) line;
              resolved = from + "/${token}";
            }) (tokensOf numbered.text)
          ) (numberedLines (readFile (root + "/${rel}")))
        )
      ) files
    );

  namedPathsOf =
    root: files:
    namedPathsIn {
      inherit root files;
      tokensOf = pathTokens;
      rootOf =
        rel:
        let
          base = dirnameOf rel;
        in
        if base == "" then root else root + "/${base}";
    };

  rootedPathsOf =
    root: files:
    namedPathsIn {
      inherit root files;
      tokensOf = repoTokens;
      rootOf = _: repoRoot;
    };

  # ------------------------------------------------------- what a fixture is --

  # Each `.nix` file of an end-to-end folder, with the paths it names resolved
  # against its own directory.
  e2ePathsOf =
    folder:
    let
      root = e2eRoot + "/${folder}";
    in
    map (p: p // { inherit folder; }) (
      namedPathsOf root (filter (rel: match ".*\\.nix" rel != null) (filesUnder root))
    );

  namedPaths = concatLists (map e2ePathsOf e2eNames);

  unresolved = sorted (
    map (p: "tests/e2e/${p.folder}/${p.rel}: ${p.token}") (
      filter (p: !(pathExists p.resolved)) namedPaths
    )
  );

  # A path that leaves its own folder. `..` is only legitimate while it stays
  # inside the folder, and `toString` of a resolved path makes that decidable
  # without re-implementing normalisation.
  escapes =
    p:
    let
      inside = toString (e2eRoot + "/${p.folder}");
      target = toString p.resolved;
    in
    !(hasInfix "${inside}/" "${target}/");

  outside = sorted (
    map (p: "tests/e2e/${p.folder}/${p.rel}: ${p.token} leaves tests/e2e/${p.folder}") (
      filter escapes namedPaths
    )
  );

  # A reference from one folder into a sibling, named in text rather than as a
  # path literal: a Python import, a docstring, a string holding the name.
  siblingReferences = concatLists (
    map (
      folder:
      let
        root = e2eRoot + "/${folder}";
        text = concatStringsSep "\n" (map (rel: readFile (root + "/${rel}")) (filesUnder root));
      in
      map (other: "tests/e2e/${folder} names tests/e2e/${other}") (
        filter (other: other != folder && hasInfix other text) e2eNames
      )
    ) e2eNames
  );

  # Two folders holding the same file: a fixture both need belongs at the
  # layer's root, where one statement of what it guarantees serves both.
  fileNamesOf = folder: map (rel: { inherit folder rel; }) (filesUnder (e2eRoot + "/${folder}"));
  allFolderFiles = concatLists (map fileNamesOf e2eNames);

  duplicated = sorted (
    map (entry: "${entry.rel} is in tests/e2e/${entry.folder} and a sibling") (
      filter (
        entry:
        builtins.any (
          other:
          other.folder != entry.folder
          && other.rel == entry.rel
          &&
            readFile (e2eRoot + "/${other.folder}/${other.rel}")
            == readFile (e2eRoot + "/${entry.folder}/${entry.rel}")
        ) allFolderFiles
      ) allFolderFiles
    )
  );

  # ------------------------------------------------- what the repository is --

  # The library, the two realisers, the perf harness, the tests, the fixtures,
  # the documentation and the flake's own Nix files. `openspec/` is not here:
  # see `testARecordIsReadAsHistory`.
  scannedDirectories = [
    "lib"
    "image"
    "flakelet"
    "perf"
    "tests"
    "fixtures"
    "docs"
  ];

  scannedFiles =
    concatLists (
      map (dir: map (rel: "${dir}/${rel}") (filesUnder (repoRoot + "/${dir}"))) scannedDirectories
    )
    ++ filter (name: match ".*\\.nix" name != null) (filesIn repoRoot);

  repoNamedPaths = namedPathsOf repoRoot scannedFiles ++ rootedPathsOf repoRoot scannedFiles;

  unresolvedReferences = sorted (
    map (p: "${p.rel}: ${toString p.line}: ${p.token}") (
      filter (p: !(pathExists p.resolved)) repoNamedPaths
    )
  );

  # ------------------------------------------------------- a deleted folder --

  # A folder that has been removed leaves references behind in prose and in the
  # suites. The flake module cannot: a path literal that does not exist is an
  # evaluation error, so only text can go stale.
  proseFiles =
    map (rel: {
      where = "docs/${rel}";
      text = readFile (docsRoot + "/${rel}");
    }) (filter (rel: match ".*\\.md" rel != null) (filesUnder docsRoot))
    ++ map (rel: {
      where = "tests/${rel}";
      text = readFile (testsRoot + "/${rel}");
    }) (filter (rel: match "(unit|e2e)/.*\\.(nix|py)" rel != null) (filesUnder testsRoot));

  namedFolderOf =
    line:
    let
      m = match ".*tests/e2e/([a-z0-9-]+)/.*" line;
    in
    if m == null then null else head m;

  danglingIn =
    entry:
    map (name: "${entry.where}: tests/e2e/${name} does not exist") (
      filter (name: name != null && !(elem name e2eNames)) (map namedFolderOf (lines entry.text))
    );

  dangling = sorted (concatLists (map danglingIn proseFiles));

  # ------------------------------------------------------------ stand-ins ----

  # A program a realiser's output invokes on a machine. A test that writes an
  # executable of one of these names is asserting against its own script.
  systemBinaries = [
    "portablectl"
    "systemctl"
    "nix-store"
    "ssh"
  ];

  # Every test file of this package: the machine layer's, the evaluating
  # layer's, and any left in the tree from before there were two.
  testFiles = filter (
    rel:
    isTestFile (baseNameOf rel)
    || match "unit/.*\\.nix" rel != null
    || match "nixos/.*\\.nix" rel != null
  ) (filesUnder testsRoot);

  # An executable a test creates is a shebang the test writes, on the line that
  # names what it is standing in for. Reading the real program's output, or
  # running it over ssh on a machine, writes no shebang; only a double does.
  writesAnExecutable = line: hasInfix "#!/bin/sh" line || hasInfix "#!/usr/bin/env" line;

  standInsIn =
    rel:
    concatLists (
      map (
        line:
        if !(writesAnExecutable line) then
          [ ]
        else
          map (binary: "tests/${rel} stands in for ${binary}") (
            filter (binary: hasInfix binary line) systemBinaries
          )
      ) (lines (readFile (testsRoot + "/${rel}")))
    );

  standIns = sorted (concatLists (map standInsIn testFiles));
in
{
  # Two layers and nothing else. The entry point and the reporter sit beside
  # them because neither is a test: one imports the suites, the other counts
  # their failures.
  testTheTestTreeIsRead = {
    expr = {
      layers = sorted (directoriesIn testsRoot);
      beside = sorted (filesIn testsRoot);
    };
    expected = {
      layers = [
        "e2e"
        "unit"
      ];
      beside = [
        "default.nix"
        "report.nix"
      ];
    };
  };

  # The evaluating layer is Nix and only Nix. A file of any other kind in it is
  # a test that needs something evaluation cannot provide.
  testAUnitTestNeedsNoMachine = {
    expr = sorted (filter (rel: match ".*\\.nix" rel == null) (filesUnder unitRoot));
    expected = [ ];
  };

  # One directory per end-to-end test, holding exactly one test file, and a
  # root holding only what every one of them shares.
  testAnEndToEndTestNeedsAMachine = {
    expr = {
      perDirectory = sorted (
        map (
          name:
          "tests/e2e/${name} holds ${
            toString (length (filter isTestFile (filesIn (e2eRoot + "/${name}"))))
          } test files"
        ) (filter (name: length (filter isTestFile (filesIn (e2eRoot + "/${name}"))) != 1) e2eNames)
      );
      harness = sorted (filesIn e2eRoot);
    };
    expected = {
      perDirectory = [ ];
      harness = [
        "delivery.py"
        "guest.nix"
        "runner.py"
        "test_harness.py"
      ];
    };
  };

  # Everything an end-to-end folder's fixture names is in that folder.
  testAReaderOpensAnEndToEndDirectory = {
    expr = {
      inherit unresolved outside;
    };
    expected = {
      unresolved = [ ];
      outside = [ ];
    };
  };

  # No folder reaches into a sibling, by path or by name.
  testAnEndToEndTestReadsAFileOfAnotherEndToEndTest = {
    expr = sorted siblingReferences;
    expected = [ ];
  };

  # A fixture two folders need lives at the root, so it is stated once.
  testAFixtureIsNeededByEveryEndToEndTest = {
    expr = duplicated;
    expected = [ ];
  };

  # Nothing names a folder that is not there.
  testAnEndToEndTestIsDeleted = {
    expr = dangling;
    expected = [ ];
  };

  # No test of this package writes an executable standing in for a program a
  # machine would run.
  testATestWritesAStandInForASystemBinary = {
    expr = standIns;
    expected = [ ];
  };

  # A path this repository names is a path this repository has. Comments count:
  # every reference the transplant out of the corpus left dangling is in one,
  # and a check reading only what an evaluator reads would have passed on them.
  testAFileNamesAPathThatIsNotThere = {
    expr = unresolvedReferences;
    expected = [ ];
  };

  # `openspec/` is outside that rule, and the exemption is stated here rather
  # than left for a reader to notice: a specification, a proposal or a task
  # record describes the repository as it was when it was written, so a path it
  # names is evidence of a decision rather than a claim about this tree.
  testARecordIsReadAsHistory = {
    expr = {
      scanned = filter (dir: dir == "openspec") scannedDirectories;
      files = filter (rel: match "openspec/.*" rel != null) scannedFiles;
      records = pathExists (repoRoot + "/openspec");
    };
    expected = {
      scanned = [ ];
      files = [ ];
      records = true;
    };
  };

  # Every top-level entry is one of the classes this repository states. The
  # failure names the entry and the classes, so the answer is to classify it
  # here or to take it out, never to leave it unowned.
  testATopLevelEntryBelongsToNoStatedClass = {
    expr = unowned;
    expected = [ ];
  };

  # The first file a reader opens says what the repository is, how the tree is
  # laid out and what checks it, and hands the library's own reading order on
  # to `docs/README.md` rather than answering it a second time.
  testTheRootDoesNotSayWhatTheRepositoryIs = {
    expr = {
      present = hasRootDocument;
      unsaid = filter (needle: !(hasInfix needle rootDocument)) [
        "docs/"
        "docs/README.md"
        "fixtures/"
        "flakelet/"
        "image/"
        "lib/"
        "nix build .#checks.x86_64-linux.planner-perf"
        "nix build .#checks.x86_64-linux.planner-tests"
        "nix build .#checks.x86_64-linux.treefmt"
        "nix develop .#planner"
        "nix develop .#planner-cluster"
        "openspec/"
        "perf/"
        "tests/e2e/"
        "tests/unit/"
      ];
    };
    expected = {
      present = true;
      unsaid = [ ];
    };
  };
}
