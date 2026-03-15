---
phase: 10-ui-backend-wiring-gap-closure
plan: 01
subsystem: ui
tags: [flutter, riverpod, fastapi, overdue-panel, quote-builder, travel-time, ors, dependency-injection]

# Dependency graph
requires:
  - phase: 08-business-operations
    provides: QuoteBuilderScreen, QuoteEntity, quoteForJobProvider, SchedulingService
  - phase: 05-calendar-and-dispatch-ui
    provides: OverduePanel widget, overdue_providers, ScheduleScreen
  - phase: 03-scheduling-engine
    provides: SchedulingService, CachedTravelTimeProvider, TravelTimeCacheService
provides:
  - OverduePanel rendered in ScheduleScreen (replacing placeholder Container)
  - Create Quote / View-Edit Quote navigation from JobDetailScreen
  - get_scheduling_service FastAPI dependency with CachedTravelTimeProvider injection
  - ors_api_key field on Settings for ORS API key configuration
  - E2E tests for SCHED-08, BIZ-01, BIZ-02, SCHED-06
affects:
  - schedule screen rendering (overdue jobs now visible to admin)
  - job detail screen (admin workflow: job -> quote)
  - scheduling endpoints (travel time now injected when ORS_API_KEY set)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "FastAPI dependency injection for service construction: get_scheduling_service provides SchedulingService with optional CachedTravelTimeProvider"
    - "OverduePanel self-manages visibility via AnimatedContainer(height: isVisible ? null : 0) — no external guard needed"
    - "Provider.autoDispose.family override in tests: noteCountProvider('id').overrideWith((ref) => 0)"

key-files:
  created:
    - mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart
    - backend/tests/integration/test_phase_10_e2e.py
  modified:
    - mobile/lib/features/schedule/presentation/screens/schedule_screen.dart
    - mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart
    - mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart
    - backend/app/core/config.py
    - backend/app/features/scheduling/router.py

key-decisions:
  - "get_scheduling_service dependency constructs per-request httpx.AsyncClient when ORS_API_KEY is set — documented as tech debt for lifespan-managed shared client"
  - "OverduePanel outer if (showOverduePanel) guard removed — widget manages its own animated visibility via AnimatedContainer height=0"
  - "Quote section hidden entirely for cancelled/invoiced jobs — not just the button but the whole card"
  - "9 of 10 SchedulingService(db) inline constructions replaced with Depends(get_scheduling_service); list_bookings/get_weekly_schedule/get_date_overrides keep db for direct ORM queries"

patterns-established:
  - "FastAPI: create a named dependency function (get_X_service) instead of inline service construction in each endpoint — enables travel provider injection without endpoint changes"
  - "Flutter: quote section uses hasQuote boolean to switch between FilledButton (create) and OutlinedButton (view/edit) — single card, two states"

requirements-completed: [SCHED-08, BIZ-01, BIZ-02, SCHED-06]

# Metrics
duration: 6min
completed: 2026-03-14
---

# Phase 10 Plan 01: UI Backend Wiring Gap Closure Summary

**Three surgical connection-tissue wires: OverduePanel into ScheduleScreen, Create/View-Quote navigation from JobDetailScreen, and CachedTravelTimeProvider injection via FastAPI dependency — all backed by 12 passing E2E/integration tests**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-14T17:32:15Z
- **Completed:** 2026-03-14T17:38:40Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- Replaced placeholder Container ("Overdue panel loading...") in ScheduleScreen with `const OverduePanel()`, satisfying SCHED-08
- Added Quote section card in `_DetailsTab` with Create Quote (FilledButton) and View / Edit Quote (OutlinedButton) for admin on non-terminal jobs, satisfying BIZ-01 and BIZ-02
- Added `ors_api_key: str | None = None` to Settings and `get_scheduling_service` FastAPI dependency that injects CachedTravelTimeProvider when ORS_API_KEY is configured, satisfying SCHED-06
- Replaced 9 inline `SchedulingService(db)` constructions in scheduling router with `Depends(get_scheduling_service)` for consistent travel provider wiring
- Fixed `quote_builder_screen.dart` to use `RouteNames.quotePreviewPath` instead of hardcoded path string (Rule 1 auto-fix)
- Created 8 Flutter E2E tests (all pass) and 4 backend integration tests (all pass)

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire OverduePanel, QuoteBuilder nav, and TravelTime injection** - `f41543b` (feat)
2. **Task 2: E2E and integration tests for all wiring fixes** - `75d1bd3` (test)

## Files Created/Modified

- `mobile/lib/features/schedule/presentation/screens/schedule_screen.dart` - Added overdue_panel.dart import; replaced placeholder Container with `const OverduePanel()`
- `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` - Added quote imports; added Quote section card with Create/View-Edit buttons for admin
- `mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart` - Fixed hardcoded preview path to use RouteNames.quotePreviewPath
- `backend/app/core/config.py` - Added `ors_api_key: str | None = None` to Settings
- `backend/app/features/scheduling/router.py` - Added get_scheduling_service dependency; replaced 9 inline SchedulingService constructions; added httpx/travel imports
- `mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart` - 8 E2E widget tests for SCHED-08, BIZ-01, BIZ-02
- `backend/tests/integration/test_phase_10_e2e.py` - 4 integration tests for SCHED-06

## Decisions Made

- `get_scheduling_service` uses a per-request `httpx.AsyncClient` when ORS_API_KEY is set — documented as tech debt for lifespan-managed shared client in future
- OverduePanel outer `if (showOverduePanel)` guard removed because OverduePanel manages its own visibility internally via `AnimatedContainer(height: isVisible ? null : 0)` — adding an outer guard is redundant and prevents the widget from animating on show
- Quote section hidden entirely (not just buttons) for cancelled/invoiced jobs — cleaner UX
- `list_bookings`, `get_weekly_schedule`, `get_date_overrides` keep their `db: AsyncSession` parameter because they execute direct ORM queries (not via SchedulingService)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed hardcoded route string in quote_builder_screen.dart**
- **Found during:** Task 1 (reviewing quote_builder_screen.dart for null-extra handling)
- **Issue:** `context.push('/jobs/${widget.jobId}/quote/preview')` was hardcoded instead of using `RouteNames.quotePreviewPath`
- **Fix:** Changed to `context.push(RouteNames.quotePreviewPath(widget.jobId))` for consistency with project routing pattern
- **Files modified:** mobile/lib/features/quotes/presentation/screens/quote_builder_screen.dart
- **Verification:** dart analyze passes, RouteNames.quotePreviewPath already defined
- **Committed in:** f41543b (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Inline fix required for routing correctness. No scope creep.

## Issues Encountered

- Flutter E2E tests required two fix iterations: (1) `JobEntity.jobStatus` → `status` (freezed uses String field), and (2) `showOverduePanelProvider` found in `calendar_providers.dart` not `overdue_providers.dart`. Both fixed in same iteration.

## User Setup Required

None — `ors_api_key` defaults to None. Set `ORS_API_KEY` in `.env` to enable travel time in scheduling.

## Next Phase Readiness

- All four v1.0 milestone gap requirements (SCHED-08, BIZ-01, BIZ-02, SCHED-06) are now satisfied
- Schedule screen shows real overdue jobs panel to admin
- Admin can create and view quotes directly from job detail
- Travel time computation activates automatically when ORS_API_KEY is configured in environment

---
*Phase: 10-ui-backend-wiring-gap-closure*
*Completed: 2026-03-14*

## Self-Check: PASSED

Files verified:
- mobile/lib/features/schedule/presentation/screens/schedule_screen.dart: FOUND
- mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart: FOUND
- backend/app/core/config.py: FOUND
- backend/app/features/scheduling/router.py: FOUND
- mobile/test/e2e/phase_10_ui_wiring_e2e_test.dart: FOUND
- backend/tests/integration/test_phase_10_e2e.py: FOUND

Commits verified:
- f41543b: FOUND (feat(10-01): wire OverduePanel, QuoteBuilder nav, and TravelTime injection)
- 75d1bd3: FOUND (test(10-01): add E2E and integration tests for UI wiring gap closure)
