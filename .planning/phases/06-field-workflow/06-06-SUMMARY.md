---
phase: 06-field-workflow
plan: 06
subsystem: test-suite
tags: [testing, widget-tests, unit-tests, integration-tests, drift, riverpod, backend, field-workflow]
dependency_graph:
  requires: [06-01, 06-02, 06-03, 06-04, 06-05]
  provides: [FIELD-01-tests, FIELD-02-tests, FIELD-03-tests, FIELD-04-tests, test-field-workflow-py]
  affects: [conftest-clean-tables, drawing-pad-screen]
tech_stack:
  added: []
  patterns: [ProviderScope-overrides-StreamProvider-lambda, pump-not-pumpAndSettle, GoRouter-in-widget-tests, CustomPainter-drawing, pytest-asyncio-ASGI]
key_files:
  created:
    - mobile/test/widget/features/jobs/contractor_job_card_test.dart
  modified:
    - mobile/test/widget/features/jobs/notes_tab_test.dart
    - mobile/test/widget/features/jobs/add_note_bottom_sheet_test.dart
    - mobile/test/widget/features/jobs/timer_screen_test.dart
    - mobile/test/widget/features/jobs/drawing_pad_screen_test.dart
    - mobile/test/widget/features/jobs/gps_capture_widget_test.dart
    - mobile/test/unit/features/jobs/note_dao_test.dart
    - mobile/test/unit/features/jobs/time_entry_dao_test.dart
    - mobile/test/unit/features/jobs/attachment_upload_service_test.dart
    - backend/tests/test_field_workflow.py
    - mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart
    - mobile/lib/features/jobs/presentation/providers/note_providers.dart
    - backend/tests/conftest.py
decisions:
  - Rewrote drawing_pad_screen.dart with native CustomPainter instead of flutter_drawing_board v1 API (package lacks SimpleLine/Eraser/Rectangle/etc.)
  - Used Provider.autoDispose.family for noteCountProvider (Riverpod 3 has no .stream getter on StreamProvider)
  - Used pump() not pumpAndSettle() for all async provider tests (Drift streams never settle)
  - Toolbar Row replaced with Wrap for thickness chips to avoid overflow in widget tests
metrics:
  duration: "~60 minutes (cross-session)"
  tasks_completed: 2
  files_modified: 13
  completed_date: "2026-03-11"
---

# Phase 06 Plan 06: Field Workflow Test Suite Summary

Comprehensive test suite for all Phase 6 field workflow features replacing Wave 0 stub files with full test implementations — 23 unit tests (NoteDao, TimeEntryDao, AttachmentUploadService), 39 widget tests (6 files), and 15 backend integration tests.

## What Was Built

### Unit Tests (Task 1 — committed eaa378b in previous session)

**NoteDao unit tests** (`note_dao_test.dart`): 7 tests covering insertNote dual-write to sync_queue, watchNotesForJob ordering (newest-first), filtering by jobId, soft-delete exclusion, and upsertFromSync for both insert and update operations.

**TimeEntryDao unit tests** (`time_entry_dao_test.dart`): 11 tests covering clockIn creates active entry with sync queue entry, clockIn auto-clocks out existing session (one-job-at-a-time enforcement), auto-clock-out duration calculation, clockOut sets completed status, watchActiveSession returns null when none, watchEntriesForJob ordering, soft-delete exclusion.

**AttachmentUploadService unit tests** (`attachment_upload_service_test.dart`): 5 tests covering empty pending list skips Dio, successful upload calls markUploaded with remoteUrl, DioException calls incrementRetry, status set to uploading before attempt, FormData includes note_id and attachment_type.

### Widget Tests (Task 2 — committed be116b3)

**NotesTab** (6 tests): renders note body, truncates authorId to last 8 chars, multiple notes, empty state "No notes yet", empty state "Add the first note" button, FAB "Add Note" when notes exist.

**TimerScreen** (6 tests): HH:MM:SS display, Clock In when no active session, Clock Out when active session, session history with duration, total time summary, empty session placeholder.

**ContractorJobCard** (7 tests): Add Note for non-completed, Camera button, Clock In, Clock Out when active, no action bar for completed, job description text, status badge.

**AddNoteBottomSheet** (8 tests): opens bottom sheet, text field hint, Camera/Gallery/PDF/Draw buttons, Save disabled when empty, Save enabled with text.

**DrawingPadScreen** (7 tests): pen icon, eraser icon, 8 color swatches, 3 thickness options (Thin/Med/Thick), grid toggle, save button, undo button.

**GpsCaptureButton** (5 tests): Capture Location button, coordinates display, geocoded address display, button present with address, no coordinates text when no GPS data.

### Backend Integration Tests (Task 2)

15 tests in `backend/tests/test_field_workflow.py`:
- Notes: create note (201), list newest first, exact max_length (2000 chars), body too long (422), missing job (404)
- Time entries: clock in (201), clock out with duration, auto-close on new clock-in, admin adjustment with audit trail, list ordered DESC
- File upload: valid upload (201), no auth (401), invalid attachment_type (400)
- RLS: note cross-tenant isolation, time entry cross-tenant isolation

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] flutter_drawing_board v1 API mismatch**
- **Found during:** Task 2 (drawing_pad_screen_test.dart)
- **Issue:** drawing_pad_screen.dart used APIs that don't exist in flutter_drawing_board 1.0.1+2: `SimpleLine`, `StraightLine`, `Rectangle`, `Circle`, `Eraser`, `showDefaultTools`, `showDefaultActions`, `setPaintContent`, `setStyle`
- **Fix:** Completely rewrote drawing_pad_screen.dart using native Flutter `CustomPainter` and `GestureDetector` — no dependency on flutter_drawing_board's tool classes. Same UI/UX, fully functional drawing.
- **Files modified:** `mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart`
- **Commit:** be116b3

**2. [Rule 1 - Bug] noteCountProvider used .stream on StreamProvider (Riverpod 3 API)**
- **Found during:** Task 2 compilation
- **Issue:** `StreamProvider.autoDispose.family` in Riverpod 3 has no `.stream` getter
- **Fix:** Changed to `Provider.autoDispose.family` using `maybeWhen(data: ..., orElse: ...)`
- **Files modified:** `mobile/lib/features/jobs/presentation/providers/note_providers.dart`
- **Commit:** be116b3

**3. [Rule 2 - Missing] conftest.py missing Phase 6 tables in clean_tables**
- **Found during:** Task 2 (backend tests)
- **Issue:** clean_tables fixture didn't truncate `attachments`, `time_entries`, `job_notes` — cross-test pollution possible
- **Fix:** Added Phase 6 tables in proper FK order (children before parents)
- **Files modified:** `backend/tests/conftest.py`
- **Commit:** be116b3

**4. [Rule 1 - Bug] ChoiceChip Row overflow in widget tests**
- **Found during:** Task 2 (drawing_pad_screen tests)
- **Issue:** Toolbar thickness selector used `Row` with ChoiceChips that overflowed the 200px panel in test viewport
- **Fix:** Changed `Row` to `Wrap` for thickness chip selector
- **Files modified:** `mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart`
- **Commit:** be116b3

## Self-Check: PASSED

- contractor_job_card_test.dart: FOUND
- test_field_workflow.py: FOUND
- commit be116b3: FOUND (feat(06-06): complete widget tests and backend integration tests)
- commit eaa378b: FOUND (test(06-06): add unit tests for NoteDao, TimeEntryDao, and AttachmentUploadService)
