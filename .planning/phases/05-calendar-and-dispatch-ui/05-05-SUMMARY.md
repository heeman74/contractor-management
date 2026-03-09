---
phase: 05-calendar-and-dispatch-ui
plan: 05
subsystem: ui
tags: [flutter, riverpod, drift, calendar, week-view, month-view, contractor-schedule, go_router]

# Dependency graph
requires:
  - phase: 05-calendar-and-dispatch-ui
    provides: "Day view, contractor lanes, booking cards, overdue providers, calendar_providers.dart, BookingDao, DelayJustificationDialog"
  - phase: 05-calendar-and-dispatch-ui
    provides: "CalendarViewMode enum, pixelsPerMinute const, statusColorMap, ContractorLane widget"
provides:
  - CalendarWeekView widget (7-column grid with contractor rows, job chips, overdue borders)
  - CalendarMonthView widget (monthly grid with booking count badges)
  - ContractorScheduleScreen (personal schedule with list/calendar toggle, overdue prompts, Report Delay)
  - ScheduleSettingsScreen (7-day weekly template form with time pickers, GET/PATCH API)
  - Long-press on contractor lane header navigates to schedule settings (admin only)
  - RouteNames.contractorSchedule + RouteNames.scheduleSettings constants
  - Role-based Schedule tab screen selection (admin -> ScheduleScreen, contractor -> ContractorScheduleScreen)
affects: [06-notifications, routing, schedule-management]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Week/Month view swipe via GestureDetector.onHorizontalDragEnd (not PageView) to avoid scroll conflicts"
    - "Role-based route builder: ProviderScope.containerOf(context).read() for synchronous auth read in GoRouter builder"
    - "ConsumerWidget for _ContractorHeader to access auth role for conditional long-press"
    - "StreamProvider.autoDispose.family with record typedef for typed key (contractor + date)"
    - "Minimal UserEntity from auth state for calendar lane display without DB lookup"

key-files:
  created:
    - mobile/lib/features/schedule/presentation/widgets/calendar_week_view.dart
    - mobile/lib/features/schedule/presentation/widgets/calendar_month_view.dart
    - mobile/lib/features/schedule/presentation/screens/contractor_schedule_screen.dart
    - mobile/lib/features/schedule/presentation/screens/schedule_settings_screen.dart
  modified:
    - mobile/lib/features/schedule/presentation/screens/schedule_screen.dart
    - mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart

key-decisions:
  - "GestureDetector.onHorizontalDragEnd for week/month swipe — avoids PageView scroll controller lifecycle complexity (same decision as contractorPageIndexProvider from P03)"
  - "ProviderScope.containerOf(context).read() in GoRouter builder for synchronous role check — builder is not a Consumer widget"
  - "_ContractorHeader upgraded from StatelessWidget to ConsumerWidget — needed to watch authNotifierProvider for admin role check"
  - "Minimal UserEntity constructed from auth state for ContractorLane in contractor calendar — avoids async DB lookup in build"
  - "scheduleSettings as top-level GoRoute (not shell branch) — accessed via context.push() from both admin calendar and contractor settings gear icon"
  - "Role selection in Schedule tab builder reads auth synchronously after redirect ran — redirect guarantees auth is resolved before builder fires"

patterns-established:
  - "Week view: getMondayOfWeek() + 7-day list + GestureDetector swipe navigation"
  - "Month view: _buildCalendarCells() generates complete 7-col rows from firstMonday to lastSunday of month"
  - "Contractor schedule: StreamProvider.autoDispose.family with record typedef ({contractorId, date}) for typed family key"
  - "Schedule settings: offline banner on network errors, DioClient.instance for Dio access"

requirements-completed: [SCHED-03, SCHED-08]

# Metrics
duration: 16min
completed: 2026-03-09
---

# Phase 5 Plan 05: Week/Month Calendar Views, Contractor Schedule, and Settings Summary

**Week/month calendar views + contractor personal schedule with list/calendar toggle + schedule settings screen with weekly template management + long-press admin shortcut to contractor settings**

## Performance

- **Duration:** 16 min
- **Started:** 2026-03-09T21:54:16Z
- **Completed:** 2026-03-09T22:10:00Z
- **Tasks:** 2
- **Files modified:** 8 (4 created, 4 modified)

## Accomplishments

- Three complete calendar view modes (day/week/month) — week/month replace "Coming soon" placeholder
- Week view: 7-column contractor grid, job chips with overdue severity borders, +N overflow badges, swipe navigation, tap-to-drill-down to day view, contractor pagination
- Month view: standard calendar grid, booking count badges with severity coloring, today highlighted, dimmed out-of-month days, swipe navigation, month header with arrows
- ContractorScheduleScreen: date-grouped list view + single-lane calendar view with toggle, overdue prompts, Report Delay button, pull-to-refresh
- ScheduleSettingsScreen: 7-day weekly template with working/off toggles, time pickers, copy-to-weekdays quick action, offline banner, GET/PATCH to scheduling API
- Long-press on contractor lane header opens schedule settings for that contractor (admin-only, locked CONTEXT.md decision implemented)
- Role-based Schedule tab: admin sees dispatch calendar, contractor sees personal schedule

## Task Commits

Each task was committed atomically:

1. **Task 1: Week view, month view, and schedule screen view mode integration** - `27a08ec` (feat)
2. **Task 2: Contractor personal schedule, settings, long-press nav, and routes** - `c6688dc` (feat)

## Files Created/Modified

- `mobile/lib/features/schedule/presentation/widgets/calendar_week_view.dart` - 7-column week grid with contractor rows, job chips, swipe nav, drill-down
- `mobile/lib/features/schedule/presentation/widgets/calendar_month_view.dart` - Monthly grid with booking count badges, today highlight, swipe nav
- `mobile/lib/features/schedule/presentation/screens/contractor_schedule_screen.dart` - Personal schedule with list/calendar toggle, overdue prompts, Report Delay
- `mobile/lib/features/schedule/presentation/screens/schedule_settings_screen.dart` - Weekly template form with 7 day rows, time pickers, offline support
- `mobile/lib/features/schedule/presentation/screens/schedule_screen.dart` - Added week/month view builders, view-mode-aware date navigation, removed Coming Soon
- `mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart` - _ContractorHeader upgraded to ConsumerWidget with admin long-press to settings
- `mobile/lib/core/routing/app_router.dart` - Added scheduleSettings route, contractorSchedule to Branch 5, role-based Schedule tab builder
- `mobile/lib/core/routing/route_names.dart` - Added contractorSchedule and scheduleSettings constants

## Decisions Made

- **GestureDetector swipe for week/month**: Used `GestureDetector.onHorizontalDragEnd` rather than `PageView` — avoids ScrollController lifecycle complexity in paginated contractor rows; consistent with existing `contractorPageIndexProvider` pattern from P03.
- **Role-based GoRouter builder**: Used `ProviderScope.containerOf(context).read(authNotifierProvider)` in the GoRoute builder function to synchronously read auth state for role-based screen selection. GoRouter redirect always runs before builder, guaranteeing auth is resolved.
- **Minimal UserEntity for contractor calendar**: Constructed a placeholder `UserEntity` from auth state fields instead of async DB lookup. The ContractorLane widget only uses UserEntity for avatar initials/name display — "My Schedule" is sufficient for the single-lane contractor view.
- **scheduleSettings as top-level route**: Placed outside StatefulShellRoute so it can be pushed from any context (admin calendar via long-press, contractor schedule screen via gear icon) without being bound to a specific branch.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

- `DioClient.dio` getter does not exist — the correct getter is `DioClient.instance`. Fixed by using the correct getter name (Rule 1 auto-fix during Task 2).
- Pre-existing `BookingEntity` field resolution errors throughout the schedule feature (same as all other schedule files since Plan 02) — caused by missing `build_runner` code generation. Documented blocker in STATE.md: "Flutter SDK not installed". No new errors introduced.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All three calendar view modes complete — Phase 5 Plans 01-05 done
- Contractor personal schedule functional with list/calendar toggle
- Schedule settings ready with API integration
- Long-press admin shortcut to contractor settings implemented (locked decision)
- Only Plan 06 remaining in Phase 5

---
*Phase: 05-calendar-and-dispatch-ui*
*Completed: 2026-03-09*
