---
phase: 11-integration-polish
plan: 01
subsystem: schedule
tags: [drift, riverpod, flutter, sync, calendar, overdue-panel]

# Dependency graph
requires:
  - phase: 05-calendar-and-dispatch-ui
    provides: CalendarDayView, ContractorLane, TravelTimeBlock, BlockedInterval, JobSiteSyncHandler
  - phase: 09-sync-engine-gap-closure
    provides: JobSiteSyncHandler pull implementation, sync handler pattern
  - phase: 10-ui-backend-wiring-gap-closure
    provides: OverduePanel wired into ScheduleScreen
provides:
  - Correct latitude/longitude field mapping in JobSiteSyncHandler (INT-01)
  - travel_buffer BlockedInterval generation in CalendarDayView (INT-02)
  - Human-readable name resolution in overdueJobsProvider from companyUsersProvider (INT-03)
  - Phase 11 E2E test suite with 9 passing tests
affects: [schedule, sync, overdue-panel, calendar-dispatch]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Travel buffer interval generation: sort contractor bookings by start, generate BlockedInterval for gaps > 0 and <= 60 min"
    - "Name resolution via StreamProvider.family watch in sync Provider — falls back to empty map during loading, falls back to raw ID when user not found"
    - "Int03 test pattern: use ConsumerWidget + tester.pump() to allow StreamProvider to emit before asserting ProviderContainer values"

key-files:
  created:
    - mobile/test/e2e/phase_11_integration_polish_e2e_test.dart
  modified:
    - mobile/lib/features/schedule/data/job_site_sync_handler.dart
    - mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart
    - mobile/lib/features/schedule/presentation/providers/overdue_providers.dart

key-decisions:
  - "INT-01: Backend uses latitude/longitude in JobSiteResponse JSON; Drift column names (lat/lng) are intentionally different — only the read-side mapping was wrong"
  - "INT-02: Travel buffer interval uses exact booking.timeRangeEnd → next.timeRangeStart to satisfy ContractorLane isAtSameMomentAs matching; gaps > 60 min skipped (free time, not travel)"
  - "INT-03: overdueJobsProvider returns empty list when auth is not AuthAuthenticated — prevents crash and avoids empty companyId lookup"
  - "INT-03: _displayName helper uses firstName+lastName, firstName alone, or email-prefix fallback — matches ContractorLaneHeader pattern"

patterns-established:
  - "INT-03 test pattern: wrap ProviderContainer reads in ConsumerWidget + pump() to allow StreamProvider.autoDispose.family to emit values before asserting"

requirements-completed: [SCHED-06, SCHED-08]

# Metrics
duration: 15min
completed: 2026-03-14
---

# Phase 11 Plan 01: Integration Polish Summary

**Surgical wiring fixes for three v1.0 milestone gaps: latitude/longitude field name mapping in sync handler, travel buffer interval generation in calendar day view, and UUID-to-name resolution in overdue panel.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-03-14T04:01:44Z
- **Completed:** 2026-03-14T04:16:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Fixed INT-01: `JobSiteSyncHandler.applyPulled()` now reads `data['latitude']`/`data['longitude']` (not `data['lat']`/`data['lng']`) — job site coordinates sync correctly from backend
- Fixed INT-02: `CalendarDayView._buildLaneWidgets()` generates `BlockedInterval(reason: 'travel_buffer')` between consecutive bookings with gaps of 1–60 minutes — TravelTimeBlock renders on calendar
- Fixed INT-03: `overdueJobsProvider` watches `companyUsersProvider(companyId)` and resolves client/contractor names — OverduePanel shows "Alice Smith" not raw UUIDs
- All 9 E2E tests pass (2 INT-01 unit tests, 3 INT-02 widget tests, 3 INT-03 tests, 1 e2e_coordinate_flow round-trip)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create E2E test stubs** - `a48f1b9` (test)
2. **Task 2: Fix INT-01, INT-02, INT-03 and fill E2E tests** - `8d0bcaf` (feat)

## Files Created/Modified
- `mobile/lib/features/schedule/data/job_site_sync_handler.dart` - Changed `data['lat']`/`data['lng']` to `data['latitude']`/`data['longitude']`
- `mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart` - Added travel_buffer BlockedInterval generation loop after building outside_working_hours intervals
- `mobile/lib/features/schedule/presentation/providers/overdue_providers.dart` - Added auth check, companyUsersProvider watch, _displayName helper, and name resolution in _toOverdueJobInfo
- `mobile/test/e2e/phase_11_integration_polish_e2e_test.dart` - Created: 9 E2E tests covering all three integration gaps

## Decisions Made
- INT-01: Backend JSON uses `latitude`/`longitude` (full names); Drift column names `lat`/`lng` are correct and unchanged — only the read-side mapping in `applyPulled` needed updating
- INT-02: Interval gap threshold is 60 minutes — gaps > 60 min are genuine free time, not travel; the interval's `end` must exactly equal `nextBooking.timeRangeStart` to satisfy `ContractorLane`'s `isAtSameMomentAs` check
- INT-03: `overdueJobsProvider` guards against non-authenticated state by returning empty list early — prevents `companyId` being empty string and triggering spurious DB queries
- INT-03 test: Needed to use `ConsumerWidget` + `tester.pump()` instead of bare `ProviderContainer.read()` because `StreamProvider.autoDispose.family` requires a widget subscriber to stay alive and emit values

## Deviations from Plan

None — plan executed exactly as written. All three fixes were surgical one-file changes as specified.

## Issues Encountered

- **INT-02 widget test layout overflow**: Initial test used `SizedBox(width: 400)` but `CalendarDayView._calcLaneWidth()` reads from `MediaQuery.of(context).size.width` (full test window, 800px) instead of the SizedBox constraint. Fixed by setting `tester.view.physicalSize` + wrapping in explicit `MediaQuery` override, giving consistent lane widths in tests.
- **INT-03 StreamProvider timing**: `ProviderContainer.read(overdueJobsProvider)` without a widget subscriber returned stale data (empty userNames map) because `StreamProvider.autoDispose.family` hadn't emitted yet. Fixed by reading inside a `ConsumerWidget` and calling `tester.pump()` to drive stream delivery.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- INT-01, INT-02, INT-03 gaps from v1.0 milestone audit are now closed
- Phase 11 Plan 01 complete; ready for Phase 11 Plan 02 (if any remaining integration gaps)

## Self-Check: PASSED

All files exist and commits verified:
- FOUND: job_site_sync_handler.dart
- FOUND: calendar_day_view.dart
- FOUND: overdue_providers.dart
- FOUND: phase_11_integration_polish_e2e_test.dart
- FOUND: 11-01-SUMMARY.md
- FOUND: commit a48f1b9 (Task 1)
- FOUND: commit 8d0bcaf (Task 2)

---
*Phase: 11-integration-polish*
*Completed: 2026-03-14*
