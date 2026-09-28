# Deploying ContractorHub to Render

`render.yaml` in the repo root is a Blueprint describing four resources:
managed Postgres 16, a Key Value (Redis) instance, the FastAPI API as a
**private** service, and the Next.js app as the only public web service.

Nothing here has been deployed yet — the blueprint has not been run against a
real Render account, so treat the first deploy as a dry run and expect to
confirm plan names and the internal API port in the dashboard.

## Before the first deploy

### 1. Set up an email provider

Password reset ships in this release and it is the one feature that fails
*silently* when misconfigured. With `SMTP_HOST` unset, `EmailService` runs in
dev mode: `/forgot-password` still returns 202, the UI still says "check your
email", and nothing is ever sent.

Pick a provider (SES, SendGrid, Mailgun — all expose plain SMTP), verify a
sending domain, and collect host, port, username, password, and a From address
on the verified domain.

### 2. Create the Blueprint

In Render: **New → Blueprint**, point it at `heeman74/contractor-management`,
branch `master`. It will read `render.yaml`.

### 3. Fill in the values marked `sync: false`

| Variable | Service | Value |
|---|---|---|
| `PUBLIC_WEB_URL` | contractorhub-api | The web service's public URL, e.g. `https://contractorhub-web.onrender.com`. **Reset links are built from this** — a wrong value produces links that 404. |
| `SMTP_HOST` | contractorhub-api | Provider SMTP host |
| `SMTP_USER` | contractorhub-api | Provider SMTP username |
| `SMTP_PASSWORD` | contractorhub-api | Provider SMTP password |
| `SMTP_FROM` | contractorhub-api | `ContractorHub <no-reply@yourdomain.com>` on the verified domain |
| `ANTHROPIC_API_KEY` | contractorhub-api | Only needed for the AI features |

`PUBLIC_WEB_URL` is circular on a first deploy — the web URL does not exist
until the web service is created. Deploy once, copy the web URL, set it, and
redeploy the API.

### 4. Database extensions

Migrations create `uuid-ossp` and `btree_gist`. Both are on Render's supported
list, but the migration runs as the database owner rather than a superuser, so
if `preDeployCommand` fails on `CREATE EXTENSION`, create them once by hand
from the Render Postgres shell and re-run the deploy.

## Why tenant isolation depends on migration 0041

Locally, `docker/init.sql` creates `appuser`, a `NOSUPERUSER NOBYPASSRLS` role
that is *not* the table owner in CI, so row level security is enforced.

Render gives you exactly one role and it owns every table. Postgres exempts a
table's owner from its own RLS policies unless the table is set to **FORCE**.
Four tables (`billing_milestones`, `punch_list_items`, `site_walk_flags`,
`task_inspections`) only ever called `ENABLE`, and the drift differed between
databases. Migration `0041_force_rls_missing_tables` forces RLS on every
policy-bearing table it finds, and `tests/test_rls_forced.py` keeps the
invariant from regressing.

**Do not point this blueprint at a database that has not reached 0041.** On an
owner connection, those four tables would serve rows from every company.

## After deploying

1. Register a company and confirm login works.
2. Run the full reset flow against a **real inbox** — this is the check that
   local testing cannot make, because locally the mail is only logged.
3. Confirm the reset link's host matches `PUBLIC_WEB_URL`.
4. Change password from the topbar dialog; confirm the old password fails.
5. Create a quote and confirm the quote number appears in list and detail.

## Rollback

`0041`'s downgrade is deliberately a no-op: the prior state was a
tenant-isolation hole and it differed per database, so there is no correct set
of tables to un-force. Roll back application code freely; do not try to reverse
0041.
