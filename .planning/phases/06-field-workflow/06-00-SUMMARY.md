---
phase: 06-field-workflow
plan: "00"
subsystem: testing
tags: [flutter, pytest, drift, wave-0, test-stubs, field-workflow]

# Dependency graph
requires:
  - phase: 05-calendar-and-dispatch-ui
    provides: existing test patterns and widget test infrastructure

provides:
  - 12 Flutter Wave 0 test stubs for notes, GPS, drawing, and timer features
  - 1 backend Wave 0 test stub covering all FIELD-01 through FIELD-04 requirements
  - test/unit/features/jobs/ directory created for future unit test targets
  - Nyquist compliance: every Wave 1-2 implementation plan has a ready verify target

affects: [06-01, 06-02, 06-03, 06-04, 06-05, 06-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 stub pattern: skip: 'Wave 0 stub — implementation in plan 06-XX' with plan reference"
    - "Backend stub pattern: @pytest.mark.skip(reason='Wave 0 stub — ...') with docstring"

key-files:
  created:
    - mobile/test/unit/features/jobs/note_dao_test.dart
    - mobile/test/unit/features/jobs/attachment_dao_test.dart
    - mobile/test/unit/features/jobs/gps_capture_test.dart
    - mobile/test/unit/features/jobs/drawing_save_test.dart
    - mobile/test/unit/features/jobs/time_entry_dao_test.dart
    - mobile/test/unit/features/jobs/timer_notifier_test.dart
    - mobile/test/widget/features/jobs/add_note_bottom_sheet_test.dart
    - mobile/test/widget/features/jobs/notes_tab_test.dart
    - mobile/test/widget/features/jobs/gps_capture_widget_test.dart
    - mobile/test/widget/features/jobs/gps_overwrite_dialog_test.dart
    - mobile/test/widget/features/jobs/drawing_pad_screen_test.dart
    - mobile/test/widget/features/jobs/timer_screen_test.dart
    - backend/tests/test_field_workflow.py
  modified: []

key-decisions:
  - "Wave 0 stub naming includes target plan number for traceability (e.g., 'plan 06-02')"
  - "Backend stubs reference compound plan ranges (06-01/06-06) when tests span multiple plans"

patterns-established:
  - "Flutter skip string: skip: 'Wave 0 stub — implementation in plan 06-XX'"
  - "Backend skip string: @pytest.mark.skip(reason='Wave 0 stub — implementation in plan 06-XX')"
  - "Each stub group describes exact behavior with '# Will test:' comments"

requirements-completed: [FIELD-01, FIELD-02, FIELD-03, FIELD-04]

# Metrics
duration: 2min
completed: 2026-03-11
---

# Phase 6 Plan 00: Field Workflow Wave 0 Test Stubs Summary

**13 Wave 0 test stub files (12 Flutter + 1 backend) giving every field workflow implementation task a ready-to-run verify target before a single line of production code is written**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-11T23:13:22Z
- **Completed:** 2026-03-11T23:15:55Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments

- Created `test/unit/features/jobs/` directory and 6 unit test stubs (NoteDao, AttachmentDao, GpsCapture, DrawingSave, TimeEntryDao, TimerNotifier)
- Created 6 widget test stubs in existing `test/widget/features/jobs/` dir (AddNoteBottomSheet, NotesTab, GpsCaptureWidget, GpsOverwriteDialog, DrawingPadScreen, TimerScreen)
- Created backend integration test stub with 14 skipped tests covering all FIELD-01 through FIELD-04 requirements

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Flutter test stubs (12 files)** - `ee46647` (test)
2. **Task 2: Create backend test stub file** - `51cf5c4` (test)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `mobile/test/unit/features/jobs/note_dao_test.dart` - NoteDao stubs: insert/watch/soft-delete
- `mobile/test/unit/features/jobs/attachment_dao_test.dart` - AttachmentDao stubs: insert/pending/markUploaded
- `mobile/test/unit/features/jobs/gps_capture_test.dart` - GPS store/permission stubs
- `mobile/test/unit/features/jobs/drawing_save_test.dart` - PNG export/Navigator.pop stubs
- `mobile/test/unit/features/jobs/time_entry_dao_test.dart` - clockIn/auto-close/clockOut stubs
- `mobile/test/unit/features/jobs/timer_notifier_test.dart` - restore/start/stop timer stubs
- `mobile/test/widget/features/jobs/add_note_bottom_sheet_test.dart` - render/validate/save stubs
- `mobile/test/widget/features/jobs/notes_tab_test.dart` - list/empty-state/FAB stubs
- `mobile/test/widget/features/jobs/gps_capture_widget_test.dart` - button/coordinates/address stubs
- `mobile/test/widget/features/jobs/gps_overwrite_dialog_test.dart` - dialog confirm/cancel stubs
- `mobile/test/widget/features/jobs/drawing_pad_screen_test.dart` - toolbar/colors/grid stubs
- `mobile/test/widget/features/jobs/timer_screen_test.dart` - display/button/history stubs
- `backend/tests/test_field_workflow.py` - 14 skipped integration tests

## Decisions Made

- Wave 0 stub naming includes target plan number for traceability (e.g., "plan 06-02") so implementors know exactly which plan will fill each stub
- Backend stubs reference compound plan ranges (06-01/06-06) when tests span multiple implementation plans

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 13 test stub files exist and skip cleanly (zero failures)
- Wave 1 plans (06-01 through 06-05) can now reference these files in their `<verify>` steps
- Wave 2 plan (06-06) sync tests also have ready stubs
- No blockers for Wave 1 execution

---
*Phase: 06-field-workflow*
*Completed: 2026-03-11*

## Self-Check: PASSED

All 13 stub files confirmed present on disk. Commits ee46647 and 51cf5c4 confirmed in git log.
