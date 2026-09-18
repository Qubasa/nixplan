# shellcheck shell=bash
set -u

# Two variables this script reads are assigned by nobody it can see, so the
# one warning about that is disabled at each of the two commands that read
# one. A directive is not written at the top of this file because this file is
# not the top of the script: its bytes are concatenated into a wrapper below
# the wrapper's own prelude, so a directive here is a directive about the next
# command and never about the file. `expiry` is assigned by the deployment,
# one line above these bytes, and `out` is handed to a generator's program by
# whatever realises it - this deployment states the program and runs it never.

# The credential this deployment declares, minted with the coordination
# server's own tool: single-use, because the key admits whoever presents it
# first and the second presenter has to be refused for an interception to be
# visible, and expiring, because a key that never expires is bearer authority
# forever. Single-use is the absence of a reusable flag and the expiry is the
# one this deployment states, prepended to this script as `expiry`; both
# refusals are then the server's own and neither is this tree's to make.
#
# `runtimeInputs` put the server's tool on this script's own PATH, so what
# mints the key is the package the deployment names rather than whatever the
# caller's PATH resolves.
#
# Two facts arrive from the environment because neither can be written here.
# The configuration path is derived inside `impl` from the identity of the
# entry that runs the server, so a copy of it in this script would be a host
# path this deployment states. `HEADSCALE_OWNER` carries a number and not a
# word: the tool's own flag is `-u, --user uint`, so what it takes is the
# identifier the server's database assigned the group, read back with
# `headscale users list --output json`. That database is never a source this
# tree reads, so an operator who runs this hands both facts in.
#
# The tool prints one JSON object per created credential, and `jq` takes the
# key out of it: a file holding the whole answer would be a credential nobody
# can present, and a presenter that had to find the key inside it would be
# parsing the tool's output shape twice.
#
# One file, no trailing newline: a credential is presented byte for byte, and a
# trailing byte is one the presenter would have to know to strip. The key is
# bound to a variable first, because the exit status of a command substitution
# inside an argument of `printf` is `printf`'s and not the minting's.
# shellcheck disable=SC2154
key="$(
  headscale \
    --config "$HEADSCALE_CONFIG" \
    preauthkeys create \
    --user "$HEADSCALE_OWNER" \
    --expiration "$expiry" \
    --output json |
    jq -r '.key'
)"
# shellcheck disable=SC2154
printf '%s' "$key" > "$out/preauthkey"
