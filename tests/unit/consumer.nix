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
    filter
    fromJSON
    listToAttrs
    mapAttrs
    readFile
    removeAttrs
    sort
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
}
