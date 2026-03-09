---
phase: 04-job-lifecycle
plan: "08"
subsystem: testing
tags: [pytest, asyncio, integration-tests, unit-tests, state-machine, seed-data, rls, fastapi]

# Dependency graph
requires:
  - phase: 04-job-lifecycle/04-04
    provides: Job lifecycle REST router with all endpoints
  - phase: 04-job-lifecycle/04-06
    provides: RequestService, web form handler, job request endpoints
  - phase: 04-job-lifecycle/04-07
    provides: CRM service, CrmRepository, RatingService

provides:
  - 8 state machine unit tests (no DB, direct import of ALLOWED_TRANSITIONS)
  - 15 job lifecycle integration tests via ASGI HTTP transport
  - 11 CRM integration tests (profile CRUD, properties, ratings)
  - 10 job request integration tests (in-app, web form, review actions, E2E)
  - Updated seed data script with Phase 4 full demo pipeline

affects: [05-mobile-app, future-phases-using-job-data]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Unit tests import ALLOWED_TRANSITIONS/is_backward directly from service.py — no fixtures needed"
    - "Web form RLS fix: set_current_tenant_id(company_id) must be called before service call for anonymous user creation"
    - "Route ordering in FastAPI: specific literal paths before {param} catch-all routes"
    - "Seed idempotency: SET RLS context BEFORE existence check so SELECT COUNT sees RLS-protected rows"
    - "asyncpg SET LOCAL: use string formatting, not parameterized queries (asyncpg does not support parameterized SET commands)"

key-files:
  created:
    - backend/tests/unit/__init__.py
    - backend/tests/unit/test_state_machine.py
    - backend/tests/integration/test_job_lifecycle.py
    - backend/tests/integration/test_client_crm.py
    - backend/tests/integration/test_job_requests.py
  modified:
    - backend/scripts/seed_data.py
    - backend/app/features/jobs/crm_repository.py
    - backend/app/features/jobs/crm_service.py
    - backend/app/features/jobs/router.py

key-decisions:
  - "Route ordering fix: all /jobs/requests* and /jobs/request/{company_id} routes must be declared BEFORE /jobs/{job_id} in router.py to prevent FastAPI from parsing 'requests' as a UUID path parameter"
  - "Web form RLS: submit_job_request_form calls set_current_tenant_id(company_id) before service to enable anonymous User creation under RLS"
  - "CrmRepository.soft_delete_property: new method added to query ClientProperty directly instead of using inherited soft_delete (which queries ClientProfile)"
  - "Seed idempotency: RLS context must be set before existence check queries, not just before INSERT operations"

patterns-established:
  - "State machine unit tests: test ALLOWED_TRANSITIONS directly without any fixtures or DB"
  - "Integration tests: create_job_site_direct helper uses raw SQL (text()) when no HTTP endpoint exists for a model"
  - "Contractor isolation test: create real users via POST /api/v1/users/ before assigning as contractor_id — FK constraint requires real user rows"

requirements-completed: [SCHED-01, SCHED-02, CLNT-01, CLNT-04]

# Metrics
duration: 120min
completed: 2026-03-09
---

# Phase 4 Plan 8: Tests and Seed Data Summary

**36 new tests (8 unit + 15 job lifecycle + 11 CRM + 10 request flow) with 4 auto-fixed bugs discovered during testing; Phase 4 seed data creates full demo pipeline with jobs at every lifecycle stage**

## Performance

- **Duration:** ~120 min (continued from previous context)
- **Started:** 2026-03-08T00:00:00Z (previous context)
- **Completed:** 2026-03-09T03:41:07Z
- **Tasks:** 2 of 2 completed
- **Files modified:** 8 files (5 created, 3 modified)

## Accomplishments

- 36 new tests covering all Phase 4 backend logic: state machine transitions, role enforcement, version checks, request-to-job conversion, CRM CRUD, ratings, and full E2E dual-flow pipeline
- 4 bugs discovered and auto-fixed during test implementation (route ordering conflict, CRM soft-delete wrong model, web form RLS, seed idempotency)
- Phase 4 seed data creates full demo pipeline: 8 jobs at every lifecycle stage, 4 job requests (2 pending/1 accepted/1 declined), client profile with saved property, 2 ratings

## Task Commits

Each task was committed atomically:

1. **Task 1: State machine unit tests and job lifecycle integration tests** - `d58976c` (test)
2. **Task 2: CRM tests, request flow tests, and seed data** - `b681a4c` + `039dc92` (test + chore)

**Plan metadata:** (this commit — docs: complete plan)

## Files Created/Modified

- `backend/tests/unit/__init__.py` - Python package marker for unit test directory
- `backend/tests/unit/test_state_machine.py` - 8 pure unit tests for state machine (no DB, no HTTP); tests ALLOWED_TRANSITIONS matrix, is_backward(), role enforcement, terminal state
- `backend/tests/integration/test_job_lifecycle.py` - 15 integration tests for job CRUD and lifecycle via HTTP: create, get, list, search, transitions (forward/backward/invalid), version mismatch (409), soft delete, contractor isolation, full lifecycle E2E
- `backend/tests/integration/test_client_crm.py` - 11 integration tests for CRM operations: profile CRUD, search, job history, saved properties (add/remove/default), ratings (create, pre-complete rejection, uniqueness, average calculation)
- `backend/tests/integration/test_job_requests.py` - 10 integration tests for job request flow: in-app submission, web form (anonymous + email), new client creation, existing client match, list pending, accept/decline/info-requested review actions, HTML render, dual-flow E2E
- `backend/scripts/seed_data.py` - Phase 4 additions: 2 job sites, client profile, saved property, 8 jobs at all lifecycle stages, 4 job requests, 2 ratings with denormalized average_rating
- `backend/app/features/jobs/crm_repository.py` - Added `soft_delete_property` method for direct ClientProperty soft-deletion (rule 1 bug fix)
- `backend/app/features/jobs/crm_service.py` - Updated `remove_property` to call `crm_repo.soft_delete_property` instead of inherited `soft_delete` (rule 1 bug fix)
- `backend/app/features/jobs/router.py` - Moved all /jobs/requests* routes before /jobs/{job_id}; added `set_current_tenant_id(company_id)` in web form handler (rule 1 + rule 2 bug fixes)

## Decisions Made

- Used direct import of `ALLOWED_TRANSITIONS` and `is_backward` for unit tests (no HTTP, no DB) — fastest feedback for pure logic
- CRM tests use `create_job_site_direct` helper with raw SQL since no HTTP endpoint exists for job_sites (established pattern from scheduling conftest)
- Seed data uses RLS-aware idempotency: SET LOCAL context before SELECT COUNT checks, not just before INSERTs

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] CrmService.remove_property always returned 404**
- **Found during:** Task 2 (test_client_crm.py — test_remove_saved_property)
- **Issue:** `CrmService.remove_property` called `self.crm_repo.soft_delete(property_id)` which uses the inherited method targeting `ClientProfile` (repository model type), not `ClientProperty`. So `db.get(ClientProfile, property_id)` with a `ClientProperty` UUID always returned None, causing 404.
- **Fix:** Added `CrmRepository.soft_delete_property` method that queries `ClientProperty` directly. Updated `CrmService.remove_property` to call it.
- **Files modified:** `backend/app/features/jobs/crm_repository.py`, `backend/app/features/jobs/crm_service.py`
- **Verification:** `test_remove_saved_property` passes; `DELETE /clients/properties/{id}` returns 204 then 404 on repeat.
- **Committed in:** `b681a4c` (Task 2 commit)

**2. [Rule 1 - Bug] FastAPI route ordering conflict — /jobs/requests returned 422**
- **Found during:** Task 2 (test_job_requests.py — test_list_pending_requests, test_submit_request_in_app)
- **Issue:** `/jobs/requests`, `/jobs/requests/{request_id}`, and `/jobs/request/{company_id}` routes were declared AFTER `/jobs/{job_id}` in router.py. FastAPI processes routes in declaration order and matched "requests" as a UUID job_id path parameter, returning 422 Unprocessable Entity.
- **Fix:** Moved all request-related routes to be declared before `/jobs/{job_id}`. Added comment explaining the ordering requirement.
- **Files modified:** `backend/app/features/jobs/router.py`
- **Verification:** All 10 request flow tests pass; /jobs/requests returns list, not 422.
- **Committed in:** `b681a4c` (Task 2 commit)

**3. [Rule 2 - Missing Critical] Web form anonymous user creation violated RLS**
- **Found during:** Task 2 (test_job_requests.py — test_web_form_creates_new_client)
- **Issue:** Web form `POST /jobs/request/{company_id}` has no JWT auth. `TenantMiddleware` resets `_current_tenant_id = None`. When `submitted_email` triggers a new User INSERT in `RequestService`, the `after_begin` event does not set `app.current_company_id` (tenant is None), so the INSERT fails RLS with `InsufficientPrivilegeError`.
- **Fix:** Added `set_current_tenant_id(company_id)` call in `submit_job_request_form` before the service call, using the URL path parameter `company_id`.
- **Files modified:** `backend/app/features/jobs/router.py`
- **Verification:** `test_web_form_creates_new_client` and `test_web_form_matches_existing_client` pass; new User rows are created correctly under RLS.
- **Committed in:** `b681a4c` (Task 2 commit)

**4. [Rule 1 - Bug] Seed idempotency check failed to detect existing data under RLS**
- **Found during:** Task 2 (seed data — second run)
- **Issue:** `_phase4_data_exists` checks `SELECT COUNT(*) FROM jobs/client_profiles/job_sites WHERE company_id = :cid` but RLS hides rows when `app.current_company_id` is not set. The check always returned False (0 rows visible), causing re-insertion attempts that failed with UniqueViolationError on `client_profiles_user_id_key`.
- **Fix:** Moved `SET LOCAL app.current_company_id = '{ace.id}'` to occur BEFORE the `_phase4_data_exists` call, so RLS context is active during the existence check.
- **Files modified:** `backend/scripts/seed_data.py`
- **Verification:** Second `seed_data.py` run correctly skips Phase 4 data insertion when data already exists.
- **Committed in:** `039dc92` (seed data commit)

---

**Total deviations:** 4 auto-fixed (2 Rule 1 - Bug, 1 Rule 2 - Missing Critical, 1 Rule 1 - Bug in seed)
**Impact on plan:** All auto-fixes required for correctness/security. No scope creep. The router ordering and RLS fixes were previously unknown systemic bugs that would have silently failed without tests.

## Issues Encountered

- Test `test_contractor_sees_own_jobs_only` originally used random UUIDs for `contractor_id` causing FK constraint violation. Fixed by creating real users via the admin API before assigning as contractor. This is a required pattern when jobs reference user FK columns.
- asyncpg does not support parameterized `SET LOCAL` commands (`$1` placeholder causes PostgresSyntaxError). Must use string formatting: `SET LOCAL app.current_company_id = '{uuid}'`. This is safe because UUIDs are generated by PostgreSQL/auth, never from user input.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All Phase 4 backend logic is fully tested: state machine, role enforcement, version checks, CRM, request flow, ratings
- 162 total tests pass (including all prior phases)
- Seed data creates full demo pipeline ready for manual testing and frontend development
- Phase 5 (mobile app) can rely on all Phase 4 HTTP endpoints being correct and tested

## Self-Check: PASSED

All created files verified present on disk. All task commits verified in git history.

---
*Phase: 04-job-lifecycle*
*Completed: 2026-03-09*
