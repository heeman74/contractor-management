---
phase: 22-task-execution-and-photo-annotation
plan: "02"
subsystem: mobile-data-layer
tags: [drift, dao, offline-sync, riverpod, flutter]
dependency_graph:
  requires: []
  provides: [task-note-dao, task-attachment-dao, my-tasks-query, task-providers, task-routes]
  affects: [mobile-task-execution-ui, contractor-my-tasks-screen, photo-annotation-screen]
tech_stack:
  added: [TaskNoteDao, TaskAttachmentDao, TaskNotes Drift table]
  patterns: [transactional-outbox-dual-write, drift-in-memory-dao-tests, riverpod-family-stream-providers]
key_files:
  created:
    - mobile/lib/core/database/tables/task_notes.dart
    - mobile/lib/features/projects/data/task_note_dao.dart
    - mobile/lib/features/projects/data/task_attachment_dao.dart
    - mobile/test/features/projects/task_note_dao_test.dart
    - mobile/test/features/projects/task_attachment_dao_test.dart
  modified:
    - mobile/lib/core/database/tables/task_attachments.dart
    - mobile/lib/core/database/app_database.dart
    - mobile/lib/features/projects/data/task_dao.dart
    - mobile/lib/features/projects/presentation/providers/project_providers.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/core/di/service_locator.dart
decisions:
  - "TaskNoteDao uses transactional outbox (same as NoteDao/TaskDao) — dual-write to task_notes + sync_queue atomically"
  - "TaskAttachmentDao follows sync queue pattern (unlike AttachmentDao for job photos which uses binary upload service) — task attachments sync via standard outbox"
  - "annotationData column is nullable text on TaskAttachments — non-destructive JSON overlay, base photo never modified"
  - "watchTasksForContractor uses status.isNotIn(['complete']) not status.equals('not_started') — catches in_progress and blocked tasks too"
  - "TaskNoteDao and TaskAttachmentDao registered in service_locator.dart under Phase 22 section for explicit DI"
  - "Test files placed at mobile/test/features/projects/ per plan frontmatter spec (not unit/features/ pattern)"
metrics:
  duration: "~12 minutes"
  completed_date: "2026-03-24"
  tasks_completed: 2
  files_modified: 11
---

# Phase 22 Plan 02: Mobile Drift Data Layer for Task Execution Summary

Drift schema v10 with TaskNotes table and annotationData on TaskAttachments. TaskNoteDao and TaskAttachmentDao with full CRUD and transactional sync queue dual-write. Cross-scope contractor task query in TaskDao. Six Riverpod stream providers. Three route constants. All 10 in-memory DAO tests pass.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Drift schema v10 — TaskNotes table + annotationData column + DAOs | `80f94c5` | task_notes.dart, task_attachments.dart, app_database.dart, task_note_dao.dart, task_attachment_dao.dart, app_database.g.dart |
| 2 | Cross-scope TaskDao query + providers + routes + DAO tests | `43c90ac` | task_dao.dart, project_providers.dart, route_names.dart, service_locator.dart, task_note_dao_test.dart, task_attachment_dao_test.dart |

## What Was Built

### Drift Schema v10

**New table: `task_notes`** — mirrors `job_notes` pattern exactly:
- `id`, `companyId` (FK Companies), `taskId` (FK ProjectTasks), `authorId` (soft FK), `body`, `version`, timestamps, soft-delete

**New column: `task_attachments.annotationData`** — nullable TEXT:
- Stores photo annotation overlays as JSON (arrows, circles, text, measurements)
- Non-destructive: base photo in `localPath`/`remoteUrl` is never modified
- Added via migration `m.addColumn(taskAttachments, taskAttachments.annotationData)` in schema v9→v10

**Migration v9→v10:**
```dart
if (from < 10) {
  await m.createTable(taskNotes);
  await m.addColumn(taskAttachments, taskAttachments.annotationData);
}
```

### TaskNoteDao

Located at: `mobile/lib/features/projects/data/task_note_dao.dart`

- `watchByTask(taskId)` — Stream, ordered by `createdAt DESC`, excludes soft-deleted
- `countByTask(taskId)` — count of active notes for badge display
- `insertNote(entry)` — transaction: insert note + CREATE sync queue entry (`entityType: 'task_note'`)
- `deleteNote(id)` — transaction: set `deletedAt` + DELETE sync queue entry

### TaskAttachmentDao

Located at: `mobile/lib/features/projects/data/task_attachment_dao.dart`

- `watchByTask(taskId)` — Stream, ordered by `sortOrder ASC`, excludes soft-deleted
- `watchCountByTask(taskId)` — reactive count stream for photo gate
- `watchPhotoCountByTask(taskId)` — count only `attachmentType='photo'`
- `watchDocCountByTask(taskId)` — count only `attachmentType='document'`
- `insertAttachment(entry)` — transaction: insert + CREATE sync queue entry
- `updateAnnotation(id, json)` — transaction: update `annotationData`+`updatedAt` + UPDATE sync queue entry
- `deleteAttachment(id)` — transaction: soft-delete + DELETE sync queue entry

### TaskDao extensions

- `watchTasksForContractor(userId)` — cross-scope stream: all incomplete tasks assigned to user, ordered by priority (urgent=0/high=1/medium=2/low=3) then `dueDate ASC`
- `watchTasksByScopeWithStatus(tradeScopeId)` — same as `watchTasksByScope` but includes completed tasks for GC read-only view

### Riverpod Providers

Added to `project_providers.dart`:
- `taskNoteDaoProvider` — Provider<TaskNoteDao>
- `taskAttachmentDaoProvider` — Provider<TaskAttachmentDao>
- `myTasksProvider` — StreamProvider.family<List<ProjectTask>, String>(userId)
- `taskNotesProvider` — StreamProvider.family<List<TaskNote>, String>(taskId)
- `taskAttachmentsProvider` — StreamProvider.family<List<TaskAttachment>, String>(taskId)
- `taskPhotoCountProvider` — StreamProvider.family<int, String>(taskId)
- `taskDocCountProvider` — StreamProvider.family<int, String>(taskId)

### Route Constants

Added to `RouteNames`:
- `myTasks = '/my-tasks'` — contractor cross-scope checklist
- `taskDetail = '/tasks/:taskId'` — task detail screen
- `photoAnnotation = '/tasks/:taskId/photos/:attachmentId/annotate'` — annotation screen
- `taskDetailPath(taskId)` helper
- `photoAnnotationPath(taskId, attachmentId)` helper

## Verification Results

- `dart run build_runner build --delete-conflicting-outputs` — clean (wrote 445 outputs)
- `dart analyze lib/core/database/ lib/features/projects/data/` — 6 info items, all pre-existing, no errors
- `flutter test test/features/projects/task_note_dao_test.dart test/features/projects/task_attachment_dao_test.dart` — **10/10 tests pass**

### Test Coverage

**task_note_dao_test.dart (5 tests):**
1. insertNote creates note and sync queue entry (entityType=task_note, operation=CREATE)
2. watchByTask returns notes ordered by createdAt DESC (newest first)
3. deleteNote soft-deletes note and creates DELETE sync queue entry
4. watchByTask filters by taskId (notes for other tasks not returned)
5. watchByTask excludes soft-deleted notes

**task_attachment_dao_test.dart (5 tests):**
1. insertAttachment creates record and sync queue entry (entityType=task_attachment)
2. watchByTask returns attachments ordered by sortOrder ASC
3. updateAnnotation stores JSON and creates UPDATE sync queue entry
4. watchPhotoCountByTask counts only photo-type attachments
5. deleteAttachment soft-deletes and creates DELETE sync queue entry

## Decisions Made

1. **TaskNoteDao uses transactional outbox (not binary upload service)** — task notes are text-only, so the same dual-write outbox pattern as `NoteDao`/`TaskDao` is correct.

2. **TaskAttachmentDao uses sync queue outbox** — unlike `AttachmentDao` for job photos (which uses binary upload service), task attachments sync via standard outbox to keep the data layer simple for this phase. Binary upload can be added in a later phase.

3. **`annotationData` is nullable TEXT** — non-destructive JSON overlay storage. Null until user annotates. Matches v3.0 decision: "Annotation storage is non-destructive (base photo immutable; annotation JSON in separate JSONB column)".

4. **`watchTasksForContractor` uses `isNotIn(['complete'])`** — catches tasks in `in_progress`, `not_started`, and `blocked` states, not just `not_started`. This ensures the contractor's My Tasks checklist shows all actionable work.

5. **DAOs registered under "Phase 22" comment** in `service_locator.dart` — keeps DI wiring organized by phase for maintainability.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- [x] `mobile/lib/core/database/tables/task_notes.dart` — exists
- [x] `mobile/lib/core/database/tables/task_attachments.dart` — annotationData present
- [x] `mobile/lib/core/database/app_database.dart` — schemaVersion 10, TaskNoteDao/TaskAttachmentDao registered
- [x] `mobile/lib/features/projects/data/task_note_dao.dart` — exists, watchByTask present
- [x] `mobile/lib/features/projects/data/task_attachment_dao.dart` — exists, watchPhotoCountByTask + updateAnnotation present
- [x] `mobile/lib/features/projects/data/task_dao.dart` — watchTasksForContractor present
- [x] `mobile/lib/features/projects/presentation/providers/project_providers.dart` — myTasksProvider + 4 new providers present
- [x] `mobile/lib/core/routing/route_names.dart` — myTasks, taskDetail, photoAnnotation routes present
- [x] Commits `80f94c5` and `43c90ac` exist in git log
- [x] 10/10 DAO tests pass
