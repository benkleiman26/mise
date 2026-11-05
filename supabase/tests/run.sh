#!/usr/bin/env bash
# Runs supabase/schema.sql against a throwaway Postgres and checks it behaves.
#
# The schema is the one part of Mise that nothing else tests, and it is the
# part that took four rounds to get right against the real server. This starts
# a local Postgres, stands up the pieces Supabase would provide, loads the
# schema and runs the checks. Nothing here touches the real project.
#
#   ./supabase/tests/run.sh
#
# Needs a Postgres server binary. On a Mac: brew install postgresql@16
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
schema="$here/../schema.sql"

for dir in /usr/lib/postgresql/*/bin /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@16/bin; do
  [ -x "$dir/initdb" ] && export PATH="$dir:$PATH" && break
done
command -v initdb >/dev/null || { echo "No Postgres server found. brew install postgresql@16"; exit 1; }

# initdb refuses to run as root, so when we are root the work happens as the
# postgres user, whose home is somewhere it can actually write.
if [ "$(id -u)" = "0" ]; then
  base=$(getent passwd postgres | cut -d: -f6)
  # su resets PATH, so the Postgres binaries have to be handed over.
  runner() { su postgres -c "export PATH='$PATH'; $1"; }
  install -o postgres -m 644 "$schema" "$base/schema.sql"
  for f in "$here"/0*.sql; do install -o postgres -m 644 "$f" "$base/$(basename "$f")"; done
else
  base="${TMPDIR:-/tmp}/mise-schema-test"
  mkdir -p "$base"
  runner() { bash -c "$1"; }
  cp "$schema" "$base/schema.sql"
  cp "$here"/0*.sql "$base/"
fi

data="$base/pg/data"
sock="$base/pg/sock"
port=${PGPORT:-5433}

runner "rm -rf '$base/pg'; mkdir -p '$sock'"
runner "initdb -D '$data' -U postgres --auth=trust >/dev/null 2>&1"
runner "pg_ctl -D '$data' -o \"-k '$sock' -p $port -c listen_addresses=''\" -l '$base/pg/log' -w start >/dev/null"
trap "runner \"pg_ctl -D '$data' -m immediate stop >/dev/null 2>&1 || true\"" EXIT

files="-f '$base/00-supabase-stubs.sql' -f '$base/schema.sql' -f '$base/01-push.sql' -f '$base/02-policies.sql'"
output=$(runner "psql -h '$sock' -p $port -U postgres -v ON_ERROR_STOP=1 -q $files" 2>&1) || {
  echo "$output" | grep -E "ERROR|FAIL" || echo "$output" | tail -20
  exit 1
}

echo "$output" | grep -E "PASS|FAIL" | sed 's/^.*NOTICE:  //'
echo
echo "$(echo "$output" | grep -c PASS) checks passed."
