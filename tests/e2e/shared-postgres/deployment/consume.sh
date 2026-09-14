# shellcheck shell=bash
# One row written and read back through the capability this entry wired, and a
# record of what it took to do it. The unit is one-shot and remains after exit,
# so "the credential worked" is a unit state.
#
# The retry is cross-machine boot ordering and nothing else: the cluster's
# machine may still be running its initialiser when this unit starts.

rest="${DB_DSN#postgresql://}"
hostport="${rest#*@}"
hostport="${hostport%%/*}"
host="${hostport%%:*}"
port="${hostport##*:}"
database="${rest##*/}"

PGPASSWORD="$(cat "$DB_PASSWORD_FILE")"
export PGPASSWORD

ask() {
  psql \
    --no-psqlrc \
    --quiet \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --host="$host" \
    --port="$port" \
    --username="$DB_USER" \
    --dbname="$database" \
    --file=-
}

reached=no
for _ in $(seq 1 90); do
  if printf 'SELECT 1;\n' | ask >/dev/null 2>&1; then
    reached=yes
    break
  fi
  sleep 2
done

if [ "$reached" != yes ]; then
  echo "no answer from $host:$port/$database" >&2
  exit 1
fi

ask <<ROW
CREATE TABLE IF NOT EXISTS notes (label text PRIMARY KEY, written timestamptz NOT NULL DEFAULT now());
INSERT INTO notes (label) VALUES ('$LABEL') ON CONFLICT (label) DO NOTHING;
ROW

labels="$(printf 'SELECT string_agg(label, %s ORDER BY label) FROM notes;\n' "','" | ask)"
serverVersion="$(printf 'SHOW server_version;\n' | ask)"
currentUser="$(printf 'SELECT current_user;\n' | ask)"
currentDatabase="$(printf 'SELECT current_database();\n' | ask)"
identifier="$(printf 'SELECT system_identifier FROM pg_control_system();\n' | ask)"

# One `key=value` line per observation, because a value spanning lines is a
# parse the reader on the other end cannot make.
record="$(mktemp)"
cat >"$record" <<RECORD
label=$LABEL
dsn=$DB_DSN
host=$host
port=$port
database=$currentDatabase
user=$currentUser
declaredVersion=$DB_VERSION
serverVersion=$serverVersion
identifier=$identifier
labels=$labels
RECORD
install -m 0644 "$record" "$RECORD_PATH"
rm -f "$record"
