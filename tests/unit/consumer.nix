# What this flake publishes to a consumer, read as a consumer reads it: the
# identity of the package set whose platform definitions the library was applied
# to, and the library obtained against a caller's own. `flake.mkLib` is one line
# over an import of `lib/`, which is what this suite calls: the evaluating layer
# cannot read a flake output without evaluating the flake that runs it.
{
  planner,
  support,
  korora,
  systems,
  libSource,
  repoSource,
  folder,
}:
let
  inherit (builtins)
    all
    attrNames
    attrValues
    concatLists
    concatStringsSep
    elemAt
    filter
    fromJSON
    head
    isAttrs
    isFunction
    isList
    isString
    length
    listToAttrs
    mapAttrs
    match
    pathExists
    readFile
    removeAttrs
    sort
    split
    stringLength
    ;

  inherit (support)
    entryPlan
    hasInfix
    messageById
    planOf
    soleRoot
    ;

  inherit (planner.util) quoteList;

  vocabulary = planner.vocabulary;

  sorted = sort (a: b: a < b);

  lock = fromJSON (readFile (repoSource + "/flake.lock"));

  # A consumer's own definitions, in the shape a unit suite can hold one: this
  # flake's pin with one answer of the elaboration replaced. A second package set
  # is not something this layer can import, and the fact under test is that the
  # elaboration a caller hands in is the elaboration a plan is built with.
  theirSystems = systems // {
    elaborate = args: systems.elaborate args // { libc = "theirs"; };
  };

  theirLibrary = import libSource {
    inherit korora;
    systems = theirSystems;
    platformSource = "a consumer's own package set";
  };

  planWith =
    library:
    (library.mkPlan
      (import ./worked.nix {
        planner = library;
        inherit folder;
      }).args
    ).plan;

  ourPlan = support.workedResult.plan;
  theirPlan = planWith theirLibrary;

  placed = plan: filter (key: plan.${key} ? target) (attrNames plan);

  # Every entry carries its own digest, and the digest is over the entry, so an
  # entry whose platform record changed is an entry whose key changed. That is the
  # identity the choice of elaboration decides, and the rest of the plan is what it
  # does not.
  withoutIdentity =
    plan:
    mapAttrs (
      _: entry:
      removeAttrs entry [ "key" ]
      // (if entry ? target then { target = removeAttrs entry.target [ "system" ]; } else { })
    ) plan;

  libcsIn =
    plan:
    sorted (
      attrNames (
        listToAttrs (
          map (entry: {
            name = entry.target.system.libc;
            value = null;
          }) (filter (entry: entry ? target) (attrValues plan))
        )
      )
    );

  # A leaf of the projection, held to the one shape a decode has to read: a
  # string, a list of strings, or a record of those. A korora validator is a
  # function, and serialising one ends the evaluation that would have reported it,
  # so this is what "a type is named and never serialised" comes to.
  wellFormed =
    value:
    if isString value then
      true
    else if isList value then
      all isString value
    else if isAttrs value then
      all wellFormed (attrValues value)
    else
      false;

  stringsIn =
    value:
    if isString value then
      [ value ]
    else if isList value || isAttrs value then
      concatLists (map stringsIn (if isList value then value else attrValues value))
    else
      [ ];

  repeatedIn =
    keys:
    length keys != length (
      attrNames (
        listToAttrs (
          map (key: {
            name = key;
            value = null;
          }) keys
        )
      )
    );

  repeated = sorted (
    filter (name: repeatedIn vocabulary.declarations.${name}) (attrNames vocabulary.declarations)
  );

  # The keys a reading admits, read off the row that refuses one it does not:
  # that row renders the table the reading holds, so crossing the projection
  # against it compares the projection with what the library enforces rather than
  # with a binding the projection itself read. One deployment per site, because
  # five of the eight sites earn one identifier and a row is read by it.
  declarationRow = "declaration-unknown-key";
  implementationRow = "implementation-unknown-key";

  serves = _: { units.only.command = "/bin/true"; };

  placedIn = instance: planOf { instances.svc = instance; };

  withMachineKey =
    record:
    planOf {
      instances = { };
      machines = support.machines // {
        one = support.machines.one // record;
      };
    };

  extraMachineKey = withMachineKey { nope = true; };
  extraReservationKey = withMachineKey { reserves.nope = [ ]; };

  extraInstanceKey = placedIn {
    module = soleRoot { module = _: { impl = serves; }; };
    placement.every.only.machines = [ "one" ];
    nope = true;
  };

  extraPlacementKey = placedIn {
    module = soleRoot { module = _: { impl = serves; }; };
    placement.every.only = {
      machines = [ "one" ];
      nope = true;
    };
  };

  extraModuleKey = placedIn {
    module = soleRoot {
      module = _: {
        impl = serves;
        nope = true;
      };
    };
    placement.every.only.machines = [ "one" ];
  };

  extraImplKey = entryPlan { } (_: {
    units.only.command = "/bin/true";
    nope = true;
  });

  extraUnitKey = entryPlan { } (_: {
    units.only = {
      command = "/bin/true";
      nope = true;
    };
  });

  extraConfigFileKey = entryPlan { } (_: {
    units.only.command = "/bin/true";
    configData."/etc/only.conf" = {
      mode = "0444";
      source = support.assemble "only.conf" "x";
      nope = true;
    };
  });

  admits =
    row: result: keys:
    hasInfix (quoteList keys) (messageById row result);

  # The document the projection points at, and the sentences of the section it
  # names. A sentence of that section inside the projection is the copy the split
  # exists to refuse: the sentences have one home and the data has another.
  authoring = readFile (repoSource + "/docs/authoring.md");

  flattened = text: concatStringsSep " " (filter isString (split "[[:space:]]+" text));

  namedSection =
    let
      parts = split "### ${vocabulary.failures.section}" authoring;
    in
    if length parts < 3 then "" else flattened (head (split "\n### " (elemAt parts 2)));

  namedSentences = filter (sentence: stringLength sentence >= 40) (
    map flattened (filter isString (split "\\. " namedSection))
  );

  projectedText = concatStringsSep " " (stringsIn vocabulary);

  copiedSentences = filter (sentence: hasInfix sentence projectedText) namedSentences;

  # The scaffold, read as a reader who initialised it reads it.
  scaffold = repoSource + "/tests/e2e/newcomer/template";
  argsText = readFile (scaffold + "/deployment/args.nix");
  composingText = readFile (scaffold + "/deployment/default.nix");
  scaffoldFlake = readFile (scaffold + "/flake.nix");
  rootDocument = readFile (repoSource + "/README.md");

  # What the rows-only output of that flake stands packages in with, read off its
  # own text by the reading that decides whether a stand-in is a store path at
  # all.
  standIns = planner.util.storePathsIn builtins.storeDir scaffoldFlake;

  scaffoldArgs =
    greeter: (import (scaffold + "/deployment/args.nix") { packages.greeter = greeter; }).args;

  askedWith = greeter: planner.mkPlan (scaffoldArgs greeter);

  rowsOf = result: sorted (map (row: row.id) result.diagnostics);

  # The published names, read off the modules that publish them: this layer is a
  # pure evaluation and cannot read the flake that runs it, so what a consumer
  # reaches by name is read as text.
  publishingFiles = [
    "flake-module.nix"
    "cli/flake-module.nix"
    "view/flake-module.nix"
  ];

  publishedText = concatStringsSep "\n" (
    map (rel: readFile (repoSource + "/${rel}")) publishingFiles
  );

  namesOf =
    namespace: text:
    sorted (
      filter (name: name != null) (
        map (
          line:
          let
            m = match " *${namespace}\\.([a-zA-Z0-9-]+) *=.*" line;
          in
          if m == null then null else head m
        ) (support.lines text)
      )
    );

  applications = namesOf "apps" publishedText;
  publishedChecks = namesOf "checks" publishedText;

  bothProgramAndCheck = sorted (
    map (name: "${name} names a program and a check") (
      filter (name: builtins.elem name publishedChecks) applications
    )
  );

  viewModule = readFile (repoSource + "/view/flake-module.nix");

  viewUnpublished = filter (needle: !(hasInfix needle viewModule)) [
    "packages.planner-view ="
    "packages.planner-view-src ="
    "apps.planner-view ="
  ];

  viewImported = hasInfix "view/flake-module.nix" (readFile (repoSource + "/flake.nix"));

  pinnedInputs = sorted (attrNames (removeAttrs lock.nodes [ "root" ]));
in
{
  testTheLibraryStatesWhoseNixpkgsElaboratedItsPlatforms = {
    expr = {
      recorded = planner.platformSource or null;
    };
    expected = {
      recorded = lock.nodes.nixpkgs.locked.rev;
    };
  };

  testAConsumerElaboratesAMachineWithItsOwnNixpkgs = {
    expr = {
      theirs = libcsIn theirPlan;
      ours = libcsIn ourPlan;
      keys = attrNames theirPlan;
      rekeyed = sorted (filter (key: theirPlan.${key}.key != ourPlan.${key}.key) (attrNames ourPlan));
      otherwise = withoutIdentity theirPlan;
    };
    expected = {
      theirs = [ "theirs" ];
      ours = [ "glibc" ];
      keys = attrNames ourPlan;
      rekeyed = sorted (placed ourPlan);
      otherwise = withoutIdentity ourPlan;
    };
  };

  # The view is reached by output name and adds no input of its own: the standard
  # library is what it is written against, so the pinned set is the set it was
  # before.
  testAConsumerReadsTheViewOffAnOutput = {
    expr = {
      unpublished = viewUnpublished;
      imported = viewImported;
      ownInput = hasInfix "inputs." viewModule;
      inputs = pinnedInputs;
    };
    expected = {
      unpublished = [ ];
      imported = true;
      ownInput = false;
      inputs = [
        "adios"
        "flake-parts"
        "flakelet"
        "korora"
        "nixpkgs"
        "treefmt-nix"
      ];
    };
  };

  # A check is a value of this repository's own development and a program is the
  # thing a reader runs, so no name answers one command with the program and
  # another with its check.
  testACheckOverAPublishedProgramTakesANameOfItsOwn = {
    expr = {
      answering = bothProgramAndCheck;
      program = builtins.elem "planner-view" applications;
      check = builtins.elem "planner-view-tests" publishedChecks;
    };
    expected = {
      answering = [ ];
      program = true;
      check = true;
    };
  };

  testThePublishedVocabularyNamesEveryKeyADeclarationMayCarry = {
    expr = {
      machine = admits declarationRow extraMachineKey vocabulary.declarations.machine;
      reservation = admits declarationRow extraReservationKey vocabulary.declarations.reservation;
      instance = admits declarationRow extraInstanceKey vocabulary.declarations.instance;
      placement = admits declarationRow extraPlacementKey vocabulary.declarations.placement;
      module = admits declarationRow extraModuleKey vocabulary.declarations.module;
      impl = admits implementationRow extraImplKey vocabulary.declarations.impl;
      unit = admits implementationRow extraUnitKey vocabulary.declarations.unit;
      configFile = admits implementationRow extraConfigFileKey vocabulary.declarations.configFile;
      tables = sorted (attrNames vocabulary.declarations);
      inherit repeated;
      # Every field of the unit vocabulary is a key the unit declaration names,
      # so a field added to one table and absent from the other fails here.
      fieldsAreKeys = sorted (
        filter (field: !(builtins.elem field vocabulary.declarations.unit)) (
          attrNames vocabulary.unitFields
        )
      );
      # A directory kind is two keys of that declaration: the kind, and the mode
      # the kind is applied at.
      kindsAreKeys = sorted (
        filter (
          key:
          !(builtins.elem key vocabulary.declarations.unit)
          || !(builtins.elem vocabulary.directoryKinds.${key} vocabulary.declarations.unit)
        ) (attrNames vocabulary.directoryKinds)
      );
    };
    expected = {
      machine = true;
      reservation = true;
      instance = true;
      placement = true;
      module = true;
      impl = true;
      unit = true;
      configFile = true;
      tables = [
        "configFile"
        "impl"
        "instance"
        "machine"
        "module"
        "placement"
        "reservation"
        "unit"
      ];
      repeated = [ ];
      fieldsAreKeys = [ ];
      kindsAreKeys = [ ];
    };
  };

  testATypeIsPublishedByItsNameAndNotByItsPredicate = {
    expr = {
      # Three fields whose types are predicates over strings, one of them a
      # compound: each carries the name korora built the type under.
      account = vocabulary.unitFields.user;
      bound = vocabulary.unitFields.probeTimeout;
      references = vocabulary.unitFields.after;
      namedByTheAtom = vocabulary.unitFields.user == planner.atoms.userName.name;
      # The validator beside that name is a function, which is why a name is what
      # a projection can carry at all.
      validatorIsAFunction = isFunction planner.atoms.userName.verify;
      everyLeafIsReadable = wellFormed vocabulary;
      # The port range is text for the same reason: one decode reads every leaf
      # of this record.
      range = vocabulary.portRange;
    };
    expected = {
      account = "userName";
      bound = "duration";
      references = "listOf<unitRef>";
      namedByTheAtom = true;
      validatorIsAFunction = true;
      everyLeafIsReadable = true;
      range = {
        first = "1";
        last = "65535";
        privilegedBelow = "1024";
      };
    };
  };

  testADomainThatIsAPredicateIsNotPublishedAsADomain = {
    expr = {
      published = sorted (attrNames vocabulary.domains);
      restartPolicy = vocabulary.domains.restartPolicy;
      scope = vocabulary.domains.scope;
      # The table the projection reads carries one predicate, riding a key no
      # atom carries, and the projection carries no entry for it.
      tableCarriesThePredicate = planner.atoms.domains ? isZeroDuration;
      predicateIsAFunction = isFunction planner.atoms.domains.isZeroDuration;
      publishedAsADomain = vocabulary.domains ? isZeroDuration;
    };
    expected = {
      published = [
        "consumerCardinality"
        "protocol"
        "restartPolicy"
        "scope"
      ];
      restartPolicy = [
        "no"
        "on-failure"
        "on-abnormal"
        "always"
      ];
      scope = [
        "system"
        "user"
      ];
      tableCarriesThePredicate = true;
      predicateIsAFunction = true;
      publishedAsADomain = false;
    };
  };

  testThePublishedVocabularyNamesTheSectionRatherThanCopyingIt = {
    expr = {
      document = vocabulary.failures.document;
      section = vocabulary.failures.section;
      documentIsThere = pathExists (repoSource + "/${vocabulary.failures.document}");
      headingIsThere = hasInfix "### ${vocabulary.failures.section}" authoring;
      sectionWasRead = length namedSentences >= 4;
      copied = copiedSentences;
    };
    expected = {
      document = "docs/authoring.md";
      section = "What ends an evaluation";
      documentIsThere = true;
      headingIsThere = true;
      sectionWasRead = true;
      copied = [ ];
    };
  };

  testTheScaffoldCarriesTwoEntryPointsOverOneDeployment = {
    expr = {
      # The entry point that takes no package set states the deployment.
      statesTheInstances = hasInfix "inherit (deployment) instances" argsText;
      statesTheRegistry = hasInfix "inherit (registry) machines" argsText;
      takesNoPackageSet = hasInfix "pkgs" argsText;
      # The one that takes a package set composes it and states none of it. The
      # needle carries no leading `./`: the path scan reads one in this file as
      # this file's own, and a sibling of `tests/unit/` is not what it names.
      composes = hasInfix "args.nix" composingText;
      statesAnInstance = hasInfix "instances" composingText;
      readsTheRegistry = hasInfix "machines.nix" composingText;
      takesAPackageSet = hasInfix "pkgs," composingText;
      # Both are in the text a document shows, which that document is held to
      # byte for byte by `testTheExampleADocumentShowsIsTheExampleAFolderHolds`.
      bothShown = hasInfix argsText rootDocument && hasInfix composingText rootDocument;
    };
    expected = {
      statesTheInstances = true;
      statesTheRegistry = true;
      takesNoPackageSet = false;
      composes = true;
      statesAnInstance = false;
      readsTheRegistry = false;
      takesAPackageSet = true;
      bothShown = true;
    };
  };

  testAPlaceholderPackageIsAStorePath = {
    expr = {
      # The stand-in is read off the scaffold's own flake by the reading that
      # decides whether one is a store path at all.
      recognised = standIns;
      # And it is load-bearing: a bare name is recognised as no store path, so
      # the family of rows comparing an entry's mentioned paths against its
      # declared roots answers about nothing and a clean table means nothing.
      asAStorePath = rowsOf (askedWith (head standIns));
      asABareName = rowsOf (askedWith "greeter");
      entries = sorted (
        filter (key: (askedWith (head standIns)).plan.${key} ? target) (
          attrNames (askedWith (head standIns)).plan
        )
      );
    };
    expected = {
      recognised = [ "/nix/store/9zv4c8m2kq7r5xn3bdlp6yfs0agh1jw2-greet" ];
      asAStorePath = [ ];
      asABareName = [
        "closure-root-outside-store"
        "closure-root-outside-store"
        "closure-root-unmentioned"
        "closure-root-unmentioned"
      ];
      entries = [
        "greeter:greet@alpha"
        "greeter:greet@beta"
      ];
    };
  };
}
