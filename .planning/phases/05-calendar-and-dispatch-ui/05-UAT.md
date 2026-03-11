---
status: testing
phase: 05-calendar-and-dispatch-ui
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md, 05-03-SUMMARY.md, 05-04-SUMMARY.md, 05-05-SUMMARY.md, 05-06-SUMMARY.md]
started: 2026-03-09T23:10:00Z
updated: 2026-03-09T23:10:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 1
name: Schedule Screen Day View
expected: |
  Open the Schedule tab as an admin user. A day view calendar should render with: vertical time axis on the left (hour lines), horizontal contractor lanes (each with avatar/name header), positioned booking cards color-coded by status, a red "now" line at the current time, and grey shading for non-working hours (06:00-18:00 default).
awaiting: user response

## Tests

### 1. Schedule Screen Day View
automated: true
test_file: mobile/test/widget/features/schedule/schedule_screen_test.dart
expected: Open the Schedule tab as an admin user. A day view calendar should render with: vertical time axis on the left (hour lines), horizontal contractor lanes (each with avatar/name header), positioned booking cards color-coded by status, a red "now" line at the current time, and grey shading for non-working hours (06:00-18:00 default).
result: [pending]

### 2. Date Navigation and Today Button
automated: true
test_file: mobile/test/widget/features/schedule/schedule_screen_test.dart
expected: In the Schedule screen, tap the forward arrow to advance one day — the date label updates and bookings change. Tap the back arrow to go back. Tap the date label itself to open a date picker dialog. Tap the "Today" button to snap back to today's date.
result: [pending]

### 3. View Mode Switching (Day/Week/Month)
automated: true
test_file: mobile/test/widget/features/schedule/schedule_screen_test.dart
expected: In the Schedule screen, the SegmentedButton at the top shows Day/Week/Month options. Tapping "Week" switches to a 7-column grid layout. Tapping "Month" shows a monthly calendar grid. Tapping "Day" returns to the lane-based day view.
result: [pending]

### 4. Week View Display
automated: true
test_file: mobile/test/widget/features/schedule/calendar_week_view_test.dart
expected: In Week view, a 7-column grid shows with contractor rows. Job chips appear in their scheduled day column, color-coded by status. Overdue jobs show severity borders. A "+N" overflow badge appears if too many jobs are on one day. Swiping horizontally navigates to next/previous week. Tapping a day cell drills down to the day view for that date.
result: [pending]

### 5. Month View Display
automated: true
test_file: mobile/test/widget/features/schedule/calendar_month_view_test.dart
expected: In Month view, a standard calendar grid renders the current month. Each day cell shows a booking count badge with severity coloring if any jobs are overdue. Today's cell is highlighted. Days outside the current month appear dimmed. Swiping horizontally navigates months. Month header shows month/year with arrow buttons.
result: [pending]

### 6. Unscheduled Jobs Drawer
automated: true
test_file: mobile/test/widget/features/schedule/unscheduled_jobs_drawer_test.dart
expected: In Day view, a toggle button in the header opens a collapsible sidebar panel (left side). It lists jobs that have no booking for the selected date. Each job card is draggable (long-press to start). A filter bar allows searching by client name, filtering by status (All/Quote/Scheduled), and filtering by trade type. If all jobs are scheduled, an empty state message "All jobs scheduled" appears.
result: [pending]

### 7. Drag to Schedule
automated: false
manual_reason: Cross-widget LongPressDraggable gesture arena unreliable in widget tests
expected: Open the unscheduled jobs drawer. Long-press a job card — it lifts with haptic feedback and a semi-transparent ghost remains in the drawer. Drag the card to an empty time slot on a contractor lane. A green overlay appears on valid drop zones. Release to create a booking — the job card disappears from the drawer and a booking card appears in the lane at the drop time.
result: [pending]

### 8. Scheduling Conflict Detection
automated: false
manual_reason: Requires full drag path to trigger DragTarget rejection with visual overlay
expected: Drag a job onto a time slot that already has a booking. The drop zone shows a red overlay instead of green and the drop is rejected. On release, a conflict snackbar appears with a message like "Conflict: {job} at {time}" explaining the overlap. The job returns to the drawer.
result: [pending]

### 9. Tap to Schedule
automated: false
manual_reason: Private _TapToScheduleSheet inside ContractorLane requires positioned slot tap
expected: Tap on an empty time slot in a contractor lane (not long-press). A bottom sheet slides up showing a searchable list of unscheduled jobs. Select a job from the list to create a booking at that time slot.
result: [pending]

### 10. Booking Edge Resize
automated: true
test_file: mobile/test/widget/features/schedule/booking_card_interactions_test.dart
expected: On an existing booking card, drag the top or bottom edge (8px handle area). A live time range overlay shows the new start/end time as you drag. The resize snaps to 15-minute increments. A minimum 15-minute duration is enforced. Releasing the handle updates the booking times.
result: [pending]

### 11. Cross-Lane Booking Reassignment
automated: false
manual_reason: Same drag-drop limitation as #7 across different ContractorLane parents
expected: Long-press an existing booking card on one contractor's lane. Drag it to a different contractor's lane and drop on an empty time slot. The booking moves from the original contractor to the new one — disappears from the source lane and appears in the target lane.
result: [pending]

### 12. Multi-Day Wizard Dialog
automated: true
test_file: mobile/test/widget/features/schedule/multi_day_wizard_dialog_test.dart
expected: Schedule a job that requires more than 8 hours of work. After the first-day booking is created, a Multi-Day Wizard dialog appears showing the first day as a non-editable summary. Additional day entries can be added with date and time pickers. An "Add day" button appends entries. "Suggest dates" attempts an API call (shows "Offline" message if no internet). Cancel reverses the first-day booking. Confirm creates bookings for all additional days.
result: [pending]

### 13. Undo Booking Action
automated: true
test_file: mobile/test/widget/features/schedule/schedule_screen_test.dart
expected: After creating or moving a booking, an undo snackbar appears at the bottom for 5 seconds. Tapping "Undo" reverses the booking action — the booking is removed (or moved back) and the job reappears in the unscheduled drawer if applicable.
result: [pending]

### 14. Overdue Panel and Bottom Nav Badge
automated: true
test_file: mobile/test/widget/features/schedule/overdue_panel_test.dart
expected: If there are overdue jobs, the Schedule tab in the bottom navigation shows a red Badge with the overdue count — visible from any tab. Tapping the overdue badge in the calendar header opens an expandable panel listing overdue jobs sorted by severity (critical first, then warning). Each item shows severity color (red for critical, orange for warning), days overdue count, latest delay reason if any, and action buttons (View Job, Contact Contractor).
result: [pending]

### 15. Delay Justification Dialog
automated: true
test_file: mobile/test/widget/features/schedule/delay_dialog_test.dart
expected: On a scheduled or in-progress job, tap "Report Delay". A dialog appears with: a required reason text field, a required new ETA date picker, and Submit/Cancel buttons. The dialog cannot be dismissed by tapping outside (barrierDismissible=false). Submitting with empty reason or no ETA shows validation errors. Valid submission saves the delay report offline via Drift.
result: [pending]

### 16. Job Detail Report Delay Button
automated: true
test_file: mobile/test/widget/features/schedule/booking_card_interactions_test.dart
expected: Open a job detail screen for a job with "scheduled" or "in_progress" status. A "Report Delay" button appears in the bottom navigation bar. Tapping it opens the delay justification dialog. After submitting a delay, the History tab on the job detail screen shows the delay entry with a distinct icon (schedule_send), red color, and the new ETA date.
result: [pending]

### 17. Contractor Personal Schedule
automated: true
test_file: mobile/test/widget/features/schedule/contractor_schedule_screen_test.dart
expected: Log in as a contractor role user. The Schedule tab shows a personal schedule screen (not the admin dispatch calendar). It offers two view modes via toggle: a date-grouped list view and a single-lane calendar view. Overdue job prompts appear if applicable. A "Report Delay" button is available. Pull-to-refresh syncs data.
result: [pending]

### 18. Schedule Settings Screen
automated: true
test_file: mobile/test/widget/features/schedule/schedule_settings_screen_test.dart
expected: Navigate to Schedule Settings (via contractor gear icon or admin long-press on contractor header). A form shows 7 day rows (Mon-Sun) with working/off toggle for each day, and start/end time pickers for working days. A "Copy to weekdays" action copies the current row's times to all weekdays. Save sends a PATCH to the scheduling API. An offline banner appears if there's no network connectivity.
result: [pending]

### 19. Backend Delay Endpoint
automated: true
test_file: backend/tests/test_delay_endpoint.py
expected: Send a PATCH request to /jobs/{id}/delay with a valid body (reason, new_eta, version). The endpoint returns the updated job with the delay recorded in status_history and scheduled_completion_date updated. Sending with wrong status returns 422, version conflict returns 409, missing job returns 404.
result: [pending]

## Summary

total: 19
passed: 0
issues: 0
pending: 19
skipped: 0

## Gaps

[none yet]
