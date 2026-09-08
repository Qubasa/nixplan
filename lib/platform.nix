# The platform record a plan carries: a fixed projection of one elaborated
# system, reduced to the facts a cross build spends and JSON-safe at every
# depth.
#
# The projection is a toolchain's own vocabulary and nothing else. The target
# triple, the libc it is configured against and the parsed cpu/kernel/abi are
# what selects a compiler and what a build has to agree with; the `gcc` group is
# the codegen fields nixpkgs itself spends, `arch`, `tune`, `cpu`, `fpu`,
# `float`, `float-abi`, `mode`, `thumb`, `strict-align` and `cmodel` through
# cc-wrapper (`nixpkgs:pkgs/build-support/cc-wrapper/default.nix:315-367`) and
# `abi`, `float`, `mode` and `long-double-format` through gcc's own build
# (`nixpkgs:pkgs/development/compilers/gcc/common/platform-flags.nix:8-45`).
#
# The `is*` predicates are deliberately absent. Every one of them is a function
# of `parsed` — `isLinux` is `parsed.kernel.name == "linux"`, `is64bit` is
# `parsed.cpu.bits == 64` — so recording them would put seventy-five derived
# booleans in every entry, in every entry's key, and in every plan diff, while
# telling a consumer nothing `parsed` does not. A consumer that wants one
# derives it; a consumer that wants the whole family elaborates the `system`
# string the record carries.
#
# Upstream's own `_withoutFunctions` is not this projection and cannot be. It is
# `removeAttrs` over a deny-list of four top-level names, so functions nested
# below the top level survive it and `builtins.toJSON` of the result raises,
# which suites/platform.nix measures. It is also the whole record, so an
# upstream field would enter every entry's key without anybody deciding it.
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

  # `parsed.abi` carries `assertions`, whose entries hold a function each. It is
  # the measurement that rules upstream's filter out, so the name is excluded
  # here rather than the value being filtered by shape.
  abiExcluded = [ "assertions" ];

  # Written out rather than matched with a pattern, so a codegen field upstream
  # adds to a platform is a decision here instead of a silent re-key of every
  # entry in the fleet. suites/platform.nix crosses this list against every
  # exposed double's elaboration.
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

  # Every name the projection can put in a record, which is what a guard case
  # compares against `lib.systems.functionNames`.
  fieldNames = scalarNames ++ [
    "parsed"
    "gcc"
  ];

  # The elaboration itself, for the guard case that measures what upstream's
  # filter leaves behind. Nothing in the library reads a plan value through it.
  inherit (systems) elaborate functionNames;

  # One system string and the microarchitecture the machine declared, or null.
  # A caller memoises this per distinct pair: the cost is one elaboration per
  # architecture in the fleet rather than one per machine.
  #
  # The `gcc` group is read off the elaboration rather than from the declared
  # microarchitecture, so the record is a `crossSystem` fragment that replays:
  # elaborating `{ system, gcc }` from a record reproduces that record. A
  # platform carrying codegen defaults — `armv7l-linux` its `arch` and `fpu`,
  # `loongarch64-linux` its `cmodel` and `strict-align` — therefore records
  # them for a machine that declared no microarchitecture, and a declared one
  # replaces the whole group rather than merging into it, because `elaborate`
  # applies `args` over `platforms.select`
  # (`nixpkgs/lib/systems/default.nix:320-328,443`). That is what cc-wrapper
  # would be handed for the same declaration.
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
