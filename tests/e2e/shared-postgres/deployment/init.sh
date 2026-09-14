# shellcheck shell=bash
# Everything the cluster needs exactly once: the data directory, the
# authentication file, and one role and one database per configured database
# with the password the operator delivered. The unit is one-shot and remains
# after exit, so a second apply reruns this and every step is idempotent.
#
# The unit runs as the cluster's own account, which is the account the password
# is delivered to, so nothing here is root and nothing drops privilege: the
# reader of the credential is the service that uses it.

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

install -d -m 0700 "$PGDATA"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  initdb \
    --pgdata="$PGDATA" \
    --auth-local=trust \
    --auth-host=scram-sha-256 \
    --encoding=UTF8 \
    --no-locale
fi

cat >"$work/pg_hba.conf" <<'RULES'
local   all all                 trust
host    all all 127.0.0.1/32    scram-sha-256
host    all all ::1/128         scram-sha-256
host    all all 0.0.0.0/0       scram-sha-256
RULES
install -m 0600 "$work/pg_hba.conf" "$PGDATA/pg_hba.conf"

# A private server on a unix socket of its own: the roles and the databases are
# applied before anything listens on the port the plan published.
pg_ctl \
  --pgdata="$PGDATA" \
  --wait \
  --options="-c listen_addresses= -c unix_socket_directories=$work" \
  start

trap 'pg_ctl --pgdata="$PGDATA" --wait --mode=fast stop || true; rm -rf "$work"' EXIT

sql() {
  psql \
    --no-psqlrc \
    --quiet \
    --set=ON_ERROR_STOP=1 \
    --host="$work" \
    --dbname=postgres \
    --file=-
}

query() {
  psql \
    --no-psqlrc \
    --quiet \
    --tuples-only \
    --no-align \
    --set=ON_ERROR_STOP=1 \
    --host="$work" \
    --dbname=postgres \
    --file=-
}

read -ra specs <<<"$DATABASES"
for spec in "${specs[@]}"; do
  database="${spec%%:*}"
  rest="${spec#*:}"
  owner="${rest%%:*}"
  file="${rest#*:}"

  # Doubling a quote is what SQL escapes a literal with, so a password carrying
  # one is still one literal. The bytes reach psql on stdin and never in argv.
  password="$(sed "s/'/''/g" "$file")"

  sql <<ROLE_SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$owner') THEN
    CREATE ROLE "$owner" LOGIN;
  END IF;
END
\$\$;
ALTER ROLE "$owner" WITH LOGIN PASSWORD '$password';
ROLE_SQL

  held="$(printf "SELECT 1 FROM pg_database WHERE datname = '%s';\n" "$database" | query)"
  if [ -z "$held" ]; then
    sql <<DATABASE_SQL
CREATE DATABASE "$database" OWNER "$owner";
DATABASE_SQL
  fi
done
