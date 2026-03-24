---
phase: 22-task-execution-and-photo-annotation
plan: "03"
subsystem: mobile-flutter
tags: [flutter, riverpod, drift, ui, task-execution, contractor-workflow]
dependency_graph:
  requires: [22-02]
  provides: [MyTasksScreen, TaskDetailScreen, TaskChecklistCard, TaskScopeGroupHeader, TaskNoteItem, TaskPhotoGrid]
  affects: [mobile routing, contractor task workflow]
tech_stack:
  added: [url_launcher ^6.3.1]
  patterns: [ConsumerStatefulWidget, StreamProvider.family, photo gate, transactional outbox, GoRouter push routes]
key_files:
  created:
    - mobile/lib/features/projects/presentation/screens/my_tasks_screen.dart
    - mobile/lib/features/projects/presentation/screens/task_detail_screen.dart
    - mobile/lib/features/projects/presentation/screens/task_photo_viewer_screen.dart
    - mobile/lib/features/projects/presentation/widgets/task_checklist_card.dart
    - mobile/lib/features/projects/presentation/widgets/task_scope_group_header.dart
    - mobile/lib/features/projects/presentation/widgets/task_note_item.dart
    - mobile/lib/features/projects/presentation/widgets/task_photo_grid.dart
  modified:
    - mobile/lib/core/routing/app_router.dart
    - mobile/lib/core/routing/route_names.dart
    - mobile/lib/features/projects/data/task_dao.dart
    - mobile/lib/features/projects/data/trade_scope_dao.dart
    - mobile/lib/features/projects/presentation/providers/project_providers.dart
    - mobile/pubspec.yaml
decisions:
  - "Photo gate uses AsyncValue.value (not valueOrNull) — Riverpod 3 pattern; .valueOrNull doesn't exist"
  - "scopeNameMapProvider watches all company scopes to build a scopeId→tradeName map — avoids per-task scope queries"
  - "watchTaskById added to TaskDao using watchSingleOrNull — single-task stream for TaskDetailScreen"
  - "watchAllScopesByCompany added to TradeScopeDao for company-wide scope name lookup in MyTasksScreen"
  - "TaskPhotoViewerScreen added as push route with swipe navigation and Annotate action"
  - "url_launcher added for PDF system viewer launch (File URI scheme)"
metrics:
  duration: "534s"
  completed: "2026-03-24"
  tasks: 2
  files: 13
---

# Phase 22 Plan 03: Mobile Contractor UI — Task Execution and Detail Summary

**One-liner:** Flutter contractor task workflow: MyTasksScreen (cross-scope checklist with photo gate), TaskDetailScreen (notes, photos, PDF attachments), and full GoRouter registration.

## What Was Built

### Task 1: MyTasksScreen with Grouped Checklist Cards

**TaskScopeGroupHeader** (`task_scope_group_header.dart`):
- Collapsible section header showing trade name, completed/total count, expand/collapse icon
- 48px min height, Semantics label for accessibility
- Collapse state managed in parent StatefulWidget (no Drift persistence)

**TaskChecklistCard** (`task_checklist_card.dart`):
- Priority left border (urgent=red, high=orange, medium=blue, low=grey) using IntrinsicHeight Row pattern
- Photo gate: if `task.photoRequired == true` and no photos → camera icon; otherwise checkbox
- Camera capture: ImagePicker → FlutterImageCompress → localPath → TaskAttachmentDao.insertAttachment
- Checkbox toggles status between 'complete' and 'in_progress' via TaskDao.updateTask
- Overdue amber background (`Color(0xFFFFF8E1)`) when dueDate < now
- Blocked state: lock icon, checkbox disabled
- Completed state: strikethrough title, opacity 0.7
- Priority badge chip, optional time estimate chip, "Photo required" chip

**MyTasksScreen** (`my_tasks_screen.dart`):
- ConsumerStatefulWidget watching `myTasksProvider(userId)` and `scopeNameMapProvider(companyId)`
- Groups tasks by tradeScopeId client-side, sorts within groups: overdue → priority → dueDate ASC
- Collapsible sections with `Map<String, bool>` state
- Empty state: "No tasks assigned" message
- Tapping task card navigates to `RouteNames.taskDetailPath(task.id)`

**New DAO methods:**
- `TradeScopeDao.watchAllScopesByCompany(companyId)` — company-wide scope stream
- `TaskDao.watchTaskById(id)` — single-task reactive stream using watchSingleOrNull

**New providers:**
- `scopeNameMapProvider(companyId)` — `Map<scopeId, tradeName>` for My Tasks group headers

**Routes registered:**
- `RouteNames.myTasks` → `MyTasksScreen()`
- `RouteNames.taskDetail` → `TaskDetailScreen(taskId: ...)`
- `RouteNames.taskPhotoViewer` → `TaskPhotoViewerScreen(...)`

### Task 2: TaskDetailScreen with Notes, Photos, PDF Attachments

**TaskNoteItem** (`task_note_item.dart`):
- Immutable (no edit/delete) per D-11
- Shows author label (last 8 chars of userId as "#xxxxxxxx"), relative timestamp, body text
- Divider separator between entries

**TaskPhotoGrid** (`task_photo_grid.dart`):
- 3-column GridView with square aspect ratio
- Thumbnails from localPath (File.existsSync check) or remoteUrl
- Pencil badge (CircleAvatar with edit icon) when `attachment.annotationData != null`
- Tap navigates to TaskPhotoViewerScreen with full photo list
- Empty state message

**TaskPhotoViewerScreen** (`task_photo_viewer_screen.dart`):
- Full-screen PageView with InteractiveViewer for pinch-zoom
- "Annotate" button in AppBar navigates to `RouteNames.photoAnnotationPath`
- Page index indicator in title

**TaskDetailScreen** (`task_detail_screen.dart`):
- CustomScrollView with 5 SliverToBoxAdapter sections
- Section 1 (Header): title, status badge, priority badge, photo-required chip
- Section 2 (Details): description, estimated hours/cost, materials needed bullet list
- Section 3 (Notes): inline TextField + submit button, live list of TaskNoteItem
- Section 4 (Photos): `Add Photo` button (camera/gallery sheet), `TaskPhotoGrid`, max 10 enforced
- Section 5 (Attachments): PDF picker via FilePicker, list with `url_launcher` system viewer, max 5 enforced
- Bottom bar: `Add Photo` OutlinedButton + `Mark Done`/`Mark Incomplete` ElevatedButton (48px min)
- Photo gate: when `task.photoRequired && photoCount == 0` → Mark Done disabled, text "Add photo first"
- `_taskByIdProvider` — inline family StreamProvider using `dao.watchTaskById(taskId)`
- `url_launcher` added to pubspec.yaml for PDF file launch

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Used `.value` instead of `.valueOrNull` for Riverpod 3**
- **Found during:** Task 1 verification
- **Issue:** `AsyncValue.valueOrNull` doesn't exist in Riverpod 3; the correct API is `.value` which returns `T?`
- **Fix:** Changed `photoCountAsync.valueOrNull ?? 0` → `photoCountAsync.value ?? 0` in TaskChecklistCard and TaskDetailScreen
- **Files modified:** task_checklist_card.dart, task_detail_screen.dart

**2. [Rule 2 - Missing functionality] Added `watchTaskById` to TaskDao**
- **Found during:** Task 2 implementation
- **Issue:** TaskDetailScreen needs a reactive stream for a single task by ID; no such method existed in TaskDao
- **Fix:** Added `watchTaskById(String id)` using `watchSingleOrNull()` to TaskDao
- **Files modified:** mobile/lib/features/projects/data/task_dao.dart

**3. [Rule 2 - Missing functionality] Added `watchAllScopesByCompany` to TradeScopeDao**
- **Found during:** Task 1 implementation
- **Issue:** MyTasksScreen needs scope names for group headers, but only has scopeIds from tasks; no company-wide scope stream existed
- **Fix:** Added `watchAllScopesByCompany(String companyId)` to TradeScopeDao; added `scopeNameMapProvider` to project_providers.dart
- **Files modified:** mobile/lib/features/projects/data/trade_scope_dao.dart, project_providers.dart

**4. [Rule 2 - Missing functionality] Added TaskPhotoViewerScreen**
- **Found during:** Task 2 implementation of TaskPhotoGrid
- **Issue:** TaskPhotoGrid needs to navigate to a full-screen viewer; no task-specific viewer existed
- **Fix:** Created TaskPhotoViewerScreen with PageView, InteractiveViewer, and Annotate action; registered route in app_router.dart
- **Files modified:** task_photo_viewer_screen.dart (new), app_router.dart, route_names.dart

## Self-Check: PASSED

All created files verified present. Both task commits verified in git log.

| Check | Result |
|-------|--------|
| my_tasks_screen.dart | FOUND |
| task_detail_screen.dart | FOUND |
| task_checklist_card.dart | FOUND |
| task_scope_group_header.dart | FOUND |
| task_note_item.dart | FOUND |
| task_photo_grid.dart | FOUND |
| Task 1 commit 999c5cf | FOUND |
| Task 2 commit b23e39d | FOUND |
