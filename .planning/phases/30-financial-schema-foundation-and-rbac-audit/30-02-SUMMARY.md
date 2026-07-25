---
phase: 30-financial-schema-foundation-and-rbac-audit
plan: 02
subsystem: finance
tags: [sqlalchemy, alembic, rls, pydantic, postgresql]

# Dependency graph
requires: ["30-01"]
provides:
  - "CostCategory, CostEntry, LaborRate, Budget, BudgetCategoryBreakdown TenantScopedModel ORM models (backend/app/features/finance/models.py)"
  - "CostEntryCreate / BudgetCreate / BudgetCategoryBreakdownCreate Pydantic schemas with XOR anchor + breakdown-sum validators (backend/app/features/finance/schemas.py)"
  - "Migration 0032 — 5 RLS-protected finance tables, per-company is_system cost_categories seed, project_manager finance-key backfill"
affects: [30-03, 30-04, 31, 32, 33, 34, 35]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CostEntry/Budget use soft (relationship-less) job_id/trade_scope_id and project_id/trade_scope_id anchor columns — mirrors the Quote/Invoice polymorphic-anchor pattern, avoiding lazy-load footguns on the anchor side"
    - "Pre-RLS plain-INSERT seed for cost_categories (CROSS JOIN companies, ON CONFLICT DO NOTHING) — mirrors 0027's backfill-before-ENABLE approach"
    - "Per-company SET LOCAL app.current_company_id loop for a raw-SQL UPDATE against a FORCE-RLS table the appuser role can't touch cross-tenant in a single statement"

key-files:
  created:
    - backend/app/features/finance/__init__.py
    - backend/app/features/finance/models.py
    - backend/app/features/finance/schemas.py
    - backend/migrations/versions/0032_financial_schema_and_rbac.py
    - backend/tests/unit/test_finance_schemas.py
  modified:
    - backend/tests/conftest.py

key-decisions:
  - "No CostCategory/CostEntry CRUD layer (repository/service/router) ships this phase — Phase 31 builds the thin CRUD layer per 30-RESEARCH.md Q1"
  - "CostEntry anchors job_id/trade_scope_id (D-04); Budget anchors project_id/trade_scope_id (D-09) — deliberate asymmetry, not a copy-paste of one onto the other"
  - "cost_categories seeded via plain INSERT before ENABLE ROW LEVEL SECURITY (table owner appuser is NOSUPERUSER NOBYPASSRLS); company_role_permissions PM backfill instead loops per-company with SET LOCAL because that table has had FORCE RLS since migration 0027"

patterns-established:
  - "Finance domain models with money as Numeric(10,2) and lazy=\"raise\" relationships, consistent with quotes/invoices"

requirements-completed: [FINSEC-01]

# Metrics
duration: 25min
completed: 2026-07-25
---

# Phase 30 Plan 02: Financial Schema Foundation Summary

**Five RLS-protected finance tables (cost_categories, cost_entries, labor_rates, budgets, budget_category_breakdowns) plus XOR-validated Pydantic create-schemas — the data layer every later financial phase builds on, with existing companies backfilled with system cost categories and PMs' finance permissions.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 3
- **Files modified:** 6 (5 created, 1 fixed — conftest.py)

## Accomplishments
- `backend/app/features/finance/models.py` — five `TenantScopedModel` subclasses (`CostCategory`, `CostEntry`, `LaborRate`, `Budget`, `BudgetCategoryBreakdown`), all money columns `Numeric(10, 2)`, all hard-FK relationships `lazy="raise"`; `CostCategory.is_system` protects the four seeded defaults; `CostEntry`/`Budget` deliberately omit relationships on their soft anchor columns (job_id/trade_scope_id, project_id/trade_scope_id) to avoid lazy-load footguns, mirroring the Quote/Invoice pattern
- `backend/app/features/finance/schemas.py` — `CostEntryCreate` (job_id XOR trade_scope_id), `BudgetCreate` (project_id XOR trade_scope_id + `category_breakdowns` sum ≤ `total`), `BudgetCategoryBreakdownCreate`; validators mirror `QuoteCreate.validate_fields` exactly
- `backend/migrations/versions/0032_financial_schema_and_rbac.py` — creates the five tables with the inherited `TenantScopedModel` columns; seeds 4 `is_system` cost categories per company via a pre-RLS `INSERT ... CROSS JOIN companies ... ON CONFLICT DO NOTHING`; applies `ENABLE`/`FORCE ROW LEVEL SECURITY` + a `tenant_isolation_<table>` policy + `GRANT ... TO appuser` per table; backfills every existing company's `project_manager` row in `company_role_permissions` with the three `finance.*` keys via a per-company `SET LOCAL app.current_company_id` loop (idempotent via a `jsonb @>` guard); admin/owner/gc/foreman/contractor/worker/client rows are untouched
- `backend/tests/unit/test_finance_schemas.py` — 11 pure-unit tests (no DB) covering both-None/both-set/single-anchor cases for both schemas, non-positive-amount rejection, and breakdown-sum-vs-total (exceeds / within)
- Verified against `contractorhub_test`: `alembic upgrade head` clean, `downgrade -1` / `upgrade head` round-trips clean; manual `asyncpg` inspection confirmed both seeded test companies received exactly the 4 system categories and their `project_manager` rows gained the 3 finance keys while `admin` rows contained zero `finance.*` keys
- Applied the same migration directly to the dev DB `contractorhub` (`alembic upgrade head` against `DATABASE_URL`) since the local Docker daemon is not running — see Deviations

## Task Commits

Each task was committed atomically:

1. **Task 1: Finance ORM models + Pydantic create-schemas with XOR validators** - `a361aa9` (feat) — includes `test_finance_schemas.py` (Task 3's deliverable), since Task 1 is `tdd="true"` and its own `<verify>` step requires that test file to exist and pass before the task can be marked done
2. **Task 2: Migration 0032 — 5 tables + RLS + category seed + PM backfill loop** - `f5eec62` (feat)
3. **Task 3: XOR validator unit tests for the finance schemas** - already delivered as part of `a361aa9` above (see note); no separate commit was created since the test file was authored alongside Task 1 to satisfy its TDD verification gate. All of Task 3's acceptance criteria (11 `def test_` functions, `ValidationError` usage, green pytest run, clean `ruff check`) are independently satisfied by that same file.
4. **Blocking-issue fix: `clean_tables` truncate-list gap** - `8a4a7af` (fix) — Rule 3 auto-fix, see Deviations

## Files Created/Modified
- `backend/app/features/finance/__init__.py` - empty package marker
- `backend/app/features/finance/models.py` - 5 finance ORM models
- `backend/app/features/finance/schemas.py` - `CostEntryCreate`, `BudgetCreate`, `BudgetCategoryBreakdownCreate`
- `backend/migrations/versions/0032_financial_schema_and_rbac.py` - 5 tables + RLS + seed + PM backfill
- `backend/tests/unit/test_finance_schemas.py` - 11 pure-unit XOR/breakdown-sum tests
- `backend/tests/conftest.py` - added the 5 new finance tables to the `clean_tables` fixture's explicit `TRUNCATE TABLE` list

## Decisions Made
- No CRUD layer (repository/service/router) for `finance` this phase — schema + migration only, per 30-RESEARCH.md's resolved Q1; Phase 31 builds the CRUD layer
- `CostEntry` anchors `job_id`/`trade_scope_id`; `Budget` anchors `project_id`/`trade_scope_id` — an intentional asymmetry (D-04 vs D-09), not copy-paste
- `cost_categories` seed runs as a plain `INSERT` before `ENABLE ROW LEVEL SECURITY` (table is brand new, so no RLS is active yet); the `project_manager` finance-key backfill instead loops per-company with `SET LOCAL app.current_company_id` because `company_role_permissions` has carried `FORCE ROW LEVEL SECURITY` since migration 0027 and `appuser` is `NOBYPASSRLS`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] `clean_tables` test fixture's explicit TRUNCATE list didn't include the new finance tables**
- **Found during:** Task 1/3 verification — running `test_finance_schemas.py` under the full test suite (not in isolation) surfaced a `FeatureNotSupportedError: cannot truncate a table referenced in a foreign key constraint` because `cost_entries` FKs to `jobs` (and `trade_scopes`), and `budgets` FKs to `projects`/`trade_scopes`, but PostgreSQL's non-CASCADE `TRUNCATE` requires every FK-referencing table to be listed in the same statement.
- **Fix:** Added `budget_category_breakdowns, cost_entries, budgets, labor_rates, cost_categories` to `backend/tests/conftest.py`'s `clean_tables` `TRUNCATE TABLE` list (order within the list is irrelevant to PostgreSQL's FK check for a single-statement TRUNCATE, but placed alongside the Phase 27 RBAC block for readability).
- **Files modified:** `backend/tests/conftest.py`
- **Commit:** `8a4a7af`
- **Verification:** `pytest tests/unit/test_finance_schemas.py -q` (11 passed), `pytest tests/unit/ -q` (39 passed), `pytest tests/test_phase_30_e2e.py -q` (3 passed, confirms 30-01's RBAC E2E tests still pass with the fixture change)

**2. [Rule 3 - Blocking issue] `docker compose up migrate` unavailable — Docker daemon not running locally**
- **Found during:** Task 2, applying the migration to the dev DB per CLAUDE.md
- **Issue:** `docker info` fails; the local Docker daemon is not running in this environment (matches the environment notes provided for this run).
- **Fix:** Applied migration 0032 directly against the dev DB `contractorhub` with `DATABASE_URL="postgresql+asyncpg://appuser:apppassword@localhost:5432/contractorhub" alembic upgrade head` — confirmed via `alembic current` showing `0032_financial_schema_and_rbac (head)`.
- **Status:** Dev DB is up to date; the `docker compose up migrate` step itself is skipped-no-docker, as anticipated by the environment notes for this run.

## Issues Encountered
None beyond the two auto-fixed items above.

## User Setup Required

None — no external service configuration required. (When a Docker daemon becomes available again, `docker compose up migrate` will be a no-op since the dev DB is already at `0032_financial_schema_and_rbac`.)

## Next Phase Readiness
- `app/features/finance/{models,schemas}.py` and migration `0032` are the fixed schema contract every later Phase 30 plan and financial phase (31-36) builds against.
- No CRUD layer exists yet for `CostCategory`/`CostEntry`/`Budget` — this is intentional; Phase 31 adds it.
- No blockers for plan 30-03/30-04 (both already landed by other parallel executors during this run) or Phase 31.

---
*Phase: 30-financial-schema-foundation-and-rbac-audit*
*Completed: 2026-07-25*

## Self-Check: PASSED

All created files and task commits (`a361aa9`, `f5eec62`, `8a4a7af`) verified present.
