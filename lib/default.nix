# The deployment planner. mkPlan evaluates a deployment into a plan and a
# diagnostics table and realises nothing: no derivation, no filesystem read, no
# network, and no store path that is not a literal string.
#
# Evaluation is total. Every check returns a row instead of raising, and no
# raising call appears anywhere under this directory. An abort and a missing
# attribute are the two things a caller cannot catch, so both propagate on
# purpose: a missing attribute in library source is a bug that should fail loudly.
#
# systems is lib.systems of the pinned nixpkgs, the one dependency beside korora.
{ korora, systems }:
let
  util = import ./util.nix;
  excluded = import ./excluded.nix;
  diag = import ./diagnostics.nix { inherit util; };
  atoms = import ./atoms.nix { inherit korora; };
  interface = import ./interface.nix { inherit util diag excluded; };
  platform = import ./platform.nix { inherit util systems; };
  module = import ./module.nix {
    inherit
      util
      diag
      excluded
      interface
      atoms
      ;
  };
  compose = import ./compose.nix { inherit util diag excluded; };
  resolve = import ./resolve.nix {
    inherit
      util
      diag
      interface
      module
      compose
      excluded
      platform
      ;
  };
  plan = import ./plan.nix { inherit util diag; };

  defaultSources = {
    deployment = "deployment/instances.nix";
    machines = "deployment/machines.nix";
    modules = { };
    leaves = { };
  };
in
{
  inherit
    atoms
    excluded
    platform
    util
    ;

  korora = atoms // {
    inherit (interface) interface unitExtension fold;
  };

  inherit (interface)
    interface
    unitExtension
    fold
    foldName
    foldApply
    identityOf
    secrecyOf
    exportNames
    atomRows
    foldOf
    registry
    fileOf
    label
    ;
  inherit (compose) service mkRoot;
  inherit (diag)
    render
    mkTable
    row
    error
    warning
    ;

  # interfaces maps a declaring file to the interfaces declared in it. It is
  # attribution and never validation: an interface absent from it is still an
  # interface, and a row about one simply cannot print its file.
  #
  # sources is the file each row names. varsState is which generated files exist
  # and what the public ones hold. storeDir is the store an entry's paths are read
  # against and the one a consumer populates, so a machine whose store lives
  # elsewhere is planned under its own.
  mkPlan =
    {
      interfaces ? { },
      instances,
      machines,
      varsState ? { },
      sources ? { },
      storeDir ? builtins.storeDir,
    }:
    let
      merged = defaultSources // sources;
      reg = interface.registry interfaces;

      resolved = resolve.resolve {
        inherit
          reg
          instances
          machines
          varsState
          storeDir
          ;
        sources = merged;
      };

      emitted = plan.entries resolved;

      atomRows = interface.registryRows reg;

      diagnostics = diag.mkTable (atomRows ++ resolved.rows ++ emitted.rows);
    in
    {
      inherit (emitted) plan;
      inherit diagnostics;
      applicable = !diag.hasError diagnostics;
    };
}
