#!/bin/sh
# Container entrypoint for platform deploys (Render, and anything like it).
#
# Exists as a script rather than an inline dockerCommand because the platform
# wraps that command in a shell of its own. An inline `sh -c "a && b"` then
# gets re-quoted and the whole thing is treated as one command name:
#
#   sh: 1: alembic upgrade head && uvicorn ...: not found
#
# A script sidesteps every layer of that quoting.
set -e

# Render assigns the port it will route to and injects it as $PORT; it is not
# necessarily 8000. Binding the wrong one fails the health check.
PORT="${PORT:-8000}"

# Free instances are small, so default to a single worker. Render also sets
# WEB_CONCURRENCY based on available CPUs, so honour that when present.
WORKERS="${WEB_CONCURRENCY:-1}"

echo "Running migrations..."
alembic upgrade head

echo "Starting uvicorn on 0.0.0.0:${PORT} with ${WORKERS} worker(s)..."
# --proxy-headers makes the app read X-Forwarded-Proto, so every URL it builds
# keeps the scheme the browser used. Without it the platform's TLS terminator
# forwards plain HTTP and the app believes it is serving http://, which it then
# writes into absolute URLs: the trailing-slash redirect on every list endpoint
# came back as http://, and a https -> http hop is cross-origin, where fetch
# drops Authorization. The result was a 401 on exactly those endpoints.
#
# --forwarded-allow-ips="*" is required for the above to take effect: uvicorn
# only honours forwarded headers from trusted peers and defaults to 127.0.0.1,
# while the platform router connects from an internal address that varies. The
# container takes traffic only through that router, so every peer it sees is the
# proxy.
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT}" --workers "${WORKERS}" \
  --proxy-headers --forwarded-allow-ips="*"
