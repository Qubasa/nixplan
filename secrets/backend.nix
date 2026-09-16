# The deploy step of the external secret generator, rendered from one plan.
#
# The contract hands that step a list of files on standard input and nothing
# else: no machine, no address and no path. So this file renders it, addressing
# exactly the machines a value's delivery set names, at the addresses the plan
# recorded, and writing each file at the path the plan fixed.
{
  planner,
  reader ? import ./read.nix { inherit planner; },
}:
let
  inherit (builtins) concatStringsSep filter;

  # Every value the local shell parses goes through the library's own escape, a
  # word `wordOf` already admitted included: the rule and the escape hold
  # independently, or the next character the rule gains closes the quoting it was
  # relying on.
  inherit (planner.util) shellQuote;

  # The words the step carries are the reading's, asked of it rather than
  # restated, so a word this renders is a word that plan was already refused
  # for and the row and the refusal are one sentence.
  inherit (reader) accounts renderedWords;

  wordOf =
    ctx: word:
    let
      value = word.word ctx;
    in
    if value == null then
      word.absent ctx
    else if reader.unrenderable value then
      reader.fail accounts.wordUnrenderable {
        inherit (ctx) key;
        inherit (word) what;
        named = word.named ctx;
        inherit value;
      }
    else
      shellQuote value;

  # One branch per file the tool may name on standard input, and one `deliver` per
  # machine of that file's delivery set. A pair no branch names is refused: it
  # means the configuration and this script were rendered from two plans.
  branch =
    user: delivery: file:
    [
      "  ${shellQuote "${delivery.name} ${file.file}"})"
    ]
    ++ map (
      target:
      let
        ctx = {
          inherit (delivery) key;
          inherit user;
        }
        // file
        // target;
      in
      "    deliver ${shellQuote delivery.name} ${shellQuote file.file} ${concatStringsSep " " (map (wordOf ctx) renderedWords)}"
    ) delivery.machines
    ++ [ "    ;;" ];

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
    "get=${shellQuote get}"
    "ssh_options=\${${options}:-}"
    ""
    "# One temporary for the whole step, removed on every way out of it. The fetch"
    "# writes plaintext and `set -eu` exits the step where a send is refused, so a"
    "# removal written after the send is the one that never runs."
    "tmp=$(mktemp)"
    "trap 'rm -f \"$tmp\"' EXIT INT TERM HUP"
    ""
    "deliver() {"
    "  : > \"$tmp\""
    "  out=\"$tmp\" \"$get\" \"$1\" \"$2\""
    "  # shellcheck disable=SC2086"
    "  ssh $ssh_options -T \"$3\" \"set -eu; umask 077; (umask 066; mkdir -p '$4'); chmod 0711 '$4'; install -m 0600 /dev/null '$5.new'; cat > '$5.new'; chown '$7' '$5.new'; chmod '$6' '$5.new'; mv '$5.new' '$5'; chmod '$6' '$5'; chown '$7' '$5'\" < \"$tmp\""
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
