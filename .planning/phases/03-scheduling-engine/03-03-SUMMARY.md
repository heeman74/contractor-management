---
phase: 03-scheduling-engine
plan: "03"
subsystem: backend-scheduling-engine-core
tags: [postgresql, sqlalchemy, tstzrange, gist, select-for-update, interval-subtraction, availability, booking, zoneinfo]

requires:
  - phase: 03-01
    provides: Booking, ContractorWeeklySchedule, ContractorDateOverride, ContractorScheduleLock ORM models and PostgreSQL scheduling tables
  - phase: 03-02
    provides: TravelTimeProvider ABC, CachedTravelTimeProvider, apply_safety_margin() for travel buffer computation

provides:
  - SchedulingRepository — booking queries with TSTZRANGE && overlap, SELECT FOR UPDATE lock acquisition, schedule/override retrieval, company config JSONB parsing
  - SchedulingService — full scheduling engine: availability computation, conflict detection, book_slot, book_multiday_job, suggest_dates, reschedule_booking, schedule CRUD
  - SchedulingConflictError, OutsideWorkingHoursError, BookingTooShortError — typed exception hierarchy for 409/422 error handling
  - BookingConflictError — GIST constraint violation wrapper in repository layer

affects: [03-04-scheduling-api, scheduling-endpoints, calendar-ui, Phase-5]

tech-stack:
  added: []
  patterns:
    - Interval subtraction algorithm: working_blocks - (bookings + travel_buffers) = free_windows with buffer expansion and merge sweep
    - Two-layer booking protection: SELECT FOR UPDATE (application) + GIST EXCLUDE (database)
    - Two-level working hours override: ContractorDateOverride > ContractorWeeklySchedule > SchedulingConfig.default_working_hours
    - DST-safe timezone conversion via zoneinfo: datetime(..., tzinfo=contractor_tz).astimezone(UTC) never breaks on DST transitions
    - All-or-nothing multi-day booking: single contractor lock covers all days; any conflict rejects entire batch
    - Consecutive-first date suggestion: suggest_dates() fills consecutive slots before offering non-consecutive combinations

key-files:
  created:
    - backend/app/features/scheduling/repository.py
    - backend/app/features/scheduling/service.py
  modified: []

key-decisions:
  - "SchedulingRepository contains all DB operations including schedule CRUD helpers (delete_weekly_schedule_for_day, etc.) — keeps SchedulingService free of raw SQL/ORM queries"
  - "Optional travel_provider in SchedulingService constructor: None skips travel computation, allowing pure-logic unit testing without external API mocking"
  - "reschedule_booking uses soft-delete + rebook + rollback pattern: soft-deletes old booking first so conflict check sees a clean slate, restores on failure"
  - "_compute_free_windows tracks reason_before on FreeWindow for UI calendar rendering — dispatchers can see why gaps exist"
  - "suggest_dates builds eligible dates list then searches for consecutive runs, falling back to itertools.combinations for non-consecutive — avoids O(n^k) upfront"

patterns-established:
  - "Repository helpers pattern: SchedulingRepository exposes fine-grained delete/create methods used by service layer instead of inline ORM operations in service"
  - "Blocked interval tuple format: (start, end, reason_str) flows through _get_travel_buffers -> _compute_free_windows -> BlockedInterval schema without type conversion overhead"
  - "Lock-then-check booking pattern: acquire_contractor_lock() THEN check_conflicts() inside the lock ensures no TOCTOU race between conflict check and insert"

requirements-completed: [SCHED-04, SCHED-05, SCHED-06, SCHED-07]

duration: 8min
completed: 2026-03-07
---

# Phase 3 Plan 3: Scheduling Engine Core Summary

**SchedulingRepository + SchedulingService implementing interval subtraction availability, SELECT FOR UPDATE + GIST two-layer booking protection, all-or-nothing multi-day booking, and consecutive-first date suggestion.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-07T01:55:53Z
- **Completed:** 2026-03-07T02:03:06Z
- **Tasks:** 2
- **Files modified:** 2 created, 0 modified

## Accomplishments

- SchedulingRepository with 12 methods: contractor lock acquisition (SELECT FOR UPDATE with auto-create), TSTZRANGE && overlap booking queries, weekly schedule/date override retrieval, company JSONB config parsing, GIST violation -> BookingConflictError conversion, and schedule CRUD helpers
- SchedulingService with full availability engine: interval subtraction algorithm (expand buffers -> merge overlapping -> subtract from working blocks), two-level working hours override, DST-safe UTC conversion via zoneinfo
- book_slot() and book_multiday_job() with lock + pre-check + GIST two-layer protection; multiday is all-or-nothing with batch conflict detection
- suggest_dates() scanning eligible dates in a 30-day window, returning consecutive combinations first and non-consecutive as fallback
- Custom exception hierarchy: SchedulingConflictError (with ConflictDetail list), OutsideWorkingHoursError, BookingTooShortError

## Task Commits

Each task was committed atomically:

1. **Task 1: SchedulingRepository** - `7a67494` (feat)
2. **Task 2: SchedulingService** - `aa15d0f` (feat)

## Files Created/Modified

- `backend/app/features/scheduling/repository.py` — SchedulingRepository (385 lines): booking queries, lock acquisition, schedule resolution, CRUD helpers
- `backend/app/features/scheduling/service.py` — SchedulingService (1141 lines): availability computation, booking, multi-day, suggest_dates, schedule management

## Decisions Made

- Optional `travel_provider: TravelTimeProvider | None` in SchedulingService constructor — when None, uses `config.default_travel_time_minutes` as fallback, enabling pure-logic unit testing without ORS mocking
- `reschedule_booking` uses soft-delete + rebook + rollback: soft-deletes existing booking first so the conflict check sees a clean slot, restores the original on any failure
- `_compute_free_windows` returns `reason_before` on FreeWindow objects — UI calendar rendering can explain why each free slot starts where it does (e.g., "outside_working_hours" at day start, "existing_job" after a booking)
- `suggest_dates` builds eligible dates list then finds consecutive runs in O(n), falling back to `itertools.combinations` only for non-consecutive — avoids O(n^k) combinatorial explosion

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Ruff F401: unused imports in repository.py**
- **Found during:** Task 1 verification (ruff check)
- **Issue:** `Range` from `sqlalchemy.dialects.postgresql` and `text` from `sqlalchemy` were imported at top level but not used (TSTZRANGE overlap uses `func.tstzrange()` instead)
- **Fix:** Removed both unused imports via `ruff check --fix`
- **Files modified:** `backend/app/features/scheduling/repository.py`
- **Verification:** `ruff check` reports "All checks passed!"
- **Committed in:** `7a67494` (part of Task 1 commit)

**2. [Rule 1 - Bug] Ruff I001: unsorted imports in delete helper methods in repository.py**
- **Found during:** Task 1 verification (ruff check)
- **Issue:** Local imports inside `delete_weekly_schedule_for_day` and `delete_date_overrides_for_date` were not sorted (datetime before sqlalchemy)
- **Fix:** Auto-fixed by `ruff check --fix`
- **Files modified:** `backend/app/features/scheduling/repository.py`
- **Committed in:** `7a67494` (part of Task 1 commit)

**3. [Rule 1 - Bug] Multiple ruff violations in service.py (F401 unused imports, I001 import sorting, B007 unused loop vars, B905 zip without strict, F841 unused variables)**
- **Found during:** Task 2 verification (ruff check)
- **Issue:** Initial draft had `DateOverrideCreate`, `WeeklyScheduleCreate` imported but not needed as parameters; `get_current_tenant_id` import became unused after removing dead `company_id` assignment in `_get_travel_buffers`; local imports inside methods needed moving to top level; `found_consecutive`/`max_to_add` unused; loop vars `i`/`day_block` unused; `zip()` without `strict=`
- **Fix:** Moved `Range`, `sa_select`, `JobSite`, `DayBlock` to top-level imports; removed unused imports; renamed unused loop vars to `_day_block`; added `strict=True` to all `zip()` calls; removed dead variable assignments; ran `ruff check --fix` + `ruff format`
- **Files modified:** `backend/app/features/scheduling/service.py`
- **Verification:** `ruff check app/features/scheduling/` reports "All checks passed!"
- **Committed in:** `aa15d0f` (part of Task 2 commit)

---

**Total deviations:** 3 auto-fixed (3 Rule 1 — lint/bug fixes)
**Impact on plan:** All auto-fixes are ruff compliance issues from initial draft. No logic changes or scope creep.

## Issues Encountered

None — all planned functionality implemented on first pass. Ruff violations were mechanical cleanup items from the initial draft.

## User Setup Required

None - no external service configuration required. Travel provider is optional and wired in by callers via dependency injection.

## Next Phase Readiness

- SchedulingRepository and SchedulingService are importable and ruff-clean — Plan 03-04 (API endpoints) can wire these directly
- All scheduling business logic is encapsulated in the service layer — API layer will be thin (schema validation + service delegation)
- Custom exceptions (SchedulingConflictError, OutsideWorkingHoursError, BookingTooShortError) are ready for HTTP exception handlers in the router layer

---
*Phase: 03-scheduling-engine*
*Completed: 2026-03-07*
