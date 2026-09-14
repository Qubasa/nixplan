# shellcheck shell=bash
# One role and one database per configured database, with the password the
# operator delivered. The cluster and its data directory are somebody else's:
# the directory is a declaration the service manager honours and the cluster is
# a unit of its own, so this step creates neither and runs on every apply.
#
# Convergence is the point. Each statement states what the deployment names
# rather than what is missing, so a changed owner reaches a database that
# already exists and a role the deployment no longer names loses its login.
#
# The unit runs as the cluster's own account, which is the account the password
# is delivered to, so nothing here is root and nothing drops privilege: the
# reader of the credential is the service that uses it.

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The roles are applied through whichever server holds this cluster, and both
# read the configuration file the deployment declares, so that one file decides
# how a password is hashed either way. A first apply has no server, so one is
# started on a socket of its own and stopped again; a later apply reaches the
# published server over the socket directory that same file names.
if pg_ctl --pgdata="$PGDATA" status >/dev/null 2>&1; then
  socket="$PGDATA"
else
  socket="$work"
  pg_ctl \
    --pgdata="$PGDATA" \
    --wait \
    --options="-c config_file=$PGCONFIG -c listen_addresses= -c unix_socket_directories=$work" \
    start
  trap 'pg_ctl --pgdata="$PGDATA" --wait --mode=fast stop || true; rm -rf "$work"' EXIT
fi

sql() {
  psql \
    --no-psqlrc \
    --quiet \
    --set=ON_ERROR_STOP=1 \
    --host="$socket" \
    --port="$PGPORT" \
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
    --host="$socket" \
    --port="$PGPORT" \
    --dbname=postgres \
    --file=-
}

# Doubling the quote is what SQL escapes with, and which quote depends on
# whether the value names a thing or is one. The substitution is the shell's
# own and the statements reach psql on stdin, so a password is in no process
# argument list and no external program ever sees it.
literal() {
  printf "'%s'" "${1//\'/\'\'}"
}

ident() {
  printf '"%s"' "${1//\"/\"\"}"
}

read -ra specs <<<"$DATABASES"

named=""
for spec in "${specs[@]}"; do
  rest="${spec#*:}"
  named="$named ${rest%%:*}"
done

superseded=""

for spec in "${specs[@]}"; do
  database="${spec%%:*}"
  rest="${spec#*:}"
  owner="${rest%%:*}"
  file="${rest#*:}"

  password="$(cat "$file")"

  sql <<ROLE_SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = $(literal "$owner")) THEN
    CREATE ROLE $(ident "$owner") LOGIN;
  END IF;
END
\$\$;
ALTER ROLE $(ident "$owner") WITH LOGIN PASSWORD $(literal "$password");
ROLE_SQL

  held="$(printf 'SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = %s;\n' "$(literal "$database")" | query)"

  if [ -z "$held" ]; then
    sql <<DATABASE_SQL
CREATE DATABASE $(ident "$database") OWNER $(ident "$owner");
DATABASE_SQL
  else
    # The owner is stated rather than created, and the role that held it hands
    # over what it owns inside the database: an object's owner is not the
    # database's, so without the grant the newly declared owner could not read
    # a table the previous one wrote.
    sql <<OWNER_SQL
ALTER DATABASE $(ident "$database") OWNER TO $(ident "$owner");
OWNER_SQL
    if [ "$held" != "$owner" ]; then
      sql <<HANDOVER_SQL
GRANT $(ident "$held") TO $(ident "$owner");
HANDOVER_SQL
      superseded="$superseded $held"
    fi
  fi
done

# A role the deployment no longer names loses its login and nothing else. What
# a deployment states is who may log in, never which of a machine's objects to
# delete, so the role and everything it owns stay where they are.
for role in $superseded; do
  case " $named " in
  *" $role "*) continue ;;
  esac
  sql <<LOGIN_SQL
ALTER ROLE $(ident "$role") NOLOGIN;
LOGIN_SQL
done
