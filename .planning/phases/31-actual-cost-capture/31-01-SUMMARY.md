---
phase: 31-actual-cost-capture
plan: 01
subsystem: api
tags: [fastapi, sqlalchemy, postgres, rls, finance, cost-entries]

# Dependency graph
requires:
  - phase: 30-financial-schema-foundation-and-rbac-audit
    provides: "CostEntry/CostCategory models + XOR anchor validator, finance.view/finance.manage permission keys, per-company cost_categories seed"
provides:
  - "Gated /api/v1/cost-entries CRUD (create/list/get/patch/soft-delete) anchored to job XOR trade scope"
  - "/api/v1/projects/{id}/cost-entries single-query rollup (trade-scope costs + job costs)"
  - "/api/v1/cost-categories listing endpoint"
  - "cost_receipts table (migration 0034) + CostReceipt model, ready for Plan 31-02's upload/serve endpoints"
affects: [31-02-receipt-upload-and-serving, 33-margin-tracking, 34-budgeting, 35-financial-dashboard]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Plain APIRouter with inline require_permission(...)(current_user, db) gating (not CRUDRouter — no permission hook)"
    - "Single LEFT OUTER JOIN + OR-predicate rollup query (trade_scopes.project_id OR jobs.project_id), Decimal total summed in Python over the one fetched list — no second aggregate query"
    - "Every custom repository list/get method adds .where(CostEntry.deleted_at.is_(None)) explicitly — TenantScopedRepository.list_all() does not filter soft-deletes"

key-files:
  created:
    - backend/migrations/versions/0034_cost_receipts.py
    - backend/app/features/finance/repository.py
    - backend/app/features/finance/service.py
    - backend/app/features/finance/router.py
    - backend/tests/test_phase_31_e2e.py
  modified:
    - backend/app/features/finance/models.py
    - backend/app/features/finance/schemas.py
    - backend/app/main.py
    - backend/tests/conftest.py

key-decisions:
  - "CostEntryUpdate does not allow changing job_id/trade_scope_id (anchor is immutable after creation) — avoids re-deriving XOR consistency and rollup-cache invalidation complexity, per research recommendation"
  - "cost_receipts is a dedicated table (not a generic polymorphic attachments table), consistent with the codebase's one-table-per-domain attachment convention"
  - "New companies created via /auth/register are NOT auto-seeded with cost_categories (a pre-existing Phase 30 gap, not introduced here) — E2E tests seed categories explicitly per test, mirroring test_phase_30_e2e.py's own workaround"

requirements-completed: [COST-01, COST-02]

# Metrics
duration: 30min
completed: 2026-07-26
---

# Phase 31 Plan 01: Cost-Entry Backend CRUD + Rollup Summary

**Gated `/api/v1/cost-entries` + `/api/v1/cost-categories` + `/api/v1/projects/{id}/cost-entries` REST API for materials/subcontractor/other cost entries, backed by a single-query project rollup and a new `cost_receipts` table for Plan 31-02.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-07-26T04:31Z
- **Completed:** 2026-07-26T04:44Z
- **Tasks:** 3 completed
- **Files modified:** 9 (5 created, 4 modified)

## Accomplishments

- Owner/PM can create, list, read, update, and soft-delete materials/subcontractor/other cost entries anchored to a job XOR a trade scope, gated by `finance.manage`/`finance.view` — proven by 9 passing backend E2E tests.
- Project cost rollup (`GET /api/v1/projects/{id}/cost-entries`) combines trade-scope-anchored costs and job-anchored costs (where `jobs.project_id` matches) in a single query, excluding soft-deleted entries and unrelated jobs.
- Migration 0034 creates `cost_receipts` (RLS-enabled, chained off 0033) and the `CostReceipt` model, so Plan 31-02 can add upload/serve endpoints without a schema change.
- A non-finance role (admin) gets 403 on every cost-entry, rollup, and category endpoint — verified by `test_non_finance_role_403_on_every_cost_endpoint`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Migration 0034 + CostReceipt model + finance response/update schemas** - `8282ce5` (feat)
2. **Task 2: FinanceRepository + FinanceService (deleted_at filters, single-query rollup)** - `703d6a3` (feat)
3. **Task 3: finance router (gated cost-entry + category + rollup endpoints), register in main.py, cost-entry E2E** - `371d4bb` (feat)

_No TDD RED/GREEN split — Task 2 was tagged `tdd="true"` in the plan, but its own verify command is an import/source assertion; the actual behavioral coverage (list/rollup/soft-delete/RLS) is the Task 3 E2E suite, per the plan's own Validation Architecture (31-01-T2 = import+source assert, 31-01-T3 = E2E)._

## Files Created/Modified

- `backend/migrations/versions/0034_cost_receipts.py` - `cost_receipts` table + RLS (ENABLE/FORCE + tenant_isolation policy + appuser grant), chained off `0033_project_quotes`
- `backend/app/features/finance/models.py` - Added `CostReceipt(TenantScopedModel)` with `lazy="raise"` relationship to `CostEntry`
- `backend/app/features/finance/schemas.py` - Added `CostEntryUpdate`, `CostCategoryResponse`, `CostReceiptResponse`, `CostEntryResponse` (with `category_name`), `ProjectCostRollupResponse`
- `backend/app/features/finance/repository.py` - `FinanceRepository`: `list_for_job`, `list_for_trade_scope`, `rollup_for_project` (single LEFT OUTER JOIN query), `get_entry_or_404`, `soft_delete`, `list_categories`
- `backend/app/features/finance/service.py` - `FinanceService(TenantScopedService[CostEntry])` — delegates all logic to the repository, no `db.commit()`
- `backend/app/features/finance/router.py` - Plain `APIRouter`, 7 endpoints, `require_permission` called inline in every handler
- `backend/app/main.py` - Registered `finance_router` at `/api/v1`, next to `billing_milestones_router`
- `backend/tests/test_phase_31_e2e.py` - 9 E2E tests: materials on job/trade-scope, XOR-anchor rejection, subcontractor/other categories, soft-delete exclusion (list + rollup), project rollup combining scope+job costs, API-level RLS isolation, 403-for-non-finance across every endpoint
- `backend/tests/conftest.py` - Added `cost_receipts` to `clean_tables`'s TRUNCATE list (new table from migration 0034), ordered before `cost_entries` (FK child-before-parent)

## Decisions Made

- **CostEntryUpdate anchor immutability**: chose not to allow changing `job_id`/`trade_scope_id` on update — the research doc flagged this as the simpler, lower-risk choice (avoids re-validating XOR + any future rollup-cache invalidation), and CONTEXT.md left this to discretion.
- **Dedicated `cost_receipts` table**: mirrors the codebase's existing one-table-per-domain attachment pattern (`task_attachments`, `attachments`) rather than a shared polymorphic table — keeps the finance domain self-contained and makes the future `serve_router.py` existence check a simple single-model query.
- **Rollup computed in Python, not SQL `SUM`**: the service sums `Decimal` amounts over the one itemized list already fetched by the repository, rather than issuing a second aggregate query — satisfies the "one query" N+1 rule while still returning the itemized list the Costs tab needs.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] `cost_receipts` missing from `clean_tables` TRUNCATE list**
- **Found during:** Task 3 (writing the E2E test file, reasoning about test isolation for the new table)
- **Issue:** Migration 0034 (Task 1) created `cost_receipts`, but `conftest.py`'s `clean_tables` fixture — which CLAUDE.md's Testing Rules require to truncate ALL tables between tests — did not include it. No test in this plan writes to `cost_receipts` yet (that's Plan 31-02), so there was no test-pollution risk today, but leaving a newly-created table out of the truncation list is an accepted-debt trap for whichever plan starts writing to it.
- **Fix:** Added `cost_receipts` to the TRUNCATE statement, positioned before `cost_entries` (its parent via FK) to preserve the file's documented child-before-parent ordering.
- **Files modified:** `backend/tests/conftest.py`
- **Commit:** `371d4bb` (part of Task 3's commit)

---

**Total deviations:** 1 auto-fixed (Rule 2)
**Impact on plan:** Low-risk, in-scope completion of test infrastructure for a table this plan itself created. No scope creep — the fix is a one-line addition to an existing list, not new functionality.

## Issues Encountered

- **Alembic env var loading**: `alembic upgrade head` failed locally with `password authentication failed for user "placeholder"` because `migrations/env.py` reads `DATABASE_URL` from `os.environ` (not from `.env` via `python-dotenv`), and `alembic.ini`'s fallback URL is a `placeholder:placeholder` credential pair. Resolved by exporting `.env`'s variables into the shell (`export $(grep -v '^#' .env | xargs)`) before running `alembic upgrade head` / `pytest`. Not a code defect — `conftest.py` already handles this correctly for the test DB by setting `os.environ["DATABASE_URL"]` directly before importing the app; this only affected my manual dev-DB migration run.
- **Docker unavailable**: `docker compose up migrate` (the plan's stated dev-DB migration command) could not run — the Docker daemon was not running in this environment. Applied the migration directly to the locally-running PostgreSQL 13 instance via `alembic upgrade head` instead (confirmed via `alembic heads` showing `0034_cost_receipts` as the sole head). No functional difference for verification purposes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 31-02 (receipt upload/serving) can proceed immediately: `cost_receipts` table, `CostReceipt` model, and `CostReceiptResponse` schema all exist and are verified; the only remaining work is the upload endpoint, `serve_router.py` extension, and receipt-specific E2E tests.
- `backend/tests/test_phase_31_e2e.py` is the shared phase E2E file — Plan 31-02 extends it with receipt tests (per 31-VALIDATION.md's per-task map), matching the existing pattern from `test_phase_30_e2e.py`.
- No blockers. Full backend regression sample (phase 30, 25, 19 E2E — 45 tests) passed after this plan's `main.py`/`conftest.py` changes; a full-suite run was kicked off to catch any wider regressions and will be confirmed before the phase is considered fully verified.

---
*Phase: 31-actual-cost-capture*
*Completed: 2026-07-26*

## Self-Check: PASSED

All created files found on disk; all three task commit hashes (`8282ce5`, `703d6a3`, `371d4bb`) found in git history.
