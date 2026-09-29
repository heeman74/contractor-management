# Deploying ContractorHub to Render (free tier)

`render.yaml` is a Blueprint describing three resources: managed Postgres 16,
the FastAPI API, and the Next.js app. Both services run on the free plan.

Nothing here has been deployed successfully yet. The start command and the
migration step have been verified locally against the real production image,
but the blueprint itself has not completed a run on Render.

## Free-tier limitations, and what they cost you

| Limit | Consequence |
|---|---|
| Private services are paid-only | The API runs as a public web service. The browser still only talks to the Next.js app, but the API has a reachable URL. |
| `preDeployCommand` is paid-only | Migrations run in `backend/start.sh` instead, which then execs uvicorn. Safe here because the service runs a single worker. |
| ~512MB RAM | uvicorn runs 1 worker, not 4. |
| Services sleep when idle | First request after a sleep is slow. If the API is asleep, the web app's first call can fail before it wakes. |
| No private networking | `FASTAPI_URL` must be the API's **public** URL, not an internal hostname. |
| No Redis in this blueprint | Redis is lazy-initialised and only backs chat WebSocket fan-out, so the app boots fine. Realtime chat relay is the one feature that will not work. |
| Free Postgres expires | Render's free databases are time-limited. Plan to upgrade or migrate before it lapses — check the current expiry in your dashboard, as the policy has changed over time. |

## Why there is a start.sh

`dockerCommand` cannot be an inline `sh -c "a && b"`. Render wraps the command
in a shell of its own, which re-quotes the string so the whole thing becomes a
single command name:

    sh: 1: alembic upgrade head && uvicorn ...: not found
    ==> Exited with status 127

`backend/start.sh` avoids every layer of that quoting. It also binds `$PORT`,
which Render assigns and which is **not** 8000 — binding the wrong port fails
the health check. Verified locally with `PORT=10000`: `/health` returned 200.
Next's standalone server already honours `$PORT` on its own, so the web service
needs no equivalent.

## Deploy order

`PUBLIC_WEB_URL` and `FASTAPI_URL` each need a URL that does not exist until
the other service is created, so the first pass is deliberately two-phase.

1. **Render → New → Blueprint**, point at `heeman74/contractor-management`,
   branch `master`. It reads `render.yaml`. Do **not** create services by hand —
   a manually created Web Service defaults to the repo root, which has no
   Dockerfile, and the build fails immediately.
2. Let both services build. The web service will be unhealthy at this point;
   that is expected, it has no `FASTAPI_URL` yet.
3. Copy the two public URLs Render assigns.
4. Set the `sync: false` values (table below), then redeploy both services.

## Values you must set

| Variable | Service | Value |
|---|---|---|
| `FASTAPI_URL` | contractorhub-web | The API's public URL, e.g. `https://contractorhub-api.onrender.com` |
| `PUBLIC_WEB_URL` | contractorhub-api | The web app's public URL. **Reset links are built from this** — wrong value means links that 404. |
| `SMTP_HOST` | contractorhub-api | Provider SMTP host |
| `SMTP_USER` | contractorhub-api | Provider SMTP username |
| `SMTP_PASSWORD` | contractorhub-api | Provider SMTP password |
| `SMTP_FROM` | contractorhub-api | `ContractorHub <no-reply@yourdomain.com>`, on a verified domain |
| `ANTHROPIC_API_KEY` | contractorhub-api | Only needed for the AI features |

### Email is the silent one

With `SMTP_HOST` unset, `EmailService` runs in dev mode: `/forgot-password`
still returns 202, the UI still says "check your email", and nothing is sent.
Password reset ships in this release, so set SMTP before real users touch it.

## Database extensions

Migrations create `uuid-ossp` and `btree_gist`. Both are on Render's supported
list, but the migration runs as the database owner rather than a superuser. If
the deploy fails on `CREATE EXTENSION`, create them once by hand from the
Render Postgres shell and redeploy.

## Why tenant isolation depends on migration 0041

Locally, `docker/init.sql` creates `appuser`, a `NOSUPERUSER NOBYPASSRLS` role
that does not own the tables, so row level security is enforced.

Render gives you exactly one role and it owns every table. Postgres exempts a
table's owner from its own RLS policies unless the table is set to **FORCE**.
Four tables (`billing_milestones`, `punch_list_items`, `site_walk_flags`,
`task_inspections`) only ever called `ENABLE`, and the drift differed between
databases. Migration `0041_force_rls_missing_tables` forces RLS on every
policy-bearing table it finds; `tests/test_rls_forced.py` keeps it from
regressing.

**Do not point this blueprint at a database below revision 0041.** On an owner
connection, those four tables would serve rows from every company.

## After deploying

1. Register a company and confirm login works.
2. Run the full reset flow against a **real inbox** — the check local testing
   cannot make, because locally the mail is only logged.
3. Confirm the reset link's host matches `PUBLIC_WEB_URL`.
4. Change password from the topbar dialog; confirm the old password fails.
5. Create a quote and confirm the quote number appears in list and detail.

## Rollback

`0041`'s downgrade is deliberately a no-op: the prior state was a
tenant-isolation hole and it differed per database, so there is no correct set
of tables to un-force. Roll back application code freely; do not reverse 0041.
