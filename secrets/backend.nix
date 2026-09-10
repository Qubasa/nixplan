# The deploy step of the external secret generator, rendered from one plan.
#
# The contract hands that step a list of files on standard input and nothing
# else: no machine, no address and no path. So this file renders it. For every
# file the plan records, the script addresses exactly the machines the value's
# delivery set names, at the addresses the plan recorded, and writes the file at
# the path the plan fixed.
#
# It carries no bytes. Each file is fetched from the store backend's own `get`
# program at run time, which is the only thing that ever reads them.
{
  planner,
  reader ? import ./read.nix { inherit planner; },
}:
let
  inherit (builtins)
    concatStringsSep
    filter
    match
    replaceStrings
    ;

  # The rule an address and a path are held to is the reading's, asked of it
  # rather than restated, so the row it reports and the refusal here are one
  # sentence.
  inherit (reader) accounts;

  wordOf =
    key: what: named: value:
    if reader.unrenderable value then
      reader.fail accounts.wordUnrenderable {
        inherit
          key
          what
          named
          value
          ;
      }
    else
      "'${value}'";

  quoted = value: "'${replaceStrings [ "'" ] [ "'\\''" ] value}'";

  # One branch per file the tool may name on standard input, and one `deliver` per
  # machine of that file's delivery set. A pair no branch names is refused: it
  # means the configuration and this script were rendered from two plans.
  branch =
    user: delivery: file:
    let
      word = wordOf delivery.key;
    in
    [
      "  ${quoted "${delivery.name} ${file.file}"})"
    ]
    ++ map (
      target:
      "    deliver ${quoted delivery.name} ${quoted file.file} ${
            word "the address" target.machine "${user}@${target.address}"
          } ${word "the parent directory of the path" delivery.key (parentOf delivery.key file.path)} ${
            word "the path" delivery.key file.path
          }"
    ) delivery.machines
    ++ [ "    ;;" ];

  parentOf =
    key: path:
    let
      m = match "(.*)/[^/]*" path;
    in
    if m == null then
      reader.fail accounts.pathNamesNoDirectory { inherit key path; }
    else
      builtins.head m;

  # The contract says a deploy step takes what else it needs from the environment,
  # and reaching a machine whose host key nobody has accepted yet is exactly that:
  # unquoted on purpose, so an operator's options are words rather than one.
  options = "PLANNER_SECRETS_SSH_OPTS";

  header = get: [
    "#!/bin/sh"
    "# Rendered by planner secrets from one plan. It names machines and paths and"
    "# carries no bytes: every file is read from the store backend at run time."
    "set -eu"
    ""
    "get=${quoted get}"
    "ssh_options=\${${options}:-}"
    ""
    "deliver() {"
    "  tmp=$(mktemp)"
    "  out=\"$tmp\" \"$get\" \"$1\" \"$2\""
    "  # shellcheck disable=SC2086"
    "  ssh $ssh_options -T \"$3\" \"set -eu; umask 077; mkdir -p '$4'; cat > '$5.new'; chmod 0400 '$5.new'; mv '$5.new' '$5'\" < \"$tmp\""
    "  rm -f \"$tmp\""
    "}"
    ""
    "# The tool writes the file list with `\"\\n\".join(...)`, so its last line carries"
    "# no newline and a plain `read` would return non-zero having already assigned it."
    "while read -r generator file || [ -n \"$generator\" ]; do"
    "  [ -n \"$generator\" ] || continue"
    "  case \"$generator $file\" in"
  ];

  footer = [
    "  *)"
    "    echo \"planner secrets: the plan names no delivery for '$generator/$file'\" >&2"
    "    exit 1"
    "    ;;"
    "  esac"
    "done"
  ];
in
{
  inherit reader;

  # get is the store backend's own `get` program, as a path. The plan holds no
  # such thing and neither does the contract's deploy step, so the caller that
  # owns the backend hands it over.
  render =
    {
      plan,
      get,
      user ? "root",
    }:
    let
      deliveries = filter (delivery: delivery.machines != [ ]) (reader.deliveriesOf plan);
      branches = builtins.concatLists (
        map (delivery: builtins.concatLists (map (branch user delivery) delivery.files)) deliveries
      );
    in
    concatStringsSep "\n" (header get ++ branches ++ footer) + "\n";
}
