# shellcheck shell=bash
# The cluster's one-time initialisation. Whether it runs at all is the service
# manager's answer, from the absence of the file this step creates, and the
# directory it writes into is one the service manager created for the unit.
#
# No authentication flag is stated here: the declared configuration file names
# the authentication file and the hashing method, so one file decides both.

initdb \
  --pgdata="$PGDATA" \
  --encoding=UTF8 \
  --no-locale
