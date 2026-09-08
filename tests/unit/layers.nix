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

  # One row per top-level entry of the repository. A file or directory with no row
  # here fails testATopLevelEntryBelongsToNoStatedClass.
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
    "CLAUDE.md" = "the invariants an author has to keep";
    "openspec" = "the specification records";
    "treefmt.nix" = "the formatter's own configuration";
    "styles" = "the formatter's own configuration";
    ".omp" = "the formatter's own configuration";
    "flake.nix" = "the flake";
    "flake.lock" = "the flake";
    "flake-module.nix" = "the flake";
    "devshells.nix" = "the flake";
    "pytest-env.nix" = "the flake";
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

  hasRootDocument = pathExists (repoRoot + "/README.md");
  rootDocument = if hasRootDocument then readFile (repoRoot + "/README.md") else "";

  tokensIn =
    text:
    map (
      token:
      let
        m = match "(.*[^.])\\.*" token;
      in
      if m == null then token else head m
    ) (filter isString (split "[^a-zA-Z0-9_./-]+" text));

  pathTokens = text: filter (token: match "\\.\\.?/.*" token != null) (tokensIn text);

  firstSegment =
    token:
    let
      m = match "([^/]+)/.*" token;
    in
    if m == null then null else head m;

  # A repository-rooted path counts only when its first segment is a real top-level
  # entry. That is what keeps foreign paths and URLs out of the scan.
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

  # openspec is absent on purpose. A record describes the repository as it was, so a
  # path it names is history rather than a claim about today.
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

  # The scan reads raw file text, comments included, because a stale path reference
  # usually survives in a comment rather than in code.
  repoNamedPaths = namedPathsOf repoRoot scannedFiles ++ rootedPathsOf repoRoot scannedFiles;

  unresolvedReferences = sorted (
    map (p: "${p.rel}: ${toString p.line}: ${p.token}") (
      filter (p: !(pathExists p.resolved)) repoNamedPaths
    )
  );

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

  systemBinaries = [
    "portablectl"
    "systemctl"
    "nix-store"
    "ssh"
  ];

  testFiles = filter (
    rel:
    isTestFile (baseNameOf rel)
    || match "unit/.*\\.nix" rel != null
    || match "nixos/.*\\.nix" rel != null
  ) (filesUnder testsRoot);

  writesAnExecutable = line: hasInfix "#!/bin/sh" line || hasInfix "#!/usr/bin/env" line;

  # A stand-in is an executable a test writes whose line also names a program a
  # realiser calls on a machine. Reading a real program's output writes no such file.
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

  testAUnitTestNeedsNoMachine = {
    expr = sorted (filter (rel: match ".*\\.nix" rel == null) (filesUnder unitRoot));
    expected = [ ];
  };

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
        "conftest.py"
        "delivery.py"
        "guest.nix"
        "runner.py"
        "test_harness.py"
      ];
    };
  };

  testAReaderOpensAnEndToEndDirectory = {
    expr = {
      inherit unresolved outside;
    };
    expected = {
      unresolved = [ ];
      outside = [ ];
    };
  };

  testAnEndToEndTestReadsAFileOfAnotherEndToEndTest = {
    expr = sorted siblingReferences;
    expected = [ ];
  };

  testAFixtureIsNeededByEveryEndToEndTest = {
    expr = duplicated;
    expected = [ ];
  };

  testAnEndToEndTestIsDeleted = {
    expr = dangling;
    expected = [ ];
  };

  testATestWritesAStandInForASystemBinary = {
    expr = standIns;
    expected = [ ];
  };

  testAFileNamesAPathThatIsNotThere = {
    expr = unresolvedReferences;
    expected = [ ];
  };

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

  testATopLevelEntryBelongsToNoStatedClass = {
    expr = unowned;
    expected = [ ];
  };

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
        "nix develop"
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
