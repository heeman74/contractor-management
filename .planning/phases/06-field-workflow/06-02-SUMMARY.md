---
phase: 06-field-workflow
plan: 02
subsystem: mobile-data-layer
tags: [drift, flutter, sync, field-workflow, dao, migration]
dependency_graph:
  requires: [06-00]
  provides: [job-notes-table, attachments-table, time-entries-table, note-dao, attachment-dao, time-entry-dao, note-sync-handler, time-entry-sync-handler, gps-columns]
  affects: [06-03, 06-04, 06-05, 06-06]
tech_stack:
  added: [flutter_drawing_board ^1.0.1+2, geolocator ^14.0.2, flutter_image_compress ^2.4.0, file_picker ^10.3.10]
  patterns: [Drift DatabaseAccessor with mixin, Freezed entity, transactional outbox dual-write, SyncHandler push/pull]
key_files:
  created:
    - mobile/lib/core/database/tables/job_notes.dart
    - mobile/lib/core/database/tables/attachments.dart
    - mobile/lib/core/database/tables/time_entries.dart
    - mobile/lib/features/jobs/data/note_dao.dart
    - mobile/lib/features/jobs/data/attachment_dao.dart
    - mobile/lib/features/jobs/data/time_entry_dao.dart
    - mobile/lib/features/jobs/domain/note_entity.dart
    - mobile/lib/features/jobs/domain/attachment_entity.dart
    - mobile/lib/features/jobs/domain/time_entry_entity.dart
    - mobile/lib/core/sync/handlers/note_sync_handler.dart
    - mobile/lib/core/sync/handlers/time_entry_sync_handler.dart
  modified:
    - mobile/lib/core/database/tables/jobs.dart
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/features/jobs/data/job_dao.dart
    - mobile/lib/core/sync/sync_engine.dart
    - mobile/lib/core/di/service_locator.dart
    - mobile/pubspec.yaml
decisions:
  - "Attachments use dedicated binary upload service (no sync_queue text outbox) — AttachmentUploadService handles multipart upload in Plan 06-03"
  - "TimeEntryDao.clockIn auto-closes any existing active session before creating new one — one-active-session-per-contractor invariant enforced in DAO layer"
  - "GPS columns use addColumn migration (not new table) — GPS is a property of the job, not a separate entity"
  - "NoteEntity carries List<AttachmentEntity> attachments field to avoid N+1 queries in UI"
metrics:
  duration: 25min
  completed: "2026-03-11"
  tasks: 2
  files: 17
---

# Phase 6 Plan 2: Mobile Data Foundation Summary

Drift tables, DAOs, Freezed entities, and sync handlers for field workflow features (notes, attachments, time tracking, GPS). Migration v4->v5 adds three new tables and GPS columns to jobs.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Drift tables, migration v5, entities, and new dependencies | 59d4aa5 | 12 files |
| 2 | DAOs with sync queue dual-write and sync handlers | 7c0b60f | 5 files |

## What Was Built

### New Drift Tables (3)
- **JobNotes** (`job_notes.dart`): id, companyId, jobId, authorId, body, version, timestamps, soft-delete
- **Attachments** (`attachments.dart`): id, companyId, noteId, attachmentType, localPath, thumbnailPath, caption, uploadStatus, remoteUrl, sortOrder, timestamps, soft-delete
- **TimeEntries** (`time_entries.dart`): id, companyId, jobId, contractorId, clockedInAt, clockedOutAt, durationSeconds, sessionStatus, adjustmentLog, version, timestamps, soft-delete

### GPS Columns on Jobs
- `gps_latitude` (RealColumn, nullable)
- `gps_longitude` (RealColumn, nullable)
- `gps_address` (TextColumn, nullable — populated by backend reverse geocoding)

### Migration v4->v5
- Creates `job_notes`, `attachments`, `time_entries` tables
- Adds GPS columns to `jobs` table

### DAOs (3)
- **NoteDao**: `insertNote` (dual-write to job_notes + sync_queue), `watchNotesForJob` (stream newest-first), `upsertFromSync`
- **AttachmentDao**: `insertAttachment` (no sync_queue — binary upload), `getPendingUploads`, `setUploadStatus`, `markUploaded`, `incrementRetry`, `watchAttachmentsForNote`, `upsertFromSync`
- **TimeEntryDao**: `clockIn` (auto-closes existing session), `clockOut` (computes duration), `watchActiveSession`, `watchEntriesForJob`, `upsertFromSync`

### Sync Handlers (2)
- **NoteSyncHandler**: `entityType='job_note'`, POST to `/jobs/{job_id}/notes` for CREATE, PATCH for UPDATE, applyPulled upserts to jobNotes table
- **TimeEntrySyncHandler**: `entityType='time_entry'`, POST to `/jobs/{job_id}/time-entries` for CREATE, PATCH for UPDATE, applyPulled upserts to timeEntries table

### Other Changes
- `JobDao.updateJobGps()`: Updates GPS coords with gps_address=null (signals backend to geocode)
- `SyncEngine.pullDelta()`: Extended to process jobs, job_notes, time_entries, attachments from sync response
- Service locator: NoteSyncHandler, TimeEntrySyncHandler registered; NoteDao, AttachmentDao, TimeEntryDao registered in GetIt
- pubspec.yaml: flutter_drawing_board, geolocator, flutter_image_compress, file_picker added

### Freezed Entities (3)
- **NoteEntity**: with `attachments: List<AttachmentEntity>` (eager-loaded by DAO)
- **AttachmentEntity**: uploadStatus + remoteUrl lifecycle fields
- **TimeEntryEntity**: `bool get isActive => clockedOutAt == null` computed getter

## Deviations from Plan

None - plan executed exactly as written.

## Known Limitations (Pre-existing)
- All code-gen errors (missing `.g.dart` and `.freezed.dart` files) will resolve when `flutter pub get && flutter pub run build_runner build` is run — Flutter SDK not installed in this environment (STATE.md blocker)
- `RealColumn` type assignment error in `app_database.dart` addColumn calls will resolve after build_runner regenerates the Jobs table with `GeneratedColumn<double>` GPS columns

## Self-Check: PASSED

Files verified to exist:
- mobile/lib/core/database/tables/job_notes.dart: FOUND
- mobile/lib/core/database/tables/attachments.dart: FOUND
- mobile/lib/core/database/tables/time_entries.dart: FOUND
- mobile/lib/features/jobs/data/note_dao.dart: FOUND
- mobile/lib/features/jobs/data/attachment_dao.dart: FOUND
- mobile/lib/features/jobs/data/time_entry_dao.dart: FOUND
- mobile/lib/core/sync/handlers/note_sync_handler.dart: FOUND
- mobile/lib/core/sync/handlers/time_entry_sync_handler.dart: FOUND

Commits verified:
- 59d4aa5: feat(06-02): Drift tables, migration v5, entities, and new dependencies
- 7c0b60f: feat(06-02): DAOs with sync queue dual-write and sync handlers
