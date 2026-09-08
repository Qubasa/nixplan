# The deployment planner. `mkPlan` evaluates a deployment into a plan and a
# diagnostics table and realises nothing: no derivation, no store path that is
# not a literal string, no filesystem read and no network.
#
# Evaluation is total. Every check returns a row rather than raising, korora's
# `verify` is the only entry point used, and `check` and the raise builtins
# appear nowhere under this directory. What the interpreter does not let a
# caller catch is an abort and a missing attribute, and both are documented as
# propagating rather than contained: a missing attribute inside library source
# is a bug that fails the suite loudly.
#
# `systems` is `lib.systems` of the pinned nixpkgs, the one dependency beside
# korora. It is pure Nix, produces no derivation, and one system string is
# elaborated once however many machines declare it.
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
  compose = import ./compose.nix { inherit util diag; };
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

  # The value an interface file receives: korora's own types, the atom types
  # this library owns, and the two constructors.
  korora = atoms // {
    inherit (interface) interface unitExtension;
  };

  inherit (interface)
    interface
    unitExtension
    secrecyOf
    exportNames
    atomRows
    registry
    fileOf
    label
    ;
  inherit (compose) service mkRoot;
  inherit (diag) render mkTable;

  # `interfaces` maps a declaring file, written relative to the deployment
  # root, to the interfaces declared in it. It is attribution and never
  # validation: an interface absent from it is still an interface, and a row
  # about one simply cannot render its file.
  #
  # `sources` records the files a row names: the deployment, the machine
  # registry, each instance's root and each member's leaf module.
  #
  # `varsState` is which generated files exist and what the public ones hold.
  # A file the state does not name has no bytes yet, which is the case the
  # worked deployment is built around.
  #
  # `storeDir` is the store directory an entry's paths are read against and the
  # one a consumer populates, so a machine whose store lives elsewhere is
  # planned under its own rather than under a literal written in this source.
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
