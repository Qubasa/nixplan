{
  support,
  repoSource,
}:
let
  inherit (builtins)
    attrNames
    bitAnd
    concatLists
    concatStringsSep
    elem
    elemAt
    filter
    foldl'
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
    "operator" = "the deployment build";
    "cli" = "the operator's command";
    "secrets" = "a realiser";
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
    "lemmalog.nix" = "the flake";
    "ruff.toml" = "the formatter's own configuration";
    ".envrc" = "the checkout's own configuration";
    ".mcp.json" = "the checkout's own configuration";
    ".gitignore" = "the checkout's own configuration";
    "slopo.conf.yaml" = "the checkout's own configuration";
    "slopo.ignore.txt" = "the checkout's own configuration";
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

  # Planning a deployment, realising an entry and collecting the result are the
  # repository's own code, so a folder that names one of them is a folder that has
  # taken the machinery back.
  builderNeedles = [
    "mkPlan"
    "linkFarm"
    "imageBuilder"
    "flakeletBuilder"
  ];

  builders = sorted (
    concatLists (
      map (
        entry:
        let
          text = readFile (e2eRoot + "/${entry.folder}/${entry.rel}");
        in
        map (needle: "tests/e2e/${entry.folder}/${entry.rel} names ${needle}") (
          filter (needle: hasInfix needle text) builderNeedles
        )
      ) allFolderFiles
    )
  );

  flakeModule = readFile (repoRoot + "/flake-module.nix");

  namedInTheFlake = sorted (
    map (name: "flake-module.nix names tests/e2e/${name}") (
      filter (name: hasInfix name flakeModule) e2eNames
    )
  );

  undiscoverable = sorted (
    map (name: "tests/e2e/${name} holds no deployment/default.nix") (
      filter (name: !(pathExists (e2eRoot + "/${name}/deployment/default.nix"))) e2eNames
    )
  );

  # openspec is absent on purpose. A record describes the repository as it was, so a
  # path it names is history rather than a claim about today.
  scannedDirectories = [
    "lib"
    "image"
    "flakelet"
    "operator"
    "cli"
    "secrets"
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

  # A document and the committed file whose text it shows, byte for byte. A document
  # under `docs/` cannot show a file that imports a sibling by a relative path: a
  # path this tree writes has to resolve from the file that writes it, which
  # `testAFileNamesAPathThatIsNotThere` holds every document under a scanned
  # directory to. The root document is the one the scan does not read, so it is
  # where the consumer's flake is shown.
  exampleFolder = "tests/e2e/newcomer/template/deployment";
  shownTexts = [
    {
      document = "docs/README.md";
      file = "tests/e2e/newcomer/template/deployment/machines.nix";
    }
    {
      document = "docs/README.md";
      file = "tests/e2e/newcomer/template/deployment/instances.nix";
    }
    {
      document = "docs/README.md";
      file = "tests/e2e/newcomer/template/deployment/modules/hello/greet.nix";
    }
    {
      document = "README.md";
      file = "tests/e2e/newcomer/template/flake.nix";
    }
  ];

  fencedBlocks =
    text:
    (foldl'
      (
        state: line:
        if !state.inside then
          state // { inside = line == "```nix"; }
        else if line == "```" then
          {
            inside = false;
            current = [ ];
            blocks = state.blocks ++ [ (concatStringsSep "\n" state.current + "\n") ];
          }
        else
          state // { current = state.current ++ [ line ]; }
      )
      {
        inside = false;
        current = [ ];
        blocks = [ ];
      }
      (lines text)
    ).blocks;

  unshown = sorted (
    map (shown: "${shown.document} shows no block equal to ${shown.file}") (
      filter (
        shown:
        !(elem (readFile (repoRoot + "/${shown.file}")) (
          fencedBlocks (readFile (repoRoot + "/${shown.document}"))
        ))
      ) shownTexts
    )
  );

  # The command the root advertises whose run resolves something this repository
  # does not publish, and the dependency's own name read off the runner that
  # resolves it. Written here, a rename there would leave this passing.
  advertisedCommand = "nix run .#planner-e2e";

  runnerReference =
    let
      declaration = filter (line: match ".*ROOKERY_FLAKE = \".*" line != null) (
        lines (readFile (e2eRoot + "/runner.py"))
      );
      quoted = match ".*\"(.*)\".*" (head declaration);
      segments = filter isString (split "/" (head quoted));
    in
    if declaration == [ ] then null else elemAt segments (length segments - 1);

  paragraphsOf = text: filter isString (split "\n\n+" text);

  # The advertisement is one paragraph: the dependency has to be named where the
  # command is, not in a document further down the reading order. The phrase is
  # pinned because the claim is a claim in words, and this is the smallest part of
  # it a check can hold.
  advertisement = filter (para: hasInfix advertisedCommand para) (paragraphsOf rootDocument);

  unnamed =
    if advertisement == [ ] then
      [ "README.md advertises no ${advertisedCommand}" ]
    else
      sorted (
        concatLists (
          map (
            para:
            map (needle: "README.md advertises ${advertisedCommand} without saying ${needle}") (
              filter (needle: !(hasInfix needle para)) [
                runnerReference
                "cannot run"
              ]
            )
          ) advertisement
        )
      );

  guestLines = lines (readFile (e2eRoot + "/guest.nix"));

  nixFilesOf =
    folder: filter (rel: match ".*\\.nix" rel != null) (filesUnder (e2eRoot + "/${folder}"));
  testFilesOf =
    folder: filter (rel: isTestFile (baseNameOf rel)) (filesUnder (e2eRoot + "/${folder}"));
  textOf = folder: rel: readFile (e2eRoot + "/${folder}/${rel}");

  # The account a folder's unit runs as. Nothing in a plan creates one, so each
  # is a fact its folder needs from the shared guest image - except the two
  # every Linux system already has, which no image declares and none may.
  universalAccounts = [
    "root"
    "nobody"
  ];

  accountOf =
    line:
    let
      m = match ".*user = \"([a-z_][0-9a-z_-]*)\";.*" line;
    in
    if m == null then null else head m;

  folderAccounts = concatLists (
    map (
      folder:
      concatLists (
        map (
          rel:
          map (account: { inherit folder account; }) (
            filter (a: a != null && !(elem a universalAccounts)) (map accountOf (lines (textOf folder rel)))
          )
        ) (nixFilesOf folder)
      )
    ) e2eNames
  );

  declaresAccount =
    account: builtins.any (line: match " *users\\.users\\.${account} = .*" line != null) guestLines;

  # What an account's assertion owes a reader: the folder that needs it, that no
  # plan can supply it, and what adding it costs every other folder's next run.
  accountedFor =
    entry:
    builtins.any (
      line:
      hasInfix entry.account line
      && hasInfix "tests/e2e/${entry.folder}/" line
      && hasInfix "no plan creates an account" line
      && hasInfix "snapshot cut" line
    ) guestLines;

  unaccountedAccounts = sorted (
    map (
      entry:
      "tests/e2e/${entry.folder} runs a unit as ${entry.account}, which the guest image ${
        if declaresAccount entry.account then
          "declares with no assertion naming the folder"
        else
          "does not declare"
      }"
    ) (filter (entry: !(declaresAccount entry.account) || !(accountedFor entry)) folderAccounts)
  );

  declaredAccountOf =
    line:
    let
      m = match " *users\\.users\\.([a-z_][0-9a-z_-]*)[. ].*" line;
    in
    if m == null then null else head m;

  uniqueNames =
    names:
    sorted (
      attrNames (
        listToAttrs (
          map (name: {
            inherit name;
            value = null;
          }) names
        )
      )
    );

  # The universal accounts belong to no folder: root is what rookery reaches
  # every machine as, and nobody is what a unit needing no identity of its own
  # runs as.
  imageAccounts = filter (name: !(elem name universalAccounts)) (
    uniqueNames (filter (name: name != null) (map declaredAccountOf guestLines))
  );

  neededAccounts = uniqueNames (map (entry: entry.account) folderAccounts);

  spareAccounts = sorted (
    map (account: "the guest image declares ${account}, which no folder's unit runs as") (
      filter (account: !(elem account neededAccounts)) imageAccounts
    )
  );

  homeOf =
    line:
    let
      m = match " *home = \"([^\"]*)\";" line;
    in
    if m == null then null else head m;

  # Nothing in a plan creates an account, so the home a service keeps its state
  # under is the shared guest image's own declaration. A module writing inside
  # one is a service that writes state on the machine, and the space that needs
  # is its own folder's stage's rather than the image's, which every other
  # folder's cut is keyed on. The settings knob that used to say so is gone:
  # every host path is derived where the entry's identity is.
  declaredHomes = filter (home: home != null) (map homeOf guestLines);

  writesUnderAHome =
    folder:
    builtins.any (rel: builtins.any (home: hasInfix "${home}/" (textOf folder rel)) declaredHomes) (
      nixFilesOf folder
    );

  # The other way a folder says it writes on the machine. A state directory is
  # created by the service manager under the root its kind implies, so the
  # declaration names no home and the bytes are still a stage's to hold.
  declaresAStateDirectory =
    folder: builtins.any (rel: hasInfix "stateDirectory" (textOf folder rel)) (nixFilesOf folder);

  statefulFolders = sorted (
    filter (folder: writesUnderAHome folder || declaresAStateDirectory folder) e2eNames
  );

  statefulByADeletedKnob = sorted (
    filter (
      folder: builtins.any (rel: hasInfix "dataDir" (textOf folder rel)) (nixFilesOf folder)
    ) e2eNames
  );

  declaresSpace =
    folder: builtins.any (rel: hasInfix "disk_gib" (textOf folder rel)) (testFilesOf folder);

  # The space and the stage are one declaration: a figure written anywhere else
  # would key no cut.
  declaresSpaceBesideItsStage =
    folder:
    builtins.any (
      rel:
      let
        text = textOf folder rel;
      in
      hasInfix "cluster_stage" text && hasInfix "disk_gib" text
    ) (testFilesOf folder);

  spaceAwayFromTheStage = sorted (
    map (folder: "tests/e2e/${folder} declares its space away from its own stage") (
      filter (folder: !(declaresSpaceBesideItsStage folder)) statefulFolders
    )
  );

  # The folder that instantiates one module twice, once shared and once owned.
  instancingFolder = "shared-postgres";

  databaseModules = sorted (
    filter (rel: match ".*databases\\.nix" rel != null) (nixFilesOf instancingFolder)
  );

  undeclaredSpace = sorted (
    map (folder: "tests/e2e/${folder} writes state on the machine and its stage declares no space") (
      filter (folder: !(declaresSpace folder)) statefulFolders
    )
  );

  deliveryText = readFile (e2eRoot + "/delivery.py");

  # The roots a machine owns. A literal whose first segment is one of them is a
  # host path; anything else beginning with a slash is a URL path, a path relative
  # to the folder or a name of something else.
  hostRoots = [
    "etc"
    "home"
    "nix"
    "opt"
    "root"
    "run"
    "srv"
    "tmp"
    "usr"
    "var"
  ];

  # A line split on the quote. The fragments between quotes are the string
  # literals, and a quoted attribute name is one of them, which is how
  # `configData."/etc/x"` is written and the one shape a scan over code alone
  # would miss.
  fragmentsOf = line: filter isString (split "\"" line);

  hostRootOf =
    fragment:
    let
      m = match "/([^/]+)(/.*)?" fragment;
    in
    if m == null then null else head m;

  # Written out in full means nothing was interpolated into it. A path built from
  # the identity of the entry that uses it carries the interpolation and passes.
  hostPathsOfLine =
    line:
    filter (fragment: elem (hostRootOf fragment) hostRoots && !(hasInfix "\${" fragment)) (
      fragmentsOf line
    );

  hostPathSitesOf =
    folder: rels:
    concatLists (
      map (
        rel:
        concatLists (
          map (
            numbered:
            map (path: {
              inherit rel path;
              inherit (numbered) line;
            }) (hostPathsOfLine numbered.text)
          ) (numberedLines (textOf folder rel))
        )
      ) rels
    );

  # The template a consumer copies is read with the folders' own: it is the first
  # deployment a reader outside this repository writes from.
  deploymentFilesOf =
    folder:
    filter (rel: match "(template/)?deployment/.*\\.nix" rel != null) (
      filesUnder (e2eRoot + "/${folder}")
    );

  statedHostPaths = sorted (
    concatLists (
      map (
        folder:
        map (site: "tests/e2e/${folder}/${site.rel}:${toString site.line}: ${site.path}") (
          hostPathSitesOf folder (deploymentFilesOf folder)
        )
      ) e2eNames
    )
  );

  # A path both halves of a folder carry is the test agreeing with the deployment
  # about a convention rather than reading what the deployment produced. A path
  # only the test names is its own claim and is outside this.
  restatementsBetween =
    folder: declared: asserted:
    concatLists (
      map (
        site:
        map (other: "tests/e2e/${folder}: ${site.path} is in ${other.rel} and in ${site.rel}") (
          filter (other: other.path == site.path) declared
        )
      ) asserted
    );

  restatementsIn =
    folder:
    restatementsBetween folder (hostPathSitesOf folder (deploymentFilesOf folder)) (
      hostPathSitesOf folder (testFilesOf folder)
    );

  restatedHostPaths = uniqueNames (concatLists (map restatementsIn e2eNames));

  ruleSentences = [
    "A deployment declares intent and never plumbing"
    "derived by the module that needs it"
    "no deployment declaration carries a host path"
    "reads it off the plan"
  ];

  # A sentence wraps, so the document is read with its line breaks flattened: the
  # rule is a claim in words rather than in a line.
  flattened = text: concatStringsSep " " (filter isString (split "[[:space:]]+" text));

  ruleUnstated = map (needle: "README.md does not say ${needle}") (
    filter (needle: !(hasInfix needle (flattened rootDocument))) ruleSentences
  );

  # The three homes a counterexample has, by what its own failure does: a suite
  # that reports every assertion, a probe evaluated in a process of its own, and
  # the tests of the program that is run rather than evaluated.
  counterexampleHomes = [
    "cli/counterexample_test.py"
    "tests/counterexamples/probes.nix"
    "tests/unit/counterexamples.nix"
  ];

  # What the repository states about itself: the index, the root document, the
  # prose under `docs/`, and the source the load-bearing comments live in. Each
  # text is flattened with its comment markers removed, because a sentence a test
  # quotes wraps in the file that states it and wraps differently in the file that
  # quotes it.
  statedIn = [
    "lib"
    "cli"
    "image"
    "flakelet"
    "secrets"
    "operator"
  ];

  recordFiles = [
    (repoRoot + "/CLAUDE.md")
    (repoRoot + "/README.md")
  ]
  ++ map (rel: docsRoot + "/${rel}") (filter (rel: match ".*\\.md" rel != null) (filesUnder docsRoot))
  ++ concatLists (
    map (
      dir:
      map (rel: repoRoot + "/${dir}/${rel}") (
        filter (rel: match ".*\\.(nix|py)" rel != null) (filesUnder (repoRoot + "/${dir}"))
      )
    ) statedIn
  );

  statedTexts = map (file: flattened (replaceStrings [ "#" ] [ " " ] (readFile file))) recordFiles;

  # `replaceStrings` scans the text once, where `hasInfix` walks every offset of
  # it: the corpus here is every record this repository keeps.
  stated = needle: builtins.any (text: replaceStrings [ needle ] [ "" ] text != text) statedTexts;

  commentOf =
    line:
    let
      m = match "[[:space:]]*#(.*)" line;
    in
    if m == null then null else head m;

  # One block per run of comment lines, which is the unit a comment names a claim
  # in: above a nix-unit test or a probe, inside the body of a pytest test.
  commentBlocks =
    text:
    let
      walked =
        foldl'
          (
            acc: line:
            let
              comment = commentOf line;
            in
            if comment != null then
              acc // { current = acc.current ++ [ comment ]; }
            else if acc.current == [ ] then
              acc
            else
              {
                blocks = acc.blocks ++ [ (concatStringsSep " " acc.current) ];
                current = [ ];
              }
          )
          {
            blocks = [ ];
            current = [ ];
          }
          (lines text);
    in
    walked.blocks ++ (if walked.current == [ ] then [ ] else [ (concatStringsSep " " walked.current) ]);

  quotedIn =
    block:
    let
      pieces = filter isString (split "\"" block);
    in
    map (i: elemAt pieces i) (filter (i: bitAnd i 1 == 1) (genList (i: i) (length pieces)));

  trimmed =
    text:
    let
      m = match "[[:space:].,;:]*(.*[^[:space:].,;:])[[:space:].,;:]*" (flattened text);
    in
    if m == null then "" else head m;

  # The sentence a block pins is its first quoted fragment, and an elision inside
  # it is a join of two fragments the record states apart. A later quote of the
  # same block is a word of a rendered directive or a spelling, and a quote
  # carrying a `"` of its own shifts every pairing after it.
  pinnedIn =
    block:
    let
      quotes = quotedIn block;
    in
    if quotes == [ ] then [ ] else map trimmed (filter isString (split "\\.\\.\\." (head quotes)));

  # A fragment shorter than this is a token rather than a sentence: an identifier,
  # a field name, a severity.
  sentenceLength = 24;

  pinsOf =
    rel:
    filter (frag: stringLength frag >= sentenceLength) (
      concatLists (map pinnedIn (commentBlocks (readFile (repoRoot + "/${rel}"))))
    );

  withdrawnClaims = sorted (
    concatLists (
      map (
        rel: map (frag: "${rel}: ${frag}") (filter (frag: !(stated frag)) (pinsOf rel))
      ) counterexampleHomes
    )
  );

  quotingHomes = sorted (filter (rel: pinsOf rel != [ ]) counterexampleHomes);

  probesText = readFile (testsRoot + "/counterexamples/probes.nix");

  # The attributes of the probe file, which are the lines below its own `in`: the
  # bindings above it are the deployment the probes are written against.
  probeNames = sorted (
    filter (name: name != null) (
      map
        (
          line:
          let
            m = match "  ([a-zA-Z][a-zA-Z0-9]*) = .*" line;
          in
          if m == null then null else head m
        )
        (foldl'
          (
            acc: line:
            if acc.reached then acc // { body = acc.body ++ [ line ]; } else acc // { reached = line == "in"; }
          )
          {
            reached = false;
            body = [ ];
          }
          (lines probesText)
        ).body
    )
  );

  # What the check that evaluates the probes has to say, so that adding an
  # attribute is adding the attribute: the names come off the file, each is a
  # process of its own, and each answers in a line of its own.
  probeCheckSentences = [
    "builtins.attrNames probes"
    "for name in"
    "--apply \"p: p.$name\""
    "printf 'ok"
    "printf 'raises"
  ];

  probeCheckUnsaid = map (needle: "flake-module.nix does not say ${needle}") (
    filter (needle: !(hasInfix needle flakeModule)) probeCheckSentences
  );

  probesListedByHand = sorted (filter (name: hasInfix name flakeModule) probeNames);

  commandTestFile = "cli/counterexample_test.py";

  definitionOf =
    line:
    let
      m = match "def (test_[a-z0-9_]*)\\(.*" line;
    in
    if m == null then null else head m;

  definedIn =
    rel: filter (name: name != null) (map definitionOf (lines (readFile (repoRoot + "/${rel}"))));

  commandTestNames = sorted (definedIn commandTestFile);

  coverageText = readFile (unitRoot + "/coverage.nix");

  # Every other counted pytest file, so that a name answering for a scenario
  # answers from one kind: the cross-walk fails a name two kinds carry, and the
  # command's tests are counted like any other.
  otherPytestFiles = [
    "perf/check_test.py"
  ]
  ++ map (rel: "tests/e2e/${rel}") (filter (rel: isTestFile (baseNameOf rel)) (filesUnder e2eRoot));

  namesInTwoKinds = sorted (
    concatLists (
      map (
        rel:
        map (name: "${name} is in ${rel} and in ${commandTestFile}") (
          filter (name: elem name commandTestNames) (definedIn rel)
        )
      ) otherPytestFiles
    )
  );
in
{
  # Three kinds of test and two files beside them. `counterexamples` is the third
  # kind because a nix-unit `expr` cannot hold an uncatchable raise: it takes the
  # run that would report it, so those probes are evaluated one process each by
  # `checks.planner-counterexamples-eval` rather than by the suite.
  testTheTestTreeIsRead = {
    expr = {
      layers = sorted (directoriesIn testsRoot);
      beside = sorted (filesIn testsRoot);
    };
    expected = {
      layers = [
        "counterexamples"
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
        "generation.py"
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

  testAnEndToEndFolderHoldsABuilderOfItsOwn = {
    expr = builders;
    expected = [ ];
  };

  testAnEndToEndFolderIsAddedWithoutEditingTheFlake = {
    expr = {
      named = namedInTheFlake;
      inherit undiscoverable;
    };
    expected = {
      named = [ ];
      undiscoverable = [ ];
    };
  };

  testATestWritesAStandInForASystemBinary = {
    expr = standIns;
    expected = [ ];
  };

  testAFileNamesAPathThatIsNotThere = {
    expr = unresolvedReferences;
    expected = [ ];
  };

  testTheExampleADocumentShowsIsTheExampleAFolderHolds = {
    expr = {
      inherit unshown;
      held = sorted (filesUnder (repoRoot + "/${exampleFolder}"));
    };
    expected = {
      unshown = [ ];
      held = [
        "default.nix"
        "instances.nix"
        "machines.nix"
        "modules/hello/default.nix"
        "modules/hello/greet.nix"
      ];
    };
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

  testACommandTheRootAdvertisesNeedsSomethingThisRepositoryCannotProvide = {
    expr = {
      inherit unnamed;
      dependency = runnerReference;
    };
    expected = {
      unnamed = [ ];
      dependency = "rookery";
    };
  };

  testTheImageDeclaresTheAccountAFoldersServiceRunsAs = {
    expr = {
      unaccounted = unaccountedAccounts;
      needed = neededAccounts;
    };
    expected = {
      unaccounted = [ ];
      needed = [ "postgres" ];
    };
  };

  testAnImageFactNoFolderNeedsIsNotAdded = {
    expr = {
      spare = spareAccounts;
      unknownFolders = dangling;
    };
    expected = {
      spare = [ ];
      unknownFolders = [ ];
    };
  };

  testAStatefulFolderDeclaresItsOwnSpace = {
    expr = {
      undeclared = undeclaredSpace;
      stateful = statefulFolders;
      perFolder = hasInfix "disk_gib: int = 0" deliveryText;
      forwarded = hasInfix "disk_size_gib=disk_gib" deliveryText;
    };
    expected = {
      undeclared = [ ];
      stateful = [
        "friend-enrollment"
        "shared-postgres"
      ];
      perFolder = true;
      forwarded = true;
    };
  };

  testAFolderWritingStateIsRecognisedByWhatItDeclares = {
    expr = {
      recognised = statefulFolders;
      byADeletedKnob = statefulByADeletedKnob;
      covered = map declaresSpace statefulFolders;
    };
    expected = {
      recognised = [
        "friend-enrollment"
        "shared-postgres"
      ];
      byADeletedKnob = [ ];
      covered = [
        true
        true
      ];
    };
  };

  testAStatefulFolderDeclaresItsSpaceOnItsOwnStage = {
    expr = {
      elsewhere = spaceAwayFromTheStage;
      inTheImage = builtins.any (line: hasInfix "disk_gib" line) guestLines;
    };
    expected = {
      elsewhere = [ ];
      inTheImage = false;
    };
  };

  testOneModuleFileBacksBothInstances = {
    expr = {
      copies = databaseModules;
      composed = hasInfix "postgresql/databases.nix" (
        textOf instancingFolder "deployment/modules/app/default.nix"
      );
      shared = hasInfix "databases.nix" (
        textOf instancingFolder "deployment/modules/postgresql/default.nix"
      );
    };
    expected = {
      copies = [ "deployment/modules/postgresql/databases.nix" ];
      composed = true;
      shared = true;
    };
  };

  # The two halves are reported together, so a folder that fails is told which of
  # them it failed and where.
  testADeploymentStatesAHostPath = {
    expr = {
      stated = statedHostPaths;
      restated = restatedHostPaths;
    };
    expected = {
      stated = [ ];
      restated = [ ];
    };
  };

  testAUrlPathIsNotAHostPath = {
    expr = {
      classified = hostPathsOfLine "      destination = \"/index.html\";";
      carried = builtins.any (line: hasInfix "\"/index.html\"" line) (
        lines (textOf "wired-pair" "deployment/default.nix")
      );
    };
    expected = {
      classified = [ ];
      carried = true;
    };
  };

  testADerivedPathIsPermitted = {
    expr = {
      derived = hostPathsOfLine "      marker = \"/run/\${instance}-\${member}.ran\";";
      stated = hostPathsOfLine "      marker = \"/run/cluster-sweep.ran\";";
      quoted = hostPathsOfLine "      configData.\"/etc/postgresql/postgresql.conf\" = {";
    };
    expected = {
      derived = [ ];
      stated = [ "/run/cluster-sweep.ran" ];
      quoted = [ "/etc/postgresql/postgresql.conf" ];
    };
  };

  # The intersection over one folder's two halves. A deployment at the rule carries
  # no full literal for a test to agree with, so the declared half of the failing
  # case is written here rather than read off a folder.
  testATestRestatesAPathItsDeploymentCarries = {
    expr =
      restatementsBetween "wired-pair"
        [
          {
            rel = "deployment/modules/sweep/job.nix";
            line = 11;
            path = "/run/cluster-sweep.ran";
          }
        ]
        [
          {
            rel = "test_wired_pair.py";
            line = 95;
            path = "/run/cluster-sweep.ran";
          }
        ];
    expected = [
      "tests/e2e/wired-pair: /run/cluster-sweep.ran is in deployment/modules/sweep/job.nix and in test_wired_pair.py"
    ];
  };

  # Two folders whose test names a path of its own: a fake root one of them
  # assembles under, and a path the other expects a machine to refuse.
  testATestCarriesAPathOfItsOwn = {
    expr =
      let
        pathsOf = folder: map (site: site.path) (hostPathSitesOf folder (testFilesOf folder));
      in
      {
        fakeRoot = elem "/run/planner-assembly/stop-here" (pathsOf "portable-image");
        refused = elem "/opt/vendor/greeter" (pathsOf "newcomer");
        restated = restatementsIn "portable-image" ++ restatementsIn "newcomer";
      };
    expected = {
      fakeRoot = true;
      refused = true;
      restated = [ ];
    };
  };

  testTheRootDocumentStatesHowAPathReachesAUnit = {
    expr = {
      present = hasRootDocument;
      unstated = ruleUnstated;
    };
    expected = {
      present = true;
      unstated = [ ];
    };
  };

  # A quote of a sentence nobody states any more fails here rather than passing
  # unread, so a claim this repository narrows has to be requoted where it is
  # pinned. A home quoting nothing is not counted as holding anything.
  testACounterexampleQuotesTheClaimItPins = {
    expr = {
      withdrawn = withdrawnClaims;
      quoting = quotingHomes;
    };
    expected = {
      withdrawn = [ ];
      quoting = [
        "cli/counterexample_test.py"
        "tests/counterexamples/probes.nix"
        "tests/unit/counterexamples.nix"
      ];
    };
  };

  # The check reads the probe file's own attribute names, so adding a probe is
  # adding the attribute: a name written into the flake would be the hand-written
  # list this asserts the absence of.
  testAProbeIsDiscoveredRatherThanListedByHand = {
    expr = {
      listed = probesListedByHand;
      unsaid = probeCheckUnsaid;
      pinned = elem "anImplementationWithStrictFormalsIsARow" probeNames;
    };
    expected = {
      listed = [ ];
      unsaid = [ ];
      pinned = true;
    };
  };

  # The command is run rather than evaluated, and its tests answer for scenarios
  # the way an evaluating suite's and a folder's do: the cross-walk reads their
  # names off the file, and one name may not be carried by two kinds.
  testTheCommandsOwnTestsAreCounted = {
    expr = {
      counted = hasInfix commandTestFile coverageText;
      answering = commandTestNames != [ ];
      inTwoKinds = namesInTwoKinds;
    };
    expected = {
      counted = true;
      answering = true;
      inTwoKinds = [ ];
    };
  };
}
