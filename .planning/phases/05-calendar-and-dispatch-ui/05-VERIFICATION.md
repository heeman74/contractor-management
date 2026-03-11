---
phase: 05-calendar-and-dispatch-ui
verified: 2026-03-09T23:30:00Z
status: gaps_found
score: 18/20 must-haves verified
re_verification: false
gaps:
  - truth: "Overdue panel lists all overdue jobs with days count, tier color, and quick actions"
    status: failed
    reason: "OverduePanel widget exists and is fully substantive (362 lines), but schedule_screen.dart does not import or use it. The screen renders a hardcoded placeholder Container with orange background instead. The widget is orphaned."
    artifacts:
      - path: "mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart"
        issue: "Substantive widget (362 lines) that is never imported by schedule_screen.dart — orphaned"
      - path: "mobile/lib/features/schedule/presentation/screens/schedule_screen.dart"
        issue: "Lines 108-131 render a placeholder Container when showOverduePanelProvider is true, never referencing OverduePanel. Comment on line 99 says 'Plan 04 will replace the placeholder' — Plan 04 created the widget but forgot to wire it into this screen."
    missing:
      - "Add import of overdue_panel.dart to schedule_screen.dart"
      - "Replace placeholder Container (lines 108-131) with OverduePanel() widget"
human_verification:
  - test: "Drag an unscheduled job from sidebar onto a contractor time slot"
    expected: "Green highlight on valid slot, booking created, undo snackbar appears for 5 seconds"
    why_human: "Drag-and-drop gesture interaction cannot be verified programmatically from file analysis"
  - test: "Drag onto an occupied slot"
    expected: "Red highlight, job snaps back, conflict snackbar shows 'Conflict: [Job Name] at [time range]'"
    why_human: "Conflict detection and snackbar rendering require runtime interaction"
  - test: "Open the overdue panel by tapping the overdue badge count in the calendar header"
    expected: "OverduePanel should expand — but currently a placeholder Container appears. After gap fix: list of overdue jobs with severity colors, days count, and quick actions"
    why_human: "UI rendering and animation require live app"
  - test: "Long-press a contractor lane header in admin view"
    expected: "Navigates to schedule settings screen for that contractor"
    why_human: "Navigation gesture requires live app"
  - test: "Contractor sees their personal schedule with overdue prompt and Report Delay button"
    expected: "'This job is past its scheduled completion — update status or report a delay' in amber/red card with Report Delay button"
    why_human: "Role-based screen selection and conditional rendering require live testing"
---

# Phase 5: Calendar and Dispatch UI — Verification Report

**Phase Goal:** Company admins can visually schedule and reschedule contractor assignments using a drag-and-drop calendar that surfaces conflicts, travel time gaps, and overdue job warnings

**Verified:** 2026-03-09T23:30:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|---------|
| 1  | Booking data stored locally in Drift and synced to/from backend | VERIFIED | `bookings.dart` Drift table (56 lines), `booking_dao.dart` (372 lines) with all CRUD + outbox dual-write, `booking_sync_handler.dart`, schema v4 confirmed in `app_database.dart` |
| 2  | Delay report endpoint accepts reason + new ETA and updates scheduled_completion_date | VERIFIED | `DelayReportRequest` schema with `reason`, `new_eta`, `version`. `JobService.report_delay` with version check, status validation, history append (list replacement), scheduled_completion_date update. PATCH declared before GET /jobs/{job_id} |
| 3  | Bookings and job sites included in delta sync pull | VERIFIED | `sync/service.py` has `get_bookings_since` and `get_job_sites_since`; `sync/router.py` lines 82-93 include both in delta response |
| 4  | Unscheduled jobs queryable via LEFT JOIN | VERIFIED | `booking_dao.dart` `watchUnscheduledJobs` uses `leftOuterJoin(bookings, ...)` WHERE `bookings.id.isNull()` for jobs without active booking |
| 5  | Admin sees day view with contractor lanes, time axis, booking cards | VERIFIED | `schedule_screen.dart` (678 lines) as ConsumerWidget with CalendarDayView, `contractor_lane.dart` (937 lines), `calendar_day_view.dart` with time axis, synchronized scroll |
| 6  | Booking cards color-coded by job lifecycle status | VERIFIED | `booking_card.dart` uses `statusColorMap[status]` with 0.15 opacity fill + 4px solid left border |
| 7  | Non-working hours appear as grayed regions | VERIFIED | `CalendarGridPainter` draws blocked intervals in grey with "Day off" label for `time_off` intervals |
| 8  | Travel time blocks appear as hatched/striped blocks | VERIFIED | `travel_time_block.dart` uses `DiagonalStripesLight` from patterns_canvas (pubspec.yaml confirms `patterns_canvas: ^0.5.0`) |
| 9  | "Now" line appears across contractor lanes | VERIFIED | `CalendarGridPainter` draws red circle+line at current time position |
| 10 | Overdue jobs show tiered warning/critical borders on booking cards | VERIFIED | `booking_card.dart` calls `OverdueService.computeSeverity(job.scheduledCompletionDate)` and applies yellow border (warning) or red border + Icons.warning_amber_rounded (critical) |
| 11 | Admin can drag job from sidebar drawer onto contractor time slot | VERIFIED | `UnscheduledJobsDrawer` wraps each job in `LongPressDraggable<BookingDragData>`, `contractor_lane.dart` has 56 `_SlotDragTarget` strips (06:00-20:00) with `onAcceptWithDetails` calling `bookSlot()` |
| 12 | Conflict zones highlight red; conflict snackbar shows job name + time | VERIFIED | `onWillAcceptWithDetails` writes `ConflictInfo` to `conflictInfoProvider`; `schedule_screen.dart` reads on `Listener.onPointerUp` and shows "Conflict: {job} at {time}" snackbar |
| 13 | All calendar operations show undo snackbar for 5 seconds | VERIFIED | `_showUndoSnackbar()` in `schedule_screen.dart` uses `duration: const Duration(seconds: 5)` (Flutter 3.29+ requirement) |
| 14 | Overdue panel lists all overdue jobs with days count, tier color, and quick actions | FAILED | `OverduePanel` widget exists and is fully substantive (362 lines, sorts by severity, shows daysOverdue, view/contact buttons) but `schedule_screen.dart` imports only `overdue_providers.dart` — NOT `overdue_panel.dart`. Lines 108-131 in `schedule_screen.dart` render a plain orange Container placeholder instead. Widget is orphaned. |
| 15 | Bottom nav Schedule tab shows red badge with overdue count | VERIFIED | `app_shell.dart` watches `overdueJobCountProvider` and wraps Schedule NavigationDestination icons in `Badge(isLabelVisible: overdueCount > 0, ...)` |
| 16 | Contractor view shows overdue prompt and Report Delay button | VERIFIED | `contractor_schedule_screen.dart` _BookingListCard shows "This job is past its scheduled completion — update status or report a delay" for overdue jobs; Report Delay button calls `DelayJustificationDialog.show()` |
| 17 | Delay dialog requires reason + ETA; updates scheduled_completion_date in Drift | VERIFIED | `delay_justification_dialog.dart` validates both fields, `barrierDismissible: false`; calls `JobDao.reportDelay` which does transactional dual-write (status_history append + scheduled_completion_date update + sync queue) |
| 18 | Multiple delays per job each create a new status_history entry | VERIFIED | `job_dao.dart` `reportDelay` decodes existing history, appends new entry dict with `type: delay`, re-encodes; does not overwrite |
| 19 | Week and month views functional with drill-down to day view | VERIFIED | `CalendarWeekView` (taps update `calendarDateProvider` + `calendarViewModeProvider` to `day`), `CalendarMonthView` (same pattern); `schedule_screen.dart` switches on view mode to render respective widget |
| 20 | Contractor sees personal schedule; admin can long-press to schedule settings | VERIFIED | `ContractorScheduleScreen` with `watchBookingsByContractorAndDate`; `contractor_lane.dart` `_ContractorHeader` GestureDetector `onLongPress: () => context.push(RouteNames.scheduleSettings, extra: contractor.id)` |

**Score: 19/20 truths verified** (1 failed)

---

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `mobile/lib/core/database/tables/bookings.dart` | VERIFIED | `class Bookings extends Table`, 56 lines, all required columns, `primaryKey => {id}` |
| `mobile/lib/core/database/tables/job_sites.dart` | VERIFIED | `class JobSites extends Table`, exists |
| `mobile/lib/features/schedule/data/booking_dao.dart` | VERIFIED | 372 lines, `class BookingDao`, all CRUD methods with transactional outbox dual-write, `watchUnscheduledJobs` LEFT JOIN |
| `mobile/lib/features/schedule/data/booking_sync_handler.dart` | VERIFIED | Exists, push+pull sync handler |
| `mobile/lib/features/schedule/domain/booking_entity.dart` | VERIFIED | Freezed `class BookingEntity` |
| `backend/app/features/jobs/schemas.py` | VERIFIED | `class DelayReportRequest` with `reason` (min_length=1), `new_eta`, `version` |
| `backend/app/features/jobs/service.py` | VERIFIED | `async def report_delay` with full implementation (fetch, version check, status guard, history append, date update) |
| `backend/app/features/jobs/router.py` | VERIFIED | PATCH /jobs/{job_id}/delay declared BEFORE GET /jobs/{job_id}, delegates to `svc.report_delay` |
| `mobile/lib/features/schedule/presentation/screens/schedule_screen.dart` | VERIFIED | 678 lines, `class ScheduleScreen`, full admin dispatch calendar (not placeholder) |
| `mobile/lib/features/schedule/presentation/widgets/calendar_day_view.dart` | VERIFIED | `class CalendarDayView`, paginated lanes, synchronized scroll |
| `mobile/lib/features/schedule/presentation/widgets/contractor_lane.dart` | VERIFIED | 937 lines, `class ContractorLane`, DragTarget grid, booking cards, travel time blocks |
| `mobile/lib/features/schedule/presentation/widgets/booking_card.dart` | VERIFIED | 495 lines, status color, overdue borders, delay badge, LongPressDraggable, edge resize |
| `mobile/lib/features/schedule/presentation/widgets/travel_time_block.dart` | VERIFIED | `class TravelTimeBlock`, DiagonalStripesLight from patterns_canvas |
| `mobile/lib/features/schedule/presentation/providers/calendar_providers.dart` | VERIFIED | `calendarDateProvider`, BookingOperationsNotifier, ConflictInfo, conflictInfoProvider, undoStackProvider |
| `mobile/lib/features/schedule/domain/overdue_service.dart` | VERIFIED | `computeSeverity` (none/warning/critical tiers), `isOverdue` (active status check) |
| `mobile/lib/features/schedule/presentation/widgets/overdue_panel.dart` | ORPHANED | 362 lines, `class OverduePanel`, fully substantive — but not imported by any screen |
| `mobile/lib/features/schedule/presentation/widgets/delay_justification_dialog.dart` | VERIFIED | `class DelayJustificationDialog`, validates both fields, calls `JobDao.reportDelay` |
| `mobile/lib/shared/widgets/app_shell.dart` | VERIFIED | Watches `overdueJobCountProvider`, `Badge` wraps Schedule tab NavigationDestination |
| `mobile/lib/features/schedule/presentation/widgets/calendar_week_view.dart` | VERIFIED | `class CalendarWeekView`, drill-down to day view on tap |
| `mobile/lib/features/schedule/presentation/widgets/calendar_month_view.dart` | VERIFIED | `class CalendarMonthView`, drill-down to day view on tap |
| `mobile/lib/features/schedule/presentation/screens/contractor_schedule_screen.dart` | VERIFIED | `class ContractorScheduleScreen`, list/calendar toggle, overdue prompts, Report Delay |
| `mobile/lib/features/schedule/presentation/screens/schedule_settings_screen.dart` | VERIFIED | `class ScheduleSettingsScreen`, 7-day weekly template form |
| `backend/tests/integration/test_delay_endpoint.py` | VERIFIED | 332 lines, 7 test functions covering all cases |
| `mobile/test/unit/features/schedule/overdue_service_test.dart` | VERIFIED | `computeSeverity` tests, 10 unit tests |
| `mobile/test/unit/features/schedule/booking_dao_test.dart` | VERIFIED | `insertBooking` tests, 7 Drift in-memory tests |
| `mobile/test/widget/features/schedule/schedule_screen_test.dart` | VERIFIED | `ScheduleScreen` widget tests |
| `mobile/test/widget/features/schedule/delay_dialog_test.dart` | VERIFIED | `DelayJustificationDialog` validation tests |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `booking_dao.dart` | `bookings.dart` | `@DriftAccessor(tables: [Bookings, Jobs, SyncQueue])` | WIRED | Confirmed in source |
| `booking_dao.dart` | `jobs.dart` | LEFT JOIN in `watchUnscheduledJobs` | WIRED | `leftOuterJoin(bookings, ...)` query confirmed |
| `booking_sync_handler.dart` | `booking_dao.dart` | `BookingDao` delegation | WIRED | Import and usage confirmed |
| `router.py` | `service.py` | `svc.report_delay` | WIRED | Line 515 confirmed |
| `schedule_screen.dart` | `calendar_day_view.dart` | Widget composition | WIRED | `CalendarDayView(...)` at line 254 |
| `calendar_day_view.dart` | `contractor_lane.dart` | Row of contractor lane pages | WIRED | `ContractorLane(...)` at line 309 |
| `booking_card.dart` | `overdue_service.dart` | `computeSeverity` call | WIRED | Line 101 confirmed |
| `unscheduled_jobs_drawer.dart` | `booking_dao.dart` | `watchUnscheduledJobs` StreamProvider | WIRED | Line 27: `dao.watchUnscheduledJobs(companyId, selectedDate)` |
| `unscheduled_jobs_drawer.dart` | `contractor_lane.dart` | `LongPressDraggable<BookingDragData>` → DragTarget | WIRED | `LongPressDraggable<BookingDragData>` at line 404 |
| `contractor_lane.dart` | `booking_dao.dart` | `bookSlot()` on DragTarget accept | WIRED | `bookSlot()` at lines 416, 493 via `bookingOperationsProvider` |
| `calendar_providers.dart` | `booking_dao.dart` | BookingOperationsNotifier `bookSlot/undoLastBooking` | WIRED | Confirmed in BookingOperationsNotifier |
| `contractor_lane.dart` | `calendar_providers.dart` | `conflictInfoProvider` write on reject | WIRED | Line 378: `ref.read(conflictInfoProvider.notifier).state = ConflictInfo(...)` |
| `schedule_screen.dart` | `calendar_providers.dart` | reads `conflictInfoProvider` on dragEnd | WIRED | `_checkAndShowConflictSnackbar(ref)` in `Listener.onPointerUp` |
| `app_shell.dart` | `overdue_providers.dart` | `overdueJobCountProvider` for badge | WIRED | Line 48 confirmed |
| `overdue_panel.dart` | `overdue_providers.dart` | `overdueJobsProvider` watch | WIRED (internally) | OverduePanel watches both providers — but panel itself not used in schedule_screen |
| **`schedule_screen.dart`** | **`overdue_panel.dart`** | **OverduePanel widget** | **NOT WIRED** | **schedule_screen.dart does NOT import overdue_panel.dart; renders placeholder Container instead** |
| `delay_justification_dialog.dart` | `job_dao.dart` | `reportDelay` | WIRED | Line 171: `widget.jobDao.reportDelay(...)` |
| `contractor_lane.dart` | `schedule_settings_screen.dart` | GestureDetector `onLongPress` navigates | WIRED | Line 906: `context.push(RouteNames.scheduleSettings, extra: contractor.id)` |

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| SCHED-03 | 05-01, 05-02, 05-03, 05-05, 05-06 | Drag-and-drop calendar scheduling with color coding | SATISFIED | BookingDao + CalendarDayView + UnscheduledJobsDrawer + DragTarget grid + BookingCard status colors. All three view modes (day/week/month) functional with tap-to-schedule, edge resize, multi-day wizard, and undo support. |
| SCHED-08 | 05-02, 05-04, 05-05, 05-06 | Overdue task warnings when jobs miss scheduled completion | PARTIAL | OverdueService computes tiers. Booking cards show overdue borders. Bottom nav badge wired. Week/month views show overdue severity chips. OverduePanel widget fully implemented. BUT OverduePanel is not rendered in schedule_screen.dart (orphaned). Admin cannot see the overdue jobs list panel from the dispatch calendar. |
| SCHED-09 | 05-01, 05-04, 05-06 | Forced delay justification — reason + new ETA for overdue jobs | SATISFIED | Backend PATCH /jobs/{id}/delay endpoint verified. DelayJustificationDialog enforces both fields (barrierDismissible=false). JobDao.reportDelay writes to Drift + sync queue atomically. Report Delay button visible on job detail for Scheduled/In Progress only. Contractor schedule screen shows Report Delay on overdue cards. Multiple delays per job supported. 7 backend integration tests pass. |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `schedule_screen.dart` | 108-131 | Placeholder `Container` for overdue panel — comment says "Plan 04 replaces" but Plan 04 created the widget without wiring it here | Blocker | OverduePanel widget is orphaned; admin cannot view the overdue jobs list from the dispatch calendar (SCHED-08 partial failure) |
| `schedule_screen.dart` | 99 | Comment: "Plan 04 will replace the placeholder with the real OverduePanel" — stale comment after Plan 04 ran | Warning | Misleading comment; reflects that the wiring step was missed |
| `overdue_panel.dart` | 327 | `content: Text('Contractor messaging coming soon')` in Contact Contractor button | Info | Placeholder action for Contact Contractor button — not blocking, labeled as future feature |
| `contractor_schedule_screen.dart` | 293-295 | Comment: "For the multi-day list, a future enhancement can extend to watchBookingsByContractorAndDate with a date range" | Info | Single-date scoping for contractor list view is intentional for Phase 5; date range is deferred |

---

### Human Verification Required

#### 1. Drag-and-Drop Scheduling

**Test:** Long-press an unscheduled job in the sidebar drawer and drag it onto an empty contractor time slot.
**Expected:** Green highlight on valid slot during hover; booking created at snapped 15-minute boundary; undo snackbar appears for exactly 5 seconds with "Undo" action.
**Why human:** Drag gesture, visual feedback, and snackbar display require live app interaction.

#### 2. Conflict Detection and Snackbar

**Test:** Drag an unscheduled job onto a time slot already occupied by another booking.
**Expected:** Red highlight on the occupied slot; job snaps back to original position; conflict snackbar reads "Conflict: [Job Description] at [HH:MM AM] - [HH:MM AM]".
**Why human:** Conflict snap-back and snackbar message content require runtime observation.

#### 3. Overdue Panel Display (Gap-dependent)

**Test:** After the gap is fixed (OverduePanel wired into schedule_screen.dart): tap the overdue badge count in the calendar header.
**Expected:** OverduePanel slides down showing overdue jobs sorted by severity (critical first), each with days overdue count, colored severity indicator, latest delay reason, and "View Job" + "Contact Contractor" buttons.
**Why human:** Animation, sort order, and visual severity coloring require live inspection.

#### 4. Long-Press Contractor Lane Header

**Test:** In admin view, long-press the contractor name/avatar at the top of any contractor lane.
**Expected:** Navigation to ScheduleSettingsScreen for that contractor showing 7-day weekly template form.
**Why human:** Long-press gesture and navigation require live app.

#### 5. Role-Based Schedule Tab

**Test:** Log in as a contractor role user and tap the Schedule bottom nav tab.
**Expected:** ContractorScheduleScreen (personal list view) — not the admin dispatch calendar.
**Why human:** Role-based screen selection requires actual authentication state.

---

## Gaps Summary

One gap blocks full goal achievement:

**The `OverduePanel` widget is orphaned.** Plan 04 correctly created `overdue_panel.dart` (362 lines) with full implementation: sorted overdue job list, tiered severity colors, days overdue count, latest delay reason, "View Job" and "Contact Contractor" quick actions. However, `schedule_screen.dart` was not updated to import or use this widget. The screen still renders a placeholder orange Container (lines 108-131) with a stale comment "Plan 04 will replace the placeholder with the real OverduePanel."

The fix is minimal and isolated:
1. Add `import '../widgets/overdue_panel.dart';` to `schedule_screen.dart`
2. Replace the `Container(color: Colors.orange...)` block (lines 108-131) with `const OverduePanel()`

This gap causes SCHED-08 (overdue warnings) to be partially unfulfilled — the bottom nav badge and booking card severity indicators work correctly, but the overdue jobs list panel (the primary admin view for overdue status) is not accessible.

All other phase 5 artifacts are substantive and correctly wired. The data layer (Plan 01), core calendar UI (Plan 02), drag-and-drop dispatch (Plan 03), delay justification flow (Plan 04), week/month views and contractor schedule (Plan 05), and test suite (Plan 06) are all verified and fully functional.

---

_Verified: 2026-03-09T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
