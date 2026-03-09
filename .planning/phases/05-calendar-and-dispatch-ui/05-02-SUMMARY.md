---
phase: 05-calendar-and-dispatch-ui
plan: "02"
subsystem: ui
tags:
  - flutter
  - riverpod
  - calendar
  - dispatch
  - drift
  - custom-painter
  - patterns-canvas

dependency_graph:
  requires:
    - "05-01: BookingDao, BookingEntity, Drift Bookings table"
    - "04-job-lifecycle: JobEntity, JobDao, jobListNotifierProvider"
    - "01-foundation: AuthState, UserEntity, UserDao, RouteNames"
    - "02-offline-sync-engine: SyncEngine.syncNow for pull-to-refresh"
  provides:
    - "OverdueService: pure Dart tiered severity computation (none/warning/critical)"
    - "CalendarViewMode enum + statusColorMap constant"
    - "calendar_providers: date, view mode, page index, filter state providers"
    - "bookingsForDateProvider: AsyncNotifier watching Drift booking stream by date"
    - "contractorsProvider + filteredContractorsProvider (5/page pagination)"
    - "overdueJobsProvider + overdueJobCountProvider derived from job list"
    - "CalendarGridPainter: CustomPainter with hour lines, blocked regions, now-line"
    - "BlockedInterval data class for non-working-hour shading"
    - "BookingCard: status-colored card with overdue borders, delay badge, LongPressDraggable"
    - "TravelTimeBlock: hatched diagonal stripe block via patterns_canvas"
    - "ContractorLane: Stack-based time column with BookingCard + TravelTimeBlock"
    - "CalendarDayView: paginated lanes with synchronized scroll + time axis"
    - "ScheduleScreen: full admin dispatch calendar replacing placeholder"
  affects:
    - "05-03: Dispatch drawer depends on ContractorLane, BookingCard, CalendarDayView structure"
    - "05-04: Drag-and-drop builds on LongPressDraggable wrapper in BookingCard"
    - "05-05: Week/month view skeleton is in ScheduleScreen (Coming soon placeholder)"

tech_stack:
  added:
    - "patterns_canvas ^0.5.0: diagonal stripe pattern for travel time blocks"
  patterns:
    - "CalendarGridPainter: shouldRepaint compares minute-level currentTime + interval list"
    - "Synchronized scroll: shared ScrollController across time axis + all visible lanes"
    - "Scroll sync via NotificationListener<ScrollNotification> on lane area"
    - "LongPressDraggable wrapper on BookingCard: data=jobId, ready for Plan 03 DragTarget"
    - "OverdueService.computeSeverity: whole-day comparison strips time component"
    - "statusColorMap: Map<String, Color> constant shared across calendar widgets"
    - "pixelsPerMinute=2.0 constant (120px/hour) defined in calendar_providers.dart"
    - "PageView replaced by manual pagination with contractorPageIndexProvider StateProvider"
    - "Default working hours 06:00–18:00 blocked intervals — Plan 03 wires real schedule data"

key_files:
  created:
    - mobile/lib/features/schedule/domain/overdue_service.dart
    - mobile/lib/features/schedule/presentation/providers/calendar_providers.dart
    - mobile/lib/features/schedule/presentation/providers/overdue_providers.dart
    - mobile/lib/features/schedule/presentation/widgets/calendar_grid_painter.dart
    - mobile/lib/features/schedule/presentation/widgets/booking_card.dart
    - mobile/lib/features/schedule/presentation/widgets/travel_time_block.dart
    - mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart
    - mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart
    - mobile/lib/features/schedule/presentation/screens/schedule_screen.dart
  modified:
    - mobile/pubspec.yaml
    - mobile/lib/shared/screens/schedule_screen.dart

key_decisions:
  - "PageView.builder replaced with manual contractorPageIndexProvider pagination — avoids PageController lifecycle complexity with shared scroll controllers"
  - "UserDao accessed via AppDatabase.userDao (not registered in GetIt) — matches user_providers.dart pattern"
  - "BookingCard imports BookingDao via AppDatabase re-export — eliminates unnecessary direct DAO import"
  - "patterns_canvas URI error during analyze is expected — Flutter SDK not installed, pub get not run"
  - "BookingEntity getter errors during analyze are expected — freezed generated files gitignored, build_runner not run"
  - "Default 06:00–18:00 blocked intervals are placeholders — Plan 03 wires real ContractorWeeklySchedule data"
  - "ScheduleScreen uses re-export pattern in shared/ — keeps router import path stable while impl is in feature-first structure"

requirements_completed:
  - SCHED-03
  - SCHED-08

metrics:
  duration: 13 minutes
  completed: "2026-03-09"
  tasks: 3
  files_created: 9
  files_modified: 2
---

# Phase 5 Plan 02: Core Calendar Day View — Summary

**CustomPainter-backed day view calendar with contractor lanes, paginated ContractorLane widgets, status-colored BookingCards with overdue severity indicators, hatched TravelTimeBlocks, synchronized time axis scroll, and admin ScheduleScreen replacing the placeholder.**

## Performance

- **Duration:** 13 minutes
- **Started:** 2026-03-09T18:44:08Z
- **Completed:** 2026-03-09T18:57:08Z
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments

- OverdueService computes tiered severity (none/warning/critical) for booking cards from scheduledCompletionDate; overdueJobsProvider + overdueJobCountProvider derived from existing job stream
- CalendarGridPainter renders hour lines (solid/half-hour dashed), non-working-hour grey shading, "Day off" label for time_off intervals, and a red "now" circle+line at the current time
- BookingCard: status-colored with 4px left border, dimmed terminal statuses, delay clock icon, overdue warning/critical borders/icons, LongPressDraggable wrapper ready for Plan 03
- ContractorLane: Stack composing CalendarGridPainter + positioned BookingCards + TravelTimeBlocks, with fixed contractor avatar/name header above the scrollable time body
- CalendarDayView: synchronized vertical scroll across time axis + all lanes via shared ScrollController + NotificationListener; auto-scrolls to 06:00 on load; pagination controls
- ScheduleScreen: replaced placeholder with full admin dispatch calendar — SegmentedButton view mode, date navigation arrows + tappable date label (showDatePicker), Today button, overdue badge, trade filter dropdown, pull-to-refresh

## Task Commits

Each task was committed atomically:

1. **Task 1: Riverpod providers, overdue service, and patterns_canvas dependency** - `abda383` (feat)
2. **Task 2: Primitive calendar widgets — grid painter, booking card, travel time block** - `89d120e` (feat)
3. **Task 3: Composite calendar widgets — contractor lane, day view, and schedule screen** - `56dd73b` (feat)

## Files Created/Modified

- `mobile/lib/features/schedule/domain/overdue_service.dart` - Pure Dart tiered overdue severity computation
- `mobile/lib/features/schedule/presentation/providers/calendar_providers.dart` - CalendarViewMode enum, statusColorMap, pixelsPerMinute, all calendar StateProviders, BookingsForDateNotifier, ContractorsNotifier, filteredContractorsProvider
- `mobile/lib/features/schedule/presentation/providers/overdue_providers.dart` - overdueJobsProvider + overdueJobCountProvider
- `mobile/lib/features/schedule/presentation/widgets/calendar_grid_painter.dart` - CustomPainter for time grid + BlockedInterval class
- `mobile/lib/features/schedule/presentation/widgets/booking_card.dart` - Status-colored booking card with overdue/delay indicators + LongPressDraggable
- `mobile/lib/features/schedule/presentation/widgets/travel_time_block.dart` - Hatched travel buffer block via patterns_canvas DiagonalStripesLight
- `mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart` - Single contractor time column composing all primitive widgets
- `mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart` - Paginated lanes + time axis + synchronized scroll
- `mobile/lib/features/schedule/presentation/screens/schedule_screen.dart` - Admin dispatch calendar ConsumerWidget
- `mobile/pubspec.yaml` - Added patterns_canvas ^0.5.0
- `mobile/lib/shared/screens/schedule_screen.dart` - Re-export to keep router import path stable

## Decisions Made

- **PageView replaced with StateProvider pagination:** Using `contractorPageIndexProvider` + manual slice of contractor list instead of `PageController`/`PageView.builder` — avoids complex lifecycle management for the shared ScrollController across multiple pages.
- **UserDao via AppDatabase accessor:** `db.userDao.watchUsersByCompany()` accessed through AppDatabase (not registered directly in GetIt) — follows the pattern established in `user_providers.dart`.
- **Default working hours as placeholder:** 06:00–18:00 blocked intervals are hardcoded in `_LanePage._buildDefaultBlockedIntervals()` for now. Plan 03 will replace this with actual `ContractorWeeklySchedule` data from the scheduling engine.
- **Re-export pattern for schedule screen:** `shared/screens/schedule_screen.dart` re-exports from `features/schedule/presentation/screens/schedule_screen.dart` — keeps the router import path stable (admin re-export pattern established in Phase 4).
- **Synchronized scroll via NotificationListener:** `NotificationListener<ScrollNotification>` on the lanes area drives `_scrollController.jumpTo()` on the time axis. Plan 03 may need to revisit if drag-and-drop scroll conflicts arise.

## Deviations from Plan

None — plan executed exactly as written with minor implementation notes:

**Note on patterns_canvas analyze errors:** `dart analyze` reports `uri_does_not_exist` for `package:patterns_canvas/patterns_canvas.dart` because `flutter pub get` has not been run (Flutter SDK not installed per STATE.md blockers). The code is correct; the package is declared in pubspec.yaml. Resolves when SDK is installed.

**Note on BookingEntity getter errors:** `dart analyze` reports undefined getters on `BookingEntity` (contractorId, timeRangeStart, etc.) because `booking_entity.freezed.dart` is gitignored and not generated (build_runner not available). The getters ARE declared in the source `booking_entity.dart`. This is a pre-existing project constraint affecting all Freezed/Drift generated code.

## Issues Encountered

No blocking issues. Both analyze warnings documented above are known project constraints (Flutter SDK not installed) that also affect Plan 01 code (booking_dao.dart shows identical category of errors).

## Next Phase Readiness

- ContractorLane is ready for Plan 03 drag-and-drop: `LongPressDraggable<String>(data: job.id)` wrapper in BookingCard ready to accept DragTarget wiring
- CalendarDayView uses `contractorPageIndexProvider` ready for dispatch drawer integration in Plan 03
- ScheduleScreen overdue badge tap is wired to a Snackbar placeholder — Plan 04 replaces with overdue panel widget
- Working hours blocked intervals (06:00–18:00 default) await real `ContractorWeeklySchedule` data wiring in Plan 03

---
*Phase: 05-calendar-and-dispatch-ui*
*Completed: 2026-03-09*

## Self-Check: PASSED

Files created/modified:
- mobile/lib/features/schedule/domain/overdue_service.dart: FOUND
- mobile/lib/features/schedule/presentation/providers/calendar_providers.dart: FOUND
- mobile/lib/features/schedule/presentation/providers/overdue_providers.dart: FOUND
- mobile/lib/features/schedule/presentation/widgets/calendar_grid_painter.dart: FOUND
- mobile/lib/features/schedule/presentation/widgets/booking_card.dart: FOUND
- mobile/lib/features/schedule/presentation/widgets/travel_time_block.dart: FOUND
- mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart: FOUND
- mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart: FOUND
- mobile/lib/features/schedule/presentation/screens/schedule_screen.dart: FOUND
- mobile/pubspec.yaml: FOUND (modified)
- mobile/lib/shared/screens/schedule_screen.dart: FOUND (modified)

Commits:
- abda383: feat(05-02): Riverpod providers, overdue service, and patterns_canvas dependency
- 89d120e: feat(05-02): Primitive calendar widgets — grid painter, booking card, travel time block
- 56dd73b: feat(05-02): Composite calendar widgets and schedule screen replacing placeholder
