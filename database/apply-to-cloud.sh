#!/bin/zsh
# ============================================================
# apply-to-cloud.sh: applies database scripts to the CLOUD (UAT/production) database, one file at a time, in the order given.
#
#   database/apply-to-cloud.sh migration/add_x.sql functions/fnd_y.sql     apply these, in this order
#   database/apply-to-cloud.sh --check migration/add_x.sql                 only show what would be applied
#
# Rules it enforces:
#   - only files under database/migration/ or database/functions/, ending in .sql, inside this repository
#   - each file runs in its own transaction with ON_ERROR_STOP: a file either applies completely or not at all, and the
#     run stops at the first file that fails (later files are not attempted)
#   - the database password is read from "supabase setup/supabase initial setup.txt" (never committed, never printed)
#   - every file applied is recorded in database/cloud-applied.log (date, git commit, file, result); no secrets in it
# Claude runs it only after the owner approves the specific files; the owner allowed this one script in Claude Code's settings.
# ============================================================
set -u
cd "$(dirname "$0")/.." || exit 1          # repository root
REPO=$(pwd)
SETUP="$REPO/supabase setup/supabase initial setup.txt"
LOG="$REPO/database/cloud-applied.log"
HOST="aws-1-us-east-2.pooler.supabase.com"
DBUSER="postgres.dizsenktyfnprxbxujpf"
CONTAINER="supabase_db_bps-local"          # local Docker container that has psql

CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi
if [ $# -eq 0 ]; then echo "usage: database/apply-to-cloud.sh [--check] migration/file.sql functions/file.sql ..."; exit 2; fi

# validate every file before touching the database
for f in "$@"; do
  case "$f" in
    migration/*.sql|functions/*.sql) ;;
    *) echo "REFUSED: $f (only migration/*.sql or functions/*.sql, relative to database/)"; exit 2 ;;
  esac
  case "$f" in *..*) echo "REFUSED: $f (no .. in paths)"; exit 2 ;; esac
  [ -f "$REPO/database/$f" ] || { echo "NOT FOUND: database/$f"; exit 2; }
done

COMMIT=$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo "unknown")
DIRTY=$(git -C "$REPO" status --porcelain -- "${@/#/database/}" 2>/dev/null | wc -l | tr -d ' ')
echo "Cloud database: $DBUSER @ $HOST"
echo "Git commit: $COMMIT$( [ "$DIRTY" != "0" ] && echo " (with uncommitted changes in these files)")"
echo "Files, in order:"; for f in "$@"; do echo "  database/$f"; done
if [ $CHECK -eq 1 ]; then echo "(check only: nothing applied)"; exit 0; fi

PW=$(awk -F': ' '/^Database Pswd:/{print $2; exit}' "$SETUP" 2>/dev/null | tr -d '\r')
[ -n "$PW" ] || { echo "Could not read the database password from: supabase setup/supabase initial setup.txt"; exit 3; }
docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "Docker container $CONTAINER is not running (it provides psql)"; exit 3; }

for f in "$@"; do
  printf "Applying database/%s ... " "$f"
  OUT=$(docker exec -i -e PGPASSWORD="$PW" "$CONTAINER" psql "host=$HOST port=5432 dbname=postgres user=$DBUSER sslmode=require" \
        -q -v ON_ERROR_STOP=1 --single-transaction < "$REPO/database/$f" 2>&1)
  RC=$?
  if [ $RC -eq 0 ]; then
    echo "OK"
    echo "$(date -u '+%Y-%m-%d %H:%M:%SZ')  $COMMIT  OK      database/$f" >> "$LOG"
  else
    echo "FAILED"
    echo "$OUT" | grep -v '^NOTICE' | head -20
    echo "$(date -u '+%Y-%m-%d %H:%M:%SZ')  $COMMIT  FAILED  database/$f" >> "$LOG"
    echo "Stopped: this file was rolled back; later files were not attempted."
    exit 1
  fi
done
echo "All files applied."
