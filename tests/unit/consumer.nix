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
    attrNames
    attrValues
    concatStringsSep
    filter
    fromJSON
    head
    listToAttrs
    mapAttrs
    match
    readFile
    removeAttrs
    sort
    ;

  inherit (support)
    hasInfix
    ;

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

}
