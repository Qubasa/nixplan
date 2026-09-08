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
