---
phase: 04-job-lifecycle
plan: "02"
subsystem: api

tags: [fastapi, sqlalchemy, postgresql, full-text-search, state-machine, optimistic-locking]

# Dependency graph
requires:
  - phase: 04-job-lifecycle-01
    provides: Job ORM model, schemas (JobCreate, JobUpdate, JobStatus, JobTransitionRequest), migration 0008 (jobs table with tsvector trigger)
  - phase: 03-scheduling-engine
    provides: Booking model and SchedulingRepository for booking cancellation in cancel_job_bookings

provides:
  - JobRepository: CRUD, filtered list, FTS search, bulk booking soft-delete (cancel_job_bookings)
  - JobService: state machine (ALLOWED_TRANSITIONS, is_backward), transition_status with optimistic locking, create_job, update_job, soft_delete_job, search/list delegation
  - InvalidTransitionError exception with from_status, to_status, role attributes
  - ALLOWED_TRANSITIONS dict and BACKWARD_TRANSITIONS set exported for router and test use

affects: [04-03-CRM-repository-service, 04-04-API-router, 04-05-Flutter-models, testing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "State machine as module-level dict: ALLOWED_TRANSITIONS[(status, role)] -> frozenset[str]"
    - "Optimistic locking via version field: 409 Conflict on version mismatch"
    - "Backward transition guard: BACKWARD_TRANSITIONS set + is_backward() helper"
    - "List replacement for JSONB mutation: job.status_history = [*job.status_history, entry] (not .append())"
    - "Capture original_status before mutation for post-transition logic"
    - "Lazy Booking import in _booking_model() to avoid circular import"
    - "FTS primary + ILIKE fallback merge in Python (dedup by id)"

key-files:
  created:
    - backend/app/features/jobs/repository.py
    - backend/app/features/jobs/service.py
  modified: []

key-decisions:
  - "cancel_job_bookings uses single bulk UPDATE statement (not a loop) to soft-delete bookings"
  - "Backward transition booking cancellation: original_status captured before job.status mutation to correctly detect backward direction after status assignment"
  - "Lazy Booking import in _booking_model() avoids circular imports at module load (scheduling <-> jobs)"
  - "FTS: plainto_tsquery primary + ILIKE fallback merged in Python (not SQL UNION) for simplicity"
  - "soft_delete_job sets deleted_at (admin removal, job disappears from queries) — distinct from transition_status(cancelled) which sets status only, job stays visible"

patterns-established:
  - "State machine: ALLOWED_TRANSITIONS[(current_status, role)] -> frozenset of allowed next statuses"
  - "Backward transitions require reason: BACKWARD_TRANSITIONS set checked before writing"
  - "Contractor-only guard: role == contractor AND job.contractor_id != user_id -> 403"
  - "Version-checked transitions: expected_version != job.version -> 409 Conflict"

requirements-completed: [SCHED-01, SCHED-02]

# Metrics
duration: 5min
completed: 2026-03-09
---

# Phase 4 Plan 02: Job Lifecycle Service Layer Summary

**JobRepository and JobService implementing a 6-state role-based state machine with optimistic locking, bulk booking cancellation, and PostgreSQL full-text search**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-09T02:20:29Z
- **Completed:** 2026-03-09T02:25:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- JobRepository with get_by_id (selectinload for client/contractor/bookings), list_jobs with 5 optional filters, search_jobs with FTS + ILIKE fallback, cancel_job_bookings via single bulk UPDATE, and per-role list methods
- JobService with complete state machine: 18 (status, role) combinations across admin/contractor/client, version-checked transitions (409 on mismatch), backward-requires-reason enforcement, contractor-own-jobs-only guard, and bulk booking soft-delete on cancellation/backward transitions
- Fixed logic bug: original_status captured before `job.status = new_status` mutation so the backward detection after status assignment uses correct pre-transition value

## Task Commits

Each task was committed atomically:

1. **Task 1: JobRepository -- CRUD, search, and booking operations** - `0a494fc` (feat)
2. **Task 2: JobService -- state machine, CRUD, and scheduling integration** - `b70d657` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `backend/app/features/jobs/repository.py` - JobRepository with 6 methods: get_by_id, list_jobs, search_jobs, cancel_job_bookings, get_jobs_for_client, get_jobs_for_contractor
- `backend/app/features/jobs/service.py` - JobService with state machine constants (ALLOWED_TRANSITIONS, BACKWARD_TRANSITIONS, is_backward), InvalidTransitionError, and 8 service methods

## Decisions Made

- **Lazy Booking import:** `_booking_model()` method imports Booking lazily to avoid circular imports between jobs and scheduling modules at load time
- **FTS merge in Python:** Full-text search results (plainto_tsquery) and ILIKE fallback merged in Python via seen_ids set rather than SQL UNION, keeping query logic readable
- **original_status capture:** Saved `original_status = job.status` before mutating `job.status = new_status` — required for correct backward transition detection in booking cancellation logic

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed backward transition detection using stale post-mutation status**
- **Found during:** Task 2 (transition_status implementation)
- **Issue:** Line `if new_status == JobStatus.cancelled or is_backward(job.status, new_status)` called is_backward AFTER `job.status = new_status`, so `job.status` was already the new status — `is_backward(new_status, new_status)` always returns False, silently skipping booking cancellation on backward transitions
- **Fix:** Added `original_status = job.status` before the history append and mutation; used `is_backward(original_status, new_status)` in the cancellation check
- **Files modified:** backend/app/features/jobs/service.py
- **Verification:** is_backward('scheduled', 'quote') returns True as expected; original_status correctly refers to pre-transition value
- **Committed in:** b70d657 (Task 2 commit)

**2. [Rule 1 - Bug] Removed unreachable entry from BACKWARD_TRANSITIONS**
- **Found during:** Task 2 verification
- **Issue:** BACKWARD_TRANSITIONS contained `(cancelled, quote)` with comment "unreachable — cancelled is terminal"; confused is_backward semantics and showed in output
- **Fix:** Removed the dead entry; cancelled's unreachability is enforced exclusively by ALLOWED_TRANSITIONS having empty frozenset for all (cancelled, role) pairs
- **Files modified:** backend/app/features/jobs/service.py
- **Verification:** State machine output shows no spurious backward pairs
- **Committed in:** b70d657 (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (2 bugs in Task 2)
**Impact on plan:** Both fixes required for correct booking slot freeing on backward transitions. No scope creep.

## Issues Encountered

- `AsyncSession` import was unused (ruff F401) — removed. The base class constructor handles session injection.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- JobRepository and JobService are ready for the API router (Plan 04) to consume via FastAPI dependency injection
- ALLOWED_TRANSITIONS and InvalidTransitionError exported for test assertions in Plan 05
- SchedulingService integration (calling book_slot on transition to 'scheduled') deliberately deferred to API layer (Plan 04) to avoid circular dependency

---
*Phase: 04-job-lifecycle*
*Completed: 2026-03-09*
