---
phase: 03-scheduling-engine
plan: "04"
subsystem: api, testing
tags: [fastapi, pytest, asyncio, postgresql, gist, travel-time, dst, concurrent]

requires:
  - phase: 03-scheduling-engine plans 01-03
    provides: SchedulingService, SchedulingRepository, travel time cache, ORM models, migrations

provides:
  - REST API router with 13 scheduling endpoints registered in main.py
  - 47-test suite: availability (unit + integration), concurrent booking GIST verification, multi-day semantics, travel time cache

affects: [phase-05-calendar-ui, phase-07-notifications]

tech-stack:
  added: []
  patterns:
    - Plain APIRouter (not CRUDRouter) for custom domain endpoints
    - Exception-to-HTTP mapping: BookingConflictError->409, OutsideWorkingHoursError->422, BookingTooShortError->422
    - asyncio.gather with separate AsyncClient instances for race condition testing (each gets its own DB session)
    - pytest.mark.slow for 50-client load tests
    - SET LOCAL f-string interpolation for RLS context in direct DB inserts (PostgreSQL limitation — no bind params)
    - asyncpg requires Python type objects (datetime/date/time), never strings
    - DST-aware UTC time construction: March 9, 2026 is PDT (UTC-7) not PST (UTC-8) after spring-forward

key-files:
  created:
    - backend/app/features/scheduling/router.py
    - backend/tests/scheduling/__init__.py
    - backend/tests/scheduling/conftest.py
    - backend/tests/scheduling/test_availability.py
    - backend/tests/scheduling/test_booking_conflicts.py
    - backend/tests/scheduling/test_multiday.py
    - backend/tests/scheduling/test_travel_time.py
  modified:
    - backend/app/main.py
    - backend/pyproject.toml

key-decisions:
  - "Plain APIRouter used for scheduling (not CRUDRouter) — scheduling endpoints are custom domain operations, not CRUD"
  - "asyncio.gather with separate AsyncClient instances for concurrent race tests — each client gets its own DB session via ASGI transport"
  - "pytest.mark.slow tag on 50-client load test — CI can filter with -m 'not slow' for fast runs"
  - "DST awareness: March 9, 2026 = PDT (UTC-7) not PST (UTC-8) — spring-forward occurs March 8, affects all UTC working hours"
  - "Working hours in test fixtures explicitly scoped to single blocks to avoid lunch-break boundary errors"

patterns-established:
  - "Exception mapping pattern: catch domain errors at router layer, translate to HTTP status codes"
  - "Concurrent test pattern: asyncio.gather + separate AsyncClient instances = separate DB sessions = real race conditions"
  - "RLS test pattern: SET LOCAL f-string (not bind params) + Python type objects (not strings) for asyncpg"

requirements-completed: [SCHED-04, SCHED-05, SCHED-06, SCHED-07]

duration: 45min
completed: "2026-03-07"
---

# Phase 03 Plan 04: REST API Router and Test Suite Summary

**13-endpoint scheduling REST API and 47-test suite proving GIST concurrency safety, DST correctness, multi-day all-or-nothing semantics, and travel time cache with bidirectional key normalization**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-03-07T01:40:00Z
- **Completed:** 2026-03-07T02:27:47Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- REST API router with 13 scheduling endpoints delegating to SchedulingService, registered in main.py
- 50-client concurrent load test (asyncio.gather) proves GIST + SELECT FOR UPDATE holds under sustained pressure — exactly 1 success, 49 conflicts, 0 server errors
- DST boundary test verifies spring-forward correctness: booking on 2026-03-08 stores correct 2-hour UTC range despite naive 3-hour local-time arithmetic
- Travel time cache test suite: bidirectional key normalization, TTL fallback, ORS coordinate order (GeoJSON lng,lat), safety margin pure functions

## Task Commits

1. **Task 1: REST API router for scheduling endpoints** - `279c64e` (feat)
2. **Task 2: Comprehensive test suite** - `81c3b4d` (test)

## Files Created/Modified

- `backend/app/features/scheduling/router.py` - 13 scheduling endpoints (availability, bookings, conflicts, suggest-dates, weekly schedule, date overrides)
- `backend/app/main.py` - Added scheduling router registration
- `backend/pyproject.toml` - Added pytest.mark.slow marker
- `backend/tests/scheduling/__init__.py` - Empty package init
- `backend/tests/scheduling/conftest.py` - Scheduling fixtures: tenant setup, contractor with weekly schedule, job sites, booking factory, async HTTP clients
- `backend/tests/scheduling/test_availability.py` - 13 tests: 7 unit (TestFreeWindowComputation with mocked DB) + 6 integration including DST boundary
- `backend/tests/scheduling/test_booking_conflicts.py` - 11 tests: GIST conflict, adjacent bookings, soft-delete, working hours validation, 2-client race, 50-client load
- `backend/tests/scheduling/test_multiday.py` - 7 tests: all-or-nothing, non-consecutive, per-day times, reschedule, suggest-dates consecutive/fallback
- `backend/tests/scheduling/test_travel_time.py` - 16 tests: 9 unit (key normalization, safety margin, ORS coordinate order) + 7 integration (cache TTL, bidirectional, buffer availability)

## Decisions Made

- Plain APIRouter for scheduling (not CRUDRouter) — the scheduling domain has no standard CRUD operations; all endpoints are custom queries or actions
- asyncio.gather with separate AsyncClient instances for race tests — reusing one client shares a session and doesn't simulate real concurrency
- pytest.mark.slow on 50-client test — takes ~4-5 seconds, acceptable to deselect in CI fast paths
- DST handling in tests: spring-forward March 8, 2026 means all March 9 working hours must be computed with UTC-7 (PDT) not UTC-8 (PST)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] FastAPI 204 response_model=None**
- **Found during:** Task 1 (DELETE booking endpoint)
- **Issue:** FastAPI raises `AssertionError: Status code 204 must not have a response body` when DELETE endpoint has an implicit response model
- **Fix:** Added `response_model=None` parameter to the DELETE endpoint decorator
- **Files modified:** backend/app/features/scheduling/router.py
- **Verification:** DELETE endpoint returns 204 without assertion error
- **Committed in:** 279c64e (Task 1 commit)

**2. [Rule 1 - Bug] SET LOCAL bind parameter syntax error**
- **Found during:** Task 2 (conftest.py fixtures)
- **Issue:** `text("SET LOCAL app.current_company_id = :company_id")` raises `syntax error at or near "$1"` — PostgreSQL does not accept bind parameters in SET statements
- **Fix:** Changed to f-string interpolation: `text(f"SET LOCAL app.current_company_id = '{company_id}'")`
- **Files modified:** backend/tests/scheduling/conftest.py, all test files with direct DB inserts
- **Verification:** RLS context set correctly, no `InsufficientPrivilegeError`
- **Committed in:** 81c3b4d (Task 2 commit)

**3. [Rule 1 - Bug] asyncpg requires Python type objects not strings**
- **Found during:** Task 2 (conftest.py and test files)
- **Issue:** asyncpg raises type errors when `time()`, `date()`, or `datetime()` values are passed as `.isoformat()` strings — asyncpg needs native Python objects
- **Fix:** Removed `.isoformat()` calls throughout all direct DB inserts; passed `time()`, `date()`, `datetime()` objects directly
- **Files modified:** backend/tests/scheduling/conftest.py, test_availability.py, test_multiday.py, test_travel_time.py
- **Verification:** All direct DB inserts succeed without type errors
- **Committed in:** 81c3b4d (Task 2 commit)

**4. [Rule 1 - Bug] DST spring-forward UTC offset errors**
- **Found during:** Task 2 (multiple test files)
- **Issue:** March 9, 2026 is PDT (UTC-7), not PST (UTC-8). Spring-forward occurs March 8, 2026. Tests using UTC-8 arithmetic produced times outside working hours, causing 422 errors
- **Fix:** Recalculated all UTC times for March 9+ using UTC-7: working hours 07:00-12:00 PDT = 14:00-19:00 UTC; afternoon 13:00-16:00 PDT = 20:00-23:00 UTC
- **Files modified:** backend/tests/scheduling/test_booking_conflicts.py, test_multiday.py, test_travel_time.py
- **Verification:** All booking times within working hours, 201 responses returned
- **Committed in:** 81c3b4d (Task 2 commit)

**5. [Rule 1 - Bug] Travel cache key normalization mismatch**
- **Found during:** Task 2 (test_travel_time.py TTL fallback test)
- **Issue:** Direct DB insert used (49.283, -123.117) as lat1/lng1 but `_normalize_key` sorts coordinate pairs lexicographically so (49.282, -123.120) < (49.283, -123.117), making the normalized key start with the smaller pair
- **Fix:** Changed test insert to use normalized key order: lat1=49.282, lng1=-123.120 (the smaller pair) as lat1/lng1
- **Files modified:** backend/tests/scheduling/test_travel_time.py
- **Verification:** Cache lookup finds the pre-inserted entry, returns stale fallback value
- **Committed in:** 81c3b4d (Task 2 commit)

---

**Total deviations:** 5 auto-fixed (3 bugs, 2 blocking issues)
**Impact on plan:** All fixes necessary for correct operation. No scope creep. The DST fix establishes a critical pattern for all future scheduling tests.

## Issues Encountered

- Adjacent booking test initially failed (422) because 11am-1pm PDT spans the lunch break (12pm-1pm). Fixed by using 9am-10am then 10am-11am within the morning working block.
- Multi-day per-day test initially failed because Tuesday 10am-2pm spans morning and afternoon blocks. Fixed to use afternoon block (1pm-3:30pm PDT).
- All fixes are documented under Deviations above.

## User Setup Required

None — no external service configuration required. ORS API calls are mocked in all tests.

## Next Phase Readiness

- All 4 scheduling requirements (SCHED-04 through SCHED-07) verified and passing
- Phase 5 (Calendar UI) can now call all 13 scheduling endpoints
- Availability, booking, conflict check, multi-day, and suggest-dates endpoints are production-ready
- Travel time integration requires ORS API key in production environment (mocked in tests)

---
*Phase: 03-scheduling-engine*
*Completed: 2026-03-07*

## Self-Check: PASSED

- FOUND: backend/app/features/scheduling/router.py
- FOUND: backend/tests/scheduling/__init__.py
- FOUND: backend/tests/scheduling/conftest.py
- FOUND: backend/tests/scheduling/test_availability.py
- FOUND: backend/tests/scheduling/test_booking_conflicts.py
- FOUND: backend/tests/scheduling/test_multiday.py
- FOUND: backend/tests/scheduling/test_travel_time.py
- FOUND: .planning/phases/03-scheduling-engine/03-04-SUMMARY.md
- FOUND commit: 279c64e
- FOUND commit: 81c3b4d
