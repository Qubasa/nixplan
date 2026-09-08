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

  abiExcluded = [ "assertions" ];

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
