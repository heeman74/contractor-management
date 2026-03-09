---
phase: 04-job-lifecycle
plan: "04"
subsystem: api
tags: [fastapi, sqlalchemy, jinja2, aiofiles, multipart, delta-sync, job-lifecycle, scheduling]

# Dependency graph
requires:
  - phase: 04-job-lifecycle
    provides: "JobService, CrmService, RequestService, RatingService, SchedulingService from plans 02-03"

provides:
  - "Complete REST API surface for job lifecycle domain (23 endpoints)"
  - "PATCH /jobs/{job_id}/transition wires SchedulingService for booking creation on scheduling"
  - "Public Jinja2 web form at GET/POST /jobs/request/{company_id} for anonymous client submissions"
  - "Delta sync endpoint extended with jobs, client_profiles, job_requests"
  - "Photo upload with aiofiles (max 5, JPEG/PNG/HEIC validation)"

affects:
  - "Phase 05: Calendar UI depends on job API endpoints and sync"
  - "Phase 07: Mobile integration consumes these REST endpoints"

# Tech tracking
tech-stack:
  added:
    - "aiofiles==24.1.0 — async file writes for photo uploads"
    - "Jinja2Templates — already in fastapi[standard], new usage for web form"
  patterns:
    - "isort: split comment to enforce import ordering when side-effect imports must precede configure_mappers()"
    - "scheduling.models side-effect import in router to pre-register Booking before CrmRepository triggers configure_mappers()"
    - "response_model=None on all HTTP 204 DELETE routes (FastAPI assertion requirement)"

key-files:
  created:
    - "backend/app/features/jobs/router.py — 23-route APIRouter for full job lifecycle domain"
    - "backend/app/features/jobs/templates/job_request.html — responsive Jinja2 web form"
  modified:
    - "backend/app/main.py — registered jobs_router, mounted /uploads StaticFiles"
    - "backend/requirements.txt — added aiofiles==24.1.0"
    - "backend/app/features/sync/service.py — added get_jobs_since, get_client_profiles_since, get_job_requests_since"
    - "backend/app/features/sync/schemas.py — extended SyncResponse with jobs, client_profiles, job_requests"
    - "backend/app/features/sync/router.py — delta_sync handler calls new service methods"

key-decisions:
  - "scheduling.models side-effect import must precede CrmService import in router — crm_repository.py triggers configure_mappers() via joinedload(ClientProfile.user) at class definition time, before Booking is in the mapper registry"
  - "isort: split comment used to preserve mandatory import ordering despite isort reordering"
  - "response_model=None required on all status_code=204 DELETE routes — FastAPI 0.115 raises AssertionError otherwise"
  - "Booking creation on transition-to-scheduled: single-day (<=480 min) uses book_slot with timedelta math; multi-day (>480 min) builds DayBlock list from job's scheduled_completion_date"
  - "Sync response new fields default to empty list for backwards compatibility with existing mobile clients"

patterns-established:
  - "Jinja2Templates directory: Path(__file__).parent / 'templates' pattern (per CONTEXT.md Pitfall 6)"
  - "Photo upload validation: check content_type in _ALLOWED_PHOTO_TYPES set, max _MAX_PHOTOS count before service call"
  - "Sync service methods use lazy imports (from app.features.jobs.models import X) to avoid module-load circular imports"
  - "Router delegates all business logic to service layer; only exception mapping and SchedulingService orchestration at router level"

requirements-completed: [SCHED-01, SCHED-02, CLNT-01, CLNT-04]

# Metrics
duration: 11min
completed: 2026-03-08
---

# Phase 4 Plan 04: Job Lifecycle REST Router Summary

**Complete FastAPI REST layer for job lifecycle domain: 23 endpoints covering CRUD, state transitions (wired to SchedulingService for booking creation), CRM, job requests (web form + in-app), ratings, plus delta sync extended with Phase 4 entities.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-03-08T01:57:11Z
- **Completed:** 2026-03-08T02:08:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Created `backend/app/features/jobs/router.py` with 23 routes covering job CRUD, transitions, contractor view, CRM, job requests (public web form + in-app JSON), and ratings
- PATCH `/jobs/{job_id}/transition` wires `SchedulingService.book_slot` or `book_multiday_job` when transitioning to 'scheduled', fulfilling the locked CONTEXT.md decision that "Bookings are created when scheduling"
- Extended delta sync endpoint to include `jobs`, `client_profiles`, and `job_requests` in the `SyncResponse` — same cursor high-water mark applies to all entity types

## Task Commits

1. **Task 1: Job lifecycle REST router with all endpoints** - `70e2b40` (feat)
2. **Task 2: Extend sync endpoint for job lifecycle entities** - `3e3a858` (feat)

**Plan metadata:** see final docs commit

## Files Created/Modified

- `backend/app/features/jobs/router.py` — 23-route APIRouter with full job domain endpoints
- `backend/app/features/jobs/templates/job_request.html` — responsive Jinja2 form with mobile-friendly CSS
- `backend/app/main.py` — registered `jobs_router` and mounted `/uploads` StaticFiles
- `backend/requirements.txt` — added `aiofiles==24.1.0`
- `backend/app/features/sync/service.py` — added 3 delta query methods for Phase 4 entities
- `backend/app/features/sync/schemas.py` — extended `SyncResponse` with jobs/client_profiles/job_requests fields
- `backend/app/features/sync/router.py` — updated `delta_sync` to call new service methods

## Decisions Made

- **scheduling.models pre-import:** CrmRepository imports `joinedload(ClientProfile.user)` at class definition time, which triggers `configure_mappers()`. The Job model's `bookings` relationship uses a string `'foreign(Booking.job_id) == Job.id'` that requires Booking to be in the mapper registry. Solution: import `app.features.scheduling.models` before `CrmService` using `# isort: split` to preserve order against isort reordering.
- **204 response_model=None:** FastAPI 0.115 raises `AssertionError: Status code 204 must not have a response body` unless `response_model=None` is explicitly set on DELETE routes.
- **Booking derivation from job data:** When transitioning to 'scheduled', start time is derived from `job.scheduled_completion_date` at 08:00 UTC (or tomorrow if not set). Duration drives single-day vs multi-day decision at 480-minute threshold.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed FastAPI 204 assertion error on DELETE routes**
- **Found during:** Task 1 (verification of router import)
- **Issue:** `@router.delete(status_code=204)` without `response_model=None` raises `AssertionError` in FastAPI 0.115
- **Fix:** Added `response_model=None` to all DELETE endpoints (`/jobs/{job_id}` and `/clients/properties/{property_id}`)
- **Files modified:** `backend/app/features/jobs/router.py`
- **Verification:** `uv run python -c "from app.features.jobs.router import router"` succeeds
- **Committed in:** 70e2b40

**2. [Rule 3 - Blocking] Fixed SQLAlchemy configure_mappers() race on import**
- **Found during:** Task 1 (router import verification)
- **Issue:** Importing CrmService triggers `joinedload(ClientProfile.user)` at module load, which calls `configure_mappers()` before Booking is in the registry. The Job.bookings relationship uses `foreign(Booking.job_id)` — a string resolved during configure_mappers — causing `InvalidRequestError: name 'Booking' is not defined`.
- **Fix:** Added `import app.features.scheduling.models` with `# isort: split` before CrmService import to pre-register Booking in the mapper registry.
- **Files modified:** `backend/app/features/jobs/router.py`, `backend/app/features/sync/router.py`
- **Verification:** `uv run python -c "from app.features.jobs.router import router; print(f'{len(router.routes)} routes registered')"` prints `23 routes registered`
- **Committed in:** 70e2b40

**3. [Rule 1 - Bug] Fixed ruff linting issues (5 auto-fixed + 5 manual)**
- **Found during:** Task 1 (ruff check)
- **Issue:** Import ordering (I001), unused imports (F401), unused variable (F841), and SIM105 (contextlib.suppress pattern) violations
- **Fix:** `ruff --fix` resolved 5; manually removed unused `end_time` variable and replaced try/except/pass with `contextlib.suppress`
- **Files modified:** `backend/app/features/jobs/router.py`
- **Committed in:** 70e2b40

---

**Total deviations:** 3 auto-fixed (1 bug, 1 blocking, 1 bug/linting)
**Impact on plan:** All fixes necessary for correctness and importability. No scope creep.

## Issues Encountered

- Pre-existing SAWarnings from `crm_repository.py` about overlapping `ClientProperty.client` and `ClientProperty.client_profile` relationships — these are not introduced by this plan and are out of scope per deviation rules. Logged to deferred-items.md.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Complete REST API surface available for Phase 5 (Calendar UI) and Phase 7 (Mobile integration)
- All 118 existing backend tests pass after changes
- Sync endpoint delivers Phase 4 entities to mobile clients with backwards-compatible empty defaults

---
*Phase: 04-job-lifecycle*
*Completed: 2026-03-08*
