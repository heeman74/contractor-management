#!/usr/bin/env bash
#
# Create + migrate + seed the persistent DEV database (contractorhub), which is
# kept separate from the throwaway test database (contractorhub_test).
#
# Requires the Postgres superuser password (only the `postgres` role can create
# databases on this server). Run from the backend/ directory:
#
#   PGPASSWORD='<your-postgres-password>' bash scripts/setup_dev_db.sh
#
# Idempotent: safe to re-run. Login for all seed users is `password123`.

set -euo pipefail
cd "$(dirname "$0")/.."

DB_NAME="contractorhub"
DEV_URL="postgresql+asyncpg://appuser:apppassword@localhost:5432/${DB_NAME}"

if [ -z "${PGPASSWORD:-}" ]; then
  echo "ERROR: set PGPASSWORD to the postgres superuser password, e.g.:" >&2
  echo "  PGPASSWORD='...' bash scripts/setup_dev_db.sh" >&2
  exit 1
fi

echo "1/3  Creating database '${DB_NAME}' (owner appuser)..."
createdb -h localhost -U postgres -O appuser "${DB_NAME}" 2>&1 | sed 's/^/     /' || true

# Verify it actually exists before proceeding (idempotent: fine if it pre-existed).
# We check as appuser, whose password we know, so a wrong PGPASSWORD for postgres
# here surfaces as a clear message instead of a confusing migration traceback.
if ! PGPASSWORD=apppassword psql -h localhost -U appuser -d postgres -tAc \
     "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" </dev/null 2>/dev/null | grep -q 1; then
  echo >&2
  echo "ERROR: database '${DB_NAME}' was not created." >&2
  echo "  PGPASSWORD must be the POSTGRES SUPERUSER password — not appuser's 'apppassword'." >&2
  echo "  Only the 'postgres' role can create databases on this server." >&2
  echo "  If you don't know it, reset it (as your OS admin), then re-run this script:" >&2
  echo "    sudo -u postgres psql -c \"ALTER ROLE postgres PASSWORD 'newpass';\"" >&2
  exit 1
fi
echo "     database present"

echo "2/3  Applying migrations (alembic upgrade head)..."
DATABASE_URL="${DEV_URL}" .venv/bin/alembic upgrade head

echo "3/3  Seeding demo data..."
.venv/bin/python -m scripts.seed_data

echo
echo "Dev database ready: ${DB_NAME}"
echo "  Login for all seed users: password123  (e.g. admin@ace.com)"
