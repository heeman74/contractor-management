---
phase: 19-project-data-model
plan: 03
subsystem: api
tags: [fastapi, sqlalchemy, postgresql, rls, project-management, crud]

# Dependency graph
requires:
  - phase: 19-01
    provides: "SQLAlchemy ORM models (Project, TradeCatalog, TradeScope, Task) and Pydantic schemas"

provides:
  - "ProjectRepository with selectinload for trade_scopes and client"
  - "TradeCatalogRepository, TradeScopeRepository, TaskRepository with filtered queries"
  - "ProjectService with status transition history (draft->planning auto-advance)"
  - "TradeScopeService with auto-advance project status when first scope added"
  - "TaskService with auto-assigned sort_order"
  - "REST endpoints: /api/v1/projects, /api/v1/trade-catalog, /api/v1/trade-scopes, /api/v1/tasks, /api/v1/contractors"
  - "Contractor specialty matching endpoint (/contractors/?trade_catalog_id=) with has_specialty_match sort"
  - "21 integration tests covering PROJ-01, PROJ-02, and RLS isolation"

affects:
  - phase-20-project-ui
  - phase-21-ai-planning

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "TenantScopedRepository used for project entities requiring eager loading"
    - "Semi-automatic status transitions: TradeScopeService triggers ProjectService.update_status"
    - "Contractor specialty matching via LEFT JOIN + case() expression with has_specialty_match ordering"
    - "response_model=None on 204 DELETE endpoints (FastAPI pattern)"
    - "SET LOCAL app.current_company_id with f-string for UUID (parameterized syntax unsupported)"

key-files:
  created:
    - backend/app/features/projects/repository.py
    - backend/app/features/projects/service.py
    - backend/app/features/projects/router.py
    - backend/tests/test_phase_19_e2e.py
  modified:
    - backend/app/main.py

key-decisions:
  - "ProjectService.create accepts user_id kwarg (not positional) for status_history; routes pass current_user.user_id"
  - "DELETE endpoints use response_model=None (not response_class=Response) to satisfy FastAPI 204 assertion"
  - "SET LOCAL in tests uses f-string UUID formatting (PostgreSQL SET LOCAL does not support parameterized $1 syntax)"
  - "Contractor specialty matching uses case() label with .desc() ordering; non-matching users have has_specialty_match=False"
  - "Pre-existing failures test_client_crm::test_list_clients_with_search and test_role_endpoints::test_user_roles_are_tenant_scoped are out-of-scope; deferred"

patterns-established:
  - "Pattern: All delete endpoints in projects router use response_model=None + status_code=204"
  - "Pattern: TradeScopeService.create calls ProjectService internally for auto-advance — no circular imports"
  - "Pattern: Test DB seeding with RLS: SET LOCAL app.current_company_id = '{uuid}' then INSERT"

requirements-completed: [PROJ-01, PROJ-02]

# Metrics
duration: 45min
completed: 2026-03-20
---

# Phase 19 Plan 03: Project Data Model API Summary

**FastAPI REST layer for project management: repositories with eager loading, service with draft->planning auto-advance, and 21 passing integration tests covering PROJ-01, PROJ-02, and RLS isolation**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-20T12:00:00Z
- **Completed:** 2026-03-20T12:45:00Z
- **Tasks:** 2 of 2
- **Files modified:** 5 (4 created, 1 updated)

## Accomplishments
- Full CRUD REST API for all project entities: Project, TradeCatalog, TradeScope, Task
- Semi-automatic status transition: adding first TradeScope to a draft Project auto-advances it to 'planning' with a status_history audit entry
- Contractor specialty matching endpoint (`/api/v1/contractors/?trade_catalog_id=`) returns contractors with `has_specialty_match=True` sorted first
- 21 integration tests covering project CRUD, RLS tenant isolation, trade catalog, scope + task creation, auto-advance, and specialty matching

## Task Commits

Each task was committed atomically:

1. **Task 1: Repositories, service, and router** - `ea23755` (feat)
2. **Task 2: Integration tests** - `157c38d` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `backend/app/features/projects/repository.py` - ProjectRepository, TradeCatalogRepository, TradeScopeRepository, TaskRepository with selectinload eager loading
- `backend/app/features/projects/service.py` - ProjectService (status transitions), TradeScopeService (auto-advance), TradeCatalogService, TaskService (sort_order)
- `backend/app/features/projects/router.py` - REST router with 18 routes across /projects, /trade-catalog, /trade-scopes, /tasks, /contractors
- `backend/tests/test_phase_19_e2e.py` - 21 integration tests (all passing)
- `backend/app/main.py` - Added `include_router(projects_router, prefix="/api/v1")`

## Decisions Made
- `ProjectService.create` accepts `user_id` as a keyword argument (not part of schema) to record the creator in status_history
- DELETE endpoints use `response_model=None` rather than `response_class=Response` to pass FastAPI's 204 body assertion
- `SET LOCAL` in test DB seeding uses f-string UUID formatting since PostgreSQL does not support parameterized syntax for SET LOCAL
- Contractor specialty matching uses SQLAlchemy `case()` with `.desc()` ordering; has_specialty_match defaults to `False` for no-filter queries

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] FastAPI 204 assertion failure on DELETE endpoints**
- **Found during:** Task 1 (router creation)
- **Issue:** FastAPI asserts `is_body_allowed_for_status_code(204)` fails when `-> None` return type used without `response_model=None`
- **Fix:** Added `response_model=None` to all four DELETE endpoint decorators
- **Files modified:** backend/app/features/projects/router.py
- **Verification:** `uv run python -c "from app.features.projects.router import router"` succeeds with 18 routes
- **Committed in:** ea23755 (Task 1 commit)

**2. [Rule 1 - Bug] PostgreSQL SET LOCAL syntax error with parameterized queries**
- **Found during:** Task 2 (test_contractor_specialty_matching_with_role)
- **Issue:** `text("SET LOCAL app.current_company_id = :company_id")` raises `PostgresSyntaxError: syntax error at or near "$1"` — SET LOCAL does not support parameterized queries
- **Fix:** Used f-string with UUID value: `text(f"SET LOCAL app.current_company_id = '{company_id}'")`
- **Files modified:** backend/tests/test_phase_19_e2e.py
- **Verification:** All 21 tests pass
- **Committed in:** 157c38d (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs)
**Impact on plan:** Both auto-fixes required for correctness. No scope creep.

## Issues Encountered
- Two pre-existing test failures unrelated to Phase 19: `test_client_crm::test_list_clients_with_search` (Pydantic ValidationError in jobs router) and `test_role_endpoints::test_user_roles_are_tenant_scoped`. Both documented as out-of-scope and logged to deferred items.

## Next Phase Readiness
- `/api/v1/projects`, `/api/v1/trade-catalog`, `/api/v1/trade-scopes`, `/api/v1/tasks`, `/api/v1/contractors` endpoints are all functional and tested
- Phase 20 (project UI) can consume these endpoints directly
- Phase 21 (AI planning) has project entity IDs and status history available for context

## Self-Check: PASSED

- backend/app/features/projects/repository.py: FOUND
- backend/app/features/projects/service.py: FOUND
- backend/app/features/projects/router.py: FOUND
- backend/tests/test_phase_19_e2e.py: FOUND
- git log ea23755: FOUND (feat: repository, service, router)
- git log 157c38d: FOUND (feat: 21 integration tests)

---
*Phase: 19-project-data-model*
*Completed: 2026-03-20*
