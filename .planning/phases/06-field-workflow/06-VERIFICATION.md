---
phase: 06-field-workflow
verified: 2026-03-11T00:00:00Z
status: passed
score: 5/5 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Open the Notes tab on a job detail screen, add a note with a photo while in airplane mode, then reconnect and verify the note body and photo both appear on the backend"
    expected: "Note body syncs immediately; photo uploads after text sync is complete with progress shown in app bar subtitle (e.g. '1 items synced, 1 photos uploading (0/1)')"
    why_human: "Offline-to-online sync flow and file upload progress require a running app with a real backend and network toggle"
  - test: "Open the Drawing Pad from the Add Note bottom sheet, draw a sketch, tap Save, and verify the PNG appears as an attachment thumbnail in the note"
    expected: "PNG saved, bottom sheet shows thumbnail, attachment uploads on next sync"
    why_human: "Flutter CustomPainter rendering and PNG export cannot be meaningfully exercised by widget tests alone"
  - test: "On the job detail Details tab, tap Capture Location with an existing GPS address already set"
    expected: "Confirm dialog 'Replace existing address?' appears before the new coordinates are stored"
    why_human: "Permission dialogs and geolocation require a real device or emulator with location services"
  - test: "On the contractor job list, clock in to Job A, then clock in to Job B"
    expected: "Job A auto-clocks out (shown as completed), Job B becomes the active pinned card with elapsed timer"
    why_human: "One-job-at-a-time pinning and live elapsed timer on real job cards require a running app"
---

# Phase 6: Field Workflow Verification Report

**Phase Goal:** Contractors can capture job notes, photos, GPS location, sketches, and time on-site from their mobile device — all while offline — and the data syncs when connectivity returns
**Verified:** 2026-03-11
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Contractor can add a timestamped text note to a job while offline; it syncs to the backend when connectivity is restored | VERIFIED | `NoteDao.insertNote` transactional dual-write to `job_notes` + `sync_queue`. `NoteSyncHandler` pushes to `POST /api/v1/jobs/{job_id}/notes`. `SyncEngine` drains queue on reconnect. Backend `create_note` endpoint and 7 DAO unit tests confirmed. |
| 2 | Contractor can take a photo from the job screen; it uploads to cloud storage and appears in the job record accessible to admins and the client | VERIFIED | `AttachmentUploadService.uploadPending()` posts to `POST /api/v1/files/upload` (aiofiles write confirmed). `AttachmentDao` tracks `uploadStatus` lifecycle. `SyncEngine` calls `uploadPending()` after `drainQueue()` (text-first). Backend stores to `uploads/attachments/{note_id}/` and serves via `StaticFiles` at `/files/`. 5 upload service unit tests confirmed. |
| 3 | Contractor can capture the job site address using GPS — the device location populates the address field without manual typing | VERIFIED | `GpsCaptureButton` widget uses `Geolocator.isLocationServiceEnabled()`, `Geolocator.checkPermission()`, `Geolocator.getCurrentPosition()`. On success calls `JobDao.updateJobGps()` (GPS columns exist on Drift `jobs` table). Backend `update_job_gps()` reverse-geocodes via `ORSGeocodingProvider` on sync. Android manifest has `ACCESS_FINE_LOCATION` and `ACCESS_COARSE_LOCATION` permissions. `GpsCaptureButton` wired into `job_detail_screen.dart` at line 303. |
| 4 | Contractor can open a drawing/handwriting pad, sketch a site layout or handwritten note, and save it to the job record | VERIFIED | `DrawingPadScreen` exists with native `CustomPainter` + `GestureDetector` (flutter_drawing_board v1 API incompatible — SUMMARY documents rewrite decision). 8 preset colors, 3 thickness presets, grid toggle, undo. `RepaintBoundary` key captures canvas for PNG export. Route registered at `/drawing-pad` in GoRouter (`RouteNames.drawingPad`). Orientation lock/restore via `SystemChrome`. 7 drawing pad widget tests confirmed. |
| 5 | Contractor can clock in and out per job; the time tracking record is stored locally and syncs with a precise duration | VERIFIED | `TimeEntryDao.clockIn/clockOut` with transactional outbox. `TimerNotifier.build()` restores active session from Drift on app restart. `TimerScreen` shows HH:MM:SS elapsed. One-job-at-a-time enforced in DAO layer (11 unit tests). `TimeEntrySyncHandler` pushes to `POST /api/v1/jobs/{job_id}/time-entries`. Timer route registered at `/timer/:jobId`. 6 timer screen widget tests confirmed. |

**Score:** 5/5 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `backend/migrations/versions/0009_field_workflow_tables.py` | job_notes, attachments, time_entries tables + GPS columns | VERIFIED | Exists, substantive |
| `backend/app/features/files/router.py` | File upload endpoint | VERIFIED | `upload_attachment` endpoint with `aiofiles.open` write confirmed at line 102 |
| `backend/app/features/jobs/router.py` | Note and time entry REST endpoints | VERIFIED | `create_note` at line 538, `create_time_entry` at line 576 |
| `backend/app/features/sync/schemas.py` | SyncResponse with new entity lists | VERIFIED | `job_notes`, `time_entries`, `attachments` with `default=[]` at lines 76-78 |
| `mobile/lib/core/database/tables/job_notes.dart` | JobNotes Drift table | VERIFIED | Exists with correct columns |
| `mobile/lib/core/database/tables/attachments.dart` | Attachments Drift table | VERIFIED | Exists with `uploadStatus`, `localPath`, `remoteUrl` |
| `mobile/lib/core/database/tables/time_entries.dart` | TimeEntries Drift table | VERIFIED | Exists with `clockedInAt`, `clockedOutAt`, `durationSeconds`, `sessionStatus` |
| `mobile/lib/features/jobs/data/note_dao.dart` | NoteDao with sync queue dual-write | VERIFIED | `_$NoteDaoMixin` pattern, transactional `insertNote` + `watchNotesForJob` |
| `mobile/lib/features/jobs/data/time_entry_dao.dart` | TimeEntryDao with active session management | VERIFIED | `clockIn` auto-closes existing session, one-job-at-a-time invariant enforced |
| `mobile/lib/core/sync/handlers/note_sync_handler.dart` | NoteSyncHandler | VERIFIED | `entityType = 'job_note'`, push/pull wired |
| `mobile/lib/core/sync/handlers/time_entry_sync_handler.dart` | TimeEntrySyncHandler | VERIFIED | Confirmed in service_locator.dart registration |
| `mobile/lib/features/jobs/presentation/widgets/notes_tab.dart` | Notes tab | VERIFIED | Watches `notesForJobProvider`, renders NoteEntity list, wired into `job_detail_screen.dart` tab 3 |
| `mobile/lib/features/jobs/presentation/widgets/add_note_bottom_sheet.dart` | Add Note bottom sheet | VERIFIED | Camera/gallery/PDF/drawing buttons, text field, `NoteDao.insertNote` on save |
| `mobile/lib/features/jobs/presentation/services/attachment_upload_service.dart` | Attachment upload with retry | VERIFIED | `getPendingUploads` + `markUploaded` pattern confirmed |
| `mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart` | Drawing pad screen | VERIFIED | Native CustomPainter, 8 colors, 3 thicknesses, grid toggle, PNG export via `RepaintBoundary` |
| `mobile/lib/features/jobs/presentation/widgets/gps_capture_button.dart` | GPS capture button | VERIFIED | `Geolocator.checkPermission/getCurrentPosition`, `updateJobGps` call, wired into job detail |
| `mobile/lib/features/jobs/presentation/screens/timer_screen.dart` | Timer screen | VERIFIED | HH:MM:SS display, clock in/out, session history, total time |
| `mobile/lib/features/jobs/presentation/providers/timer_providers.dart` | TimerNotifier | VERIFIED | `AsyncNotifier`, `watchActiveSession` restores on restart, `Timer.periodic` tick |
| `mobile/lib/features/jobs/presentation/widgets/time_tracked_section.dart` | Time tracked section | VERIFIED | File exists, wired into Schedule tab |
| `mobile/lib/features/jobs/presentation/widgets/contractor_job_card.dart` | Contractor job card with action bar | VERIFIED | `timerNotifierProvider` watched, Add Note/Camera/Clock In/Out buttons |
| `mobile/test/unit/features/jobs/note_dao_test.dart` | NoteDao unit tests | VERIFIED | 7 tests, no skip markers, in-memory Drift, dual-write and ordering covered |
| `mobile/test/unit/features/jobs/time_entry_dao_test.dart` | TimeEntryDao unit tests | VERIFIED | 11 tests, no skip markers, one-job-at-a-time explicitly tested |
| `mobile/test/unit/features/jobs/attachment_upload_service_test.dart` | Upload service tests | VERIFIED | 5 tests, MockDio, retry logic covered |
| `mobile/test/widget/features/jobs/notes_tab_test.dart` | Notes tab widget tests | VERIFIED | 6 tests, ProviderScope overrides, pump() not pumpAndSettle() |
| `mobile/test/widget/features/jobs/timer_screen_test.dart` | Timer screen widget tests | VERIFIED | 6 tests, stub TimerNotifier, HH:MM:SS display and button states covered |
| `mobile/test/widget/features/jobs/contractor_job_card_test.dart` | Contractor card widget tests | VERIFIED | 7 tests including active state, completed state, action bar |
| `backend/tests/test_field_workflow.py` | Backend integration tests | VERIFIED | 15 tests, no skip markers, RLS cross-tenant isolation tested |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `backend/app/features/files/router.py` | uploads/ directory | `aiofiles.open` | WIRED | `aiofiles.open(dest_path, "wb")` at line 102 |
| `backend/app/features/jobs/router.py` | `backend/app/features/jobs/service.py` | `service.create_note` / `service.create_time_entry` | WIRED | `svc.create_note(...)` at line 550, `svc.create_time_entry(...)` at line 591 |
| `mobile/lib/features/jobs/data/note_dao.dart` | `mobile/lib/core/database/tables/job_notes.dart` | Drift DAO mixin | WIRED | `_$NoteDaoMixin` pattern confirmed |
| `mobile/lib/core/sync/sync_registry.dart` | `mobile/lib/core/sync/handlers/note_sync_handler.dart` | handler registration | WIRED | `registry.register(NoteSyncHandler(dioClient, db))` at service_locator.dart line 62 |
| `mobile/lib/core/sync/sync_registry.dart` | `mobile/lib/core/sync/handlers/time_entry_sync_handler.dart` | handler registration | WIRED | `registry.register(TimeEntrySyncHandler(dioClient, db))` at service_locator.dart line 63 |
| `mobile/lib/features/jobs/presentation/widgets/notes_tab.dart` | `mobile/lib/features/jobs/data/note_dao.dart` | StreamProvider watching notes | WIRED | `noteDao.watchNotesForJob(jobId)` in `note_providers.dart` line 44 |
| `mobile/lib/features/jobs/presentation/services/attachment_upload_service.dart` | `mobile/lib/features/jobs/data/attachment_dao.dart` | `getPendingUploads` + `markUploaded` | WIRED | `_attachmentDao.getPendingUploads()` at line 56, `_attachmentDao.markUploaded(...)` at line 180 |
| `mobile/lib/features/jobs/presentation/screens/job_detail_screen.dart` | `mobile/lib/features/jobs/presentation/widgets/notes_tab.dart` | TabBarView child | WIRED | `NotesTab(...)` at line 157 |
| `mobile/lib/core/sync/sync_status_provider.dart` | `mobile/lib/features/jobs/presentation/services/attachment_upload_service.dart` | upload progress stream | WIRED | `uploadTotal`/`uploadCompleted` merged into SyncStatus at lines 79-80, `_UploadEvent` at line 142 |
| `mobile/lib/features/jobs/presentation/screens/drawing_pad_screen.dart` | native CustomPainter | `RepaintBoundary` PNG export | WIRED | `flutter_drawing_board` v1 API incompatible — rewritten with CustomPainter (SUMMARY 06-06 decision 1). Same UX contract met. |
| `mobile/lib/features/jobs/presentation/widgets/gps_capture_button.dart` | `geolocator` | `Geolocator.checkPermission` + `getCurrentPosition` | WIRED | `checkPermission` at line 56, `getCurrentPosition` at line 150 |
| `mobile/lib/features/jobs/presentation/widgets/gps_capture_button.dart` | `mobile/lib/features/jobs/data/job_dao.dart` | `updateJobGps` | WIRED | `jobDao.updateJobGps(...)` at line 157 |
| `mobile/lib/features/jobs/presentation/providers/timer_providers.dart` | `mobile/lib/features/jobs/data/time_entry_dao.dart` | `clockIn`/`clockOut`/`watchActiveSession` | WIRED | `dao.watchActiveSession(contractorId)` in build(), `dao.clockIn(...)` in clockIn() at line 143 |
| `mobile/lib/features/jobs/presentation/widgets/contractor_job_card.dart` | `mobile/lib/features/jobs/presentation/providers/timer_providers.dart` | `timerNotifierProvider` | WIRED | `ref.watch(timerNotifierProvider)` at line 43 |
| `mobile/lib/features/jobs/presentation/screens/timer_screen.dart` | `mobile/lib/features/jobs/presentation/providers/timer_providers.dart` | `timerNotifierProvider` | WIRED | `ref.watch(timerNotifierProvider)` at line 64 |
| `mobile/lib/core/sync/sync_engine.dart` | `mobile/lib/features/jobs/presentation/services/attachment_upload_service.dart` | `uploadPending()` after drainQueue | WIRED | `_attachmentUploadService!.uploadPending()` at line 375 (Plan 02 TODO placeholder replaced) |

---

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| FIELD-01 | 06-01, 06-02, 06-03, 06-06 | Job notes and photo capture (timestamped, offline-capable) | SATISFIED | NoteDao dual-write, NotesTab, AddNoteBottomSheet, AttachmentUploadService, backend note endpoints, 7+6+8+5 tests |
| FIELD-02 | 06-01, 06-02, 06-04, 06-06 | GPS-based address capture for property locations | SATISFIED | GpsCaptureButton, Geolocator integration, JobDao.updateJobGps, backend reverse geocode, GPS columns in migration 0009, 5 GPS widget tests |
| FIELD-03 | 06-02, 06-04, 06-06 | Drawing/handwriting pad for sketches and handwritten notes | SATISFIED | DrawingPadScreen with native CustomPainter (flutter_drawing_board v1 API rewrite), 8 colors, 3 thicknesses, PNG export, GoRouter registration, 7 drawing pad tests |
| FIELD-04 | 06-01, 06-02, 06-05, 06-06 | Time tracking (clock in/out per job) | SATISFIED | TimeEntryDao, TimerNotifier (AsyncNotifier with session restore), TimerScreen, one-job-at-a-time enforced, backend time entry endpoints, 11+6+5 tests |

No orphaned requirements — all 4 FIELD requirements mapped to plans and verified in codebase.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `mobile/lib/core/sync/sync_engine.dart` | 138 | `AttachmentUploadService? _attachmentUploadService` nullable field (post-construction injection) | Info | By design — documented in code to break circular GetIt dependency. Not a stub. |

No blockers. No incomplete handlers. No empty returns in feature code.

---

### Notable Deviations (Documented in Summaries — Verified Acceptable)

1. **DrawingPadScreen** — Plan 06-04 specified `flutter_drawing_board` with `DrawingController`/`DrawingBoard` key link pattern. The package's v1 API was incompatible (`SimpleLine`, `Eraser`, etc. missing). The implementation was rewritten with native Flutter `CustomPainter` + `GestureDetector`. The observable behavior contract (pen, eraser, shapes, 8 colors, 3 thicknesses, grid toggle, PNG export) is fully met. 7 widget tests pass against the native implementation.

2. **noteCountProvider** — Plan 06-03 specified `StreamProvider.autoDispose.family` with `.stream` getter. Riverpod 3 removed this API. Implemented as `Provider.autoDispose.family` with `maybeWhen(data:, orElse:)`. Notes tab badge count works correctly.

3. **conftest.py** — Phase 6 tables (`attachments`, `time_entries`, `job_notes`) were missing from `clean_tables` fixture. Added in Plan 06-06 (in proper FK order). Cross-test isolation now correct.

---

### Human Verification Required

#### 1. Offline Note Sync Flow

**Test:** Put device in airplane mode. Open a job, go to Notes tab, add a note with a photo. Re-enable WiFi.
**Expected:** Note body appears immediately in UI. Sync indicator shows "1 items synced, 1 photos uploading (0/1)" then "All synced" after upload completes. Backend shows note + attachment.
**Why human:** Real network toggling, actual file upload sequence, and sync status transitions cannot be simulated in widget tests.

#### 2. Drawing Pad PNG Export to Note

**Test:** Open Add Note, tap the drawing button, sketch on the canvas, tap Save. Verify back in the Add Note sheet that a thumbnail appears.
**Expected:** PNG thumbnail visible in the pre-save attachment row. After saving, thumbnail appears inline in the note card on the Notes tab.
**Why human:** CustomPainter rendering and `RepaintBoundary.toImage()` PNG export require a real render tree.

#### 3. GPS Permission Denied Forever

**Test:** On a device where location permission is permanently denied, tap Capture Location.
**Expected:** A dialog appears explaining why GPS is needed, with an "Open Settings" button that navigates to app settings.
**Why human:** `Geolocator.deniedForever` permission state requires OS-level permission management and cannot be fully simulated in widget tests.

#### 4. One-Job-at-a-Time Clock In (Live)

**Test:** Clock in to Job A from the contractor job list. Then clock in to Job B.
**Expected:** Job A disappears from active state (shown as completed with total duration), Job B becomes the pinned card at the top with highlighted border and live elapsed timer.
**Why human:** Real Drift writes, timer provider state transitions, and card pinning/reordering require a running app.

---

## Summary

Phase 6 delivers the full field workflow capability. All 5 observable truths from the ROADMAP Success Criteria are verified: text notes (FIELD-01), photo capture with upload (FIELD-01), GPS capture (FIELD-02), drawing pad (FIELD-03), and time tracking (FIELD-04). The backend has 15 integration tests covering all endpoints with RLS. The mobile layer has 23 unit tests (DAO + upload service) and 39 widget tests across 6 screens. All key links are wired — the sync registry, DAO dual-writes, upload service integration with sync engine, and GPS/drawing routes are confirmed connected.

The one notable deviation (flutter_drawing_board v1 API rewrite to native CustomPainter) is well-documented, acceptable, and the same observable contract is met with tests passing.

4 items require human verification due to real device/network/permission state dependencies, but none of these represent structural gaps — the code paths are implemented and unit-tested.

---

_Verified: 2026-03-11_
_Verifier: Claude (gsd-verifier)_
