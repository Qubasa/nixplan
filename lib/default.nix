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
# platformSource is that package set's identity as its caller knows it. A platform
# record is a field of every placed entry and an entry key is a digest over the
# entry, so which elaboration ran decides identity. The library invents no name for
# it and records nothing where a caller states none.
{
  korora,
  systems,
  platformSource ? null,
}:
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
      atoms
      diag
      interface
      module
      compose
      platform
      ;
  };
  plan = import ./plan.nix { inherit util diag module; };

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
    platformSource
    util
    ;

  korora = atoms // {
    inherit (interface)
      interface
      unitExtension
      fold
      refuse
      ;
  };

  inherit (interface)
    interface
    unitExtension
    fold
    refuse
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
      # Every argument is read for its kind before anything indexes it. A
      # caller's argument sits in no module file and carries no plan key, so the
      # row names the file the caller writes its deployment in, which is the
      # subject a name the reading refused already falls back to.
      argument =
        {
          name,
          value,
          ok,
          fallback,
          what,
        }:
        if ok then
          {
            inherit value;
            rows = [ ];
          }
        else
          {
            value = fallback;
            rows = [
              (diag.error {
                subject = subjectFile;
                id = "planner-argument-malformed";
                message = "`mkPlan` was handed ${util.quote name} as ${util.shownValue value}, and the planner reads ${what} there";
                evidence = "an argument of the entry point is indexed, coerced or hashed by the readings below it, and a value of another kind is neither a catchable error nor a row, so the argument is read as unstated and the rest of the deployment is still planned";
                resolution = "write ${what} for ${util.quote name} where `mkPlan` is called";
              })
            ];
          };

      record =
        name: value:
        argument {
          inherit name value;
          ok = builtins.isAttrs value;
          fallback = { };
          what = "a record";
        };

      sourcesRead = record "sources" sources;
      sourceField =
        name: fallback: ok:
        argument {
          name = "sources.${name}";
          value = sourcesRead.value.${name} or fallback;
          inherit fallback;
          ok = !(sourcesRead.value ? ${name}) || ok sourcesRead.value.${name};
          what = if builtins.isString fallback then "a path relative to the deployment root" else "a record";
        };

      sourceFields = {
        deployment = sourceField "deployment" defaultSources.deployment builtins.isString;
        machines = sourceField "machines" defaultSources.machines builtins.isString;
        modules = sourceField "modules" defaultSources.modules builtins.isAttrs;
        leaves = sourceField "leaves" defaultSources.leaves builtins.isAttrs;
      };

      merged = builtins.mapAttrs (_: read: read.value) sourceFields;
      subjectFile =
        let
          stated = sourcesRead.value.deployment or null;
        in
        if diag.isValidSubject stated then stated else defaultSources.deployment;

      machinesRead = record "machines" machines;
      instancesRead = record "instances" instances;
      interfacesRead = record "interfaces" interfaces;
      varsStateRead = record "varsState" varsState;
      storeDirRead = argument {
        name = "storeDir";
        value = storeDir;
        ok = builtins.isString storeDir;
        fallback = builtins.storeDir;
        what = "the store directory as a string";
      };

      argumentRows =
        sourcesRead.rows
        ++ builtins.concatLists (builtins.attrValues (builtins.mapAttrs (_: read: read.rows) sourceFields))
        ++ machinesRead.rows
        ++ instancesRead.rows
        ++ interfacesRead.rows
        ++ varsStateRead.rows
        ++ storeDirRead.rows;

      reg = interface.registry interfacesRead.value;

      resolved = resolve.resolve {
        inherit reg;
        instances = instancesRead.value;
        machines = machinesRead.value;
        varsState = varsStateRead.value;
        storeDir = storeDirRead.value;
        sources = merged;
      };

      emitted = plan.entries resolved;

      atomRows = interface.registryRows reg resolved.interfaces;

      diagnostics = diag.mkTable (argumentRows ++ atomRows ++ resolved.rows ++ emitted.rows);
    in
    {
      inherit (emitted) plan;
      inherit diagnostics;
      applicable = !diag.hasError diagnostics;
    };
}
