---
phase: 19-project-data-model
plan: 01
subsystem: database
tags: [sqlalchemy, alembic, postgresql, rls, pydantic, tenant-isolation]

# Dependency graph
requires:
  - phase: prior migrations
    provides: TenantScopedModel base class, existing migration chain through 0014

provides:
  - Six SQLAlchemy TenantScopedModel subclasses for project data model
  - Pydantic Create/Update/Response schemas for all six entities
  - Alembic migration 0015 creating all tables with RLS, indexes, triggers, data migration

affects:
  - 19-02 (Drift schema uses same entity names)
  - 19-03 (backend CRUD endpoints use these models and schemas)
  - 21 (AI intake creates projects/trade_scopes/tasks using these tables)
  - 20 (dependency engine operates on tasks table)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Six-table project hierarchy (Project -> TradeScope -> Task -> TaskAttachment)
    - TradeCatalog as reference table with UNIQUE(company_id, name) normalization
    - UserTradeSpecialty as join table (queryable specialty matching, not JSONB)
    - unnest() lateral join form for PostgreSQL 13 compatibility in data migrations
    - Conftest clean_tables must include all new tables in FK dependency order

key-files:
  created:
    - backend/app/features/projects/__init__.py
    - backend/app/features/projects/models.py
    - backend/app/features/projects/schemas.py
    - backend/migrations/versions/0015_project_data_model.py
  modified:
    - backend/tests/conftest.py

key-decisions:
  - "TradeCatalog uses UNIQUE(company_id, name) constraint; ON CONFLICT DO NOTHING makes data migration idempotent"
  - "UserTradeSpecialty is a join table (not JSONB on User) to enable queryable contractor specialty matching"
  - "unnest(trade_types) uses lateral join syntax (FROM companies, unnest(...) AS ut(trade_name)) for PostgreSQL 13 compatibility"
  - "conftest clean_tables must list task_attachments->tasks->trade_scopes->projects->user_trade_specialties->trade_catalog before users/companies"

patterns-established:
  - "Pattern: All six new models follow TenantScopedModel inheritance with lazy='raise' on all relationships"
  - "Pattern: from __future__ import annotations + TYPE_CHECKING for User FK to avoid circular imports"
  - "Pattern: RLS loop in migration applies ENABLE, CREATE POLICY, FORCE for all tables in a single loop"

requirements-completed: [PROJ-01, PROJ-02]

# Metrics
duration: 13min
completed: 2026-03-20
---

# Phase 19 Plan 01: Project Data Model - Backend Models and Migration Summary

**Six TenantScopedModel SQLAlchemy models, Pydantic schemas, and Alembic migration 0015 creating Project/TradeScope/Task hierarchy with RLS, 11 indexes, and trade_catalog data migration from free-text Jobs/Companies data**

## Performance

- **Duration:** 13 min
- **Started:** 2026-03-20T11:33:22Z
- **Completed:** 2026-03-20T11:46:20Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Six SQLAlchemy models (Project, TradeCatalog, TradeScope, Task, TaskAttachment, UserTradeSpecialty) with correct inheritance, all relationships using lazy="raise", CheckConstraints and UniqueConstraints
- Full Pydantic v2 Create/Update/Response schema set for all entities inheriting TenantResponseSchema
- Migration 0015 creates all 6 tables in FK-dependency order with RLS tenant_isolation policy, set_updated_at triggers, and 11 indexes
- Data migration seeds trade_catalog from existing Jobs.trade_type and Companies.trade_types using idempotent ON CONFLICT DO NOTHING
- All existing 271 tests still pass after migration

## Task Commits

Each task was committed atomically:

1. **Task 1: SQLAlchemy models and Pydantic schemas** - `ac73c67` (feat)
2. **Task 2: Alembic migration 0015 + conftest fix** - `ecf4f7d` (feat)

## Files Created/Modified
- `backend/app/features/projects/__init__.py` - Empty package init
- `backend/app/features/projects/models.py` - Six TenantScopedModel subclasses with relationships and constraints
- `backend/app/features/projects/schemas.py` - Create/Update/Response Pydantic schemas for all six entities
- `backend/migrations/versions/0015_project_data_model.py` - Full migration with tables, RLS, indexes, triggers, data migration
- `backend/tests/conftest.py` - Added new tables to clean_tables truncation list

## Decisions Made
- TradeCatalog uses UNIQUE(company_id, name) to prevent duplicates; ON CONFLICT DO NOTHING in data migration makes it idempotent and safe to run multiple times
- UserTradeSpecialty is a join table rather than JSONB on User because the contractor assignment feature requires queryable specialty matching
- unnest() in the data migration uses the lateral join form `FROM companies, unnest(trade_types) AS ut(trade_name)` because PostgreSQL 13 does not support `SELECT DISTINCT company_id, unnest(trade_types)` (the DISTINCT blocks the set-returning function)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed PostgreSQL 13 incompatible unnest() syntax in data migration**
- **Found during:** Task 2 (Alembic migration 0015)
- **Issue:** The RESEARCH.md Pattern 3 data migration SQL used `SELECT DISTINCT company_id, unnest(trade_types) AS trade_name FROM companies` which PostgreSQL 13 rejects with "column company_id does not exist" when unnest() is in the SELECT list alongside DISTINCT
- **Fix:** Changed to lateral join form: `FROM companies, unnest(trade_types) AS ut(trade_name)` with `id AS company_id`
- **Files modified:** backend/migrations/versions/0015_project_data_model.py
- **Verification:** SQL tested directly via psql; returns correct results (0 rows on empty test DB, no error)
- **Committed in:** ecf4f7d (Task 2 commit)

**2. [Rule 2 - Missing Critical] Added new tables to conftest clean_tables truncation list**
- **Found during:** Task 2 (running existing tests after migration)
- **Issue:** `clean_tables` fixture TRUNCATE statement didn't include the 6 new tables, causing `cannot truncate a table referenced in a foreign key constraint` error for all existing tests
- **Fix:** Added task_attachments, tasks, trade_scopes, projects, user_trade_specialties, trade_catalog (in FK-dependency order, before users/companies) to the TRUNCATE statement
- **Files modified:** backend/tests/conftest.py
- **Verification:** All 271 previously-passing tests continue to pass
- **Committed in:** ecf4f7d (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (1 Rule 1 bug, 1 Rule 2 missing critical)
**Impact on plan:** Both fixes required for migration to succeed and tests to remain green. No scope creep.

## Issues Encountered
- Pre-existing test failures (unrelated to our changes): `test_list_clients_with_search` (ValidationError in jobs/router.py) and `test_user_roles_are_tenant_scoped` - both confirmed pre-existing by stashing our changes and reproducing the failures.

## Next Phase Readiness
- Migration 0015 applied to contractorhub_test database; all 6 tables exist with RLS
- All models and schemas importable; ready for Plan 02 (Drift schema v7)
- Plan 03 (backend CRUD endpoints) can proceed after Plan 02

---
*Phase: 19-project-data-model*
*Completed: 2026-03-20*
