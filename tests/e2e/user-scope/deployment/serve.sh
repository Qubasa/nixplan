# shellcheck shell=bash
set -u

# The value the run delivered, opened by the unit that reads it: the whole
# question this folder asks of a machine is whether an account's own manager can
# run this at all and whether this can open that file.
token="$(cat "$TOKEN_FILE")"
printf 'token-read: %s\n' "$token"
printf 'identity: uid=%s\n' "$(id -u)"
printf '%s' "$token" > "$RUNTIME_DIRECTORY/$RECORD_NAME"
printf 'record: %s\n' "$RUNTIME_DIRECTORY/$RECORD_NAME"
exec sleep infinity
