---
phase: 15-scheduling-calendar
plan: 04
subsystem: api
tags: [fastapi, pydantic, typescript, react, tanstack-query, sqlalchemy]

# Dependency graph
requires:
  - phase: 15-scheduling-calendar
    provides: calendar booking events that display job + contractor data

provides:
  - client_name field on backend JobResponse (populated from eager-loaded Job.client)
  - client_name field on frontend Job TypeScript interface
  - clientName populated from job.client_name in use-bookings hook

affects: [15-scheduling-calendar, 16-quotes-invoices]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "sa_inspect(job).unloaded check before accessing lazy='raise' relationship to avoid
       MissingGreenlet errors after db.refresh() mutations"

key-files:
  created: []
  modified:
    - backend/app/features/jobs/schemas.py
    - backend/app/features/jobs/router.py
    - web/src/types/api.ts
    - web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts

key-decisions:
  - "Use sqlalchemy inspect().unloaded to guard lazy-raise relationship access — prevents MissingGreenlet after db.refresh() in create/update/transition endpoints while still populating client_name when relationship is already loaded (list_jobs, get_job paths)"
  - "client_name is additive-only — no existing fields renamed or removed (protects mobile Dart models from breaking)"

patterns-established:
  - "_job_with_client_name() helper pattern: serialize ORM to Pydantic then conditionally populate computed fields from eager-loaded relationships using sa_inspect guard"

requirements-completed: [SCHED-01, SCHED-02, SCHED-03]

# Metrics
duration: 12min
completed: 2026-03-17
---

# Phase 15 Plan 04: Scheduling Calendar — Client Name Gap Closure Summary

**client_name field added to JobResponse (backend) and Job interface (frontend), wired through use-bookings so calendar booking events display the assigned client's full name**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-17T07:25:00Z
- **Completed:** 2026-03-17T07:37:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `client_name: str | None = None` to `JobResponse` Pydantic schema
- Added `_job_with_client_name()` router helper that computes `first_name + last_name` from the eager-loaded `Job.client` relationship, with an `sa_inspect` guard to avoid accessing unloaded lazy-raise relationships after `db.refresh()` mutations
- Applied the helper to all seven `JobResponse`-returning router endpoints (list, search, mine, get, update, delay, transition)
- Added `client_name: string | null` to the `Job` TypeScript interface
- Replaced the hardcoded `clientName: ""` in `use-bookings.ts` with `job?.client_name ?? ""`
- Backend lint (`ruff check`) and frontend TypeScript (`tsc --noEmit`) both pass cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: Add client_name to backend JobResponse and wire serialization** - `bb831b3` (feat)
2. **Task 2: Add client_name to frontend Job type and wire into use-bookings** - `836706f` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified

- `backend/app/features/jobs/schemas.py` - Added `client_name: str | None = None` to JobResponse
- `backend/app/features/jobs/router.py` - Added `_job_with_client_name()` helper, applied to all job endpoints
- `web/src/types/api.ts` - Added `client_name: string | null` to Job interface
- `web/src/app/(dashboard)/schedule/_hooks/use-bookings.ts` - Wire `job?.client_name ?? ""` to clientName

## Decisions Made

- Used `sqlalchemy.inspect(job).unloaded` check before accessing `job.client` in the router helper. This prevents `MissingGreenlet` / `lazy="raise"` errors in endpoints that call `db.refresh()` after mutations (create, update, transition, delay) which expire all relationship attributes. The list and get endpoints go through `repository.get_by_id` / `repository.list_jobs` which already eager-load `Job.client`, so the guard is a no-op for those paths.
- Change is additive-only: no existing fields renamed or removed. Mobile Dart models receive an extra JSON key they ignore harmlessly.

## Deviations from Plan

None - plan executed exactly as written, plus one minor correctness addition (the `sa_inspect` guard) discovered during analysis of service-layer mutation paths.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 15 verification gap is now closed: calendar booking events will display `clientName` from the API when a client is assigned to the job
- `BookingEvent` component already handles empty `clientName` conditionally — no UI changes needed
- Phase 16 (Quotes/Invoices) can proceed; the `client_name` field is already available on JobResponse for any quote/invoice views that need it

---
*Phase: 15-scheduling-calendar*
*Completed: 2026-03-17*
