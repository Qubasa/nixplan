# shellcheck shell=bash
set -u

# The one thing this unit is for: write back the name the operator's runs dial
# this machine by, so the mesh name is read off the machine as well as off the
# plan. Nothing here knows how the machine became a member.
printf 'dialled-name: %s\n' "$DIALLED_NAME"
printf 'identity: uid=%s\n' "$(id -u)"
printf '%s' "$DIALLED_NAME" > "$RUNTIME_DIRECTORY/$RECORD_NAME"
printf 'record: %s\n' "$RUNTIME_DIRECTORY/$RECORD_NAME"
exec sleep infinity
