# The names of the tests whose actual value differs from their expected one.
#
# nix-unit is the runner the check uses; this is the same comparison as a plain
# value, so that `nix eval .#planner.failures` answers "what is red" without a
# build.
suites:
let
  isTest = v: builtins.isAttrs v && v ? expr && v ? expected;

  walk =
    prefix: set:
    builtins.concatLists (
      builtins.attrValues (
        builtins.mapAttrs (
          name: value:
          if isTest value then
            (if value.expr == value.expected then [ ] else [ "${prefix}${name}" ])
          else if builtins.isAttrs value then
            walk "${prefix}${name}." value
          else
            [ ]
        ) set
      )
    );
in
walk "" suites
