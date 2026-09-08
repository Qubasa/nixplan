# The platform record a plan carries: one elaborated system reduced to the facts a
# cross build spends, and JSON-safe at every depth.
#
# The is* predicates are absent on purpose. Each one is a function of parsed, so
# recording them would put seventy-five derived booleans into every entry and into
# every entry's key while telling a consumer nothing parsed does not.
{
  util,
  systems,
}:
let
  scalarNames = [
    "system"
    "config"
    "libc"
    "useLLVM"
    "linuxArch"
  ];

  parsedNames = [
    "cpu"
    "kernel"
    "abi"
  ];

  # parsed.abi carries assertions, whose entries hold a function each. The name is
  # excluded here rather than the value filtered by shape.
  abiExcluded = [ "assertions" ];

  # Written out rather than matched with a pattern, so a codegen field upstream adds
  # is a decision here instead of a silent re-key of every entry in the fleet.
  gccNames = [
    "abi"
    "arch"
    "cmodel"
    "cpu"
    "float"
    "float-abi"
    "fpu"
    "long-double-format"
    "mode"
    "strict-align"
    "thumb"
    "tune"
  ];
in
{
  inherit
    scalarNames
    parsedNames
    gccNames
    abiExcluded
    ;

  fieldNames = scalarNames ++ [
    "parsed"
    "gcc"
  ];

  inherit (systems) elaborate functionNames;

  # One system string and the microarchitecture a machine declared. A caller
  # memoises this per distinct pair, so the cost is one elaboration per
  # architecture in the fleet rather than one per machine.
  #
  # The gcc group is read off the elaboration, so the record replays: elaborating a
  # record reproduces it. A declared microarchitecture replaces the whole group
  # rather than merging into it, because elaborate applies its arguments over the
  # platform defaults. That is what a cross build would be handed.
  record =
    {
      system,
      microarchitecture,
    }:
    let
      tuned = microarchitecture != null;
      elaborated = systems.elaborate (
        {
          inherit system;
        }
        // (
          if tuned then
            {
              gcc = {
                arch = microarchitecture;
                tune = microarchitecture;
              };
            }
          else
            { }
        )
      );
      gcc = util.pickAttrs gccNames elaborated.gcc;
    in
    util.pickAttrs scalarNames elaborated
    // {
      parsed = util.pickAttrs parsedNames elaborated.parsed // {
        abi = removeAttrs elaborated.parsed.abi abiExcluded;
      };
    }
    // (if gcc == { } then { } else { inherit gcc; });
}
