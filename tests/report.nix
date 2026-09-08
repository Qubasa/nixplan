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
